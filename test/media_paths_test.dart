import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/media_paths.dart';

void main() {
  const uid = 'user-abc';
  const id = '0123456789abcdef0123456789abcdef';

  group('newMediaId', () {
    test('is 32 lowercase hex characters', () {
      final id = newMediaId();
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('does not collide over many draws', () {
      final seen = <String>{};
      for (var i = 0; i < 10000; i++) {
        expect(seen.add(newMediaId()), isTrue);
      }
    });

    test('the same file picked twice gets two different ids', () {
      // Ids are random, never content-derived. A content hash would make the
      // second upload OVERWRITE the first object at the same path, rotating
      // its download token and breaking anything already pointing at it.
      expect(newMediaId(), isNot(newMediaId()));
    });
  });

  group('object paths', () {
    test('are rooted at users/{uid}/media/{id} so the rule can be isOwner', () {
      expect(
        originalObjectPath(uid: uid, mediaId: id, contentType: 'image/jpeg'),
        'users/$uid/media/$id/original.jpg',
      );
      expect(thumbObjectPath(uid: uid, mediaId: id),
          'users/$uid/media/$id/thumb.jpg');
      expect(mediaFolderPath(uid: uid, mediaId: id), 'users/$uid/media/$id');
    });

    test('are deterministic', () {
      final a =
          originalObjectPath(uid: uid, mediaId: id, contentType: 'video/mp4');
      final b =
          originalObjectPath(uid: uid, mediaId: id, contentType: 'video/mp4');
      expect(a, b);
    });

    test('the extension comes from the content type, never a filename', () {
      expect(
        originalObjectPath(uid: uid, mediaId: id, contentType: 'image/heic'),
        endsWith('original.heic'),
      );
      expect(
        originalObjectPath(
            uid: uid, mediaId: id, contentType: 'video/quicktime'),
        endsWith('original.mov'),
      );
    });

    test('an unsupported content type has no path', () {
      // Refusal happens in media_limits; this is the belt-and-braces half.
      expect(
        () => originalObjectPath(
            uid: uid, mediaId: id, contentType: 'application/pdf'),
        throwsArgumentError,
      );
    });

    test('the file name segment is always original.* or thumb.jpg', () {
      // storage.rules pins fileName to ^(original|thumb)\.[a-z0-9]+$; if this
      // ever produces anything else, every upload starts failing in production
      // and passing in tests.
      final pattern = RegExp(r'^(original|thumb)\.[a-z0-9]+$');
      for (final t in ['image/jpeg', 'image/png', 'image/webp', 'image/heic',
        'image/heif', 'video/mp4', 'video/quicktime']) {
        final path =
            originalObjectPath(uid: uid, mediaId: id, contentType: t);
        expect(pattern.hasMatch(path.split('/').last), isTrue, reason: t);
      }
      expect(
        pattern.hasMatch(thumbObjectPath(uid: uid, mediaId: id).split('/').last),
        isTrue,
      );
    });
  });

  group('paths carry no user content', () {
    test('a caption or note can never reach a path', () {
      // Object paths appear in Cloud Storage access logs, audit logs and
      // billing exports. purge.js already hashes uids before logging for this
      // reason; "IMG_ultrasound_2026-03-04.heic" in a log line would undo it.
      final path =
          originalObjectPath(uid: uid, mediaId: id, contentType: 'image/jpeg');
      expect(path.split('/'), ['users', uid, 'media', id, 'original.jpg']);
    });

    test('a mediaId that is not opaque hex is rejected', () {
      expect(
        () => originalObjectPath(
            uid: uid, mediaId: 'my-ultrasound.jpg', contentType: 'image/jpeg'),
        throwsArgumentError,
      );
      expect(
        () => originalObjectPath(
            uid: uid, mediaId: '../../other', contentType: 'image/jpeg'),
        throwsArgumentError,
      );
    });

    test('an empty uid is rejected', () {
      expect(
        () => originalObjectPath(
            uid: '', mediaId: id, contentType: 'image/jpeg'),
        throwsArgumentError,
      );
    });
  });
}
