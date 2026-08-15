import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'storage_ref.dart';

/// Reading and writing media bytes. **This is the only file in `lib/` that may
/// import `package:firebase_storage`** — a structural test enforces it.
///
/// Everything above this seam (upload, sync, the timeline) is driven in tests
/// by an in-memory implementation, which is what keeps ~700 widget tests
/// runnable with no initialized Firebase app. `lunaStorage()` throws without
/// one, so removing the seam would not "simplify" anything; it would make the
/// media feature untestable.
abstract class MediaBlobStore {
  /// Uploads small in-memory bytes (thumbnails). Never a video: `putData` holds
  /// the whole payload in RAM.
  Future<void> putBytes(String path, Uint8List bytes, String contentType);

  /// Uploads a file by streaming it. The only way full-size media goes up.
  Future<void> putFile(String path, File file, String contentType);

  /// Downloads an object into memory, bounded. For thumbnails and images only.
  Future<Uint8List> getBytes(String path, {required int maxBytes});

  /// Streams an object to [dest]. How video reaches a playable local path.
  Future<void> downloadToFile(String path, File dest);

  Future<void> delete(String path);

  /// The item ids (folder names) directly under [prefix], for the orphan sweep.
  Future<List<String>> listItemIds(String prefix);

  /// The object paths directly under [prefix].
  ///
  /// Separate from [listItemIds] because Cloud Storage listing is not
  /// recursive: one call yields either the sub-prefixes or the objects at that
  /// level, never the whole tree. The sweep needs both — ids to diff, then the
  /// actual objects inside an orphaned folder so it deletes what is really
  /// there rather than guessing at extensions.
  Future<List<String>> listObjectPaths(String prefix);
}

/// The production implementation, against the dedicated LunaTrack bucket.
class FirebaseMediaBlobStore implements MediaBlobStore {
  FirebaseMediaBlobStore({FirebaseStorage? storage})
      : _storage = storage ?? lunaStorage() {
    // ────────────────────────────────────────────────────────────────────────
    // THIS LINE IS LOAD-BEARING. Do not remove it as a "default anyway".
    //
    // firebase_storage retries a failed upload for **10 minutes** by default.
    // Left alone, an upload started with no connection sits there retrying
    // while the user stares at a spinner, and may still succeed long after
    // they gave up and walked away.
    //
    // That is an offline upload queue. The media feature is deliberately
    // cloud-required WITHOUT one — no pending state, no failed state, no
    // retry: an item exists only once its upload has succeeded. A queue that
    // arrives as a library default is the worst version of the thing we chose
    // not to build, because it has no UI, no cancel and no visibility.
    //
    // Twenty seconds is long enough to ride out a brief blip on a live
    // connection and short enough that "you are offline" is an answer rather
    // than a wait. It is also why there is no connectivity probe anywhere in
    // this feature: a pre-flight ping can succeed while the upload still
    // fails, so the bounded attempt IS the check.
    // ────────────────────────────────────────────────────────────────────────
    _storage.setMaxUploadRetryTime(const Duration(seconds: 20));
    _storage.setMaxOperationRetryTime(const Duration(seconds: 20));
  }

  final FirebaseStorage _storage;

  /// Content type is the ONLY metadata sent.
  ///
  /// `storage.rules` refuses any object carrying client custom metadata,
  /// because `firebaseStorageDownloadTokens` lives there: a client able to
  /// write it can mint a permanent, rules-bypassing bearer URL for the object
  /// at upload time. Do not add a `customMetadata:` argument here — the real
  /// metadata belongs in Firestore, under a validated shape.
  SettableMetadata _meta(String contentType) =>
      SettableMetadata(contentType: contentType);

  @override
  Future<void> putBytes(String path, Uint8List bytes, String contentType) async {
    await _storage.ref(path).putData(bytes, _meta(contentType));
  }

  @override
  Future<void> putFile(String path, File file, String contentType) async {
    await _storage.ref(path).putFile(file, _meta(contentType));
  }

  @override
  Future<Uint8List> getBytes(String path, {required int maxBytes}) async {
    // getData, NOT getDownloadURL. A download URL carries a token that is a
    // bearer credential: it is not evaluated against security rules, does not
    // expire, and works for anyone holding the string — so one leak into a log
    // line, a crash report or the unencrypted Firestore SDK cache is a
    // permanent public link to an intimate photograph. getData authenticates
    // every request and mints nothing. `grep getDownloadURL lib/` must return
    // nothing; a structural test asserts it.
    final bytes = await _storage.ref(path).getData(maxBytes);
    if (bytes == null) {
      throw StateError('No bytes at $path');
    }
    return bytes;
  }

  @override
  Future<void> downloadToFile(String path, File dest) async {
    await _storage.ref(path).writeToFile(dest);
  }

  @override
  Future<void> delete(String path) => _storage.ref(path).delete();

  @override
  Future<List<String>> listItemIds(String prefix) async {
    // Each item is a folder (`…/media/{id}/original.jpg` + `thumb.jpg`), so the
    // ids are the sub-prefixes, not the objects.
    final result = await _storage.ref(prefix).listAll();
    return result.prefixes.map((r) => r.name).toList();
  }

  @override
  Future<List<String>> listObjectPaths(String prefix) async {
    final result = await _storage.ref(prefix).listAll();
    return result.items.map((r) => r.fullPath).toList();
  }
}

/// Used when there is no Firebase app — the local-only hatch.
///
/// Mirrors `UnavailableAuthService`. Every call throws, and that is correct
/// rather than defensive: the media timeline is hidden entirely when Firebase
/// is unavailable, so reaching one of these methods means an entry point
/// escaped its gate, and a loud failure is how that gets found.
class UnavailableMediaBlobStore implements MediaBlobStore {
  const UnavailableMediaBlobStore();

  Never _unavailable() =>
      throw StateError('Cloud storage is unavailable on this device.');

  @override
  Future<void> putBytes(String path, Uint8List bytes, String contentType) async =>
      _unavailable();
  @override
  Future<void> putFile(String path, File file, String contentType) async =>
      _unavailable();
  @override
  Future<Uint8List> getBytes(String path, {required int maxBytes}) async =>
      _unavailable();
  @override
  Future<void> downloadToFile(String path, File dest) async => _unavailable();
  @override
  Future<void> delete(String path) async => _unavailable();
  @override
  Future<List<String>> listItemIds(String prefix) async => _unavailable();
  @override
  Future<List<String>> listObjectPaths(String prefix) async => _unavailable();
}
