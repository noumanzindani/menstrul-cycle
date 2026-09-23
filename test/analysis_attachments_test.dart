import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/media_analysis.dart';

void main() {
  final photo = 'a' * 32;
  final video = 'b' * 32;

  group('encodeAttachments / decodeAttachments', () {
    test('an empty list stores nothing', () {
      expect(encodeAttachments(const []), isNull);
      expect(decodeAttachments(null), isEmpty);
    });

    test('round-trips ids and kinds in order', () {
      final refs = [AttachmentRef.video(video), AttachmentRef.image(photo)];
      final json = encodeAttachments(refs);

      expect(
        json,
        '[{"mediaId":"$video","kind":"video"},'
        '{"mediaId":"$photo","kind":"image"}]',
      );
      expect(decodeAttachments(json), refs);
    });

    test('a malformed column reads as no attachments, never a crash', () {
      expect(decodeAttachments(''), isEmpty);
      expect(decodeAttachments('not json'), isEmpty);
      expect(decodeAttachments('{"mediaId":"x","kind":"image"}'), isEmpty);
    });

    test('drops entries it cannot trust and keeps the rest', () {
      final json =
          '[{"mediaId":"$photo","kind":"image"},'
          '{"mediaId":"","kind":"image"},'
          '{"mediaId":42,"kind":"image"},'
          '{"mediaId":"$video","kind":"audio"},'
          '"$video",'
          '{"mediaId":"$video","kind":"video","url":"https://x"}]';

      // An unknown kind is dropped rather than guessed, and extra keys are
      // ignored: only the id and kind are ever read back.
      expect(decodeAttachments(json), [
        AttachmentRef.image(photo),
        AttachmentRef.video(video),
      ]);
    });
  });

  group('effectiveAttachments', () {
    test('a pre-v16 Describe chat gets its photo on the first user turn', () {
      final result = effectiveAttachments(photo, const [
        (role: 'user', attachmentsJson: null),
        (role: 'model', attachmentsJson: null),
        (role: 'user', attachmentsJson: null),
      ]);

      expect(result, [
        [AttachmentRef.image(photo)],
        <AttachmentRef>[],
        <AttachmentRef>[],
      ]);
    });

    test('a chat started in the tab gets nothing added', () {
      final result = effectiveAttachments('', const [
        (role: 'user', attachmentsJson: null),
        (role: 'model', attachmentsJson: null),
      ]);

      expect(result, [<AttachmentRef>[], <AttachmentRef>[]]);
    });

    test('stored attachments win and the shim adds nothing', () {
      final stored = encodeAttachments([AttachmentRef.image(photo)]);
      final later = encodeAttachments([AttachmentRef.image(video)]);
      final result = effectiveAttachments(photo, [
        (role: 'user', attachmentsJson: stored),
        (role: 'model', attachmentsJson: null),
        (role: 'user', attachmentsJson: later),
      ]);

      expect(result, [
        [AttachmentRef.image(photo)],
        <AttachmentRef>[],
        [AttachmentRef.image(video)],
      ]);
    });

    test('skips leading model turns to find the first user turn', () {
      final result = effectiveAttachments(photo, const [
        (role: 'model', attachmentsJson: null),
        (role: 'user', attachmentsJson: null),
      ]);

      expect(result, [
        <AttachmentRef>[],
        [AttachmentRef.image(photo)],
      ]);
    });

    test('an empty transcript stays empty', () {
      expect(effectiveAttachments(photo, const []), isEmpty);
    });
  });
}
