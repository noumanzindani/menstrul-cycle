import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../providers/media_provider.dart';
import '../../services/media_upload_service.dart';
import '../../widgets/media_tile.dart';

/// The standalone media timeline: photos and videos the user has uploaded,
/// newest capture first.
///
/// ## No ad banner
///
/// Same family as the diary and the day editor, where ads are banned — and
/// more so here, since the content is plausibly bodily or clinical imagery. A
/// banner rendered beside it is not a placement this app makes.
/// `test/ad_placement_test.dart` guards it structurally.
///
/// ## Cloud-required, and honest about it
///
/// Every callback is nullable, and null means "the cloud is not reachable from
/// this build" — the local-only hatch, where `Firebase.app()` does not exist.
/// The screen then still renders (so nothing crashes and tests stay pumpable)
/// but cannot add anything, and says why. There is no local-only media: an item
/// exists only once it has been uploaded.
class MediaTimelineScreen extends StatefulWidget {
  const MediaTimelineScreen({
    super.key,
    this.onRefresh,
    this.onAdd,
    this.onOpen,
  });

  /// Pull metadata, hydrate thumbnails, sweep orphans. Null when offline-hatched.
  final Future<void> Function()? onRefresh;

  /// Pick and upload. Null disables adding.
  final Future<MediaUploadOutcome> Function()? onAdd;

  /// Opens one item full-screen. Injected so the grid does not depend on the
  /// viewer (and its video controller) in widget tests.
  final void Function(BuildContext context, MediaItem item)? onOpen;

  bool get canAdd => onAdd != null;

  @override
  State<MediaTimelineScreen> createState() => _MediaTimelineScreenState();
}

class _MediaTimelineScreenState extends State<MediaTimelineScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // After the first frame so the grid paints from the local replica
    // immediately — the network round-trip must never be what the user waits
    // for to see what they already have.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    if (refresh == null) return;
    try {
      await refresh();
    } catch (_) {
      // Opportunistic. A failed pull leaves the local replica exactly as it
      // was, which is a working screen.
    }
    if (mounted) await context.read<MediaProvider>().reload();
  }

  Future<void> _add() async {
    final add = widget.onAdd;
    if (add == null || _busy) return;
    setState(() => _busy = true);
    MediaUploadOutcome outcome;
    try {
      outcome = await add();
    } catch (error, stack) {
      // Reported, not swallowed. `failed: 1` is a COUNT the user reads, and a
      // thrown batch reports 1 no matter how many files were picked — so on its
      // own it is both wrong and untraceable. A device test spent most of its
      // time recovering an exception this line used to discard.
      //
      // Debug-only, and the payload is an exception, never a token or a
      // filename: the caps refuse by reason, and paths are opaque ids.
      assert(() {
        debugPrint('[media] upload batch threw: $error\n$stack');
        return true;
      }());
      outcome = const MediaUploadOutcome(failed: 1);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await context.read<MediaProvider>().reload();
    if (!mounted) return;
    final message = _messageFor(outcome);
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// What to tell the user after a pick. Null when everything worked.
  ///
  /// Every partial outcome is reported: a silently dropped file reads as "we
  /// took everything", and with no queue there is nothing left behind to hint
  /// otherwise.
  String? _messageFor(MediaUploadOutcome outcome) {
    switch (outcome.blocked) {
      case MediaUploadBlock.notSignedIn:
        return 'Sign in to add photos and videos.';
      case MediaUploadBlock.syncDeclined:
        // Not a failure — a decision they made. Do not phrase it as an error.
        return 'You chose to keep your data on this device. Photos and videos '
            'are stored in your account, so adding them is turned off.';
      case MediaUploadBlock.deletionPending:
        return 'Your account is queued for deletion, so nothing new can be '
            'added.';
      case MediaUploadBlock.syncOff:
        // Names where to fix it, because unlike the cases around it this one
        // IS fixable by the user, from a screen they have already seen.
        return 'Cloud sync is off, and photos and videos are stored in your '
            'account. Turn it on in Settings to add them.';
      case MediaUploadBlock.writesBlocked:
      case MediaUploadBlock.accountChanged:
        return 'Nothing was added. Try again in a moment.';
      case null:
        break;
    }

    final parts = <String>[];
    if (outcome.dropped > 0) {
      parts.add('${outcome.dropped} not added (10 at a time)');
    }
    if (outcome.failed > 0) {
      parts.add('${outcome.failed} didn\'t upload');
    }
    for (final r in outcome.rejected) {
      parts.add(r.message);
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MediaProvider>();
    final items = provider.items;

    return Scaffold(
      appBar: AppBar(title: const Text('Photos & videos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'media.add',
        onPressed: widget.canAdd && !_busy ? _add : null,
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined),
        label: Text(_busy ? 'Uploading…' : 'Add'),
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? _EmptyState(canAdd: widget.canAdd)
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: GridView.builder(
                    key: const Key('media-grid'),
                    padding: const EdgeInsets.all(4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return MediaTile(
                        key: Key('media-tile-${item.id}'),
                        item: item,
                        onTap: () => widget.onOpen?.call(context, item),
                      );
                    },
                  ),
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canAdd});

  final bool canAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            canAdd
                // Says where they go, because that is the one thing about this
                // feature a user cannot see for themselves. No claim about
                // encryption or privacy — the bucket is neither.
                ? 'Photos and videos you add are stored in your account, so '
                    'they show up on your other devices.'
                : 'Photos and videos are stored in your account. This device '
                    "can't reach it right now.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

/// The date header format the viewer and any future grouping share.
final mediaDateFormat = DateFormat.yMMMEd();
