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
      child: AnalysisResultSheet(initialText: initialText, onAsk: onAsk),
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
  });

  final String initialText;
  final Future<AnalysisSheetReply> Function(String question) onAsk;

  @override
  State<AnalysisResultSheet> createState() => _AnalysisResultSheetState();
}

class _AnalysisResultSheetState extends State<AnalysisResultSheet> {
  late final List<_Message> _messages = [
    _Message(widget.initialText, fromUser: false),
  ];
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              // means the answer IS reliable.
              Text(
                kAnalysisCaveat,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('analysis-question-field'),
                      controller: _controller,
                      maxLength: kMaxQuestionLength,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(),
                      decoration: const InputDecoration(
                        hintText: 'Ask about this photo',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('analysis-ask-button'),
                    onPressed: _busy ? null : _ask,
                    icon: const Icon(Icons.arrow_upward),
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

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final Color background;
    final Color foreground;
    if (message.isError) {
      background = scheme.errorContainer;
      foreground = scheme.onErrorContainer;
    } else if (message.fromUser) {
      background = scheme.primaryContainer;
      foreground = scheme.onPrimaryContainer;
    } else {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurface;
    }

    return Align(
      alignment:
          message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        // Selectable so a description can be copied out — the reason the
        // single-answer version used SelectableText, kept here per bubble.
        child: SelectableText(
          message.text,
          style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
        ),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('analysis-pending'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
