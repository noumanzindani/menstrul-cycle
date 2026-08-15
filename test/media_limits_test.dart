import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/media_limits.dart';

void main() {
  group('kind is derived from the content type', () {
    test('recognises the allowed image types', () {
      for (final t in ['image/jpeg', 'image/png', 'image/webp', 'image/heic',
        'image/heif']) {
        expect(mediaKindFor(t), MediaKind.image, reason: t);
      }
    });

    test('recognises the allowed video types', () {
      for (final t in ['video/mp4', 'video/quicktime']) {
        expect(mediaKindFor(t), MediaKind.video, reason: t);
      }
    });

    test('is case-insensitive and tolerates a parameter suffix', () {
      expect(mediaKindFor('IMAGE/JPEG'), MediaKind.image);
      expect(mediaKindFor('image/jpeg; charset=binary'), MediaKind.image);
    });

    test('returns null for everything else', () {
      for (final t in [
        'application/pdf',
        'text/html',
        'application/octet-stream',
        'image/gif',
        'image/svg+xml',
        'video/x-msvideo',
        '',
      ]) {
        expect(mediaKindFor(t), isNull, reason: t);
      }
    });

    test('a partial match cannot slip through', () {
      // The storage.rules allowlist is anchored; this must agree with it.
      expect(mediaKindFor('text/html;image/jpeg'), isNull);
      expect(mediaKindFor('image/jpeg.evil'), isNull);
      expect(mediaKindFor('ximage/jpeg'), isNull);
    });
  });

  group('image size cap', () {
    test('accepts a file exactly at the cap', () {
      expect(
        checkPickedFile(contentType: 'image/jpeg', bytes: kMaxImageBytes),
        isNull,
      );
    });

    test('refuses one byte over the cap', () {
      final r = checkPickedFile(
        contentType: 'image/jpeg',
        bytes: kMaxImageBytes + 1,
      );
      expect(r, isNotNull);
      expect(r!.reason, MediaRefusal.tooLarge);
    });

    test('the image cap is independent of the video cap', () {
      // A video-sized image must still be refused.
      expect(
        checkPickedFile(contentType: 'image/png', bytes: kMaxVideoBytes)?.reason,
        MediaRefusal.tooLarge,
      );
    });
  });

  group('video caps', () {
    test('accepts a clip exactly at both caps', () {
      expect(
        checkPickedFile(
          contentType: 'video/mp4',
          bytes: kMaxVideoBytes,
          duration: kMaxVideoDuration,
        ),
        isNull,
      );
    });

    test('refuses one byte over the size cap', () {
      expect(
        checkPickedFile(
          contentType: 'video/mp4',
          bytes: kMaxVideoBytes + 1,
          duration: const Duration(seconds: 5),
        )?.reason,
        MediaRefusal.tooLarge,
      );
    });

    test('refuses one millisecond over the duration cap', () {
      expect(
        checkPickedFile(
          contentType: 'video/mp4',
          bytes: 1024,
          duration: kMaxVideoDuration + const Duration(milliseconds: 1),
        )?.reason,
        MediaRefusal.tooLong,
      );
    });

    test('refuses a video whose duration could not be read', () {
      // The probe times out on malformed files. A video we cannot measure is
      // refused rather than uploaded unmeasured — the cap is a refusal, and an
      // unenforceable cap is not a cap.
      expect(
        checkPickedFile(contentType: 'video/mp4', bytes: 1024)?.reason,
        MediaRefusal.unreadable,
      );
    });

    test('an image needs no duration', () {
      expect(checkPickedFile(contentType: 'image/jpeg', bytes: 1024), isNull);
    });
  });

  test('an unsupported type is refused before any size check', () {
    final r = checkPickedFile(contentType: 'application/pdf', bytes: 10);
    expect(r?.reason, MediaRefusal.unsupportedType);
  });

  test('an empty file is refused', () {
    expect(
      checkPickedFile(contentType: 'image/jpeg', bytes: 0)?.reason,
      MediaRefusal.empty,
    );
  });

  group('every refusal carries a message', () {
    test('the message is non-empty and names no file path', () {
      final cases = <MediaRejection?>[
        checkPickedFile(contentType: 'application/pdf', bytes: 10),
        checkPickedFile(contentType: 'image/jpeg', bytes: 0),
        checkPickedFile(contentType: 'image/jpeg', bytes: kMaxImageBytes + 1),
        checkPickedFile(
            contentType: 'video/mp4',
            bytes: kMaxVideoBytes + 1,
            duration: const Duration(seconds: 1)),
        checkPickedFile(
            contentType: 'video/mp4',
            bytes: 1,
            duration: kMaxVideoDuration + const Duration(seconds: 1)),
        checkPickedFile(contentType: 'video/mp4', bytes: 1),
      ];
      for (final c in cases) {
        expect(c, isNotNull);
        expect(c!.message.trim(), isNotEmpty);
      }
    });

    test('no refusal copy claims the media is safe, private or encrypted',
        () {
      // Same family of guardrail as the change-timer copy rules: the bucket is
      // unencrypted and operator-readable, so no string here may imply
      // otherwise. See CLAUDE.md — copy describes what the code does today.
      const banned = ['safe', 'private', 'secure', 'encrypted', 'protected'];
      for (final r in MediaRefusal.values) {
        final message = messageFor(r).toLowerCase();
        for (final word in banned) {
          expect(message.contains(word), isFalse,
              reason: '"$word" appears in the copy for $r');
        }
      }
    });
  });

  group('per-pick count limit', () {
    test('accepts exactly the limit with nothing dropped', () {
      final items = List.generate(kMaxItemsPerPick, (i) => i);
      final r = applyPickLimit(items);
      expect(r.accepted, hasLength(kMaxItemsPerPick));
      expect(r.dropped, 0);
    });

    test('truncates over the limit and REPORTS how many were dropped', () {
      // A silent truncation reads as "we took everything". The count is what
      // lets the caller say so.
      final items = List.generate(kMaxItemsPerPick + 3, (i) => i);
      final r = applyPickLimit(items);
      expect(r.accepted, hasLength(kMaxItemsPerPick));
      expect(r.dropped, 3);
      expect(r.accepted.first, 0, reason: 'keeps the first N, in order');
    });

    test('an empty pick drops nothing', () {
      final r = applyPickLimit(<int>[]);
      expect(r.accepted, isEmpty);
      expect(r.dropped, 0);
    });
  });
}
