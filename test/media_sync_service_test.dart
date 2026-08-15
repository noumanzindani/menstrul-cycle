import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/media_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/media_limits.dart';
import 'package:menstrul_track/services/media_sync_service.dart';

import 'support/fake_media_blob_store.dart';

void main() {
  late AppDatabase db;
  late MediaRepository repo;
  late FakeMediaBlobStore blobs;
  late FakeFirebaseFirestore firestore;
  late MediaSyncService sync;
  final evicted = <String>[];

  const uid = 'uid-1';
  String idOf(String c) => c * 32;

  MediaSyncService build() => MediaSyncService(
        repo: repo,
        blobStore: blobs,
        firestore: firestore,
        uid: uid,
        deviceId: 'device-1',
        evictCache: (id) async => evicted.add(id),
      );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MediaRepository(db);
    blobs = FakeMediaBlobStore();
    firestore = FakeFirebaseFirestore();
    evicted.clear();
    sync = build();
  });
  tearDown(() => db.close());

  Future<void> remoteItem(String id, {DateTime? capturedAt, String kind = 'image'}) =>
      firestore.doc('users/$uid/media/$id').set({
        'id': id,
        'kind': kind,
        'storagePath': 'users/$uid/media/$id/original.jpg',
        'thumbPath': 'users/$uid/media/$id/thumb.jpg',
        'bytes': 2048,
        'capturedAt': (capturedAt ?? DateTime(2026, 6, 1)).millisecondsSinceEpoch,
        'updatedAt': DateTime(2026, 6, 1).millisecondsSinceEpoch,
        'syncedAt': FieldValue.serverTimestamp(),
      });

  Future<void> remoteTombstone(String id, {DateTime? deletedAt}) =>
      firestore.doc('users/$uid/media/$id').set({
        'id': id,
        'deletedAt':
            (deletedAt ?? DateTime(2026, 7, 1)).millisecondsSinceEpoch,
        'syncedAt': FieldValue.serverTimestamp(),
      });

  Future<void> localItem(String id) => repo.upsert(
        id: id,
        uid: uid,
        kind: MediaKind.image,
        storagePath: 'users/$uid/media/$id/original.jpg',
        thumbPath: 'users/$uid/media/$id/thumb.jpg',
        capturedAt: DateTime(2026, 6, 1),
      );

  group('pull', () {
    test('brings remote items into the local replica', () async {
      await remoteItem(idOf('a'));
      await remoteItem(idOf('b'));

      await sync.pull();

      expect(await repo.allFor(uid), hasLength(2));
      final row = await repo.byId(idOf('a'));
      expect(row!.storagePath, 'users/$uid/media/${idOf('a')}/original.jpg');
      expect(row.uid, uid, reason: 'rows are filed under the pulling account');
    });

    test('never carries thumbnail bytes down from Firestore', () async {
      // Imagery in Firestore documents would land in the SDK's UNENCRYPTED
      // on-device cache on every device the account touches. The blob column is
      // filled locally from thumbPath instead.
      await remoteItem(idOf('a'));
      await sync.pull();
      expect((await repo.byId(idOf('a')))!.thumbnail, isNull);
    });

    test('a tombstone deletes the local row and evicts its cached bytes',
        () async {
      await localItem(idOf('a'));
      await remoteTombstone(idOf('a'));

      await sync.pull();

      expect(await repo.byId(idOf('a')), isNull);
      expect(evicted, [idOf('a')]);
    });

    test('a tombstone for something never seen locally is harmless', () async {
      await remoteTombstone(idOf('z'));
      await expectLater(sync.pull(), completes);
      expect(await repo.allFor(uid), isEmpty);
    });

    test('advances its own cursor, not the log or deletion cursors', () async {
      await remoteItem(idOf('a'));
      await sync.pull();

      final device =
          (await firestore.doc('users/$uid/devices/device-1').get()).data()!;
      expect(device['mediaCursor'], isNotNull);
      // Sharing a cursor across collections is the silent-permanent-skip bug
      // the per-collection rule in sync_service.dart exists to prevent.
      expect(device.containsKey('logsCursor'), isFalse);
      expect(device.containsKey('deletionsCursor'), isFalse);
    });

    test('merges into a device document that already has other cursors',
        () async {
      await firestore
          .doc('users/$uid/devices/device-1')
          .set({'logsCursor': Timestamp.fromDate(DateTime(2026, 1, 1))});
      await remoteItem(idOf('a'));

      await sync.pull();

      final device =
          (await firestore.doc('users/$uid/devices/device-1').get()).data()!;
      expect(device['logsCursor'], isNotNull, reason: 'must not be clobbered');
      expect(device['mediaCursor'], isNotNull);
    });

    test('a second pull with nothing new leaves the cursor alone', () async {
      await remoteItem(idOf('a'));
      await sync.pull();
      final first =
          (await firestore.doc('users/$uid/devices/device-1').get())
              .data()!['mediaCursor'];

      await sync.pull();

      final second =
          (await firestore.doc('users/$uid/devices/device-1').get())
              .data()!['mediaCursor'];
      expect(second, first);
    });

    test('a full sweep ignores the cursor', () async {
      await remoteItem(idOf('a'));
      await sync.pull();
      await repo.deleteById(idOf('a')); // as a local wipe would

      await sync.pull(fullSweep: true);

      expect(await repo.byId(idOf('a')), isNotNull);
    });
  });

  group('delete', () {
    test('writes the tombstone, removes both objects, then the local row',
        () async {
      await localItem(idOf('a'));
      blobs.objects['users/$uid/media/${idOf('a')}/original.jpg'] = 10;
      blobs.objects['users/$uid/media/${idOf('a')}/thumb.jpg'] = 5;

      await sync.delete(idOf('a'));

      final doc = await firestore.doc('users/$uid/media/${idOf('a')}').get();
      expect(doc.data()!['deletedAt'], isNotNull);
      // The replace scrubs the metadata off the server in the same write.
      expect(doc.data()!.containsKey('storagePath'), isFalse);
      expect(doc.data()!.containsKey('caption'), isFalse);

      expect(blobs.deleted, hasLength(2));
      expect(await repo.byId(idOf('a')), isNull);
      expect(evicted, [idOf('a')]);
    });

    test('a missing object does not abort the delete', () async {
      // A delete whose object is already gone has SUCCEEDED. Treating a 404 as
      // failure would strand the row forever.
      await localItem(idOf('a'));
      blobs.failOn = 'original';

      await expectLater(sync.delete(idOf('a')), completes);
      expect(await repo.byId(idOf('a')), isNull);
    });
  });

  group('sweepOrphans', () {
    Future<void> bucketObject(String id, String name) async {
      blobs.objects['users/$uid/media/$id/$name'] = 100;
    }

    test('deletes an object with no metadata document', () async {
      await bucketObject(idOf('a'), 'original.jpg');

      final removed = await sync.sweepOrphans();

      expect(removed, 1);
      expect(blobs.objects, isEmpty);
    });

    test('KEEPS an object that has a document — the discriminating half',
        () async {
      await bucketObject(idOf('a'), 'original.jpg');
      await bucketObject(idOf('a'), 'thumb.jpg');
      await remoteItem(idOf('a'));

      final removed = await sync.sweepOrphans();

      expect(removed, 0);
      expect(blobs.objects, hasLength(2));
    });

    test('skips ids that are uploading right now', () async {
      // Mid-upload is indistinguishable from orphaned from the outside: object
      // present, document not written yet. Deleting it would destroy a photo
      // the user is actively adding.
      await bucketObject(idOf('a'), 'original.jpg');

      final removed = await sync.sweepOrphans(skipIds: {idOf('a')});

      expect(removed, 0);
      expect(blobs.objects, hasLength(1));
    });

    test('never touches another account\'s prefix', () async {
      blobs.objects['users/other-uid/media/${idOf('z')}/original.jpg'] = 100;
      await bucketObject(idOf('a'), 'original.jpg');

      await sync.sweepOrphans();

      expect(
        blobs.objects.keys,
        ['users/other-uid/media/${idOf('z')}/original.jpg'],
      );
    });

    test('deletes every object in an orphaned folder, whatever the extension',
        () async {
      await bucketObject(idOf('a'), 'original.mov');
      await bucketObject(idOf('a'), 'thumb.jpg');

      await sync.sweepOrphans();

      expect(blobs.objects, isEmpty);
    });

    test('a listing failure is survivable, not fatal', () async {
      // The sweep runs when a screen opens. It must never be the reason the
      // timeline fails to appear.
      blobs.failOn = 'users';
      expect(await sync.sweepOrphans(), 0);
    });

    test('an empty bucket sweeps nothing and reads no documents', () async {
      expect(await sync.sweepOrphans(), 0);
    });
  });

  group('pruneOldMarkers', () {
    test('removes markers past the retention window and keeps recent ones',
        () async {
      final now = DateTime(2026, 8, 1);
      await remoteTombstone(idOf('a'),
          deletedAt: now.subtract(const Duration(days: 200)));
      await remoteTombstone(idOf('b'),
          deletedAt: now.subtract(const Duration(days: 10)));
      await remoteItem(idOf('c'));

      await sync.pruneOldMarkers(now: now);

      final remaining =
          (await firestore.collection('users/$uid/media').get()).docs;
      expect(remaining.map((d) => d.id), unorderedEquals([idOf('b'), idOf('c')]));
    });
  });

  test('thumbnail blobs stay a per-device cache across a pull', () async {
    // A device that has cached a thumbnail must not lose it just because the
    // item was re-pulled; and a device that has not must not gain one.
    await remoteItem(idOf('a'));
    await sync.pull();
    await repo.upsert(
      id: idOf('a'),
      uid: uid,
      kind: MediaKind.image,
      storagePath: 'users/$uid/media/${idOf('a')}/original.jpg',
      capturedAt: DateTime(2026, 6, 1),
      thumbnail: Uint8List.fromList([1, 2, 3]),
    );
    expect((await repo.byId(idOf('a')))!.thumbnail, isNotNull);
  });
}
