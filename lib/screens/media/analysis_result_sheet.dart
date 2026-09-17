import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/media_analysis.dart';

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

/// One line of the on-screen transcript.
///
/// Not the same thing as an `AnalysisTurn`: errors and refusals appear here for
/// the user to read but are never sent back to the model as conversation.
class _Message {
  const _Message(this.text, {required this.fromUser, this.isError = false});

  final String text;
  final bool fromUser;
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

class _AnalysisResultSheetState extends State<AnalysisResultSheet> {
  late final List<_Message> _messages = widget.initialTurns.isEmpty
      ? [_Message(widget.initialText, fromUser: false)]
      : widget.initialTurns
          .map((turn) => _Message(
                turn.text,
                fromUser: turn.role == AnalysisRole.user,
              ))
          .toList();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Rides a post-frame callback because the new bubble has not been laid out
  /// yet when setState returns — `maxScrollExtent` would still be the old one.
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

  Future<void> _ask() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _busy) return;

    setState(() {
      _messages.add(_Message(question, fromUser: true));
      _controller.clear();
      _busy = true;
    });
    _scrollToEnd();

    final reply = await widget.onAsk(question);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _messages.add(
        _Message(reply.text, fromUser: false, isError: reply.isError),
      );
    });
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        // Bounded so a long conversation scrolls inside the sheet instead of
        // pushing the input field off the bottom of the screen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.title != null)
                _SheetHeader(
                  title: widget.title!,
                  thumbnail: widget.thumbnail,
                ),
              Flexible(
                child: ListView.builder(
                  key: const Key('analysis-transcript'),
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length + (_busy ? 1 : 0),
                  itemBuilder: (context, i) => i == _messages.length
                      ? const _Pending()
                      : _Bubble(_messages[i]),
                ),
              ),
              const SizedBox(height: 12),
              // Fixed, always present, never conditional on what came back. A
              // caveat shown only sometimes teaches the user that its absence
              // means the answer IS reliable. It sits under the transcript
              // rather than under each answer so that there is exactly one of
              // it, always, whatever the conversation did.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kAnalysisCaveat,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.messagesLeft != null) ...[
                const SizedBox(height: 10),
                Text(
                  // "messages", not "photos": every turn of a conversation
                  // bills, so the cap counts turns. Same wording as the
                  // refusal copy the user meets when it runs out.
                  '${widget.messagesLeft!()} of $kMaxAnalysesPerDay messages '
                  'left today',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('analysis-question-field'),
                      controller: _controller,
                      maxLength: kMaxQuestionLength,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 3,
                      onSubmitted: (_) => _ask(),
                      decoration: InputDecoration(
                        hintText: 'Ask a follow-up',
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
                    onPressed: _busy ? null : _ask,
                    icon: const Icon(Icons.arrow_upward),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(52, 52),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // The user's own words are a bubble; the model's answer is plain prose.
    // That asymmetry is deliberate — the answer is the content of this sheet,
    // and a tinted container around it makes it look like a quoted verdict
    // rather than a paragraph the user is meant to read and weigh.
    if (!message.fromUser) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 24, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.isError) ...[
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
              // Selectable so a description can be copied out — the reason the
              // single-answer version used SelectableText, kept here.
              child: SelectableText(
                message.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.45,
                  color: message.isError ? scheme.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          message.text,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
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
