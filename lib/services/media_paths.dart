/// Where a media item's bytes live in Cloud Storage, and the ids that get it
/// there. Pure — no plugin calls, no Firebase types.
///
/// ## The layout
///
/// ```
/// users/{uid}/media/{mediaId}/original.<ext>
/// users/{uid}/media/{mediaId}/thumb.jpg
/// ```
///
/// Three properties, each load-bearing:
///
/// 1. **`users/{uid}` first**, so the Storage rule is the byte-for-byte
///    analogue of `firestore.rules`' `isOwner()` — `request.auth.uid` compared
///    against the uid in the path, never a bare `request.auth != null`. In a
///    Firebase project shared with unrelated apps, "is signed in" is no
///    boundary at all; that argument is why `kLunaDatabaseId` exists, and it
///    applies harder here because these bytes are unencrypted.
/// 2. **A folder per item**, so deleting an item is a prefix operation derived
///    from the id alone, and the orphan sweep can list prefixes and diff them
///    against the Firestore document ids.
/// 3. **An opaque random id and a fixed file name.** Object paths appear in
///    Cloud Storage access logs, Cloud Audit Data Access logs and billing
///    exports. `functions/purge.js` already hashes uids before they reach Cloud
///    Logging for exactly this reason — "IMG_ultrasound_2026-03-04.heic" in a
///    log line would undo that effort entirely. The extension therefore comes
///    from the content type, never from the picked file's name.
library;

import 'dart:math';

import 'media_limits.dart';

final _rnd = Random.secure();

/// A fresh opaque media id: 128 random bits as 32 lowercase hex characters.
///
/// Random, never content-derived. A content hash would make the same photo
/// picked twice OVERWRITE the first object at the same path — which rotates
/// its download token and breaks anything already pointing at it.
///
/// This id is the Storage path segment AND the Firestore document id AND the
/// drift primary key, so nothing ever needs a lookup table, and it is chosen
/// BEFORE the upload starts so a crash mid-upload still leaves a path the
/// orphan sweep can reconstruct.
String newMediaId() => List<int>.generate(16, (_) => _rnd.nextInt(256))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

final _idPattern = RegExp(r'^[0-9a-f]{32}$');

void _validate(String uid, String mediaId) {
  if (uid.isEmpty || uid.contains('/')) {
    throw ArgumentError.value(uid, 'uid', 'must be a non-empty path segment');
  }
  if (!_idPattern.hasMatch(mediaId)) {
    // Rejects a filename, a date, and a traversal attempt in one check.
    throw ArgumentError.value(
        mediaId, 'mediaId', 'must be 32 lowercase hex characters');
  }
}

/// The prefix holding one item's objects. Also what the orphan sweep lists and
/// what a delete removes.
String mediaFolderPath({required String uid, required String mediaId}) {
  _validate(uid, mediaId);
  return 'users/$uid/media/$mediaId';
}

/// The full-size object's path. Throws if [contentType] is not accepted —
/// belt-and-braces behind [checkPickedFile], which refuses it first.
String originalObjectPath({
  required String uid,
  required String mediaId,
  required String contentType,
}) {
  final ext = extensionFor(contentType);
  if (ext == null) {
    throw ArgumentError.value(
        contentType, 'contentType', 'not an accepted media type');
  }
  return '${mediaFolderPath(uid: uid, mediaId: mediaId)}/original.$ext';
}

/// The thumbnail object's path. Always JPEG: the thumbnailer encodes JPEG
/// regardless of the original's type, so a HEIC photo still gets a thumbnail
/// every platform can decode.
String thumbObjectPath({required String uid, required String mediaId}) =>
    '${mediaFolderPath(uid: uid, mediaId: mediaId)}/thumb.jpg';
