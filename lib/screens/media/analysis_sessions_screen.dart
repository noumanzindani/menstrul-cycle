import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';

/// The saved photo-description conversations, most recently active first.
///
/// Every lookup is injected rather than reached for — no service, no
/// database, no Firebase — the same seam `AnalysisResultSheet` itself uses,
/// so this screen pumps with nothing but four callbacks in a widget test.
///
/// Rows render in EXACTLY the order [load] hands back. The repository behind
/// it already sorts by `updatedAt` descending (most recently active first);
/// re-sorting here would be a second place for that ordering to disagree with
/// the one the repository already decided.
class AnalysisSessionsScreen extends StatefulWidget {
  const AnalysisSessionsScreen({
    super.key,
    required this.load,
    required this.loadMessages,
    required this.loadMedia,
    required this.onOpen,
  });

  /// This account's saved sessions, in display order.
  final Future<List<AnalysisSession>> Function() load;

  /// One session's turns, oldest first.
  final Future<List<AnalysisMessage>> Function(String sessionId) loadMessages;

  /// The photo a session is about, for its cached thumbnail. Null is normal —
  /// a photo can be deleted independently of its saved conversation.
  final Future<MediaItem?> Function(String mediaId) loadMedia;

  /// Opens one saved conversation. Handed the row's [BuildContext] (not the
  /// screen's own) so the caller can push straight from it.
  final void Function(BuildContext context, AnalysisSession session) onOpen;

  @override
  State<AnalysisSessionsScreen> createState() =>
      _AnalysisSessionsScreenState();
}

/// What one row needs beyond the session itself.
class _RowData {
  const _RowData({this.thumbnail, this.subtitle});

  final Uint8List? thumbnail;

  /// The first `role == 'model'` message — the opening description, which is
  /// what a user scanning this list is trying to recall. A later follow-up
  /// answer is not a useful preview of which photo this conversation is
  /// about.
  final String? subtitle;
}

class _AnalysisSessionsScreenState extends State<AnalysisSessionsScreen> {
  List<AnalysisSession>? _sessions;

  /// One future per session, built once when [_sessions] arrives rather than
  /// inside `itemBuilder` — `ListView.builder` re-invokes `itemBuilder` on
  /// every scroll frame near a boundary, and re-calling [widget.loadMessages]
  /// / [widget.loadMedia] each time would re-read the database (and the
  /// caller may re-download a thumbnail) for the same row repeatedly.
  final Map<String, Future<_RowData>> _rows = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.load();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      for (final session in sessions) {
        _rows[session.id] = _loadRow(session);
      }
    });
  }

  Future<_RowData> _loadRow(AnalysisSession session) async {
    final messages = await widget.loadMessages(session.id);
    final media = await widget.loadMedia(session.mediaId);
    AnalysisMessage? firstReply;
    for (final message in messages) {
      if (message.role == 'model') {
        firstReply = message;
        break;
      }
    }
    return _RowData(
      thumbnail: media?.thumbnail,
      subtitle: firstReply?.messageText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved descriptions')),
      body: sessions == null
          ? const Center(child: CircularProgressIndicator())
          : sessions.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  key: const Key('analysis-sessions-list'),
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    return _SessionTile(
                      session: session,
                      rowFuture: _rows[session.id]!,
                      onTap: () => widget.onOpen(context, session),
                    );
                  },
                ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.rowFuture,
    required this.onTap,
  });

  final AnalysisSession session;
  final Future<_RowData> rowFuture;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<_RowData>(
      future: rowFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data?.thumbnail;
        final subtitle = snapshot.data?.subtitle;
        return ListTile(
          key: Key('analysis-session-${session.id}'),
          onTap: onTap,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 44,
              height: 44,
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
                      cacheWidth: 176,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          title: Text(_dateLabel(session.updatedAt)),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        );
      },
    );
  }
}

/// "Today" / "Yesterday" / a short date — the same relative-date shape used
/// elsewhere in the app, so a saved conversation reads the way a recently
/// active thread should rather than as a raw timestamp.
String _dateLabel(DateTime updatedAt, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
  final start = DateTime(today.year, today.month, today.day);
  final diff = start.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat.yMMMd().format(updatedAt);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
              Icons.forum_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text('No saved descriptions yet',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Conversations you have about a photo are kept here so you can '
              'reopen them.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
