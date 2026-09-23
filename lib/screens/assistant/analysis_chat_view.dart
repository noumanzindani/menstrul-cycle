import 'package:flutter/material.dart';

import '../../db/database.dart';
import '../../services/media_analysis.dart';

/// What one line of the on-screen transcript is.
///
/// Not the same thing as an `AnalysisTurn`: errors and notices appear here for
/// the user to read but are never sent back to the model as conversation.
enum ChatEntryKind {
  /// Something the user sent.
  user,

  /// The model's answer.
  reply,

  /// A refusal or failure the user can act on. Never red.
  error,

  /// Something the app says itself, such as the declined-video notice. Never
  /// red either: nothing here is an emergency.
  notice,
}

/// One photo or video a message carries, as the transcript shows it.
class ChatAttachment {
  const ChatAttachment({
    required this.mediaId,
    required this.kind,
    this.item,
  });

  final String mediaId;
  final AttachmentKind kind;

  /// The stored item, for its thumbnail. Null means it was deleted after the
  /// message was sent, and the tile says so.
  final MediaItem? item;

  bool get removed => item == null;
}

/// One line of the transcript.
class ChatEntry {
  const ChatEntry(this.kind, this.text, {this.attachments = const []});

  const ChatEntry.user(String text, {List<ChatAttachment> attachments = const []})
      : this(ChatEntryKind.user, text, attachments: attachments);
  const ChatEntry.reply(String text) : this(ChatEntryKind.reply, text);
  const ChatEntry.error(String text) : this(ChatEntryKind.error, text);
  const ChatEntry.notice(String text) : this(ChatEntryKind.notice, text);

  final ChatEntryKind kind;
  final String text;
  final List<ChatAttachment> attachments;

  bool get fromUser => kind == ChatEntryKind.user;
}

/// Where an attachment waiting in the composer is.
enum PendingState { uploading, ready, failed }

/// An attachment waiting in the composer, not yet sent.
class PendingAttachment {
  const PendingAttachment({required this.key, required this.state, this.item});

  /// Stable for the chip's lifetime, including before an upload has produced
  /// an item to name it by.
  final String key;
  final PendingState state;
  final MediaItem? item;

  bool get isVideo => item?.kind == 'video';
}

/// The conversation surface: a transcript, the fixed caveat, the day's
/// remaining messages, and a composer.
///
/// Presentational only. It owns no conversation, sends nothing and reaches for
/// no service or provider — the screen above it holds the state and hands in
/// callbacks — so a widget test pumps it with plain values. Every key the
/// photo-description sheet it was extracted from carried is kept, so the
/// tests written against that sheet still find the same controls.
class AnalysisChatView extends StatefulWidget {
  const AnalysisChatView({
    super.key,
    required this.entries,
    required this.controller,
    required this.onSend,
    this.pending = false,
    this.messagesLeft,
    this.notice,
    this.onAttach,
    this.attachEnabled = true,
    this.attachments = const [],
    this.onRemoveAttachment,
    this.hintText = 'Ask a follow-up',
    this.expand = true,
  });

  final List<ChatEntry> entries;
  final TextEditingController controller;

  /// Null disables Send.
  final VoidCallback? onSend;

  /// Whether a reply is on its way. Shows the pending indicator.
  final bool pending;

  /// Messages today's cap still allows. Null hides the counter — a display of
  /// a budget nobody supplied would be a guess.
  final int? messagesLeft;

  /// A standing line above the composer, such as the daily-cap notice.
  final String? notice;

  /// Opens the attach sheet. Null hides the button.
  final VoidCallback? onAttach;

  /// False greys the attach button out without hiding it — while a reply is
  /// on its way, or once a message holds all it can carry.
  final bool attachEnabled;

  /// What the next message will carry.
  final List<PendingAttachment> attachments;
  final void Function(PendingAttachment attachment)? onRemoveAttachment;

  final String hintText;

  /// True fills the available height, which is what a full screen wants. False
  /// sizes to the transcript, for a bottom sheet.
  final bool expand;

  @override
  State<AnalysisChatView> createState() => _AnalysisChatViewState();
}

class _AnalysisChatViewState extends State<AnalysisChatView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(AnalysisChatView old) {
    super.didUpdateWidget(old);
    if (old.entries.length != widget.entries.length ||
        old.pending != widget.pending) {
      _scrollToEnd();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Rides a post-frame callback because the new bubble has not been laid out
  /// yet when the rebuild happens — `maxScrollExtent` would still be the old
  /// one.
  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final entries = widget.entries;
    final transcript = ListView.builder(
      key: const Key('analysis-transcript'),
      controller: _scroll,
      shrinkWrap: !widget.expand,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length + (widget.pending ? 1 : 0),
      itemBuilder: (context, i) =>
          i == entries.length ? const _Pending() : _Bubble(entries[i]),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.expand)
            Expanded(child: transcript)
          else
            Flexible(child: transcript),
          const SizedBox(height: 12),
          // Fixed, always present, never conditional on what came back. A
          // caveat shown only sometimes teaches the user that its absence
          // means the answer IS reliable. It sits under the transcript rather
          // than under each answer so that there is exactly one of it, always,
          // whatever the conversation did.
          _InfoLine(kAnalysisCaveat, color: muted),
          if (widget.messagesLeft != null) ...[
            const SizedBox(height: 10),
            Text(
              // "messages", not "photos": every turn of a conversation bills,
              // so the cap counts turns. Same wording as the refusal copy the
              // user meets when it runs out.
              '${widget.messagesLeft} of $kMaxAnalysesPerDay messages '
              'left today',
              key: const Key('analysis-messages-left'),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
          if (widget.notice != null) ...[
            const SizedBox(height: 10),
            _InfoLine(
              widget.notice!,
              key: const Key('analysis-cap-notice'),
              color: muted,
            ),
          ],
          if (widget.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _PendingChip(
                  attachment: widget.attachments[i],
                  onRemove: widget.onRemoveAttachment,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.onAttach != null) ...[
                IconButton(
                  key: const Key('analysis-attach-button'),
                  tooltip: 'Attach',
                  onPressed: widget.attachEnabled ? widget.onAttach : null,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  key: const Key('analysis-question-field'),
                  controller: widget.controller,
                  maxLength: kMaxQuestionLength,
                  textInputAction: TextInputAction.send,
                  minLines: 1,
                  maxLines: 3,
                  onSubmitted: (_) => widget.onSend?.call(),
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    counterText: '',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('analysis-ask-button'),
                tooltip: 'Send',
                onPressed: widget.onSend,
                icon: const Icon(Icons.arrow_upward),
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small muted line with an info icon: the caveat, and standing notices.
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: color, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.entry);

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The user's own words are a bubble; the model's answer is plain prose.
    // That asymmetry is deliberate — the answer is the content of this view,
    // and a tinted container around it makes it look like a quoted verdict
    // rather than a paragraph the user is meant to read and weigh.
    if (!entry.fromUser) {
      final muted = entry.kind != ChatEntryKind.reply;
      return Padding(
        key: entry.kind == ChatEntryKind.notice
            ? const Key('analysis-notice')
            : null,
        padding: const EdgeInsets.fromLTRB(0, 8, 24, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (muted) ...[
              // Neutral, never the error container: nothing here is an
              // emergency, and this app does not use red as an alert colour.
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              // Selectable so an answer can be copied out.
              child: SelectableText(
                entry.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  color: muted ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (entry.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in entry.attachments) _SentAttachment(a),
                  ],
                ),
              ),
            if (entry.text.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(4),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: SelectableText(
                  entry.text,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sent photo or video, above the words it went with.
class _SentAttachment extends StatelessWidget {
  const _SentAttachment(this.attachment);

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (attachment.removed) {
      // Said in words: an empty tile would read as still loading.
      return Container(
        key: Key('analysis-attachment-removed-${attachment.mediaId}'),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hide_image_outlined,
                size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              attachment.kind == AttachmentKind.video
                  ? 'Video removed'
                  : 'Photo removed',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return _Thumb(
      key: Key('analysis-attachment-${attachment.mediaId}'),
      item: attachment.item!,
    );
  }
}

/// A 48px square of one item: its thumbnail, or for a video a neutral tile
/// with a play icon and the length. Video has no poster frame (see
/// `MediaThumbnailer`), and the tile must not pretend to preview it.
class _Thumb extends StatelessWidget {
  const _Thumb({super.key, required this.item});

  final MediaItem item;

  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = item.thumbnail;
    final Widget child;
    if (item.kind == 'video') {
      child = ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded,
                size: 20, color: scheme.onSurfaceVariant),
            Text(
              clipDurationLabel(item.durationMs),
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    } else if (bytes != null) {
      child = Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: 160,
        gaplessPlayback: true,
      );
    } else {
      child = ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.image_outlined,
            size: 20, color: scheme.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

/// `m:ss`, or "Video" when the length is unknown.
String clipDurationLabel(int? ms) {
  if (ms == null || ms <= 0) return 'Video';
  final total = Duration(milliseconds: ms);
  final seconds = total.inSeconds % 60;
  return '${total.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

/// One attachment in the composer, with its remove control.
class _PendingChip extends StatelessWidget {
  const _PendingChip({required this.attachment, this.onRemove});

  final PendingAttachment attachment;
  final void Function(PendingAttachment attachment)? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = attachment.item;
    final Widget tile = switch (attachment.state) {
      PendingState.ready when item != null => _Thumb(item: item),
      PendingState.uploading => _PlainTile(
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      // Neutral, not the error colour: a failed upload is a retry, not an
      // alarm, and nothing was kept.
      _ => _PlainTile(
          child: Icon(Icons.cloud_off_outlined,
              size: 20, color: scheme.onSurfaceVariant),
        ),
    };
    return SizedBox(
      key: Key('analysis-chip-${attachment.key}'),
      width: 56,
      height: 56,
      child: Stack(
        children: [
          Positioned(left: 0, bottom: 0, child: tile),
          if (onRemove != null)
            Positioned(
              right: 0,
              top: 0,
              child: Tooltip(
                message: 'Remove attachment',
                child: GestureDetector(
                  key: Key('analysis-chip-remove-${attachment.key}'),
                  onTap: () => onRemove!(attachment),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                    child: Icon(Icons.close,
                        size: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlainTile extends StatelessWidget {
  const _PlainTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: _Thumb.size,
          height: _Thumb.size,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: child,
        ),
      );
}

class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        key: Key('analysis-pending'),
        // Aligned with the prose it is about to be replaced by, so the answer
        // does not jump sideways when it lands.
        padding: EdgeInsets.fromLTRB(0, 16, 0, 16),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
