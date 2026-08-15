import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/media_repository.dart';
import 'account_deletion_service.dart';
import 'media_blob_store.dart';
import 'media_limits.dart';
import 'media_paths.dart';
import 'media_thumbnailer.dart';
import 'sync_trigger.dart';

/// One file chosen in the picker, already probed.
///
/// [duration] and the dimensions come from the caller because reading them
/// means touching a platform plugin (`video_player`'s container-header read),
/// which does not belong below this seam.
class PickedMedia {
  const PickedMedia({
    required this.file,
    required this.contentType,
    this.duration,
    this.capturedAt,
    this.width,
    this.height,
  });

  final File file;
  final String contentType;
  final Duration? duration;

  /// When the photo was taken, if the picker knew. Null falls back to now.
  final DateTime? capturedAt;
  final int? width;
  final int? height;
}

/// Why an entire batch was refused before anything was uploaded.
enum MediaUploadBlock {
  /// No signed-in account. Media is cloud-required; there is nowhere to put it.
  notSignedIn,

  /// The user chose "keep my data on this device only".
  syncDeclined,

  /// This account has a deletion request pending.
  deletionPending,

  /// An account deletion is sweeping right now (`SyncTrigger.suspend`).
  writesBlocked,

  /// This device is not syncing for this account, for a reason none of the
  /// narrower blocks above names.
  ///
  /// Device-found (2026-08-12), and the gap was not theoretical: with Settings
  /// showing "Cloud sync is off — your logs stay on this device only", the Add
  /// button was live and the upload reached the network. The batch came back
  /// `failed`, not `blocked`, which is only reachable once every gate has
  /// passed. It failed on the network, not on consent.
  ///
  /// The narrower checks are each true things that are not the whole question.
  /// `declinedUidOnRecord` answers "did they say no?", and an account with NO
  /// decision on record has not said no — yet nothing is syncing for it either.
  /// [SyncTrigger.isSyncEnabledFor] is the predicate the Settings tile itself
  /// renders from, so gating on it is what makes the tile and this feature
  /// incapable of disagreeing. Uploading photographs while the app states they
  /// stay on the device is a false privacy claim, which is the one failure this
  /// app treats as unshippable.
  syncOff,

  /// The account changed while the batch was in flight.
  accountChanged,
}

/// What one `upload` call did.
class MediaUploadOutcome {
  const MediaUploadOutcome({
    this.uploadedIds = const [],
    this.rejected = const [],
    this.dropped = 0,
    this.failed = 0,
    this.blocked,
  });

  /// Items that fully succeeded — bytes, document and local row.
  final List<String> uploadedIds;

  /// Files refused by the caps, with a reason each.
  final List<MediaRejection> rejected;

  /// Files trimmed by the per-pick count limit. Never leave this unreported.
  final int dropped;

  /// Files that passed the caps but failed to upload.
  final int failed;

  /// Set when the whole batch was refused before any work.
  final MediaUploadBlock? blocked;

  bool get isBlocked => blocked != null;
}

/// Uploads picked media, then records it locally.
///
/// ## Cloud-first, deliberately
///
/// Bytes → thumbnail object → Firestore document → drift row, in that order,
/// with the local row written LAST. A row therefore means "this item is fully
/// up there", which is what lets the timeline treat drift as the truth without
/// ever inventing a pending or failed state. There is no upload queue: a
/// failure leaves nothing behind locally, and the user simply picks again.
///
/// ## Why this is not part of SyncService
///
/// `SyncService.syncNow` advances `lastSyncedAt` and its pull cursors only on
/// full success, and its step ordering carries an explicit "do not reorder"
/// warning. Splicing media into it would mean an unreachable bucket, a rules
/// regression or one malformed media document could wedge DAILY-LOG sync — the
/// health data of record — indefinitely. Media is isolated so its failures stay
/// its own.
///
/// It is not, however, independent of [SyncTrigger]. Uploading writes to
/// Firestore, so it must honour the same gates every other write does, and
/// `suspend()` must be able to wait for it. Getting that wrong means an upload
/// landing during an account-deletion sweep and outliving it.
class MediaUploadService {
  MediaUploadService({
    required MediaRepository repo,
    required MediaBlobStore blobStore,
    required MediaThumbnailer thumbnailer,
    required FirebaseFirestore Function() firestore,
    required SyncTrigger trigger,
    required Future<String> Function() deviceId,
  })  : _repo = repo,
        _blobs = blobStore,
        _thumbs = thumbnailer,
        _firestore = firestore,
        _trigger = trigger,
        _deviceId = deviceId;

  final MediaRepository _repo;
  final MediaBlobStore _blobs;
  final MediaThumbnailer _thumbs;
  final FirebaseFirestore Function() _firestore;
  final SyncTrigger _trigger;
  final Future<String> Function() _deviceId;

  final Set<String> _inFlight = {};

  /// Ids whose objects are in the bucket right now but whose Firestore document
  /// may not be written yet.
  ///
  /// The orphan sweep must skip these, or it would delete the bytes of an
  /// upload still in progress — an object with no document is exactly what an
  /// in-flight upload looks like from the outside. Uploads are foreground-only
  /// (cloud-required, no queue), so an in-memory set covers every case that can
  /// arise within a process; anything left by a CRASH has no live uploader and
  /// is correctly collected on the next sweep.
  Set<String> get inFlightIds => Set.unmodifiable(_inFlight);

  /// Largest image read whole into memory to make a thumbnail.
  ///
  /// Bounded by [kMaxImageBytes], which the caps already enforce — this is the
  /// belt-and-braces half, because `readAsBytes` on an unbounded file is the
  /// single easiest way to OOM a low-end device.
  static const int _thumbSourceMaxBytes = kMaxImageBytes;

  Future<MediaUploadOutcome> upload(List<PickedMedia> files) {
    final run = _upload(files);
    // So `SyncTrigger.suspend()` waits for this. Registered around the WHOLE
    // batch, not per file, because the guarantee suspend needs is "nothing is
    // still writing", not "no individual file is".
    _trigger.registerOutstanding(run.then((_) {}));
    return run;
  }

  Future<MediaUploadOutcome> _upload(List<PickedMedia> files) async {
    final epoch = _trigger.epoch;
    final uid = _trigger.currentUid;
    if (uid == null) {
      return const MediaUploadOutcome(blocked: MediaUploadBlock.notSignedIn);
    }
    if (_trigger.writesBlocked) {
      // Covers both a suspended trigger and an outstanding claim question. The
      // decline case is reported separately below so the UI can explain it.
      final declined = await _trigger.declinedUidOnRecord();
      return MediaUploadOutcome(
        blocked: declined == uid
            ? MediaUploadBlock.syncDeclined
            : MediaUploadBlock.writesBlocked,
      );
    }
    if (await _trigger.declinedUidOnRecord() == uid) {
      return const MediaUploadOutcome(blocked: MediaUploadBlock.syncDeclined);
    }
    // Last and broadest: the same predicate the Settings sync tile renders
    // from. The two checks above are narrower, so each can be false while this
    // device is still not syncing — see [MediaUploadBlock.syncOff].
    if (!await _trigger.isSyncEnabledFor(uid)) {
      return const MediaUploadOutcome(blocked: MediaUploadBlock.syncOff);
    }

    // The same one-document read `SyncService.syncNow` makes, for the same
    // reason: it does not depend on this device's in-memory state, so a
    // deletion requested from another device stops uploads here too.
    final firestore = _firestore();
    final pending =
        await firestore.doc(AccountDeletionService.requestPath(uid)).get();
    if (pending.exists) {
      return const MediaUploadOutcome(blocked: MediaUploadBlock.deletionPending);
    }
    if (epoch != _trigger.epoch) {
      return const MediaUploadOutcome(blocked: MediaUploadBlock.accountChanged);
    }

    final limited = applyPickLimit(files);
    final deviceId = await _deviceId();

    final uploaded = <String>[];
    final rejected = <MediaRejection>[];
    var failed = 0;

    for (final item in limited.accepted) {
      final bytes = await item.file.length();
      final rejection = checkPickedFile(
        contentType: item.contentType,
        bytes: bytes,
        duration: item.duration,
      );
      if (rejection != null) {
        rejected.add(rejection);
        continue;
      }
      // Re-checked before EVERY item, not just once: a batch of ten videos can
      // run for minutes, and the account can change at any point in it.
      if (epoch != _trigger.epoch) {
        return MediaUploadOutcome(
          uploadedIds: uploaded,
          rejected: rejected,
          dropped: limited.dropped,
          failed: failed,
          blocked: MediaUploadBlock.accountChanged,
        );
      }

      final ok = await _uploadOne(
        item: item,
        bytes: bytes,
        uid: uid,
        epoch: epoch,
        deviceId: deviceId,
        firestore: firestore,
      );
      if (ok == null) {
        failed++;
      } else {
        uploaded.add(ok);
      }
    }

    return MediaUploadOutcome(
      uploadedIds: uploaded,
      rejected: rejected,
      dropped: limited.dropped,
      failed: failed,
    );
  }

  /// Returns the new id, or null if anything failed.
  ///
  /// All-or-nothing from the app's point of view: a failure at any step leaves
  /// no document and no row. It may leave BYTES — an object whose metadata
  /// write never happened — which is precisely what the orphan sweep collects.
  /// That residue is unavoidable without a two-phase commit across two
  /// services; making it *discoverable* (a path derived from an id chosen up
  /// front) is the design.
  Future<String?> _uploadOne({
    required PickedMedia item,
    required int bytes,
    required String uid,
    required int epoch,
    required String deviceId,
    required FirebaseFirestore firestore,
  }) async {
    final kind = mediaKindFor(item.contentType)!;
    // Chosen BEFORE the first upload, so every object this call creates lives
    // under one prefix the sweep can reconstruct from the id alone.
    final id = newMediaId();
    final originalPath = originalObjectPath(
      uid: uid,
      mediaId: id,
      contentType: item.contentType,
    );

    _inFlight.add(id);
    try {
      String? thumbPath;
      Uint8List? thumbBytes;
      if (kind == MediaKind.image) {
        // Video posters are not attempted in v1 — see MediaThumbnailer.
        final source = bytes <= _thumbSourceMaxBytes
            ? await item.file.readAsBytes()
            : null;
        thumbBytes = source == null ? null : await _thumbs.generate(source);
        if (thumbBytes != null) {
          thumbPath = thumbObjectPath(uid: uid, mediaId: id);
          await _blobs.putBytes(thumbPath, thumbBytes, 'image/jpeg');
        }
      }

      // Streamed, never read into memory: a 150 MB video through putData would
      // be ~300 MB of transient allocation.
      await _blobs.putFile(originalPath, item.file, item.contentType);

      if (epoch != _trigger.epoch) return null;

      final capturedAt = item.capturedAt ?? DateTime.now();
      final now = DateTime.now();
      await firestore.doc('users/$uid/media/$id').set({
        'id': id,
        'kind': kind.name,
        'storagePath': originalPath,
        'thumbPath': ?thumbPath,
        'bytes': bytes,
        'width': ?item.width,
        'height': ?item.height,
        'durationMs': ?item.duration?.inMilliseconds,
        'capturedAt': capturedAt.millisecondsSinceEpoch,
        'createdAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
        'deviceId': deviceId,
        // Server clock, so pulls can be scoped by a cursor that no device's
        // wall clock can skew. Same field and same reasoning as SyncService.
        'syncedAt': FieldValue.serverTimestamp(),
      });

      if (epoch != _trigger.epoch) return null;

      await _repo.upsert(
        id: id,
        uid: uid,
        kind: kind,
        storagePath: originalPath,
        thumbPath: thumbPath,
        bytes: bytes,
        width: item.width,
        height: item.height,
        durationMs: item.duration?.inMilliseconds,
        capturedAt: capturedAt,
        thumbnail: MediaThumbnailer.blobFor(thumbBytes),
        updatedAt: now,
      );
      return id;
    } catch (_) {
      // Swallowed on purpose: one unreadable file or one dropped connection
      // must not abandon the rest of the batch. The count surfaces in
      // [MediaUploadOutcome.failed] and the caller tells the user.
      return null;
    } finally {
      _inFlight.remove(id);
    }
  }
}
