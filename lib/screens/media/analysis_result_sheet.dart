import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/media_analysis.dart';
import '../assistant/analysis_chat_view.dart';

/// A conversation about one photo.
///
/// Deliberately a sheet rather than a route: the photo stays visible behind it,
/// which is what makes a description of "this" legible at all.
///
/// [onAsk] returns the next answer, or an error string to display. It is passed
/// in rather than reached for, so this widget has no service, no network and no
/// provider — a widget test pumps it with a stub. [onClosed] fires once when the
/// sheet is dismissed, so the caller can forget the conversation.
Future<void> showAnalysisResultSheet(
  BuildContext context, {
  required String initialText,
  required Future<AnalysisSheetReply> Function(String question) onAsk,
  VoidCallback? onClosed,
  String? title,
  Uint8List? thumbnail,
  int Function()? messagesLeft,
  List<AnalysisTurn> initialTurns = const [],
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      // Lifts the field clear of the keyboard. Without this the input the user
      // is typing into sits underneath it.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: AnalysisResultSheet(
        initialText: initialText,
        onAsk: onAsk,
        title: title,
        thumbnail: thumbnail,
        messagesLeft: messagesLeft,
        initialTurns: initialTurns,
      ),
    ),
  );
  onClosed?.call();
}

/// One answer, plus whether it was an error.
class AnalysisSheetReply {
  const AnalysisSheetReply(this.text, {this.isError = false});

  final String text;
  final bool isError;
}

class AnalysisResultSheet extends StatefulWidget {
  const AnalysisResultSheet({
    super.key,
    required this.initialText,
    required this.onAsk,
    this.title,
    this.thumbnail,
    this.messagesLeft,
    this.initialTurns = const [],
  });

  final String initialText;
  final Future<AnalysisSheetReply> Function(String question) onAsk;

  /// The photo's date, shown beside the thumbnail. Null renders no header —
  /// the widget stays pumpable with nothing but a string and a callback.
  final String? title;

  /// The same cached bytes the grid tile renders. Null is normal: a device that
  /// pulled metadata before hydrating thumbnails has none.
  final Uint8List? thumbnail;

  /// Messages the daily cap still allows, read on every build so an answer
  /// updates it. Null hides the counter entirely.
  final int Function()? messagesLeft;

  /// A stored transcript to hydrate the sheet with, oldest turn first.
  ///
  /// Empty (the default) reproduces today's behaviour exactly: a single
  /// model bubble seeded from [initialText]. Non-empty replaces that seed —
  /// this is what lets the sheet reopen a SAVED conversation instead of
  /// always starting from one fresh answer, without changing the shape of
  /// every existing call site.
  final List<AnalysisTurn> initialTurns;

  @override
  State<AnalysisResultSheet> createState() => _AnalysisResultSheetState();
}

/// Owns the conversation; [AnalysisChatView] draws it.
class _AnalysisResultSheetState extends State<AnalysisResultSheet> {
  late final List<ChatEntry> _entries = widget.initialTurns.isEmpty
      ? [ChatEntry.reply(widget.initialText)]
      : widget.initialTurns
          .map((turn) => turn.role == AnalysisRole.user
              ? ChatEntry.user(turn.text)
              : ChatEntry.reply(turn.text))
          .toList();
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _busy) return;

    setState(() {
      _entries.add(ChatEntry.user(question));
      _controller.clear();
      _busy = true;
    });

    final reply = await widget.onAsk(question);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _entries.add(reply.isError
          ? ChatEntry.error(reply.text)
          : ChatEntry.reply(reply.text));
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        // Bounded so a long conversation scrolls inside the sheet instead of
        // pushing the input field off the bottom of the screen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.title != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SheetHeader(
                  title: widget.title!,
                  thumbnail: widget.thumbnail,
                ),
              ),
            Flexible(
              child: AnalysisChatView(
                expand: false,
                entries: _entries,
                controller: _controller,
                pending: _busy,
                onSend: _busy ? null : _ask,
                messagesLeft: widget.messagesLeft?.call(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The photo this conversation is about: a thumbnail, its date, and a close.
///
/// The sheet covers the picture it describes, so without this the transcript
/// floats free of its subject — and a description of "this" is only legible
/// while you can see which "this" it means.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.thumbnail});

  final String title;
  final Uint8List? thumbnail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = thumbnail;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 40,
              height: 40,
              child: bytes == null
                  ? ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
