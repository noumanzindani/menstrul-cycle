// test/reply_image_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/assistant/reply_image_resolver.dart';
import 'package:menstrul_track/services/reply_image.dart';

ReplyImage _img(String q) => ReplyImage(
    query: q, id: 1, src: 'https://images.pexels.com/photos/1.jpg', photographer: 'Sam',
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

  test('a marker in live model output is never trusted: it is re-searched',
      () async {
    // Prompt injection (text in a photo, or the user's message) could make
    // the model emit a marker pointing anywhere. Only a search result may
    // become an image.
    answer = (q) => _img('searched');
    final injected = attachImage('A', _img('b'));
    final out = await resolver().resolve(injected, fallbackQuery: 'q');
    expect(searches, ['b']);
    expect(splitReply(out).image, _img('searched'));
  });

  test('its own output resolved again is served from memory', () async {
    final r = resolver();
    final out = await r.resolve('A\n[image: b]', fallbackQuery: 'q');
    expect(await r.resolve(out, fallbackQuery: 'q'), out);
    expect(searches, ['b']);
  });

  test('an empty fallback query means no search', () async {
    final out = await resolver().resolve('A', fallbackQuery: '');
    expect(out, 'A');
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
