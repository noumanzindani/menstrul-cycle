import 'package:drift/drift.dart';

import '../db/database.dart';
import '../services/media_limits.dart';
import '../services/media_thumbnailer.dart';

/// All reads/writes for the media timeline's LOCAL replica.
///
/// Every read is scoped by uid. That is not defensive habit: media is
/// cloud-required, so a row exists only because it was uploaded under one
/// account, and signing out deliberately does not wipe the device. Without the
/// filter, signing in as somebody else would render the previous account's
/// cached thumbnails — photographs — inside the new account's timeline.
///
/// This class never talks to Cloud Storage or Firestore. Uploads and pulls go
/// through `MediaUploadService` / `MediaSyncService`, which call in here once
/// the remote side has already succeeded. Keeping that direction one-way is
/// what lets every widget test drive the timeline from an in-memory database
/// with no Firebase app.
class MediaRepository {
  MediaRepository(this._db);
  final AppDatabase _db;

  /// One account's items, newest capture first.
  ///
  /// `capturedAt` descending is the timeline order (a photo taken in March
  /// belongs in March even if it was uploaded in August). The `id` tiebreak is
  /// what keeps the order STABLE: a burst of photos can share a capture second,
  /// and SQLite is free to return equal keys in any order, so without it the
  /// grid can reshuffle between rebuilds.
  Future<List<MediaItem>> allFor(String uid) => (_db.select(_db.mediaItems)
        ..where((t) => t.uid.equals(uid))
        ..orderBy([
          (t) => OrderingTerm(expression: t.capturedAt, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.id),
        ]))
      .get();

  Future<MediaItem?> byId(String id) =>
      (_db.select(_db.mediaItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// The ids this device believes [uid] owns.
  ///
  /// The orphan sweep diffs a Storage prefix listing against this set: an
  /// object whose id is missing here has no metadata pointing at it, which is
  /// what a crash between "bytes uploaded" and "document written" leaves
  /// behind.
  Future<Set<String>> idsFor(String uid) async {
    final rows = await (_db.selectOnly(_db.mediaItems)
          ..addColumns([_db.mediaItems.id])
          ..where(_db.mediaItems.uid.equals(uid)))
        .get();
    return rows.map((r) => r.read(_db.mediaItems.id)!).toSet();
  }

  /// Inserts or replaces one item.
  ///
  /// Idempotent by [id] because that is what a pull needs: re-applying an
  /// unchanged remote document must not grow the table. [id] is the drift
  /// primary key, the Firestore document id and the Storage path segment all at
  /// once, so "same item" needs no other comparison.
  Future<void> upsert({
    required String id,
    required String uid,
    required MediaKind kind,
    required String storagePath,
    required DateTime capturedAt,
    String? thumbPath,
    int bytes = 0,
    int? width,
    int? height,
    int? durationMs,
    String? caption,
    Uint8List? thumbnail,
    DateTime? updatedAt,
  }) async {
    await _db.into(_db.mediaItems).insertOnConflictUpdate(
          MediaItemsCompanion.insert(
            id: id,
            uid: uid,
            kind: kind.name,
            storagePath: storagePath,
            capturedAt: capturedAt,
            thumbPath: Value(thumbPath),
            bytes: Value(bytes),
            width: Value(width),
            height: Value(height),
            durationMs: Value(durationMs),
            caption: Value(caption),
            thumbnail: Value(thumbnail),
            updatedAt: Value(updatedAt ?? DateTime.now()),
          ),
        );
  }

  /// Stores a fetched thumbnail against an existing row.
  ///
  /// Single-column, so it cannot disturb metadata a pull may have just written.
  /// Silently does nothing if the row has since been deleted, which is the
  /// right outcome — the thumbnail was for an item that no longer exists.
  Future<void> setThumbnail(String id, Uint8List bytes) async {
    if (bytes.length > kThumbBlobMaxBytes) return;
    await (_db.update(_db.mediaItems)..where((t) => t.id.equals(id)))
        .write(MediaItemsCompanion(thumbnail: Value(bytes)));
  }

  /// Removes one item's row and its cached thumbnail blob.
  ///
  /// Callers delete the REMOTE side first (see `MediaSyncService.delete`): a
  /// failure then leaves a row still pointing at bytes that exist, which the
  /// user can retry, rather than bytes with nothing pointing at them, which
  /// nothing enumerates and nothing ever erases.
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.mediaItems)..where((t) => t.id.equals(id))).go();
  }

  /// Drops every row that does not belong to [uid]; pass null to drop them all.
  ///
  /// Runs on an account change and on sign-out. The uid filter on every read
  /// already makes another account's rows invisible — this is what stops their
  /// thumbnails from sitting on disk regardless.
  Future<void> deleteExcept(String? uid) async {
    final q = _db.delete(_db.mediaItems);
    if (uid != null) q.where((t) => t.uid.equals(uid).not());
    await q.go();
  }
}
