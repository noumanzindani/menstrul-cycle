import 'package:flutter/material.dart';

import '../db/database.dart';

/// One cell in the media grid.
///
/// Renders from the locally cached [MediaItem.thumbnail] blob when there is
/// one, and a neutral placeholder otherwise. It never fetches anything itself:
/// a widget that reaches for the network per tile turns a scroll into a burst
/// of requests, and it would make the grid untestable without a Firebase app.
/// Hydration is `MediaSyncService.hydrateThumbnails`, run once when the screen
/// opens.
class MediaTile extends StatelessWidget {
  const MediaTile({super.key, required this.item, this.onTap});

  final MediaItem item;
  final VoidCallback? onTap;

  bool get _isVideo => item.kind == 'video';

  /// Decode width in device pixels.
  ///
  /// Without this, `Image.memory` decodes at full resolution into the image
  /// cache — a 12MP photo is ~48 MB of raster, and a screenful of them will OOM
  /// the low-end devices minSdk 26 admits. Thumbnails are only 320px, so this
  /// is belt-and-braces for them; it matters because the same widget is the
  /// obvious place someone later points at a full-size image.
  static const int decodeWidth = 320;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnail = item.thumbnail;

    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumbnail != null)
            Image.memory(
              thumbnail,
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
            )
          else
            Container(
              color: scheme.surfaceContainerHighest,
              child: Icon(
                _isVideo ? Icons.movie_outlined : Icons.image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          // Video has no poster frame in v1 — extracting one needs either a
          // retired ffmpeg wrapper or a MediaCodec per tile, which will ANR a
          // grid on a low-end device. A duration badge and a play affordance
          // say "this is a video" without pretending to preview it.
          if (_isVideo)
            Positioned(
              right: 4,
              bottom: 4,
              child: _DurationBadge(durationMs: item.durationMs),
            ),
          if (_isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70),
            ),
        ],
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({this.durationMs});

  final int? durationMs;

  String get _label {
    final ms = durationMs;
    if (ms == null || ms <= 0) return 'Video';
    final total = Duration(milliseconds: ms);
    final minutes = total.inMinutes;
    final seconds = total.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            _label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      );
}
