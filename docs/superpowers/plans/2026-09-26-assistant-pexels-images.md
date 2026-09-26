# Assistant Reply Images (Pexels) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every answered AI Assistant reply shows one relevant Pexels stock photo with a photographer credit. The photo survives save, sync and reopen.

**Architecture:**
- The model ends each reply with `[image: <topic>]`.
- `ReplyImageResolver` (owned by `LiveAssistantBackend`) swaps that tag for a resolved marker `[[pexels {json}]]`, using a Pexels search made by the new `pexels_client.dart` seam.
- The marker is stored inside the ordinary `messageText`, so there is no schema change and no rules change.
- The chat view splits prose from marker and renders the photo.
- Model replay reduces markers back to `[image: q]`.

**Tech Stack:** Flutter / Dart, `dart:io` `HttpClient` (no new dependency), drift, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-09-26-assistant-pexels-images-design.md`

## Global Constraints

**Key and dependencies**
- `LUNA_PEXELS_KEY` via `String.fromEnvironment`, read ONLY in `lib/services/pexels_client.dart`. An empty key means the feature is off.
- No new package dependency. The credit is plain text "Photo by <name> on Pexels". A tappable link needs `url_launcher`, which is pending the owner's approval, so it is out of this plan.

**Network**
- Pexels endpoint: `GET https://api.pexels.com/v1/search?query=<q>&per_page=1`, header `Authorization: <key>`.
- Timeout: 5 seconds.
- `pexels_client.dart` becomes the second and last file allowed to use `HttpClient`.

**Queries**
- The search query is the model's `[image: …]` topic. With no tag, it is the user's question with whitespace collapsed, `[` and `]` removed, and cut to 60 characters.
- No content filter (owner decision).

**What the model sees**
- The model is never sent URLs or photographer names.
- Photos are never sent to Gemini.

**Consent and copy**
- Consent becomes **8**. The sheet must say: "A short topic phrase from each reply is sent to Pexels to find a photo."
- Banned words in consent copy (existing test): safe, private, secure, encrypted, protected.
- All Dart tests use `AppDatabase.forTesting(NativeDatabase.memory())` and injected fakes. There are no real network calls; `flutter_test` answers them with 400.

## Review Focus

1. **The model puts `[image: …]` mid-reply, or twice.** Only a tag on the LAST non-empty line counts. Earlier ones stay as prose. Tested in Task 1.
2. **A stored marker from a newer or corrupt client** (bad JSON, missing fields, a non-https `src`). The prose still shows, with no image and no crash. Tested in Tasks 1 and 2.
3. **The reply is only the tag, so the prose is empty after stripping.** The resolver keeps the image, and the chat shows the image alone. It must not fail as "No answer came back" if the model DID answer. Tested in Task 3.
4. **The conversations list subtitle** must never show `[[pexels …` or `[image:`. Tested in Task 4.
5. **The same answer served twice** (service memo hit, or persist and then send) must trigger exactly one Pexels search. Tested in Task 3.

---

## File map

| File | Status | Responsibility |
|---|---|---|
| `lib/services/reply_image.dart` | create | Pure: `ReplyImage`, marker encode/split, `forModel`, `fallbackTopic` |
| `lib/services/pexels_client.dart` | create | Seam: key, HTTP GET, parse the top photo |
| `lib/screens/assistant/reply_image_resolver.dart` | create | Tag → marker, memoised |
| `lib/screens/assistant/live_assistant_backend.dart` | modify | Resolve on persist and send; `forModel` on resume; clean subtitle |
| `lib/screens/media/media_route.dart` | modify | Construct the resolver with the real client |
| `lib/services/media_analysis.dart` | modify | Instruction clause; consent 8 |
| `lib/screens/assistant/analysis_chat_view.dart` | modify | Render prose, photo and credit |
| `lib/screens/media/analysis_consent_sheet.dart` | modify | Pexels disclosure |
| `PRIVACY_POLICY.md`, `CLAUDE.md` | modify | Disclosure and docs |
| `test/reply_image_test.dart`, `test/pexels_client_test.dart`, `test/reply_image_resolver_test.dart` | create | Unit tests |
| `test/live_assistant_backend_test.dart`, `test/analysis_chat_view_test.dart`, `test/media_analysis_test.dart`, `test/analysis_consent_sheet_test.dart`, `test/media_guardrails_test.dart` | modify | Wiring, UI and guardrails |

---

### Task 1: Reply-image marker (pure)

**Files:**
- Create: `lib/services/reply_image.dart`
- Test: `test/reply_image_test.dart`

**Interfaces:**
- Produces:
  - `class ReplyImage { query, id (int), src, photographer, photographerUrl, pageUrl; toJson(); static ReplyImage? fromJson(Object?) }`
  - `typedef SplitReply = ({String prose, String? query, ReplyImage? image});`
  - `SplitReply splitReply(String text)`
  - `String attachImage(String prose, ReplyImage image)`
  - `String keepTag(String prose, String query)`
  - `String forModel(String text)`
  - `String? fallbackTopic(String question)`

- [ ] **Step 1: Write the failing test**

```dart
// test/reply_image_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/reply_image.dart';

const _img = ReplyImage(
  query: 'warm tea',
  id: 42,
  src: 'https://images.pexels.com/photos/42/medium.jpg',
  photographer: 'Ana "Bee" [Lee]\nÜ',
  photographerUrl: 'https://www.pexels.com/@ana',
  pageUrl: 'https://www.pexels.com/photo/42/',
);

void main() {
  group('splitReply', () {
    test('plain prose has no image and is returned unchanged', () {
      final s = splitReply('Cramps are common.');
      expect(s.prose, 'Cramps are common.');
      expect(s.query, isNull);
      expect(s.image, isNull);
    });

    test('a final [image: …] line becomes the query', () {
      final s = splitReply('Cramps are common.\n[image:  heat pad  ]\n');
      expect(s.prose, 'Cramps are common.');
      expect(s.query, 'heat pad');
      expect(s.image, isNull);
    });

    test('a tag that is not on the last line stays prose', () {
      const text = 'See [image: x] here.\nMore text.';
      final s = splitReply(text);
      expect(s.prose, text);
      expect(s.query, isNull);
    });

    test('only the last of two tags counts', () {
      final s = splitReply('A\n[image: one]\n[image: two]');
      expect(s.prose, 'A\n[image: one]');
      expect(s.query, 'two');
    });

    test('an empty tag is no query', () {
      final s = splitReply('A\n[image:   ]');
      expect(s.prose, 'A');
      expect(s.query, isNull);
    });

    test('a resolved marker round-trips any characters', () {
      final s = splitReply(attachImage('Tea helps some people.', _img));
      expect(s.prose, 'Tea helps some people.');
      expect(s.image, _img);
      expect(s.query, 'warm tea');
    });

    test('a corrupt marker keeps the prose and drops the image', () {
      final s = splitReply('Hi.\n[[pexels {not json}]]');
      expect(s.prose, 'Hi.');
      expect(s.image, isNull);
      expect(s.query, isNull);
    });

    test('a marker with a non-https src is refused', () {
      final bad = attachImage('Hi.', const ReplyImage(
        query: 'q', id: 1, src: 'http://evil/x.jpg', photographer: 'a',
        photographerUrl: 'https://p/a', pageUrl: 'https://p/1'));
      expect(splitReply(bad).image, isNull);
      expect(splitReply(bad).prose, 'Hi.');
    });

    test('a reply that is only a tag has empty prose', () {
      final s = splitReply('[image: sleep]');
      expect(s.prose, '');
      expect(s.query, 'sleep');
    });
  });

  group('forModel', () {
    test('reduces a marker to the tag, so no URL or name reaches the model', () {
      final out = forModel(attachImage('Tea helps.', _img));
      expect(out, 'Tea helps.\n[image: warm tea]');
      expect(out, isNot(contains('pexels.com')));
      expect(out, isNot(contains('Ana')));
    });

    test('leaves a tag and plain prose as they are', () {
      expect(forModel('A\n[image: b]'), 'A\n[image: b]');
      expect(forModel('Just prose.'), 'Just prose.');
    });
  });

  group('fallbackTopic', () {
    test('collapses whitespace, strips brackets, caps at 60', () {
      expect(fallbackTopic('  why  [am] I\ntired? '), 'why am I tired?');
      expect(fallbackTopic('x' * 80)!.length, 60);
    });

    test('blank is null', () => expect(fallbackTopic('  []  '), isNull));
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run `flutter test test/reply_image_test.dart`. Expected: FAIL, with "Target of URI doesn't exist … reply_image.dart".

- [ ] **Step 3: Implement**

```dart
// lib/services/reply_image.dart
import 'dart:convert';

/// One Pexels photo attached to an assistant reply, stored INSIDE the reply's
/// `messageText` as a final marker line so it syncs with no schema or rules
/// change. See docs/superpowers/specs/2026-09-26-assistant-pexels-images-design.md.
class ReplyImage {
  const ReplyImage({
    required this.query,
    required this.id,
    required this.src,
    required this.photographer,
    required this.photographerUrl,
    required this.pageUrl,
  });

  final String query;
  final int id;
  final String src;
  final String photographer;
  final String photographerUrl;
  final String pageUrl;

  Map<String, Object> toJson() => {
        'q': query,
        'id': id,
        'src': src,
        'by': photographer,
        'byUrl': photographerUrl,
        'page': pageUrl,
      };

  /// Null for anything malformed: the marker syncs, so another client may
  /// have written it. Only an https image URL is ever rendered.
  static ReplyImage? fromJson(Object? json) {
    if (json is! Map) return null;
    final q = json['q'], id = json['id'], src = json['src'];
    final by = json['by'], byUrl = json['byUrl'], page = json['page'];
    if (q is! String || id is! int || src is! String || by is! String ||
        byUrl is! String || page is! String) {
      return null;
    }
    if (!src.startsWith('https://')) return null;
    return ReplyImage(
      query: q,
      id: id,
      src: src,
      photographer: by,
      photographerUrl: byUrl,
      pageUrl: page,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReplyImage &&
      other.query == query &&
      other.id == id &&
      other.src == src &&
      other.photographer == photographer &&
      other.photographerUrl == photographerUrl &&
      other.pageUrl == pageUrl;

  @override
  int get hashCode =>
      Object.hash(query, id, src, photographer, photographerUrl, pageUrl);
}

typedef SplitReply = ({String prose, String? query, ReplyImage? image});

final _markerLine = RegExp(r'(?:^|\n)[ \t]*\[\[pexels (.*)\]\][ \t]*\s*$');
final _tagLine = RegExp(r'(?:^|\n)[ \t]*\[image:([^\]\n]*)\][ \t]*\s*$');

/// Splits a stored or live reply into its prose and its image line. Only a
/// marker or tag on the LAST non-empty line counts; anything earlier is prose.
SplitReply splitReply(String text) {
  final marker = _markerLine.firstMatch(text);
  if (marker != null) {
    final prose = text.substring(0, marker.start).trimRight();
    ReplyImage? image;
    try {
      image = ReplyImage.fromJson(jsonDecode(marker.group(1)!));
    } on FormatException {
      image = null;
    }
    return (prose: prose, query: image?.query, image: image);
  }
  final tag = _tagLine.firstMatch(text);
  if (tag != null) {
    final query = tag.group(1)!.trim();
    return (
      prose: text.substring(0, tag.start).trimRight(),
      query: query.isEmpty ? null : query,
      image: null,
    );
  }
  return (prose: text, query: null, image: null);
}

String attachImage(String prose, ReplyImage image) =>
    '$prose\n[[pexels ${jsonEncode(image.toJson())}]]';

String keepTag(String prose, String query) => '$prose\n[image: $query]';

/// What a resumed conversation sends back to Gemini: a marker becomes the
/// plain tag again, so the model sees its own format and never a URL or a
/// photographer's name.
String forModel(String text) {
  final s = splitReply(text);
  if (s.image == null && s.query == null) return s.prose;
  return s.query == null ? s.prose : keepTag(s.prose, s.query!);
}

/// The search used when the model left the tag out: the user's own question,
/// tidied and capped.
String? fallbackTopic(String question) {
  final t = question
      .replaceAll(RegExp(r'[\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (t.isEmpty) return null;
  return t.length > 60 ? t.substring(0, 60) : t;
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run `flutter test test/reply_image_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/reply_image.dart test/reply_image_test.dart
git commit -m "feat(assistant): reply-image marker format"
```

---

### Task 2: Pexels client seam and guardrails

**Files:**
- Create: `lib/services/pexels_client.dart`
- Test: `test/pexels_client_test.dart`
- Modify: `test/media_guardrails_test.dart:200-230`, the HTTP-caller allowlist and a new key-reader test

**Interfaces:**
- Consumes: `ReplyImage` from Task 1.
- Produces:
  - `const String kPexelsApiKey`
  - `typedef PexelsGet = Future<({int status, String body})> Function(Uri uri, Map<String, String> headers);`
  - `class PexelsClient { PexelsClient({String? apiKey, PexelsGet? get, Duration timeout}); bool get available; Future<ReplyImage?> searchTop(String query); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/pexels_client_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/pexels_client.dart';

String _body(List<Map<String, Object?>> photos) => jsonEncode({'photos': photos});

const _photo = {
  'id': 7,
  'url': 'https://www.pexels.com/photo/7/',
  'photographer': 'Sam',
  'photographer_url': 'https://www.pexels.com/@sam',
  'src': {'medium': 'https://images.pexels.com/photos/7/m.jpg'},
};

void main() {
  late Uri? lastUri;
  late Map<String, String>? lastHeaders;

  PexelsClient client(FutureOr<({int status, String body})> Function() reply,
          {String key = 'k'}) =>
      PexelsClient(
        apiKey: key,
        timeout: const Duration(milliseconds: 50),
        get: (uri, headers) async {
          lastUri = uri;
          lastHeaders = headers;
          return reply();
        },
      );

  setUp(() {
    lastUri = null;
    lastHeaders = null;
  });

  test('returns the top photo and sends the key and query', () async {
    final img = await client(() => (status: 200, body: _body([_photo])))
        .searchTop('heat pad');
    expect(img!.id, 7);
    expect(img.src, 'https://images.pexels.com/photos/7/m.jpg');
    expect(img.photographer, 'Sam');
    expect(img.query, 'heat pad');
    expect(lastUri!.host, 'api.pexels.com');
    expect(lastUri!.queryParameters, {'query': 'heat pad', 'per_page': '1'});
    expect(lastHeaders, {'Authorization': 'k'});
  });

  test('no results is null', () async {
    expect(await client(() => (status: 200, body: _body([]))).searchTop('x'),
        isNull);
  });

  test('429 and other non-200s are null', () async {
    expect(await client(() => (status: 429, body: '')).searchTop('x'), isNull);
    expect(await client(() => (status: 500, body: '')).searchTop('x'), isNull);
  });

  test('malformed JSON or a missing field is null', () async {
    expect(await client(() => (status: 200, body: '{nope')).searchTop('x'),
        isNull);
    expect(
        await client(() => (status: 200, body: _body([{'id': 7}])))
            .searchTop('x'),
        isNull);
  });

  test('a timeout is null, never a throw', () async {
    final slow = client(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      return (status: 200, body: _body([_photo]));
    });
    expect(await slow.searchTop('x'), isNull);
  });

  test('a transport error is null, never a throw', () async {
    expect(await client(() => throw StateError('offline')).searchTop('x'),
        isNull);
  });

  test('no key: unavailable and never calls out', () async {
    final c = client(() => (status: 200, body: _body([_photo])), key: '');
    expect(c.available, isFalse);
    expect(await c.searchTop('x'), isNull);
    expect(lastUri, isNull);
  });

  test('the build default has no key', () => expect(kPexelsApiKey, isEmpty));
}
```

Add to `test/media_guardrails_test.dart`, inside `group('the photo-description seam stays intact', …)`:
- Replace `expect(callers, ['lib/services/media_analyzer.dart']);` with:

```dart
      // Pexels (2026-09-26, owner decision) is the second and last seam. Both
      // are driven by fakes in every test, which is what this rule protects.
      expect(callers, [
        'lib/services/media_analyzer.dart',
        'lib/services/pexels_client.dart',
      ]);
```

- Then add after the `LUNA_GEMINI_KEY` test:

```dart
    test('the Pexels key is read in exactly one place', () {
      final readers = _libSources()
          .where((f) => _code(f.path).contains('LUNA_PEXELS_KEY'))
          .map((f) => f.path)
          .toList();
      expect(readers, ['lib/services/pexels_client.dart']);
    });
```

- [ ] **Step 2: Run to confirm failure**

Run `flutter test test/pexels_client_test.dart test/media_guardrails_test.dart`. Expected: FAIL. The URI is missing, and the guardrail lists differ.

- [ ] **Step 3: Implement**

```dart
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
```

- [ ] **Step 4: Run to confirm it passes**

Run `flutter test test/pexels_client_test.dart test/media_guardrails_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/pexels_client.dart test/pexels_client_test.dart test/media_guardrails_test.dart
git commit -m "feat(assistant): Pexels client seam, second allowed HTTP caller"
```

---

### Task 3: ReplyImageResolver

**Files:**
- Create: `lib/screens/assistant/reply_image_resolver.dart`
- Test: `test/reply_image_resolver_test.dart`

**Interfaces:**
- Consumes: `splitReply`, `attachImage`, `keepTag`, `fallbackTopic`, `ReplyImage` (Task 1).
- Produces: `class ReplyImageResolver { ReplyImageResolver({required Future<ReplyImage?> Function(String) search, required bool enabled}); const-like factory ReplyImageResolver.off(); Future<String> resolve(String reply, {required String fallbackQuery}); }`

- [ ] **Step 1: Write the failing test**

```dart
// test/reply_image_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/assistant/reply_image_resolver.dart';
import 'package:menstrul_track/services/reply_image.dart';

ReplyImage _img(String q) => ReplyImage(
    query: q, id: 1, src: 'https://i/1.jpg', photographer: 'Sam',
    photographerUrl: 'https://p/@sam', pageUrl: 'https://p/1');

void main() {
  late List<String> searches;
  ReplyImage? Function(String) answer = _img;

  ReplyImageResolver resolver({bool enabled = true}) => ReplyImageResolver(
        enabled: enabled,
        search: (q) async {
          searches.add(q);
          return answer(q);
        },
      );

  setUp(() {
    searches = [];
    answer = _img;
  });

  test('the model tag is searched and replaced by a marker', () async {
    final out = await resolver()
        .resolve('Try heat.\n[image: heat pad]', fallbackQuery: 'cramps?');
    expect(searches, ['heat pad']);
    expect(splitReply(out).prose, 'Try heat.');
    expect(splitReply(out).image, _img('heat pad'));
  });

  test('no tag: falls back to the question', () async {
    await resolver().resolve('Try heat.', fallbackQuery: '  why  cramps? ');
    expect(searches, ['why cramps?']);
  });

  test('a failed search keeps the tag and never retries', () async {
    answer = (_) => null;
    final r = resolver();
    final out = await r.resolve('A\n[image: b]', fallbackQuery: 'q');
    expect(out, 'A\n[image: b]');
    final again = await r.resolve(out, fallbackQuery: 'q');
    expect(again, out);
    expect(searches, ['b'], reason: 'one search, even when it failed');
  });

  test('the same reply resolved twice searches once', () async {
    final r = resolver();
    final a = await r.resolve('A\n[image: b]', fallbackQuery: 'q');
    final b = await r.resolve('A\n[image: b]', fallbackQuery: 'other');
    expect(a, b);
    expect(searches, ['b']);
  });

  test('an already-resolved marker is returned untouched', () async {
    final stored = attachImage('A', _img('b'));
    expect(await resolver().resolve(stored, fallbackQuery: 'q'), stored);
    expect(searches, isEmpty);
  });

  test('a reply that is only a tag still gets its image', () async {
    final out = await resolver().resolve('[image: sleep]', fallbackQuery: 'q');
    expect(splitReply(out).prose, '');
    expect(splitReply(out).image, isNotNull);
  });

  test('off: strips the tag and never searches', () async {
    final out = await ReplyImageResolver.off()
        .resolve('A\n[image: b]', fallbackQuery: 'q');
    expect(out, 'A');
    expect(searches, isEmpty);
  });
}
```

- [ ] **Step 2: Run to confirm failure**

Run `flutter test test/reply_image_resolver_test.dart`. Expected: FAIL, because the URI is missing.

- [ ] **Step 3: Implement**

```dart
// lib/screens/assistant/reply_image_resolver.dart
import '../../services/reply_image.dart';

/// Turns a model reply's `[image: …]` line into a stored Pexels marker.
///
/// Called twice per answer — from `persistTurn` (inside `analyze`) and from
/// `send` — so results are memoised by reply text: one search per answer,
/// successful or not. A failed search keeps the plain tag, and a stored tag is
/// never re-searched on reopen (it arrives here only from a live reply).
class ReplyImageResolver {
  ReplyImageResolver({
    required Future<ReplyImage?> Function(String query) search,
    required bool enabled,
  })  : _search = search,
        _enabled = enabled;

  /// No key in this build: tags are stripped, nothing is searched.
  factory ReplyImageResolver.off() =>
      ReplyImageResolver(search: (_) async => null, enabled: false);

  final Future<ReplyImage?> Function(String query) _search;
  final bool _enabled;

  /// Bounded: a long session must not grow this forever.
  static const _memoLimit = 64;
  final Map<String, Future<String>> _memo = {};

  Future<String> resolve(String reply, {required String fallbackQuery}) {
    final hit = _memo[reply];
    if (hit != null) return hit;
    if (_memo.length >= _memoLimit) _memo.remove(_memo.keys.first);
    final result = _resolve(reply, fallbackQuery);
    _memo[reply] = result;
    // The resolved text maps to itself, so a second pass is a no-op.
    result.then((out) => _memo[out] = Future.value(out));
    return result;
  }

  Future<String> _resolve(String reply, String fallbackQuery) async {
    final split = splitReply(reply);
    if (split.image != null) return reply;
    if (!_enabled) return split.prose;
    final query = split.query ?? fallbackTopic(fallbackQuery);
    if (query == null) return split.prose;
    final image = await _search(query);
    return image == null
        ? keepTag(split.prose, query)
        : attachImage(split.prose, image);
  }
}
```

- [ ] **Step 4: Run to confirm it passes**

Run `flutter test test/reply_image_resolver_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/assistant/reply_image_resolver.dart test/reply_image_resolver_test.dart
git commit -m "feat(assistant): memoised reply-image resolver"
```

---

### Task 4: Wire into LiveAssistantBackend and media_route

**Files:**
- Modify: `lib/screens/assistant/live_assistant_backend.dart`: constructor (~line 37), `conversations()` subtitle (~line 187), resume turns (~line 256), `_send` final return (~line 366), `persistTurn` (~line 465)
- Modify: `lib/screens/media/media_route.dart:99` (constructor call)
- Test: `test/live_assistant_backend_test.dart`

**Interfaces:**
- Consumes:
  - `ReplyImageResolver` (Task 3)
  - `PexelsClient` (Task 2)
  - `forModel`, `splitReply`, `attachImage`, `ReplyImage` (Task 1)
- Produces: `LiveAssistantBackend({…, ReplyImageResolver? replyImages})`

- [ ] **Step 1: Write the failing tests**

In `test/live_assistant_backend_test.dart`:
1. Add the imports:

```dart
import 'package:menstrul_track/screens/assistant/reply_image_resolver.dart';
import 'package:menstrul_track/services/reply_image.dart';
```

2. Change `build` to take `{Listenable? remoteChanges, ReplyImageResolver? replyImages}` and pass `replyImages: replyImages` to `LiveAssistantBackend`.
3. Append this group:

```dart
  group('reply images', () {
    const img = ReplyImage(
        query: 'heat pad', id: 9, src: 'https://i/9.jpg', photographer: 'Sam',
        photographerUrl: 'https://p/@sam', pageUrl: 'https://p/9');
    late List<String> searches;
    ReplyImageResolver images() => ReplyImageResolver(
        enabled: true,
        search: (q) async {
          searches.add(q);
          return img;
        });
    setUp(() => searches = []);

    test('the saved reply and the returned reply carry one resolved photo',
        () async {
      analyzer.answer = 'Heat can help.\n[image: heat pad]';
      final reply = await build(replyImages: images())
          .send(conversationId: 'chat-1', text: 'cramps?');

      expect(splitReply(reply.text).prose, 'Heat can help.');
      expect(splitReply(reply.text).image, img);
      final stored = await sessions.messagesFor('chat-1');
      expect(splitReply(stored.last.messageText).image, img);
      expect(searches, ['heat pad'], reason: 'persist and send share one');
    });

    test('a resumed chat replays the tag, never the URL or the name', () async {
      final backend = build(replyImages: images());
      analyzer.answer = 'Heat can help.\n[image: heat pad]';
      await backend.send(conversationId: 'chat-1', text: 'cramps?');
      backend.endConversation('chat-1');

      await backend.open('chat-1');
      analyzer.answer = 'ok\n[image: rest]';
      await backend.send(conversationId: 'chat-1', text: 'more?');

      final replayed = analyzer.lastHistory.last.text;
      expect(replayed, 'Heat can help.\n[image: heat pad]');
      expect(replayed, isNot(contains('https://')));
    });

    test('the conversations list subtitle never shows a marker', () async {
      analyzer.answer = 'Heat can help.\n[image: heat pad]';
      final backend = build(replyImages: images());
      await backend.send(conversationId: 'chat-1', text: 'cramps?');

      final list = await backend.conversations();
      expect(list.single.subtitle, 'Heat can help.');
    });

    test('with no resolver the tag is stripped and nothing is searched',
        () async {
      analyzer.answer = 'Heat can help.\n[image: heat pad]';
      final reply =
          await build().send(conversationId: 'chat-1', text: 'cramps?');
      expect(reply.text, 'Heat can help.');
    });
  });
```

(`open` and `endConversation` are `AssistantBackend` methods, `assistant_backend.dart:50,75`.)

- [ ] **Step 2: Run to confirm failure**

Run `flutter test test/live_assistant_backend_test.dart`. Expected: FAIL, because `replyImages` is an undefined named parameter.

- [ ] **Step 3: Implement**

In `live_assistant_backend.dart`:

1. Add the imports:

```dart
import '../../services/reply_image.dart';
import 'reply_image_resolver.dart';
```

2. Add the constructor parameter, the initializer and the field:

```dart
    ReplyImageResolver? replyImages,
```

```dart
        _replyImages = replyImages ?? ReplyImageResolver.off(),
```

```dart
  /// Swaps each answer's `[image: …]` line for a stored Pexels marker. Off
  /// (tags stripped) when the build has no Pexels key.
  final ReplyImageResolver _replyImages;
```

3. In `persistTurn`, just before the model `_sessions.append`, resolve the answer and save `stored` in place of `answer`:

```dart
    final stored =
        await _replyImages.resolve(answer, fallbackQuery: question);
```

4. In `_send`, replace `return AssistantReply(AssistantReplyKind.answer, prose);` with:

```dart
    final shown = await _replyImages.resolve(prose,
        fallbackQuery: text.trim().isEmpty ? kDefaultAnalysisQuestion : text);
    return AssistantReply(AssistantReplyKind.answer, shown);
```

5. In the resume loop (~line 256), change the model branch to send `forModel`:

```dart
          : AnalysisTurn.model(forModel(m.messageText),
              attachments: refs[i], includeInModel: m.includeInModel));
```

6. In `conversations()`, change `subtitle = m.messageText;` to:

```dart
          subtitle = splitReply(m.messageText).prose;
```

In `media_route.dart`:

1. Add the imports:

```dart
import '../../services/pexels_client.dart';
import '../assistant/reply_image_resolver.dart';
```

2. Before `final assistant = LiveAssistantBackend(`, add:

```dart
    final pexels = PexelsClient();
```

3. Add this argument to the `LiveAssistantBackend(` call:

```dart
      replyImages: ReplyImageResolver(
        search: pexels.searchTop,
        enabled: canAnalyze && pexels.available,
      ),
```

- [ ] **Step 4: Run to confirm it passes**

Run `flutter test test/live_assistant_backend_test.dart test/assistant_chat_screen_test.dart`. Expected: all pass. The existing test `reply.text == 'an answer'` still passes, because a tag-less answer with the resolver off comes back unchanged (`splitReply` returns the text as is).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/assistant/live_assistant_backend.dart lib/screens/media/media_route.dart test/live_assistant_backend_test.dart
git commit -m "feat(assistant): resolve a Pexels photo for every saved reply"
```

---

### Task 5: The instruction clause

**Files:**
- Modify: `lib/services/media_analysis.dart`, in `kAnalysisSystemInstruction` right after `'no bullet points, no headings, no bold. '`
- Test: `test/media_analysis_test.dart`, `group('kAnalysisSystemInstruction, as the assistant')`

- [ ] **Step 1: Write the failing test**

```dart
    test('ends every reply with one image-topic line (reply images)', () {
      expect(
        kAnalysisSystemInstruction,
        contains('End every reply with one final line in exactly this form: '
            '[image: a 2 to 5 word topic of your reply]. '),
      );
    });
```

- [ ] **Step 2: Run to confirm failure**

Run `flutter test test/media_analysis_test.dart`. Expected: FAIL (does not contain).

- [ ] **Step 3: Implement.** Insert after `'no bullet points, no headings, no bold. '`:

```dart
    'End every reply with one final line in exactly this form: '
    '[image: a 2 to 5 word topic of your reply]. '
```

Leave every other clause exactly as it is. The "keeps the original clauses verbatim" test asserts them.

- [ ] **Step 4: Run to confirm it passes**

Run `flutter test test/media_analysis_test.dart test/media_analysis_service_test.dart`. Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/media_analysis.dart test/media_analysis_test.dart
git commit -m "feat(assistant): ask the model for an image topic line"
```

---

### Task 6: Render the photo and credit

**Files:**
- Modify: `lib/screens/assistant/analysis_chat_view.dart`, `_Bubble` (the non-user branch, ~line 355-390)
- Test: `test/analysis_chat_view_test.dart`

**Interfaces:**
- Consumes: `splitReply`, `attachImage`, `ReplyImage` (Task 1).

- [ ] **Step 1: Write the failing test.** Append inside `main()` in `test/analysis_chat_view_test.dart`, reusing its `pump` helper:

```dart
  testWidgets('a reply with a photo shows the prose, the photo and a credit '
      'once loaded, and never the marker', (tester) async {
    final text = attachImage(
        'Heat can help.',
        const ReplyImage(
            query: 'heat pad', id: 9, src: 'https://i/9.jpg',
            photographer: 'Sam', photographerUrl: 'https://p/@sam',
            pageUrl: 'https://p/9'));
    await pump(tester, entries: [ChatEntry.reply(text)]);

    expect(find.text('Heat can help.'), findsOneWidget);
    expect(find.textContaining('[[pexels'), findsNothing);
    expect(find.byKey(const Key('reply-image')), findsOneWidget);
  });

  testWidgets('a photo that fails to load hides itself and its credit',
      (tester) async {
    // flutter_test answers every real network request with a 400, so this
    // is the failure path.
    final text = attachImage(
        'Heat can help.',
        const ReplyImage(
            query: 'heat pad', id: 9, src: 'https://i/9.jpg',
            photographer: 'Sam', photographerUrl: 'https://p/@sam',
            pageUrl: 'https://p/9'));
    await pump(tester, entries: [ChatEntry.reply(text)]);
    await tester.pumpAndSettle();

    expect(find.textContaining('Photo by Sam'), findsNothing);
    expect(find.text('Heat can help.'), findsOneWidget);
  });

  testWidgets('a bare tag is never shown as text', (tester) async {
    await pump(tester, entries: const [ChatEntry.reply('Rest.\n[image: sleep]')]);
    expect(find.text('Rest.'), findsOneWidget);
    expect(find.textContaining('[image:'), findsNothing);
  });
```

Add the import `import 'package:menstrul_track/services/reply_image.dart';`. If `pump` requires parameters other than `entries`, pass the same defaults as its first existing test.

- [ ] **Step 2: Run to confirm failure**

Run `flutter test test/analysis_chat_view_test.dart`. Expected: FAIL. The marker text is visible, and there is no `reply-image` key.

- [ ] **Step 3: Implement.** In `_Bubble.build`, non-user branch:
- Compute `final split = splitReply(entry.text);`.
- Render `split.prose` instead of `entry.text` in the `SelectableText`.
- Change the `Expanded(child: SelectableText(...))` child to a `Column`:

```dart
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (split.prose.isNotEmpty)
                    // Selectable so an answer can be copied out.
                    SelectableText(
                      split.prose,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.45,
                        color: muted ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                  if (split.image != null) _ReplyPhoto(split.image!),
                ],
              ),
            ),
```

Add at the end of the file:

```dart
/// A Pexels stock photo under a reply. The credit appears only once the image
/// has actually loaded; a failure hides both, so a missing photo never leaves
/// a dangling "Photo by".
class _ReplyPhoto extends StatelessWidget {
  const _ReplyPhoto(this.image);

  final ReplyImage image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('reply-image'),
      padding: const EdgeInsets.only(top: 10),
      child: Image.network(
        image.src,
        semanticLabel: image.query,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(height: 160),
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
        frameBuilder: (context, child, frame, _) {
          if (frame == null) return child;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
              const SizedBox(height: 4),
              Text(
                'Photo by ${image.photographer} on Pexels',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

Add `import '../../services/reply_image.dart';` to the file.

- [ ] **Step 4: Run to confirm it passes**

Run `flutter test test/analysis_chat_view_test.dart test/assistant_chat_screen_test.dart`. Expected: all pass. The existing `find.text('It is pink.')` assertions still hold, because tag-less prose renders unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/assistant/analysis_chat_view.dart test/analysis_chat_view_test.dart
git commit -m "feat(assistant): show the reply photo with a Pexels credit"
```

---

### Task 7: Consent v8, disclosure and docs

**Files:**
- Modify: `lib/services/media_analysis.dart:165-173`: `kCurrentConsentVersion = 8` plus a doc line
- Modify: `lib/screens/media/analysis_consent_sheet.dart`: one new `Text`, and the doc comment "as of consent v7" → v8
- Modify: `PRIVACY_POLICY.md`: a Pexels bullet in the assistant section, after the "Google is **an automatic service…**" bullet
- Modify: `CLAUDE.md`: the assistant bullet's "consent v7" → v8, plus one sentence on reply images
- Test: `test/analysis_consent_sheet_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('v8: says a topic phrase from each reply goes to Pexels',
      (tester) async {
    await setPhoneSize(tester);
    await openSheet(tester);

    expect(
      find.text('A short topic phrase from each reply is sent to Pexels, a '
          'stock-photo service outside LunarFlow, to find a photo to show '
          'with it.'),
      findsOneWidget,
    );
  });
```

And in `test/media_analysis_test.dart`:

```dart
  test('consent is version 8 since reply images', () {
    expect(kCurrentConsentVersion, 8);
  });
```

- [ ] **Step 2: Run to confirm failure**

Run `flutter test test/analysis_consent_sheet_test.dart test/media_analysis_test.dart`. Expected: FAIL.

- [ ] **Step 3: Implement**

1. In `analysis_consent_sheet.dart`, after the "Videos stay in the conversation…" `Text` and its `SizedBox(height: 12)`, add:

```dart
                    Text(
                      'A short topic phrase from each reply is sent to Pexels, '
                      'a stock-photo service outside LunarFlow, to find a '
                      'photo to show with it.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
```

2. In `media_analysis.dart`, replace `const int kCurrentConsentVersion = 7;` with:

```dart
/// Bumped to 8 on 2026-09-26: every reply now carries a Pexels stock photo,
/// found by sending a short topic phrase from the reply to Pexels, a second
/// outside service. Everyone who agreed under 7 is asked again.
const int kCurrentConsentVersion = 8;
```

3. In `PRIVACY_POLICY.md`, add after the Google bullet:

```markdown
- **Each assistant reply shows a stock photo from Pexels.** To find it, a
  short topic phrase taken from the reply (for example "menstrual cramps
  relief") is sent to Pexels, a separate stock-photo company with its own
  terms. The phrase can describe what you were asking about. Nothing else is
  sent to Pexels: not your messages, your photos, your tracked data or your
  account. The photo's address and photographer's name are saved with the
  reply in your conversation.
```

4. In `CLAUDE.md`, under "The AI assistant", add:

```markdown
  - **Reply images (2026-09-26, consent v8).** The model ends each reply with
    `[image: topic]`; `ReplyImageResolver` swaps it for a stored
    `[[pexels {json}]]` marker via `pexels_client.dart` (the second and last
    allowed HTTP caller; key `LUNA_PEXELS_KEY`, off when empty). The topic is
    the real subject, not sanitised, and the app is 8+ — an owner decision,
    disclosed in the sheet and `PRIVACY_POLICY.md`. Markers are reduced to the
    tag before replay (`forModel`), so the model never sees a URL.
```

Update "consent v7" → "consent v8" where the assistant bullet states the current version.

- [ ] **Step 4: Run to confirm it passes**

Run `flutter test test/analysis_consent_sheet_test.dart test/media_analysis_test.dart test/settings_photo_descriptions_toggle_test.dart test/sync_mapper_test.dart`. Expected: all pass. `sync_mapper_test`'s literal `7`s are row values, not the constant.

- [ ] **Step 5: Commit**

```bash
git add lib/services/media_analysis.dart lib/screens/media/analysis_consent_sheet.dart PRIVACY_POLICY.md CLAUDE.md test/analysis_consent_sheet_test.dart test/media_analysis_test.dart
git commit -m "feat(assistant): consent v8 discloses Pexels reply images"
```

---

### Task 8: Full verification

- [ ] **Step 1:** `flutter analyze`. Expected: `No issues found!`
- [ ] **Step 2:** `flutter test`. Expected: every test passes except the 2 known failures in `firebase_unavailable_test.dart`. Update the count in `CLAUDE.md` → Testing.
- [ ] **Step 3: Device check (owner runs it).** With `LUNA_PEXELS_KEY` added to `.env`:
  `flutter run -d <device> --dart-define-from-file=.env`
  1. Consent v8 is asked again.
  2. A reply shows a photo and "Photo by … on Pexels".
  3. Reopening the chat shows the same photo.
  4. In airplane mode, a new reply shows no image and no error.
- [ ] **Step 4:** Commit the CLAUDE.md count change: `git commit -am "docs: test count after reply images"`.
