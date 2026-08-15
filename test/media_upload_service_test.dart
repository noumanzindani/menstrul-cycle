import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/media_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/account_deletion_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/media_limits.dart';
import 'package:menstrul_track/services/media_thumbnailer.dart';
import 'package:menstrul_track/services/media_upload_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

import 'support/fake_media_blob_store.dart';

void main() {
  late AppDatabase db;
  late MediaRepository repo;
  late FakeMediaBlobStore blobs;
  late FakeFirebaseFirestore firestore;
  late SyncTrigger trigger;
  late Directory tmp;
  ClaimRecord? claim;

  const uid = 'uid-1';

  Future<SyncTrigger> buildTrigger(String? signedIn) async {
    final t = SyncTrigger(
      db,
      firestore: () => firestore,
      deviceId: () async => 'device-1',
      readClaim: () async => claim,
      writeClaim: (r) async => claim = r,
    );
    await t.setUser(signedIn);
    return t;
  }

  MediaUploadService buildService() => MediaUploadService(
        repo: repo,
        blobStore: blobs,
        thumbnailer: MediaThumbnailer(
          encoder: (src, {required maxEdge, required quality}) async =>
              Uint8List(1024),
        ),
        firestore: () => firestore,
        trigger: trigger,
        deviceId: () async => 'device-1',
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MediaRepository(db);
    blobs = FakeMediaBlobStore();
    firestore = FakeFirebaseFirestore();
    claim = const ClaimRecord(uid: uid, declined: false);
    tmp = await Directory.systemTemp.createTemp('luna_upload_test');
    trigger = await buildTrigger(uid);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<PickedMedia> picked({
    String contentType = 'image/jpeg',
    int bytes = 1024,
    Duration? duration,
    DateTime? capturedAt,
  }) async {
    final f = File('${tmp.path}/pick${blobs.uploads.length}_$bytes.bin');
    await f.writeAsBytes(List.filled(bytes, 2), flush: true);
    return PickedMedia(
      file: f,
      contentType: contentType,
      duration: duration,
      capturedAt: capturedAt,
    );
  }

  Future<int> mediaDocCount() async =>
      (await firestore.collection('users/$uid/media').get()).docs.length;

  group('a successful image upload', () {
    test('writes thumb, then original, then the document, then the row',
        () async {
      final outcome = await buildService().upload([await picked()]);

      expect(outcome.uploadedIds, hasLength(1));
      final id = outcome.uploadedIds.single;

      // Order matters: the row is written LAST, so its existence means the
      // bytes and the metadata are both already up there.
      expect(blobs.uploads, [
        'users/$uid/media/$id/thumb.jpg',
        'users/$uid/media/$id/original.jpg',
      ]);
      expect(await mediaDocCount(), 1);

      final row = await repo.byId(id);
      expect(row, isNotNull);
      expect(row!.uid, uid);
      expect(row.kind, 'image');
      expect(row.storagePath, 'users/$uid/media/$id/original.jpg');
      expect(row.thumbPath, 'users/$uid/media/$id/thumb.jpg');
      expect(row.thumbnail, isNotNull, reason: 'small thumb is blob-cached');
    });

    test('the Firestore document carries no download URL', () async {
      final outcome = await buildService().upload([await picked()]);
      final doc = await firestore
          .doc('users/$uid/media/${outcome.uploadedIds.single}')
          .get();

      // A download token is a bearer credential that no rule evaluates and that
      // never expires. Storing one replicates it into the unencrypted Firestore
      // SDK cache on every device the account touches.
      expect(doc.data()!.keys, isNot(contains('downloadUrl')));
      expect(doc.data()!.keys, isNot(contains('downloadURL')));
      expect(doc.data()!['storagePath'], isNotNull);
    });

    test('capturedAt is preserved so the timeline sorts by when it was taken',
        () async {
      final when = DateTime(2026, 3, 14);
      final outcome =
          await buildService().upload([await picked(capturedAt: when)]);
      expect((await repo.byId(outcome.uploadedIds.single))!.capturedAt, when);
    });
  });

  group('video', () {
    test('uploads with no thumbnail object and records its duration', () async {
      final outcome = await buildService().upload([
        await picked(
          contentType: 'video/mp4',
          duration: const Duration(seconds: 12),
        )
      ]);
      final id = outcome.uploadedIds.single;

      expect(blobs.uploads, ['users/$uid/media/$id/original.mp4']);
      final row = await repo.byId(id);
      expect(row!.kind, 'video');
      expect(row.thumbPath, isNull);
      expect(row.thumbnail, isNull);
      expect(row.durationMs, 12000);
    });
  });

  group('refusals write nothing anywhere', () {
    test('an over-cap file is rejected before any upload', () async {
      final outcome = await buildService()
          .upload([await picked(bytes: kMaxImageBytes + 1)]);

      expect(outcome.uploadedIds, isEmpty);
      expect(outcome.rejected.single.reason, MediaRefusal.tooLarge);
      expect(blobs.objects, isEmpty);
      expect(await mediaDocCount(), 0);
      expect(await repo.allFor(uid), isEmpty);
    });

    test('one bad file does not stop the good ones', () async {
      final outcome = await buildService().upload([
        await picked(bytes: kMaxImageBytes + 1),
        await picked(),
      ]);

      expect(outcome.rejected, hasLength(1));
      expect(outcome.uploadedIds, hasLength(1));
    });

    test('a pick over the count limit reports what was dropped', () async {
      final files = <PickedMedia>[];
      for (var i = 0; i < kMaxItemsPerPick + 2; i++) {
        files.add(await picked(bytes: 512 + i));
      }
      final outcome = await buildService().upload(files);

      expect(outcome.uploadedIds, hasLength(kMaxItemsPerPick));
      expect(outcome.dropped, 2);
    });
  });

  group('failure leaves no half-item', () {
    test('a failed original upload leaves no document and no row', () async {
      blobs.failOn = 'original';
      final outcome = await buildService().upload([await picked()]);

      expect(outcome.uploadedIds, isEmpty);
      expect(outcome.failed, 1);
      expect(await mediaDocCount(), 0);
      expect(await repo.allFor(uid), isEmpty);
    });

    test('bytes that land while the caller fails become a sweepable orphan',
        () async {
      // The exact window the orphan sweep exists for: the object is really in
      // the bucket, nothing points at it, and nothing else would ever find it.
      blobs.completeUploadThenFail = true;
      final outcome = await buildService().upload([await picked()]);

      expect(outcome.uploadedIds, isEmpty);
      expect(await mediaDocCount(), 0);
      expect(await repo.allFor(uid), isEmpty);
      // Discoverable by prefix, which is what makes it collectable.
      expect(await blobs.listItemIds('users/$uid/media'), hasLength(1));
    });
  });

  group('gates', () {
    test('signed out: nothing is uploaded', () async {
      trigger = await buildTrigger(null);
      final outcome = await buildService().upload([await picked()]);

      expect(outcome.blocked, MediaUploadBlock.notSignedIn);
      expect(blobs.objects, isEmpty);
    });

    test('a declined claim refuses the whole batch', () async {
      // The user chose "keep my data on this device only". Uploading their
      // photographs anyway would violate a consent decision they actually made.
      claim = const ClaimRecord(uid: uid, declined: true);
      trigger = await buildTrigger(uid);

      final outcome = await buildService().upload([await picked()]);

      expect(outcome.blocked, MediaUploadBlock.syncDeclined);
      expect(blobs.objects, isEmpty);
      expect(await mediaDocCount(), 0);
    });

    test('never uploads while the Settings tile says sync is off', () async {
      // The uploader must agree with `isSyncEnabledFor` — the predicate the
      // Settings sync tile renders from — rather than re-deriving "is this
      // device syncing?" from the two narrower facts it used to check.
      //
      // Forced through a subclass ON PURPOSE, and the reason is the point of
      // the test. Today every path that makes `isSyncEnabledFor` false ALSO
      // leaves the trigger `writesBlocked` or declined, so this state is not
      // reachable through `setUser` and a fixture cannot produce it. That is a
      // property of the current claim flow, not a guarantee of the upload
      // contract: anything that later clears `_pendingClaim` without enabling
      // sync would silently start uploading photographs while the app tells the
      // user their data stays on the device. This pins the contract to the
      // predicate so that change fails here instead of on someone's phone.
      trigger = _SyncOffTrigger(
        db,
        firestore: () => firestore,
        deviceId: () async => 'device-1',
        readClaim: () async => claim,
        writeClaim: (r) async => claim = r,
      );
      await trigger.setUser(uid);

      final outcome = await buildService().upload([await picked()]);

      expect(outcome.blocked, MediaUploadBlock.syncOff);
      expect(blobs.objects, isEmpty);
      expect(await mediaDocCount(), 0);
    });

    test('a pending account deletion refuses the whole batch', () async {
      await firestore
          .doc(AccountDeletionService.requestPath(uid))
          .set({'uid': uid});

      final outcome = await buildService().upload([await picked()]);

      expect(outcome.blocked, MediaUploadBlock.deletionPending);
      expect(blobs.objects, isEmpty);
    });

    test('a suspended trigger refuses the whole batch', () async {
      // suspend() promises the device is not writing to Firestore. An upload is
      // such a write, and it would land during the account-deletion sweep.
      await trigger.suspend();

      final outcome = await buildService().upload([await picked()]);

      expect(outcome.blocked, MediaUploadBlock.writesBlocked);
      expect(blobs.objects, isEmpty);
    });
  });

  group('account changes mid-upload', () {
    test('a completion after a sign-out writes no row', () async {
      final gate = Completer<void>();
      blobs.gate = gate;

      final service = buildService();
      final pending = service.upload([await picked()]);

      await Future<void>.delayed(Duration.zero);
      await trigger.setUser(null); // the user signs out mid-upload
      gate.complete();
      final outcome = await pending;

      // The bytes may already be in the bucket — that is what the sweep is for.
      // What must NOT happen is a row or a document appearing under an account
      // that is no longer signed in.
      expect(outcome.uploadedIds, isEmpty);
      expect(await repo.allFor(uid), isEmpty);
      expect(await mediaDocCount(), 0);
    });

    test('suspend() waits for an upload already in flight', () async {
      final gate = Completer<void>();
      blobs.gate = gate;

      final pending = buildService().upload([await picked()]);
      // Wait until the upload is genuinely parked on the gate. `uploads` is not
      // appended until after the gate releases, so it cannot be the signal.
      for (var i = 0; i < 100 && blobs.inFlight == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(blobs.inFlight, 1, reason: 'the upload should be mid-flight');

      var suspended = false;
      final suspending = trigger.suspend().then((_) => suspended = true);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(suspended, isFalse, reason: 'suspend must not return mid-upload');

      gate.complete();
      await pending;
      await suspending;
      expect(suspended, isTrue);
    });

    test('suspend makes an in-flight upload abandon itself', () async {
      // Falling out at the next epoch check is stronger than merely waiting:
      // the bytes may already be in the bucket, but no document and no row are
      // written, so the account-deletion sweep cannot be outlived by metadata
      // appearing after it ran.
      final gate = Completer<void>();
      blobs.gate = gate;

      final pending = buildService().upload([await picked()]);
      for (var i = 0; i < 100 && blobs.inFlight == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final suspending = trigger.suspend();
      gate.complete();
      final outcome = await pending;
      await suspending;

      expect(outcome.uploadedIds, isEmpty);
      expect(await mediaDocCount(), 0);
      expect(await repo.allFor(uid), isEmpty);
    });

    test('an upload that throws does not make suspend() throw', () async {
      // suspend() aborts an account deletion if it throws. Its bookkeeping copy
      // of the future is error-swallowed for exactly this case.
      blobs.failOn = 'original';
      final pending = buildService().upload([await picked()]);
      await pending;
      await expectLater(trigger.suspend(), completes);
    });
  });
}

/// A trigger that is signed in and not blocked, but is not syncing.
///
/// See the "never uploads while the Settings tile says sync is off" test: the
/// real claim flow cannot currently produce this combination, so the only
/// honest way to assert the uploader honours the predicate is to state it.
class _SyncOffTrigger extends SyncTrigger {
  _SyncOffTrigger(
    super.db, {
    required super.firestore,
    required super.deviceId,
    required super.readClaim,
    required super.writeClaim,
  });

  @override
  Future<bool> isSyncEnabledFor(String uid) async => false;
}
