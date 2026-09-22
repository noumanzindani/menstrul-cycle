import 'package:flutter/material.dart';

import '../../widgets/entrance.dart';

import '../../services/media_picker_config.dart';
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
    this.onOpenSessions,
  });

  /// Pull metadata, hydrate thumbnails, sweep orphans. Null when offline-hatched.
  final Future<void> Function()? onRefresh;

  /// Capture or pick from [source], then upload. Null disables adding.
  ///
  /// Takes the source rather than choosing one, so this screen owns the
  /// CHOICE (it has the context a sheet needs) and the route owns the PICKER
  /// (it owns the configuration and the temp sweep). Neither has to know the
  /// other's half.
  final Future<MediaUploadOutcome> Function(MediaSource source)? onAdd;

  /// Opens one item full-screen. Injected so the grid does not depend on the
  /// viewer (and its video controller) in widget tests.
  final void Function(BuildContext context, MediaItem item)? onOpen;

  /// Opens the saved-conversations list. Null hides the action — same
  /// "hidden, not disabled" rule the media entry point itself follows, and
  /// what keeps this off a build with no photo-description feature at all.
  ///
  /// An app-bar action rather than a sixth bottom-nav destination or a second
  /// FAB: the `NavigationBar` is fixed at Material's five, and a second FAB on
  /// a 360dp screen already carrying one for Add would collide with it.
  final void Function(BuildContext context)? onOpenSessions;

  bool get canAdd => onAdd != null;

  @override
  State<MediaTimelineScreen> createState() => _MediaTimelineScreenState();
}

class _MediaTimelineScreenState extends State<MediaTimelineScreen> {
  bool _busy = false;

  /// How many files the last pick failed to upload.
  ///
  /// Rendered as an inline card at the top of the timeline rather than as a
  /// snack bar: with no upload queue there is nothing left behind to point at
  /// afterwards, so a message that slides away after four seconds is the whole
  /// record of the loss. Every other outcome — a refusal, a cap, a decision the
  /// user made — stays a snack bar, because those are answers, not losses.
  int _failed = 0;

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

  /// Offers capture and library picking, then runs the chosen one.
  ///
  /// A sheet rather than a second app-bar button: capture is two options, not
  /// one (still and video are separate system intents), so a single icon could
  /// never express it — and a third icon on an app bar that already carries
  /// refresh would crowd a 360dp phone.
  Future<void> _add() async {
    if (widget.onAdd == null || _busy) return;
    final source = await showModalBottomSheet<MediaSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, MediaSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record a video'),
              onTap: () => Navigator.pop(sheetContext, MediaSource.videoCamera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(sheetContext, MediaSource.library),
            ),
          ],
        ),
      ),
    );
    // Dismissing the sheet is a cancel, not an empty pick: nothing runs, and
    // the failure count from a previous attempt stays on screen.
    if (source == null || !mounted) return;
    await _uploadFrom(source);
  }

  Future<void> _uploadFrom(MediaSource source) async {
    final add = widget.onAdd;
    if (add == null || _busy) return;
    setState(() {
      _busy = true;
      // Clearing here rather than on the reply is what makes the card's own
      // "Try again" read as a retry instead of leaving the previous failure
      // standing beside the new attempt.
      _failed = 0;
    });
    MediaUploadOutcome outcome;
    try {
      outcome = await add(source);
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
    setState(() {
      _busy = false;
      _failed = outcome.failed;
    });
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
    // `outcome.failed` is deliberately absent here: it is reported by the
    // inline card instead, which persists. Reporting it in both places would
    // say the same thing twice, once in a form that vanishes.
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
      appBar: AppBar(
        title: const Text('Photos & videos'),
        actions: [
          if (widget.onOpenSessions != null)
            IconButton(
              tooltip: 'Saved descriptions',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => widget.onOpenSessions!(context),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'media.add',
        tooltip: 'Add a photo or video',
        onPressed: widget.canAdd && !_busy ? _add : null,
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_a_photo_outlined),
      ),
      body: Column(
        children: [
          // Permanent, above everything, in both the populated and the empty
          // state. Not an error strip and not dismissible: how these files are
          // held is a standing fact about the feature, not an incident.
          const _StorageNotice(),
          Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refresh,
                    // Scoped to the grid. `_StorageNotice` above is a standing
                    // disclosure about how these files are held, not content
                    // arriving, and must not fade in after the photographs it
                    // qualifies.
                    child: EntranceGroup(
                      child: CustomScrollView(
                        key: const Key('media-grid'),
                        // So the empty state can be pulled down too — a screen
                        // that cannot be refreshed is exactly the one a user
                        // pulls on when nothing has arrived yet.
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          if (_failed > 0)
                            SliverToBoxAdapter(
                              child: _UploadFailureCard(
                                count: _failed,
                                onRetry: widget.canAdd && !_busy ? _add : null,
                              ),
                            ),
                          if (items.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: _EmptyState(
                                canAdd: widget.canAdd,
                                onAdd: _busy ? null : _add,
                              ),
                            )
                          else
                            ..._monthSlivers(context, items),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// One uppercase month header plus one grid per month, in the order the
  /// provider hands them over (newest capture first).
  ///
  /// Grouping is presentation only — the query still returns one flat, sorted
  /// list. Without it a year of photographs is an undifferentiated wall, and
  /// the one thing a user is scrolling for ("around when was that?") is the one
  /// thing the screen does not say.
  List<Widget> _monthSlivers(BuildContext context, List<MediaItem> items) {
    final theme = Theme.of(context);
    final slivers = <Widget>[];

    var start = 0;
    while (start < items.length) {
      var end = start + 1;
      while (end < items.length &&
          _sameMonth(items[end].capturedAt, items[start].capturedAt)) {
        end++;
      }
      final group = items.sublist(start, end);
      final isLast = end >= items.length;

      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, start == 0 ? 16 : 24, 16, 10),
            child: Text(
              mediaMonthFormat.format(group.first.capturedAt).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      );
      // Copied BEFORE `start` is advanced at the end of the loop: the builder
      // below is a closure, and a closure over the loop variable itself reads
      // whatever value it finished on. This running offset is what makes the
      // stagger continue across month groups instead of restarting at each
      // heading.
      final base = start;
      slivers.add(
        SliverPadding(
          // Edge to edge, 2dp gutters: the photographs are the content, and
          // every pixel of chrome between them is a pixel not spent on them.
          // The trailing pad on the last group clears the FAB.
          padding: EdgeInsets.only(bottom: isLast ? 96 : 0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final item = group[i];
                return EntranceItem(
                  index: base + i,
                  child: MediaTile(
                    key: Key('media-tile-${item.id}'),
                    item: item,
                    onTap: () => widget.onOpen?.call(context, item),
                  ),
                );
              },
              childCount: group.length,
            ),
          ),
        ),
      );
      start = end;
    }
    return slivers;
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}

/// The standing disclosure about where these files live.
///
/// Deliberately says how they are held on the server as well as that they are
/// uploaded: the first half alone reads as reassurance. The wording avoids the
/// words `media_guardrails_test.dart` bans from this directory — that scan is a
/// blunt substring check and cannot tell a denial from a claim — while saying
/// the same thing the sign-up disclosure says.
class _StorageNotice extends StatelessWidget {
  const _StorageNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Photos are uploaded to your account and stored as plain files '
              'on our servers — the people who run LunarFlow can open them.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The inline record of a failed upload.
///
/// A card rather than a toast because there is nothing else left to see: this
/// feature keeps no pending row, so if the message goes away, so does the only
/// evidence that a file the user picked is not here.
class _UploadFailureCard extends StatelessWidget {
  const _UploadFailureCard({required this.count, this.onRetry});

  final int count;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // Not the error container. Nothing here is an emergency, and red on
          // a photograph of your own body is a tone this app does not take.
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_off_outlined,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == 1
                        ? "That didn't upload"
                        : "$count didn't upload",
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'LunarFlow only saves photos once the upload finishes, so '
              'nothing was kept.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              // Outlined, so it can sit on its own line without demanding the
              // infinite width `filledButtonTheme` gives a FilledButton.
              child: OutlinedButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canAdd, this.onAdd});

  final bool canAdd;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text('Nothing here yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              canAdd
                  // Says where they go, because that is the one thing about
                  // this feature a user cannot see for themselves. No claim
                  // about how they are held — the strip above covers that, and
                  // the bucket earns no reassurance.
                  ? 'Photos and videos you add are stored in your account, so '
                      'they show up on your other devices.'
                  : 'Photos and videos are stored in your account. This device '
                      "can't reach it right now.",
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (canAdd) ...[
              const SizedBox(height: 28),
              // Full width in a Column — the app's CTA convention, and the one
              // shape `filledButtonTheme`'s infinite minimum width is built
              // for. Never put one of these in a Row.
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add a photo or video'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The date format the viewer's title uses.
final mediaDateFormat = DateFormat.yMMMMd();

/// The timeline's month group headers.
final mediaMonthFormat = DateFormat.yMMMM();
