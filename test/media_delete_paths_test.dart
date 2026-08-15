import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/account_deletion_service.dart';

/// The orphan census, as an executable spec.
///
/// Media is the first thing in this app whose bytes live outside drift, so
/// every existing "erase it" path had to be checked one at a time rather than
/// inherited. This file pins the drift half; the cloud half (the `media`
/// subcollection and the Storage prefix) is pinned in
/// `test/account_deletion_test.dart` and `firebase_test/purge.test.mjs`.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seedMedia(String id) => db.into(db.mediaItems).insert(
        MediaItemsCompanion.insert(
          id: id,
          uid: 'uid-1',
          kind: 'image',
          storagePath: 'users/uid-1/media/$id/original.jpg',
          capturedAt: DateTime(2026, 6, 1),
          thumbnail: Value(Uint8List.fromList(List.filled(64, 7))),
        ),
      );

  test('deleteAllData erases media rows AND their thumbnail blobs', () async {
    await seedMedia('0123456789abcdef0123456789abcdef');
    await seedMedia('fedcba9876543210fedcba9876543210');
    expect(await db.select(db.mediaItems).get(), hasLength(2));

    await db.deleteAllData();

    // The thumbnails are the only decoded bodily imagery this database holds.
    // Leaving them would make "everything on this device is erased" false in
    // the most visible way available.
    expect(await db.select(db.mediaItems).get(), isEmpty);
  });

  test('deleteAllData still reseeds the settings row alongside the wipe',
      () async {
    await seedMedia('0123456789abcdef0123456789abcdef');
    await db.deleteAllData();
    // Guards against the media delete being added outside the transaction or
    // after the reseed, either of which would change what the caller observes.
    expect((await db.getSettings()).id, 0);
  });

  group('the cloud deletion contract', () {
    test('media is in the subcollection sweep list', () {
      // Asserted against the constant, never a duplicated literal — that class's
      // own doc says adding a subcollection without adding it there leaves data
      // behind after an erasure request.
      expect(AccountDeletionService.subcollections, contains('media'));
    });

    test('the storage prefix is uid-scoped and derivable from the uid alone',
        () {
      // Prefix-based rather than metadata-driven on purpose: an object whose
      // document was already deleted must still be swept, and a partial earlier
      // run must not make the rest unreachable.
      expect(AccountDeletionService.storagePrefix('uid-1'), 'users/uid-1/media/');
      expect(
        AccountDeletionService.storagePrefix('uid-2'),
        isNot(AccountDeletionService.storagePrefix('uid-1')),
      );
    });

    test('deleting the metadata alone is NOT the whole job', () {
      // A standing reminder in executable form. deleteFirestoreData is the
      // executable spec of the purge, and with media it is no longer complete:
      // Storage is a second service this client cannot reach. If this ever
      // becomes false, the spec is whole again and this test should go.
      expect(
        AccountDeletionService.subcollections.contains('media') &&
            AccountDeletionService.storagePrefix('u').isNotEmpty,
        isTrue,
      );
    });
  });

  test('a media row survives an ordinary day-log delete', () async {
    // Media is a standalone timeline, not a day attachment. Deleting a day must
    // not take photographs with it — there is no relationship to cascade.
    await seedMedia('0123456789abcdef0123456789abcdef');
    await db.delete(db.dailyLogs).go();
    expect(await db.select(db.mediaItems).get(), hasLength(1));
  });
}
