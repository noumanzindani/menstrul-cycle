import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/analysis_session_repository.dart';
import 'package:menstrul_track/data/media_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/media_limits.dart';

void main() {
  late AppDatabase db;
  late MediaRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<void> seed(
    String id, {
    String uid = 'uid-1',
    MediaKind kind = MediaKind.image,
    DateTime? capturedAt,
    Uint8List? thumbnail,
    int? durationMs,
  }) =>
      repo.upsert(
        id: id,
        uid: uid,
        kind: kind,
        storagePath: 'users/$uid/media/$id/original.jpg',
        thumbPath: 'users/$uid/media/$id/thumb.jpg',
        bytes: 1234,
        capturedAt: capturedAt ?? DateTime(2026, 6, 1),
        thumbnail: thumbnail,
        durationMs: durationMs,
      );

  group('upsert', () {
    test('inserts a row that reads back field for field', () async {
      await seed('a' * 32, capturedAt: DateTime(2026, 5, 4), durationMs: 4200);

      final item = await repo.byId('a' * 32);
      expect(item, isNotNull);
      expect(item!.uid, 'uid-1');
      expect(item.kind, 'image');
      expect(item.storagePath, 'users/uid-1/media/${'a' * 32}/original.jpg');
      expect(item.thumbPath, 'users/uid-1/media/${'a' * 32}/thumb.jpg');
      expect(item.bytes, 1234);
      expect(item.capturedAt, DateTime(2026, 5, 4));
      expect(item.durationMs, 4200);
    });

    test('is idempotent — the same id replaces rather than duplicates', () async {
      // The pull applies whatever the server has; re-applying an unchanged
      // document must not grow the table.
      await seed('a' * 32);
      await seed('a' * 32);
      expect(await repo.allFor('uid-1'), hasLength(1));
    });

    test('a thumbnail round-trips as bytes', () async {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i % 256));
      await seed('a' * 32, thumbnail: bytes);

      expect((await repo.byId('a' * 32))!.thumbnail, bytes);
    });

    test('a null thumbnail is allowed — it is a cache, not a source of truth',
        () async {
      await seed('a' * 32);
      expect((await repo.byId('a' * 32))!.thumbnail, isNull);
    });
  });

  group('allFor', () {
    test('is newest-captured first', () async {
      await seed('a' * 32, capturedAt: DateTime(2026, 1, 1));
      await seed('b' * 32, capturedAt: DateTime(2026, 7, 1));
      await seed('c' * 32, capturedAt: DateTime(2026, 4, 1));

      final ids = (await repo.allFor('uid-1')).map((m) => m.id).toList();
      expect(ids, ['b' * 32, 'c' * 32, 'a' * 32]);
    });

    test('breaks a capture-time tie deterministically', () async {
      // Two photos taken in the same second is ordinary — a burst, or a picker
      // that reports only whole seconds. Without a tiebreak the grid reshuffles
      // itself between rebuilds.
      final t = DateTime(2026, 6, 1, 12, 0, 0);
      await seed('b' * 32, capturedAt: t);
      await seed('a' * 32, capturedAt: t);

      final first = (await repo.allFor('uid-1')).map((m) => m.id).toList();
      final second = (await repo.allFor('uid-1')).map((m) => m.id).toList();
      expect(first, second);
      expect(first, ['a' * 32, 'b' * 32]);
    });

    test('NEVER returns another account\'s rows', () async {
      // The single most important assertion in this file. Signing out does not
      // wipe the device, so account A's rows can still be on disk when B signs
      // in — and A's thumbnails are photographs.
      await seed('a' * 32, uid: 'uid-A');
      await seed('b' * 32, uid: 'uid-B');

      expect((await repo.allFor('uid-B')).single.id, 'b' * 32);
      expect((await repo.allFor('uid-A')).single.id, 'a' * 32);
      expect(await repo.allFor('uid-C'), isEmpty);
    });
  });

  group('idsFor', () {
    test('returns exactly the ids the orphan sweep should keep', () async {
      await seed('a' * 32);
      await seed('b' * 32);
      await seed('c' * 32, uid: 'uid-other');

      expect(await repo.idsFor('uid-1'), {'a' * 32, 'b' * 32});
    });
  });

  group('deletion', () {
    test('deleteById removes the row and its thumbnail blob', () async {
      await seed('a' * 32,
          thumbnail: Uint8List.fromList(List.filled(32, 9)));
      await seed('b' * 32);

      await repo.deleteById('a' * 32);

      expect(await repo.byId('a' * 32), isNull);
      expect(await repo.allFor('uid-1'), hasLength(1));
    });

    test('deleteById is a no-op for an unknown id', () async {
      await seed('a' * 32);
      await repo.deleteById('f' * 32);
      expect(await repo.allFor('uid-1'), hasLength(1));
    });

    test('deleteExcept keeps only the signed-in account and wipes the rest',
        () async {
      await seed('a' * 32, uid: 'uid-A');
      await seed('b' * 32, uid: 'uid-B');
      await seed('c' * 32, uid: 'uid-B');

      await repo.deleteExcept('uid-B');

      expect(await repo.allFor('uid-A'), isEmpty);
      expect(await repo.allFor('uid-B'), hasLength(2));
    });

    test('deleteExcept with no signed-in account wipes everything', () async {
      // Sign-out. Nothing in the timeline is usable without an account, and the
      // thumbnails should not sit on disk waiting for the next person.
      await seed('a' * 32, uid: 'uid-A');
      await seed('b' * 32, uid: 'uid-B');

      await repo.deleteExcept(null);

      expect(await db.select(db.mediaItems).get(), isEmpty);
    });
  });

  group('cascade to saved analysis conversations', () {
    // A conversation about a photo that no longer exists is an orphan
    // holding AI-generated commentary about that photo — see
    // `AnalysisSessionRepository.deleteForMedia`/`.deleteExcept`, which this
    // repository must trigger rather than duplicate.
    late AnalysisSessionRepository sessions;

    setUp(() => sessions = AnalysisSessionRepository(db));

    test('deleteById removes the session AND its messages, not just the row',
        () async {
      await seed('a' * 32);
      final s =
          await sessions.create(uid: 'uid-1', mediaId: 'a' * 32, consentVersion: 2);
      await sessions.append(sessionId: s.id, role: 'model', text: 'a description');

      await repo.deleteById('a' * 32);

      expect(await sessions.forMedia(uid: 'uid-1', mediaId: 'a' * 32), isNull);
      expect(await db.select(db.analysisMessages).get(), isEmpty);
    });

    test('deleteById leaves another photo\'s conversation untouched',
        () async {
      await seed('a' * 32);
      await seed('b' * 32);
      final keep =
          await sessions.create(uid: 'uid-1', mediaId: 'b' * 32, consentVersion: 2);
      await sessions.append(sessionId: keep.id, role: 'model', text: 'kept');

      await repo.deleteById('a' * 32);

      expect(await sessions.forMedia(uid: 'uid-1', mediaId: 'b' * 32),
          isNotNull);
      expect(await db.select(db.analysisMessages).get(), hasLength(1));
    });

    test('deleteExcept cascades to messages of the dropped account too',
        () async {
      await seed('a' * 32, uid: 'uid-A');
      await seed('b' * 32, uid: 'uid-B');
      final dropped = await sessions.create(
          uid: 'uid-A', mediaId: 'a' * 32, consentVersion: 2);
      await sessions.append(sessionId: dropped.id, role: 'model', text: 'gone');
      final kept = await sessions.create(
          uid: 'uid-B', mediaId: 'b' * 32, consentVersion: 2);
      await sessions.append(sessionId: kept.id, role: 'model', text: 'stays');

      await repo.deleteExcept('uid-B');

      expect(await sessions.allFor('uid-A'), isEmpty);
      expect(await db.select(db.analysisMessages).get(), hasLength(1));
      expect(await sessions.allFor('uid-B'), hasLength(1));
    });
  });
}
