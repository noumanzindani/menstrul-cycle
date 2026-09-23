import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'media_analysis.dart';

/// The API key, compiled in at build time.
///
/// ```
/// flutter run --dart-define=LUNA_GEMINI_KEY=…
/// flutter build apk --release --dart-define=LUNA_GEMINI_KEY=…
/// ```
///
/// Empty is the default and it is a working state, not a broken one: with no
/// key, the assistant reports itself unavailable (`MediaWiring` in
/// `media_route.dart`): Describe is hidden entirely — the same "hidden, not
/// disabled" rule the media entry point itself follows — and the Assistant
/// shows a neutral unavailable state. That is what keeps the feature absent from any build that was not
/// deliberately given a key, including every CI and test run.
///
/// **This does not keep the key secret from a user of the app.** `--dart-define`
/// values are compiled into the Dart snapshot as plain strings and are
/// recoverable with `strings` on the shipped `.so`. It keeps the key out of
/// **git**, which is a different and smaller promise. A key shipped this way is
/// a billable endpoint anyone who unpacks the APK can drain, and Google's own
/// per-app key restrictions do not help: they are enforced through
/// `X-Android-Package`/`X-Android-Cert` headers that a plain `dart:io` request
/// cannot produce without a platform channel. Moving this behind a Cloud
/// Function — where the key stays server-side and the per-user cap can actually
/// be enforced — is a release blocker tracked in `README.md`.
const String kGeminiApiKey = String.fromEnvironment('LUNA_GEMINI_KEY');

/// Whether this build can analyse at all.
bool get analysisAvailable => kGeminiApiKey.isNotEmpty;

/// Asking the model. **This is the only file in `lib/` that makes an
/// outbound HTTP request** — a structural test enforces it.
///
/// The seam exists for the same reason `MediaBlobStore` does, plus a sharper
/// one. `flutter_test` installs a global `HttpOverrides` (see
/// `flutter_test/lib/src/_binding_io.dart`) whose mock response hardcodes
/// `int get statusCode => 400`. A real `HttpClient` call inside a widget test
/// therefore does not throw, does not hang and does not reach the network — it
/// returns a 400 and the code under test takes its error path. A test written
/// against that passes while proving nothing. Everything above this interface is
/// driven in tests by a fake.
abstract class MediaAnalyzer {
  /// Sends the conversation so far plus [next], and returns the model's answer.
  ///
  /// [history] is the conversation before [next], oldest first; empty for an
  /// opening message. [images] holds the prepared bytes for every photo any
  /// sent turn attaches, keyed by media id — a photo it does not hold is sent
  /// as the deleted-photo placeholder. [healthContext], when supplied, rides
  /// the first user turn. See `buildAnalysisRequest` in `media_analysis.dart`
  /// for exactly where each part goes and why. Throws [AnalysisException] for
  /// anything the user needs told about.
  Future<AnalysisResult> analyze({
    List<AnalysisTurn> history = const [],
    required AnalysisTurn next,
    Map<String, InlineImage> images = const {},
    String? healthContext,
  });
}

/// The production implementation, against Google's Generative Language API.
class GeminiMediaAnalyzer implements MediaAnalyzer {
  GeminiMediaAnalyzer({String? apiKey, HttpClient? client})
      : _apiKey = apiKey ?? kGeminiApiKey,
        _client = client ?? HttpClient();

  final String _apiKey;
  final HttpClient _client;

  /// End-to-end budget for one call.
  ///
  /// Measured at 2–5s on a live connection for a downscaled phone photo. Thirty
  /// seconds rides out a slow uplink and still fails while the user is plausibly
  /// still looking at the screen. Deliberately NOT the SDK-style multi-minute
  /// default: the user is holding this screen open waiting for it, exactly as
  /// with uploads, and `FirebaseMediaBlobStore` bounds those for the same reason.
  static const Duration _timeout = Duration(seconds: 30);

  /// Cap on the response we will buffer. An answer is ~600 tokens; anything
  /// approaching a megabyte is not an answer.
  static const int _maxResponseBytes = 1 * 1024 * 1024;

  @override
  Future<AnalysisResult> analyze({
    List<AnalysisTurn> history = const [],
    required AnalysisTurn next,
    Map<String, InlineImage> images = const {},
    String? healthContext,
  }) async {
    if (_apiKey.isEmpty) {
      throw const AnalysisException(
        'The assistant is not available in this build.',
      );
    }
    // The service refuses an oversized conversation before it counts it; this
    // is the backstop for a caller that skipped the service.
    if (!withinInlineBudget(history: history, next: next, images: images)) {
      throw const AnalysisException('That photo is too big to describe.');
    }

    final body = utf8.encode(
      jsonEncode(
        buildAnalysisRequest(
          history: history,
          next: next,
          images: images,
          healthContext: healthContext,
        ),
      ),
    );

    // The key rides a header, not the query string. Functionally the API accepts
    // `?key=`, but a URL is the string that ends up in proxy logs, crash
    // reports and any future retry/redirect logging — and this one is a bearer
    // credential. Nothing in this file ever writes _apiKey to a log.
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$kAnalysisModel:generateContent',
    );

    HttpClientRequest request;
    try {
      request = await _client.postUrl(uri).timeout(_timeout);
    } on Exception {
      throw const AnalysisException("Couldn't reach the service.");
    }
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set('x-goog-api-key', _apiKey);
    request.add(body);

    final HttpClientResponse response;
    final String text;
    try {
      response = await request.close().timeout(_timeout);
      text = await _readBounded(response).timeout(_timeout);
    } on Exception {
      throw const AnalysisException("Couldn't reach the service.");
    }

    if (response.statusCode == 429) {
      throw const AnalysisException('Too many requests. Try again later.');
    }
    if (response.statusCode >= 500) {
      throw const AnalysisException(
        'The service is having trouble. Try again later.',
      );
    }

    // Parsed even on a 4xx: the body carries the `error` envelope with the real
    // reason, and parseAnalysisResponse turns that into copy.
    final decoded = decodeAnalysisBody(text);
    // Debug builds only, and the count only: the request and the reply both
    // carry health data, and neither is ever written to a log.
    if (kDebugMode) {
      final tokens = promptTokenCountOf(decoded);
      if (tokens != null) debugPrint('[analysis] promptTokenCount=$tokens');
    }
    return parseAnalysisResponse(decoded);
  }

  Future<String> _readBounded(HttpClientResponse response) async {
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
      if (chunks.length > _maxResponseBytes) {
        throw const AnalysisException('The service returned too much data.');
      }
    }
    return utf8.decode(chunks, allowMalformed: true);
  }
}

/// Used when no key was compiled in, or there is no Firebase app.
///
/// Mirrors `UnavailableMediaBlobStore`. Throwing is correct rather than
/// defensive: the affordance is hidden when analysis is unavailable, so reaching
/// this means an entry point escaped its gate, and a loud failure is how that
/// gets found.
class UnavailableMediaAnalyzer implements MediaAnalyzer {
  const UnavailableMediaAnalyzer();

  @override
  Future<AnalysisResult> analyze({
    List<AnalysisTurn> history = const [],
    required AnalysisTurn next,
    Map<String, InlineImage> images = const {},
    String? healthContext,
  }) async =>
      throw StateError('Photo analysis is unavailable in this build.');
}
