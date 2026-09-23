import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'media_analysis.dart';

/// Longest edge of a photo sent to the assistant, in pixels.
///
/// Every earlier photo in a conversation is resent with every message
/// (`generateContent` keeps no state), so this is paid per follow-up, not
/// once. 1024 keeps a photo legible to the model at a fraction of the bytes
/// of the stored 2048px original.
const int kAssistantImageMaxEdge = 1024;

/// JPEG quality for assistant photos.
const int kAssistantImageQuality = 80;

/// How many prepared photos are kept in memory. Twice the per-conversation
/// cap, so switching between two conversations does not re-encode.
const int kAssistantImageCacheSize = kMaxImagesPerConversation * 2;

/// Encodes [source] to a JPEG whose longest edge is at most [maxEdge].
///
/// Injected so tests never touch a platform channel — `flutter_image_compress`
/// is a native plugin and returns nothing under `flutter_tester`.
typedef ImageDownscaler = Future<Uint8List> Function(
  Uint8List source, {
  required int maxEdge,
  required int quality,
});

// Same bounding-box call `MediaThumbnailer` makes; see its comment there.
Future<Uint8List> _compress(
  Uint8List source, {
  required int maxEdge,
  required int quality,
}) =>
    FlutterImageCompress.compressWithList(
      source,
      minWidth: maxEdge,
      minHeight: maxEdge,
      quality: quality,
      format: CompressFormat.jpeg,
    );

/// A photo ready to inline into a request.
class PreparedImage {
  const PreparedImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Shrinks photos before the assistant sends them, once per photo.
///
/// Screen-layer on purpose: `MediaAnalysisService` receives bytes and must
/// never reach storage, so the caller loads, prepares and hands them over.
class AssistantImagePrep {
  AssistantImagePrep({ImageDownscaler? encoder})
      : _encode = encoder ?? _compress;

  final ImageDownscaler _encode;

  /// Least recently used first.
  final Map<String, PreparedImage> _cache = {};

  /// The prepared copy of [mediaId], loading its original through [load]
  /// only when it is not already held.
  ///
  /// A source over [kMaxAnalysisBytes] is returned untouched and not cached:
  /// the limit is on the source, so the service refuses it as too large
  /// rather than a shrunk copy slipping under it. An encoder failure also
  /// returns the source — a photo the codec cannot shrink is still a photo,
  /// and the inline budget still bounds the request.
  Future<PreparedImage> prepare(
    String mediaId,
    Future<(Uint8List, String)> Function() load,
  ) async {
    final held = _cache.remove(mediaId);
    if (held != null) return _cache[mediaId] = held;

    final (source, mimeType) = await load();
    if (source.length > kMaxAnalysisBytes) {
      return PreparedImage(bytes: source, mimeType: mimeType);
    }
    PreparedImage prepared;
    try {
      final out = await _encode(
        source,
        maxEdge: kAssistantImageMaxEdge,
        quality: kAssistantImageQuality,
      );
      prepared = out.isEmpty
          ? PreparedImage(bytes: source, mimeType: mimeType)
          : PreparedImage(bytes: out, mimeType: 'image/jpeg');
    } catch (_) {
      prepared = PreparedImage(bytes: source, mimeType: mimeType);
    }
    _cache[mediaId] = prepared;
    if (_cache.length > kAssistantImageCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return prepared;
  }
}
