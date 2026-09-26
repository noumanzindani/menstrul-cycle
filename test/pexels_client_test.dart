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
