import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Ceiling for downloaded full-size media held on disk.
///
/// Every file here is re-downloadable, so this is a convenience budget, not
/// storage the user owns. 256 MB is roughly two capped videos plus a working
/// set of photos.
const int kMediaCacheMaxBytes = 256 * 1024 * 1024;

/// Full-size media downloaded for viewing, held as plain files.
///
/// ## This directory is NOT encrypted, and that is a deliberate trade
///
/// Everything else the app stores at rest sits inside the sqlite3mc-encrypted
/// database. These files do not, because `video_player` needs a real, readable
/// path — encrypting them would mean decrypting a 150 MB video to a temp file
/// before playback, which reintroduces the plaintext copy AND costs the time
/// and space twice.
///
/// What limits the exposure instead:
///
/// - it lives in the app-private cache directory, so another app cannot read it
///   on a non-rooted device, and the OS may evict it under storage pressure —
///   correct semantics for content that can always be fetched again;
/// - `android:allowBackup="false"` is already set, so none of it reaches
///   Android Auto Backup (do not "fix" that flag without revisiting this);
/// - [clear] runs on sign-out, on "Delete all my data" and on an account
///   deletion request.
///
/// The bucket copy is unencrypted too, so this does not widen the trust
/// boundary — it just means the honest thing to say is that media is protected
/// by the account, not by encryption. Thumbnails are different and DO stay
/// inside the encrypted database (`MediaItems.thumbnail`), because they are
/// small enough that nothing is lost by it.
class MediaCache {
  MediaCache({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = kMediaCacheMaxBytes,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final Future<Directory> Function() _directoryProvider;
  final int maxBytes;

  static const String _folderName = 'luna_media';

  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationCacheDirectory();
    return Directory(p.join(base.path, _folderName));
  }

  Future<Directory> _dir() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Where [mediaId]'s bytes live, whether or not they are there yet.
  ///
  /// The name is derived from the id and the remote object's extension, so it
  /// carries no filename the user chose and no caption — the same reasoning
  /// that keeps those out of Storage object paths.
  Future<File> fileFor(String mediaId, String storagePath) async {
    final dir = await _dir();
    final ext = p.extension(storagePath); // includes the dot, or empty
    return File(p.join(dir.path, '$mediaId$ext'));
  }

  /// Whether a file of [bytes] can be held at all.
  ///
  /// A single item larger than the whole budget would be written and then
  /// immediately trimmed away, so the download is pure waste — better to stream
  /// it straight to the viewer and keep nothing.
  bool canHold(int bytes) => bytes <= maxBytes;

  /// Total bytes currently cached.
  Future<int> size() async {
    final dir = await _dir();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Drops the least recently modified files until the total fits [maxBytes].
  ///
  /// Modification time is the proxy for use: reads do not update it, so a file
  /// viewed repeatedly but never rewritten still ages out. That is acceptable
  /// for a re-downloadable cache and avoids maintaining a parallel access log.
  Future<void> trim() async {
    final dir = await _dir();
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) files.add(entity);
    }
    var total = 0;
    for (final f in files) {
      total += await f.length();
    }
    if (total <= maxBytes) return;

    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    for (final f in files) {
      if (total <= maxBytes) break;
      final len = await f.length();
      try {
        await f.delete();
        total -= len;
      } catch (_) {}
    }
  }

  /// Removes one item's cached bytes. Called when it is deleted anywhere.
  Future<void> evict(String mediaId) async {
    final dir = await _dir();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && p.basenameWithoutExtension(entity.path) == mediaId) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  /// Empties the cache.
  ///
  /// Belongs to the CALLERS of `AppDatabase.deleteAllData()`, not inside it:
  /// that method is a pure drift transaction run against in-memory databases in
  /// tests, where `path_provider` has no platform channel. It must run BEFORE
  /// `clearLunaFirestoreCache()`, which has to stay the last Firestore call in
  /// any flow that uses it.
  Future<void> clear() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) return;
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}
