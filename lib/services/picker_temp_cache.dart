import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The name `UUID.randomUUID().toString()` produces, which is what
/// `FileUtils.getPathFromUri` calls the directory it copies an original into.
///
/// Lowercase and exact-length on purpose. This pattern is the ONLY thing
/// standing between the sweep and the rest of the app's cache directory, so it
/// matches what the producer actually writes rather than anything uuid-ish.
final RegExp _pickerDirectory = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Prefix `ImageResizer.resizedImage` gives the downscaled copy it writes.
const String _scaledPrefix = 'scaled_';

/// Deletes the copies `image_picker` leaves behind, returning bytes reclaimed.
///
/// The plugin writes TWO files per picked image and cleans up neither:
///
/// - `<cache>/<uuid>/<original name>` — the file copied out of the content URI
///   at FULL resolution. `FileUtils` marks it `deleteOnExit()` and its own TODO
///   admits that does not work on Android.
/// - `<cache>/scaled_<original name>` — the downscaled copy, written at the
///   cache ROOT, not inside the uuid directory.
///
/// Only the second path is ever returned to Dart, so the app holds no reference
/// to the original and cannot delete it by path — the directory has to be
/// recognised by shape instead. One 123 MB pick took the app's cache to 124 MB
/// on a real device, and it stayed there.
///
/// The bytes matter beyond storage: these sit BESIDE `luna_media/`, so
/// `MediaCache.clear()` — sign-out, "Delete all my data", account deletion —
/// never reached them. A full-resolution copy of every photo the user ever
/// picked outlived every clearing flow the app offers.
///
/// Deliberately narrow: anything not matching [_pickerDirectory] or
/// [_scaledPrefix] is left where it is. The cache directory is shared with
/// Flutter, Glide and `luna_media`, and over-deleting here would evict a
/// download the viewer is about to read.
///
/// [cacheDir] defaults to the app cache directory — the same place the plugin's
/// `context.getCacheDir()` resolves to. Pass it explicitly to avoid the
/// platform channel under `flutter test`.
Future<int> sweepPickerTempFiles([Directory? cacheDir]) async {
  final dir = cacheDir ?? await getApplicationCacheDirectory();
  if (!await dir.exists()) return 0;

  var reclaimed = 0;
  await for (final entity in dir.list()) {
    final name = p.basename(entity.path);
    try {
      if (entity is Directory && _pickerDirectory.hasMatch(name)) {
        reclaimed += await _sizeOf(entity);
        await entity.delete(recursive: true);
      } else if (entity is File && name.startsWith(_scaledPrefix)) {
        reclaimed += await entity.length();
        await entity.delete();
      }
    } catch (_) {
      // Best effort. A file the OS still holds open is reclaimed on the next
      // sweep; failing the pick over cache hygiene would be the worse trade.
    }
  }
  return reclaimed;
}

Future<int> _sizeOf(Directory dir) async {
  var total = 0;
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}
