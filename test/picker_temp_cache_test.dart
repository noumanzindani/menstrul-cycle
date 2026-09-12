import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/picker_temp_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory cache;

  setUp(() {
    cache = Directory.systemTemp.createTempSync('luna_picker_sweep');
  });
  tearDown(() {
    if (cache.existsSync()) cache.deleteSync(recursive: true);
  });

  /// Writes [bytes] bytes at [relative] under the fake cache directory.
  File write(String relative, int bytes) {
    final file = File(p.join(cache.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(bytes, 0));
    return file;
  }

  bool exists(String relative) =>
      File(p.join(cache.path, relative)).existsSync() ||
      Directory(p.join(cache.path, relative)).existsSync();

  // A real `UUID.randomUUID().toString()`, which is what FileUtils names the
  // directory it copies the ORIGINAL into.
  const uuid = '3f2b8c1a-9d4e-4a77-b0c3-5e6f7a8b9c0d';

  test('deletes the directory holding the full-resolution original', () async {
    write('$uuid/IMG_20260913.jpg', 4096);

    await sweepPickerTempFiles(cache);

    expect(exists(uuid), isFalse);
  });

  test('deletes the scaled copy left at the cache root', () async {
    write('scaled_IMG_20260913.jpg', 512);

    await sweepPickerTempFiles(cache);

    expect(exists('scaled_IMG_20260913.jpg'), isFalse);
  });

  test('leaves the app\'s own media cache alone', () async {
    write('luna_media/abc123.jpg', 1024);

    await sweepPickerTempFiles(cache);

    expect(
      exists('luna_media/abc123.jpg'),
      isTrue,
      reason: 'luna_media is a SIBLING of the picker temps and is managed by '
          'MediaCache.trim(); sweeping it here would evict downloads the '
          'viewer is about to read',
    );
  });

  test('leaves directories and files it does not own alone', () async {
    write('image_manager_disk_cache/a.0', 64); // Glide
    write('flutter_engine/shader.bin', 64);
    write('notes.txt', 64);
    // Right shape, wrong content: a non-hex character and a short group.
    write('3f2b8c1a-9d4e-4a77-b0c3-5e6f7a8b9cZZ/x.jpg', 64);
    write('3f2b8c1a-9d4e-4a77-b0c3-5e6f7a8b/x.jpg', 64);
    // `scaled_` must be a prefix, not a substring.
    write('rescaled_thing.jpg', 64);

    await sweepPickerTempFiles(cache);

    expect(exists('image_manager_disk_cache/a.0'), isTrue);
    expect(exists('flutter_engine/shader.bin'), isTrue);
    expect(exists('notes.txt'), isTrue);
    expect(exists('3f2b8c1a-9d4e-4a77-b0c3-5e6f7a8b9cZZ/x.jpg'), isTrue);
    expect(exists('3f2b8c1a-9d4e-4a77-b0c3-5e6f7a8b/x.jpg'), isTrue);
    expect(exists('rescaled_thing.jpg'), isTrue);
  });

  test('reports the bytes it reclaimed', () async {
    write('$uuid/IMG.jpg', 4096);
    write('scaled_IMG.jpg', 512);
    write('luna_media/kept.jpg', 9999);

    expect(await sweepPickerTempFiles(cache), 4608);
  });

  test('tolerates a cache directory that is not there', () async {
    cache.deleteSync(recursive: true);

    expect(await sweepPickerTempFiles(cache), 0);
  });
}
