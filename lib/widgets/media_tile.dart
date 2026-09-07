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
          // The ground behind a still-loading or thumbnail-less tile. Painted
          // unconditionally so a transparent PNG, a short decode or a missing
          // blob all read as the same quiet placeholder rather than as a hole
          // in the grid.
          ColoredBox(color: scheme.surfaceContainerHighest),
          if (thumbnail != null)
            Image.memory(
              thumbnail,
              fit: BoxFit.cover,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
            )
          else
            Center(
              child: Icon(
                _isVideo ? Icons.movie_outlined : Icons.image_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          // Video has no poster frame in v1 — extracting one needs either a
          // retired ffmpeg wrapper or a MediaCodec per tile, which will ANR a
          // grid on a low-end device. A duration badge and a play affordance
          // say "this is a video" without pretending to preview it.
          //
          // One badge, not two: the mock's corner play chip and the duration
          // label carry the same message, and a 118dp tile has room for one.
          // The full-bleed centre icon it replaces sat on top of the very
          // frame the user is trying to recognise.
          if (_isVideo)
            Positioned(
              right: 6,
              bottom: 6,
              child: _VideoBadge(durationMs: item.durationMs),
            ),
        ],
      ),
    );
  }
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge({this.durationMs});

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
          // A scrim, not a theme surface: it sits on the user's own photograph,
          // whose colours are unknown, so it needs its own contrast in both
          // light and dark.
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 14,
                color: Colors.white,
              ),
              const SizedBox(width: 2),
              Text(
                _label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      );
}
