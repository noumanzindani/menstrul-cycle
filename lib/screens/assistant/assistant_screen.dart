import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/media_analysis.dart';
import 'assistant_backend.dart';
import 'assistant_chat_screen.dart';

/// The assistant's conversations, most recently active first, and the way
/// into a new one.
///
/// Builds with no arguments — it reads the app-wide [AssistantBackend] from
/// the tree — so it can stand as a tab. [backend] is for tests and for
/// callers that already hold one.
///
/// No `AdBanner` here or anywhere under `screens/assistant/`: conversations
/// hold photos of the user's body and what they said about their health.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.backend});

  final AssistantBackend? backend;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final AssistantBackend _backend =
      widget.backend ?? context.read<AssistantBackend>();

  List<AssistantConversation>? _conversations;

  @override
  void initState() {
    super.initState();
    if (_backend.available) _load();
  }

  Future<void> _load() async {
    final list = await _backend.conversations();
    if (!mounted) return;
    setState(() => _conversations = list);
  }

  Future<void> _openChat({String? conversationId}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AssistantChatScreen(
        backend: _backend,
        conversationId: conversationId,
      ),
    ));
    // A message sent there changes the order, the title and the preview.
    if (mounted) await _load();
  }

  Future<void> _confirmDelete(AssistantConversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this conversation?'),
        content: const Text(
          'It is deleted from this device and from your account. Photos and '
          'videos you attached stay in Photos & videos.',
        ),
        actions: [
          // One Row, each button Expanded: the theme gives every FilledButton
          // infinite width, and a bare one in a Row pushes its neighbour off
          // a 360dp screen.
          Row(
            children: [
              Expanded(
                child: TextButton(
                  key: const Key('assistant-delete-cancel'),
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const Key('assistant-delete-confirm'),
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _backend.delete(conversation.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final available = _backend.available;
    final conversations = _conversations;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      floatingActionButton: !available
          ? null
          : FloatingActionButton.extended(
              key: const Key('assistant-new-conversation'),
              heroTag: 'assistant.new',
              onPressed: () => _openChat(),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New conversation'),
            ),
      body: !available
          ? const _Message(
              key: Key('assistant-unavailable'),
              icon: Icons.forum_outlined,
              title: 'The assistant is not available here',
              body: 'It needs an account, a connection to it, and a build '
                  'that includes it. Everything else in LunarFlow works '
                  'without it.',
            )
          : conversations == null
              ? const Center(child: CircularProgressIndicator())
              : conversations.isEmpty
                  ? const _Message(
                      key: Key('assistant-empty'),
                      icon: Icons.forum_outlined,
                      title: 'No conversations yet',
                      body: 'Ask about periods, cycles, symptoms or using '
                          'LunarFlow, or attach a photo and ask about it.',
                    )
                  : ListView.builder(
                      key: const Key('assistant-conversations'),
                      // Clears the FAB.
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: conversations.length,
                      itemBuilder: (context, i) {
                        final c = conversations[i];
                        return _ConversationTile(
                          conversation: c,
                          onTap: () => _openChat(conversationId: c.id),
                          onLongPress: () => _confirmDelete(c),
                        );
                      },
                    ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onLongPress,
  });

  final AssistantConversation conversation;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final subtitle = conversation.subtitle;
    return ListTile(
      key: Key('assistant-conversation-${conversation.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: _Cover(conversation),
      title: Text(
        // A conversation that opened with a photo and no words of its own is
        // named for what it started as.
        conversation.title ?? 'Photo description',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }
}

/// The first attachment's thumbnail; a neutral tile when there is none.
class _Cover extends StatelessWidget {
  const _Cover(this.conversation);

  final AssistantConversation conversation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = conversation.cover;
    final bytes = cover?.thumbnail;
    final Widget child;
    if (bytes != null) {
      child = Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheWidth: 176,
        gaplessPlayback: true,
      );
    } else {
      final IconData icon;
      if (conversation.firstAttachment == null) {
        icon = Icons.forum_outlined;
      } else if (cover == null) {
        // Deleted since. Said plainly rather than left looking like a
        // thumbnail still on its way.
        icon = Icons.hide_image_outlined;
      } else if (conversation.firstAttachment!.kind == AttachmentKind.video) {
        icon = Icons.movie_outlined;
      } else {
        icon = Icons.image_outlined;
      }
      child = ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 44, height: 44, child: child),
    );
  }
}

/// A neutral, centred message: the empty and unavailable states. Never the
/// error colour — neither is anything the user did wrong.
class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
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
