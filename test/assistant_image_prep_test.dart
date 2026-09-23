import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/assistant_image_prep.dart';
import 'package:menstrul_track/services/media_analysis.dart';

/// The screen-layer downscale every assistant photo goes through before it is
/// inlined. The encoder is injected: `flutter_image_compress` is a native
/// plugin and returns nothing under `flutter_tester`.
void main() {
  late List<({int maxEdge, int quality})> encodes;
  late int loads;

  AssistantImagePrep prep({bool fail = false, bool empty = false}) =>
      AssistantImagePrep(
        encoder: (source, {required maxEdge, required quality}) async {
          encodes.add((maxEdge: maxEdge, quality: quality));
          if (fail) throw StateError('codec');
          return empty ? Uint8List(0) : Uint8List(10);
        },
      );

  Future<(Uint8List, String)> Function() source(int bytes,
          [String mime = 'image/png']) =>
      () async {
        loads++;
        return (Uint8List(bytes), mime);
      };

  setUp(() {
    encodes = [];
    loads = 0;
  });

  test('downscales to a 1024px JPEG at quality 80', () async {
    final out = await prep().prepare('m1', source(5000));

    expect(encodes, [(maxEdge: 1024, quality: 80)]);
    expect(out.mimeType, 'image/jpeg');
    expect(out.bytes, hasLength(10));
  });

  test('prepares each photo once, and does not even reload it', () async {
    // Every earlier photo is resent on every message; re-reading and
    // re-encoding it each time would be paid per follow-up.
    final p = prep();
    await p.prepare('m1', source(5000));
    await p.prepare('m1', source(5000));

    expect(encodes, hasLength(1));
    expect(loads, 1);
  });

  test('passes an oversized source through untouched, so it is refused',
      () async {
    // kMaxAnalysisBytes is checked on the SOURCE: a photo too big to send
    // must not become sendable by being shrunk first.
    final out = await prep()
        .prepare('m1', source(kMaxAnalysisBytes + 1, 'image/jpeg'));

    expect(encodes, isEmpty);
    expect(out.bytes, hasLength(kMaxAnalysisBytes + 1));
    expect(out.mimeType, 'image/jpeg');
  });

  test('falls back to the original when the encoder fails or returns nothing',
      () async {
    final thrown = await prep(fail: true).prepare('m1', source(500));
    expect(thrown.bytes, hasLength(500));
    expect(thrown.mimeType, 'image/png');

    final empty = await prep(empty: true).prepare('m2', source(600));
    expect(empty.bytes, hasLength(600));
  });

  test('keeps a bounded number of prepared photos', () async {
    final p = prep();
    for (var i = 0; i <= kAssistantImageCacheSize; i++) {
      await p.prepare('m$i', source(100));
    }
    // The first one has been evicted, so it is loaded again.
    await p.prepare('m0', source(100));
    expect(loads, kAssistantImageCacheSize + 2);
  });
}
