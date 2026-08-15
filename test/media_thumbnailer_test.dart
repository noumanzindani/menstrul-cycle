import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/media_thumbnailer.dart';

void main() {
  Uint8List bytes(int n) => Uint8List.fromList(List.filled(n, 1));

  group('generate', () {
    test('asks the encoder for the agreed size and quality', () async {
      int? sawEdge;
      int? sawQuality;
      final t = MediaThumbnailer(
        encoder: (src, {required maxEdge, required quality}) async {
          sawEdge = maxEdge;
          sawQuality = quality;
          return bytes(1024);
        },
      );

      await t.generate(bytes(4 * 1024 * 1024));

      // Pinned because they are a cost decision, not a taste one: 320px at q70
      // lands a photo thumbnail around 12-25 KB, which is what makes both the
      // blob cache and the per-item thumb object cheap enough to be routine.
      expect(sawEdge, kThumbMaxEdge);
      expect(sawQuality, kThumbQuality);
    });

    test('returns the encoded bytes', () async {
      final out = bytes(2048);
      final t = MediaThumbnailer(
        encoder: (src, {required maxEdge, required quality}) async => out,
      );
      expect(await t.generate(bytes(100)), out);
    });

    test('returns null when the encoder fails, rather than throwing', () async {
      // A thumbnail is a preview, not the item. Failing the whole upload
      // because a preview could not be encoded would lose the user's photo over
      // a cosmetic problem; the tile falls back to a bounded download of the
      // original instead.
      final t = MediaThumbnailer(
        encoder: (src, {required maxEdge, required quality}) async =>
            throw StateError('decoder blew up'),
      );
      expect(await t.generate(bytes(100)), isNull);
    });

    test('returns null when the encoder produces nothing', () async {
      final t = MediaThumbnailer(
        encoder: (src, {required maxEdge, required quality}) async =>
            Uint8List(0),
      );
      expect(await t.generate(bytes(100)), isNull);
    });
  });

  group('blobFor', () {
    test('caches a thumbnail at exactly the cap', () {
      final b = bytes(kThumbBlobMaxBytes);
      expect(MediaThumbnailer.blobFor(b), b);
    });

    test('refuses to cache one byte over the cap', () {
      // Uploaded either way — this only decides whether a copy also lives in
      // the database. An unbounded blob column would grow the encrypted DB
      // without limit, and the DB is read whole by the sync layer.
      expect(MediaThumbnailer.blobFor(bytes(kThumbBlobMaxBytes + 1)), isNull);
    });

    test('a null thumbnail caches nothing', () {
      expect(MediaThumbnailer.blobFor(null), isNull);
    });

    test('the cap leaves room for a normal library', () {
      // 500 items at the expected ~25 KB is ~12 MB of DB growth. The cap is the
      // backstop for an unexpectedly large encode, not the expected size.
      expect(kThumbBlobMaxBytes, greaterThanOrEqualTo(32 * 1024));
    });
  });
}
