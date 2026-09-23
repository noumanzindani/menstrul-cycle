import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../widgets/media_tile.dart';

/// Lets the user pick up to [max] items already in Photos & videos.
///
/// Returns the chosen items in the order they were tapped, or null when the
/// sheet was dismissed. Nothing is uploaded: these are already stored, and a
/// message only carries references to them.
Future<List<MediaItem>?> showMediaSelectSheet(
  BuildContext context, {
  required List<MediaItem> items,
  required int max,
}) {
  return showModalBottomSheet<List<MediaItem>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _MediaSelectSheet(items: items, max: max),
  );
}

class _MediaSelectSheet extends StatefulWidget {
  const _MediaSelectSheet({required this.items, required this.max});

  final List<MediaItem> items;
  final int max;

  @override
  State<_MediaSelectSheet> createState() => _MediaSelectSheetState();
}

class _MediaSelectSheetState extends State<_MediaSelectSheet> {
  final List<MediaItem> _chosen = [];

  void _toggle(MediaItem item) {
    setState(() {
      final at = _chosen.indexWhere((c) => c.id == item.id);
      if (at >= 0) {
        _chosen.removeAt(at);
      } else if (_chosen.length < widget.max) {
        _chosen.add(item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _chosen.isEmpty
                          ? 'Photos & videos'
                          : '${_chosen.length} of ${widget.max} chosen',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  // A TextButton, not a FilledButton: the theme gives every
                  // FilledButton infinite width, which overflows a Row.
                  TextButton(
                    key: const Key('media-select-attach'),
                    onPressed: _chosen.isEmpty
                        ? null
                        : () => Navigator.pop(context, List.of(_chosen)),
                    child: const Text('Attach'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: widget.items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nothing in Photos & videos yet.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: widget.items.length,
                      itemBuilder: (context, i) {
                        final item = widget.items[i];
                        final chosen = _chosen.any((c) => c.id == item.id);
                        return Stack(
                          key: Key('media-select-${item.id}'),
                          fit: StackFit.expand,
                          children: [
                            MediaTile(item: item, onTap: () => _toggle(item)),
                            if (chosen)
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: scheme.primary, width: 3),
                                  ),
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Icon(Icons.check_circle,
                                          color: scheme.primary),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
