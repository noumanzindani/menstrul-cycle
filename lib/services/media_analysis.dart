/// Asking a hosted model to describe a photo the user uploaded, and the rules
/// that make that answerable without becoming a medical opinion.
///
/// Pure: no I/O, no Flutter imports, no plugin calls — the request shape, the
/// response parsing, the refusal copy and the daily cap arithmetic are all
/// reachable from `flutter test`. The network call itself lives behind
/// [MediaAnalyzer] in `media_analyzer.dart`, for a reason that is not stylistic:
/// `flutter_test` installs a global `HttpOverrides` whose mock response
/// hardcodes `statusCode => 400`, so a real `HttpClient` call inside a test does
/// not fail loudly — it quietly returns a 400 and the test passes for the wrong
/// reason.
///
/// ## The photo leaves the device, and leaves LunaTrack
///
/// Analysis sends the image bytes to Google's Generative Language API. That is
/// a third party, outside both the device and the user's own Firebase project,
/// and it is the whole reason this feature is opt-in per account rather than
/// simply "on when signed in". Copy that describes it must say where the bytes
/// go — see `analysis_consent_sheet.dart` and `PRIVACY_POLICY.md`.
///
/// ## Nothing derived is stored
///
/// A result is held for the life of the viewer and discarded. Persisting model
/// prose about a body photo would create a second, softer copy of the most
/// sensitive thing in the app — one that would then need its own erasure path
/// in `deleteAllData`, the purge job, `.lunabak` exclusion and the doctor PDF
/// exclusion. Re-asking costs one call; storing costs all of that forever.
library;

import 'dart:convert';

/// The model. Flash tier because this is one round trip a user waits on with
/// the screen open — a pro model roughly triples the latency for a description
/// of a photograph, which is not a task that rewards deliberation.
const String kAnalysisModel = 'gemini-3.5-flash';

/// Reasoning budget, and it must stay zero.
///
/// NOT a tuning knob. On Gemini 3.x, reasoning tokens are drawn from the SAME
/// allowance as the reply, so a request with `maxOutputTokens: 400` and thinking
/// left on spent ~384 tokens thinking and returned a sentence cut mid-word at 16
/// tokens with `finishReason: MAX_TOKENS`. Measured 2026-08-12: same prompt,
/// same image, thinking off → complete answer in 2.3s instead of 5.0s. There is
/// nothing to reason about in "describe this photo", so thinking here buys
/// latency and truncation and nothing else.
const int kAnalysisThinkingBudget = 0;

/// Ceiling on the reply. Roughly 400 words — long enough for a description,
/// short enough that a runaway answer cannot bill unbounded.
const int kAnalysisMaxOutputTokens = 600;

/// Low, because the task is observation. Higher values invent detail, and
/// invented detail about a body photo is the failure mode that matters here.
const double kAnalysisTemperature = 0.2;

/// Largest image this feature will send, in bytes.
///
/// Well under the API's own inline limit. The binding reason is different: the
/// bytes are base64'd into a JSON body held in memory, which inflates them by a
/// third, and the media caps already downscale a picked photo to 2048px/q85
/// (~300–800 KB). Anything arriving here above 8 MB came from a path that
/// skipped that, and is refused rather than sent.
const int kMaxAnalysisBytes = 8 * 1024 * 1024;

/// How many photos may be analysed per day, per device.
///
/// Every analysis bills, the app is free and ad-supported, and there is no
/// rate limiter anywhere else in `lib/`. This is a cost ceiling, not a product
/// decision dressed up as one — which is why the copy for [AnalysisBlock.dailyCap]
/// names the number and says it resets, rather than implying an upsell.
const int kMaxAnalysesPerDay = 20;

/// The default question, used when the user just taps and does not type one.
const String kDefaultAnalysisQuestion =
    'What do you see in this photo? Describe it plainly.';

/// How many questions the user may ask about one photo before the conversation
/// is closed off.
///
/// Two costs grow with the turn count and only one of them is obvious. The
/// obvious one: every turn is a billed call. The other: `generateContent` is
/// stateless, so each turn resends the WHOLE transcript — including the image —
/// as input. Turn ten pays for turns one through nine again. Ten is where a
/// conversation about a single photograph has run its course anyway.
const int kMaxChatTurns = 10;

/// Longest question the user may type. Bounds the request and keeps the reply
/// anchored to the image rather than to a wall of instructions.
const int kMaxQuestionLength = 200;

/// The instruction that makes this feature shippable in a health app.
///
/// **This string is a safety control, not copy.** It is what turns "an LLM
/// looking at a body photo" into something that will not name a condition. It
/// was tested against a deliberately bad question ("Does this look like an
/// infection? Should I take antibiotics?") and produced a refusal plus a
/// description of what was visibly present — which is the required behaviour.
/// `test/media_analysis_test.dart` asserts the clauses below are present; if you
/// edit this, re-run that test and re-test the refusal on a device.
///
/// LunaTrack authoring a clinical reading of a photograph is the same class of
/// harm as a synthesized fertility percentage or a BMI label: it is the app
/// putting a judgement on the user's body. The model is allowed to describe.
/// It is not allowed to interpret.
/// The plain-prose clause is not cosmetic either. Device-found 2026-08-12: the
/// model answered a real photo with Markdown, and the sheet renders with
/// `SelectableText`, which has no Markdown support — so the user was shown
/// literal `*   **On the left:**` down the screen. The alternatives were adding
/// a Markdown package (a new dependency, needing approval) or asking for prose.
/// Prose is also the right register for one short description read aloud in a
/// sheet, so the cheap fix and the correct one agree.
const String kAnalysisSystemInstruction =
    'You describe a photo the user saved in their period-tracking app. '
    'Describe only what is visibly present, plainly and briefly. '
    'Reply in plain sentences only: no Markdown, no asterisks, no bullet '
    'points, no headings, no bold. '
    'You are NOT a clinician: never diagnose, never name a condition, never '
    'estimate severity, never advise treatment. If asked to do any of those, '
    'say you cannot and suggest they speak to a healthcare professional.';

/// The line shown under every description, without exception.
///
/// Always rendered, never conditional on what came back: a caveat that appears
/// only sometimes teaches the user that its absence means the answer is
/// trustworthy. It names the answer as automatic and disclaims medical meaning,
/// which is the same shape as the non-contraception disclaimer that sits on
/// every fertility surface.
const String kAnalysisCaveat =
    'This is an automatic description of the picture. LunaTrack does not '
    'interpret it, and it is not a medical opinion.';

/// Why an analysis was refused before any request was made.
///
/// Ordered narrow-to-broad in [messageForAnalysisBlock] and checked in that same
/// order by `MediaAnalysisService`, so the most specific true reason is the one
/// the user is shown.
enum AnalysisBlock {
  /// No signed-in account.
  notSignedIn,

  /// An account deletion is sweeping right now (`SyncTrigger.suspend`).
  writesBlocked,

  /// The user chose "keep my data on this device only".
  syncDeclined,

  /// This device is not syncing for this account.
  syncOff,

  /// The account has not opted in to analysis, or a DIFFERENT account did.
  notConsented,

  /// Videos are not analysed. Only images are sent.
  notAnImage,

  /// Over [kMaxAnalysisBytes].
  tooLarge,

  /// [kMaxAnalysesPerDay] reached for today.
  dailyCap,

  /// [kMaxChatTurns] reached for THIS photo's conversation.
  turnCap,

  /// No API key was compiled into this build.
  unavailable,
}

/// Who said a turn. Mirrors the API's own `role` values, which are exactly
/// these two — there is no `system` role here; the system instruction is a
/// separate top-level field.
enum AnalysisRole { user, model }

/// One message in a conversation about one photo.
///
/// Text only, by design. The image is not carried per-turn: it is attached once
/// to the first user turn when the request is built, because the whole array is
/// resent on every call anyway.
class AnalysisTurn {
  const AnalysisTurn.user(this.text) : role = AnalysisRole.user;
  const AnalysisTurn.model(this.text) : role = AnalysisRole.model;

  final AnalysisRole role;
  final String text;

  @override
  String toString() => 'AnalysisTurn(${role.name}, $text)';
}

/// User-facing copy for each refusal.
///
/// GUARDRAIL: none of these may claim the photo is safe, private, secure,
/// encrypted or protected — the bucket is unencrypted, the bytes go to a third
/// party, and copy must describe what the code does today.
/// `test/media_guardrails_test.dart` scans for those words.
String messageForAnalysisBlock(AnalysisBlock block) {
  switch (block) {
    case AnalysisBlock.notSignedIn:
      return 'Sign in to use photo descriptions.';
    case AnalysisBlock.writesBlocked:
      return 'Not right now. Try again in a moment.';
    case AnalysisBlock.syncDeclined:
      return 'You chose to keep your data on this device. Describing a photo '
          'sends it to Google, so it is turned off.';
    case AnalysisBlock.syncOff:
      return 'Cloud sync is off. Turn it on in Settings to use photo '
          'descriptions.';
    case AnalysisBlock.notConsented:
      return 'Turn on photo descriptions in Settings first.';
    case AnalysisBlock.notAnImage:
      return 'Only photos can be described, not videos.';
    case AnalysisBlock.tooLarge:
      return "That photo is too big to describe.";
    case AnalysisBlock.dailyCap:
      // "messages", not "photos": since every turn of a conversation bills, the
      // counter counts turns. Saying "photos" would have been true when this
      // was one description per tap and is not true now.
      return 'You have sent $kMaxAnalysesPerDay messages today. This resets '
          'tomorrow.';
    case AnalysisBlock.turnCap:
      return "That's $kMaxChatTurns questions about this photo. Close this and "
          'open the photo again to start over.';
    case AnalysisBlock.unavailable:
      return 'Photo descriptions are not available in this build.';
  }
}

/// One label from a classifier backend, kept so a labels-only implementation
/// (Cloud Vision) can populate [AnalysisResult] without changing the UI.
class AnalysisLabel {
  const AnalysisLabel(this.description, this.score);

  final String description;
  final double score;

  @override
  String toString() => 'AnalysisLabel($description, $score)';
}

/// What one analysis produced.
///
/// Carries BOTH shapes on purpose. A prose model fills [prose]; a classifier
/// fills [labels]. The result sheet renders whichever is non-empty, so swapping
/// the backend behind [MediaAnalyzer] needs no UI or persistence change.
class AnalysisResult {
  const AnalysisResult({this.prose, this.labels = const []});

  /// The model's answer, when the backend produces prose.
  final String? prose;

  /// Ranked labels, when the backend produces classification instead.
  final List<AnalysisLabel> labels;

  bool get isEmpty => (prose == null || prose!.trim().isEmpty) && labels.isEmpty;
}

/// Raised when the backend answered, but not with an answer.
///
/// Separate from a transport failure because the two need different copy: a
/// refusal by the safety filter is not something "try again" fixes.
class AnalysisException implements Exception {
  const AnalysisException(this.message, {this.isSafetyRefusal = false});

  final String message;
  final bool isSafetyRefusal;

  @override
  String toString() => 'AnalysisException($message)';
}

/// The request body for one image, the conversation so far, and the new
/// [question].
///
/// Pure so the shape is testable without a network. `inline_data` (snake_case)
/// is the REST spelling — the camelCase `inlineData` of the client SDKs is
/// silently ignored here and yields a text-only request, which is a failure
/// that looks like a bad answer rather than an error.
///
/// ## Multi-turn
///
/// `generateContent` holds no session. A conversation is the entire transcript
/// resent every call, as alternating `user`/`model` entries, with the model's
/// own past replies echoed back to it — nothing is remembered server-side.
///
/// The image is attached to the FIRST user turn and only that one. The array is
/// resent whole each time, so the photo is in context for every answer; adding
/// it to each turn would bill several copies of the same picture per request and
/// leave the model reconciling duplicates.
Map<String, Object?> buildAnalysisRequest({
  required String base64Image,
  required String mimeType,
  required String question,
  List<AnalysisTurn> history = const [],
}) {
  final turns = <AnalysisTurn>[...history, AnalysisTurn.user(question)];
  final contents = <Object?>[];
  var imageAttached = false;
  for (final turn in turns) {
    final parts = <Object?>[];
    if (!imageAttached && turn.role == AnalysisRole.user) {
      parts.add(<String, Object?>{
        'inline_data': <String, Object?>{
          'mime_type': mimeType,
          'data': base64Image,
        },
      });
      imageAttached = true;
    }
    parts.add(<String, Object?>{'text': turn.text});
    contents.add(<String, Object?>{
      'role': turn.role.name,
      'parts': parts,
    });
  }

  return <String, Object?>{
    'systemInstruction': <String, Object?>{
      'parts': <Object?>[
        <String, Object?>{'text': kAnalysisSystemInstruction},
      ],
    },
    'contents': contents,
    'generationConfig': <String, Object?>{
      'maxOutputTokens': kAnalysisMaxOutputTokens,
      'temperature': kAnalysisTemperature,
      'thinkingConfig': <String, Object?>{
        'thinkingBudget': kAnalysisThinkingBudget,
      },
    },
  };
}

/// Parses a `generateContent` response into a result, or throws.
///
/// Handles every shape the API actually returns rather than the happy one:
/// an `error` envelope (HTTP 200 is not a promise of success), a prompt blocked
/// before generation, a candidate stopped by the safety filter, and a candidate
/// truncated by the token ceiling. The truncation case is reported as a failure
/// rather than shown, because a description of a body photo cut off mid-sentence
/// is worse than no description.
AnalysisResult parseAnalysisResponse(Map<String, Object?> json) {
  final error = json['error'];
  if (error is Map) {
    final message = error['message'];
    throw AnalysisException(
      message is String ? message : 'The service returned an error.',
    );
  }

  // Blocked before anything was generated.
  final feedback = json['promptFeedback'];
  if (feedback is Map && feedback['blockReason'] != null) {
    throw const AnalysisException(
      'That photo could not be described.',
      isSafetyRefusal: true,
    );
  }

  final candidates = json['candidates'];
  if (candidates is! List || candidates.isEmpty) {
    throw const AnalysisException('The service returned no answer.');
  }
  final candidate = candidates.first;
  if (candidate is! Map) {
    throw const AnalysisException('The service returned no answer.');
  }

  final finish = candidate['finishReason'];
  if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') {
    throw const AnalysisException(
      'That photo could not be described.',
      isSafetyRefusal: true,
    );
  }
  if (finish == 'MAX_TOKENS') {
    // See kAnalysisThinkingBudget: this is what a non-zero thinking budget
    // looks like from the outside, and it is why that constant is pinned.
    throw const AnalysisException('The answer was cut short. Try again.');
  }

  final content = candidate['content'];
  final parts = content is Map ? content['parts'] : null;
  if (parts is! List) {
    throw const AnalysisException('The service returned no answer.');
  }
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is Map && part['text'] is String) {
      buffer.write(part['text'] as String);
    }
  }
  final text = buffer.toString().trim();
  if (text.isEmpty) {
    throw const AnalysisException('The service returned no answer.');
  }
  return AnalysisResult(prose: text);
}

/// Decodes a raw response body, tolerating a non-JSON error page.
///
/// A gateway or a captive portal answers with HTML, and `jsonDecode` throws a
/// `FormatException` whose message quotes the page — which would then be shown
/// to the user. This turns that into copy.
Map<String, Object?> decodeAnalysisBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, Object?>) return decoded;
    return <String, Object?>{};
  } on FormatException {
    throw const AnalysisException('The service returned an unreadable reply.');
  }
}

/// Trims and bounds a user-typed question, falling back to the default.
String normalizeQuestion(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return kDefaultAnalysisQuestion;
  if (trimmed.length <= kMaxQuestionLength) return trimmed;
  return trimmed.substring(0, kMaxQuestionLength);
}

/// The day key the daily cap counts against, in the DEVICE's local time.
///
/// Local rather than UTC because the cap is explained to the user as "today",
/// and a UTC day would reset mid-afternoon for some of them. Stored as a plain
/// `yyyy-mm-dd` string so a stale key from any earlier day compares unequal
/// without date arithmetic.
String analysisDayKey(DateTime now) {
  final local = now.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}

/// The count that applies to [now], given what was stored.
///
/// A stored key from a different day reads as zero rather than being cleared,
/// so the counter needs no midnight timer and no migration when it rolls over.
int analysisCountForDay({
  required String? storedDay,
  required int? storedCount,
  required DateTime now,
}) {
  if (storedDay == null || storedDay != analysisDayKey(now)) return 0;
  return storedCount ?? 0;
}
