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
