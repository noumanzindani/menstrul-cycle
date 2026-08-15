import 'package:cloud_firestore/cloud_firestore.dart';

import '../data/media_repository.dart';
import 'media_blob_store.dart';
import 'media_limits.dart';
import 'media_paths.dart';

/// Brings one account's media metadata down to this device, propagates
/// deletions, and collects orphaned bytes.
///
/// ## Why this is not part of SyncService
///
/// `SyncService.syncNow` advances `lastSyncedAt` and its cursors only on FULL
/// success, and its step ordering carries a "do not reorder" warning earned the
/// hard way. Splicing media into it means an unreachable bucket, a rules
/// regression, or one malformed media document can wedge daily-log sync — the
/// health data of record — indefinitely. Media failures stay media failures.
///
/// ## What it borrows rather than reinvents
///
/// The cursor discipline, verbatim: pulls resume from the greatest SERVER
/// `syncedAt` this device has actually observed, never from a device clock.
/// `sync_service.dart`'s `_readPullCursors` explains why at length — a device
/// running ahead of the server would otherwise skip every peer write in that
/// window, silently and permanently. Media gets its OWN cursor key for the same
/// reason the log and deletion cursors are separate: a shared cursor advanced
/// across two queries can jump past a document written between them.
class MediaSyncService {
  MediaSyncService({
    required MediaRepository repo,
    required MediaBlobStore blobStore,
    required FirebaseFirestore firestore,
    required String uid,
    required String deviceId,
    Future<void> Function(String mediaId)? evictCache,
  })  : _repo = repo,
        _blobs = blobStore,
        _firestore = firestore,
        _uid = uid,
        _deviceId = deviceId,
        _evictCache = evictCache;

  final MediaRepository _repo;
  final MediaBlobStore _blobs;
  final FirebaseFirestore _firestore;
  final String _uid;
  final String _deviceId;

  /// Removes an item's downloaded bytes from the on-disk cache. Injected
  /// because the cache is file I/O, which does not belong in a class whose
  /// tests run against an in-memory database.
  final Future<void> Function(String mediaId)? _evictCache;

  /// How long a deletion marker is kept before it is pruned.
  ///
  /// The same 180 days `SyncService` uses for day deletions, and for the same
  /// reason: a marker has to outlive any device that might still be offline
  /// holding the deleted item, but keeping them forever grows a collection that
  /// every pull reads.
  static const Duration markerRetention = Duration(days: 180);

  CollectionReference<Map<String, dynamic>> get _remote =>
      _firestore.collection('users/$_uid/media');

  DocumentReference<Map<String, dynamic>> get _deviceDoc =>
      _firestore.doc('users/$_uid/devices/$_deviceId');

  String get _storagePrefix => 'users/$_uid/media';

  /// Applies everything the server has that this device has not seen.
  ///
  /// [fullSweep] ignores the cursor — used after a local wipe, when a cursor no
  /// longer describes what this device holds.
  Future<void> pull({bool fullSweep = false}) async {
    final previous = fullSweep ? null : await _readCursor();

    Query<Map<String, dynamic>> query = _remote.orderBy('syncedAt');
    if (previous != null) {
      query = query.where('syncedAt', isGreaterThan: previous);
    }

    final snapshot = await query.get();
    Timestamp? observed;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final syncedAt = data['syncedAt'];
      if (syncedAt is Timestamp &&
          (observed == null || syncedAt.compareTo(observed) > 0)) {
        observed = syncedAt;
      }

      if (data['deletedAt'] != null) {
        // A tombstone. The item is gone everywhere; drop the local replica and
        // its cached bytes. Deleting the row is safe even if it was never here.
        await _repo.deleteById(doc.id);
        await _evictCache?.call(doc.id);
        continue;
      }

      final kind = data['kind'] == 'video' ? MediaKind.video : MediaKind.image;
      await _repo.upsert(
        id: doc.id,
        uid: _uid,
        kind: kind,
        storagePath: data['storagePath'] as String,
        thumbPath: data['thumbPath'] as String?,
        bytes: (data['bytes'] as num?)?.toInt() ?? 0,
        width: (data['width'] as num?)?.toInt(),
        height: (data['height'] as num?)?.toInt(),
        durationMs: (data['durationMs'] as num?)?.toInt(),
        caption: data['caption'] as String?,
        capturedAt: _millis(data['capturedAt']),
        updatedAt: _millis(data['updatedAt']),
        // Deliberately NOT carried down: the thumbnail blob is a per-device
        // render cache, filled by the tile when it first fetches thumbPath.
        // Shipping bytes through Firestore would put imagery in the
        // unencrypted SDK cache on every device.
      );
    }

    // Only after every document applied cleanly. A cursor advanced past a
    // document that failed to apply would skip it forever.
    await _writeCursor(observed, previous);
  }

  /// Fills in missing thumbnail blobs by fetching each item's `thumbPath`.
  ///
  /// The blob is a per-device render cache, so a second device pulls metadata
  /// with no imagery and would otherwise show an empty grid until every
  /// full-size original had been downloaded. Fetching the small thumb object
  /// instead is the difference between a few KB per tile and several MB.
  ///
  /// Bounded and best-effort: [limit] caps one pass so opening the screen never
  /// turns into a hundred sequential requests, and a failure on one item leaves
  /// its tile on the neutral placeholder rather than failing the screen.
  Future<int> hydrateThumbnails({int limit = 24}) async {
    final items = await _repo.allFor(_uid);
    var filled = 0;
    for (final item in items) {
      if (filled >= limit) break;
      final path = item.thumbPath;
      if (item.thumbnail != null || path == null) continue;
      try {
        final bytes = await _blobs.getBytes(path, maxBytes: _thumbFetchMaxBytes);
        await _repo.setThumbnail(item.id, bytes);
        filled++;
      } catch (_) {
        // A 404 here is expected and transient by design: `delete` writes the
        // tombstone BEFORE removing bytes, so a thumb can vanish under a pull
        // that has not applied the tombstone yet.
      }
    }
    return filled;
  }

  /// Hard bound on a thumbnail fetch. Comfortably above the ~25 KB a 320px JPEG
  /// encodes to, and far below anything that could pressure memory.
  static const int _thumbFetchMaxBytes = 512 * 1024;

  /// Deletes one item everywhere.
  ///
  /// Order is remote-first, and it is the same reasoning as
  /// `SyncService._pushTombstones`: a failure must leave a state the user can
  /// retry, not bytes that nothing points at. Concretely — marker, then bytes,
  /// then the local row. A crash after the marker leaves objects with a
  /// tombstone pointing at them, which the sweep collects; a crash before it
  /// leaves the item intact and the user taps delete again.
  Future<void> delete(String mediaId) async {
    final item = await _repo.byId(mediaId);

    // A REPLACE, not an update: this scrubs the caption, capture date and paths
    // from the server in the same write that records the deletion. A separate
    // `deletions` subcollection (as day-logs use) would be the wrong shape here
    // — that exists because a `deleted` flag would force a filter onto every
    // read path, and media has exactly one.
    await _remote.doc(mediaId).set({
      'id': mediaId,
      'deletedAt': DateTime.now().millisecondsSinceEpoch,
      'syncedAt': FieldValue.serverTimestamp(),
    });

    if (item != null) {
      await _deleteObjectsFor(item.storagePath, item.thumbPath);
    }

    await _repo.deleteById(mediaId);
    await _evictCache?.call(mediaId);
  }

  Future<void> _deleteObjectsFor(String storagePath, String? thumbPath) async {
    // Individually try/caught: a missing object is a SUCCESS for a delete, and
    // failing the whole operation over one would strand the other.
    for (final path in [storagePath, ?thumbPath]) {
      try {
        await _blobs.delete(path);
      } catch (_) {}
    }
  }

  /// Deletes bucket objects that no metadata document points at.
  ///
  /// This is the entire reason "no pending state" is honest. Uploading is two
  /// steps against two different services — bytes, then document — and a crash
  /// or a lost connection between them leaves an object nothing lists, nothing
  /// renders, and nothing would ever erase, including "delete my account". A
  /// stateless reconciliation collects it without needing the pending/failed
  /// table the design deliberately does not have.
  ///
  /// [skipIds] must contain every id currently uploading
  /// (`MediaUploadService.inFlightIds`) — mid-upload is indistinguishable from
  /// orphaned when all you can see is "object exists, document does not".
  Future<int> sweepOrphans({Set<String> skipIds = const {}}) async {
    final List<String> remoteIds;
    try {
      remoteIds = await _blobs.listItemIds(_storagePrefix);
    } catch (_) {
      return 0; // a sweep is opportunistic; never let it break opening a screen
    }
    if (remoteIds.isEmpty) return 0;

    // Compared against FIRESTORE, not the local table: a device that has simply
    // not pulled yet holds no rows, and sweeping against that would delete the
    // user's entire library.
    final docs = await _remote.get();
    final known = docs.docs.map((d) => d.id).toSet();

    var deleted = 0;
    for (final id in remoteIds) {
      if (known.contains(id) || skipIds.contains(id)) continue;
      // List the folder rather than guessing names: the extension came from the
      // uploader's content type and is not recoverable from an id.
      final folder = mediaFolderPath(uid: _uid, mediaId: id);
      List<String> paths;
      try {
        paths = await _blobs.listObjectPaths(folder);
      } catch (_) {
        continue;
      }
      for (final path in paths) {
        try {
          await _blobs.delete(path);
        } catch (_) {}
      }
      deleted++;
    }
    return deleted;
  }

  /// Removes deletion markers old enough that no device can still need them.
  Future<void> pruneOldMarkers({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(markerRetention);
    final snapshot = await _remote.get();
    for (final doc in snapshot.docs) {
      final deletedAt = doc.data()['deletedAt'];
      if (deletedAt is! num) continue;
      if (DateTime.fromMillisecondsSinceEpoch(deletedAt.toInt())
          .isBefore(cutoff)) {
        await doc.reference.delete();
      }
    }
  }

  Future<Timestamp?> _readCursor() async {
    final data = (await _deviceDoc.get()).data();
    final value = data?['mediaCursor'];
    return value is Timestamp ? value : null;
  }

  Future<void> _writeCursor(Timestamp? observed, Timestamp? previous) async {
    if (observed == null) return;
    if (previous != null && observed.compareTo(previous) == 0) return;
    // merge:true — the same device document already holds logsCursor and
    // deletionsCursor, and a third key has to coexist with them.
    await _deviceDoc.set({'mediaCursor': observed}, SetOptions(merge: true));
  }

  static DateTime _millis(Object? value) => value is num
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : DateTime.fromMillisecondsSinceEpoch(0);
}
