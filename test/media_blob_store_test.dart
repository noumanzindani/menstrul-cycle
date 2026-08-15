import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'support/fake_media_blob_store.dart';

/// The blob-store contract, exercised through the fake every other media suite
/// depends on. If the fake's fault injection does not actually discriminate,
/// the tests built on it prove nothing — so it is pinned here.
void main() {
  late FakeMediaBlobStore store;
  late Directory tmp;

  setUp(() async {
    store = FakeMediaBlobStore();
    tmp = await Directory.systemTemp.createTemp('luna_media_test');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<File> tempFile(String name, int bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(List.filled(bytes, 3), flush: true);
    return f;
  }

  test('putBytes and getBytes round-trip', () async {
    await store.putBytes('p/thumb.jpg', Uint8List(64), 'image/jpeg');
    expect(store.objects['p/thumb.jpg'], 64);
    expect((await store.getBytes('p/thumb.jpg', maxBytes: 1024)).length, 64);
  });

  test('getBytes refuses to exceed its bound', () async {
    // The bound is what stops a rogue or mislabelled object being pulled whole
    // into memory on a low-end device.
    await store.putBytes('p/thumb.jpg', Uint8List(2048), 'image/jpeg');
    expect(() => store.getBytes('p/thumb.jpg', maxBytes: 1024), throwsStateError);
  });

  test('putFile streams a file in and downloadToFile streams it back out',
      () async {
    final src = await tempFile('src.mp4', 4096);
    await store.putFile('p/original.mp4', src, 'video/mp4');

    final dest = File('${tmp.path}/out.mp4');
    await store.downloadToFile('p/original.mp4', dest);
    expect(await dest.length(), 4096);
  });

  test('a missing object throws rather than returning empty', () async {
    expect(() => store.getBytes('nope', maxBytes: 10), throwsStateError);
  });

  test('delete removes the object and is recorded', () async {
    await store.putBytes('p/thumb.jpg', Uint8List(8), 'image/jpeg');
    await store.delete('p/thumb.jpg');
    expect(store.objects, isEmpty);
    expect(store.deleted, ['p/thumb.jpg']);
  });

  group('listItemIds', () {
    test('returns the item folders under a prefix, not the objects', () async {
      await store.putBytes('users/u1/media/aaa/original.jpg', Uint8List(1), 'image/jpeg');
      await store.putBytes('users/u1/media/aaa/thumb.jpg', Uint8List(1), 'image/jpeg');
      await store.putBytes('users/u1/media/bbb/original.mp4', Uint8List(1), 'video/mp4');

      expect(await store.listItemIds('users/u1/media'), ['aaa', 'bbb']);
    });

    test('is scoped to the prefix and never leaks another account', () async {
      await store.putBytes('users/u1/media/aaa/original.jpg', Uint8List(1), 'image/jpeg');
      await store.putBytes('users/u2/media/zzz/original.jpg', Uint8List(1), 'image/jpeg');

      expect(await store.listItemIds('users/u1/media'), ['aaa']);
    });

    test('an empty prefix lists nothing', () async {
      expect(await store.listItemIds('users/u1/media'), isEmpty);
    });
  });

  group('fault injection actually discriminates', () {
    test('failOn throws and stores nothing', () async {
      store.failOn = 'original';
      await expectLater(
        store.putBytes('p/original.jpg', Uint8List(4), 'image/jpeg'),
        throwsStateError,
      );
      expect(store.objects, isEmpty);

      // ...and leaves non-matching paths alone, which is what makes it a
      // discriminating knob rather than a global off switch.
      await store.putBytes('p/thumb.jpg', Uint8List(4), 'image/jpeg');
      expect(store.objects.keys, ['p/thumb.jpg']);
    });

    test('completeUploadThenFail LEAVES the object behind', () async {
      // This is the orphan. The object is really in the bucket and the caller
      // really saw an error, so no Firestore document will point at it.
      store.completeUploadThenFail = true;
      await expectLater(
        store.putBytes('users/u1/media/aaa/original.jpg', Uint8List(9),
            'image/jpeg'),
        throwsStateError,
      );
      expect(store.objects.containsKey('users/u1/media/aaa/original.jpg'), isTrue);
      expect(await store.listItemIds('users/u1/media'), ['aaa']);
    });

    test('gate holds an upload open until released', () async {
      store.gate = Completer<void>();
      var done = false;
      final upload = store
          .putBytes('p/original.jpg', Uint8List(4), 'image/jpeg')
          .then((_) => done = true);

      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse, reason: 'the upload must still be in flight');
      expect(store.objects, isEmpty);

      store.gate!.complete();
      await upload;
      expect(done, isTrue);
    });
  });
}
