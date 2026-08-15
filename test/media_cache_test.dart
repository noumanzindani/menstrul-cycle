import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/media_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late MediaCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('luna_cache_test');
    cache = MediaCache(
      directoryProvider: () async => Directory(p.join(root.path, 'media')),
      maxBytes: 1000,
    );
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Future<File> write(String id, String ext, int bytes, {DateTime? modified}) async {
    final f = await cache.fileFor(id, 'users/u/media/$id/original$ext');
    await f.writeAsBytes(List.filled(bytes, 1), flush: true);
    if (modified != null) await f.setLastModified(modified);
    return f;
  }

  group('fileFor', () {
    test('is deterministic and derives its extension from the object path',
        () async {
      final a = await cache.fileFor('abc', 'users/u/media/abc/original.mp4');
      final b = await cache.fileFor('abc', 'users/u/media/abc/original.mp4');
      expect(a.path, b.path);
      expect(p.basename(a.path), 'abc.mp4');
    });

    test('carries no user-chosen filename or caption', () async {
      final f = await cache.fileFor('abc', 'users/u/media/abc/original.jpg');
      expect(p.basename(f.path), 'abc.jpg');
    });

    test('creates the directory on demand', () async {
      await cache.fileFor('abc', 'x/original.jpg');
      expect(Directory(p.join(root.path, 'media')).existsSync(), isTrue);
    });
  });

  group('canHold', () {
    test('accepts a file that fits the budget', () {
      expect(cache.canHold(1000), isTrue);
    });

    test('refuses a file larger than the whole budget', () {
      // Writing it would trim it away immediately, so the download is waste.
      expect(cache.canHold(1001), isFalse);
    });
  });

  group('trim', () {
    test('does nothing while under the ceiling', () async {
      await write('a', '.jpg', 400);
      await write('b', '.jpg', 400);

      await cache.trim();

      expect(await cache.size(), 800);
    });

    test('drops the oldest first until it fits', () async {
      await write('old', '.jpg', 500,
          modified: DateTime.now().subtract(const Duration(days: 5)));
      await write('mid', '.jpg', 400,
          modified: DateTime.now().subtract(const Duration(days: 2)));
      await write('new', '.jpg', 400, modified: DateTime.now());

      await cache.trim();

      expect(await cache.size(), lessThanOrEqualTo(1000));
      final names = Directory(p.join(root.path, 'media'))
          .listSync()
          .map((e) => p.basenameWithoutExtension(e.path))
          .toSet();
      expect(names, contains('new'));
      expect(names, isNot(contains('old')));
    });
  });

  group('evict', () {
    test('removes one item and leaves the rest', () async {
      await write('a', '.jpg', 10);
      await write('b', '.mp4', 10);

      await cache.evict('a');

      final names = Directory(p.join(root.path, 'media'))
          .listSync()
          .map((e) => p.basenameWithoutExtension(e.path))
          .toList();
      expect(names, ['b']);
    });

    test('is a no-op for something not cached', () async {
      await write('a', '.jpg', 10);
      await expectLater(cache.evict('zzz'), completes);
      expect(await cache.size(), 10);
    });

    test('survives the directory not existing', () async {
      final fresh = MediaCache(
        directoryProvider: () async => Directory(p.join(root.path, 'nope')),
      );
      await expectLater(fresh.evict('a'), completes);
    });
  });

  group('clear', () {
    test('empties everything', () async {
      await write('a', '.jpg', 10);
      await write('b', '.mp4', 10);

      await cache.clear();

      expect(Directory(p.join(root.path, 'media')).existsSync(), isFalse);
    });

    test('does not recreate the directory as a side effect', () async {
      // clear() runs during "delete all my data". Leaving a fresh empty
      // directory behind is harmless but recreating it here would mean the wipe
      // itself touches the filesystem it just emptied.
      await cache.clear();
      expect(Directory(p.join(root.path, 'media')).existsSync(), isFalse);
    });

    test('is safe to call twice', () async {
      await write('a', '.jpg', 10);
      await cache.clear();
      await expectLater(cache.clear(), completes);
    });
  });
}
