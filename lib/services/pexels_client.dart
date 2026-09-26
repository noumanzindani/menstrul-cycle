// lib/services/pexels_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'reply_image.dart';

/// Pexels API key, compiled in: `--dart-define-from-file=.env` with
/// `LUNA_PEXELS_KEY=…` in the gitignored `.env`. Empty (the default, and every
/// test and CI run) turns reply images off. Like the Gemini key it is
/// recoverable from the APK.
const String kPexelsApiKey = String.fromEnvironment('LUNA_PEXELS_KEY');

typedef PexelsGet = Future<({int status, String body})> Function(
    Uri uri, Map<String, String> headers);

/// Finds one stock photo for an assistant reply. The SECOND and last file in
/// `lib/` allowed to make an outbound HTTP request (see
/// `media_guardrails_test.dart`); everything above it is tested with a fake
/// [PexelsGet]. Never throws: a missing photo must never break a reply.
class PexelsClient {
  PexelsClient({
    String? apiKey,
    PexelsGet? get,
    Duration timeout = const Duration(seconds: 5),
  })  : _apiKey = apiKey ?? kPexelsApiKey,
        _get = get ?? _httpGet,
        _timeout = timeout;

  final String _apiKey;
  final PexelsGet _get;
  final Duration _timeout;

  bool get available => _apiKey.isNotEmpty;

  Future<ReplyImage?> searchTop(String query) async {
    if (!available || query.trim().isEmpty) return null;
    final uri = Uri.https(
        'api.pexels.com', '/v1/search', {'query': query, 'per_page': '1'});
    try {
      final r =
          await _get(uri, {'Authorization': _apiKey}).timeout(_timeout);
      if (r.status != 200) return null;
      return _parseTop(query, r.body);
    } catch (_) {
      return null;
    }
  }
}

ReplyImage? _parseTop(String query, String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['photos'] is! List) return null;
  final photos = decoded['photos'] as List;
  if (photos.isEmpty || photos.first is! Map) return null;
  final p = photos.first as Map;
  final src = p['src'];
  return ReplyImage.fromJson({
    'q': query,
    'id': p['id'],
    'src': src is Map ? src['medium'] : null,
    'by': p['photographer'],
    'byUrl': p['photographer_url'],
    'page': p['url'],
  });
}

Future<({int status, String body})> _httpGet(
    Uri uri, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return (status: response.statusCode, body: body);
  } finally {
    client.close();
  }
}
