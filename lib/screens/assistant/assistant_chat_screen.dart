import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../services/media_analysis.dart';
import '../../services/media_picker_config.dart';
import 'analysis_chat_view.dart';
import 'assistant_backend.dart';
import 'media_select_sheet.dart';

/// Where an attachment comes from.
enum _AttachSource { camera, video, gallery, library }

/// One assistant conversation, new or resumed.
///
/// The screen holds the conversation; [AssistantBackend] does everything that
/// leaves it. Three rules live here because only the screen knows them:
///
/// * **Consent, then the ad, then the send.** Consent first so nobody watches
///   an ad and then meets a sheet they decline — a reward taken and never
///   delivered.
/// * **The ad is for the first billable send of a NEW conversation only.** A
///   resumed conversation, a follow-up and a message carrying a video (which
///   is never sent, so never billed) are never gated.
/// * **One send in flight, and none while an attachment is uploading.** Every
///   send bills, and a message must not leave without the photo it is about.
class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({
    super.key,
    this.backend,
    this.conversationId,
    this.pendingAttachments = const [],
    this.adEarned = false,
  });

  /// Null reads the app-wide one from the tree.
  final AssistantBackend? backend;

  /// A saved conversation to resume. Null starts a new one.
  final String? conversationId;

  /// Photos to send straight away with the default question: Describe opens
  /// the chat this way. The first one is also the photo the conversation is
  /// filed under, which is how Describe finds it again.
  final List<MediaItem> pendingAttachments;

  /// The caller already ran the consent and ad gates for this conversation.
  final bool adEarned;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  late final AssistantBackend _backend =
      widget.backend ?? context.read<AssistantBackend>();
  late final String _conversationId =
      widget.conversationId ?? _backend.newConversationId();
  late final String _originMediaId = widget.pendingAttachments.isEmpty
      ? ''
      : widget.pendingAttachments.first.id;

  final _controller = TextEditingController();
  final List<ChatEntry> _entries = [];
  final List<PendingAttachment> _chips = [];
  int _seq = 0;

  bool _loading = false;
  bool _busy = false;

  /// Whether this conversation may send without the ad: it was resumed, the
  /// caller already earned it, or the ad was watched here.
  late bool _earned = widget.adEarned || widget.conversationId != null;

  /// A standing line above the composer, such as why an attach failed.
  String? _notice;

  bool get _uploading => _chips.any((c) => c.state == PendingState.uploading);
  bool get _atCap => _backend.messagesLeft <= 0;

  @override
  void initState() {
    super.initState();
    if (widget.conversationId != null) _load();
    if (widget.pendingAttachments.isNotEmpty) {
      _chips.addAll([
        for (final item in widget.pendingAttachments.take(
            kMaxAttachmentsPerMessage))
          PendingAttachment(
              key: item.id, state: PendingState.ready, item: item),
      ]);
      // After the first frame, so the gates have a context to show from.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send();
      });
    }
  }

  @override
  void dispose() {
    _backend.endConversation(_conversationId);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _backend.open(_conversationId);
    if (!mounted) return;
    setState(() {
      _entries.insertAll(0, entries);
      _loading = false;
    });
  }

  Future<void> _send() async {
    if (_busy || _uploading || _atCap) return;
    final typed = _controller.text.trim();
    final attachments = [
      for (final c in _chips)
        if (c.state == PendingState.ready && c.item != null) c.item!,
    ];
    if (typed.isEmpty && attachments.isEmpty) return;
    final hasVideo = attachments.any((a) => a.kind == 'video');

    // Held while the gates run, so a second tap cannot start a second send.
    setState(() => _busy = true);
    if (_backend.needsConsent && !await _backend.requestConsent(context)) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    if (!_earned && !hasVideo) {
      if (!await _backend.earnConversation(context)) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      _earned = true;
    }
    if (!mounted) return;

    setState(() {
      _entries.add(ChatEntry.user(
        sentTextFor(typed, hasVideo: hasVideo),
        attachments: [
          for (final a in attachments)
            ChatAttachment(
              mediaId: a.id,
              kind: a.kind == 'video'
                  ? AttachmentKind.video
                  : AttachmentKind.image,
              item: a,
            ),
        ],
      ));
      _controller.clear();
      _chips.clear();
      _notice = null;
    });

    final reply = await _backend.send(
      conversationId: _conversationId,
      originMediaId: _originMediaId,
      text: typed,
      attachments: attachments,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _entries.add(switch (reply.kind) {
        AssistantReplyKind.answer => ChatEntry.reply(reply.text),
        AssistantReplyKind.declined => ChatEntry.notice(reply.text),
        AssistantReplyKind.failed => ChatEntry.error(reply.text),
      });
    });
  }

  int get _slots => kMaxAttachmentsPerMessage - _chips.length;

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<_AttachSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_backend.canCapture) ...[
              ListTile(
                key: const Key('assistant-attach-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take photo'),
                onTap: () => Navigator.pop(sheetContext, _AttachSource.camera),
              ),
              ListTile(
                key: const Key('assistant-attach-video'),
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record video'),
                onTap: () => Navigator.pop(sheetContext, _AttachSource.video),
              ),
              ListTile(
                key: const Key('assistant-attach-gallery'),
                leading: const Icon(Icons.photo_outlined),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.pop(sheetContext, _AttachSource.gallery),
              ),
            ],
            ListTile(
              key: const Key('assistant-attach-library'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('From Photos & videos'),
              onTap: () => Navigator.pop(sheetContext, _AttachSource.library),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AttachSource.camera:
        await _capture(MediaSource.camera);
      case _AttachSource.video:
        await _capture(MediaSource.videoCamera);
      case _AttachSource.gallery:
        await _capture(MediaSource.library);
      case _AttachSource.library:
        await _pickStored();
    }
  }

  /// Takes or picks something new. It is uploaded to Photos & videos first —
  /// a message carries only a reference — so a chip holds a spinner until the
  /// upload lands, and Send waits for it.
  Future<void> _capture(MediaSource source) async {
    final slots = _slots;
    if (slots <= 0) return;
    final key = 'upload-${_seq++}';
    setState(() {
      _chips.add(PendingAttachment(key: key, state: PendingState.uploading));
      _notice = null;
    });

    AttachOutcome outcome;
    try {
      outcome = await _backend.capture(source, limit: slots);
    } catch (_) {
      outcome = const AttachOutcome(failed: 1);
    }
    if (!mounted) return;
    setState(() {
      final at = _chips.indexWhere((c) => c.key == key);
      if (at < 0) return; // removed while it uploaded
      final fresh = outcome.items
          .where((item) => !_chips.any((c) => c.item?.id == item.id))
          .take(slots)
          .map((item) => PendingAttachment(
              key: item.id, state: PendingState.ready, item: item))
          .toList();
      _chips.replaceRange(at, at + 1, [
        ...fresh,
        if (outcome.failed > 0)
          PendingAttachment(key: key, state: PendingState.failed),
      ]);
      _notice = outcome.message;
    });
  }

  /// Attaches something already in Photos & videos. Nothing is uploaded.
  Future<void> _pickStored() async {
    final items = await _backend.library();
    if (!mounted) return;
    final chosen =
        await showMediaSelectSheet(context, items: items, max: _slots);
    if (chosen == null || !mounted) return;
    setState(() {
      for (final item in chosen) {
        if (_slots <= 0) break;
        if (_chips.any((c) => c.item?.id == item.id)) continue;
        _chips.add(PendingAttachment(
            key: item.id, state: PendingState.ready, item: item));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !_busy && !_uploading && !_atCap && !_loading;
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : AnalysisChatView(
                entries: _entries,
                controller: _controller,
                pending: _busy && _entries.isNotEmpty && _entries.last.fromUser,
                onSend: canSend ? _send : null,
                messagesLeft: _backend.messagesLeft,
                notice: _atCap
                    ? messageForAnalysisBlock(AnalysisBlock.dailyCap)
                    : _notice,
                onAttach: _attach,
                attachEnabled: !_busy && _slots > 0,
                attachments: _chips,
                onRemoveAttachment: (chip) =>
                    setState(() => _chips.removeWhere((c) => c.key == chip.key)),
                hintText:
                    _entries.isEmpty ? 'Ask a question' : 'Ask a follow-up',
              ),
      ),
    );
  }
}
