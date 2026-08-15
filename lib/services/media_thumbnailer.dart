import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Longest edge of a generated thumbnail, in pixels.
///
/// A 3-column grid tile is roughly 130dp; at 3x density that is ~390px, so 320
/// is very slightly soft on the densest screens and materially cheaper
/// everywhere. Raising it is a bandwidth and storage decision paid on every
/// item forever, not a local one.
const int kThumbMaxEdge = 320;

/// JPEG quality for thumbnails. 70 is the knee of the curve for photographic
/// content at this size — visibly indistinguishable from 85, roughly half the
/// bytes.
const int kThumbQuality = 70;

/// Largest thumbnail that may also be cached as a `MediaItems.thumbnail` blob.
///
/// The expected encode is 12-25 KB, so this is a backstop rather than a normal
/// outcome. It exists because the blob column lives inside the encrypted
/// database: an unbounded blob grows the one file the whole app opens, and 500
/// items at the cap would already be 32 MB. Over the cap the thumbnail is still
/// UPLOADED — only the local copy is skipped, and the tile falls back to
/// fetching the thumb object.
const int kThumbBlobMaxBytes = 64 * 1024;

/// Encodes [source] down to a JPEG whose longest edge is [maxEdge].
///
/// Injected so tests never touch a platform channel — `flutter_image_compress`
/// is a native plugin and returns nothing under `flutter_tester`.
typedef ThumbnailEncoder = Future<Uint8List> Function(
  Uint8List source, {
  required int maxEdge,
  required int quality,
});

Future<Uint8List> _compressEncoder(
  Uint8List source, {
  required int maxEdge,
  required int quality,
}) =>
    // minWidth/minHeight act as a bounding box: the image is scaled down to fit
    // within them, preserving aspect ratio. Passing the same value for both is
    // therefore "longest edge <= maxEdge".
    //
    // JPEG deliberately, not PNG. `dart:ui` can downscale with no dependency at
    // all but has no JPEG encoder, and a 320px photographic PNG runs 6-10x the
    // bytes — paid on every upload, every cross-device download and every
    // cached row, forever. That cost is why this package is here.
    FlutterImageCompress.compressWithList(
      source,
      minWidth: maxEdge,
      minHeight: maxEdge,
      quality: quality,
      format: CompressFormat.jpeg,
    );

/// Makes the small preview that the grid renders and other devices download.
///
/// **Images only in v1.** There is no maintained, non-ffmpeg Flutter package
/// for extracting a video poster frame that belongs in a health app's release
/// build, and seeking a `video_player` to grab a frame allocates a MediaCodec
/// per attempt — on the low-end devices minSdk 26 admits, doing that across a
/// grid will ANR. Video tiles therefore render a neutral poster (film icon,
/// duration, play affordance) and `MediaItems.thumbPath` stays null for them.
/// The column exists so adding real posters later needs no migration.
class MediaThumbnailer {
  MediaThumbnailer({ThumbnailEncoder? encoder})
      : _encode = encoder ?? _compressEncoder;

  final ThumbnailEncoder _encode;

  /// Returns thumbnail JPEG bytes, or null if one could not be made.
  ///
  /// Null is a normal outcome, not an error: a preview is not the item. Failing
  /// the upload because a thumbnail could not be encoded would cost the user
  /// their photo over a cosmetic problem, so the caller uploads the original
  /// with `thumbPath: null` and tiles fall back to a bounded download.
  Future<Uint8List?> generate(Uint8List source) async {
    try {
      final out = await _encode(source,
          maxEdge: kThumbMaxEdge, quality: kThumbQuality);
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// The bytes to store in the `thumbnail` blob column, or null to skip caching.
  static Uint8List? blobFor(Uint8List? thumbnail) {
    if (thumbnail == null) return null;
    return thumbnail.length <= kThumbBlobMaxBytes ? thumbnail : null;
  }
}
