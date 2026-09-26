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
