import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../data/analysis_session_repository.dart';
import '../../db/database.dart';
import '../../services/assistant_image_prep.dart';
import '../../services/media_analysis.dart';
import '../../services/media_analysis_service.dart';
import '../../services/media_paths.dart';
import '../../services/media_picker_config.dart';
import '../../services/media_upload_service.dart';
import 'analysis_chat_view.dart';
import 'assistant_backend.dart';

/// Saves one errorless exchange; the shape `MediaAnalysisService` calls.
typedef PersistTurn = Future<void> Function({
  required String conversationId,
  required String question,
  required List<AttachmentRef> attachments,
  required String answer,
  required bool isMemoHit,
});

/// The real [AssistantBackend]: the analysis service, the conversation store
/// and the uploader, joined up.
///
/// Every dependency is injected, and the construction that touches Firebase
/// lives in `media_route.dart`, so this class runs under plain `flutter test`
/// against an in-memory database and a fake analyzer.
///
/// It owns the service (see [LiveAssistantBackend.new]'s `service`), because
/// the service saves each answer through [persistTurn] here — the service
/// itself may never reach the database (`test/media_guardrails_test.dart`).
class LiveAssistantBackend implements AssistantBackend {
  LiveAssistantBackend({
    required bool available,
    required MediaAnalysisService Function(PersistTurn persistTurn) service,
    required AnalysisSessionRepository sessions,
    required String? Function() currentUid,
    required Future<MediaItem?> Function(String mediaId) loadMedia,
    required Future<List<MediaItem>> Function(String uid) libraryFor,
    required Future<(Uint8List, String)> Function(MediaItem item) loadOriginal,
    String? Function()? healthContext,
    Future<bool> Function(String uid)? syncOn,
    Future<MediaUploadOutcome> Function(MediaSource source, {int? limit})?
        pickAndUpload,
    Future<bool> Function(BuildContext context)? requestConsent,
    Future<bool> Function(BuildContext context)? earnConversation,
    AssistantImagePrep? prep,
    VoidCallback? onMediaAdded,
  })  : _available = available,
        _sessions = sessions,
        _currentUid = currentUid,
        _loadMedia = loadMedia,
        _libraryFor = libraryFor,
        _loadOriginal = loadOriginal,
        _healthContext = healthContext,
        _syncOn = syncOn,
        _pickAndUpload = pickAndUpload,
        _requestConsent = requestConsent,
        _earnConversation = earnConversation,
        _prep = prep ?? AssistantImagePrep(),
        _onMediaAdded = onMediaAdded {
    this.service = service(persistTurn);
  }

  /// A key is compiled in and Firebase is up — fixed for the app's life.
  final bool _available;

  /// [_available] AND someone is signed in, read fresh: the local-only hatch
  /// and a sign-out both leave no account for a conversation to belong to.
  @override
  bool get available => _available && _currentUid() != null;

  /// The one analysis service, app-wide: its memo, caps and in-memory
  /// conversations are shared by the Assistant tab and Describe.
  late final MediaAnalysisService service;

  final AnalysisSessionRepository _sessions;
  final String? Function() _currentUid;
  final Future<MediaItem?> Function(String mediaId) _loadMedia;
  final Future<List<MediaItem>> Function(String uid) _libraryFor;
  final Future<(Uint8List, String)> Function(MediaItem item) _loadOriginal;
  final String? Function()? _healthContext;
  final Future<bool> Function(String uid)? _syncOn;
  final Future<MediaUploadOutcome> Function(MediaSource source, {int? limit})?
      _pickAndUpload;
  final Future<bool> Function(BuildContext context)? _requestConsent;
  final Future<bool> Function(BuildContext context)? _earnConversation;
  final AssistantImagePrep _prep;
  final VoidCallback? _onMediaAdded;

  /// How a conversation that has no row yet should be created: the photo it
  /// started from and its first words. Set by [send] before the service can
  /// call [persistTurn], and dropped only when that send returns — NOT by
  /// [endConversation]: a chat closed while its first send is out still gets
  /// its reply saved, and without this the row would be created with no
  /// photo and no title, so Describe could never find it again.
  final Map<String, ({String originMediaId, String title})> _pending = {};

  /// Which opening of each conversation a send belongs to. Dropped by
  /// [endConversation], so a send still loading photos when its chat closes
  /// does not hand them to the service afterwards.
  final Map<String, Object> _openings = {};

  /// Photos a resumed conversation attached that the service has not been
  /// handed yet. Loaded at the next send, not at [open]: reading a
  /// transcript must not download anything.
  final Map<String, Set<String>> _unseeded = {};

  /// Bumped after every save and delete; see [changes].
  final ValueNotifier<int> _revision = ValueNotifier(0);

  @override
  Listenable get changes => _revision;

  @override
  bool get needsConsent => !service.consented;

  @override
  int get messagesLeft => service.remainingToday;

  @override
  bool get canCapture => _pickAndUpload != null;

  @override
  String newConversationId() => newMediaId();

  @override
  Future<bool> requestConsent(BuildContext context) async =>
      await _requestConsent?.call(context) ?? false;

  // No gate wired means no ad to earn: a test, or a build with no ads.
  @override
  Future<bool> earnConversation(BuildContext context) async =>
      await _earnConversation?.call(context) ?? true;

  @override
  Future<String?> preflight({
    String? conversationId,
    List<MediaItem> attachments = const [],
  }) async {
    final block = await service.preflight(
      conversationId: conversationId,
      newImageIds: {
        for (final a in attachments)
          if (a.kind != 'video') a.id,
      },
    );
    return block == null ? null : messageForAnalysisBlock(block);
  }

  @override
  Future<List<AssistantConversation>> conversations() async {
    final uid = _currentUid();
    if (uid == null) return const [];
    final rows = await _sessions.allFor(uid);
    final out = <AssistantConversation>[];
    for (final session in rows) {
      final messages = await _sessions.messagesFor(session.id);
      final refs = _refsFor(session, messages);
      AttachmentRef? first;
      for (final list in refs) {
        if (list.isNotEmpty) {
          first = list.first;
          break;
        }
      }
      // The first real answer. The declined-video notice is the app talking,
      // not a reply, and would make every such row read the same.
      String? subtitle;
      for (final m in messages) {
        if (m.role == AnalysisRole.model.name && m.includeInModel) {
          subtitle = m.messageText;
          break;
        }
      }
      out.add(AssistantConversation(
        id: session.id,
        updatedAt: session.updatedAt,
        title: session.title,
        subtitle: subtitle,
        firstAttachment: first,
        cover: first == null ? null : await _loadMedia(first.mediaId),
      ));
    }
    return out;
  }

  @override
  Future<String?> conversationForMedia(String mediaId) async {
    final uid = _currentUid();
    if (uid == null) return null;
    return (await _sessions.forMedia(uid: uid, mediaId: mediaId))?.id;
  }

  @override
  Future<List<ChatEntry>> open(String conversationId) async {
    final session = await _sessions.byId(conversationId);
    if (session == null ||
        session.deletedAt != null ||
        session.uid != _currentUid()) {
      return const [];
    }
    final messages = await _sessions.messagesFor(conversationId);
    final refs = _refsFor(session, messages);

    final entries = <ChatEntry>[];
    final turns = <AnalysisTurn>[];
    final images = <String>{};
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final isUser = m.role == AnalysisRole.user.name;
      if (isUser) {
        entries.add(ChatEntry.user(m.messageText, attachments: [
          for (final ref in refs[i])
            ChatAttachment(
              mediaId: ref.mediaId,
              kind: ref.kind,
              item: await _loadMedia(ref.mediaId),
            ),
        ]));
        if (m.includeInModel) {
          images.addAll([
            for (final ref in refs[i])
              if (ref.kind == AttachmentKind.image) ref.mediaId,
          ]);
        }
      } else {
        entries.add(m.includeInModel
            ? ChatEntry.reply(m.messageText)
            : ChatEntry.notice(m.messageText));
      }
      // includeInModel is carried over rather than filtered here: the request
      // builder is what leaves such a turn out of what the model sees.
      turns.add(isUser
          ? AnalysisTurn.user(m.messageText,
              attachments: refs[i], includeInModel: m.includeInModel)
          : AnalysisTurn.model(m.messageText,
              attachments: refs[i], includeInModel: m.includeInModel));
    }
    // Seeds the SERVICE, not just the screen: its transcript is the only
    // history `analyze` sends, and `generateContent` remembers nothing.
    service.seedConversation(conversationId, turns);
    if (images.isNotEmpty) _unseeded[conversationId] = images;
    return entries;
  }

  @override
  Future<void> delete(String conversationId) async {
    endConversation(conversationId);
    await _sessions.tombstone(conversationId);
    _revision.value++;
  }

  @override
  void endConversation(String conversationId) {
    service.endConversation(conversationId);
    _unseeded.remove(conversationId);
    _openings.remove(conversationId);
  }

  @override
  Future<AssistantReply> send({
    required String conversationId,
    String originMediaId = '',
    required String text,
    List<MediaItem> attachments = const [],
  }) async {
    _pending[conversationId] = (originMediaId: originMediaId, title: text);
    try {
      return await _send(conversationId, text, attachments);
    } finally {
      _pending.remove(conversationId);
    }
  }

  Future<AssistantReply> _send(
    String conversationId,
    String text,
    List<MediaItem> attachments,
  ) async {
    final hasVideo = attachments.any((a) => a.kind == 'video');
    final opening = _openings.putIfAbsent(conversationId, Object.new);

    final prepared = <AnalysisAttachment>[];
    if (hasVideo) {
      // The whole message is declined, so no photo in it is read either.
      for (final a in attachments) {
        prepared.add(AnalysisAttachment.video(a.id));
      }
    } else {
      try {
        await _seedEarlierPhotos(conversationId, opening);
        for (final a in attachments) {
          final image = await _prep.prepare(a.id, () => _loadOriginal(a));
          prepared.add(AnalysisAttachment.image(
            mediaId: a.id,
            mimeType: image.mimeType,
            bytes: image.bytes,
          ));
        }
      } catch (_) {
        return const AssistantReply(
          AssistantReplyKind.failed,
          "That photo couldn't be loaded. Try again.",
        );
      }
    }

    final outcome = await service.analyze(
      conversationId: conversationId,
      attachments: prepared,
      question: text,
      healthContext: _healthContext?.call(),
    );

    if (outcome.videoDeclined) {
      await _persistDeclined(conversationId, text, attachments);
      return const AssistantReply(
          AssistantReplyKind.declined, kVideoDeclinedNotice);
    }
    final blocked = outcome.blocked;
    if (blocked != null) {
      return AssistantReply(
          AssistantReplyKind.failed, messageForAnalysisBlock(blocked));
    }
    final error = outcome.error;
    if (error != null) {
      return AssistantReply(AssistantReplyKind.failed, error);
    }
    final prose = outcome.result?.prose;
    if (prose == null || prose.trim().isEmpty) {
      return const AssistantReply(
          AssistantReplyKind.failed, 'No answer came back. Try again.');
    }
    return AssistantReply(AssistantReplyKind.answer, prose);
  }

  /// Hands the service the photos of a resumed conversation. A photo that has
  /// since been deleted is simply left out, and the request builder sends the
  /// deleted-photo placeholder in its place.
  ///
  /// A photo that exists but would not load (offline, say) is NOT left out:
  /// that would tell the model the user deleted it. The ones that loaded are
  /// seeded, the rest stay owed for the next send, and the error is rethrown
  /// so this send fails instead of going out without them.
  Future<void> _seedEarlierPhotos(String conversationId, Object opening) async {
    final ids = _unseeded.remove(conversationId);
    if (ids == null) return;
    final images = <String, InlineImage>{};
    final owed = <String>{};
    Object? failure;
    StackTrace? trace;
    for (final id in ids) {
      try {
        final item = await _loadMedia(id);
        if (item == null) continue;
        final image = await _prep.prepare(id, () => _loadOriginal(item));
        images[id] = InlineImage(
          mimeType: image.mimeType,
          base64: base64Encode(image.bytes),
        );
      } catch (e, s) {
        owed.add(id);
        failure ??= e;
        trace ??= s;
      }
    }
    // Closed while the photos loaded: the service has already forgotten this
    // conversation, and a reopen seeds it afresh.
    if (!identical(_openings[conversationId], opening)) return;
    service.seedConversation(conversationId, const [], images: images);
    if (failure != null) {
      _unseeded.putIfAbsent(conversationId, () => {}).addAll(owed);
      Error.throwWithStackTrace(failure, trace!);
    }
  }

  /// Saves the declined-video pair, both halves out of the model's sight.
  Future<void> _persistDeclined(
    String conversationId,
    String text,
    List<MediaItem> attachments,
  ) async {
    final uid = _currentUid();
    if (uid == null) return;
    final session = await _sessionFor(conversationId, uid);
    if (session == null) return;
    await _sessions.append(
      sessionId: session.id,
      role: AnalysisRole.user.name,
      text: sentTextFor(text, hasVideo: true),
      attachments: [
        for (final a in attachments)
          a.kind == 'video'
              ? AttachmentRef.video(a.id)
              : AttachmentRef.image(a.id),
      ],
      includeInModel: false,
    );
    await _sessions.append(
      sessionId: session.id,
      role: AnalysisRole.model.name,
      text: kVideoDeclinedNotice,
      includeInModel: false,
    );
    _revision.value++;
  }

  /// Saves one errorless exchange; handed to the service at construction.
  ///
  /// [isMemoHit] (see `MediaAnalysisService._persistTurn`'s doc comment): a
  /// memo hit re-serves an answer already shown once, and
  /// `AnalysisSessionRepository.append` is a pure insert, so persisting it
  /// into a conversation that already exists would duplicate it. When NO row
  /// exists yet it is saved, because a later follow-up needs its opening turn.
  Future<void> persistTurn({
    required String conversationId,
    required String question,
    required List<AttachmentRef> attachments,
    required String answer,
    required bool isMemoHit,
  }) async {
    final uid = _currentUid();
    if (uid == null) return;
    final existing = await _sessions.byId(conversationId);
    if (isMemoHit && existing != null) return;
    final session = await _sessionFor(conversationId, uid, existing: existing);
    if (session == null) return;
    await _sessions.append(
      sessionId: session.id,
      role: AnalysisRole.user.name,
      text: question,
      attachments: attachments,
    );
    await _sessions.append(
      sessionId: session.id,
      role: AnalysisRole.model.name,
      text: answer,
    );
    _revision.value++;
  }

  /// The row for [conversationId], created on first use. Null when it was
  /// deleted while the chat was open — on this device or synced in from
  /// another — which must not bring it back under the same id.
  Future<AnalysisSession?> _sessionFor(
    String conversationId,
    String uid, {
    AnalysisSession? existing,
  }) async {
    final row = existing ?? await _sessions.byId(conversationId);
    if (row != null) return row.deletedAt == null ? row : null;
    final pending = _pending[conversationId];
    return _sessions.create(
      id: conversationId,
      uid: uid,
      mediaId: pending?.originMediaId ?? '',
      title: pending?.title,
      consentVersion: kCurrentConsentVersion,
    );
  }

  @override
  Future<AttachOutcome> capture(MediaSource source, {required int limit}) async {
    final pick = _pickAndUpload;
    if (pick == null) return const AttachOutcome();
    final uid = _currentUid();
    if (uid == null) {
      return AttachOutcome(
          message: messageForAnalysisBlock(AnalysisBlock.notSignedIn));
    }
    // Asked BEFORE the picker opens: the upload would refuse anyway, and
    // taking a photo only to be told it cannot be kept wastes the moment.
    final syncOn = _syncOn;
    if (syncOn != null && !await syncOn(uid)) {
      return AttachOutcome(
          message: messageForAnalysisBlock(AnalysisBlock.syncOff));
    }
    final outcome = await pick(source, limit: limit);
    if (outcome.isBlocked) {
      return AttachOutcome(
          message: messageForAnalysisBlock(AnalysisBlock.syncOff));
    }
    final items = <MediaItem>[
      for (final id in outcome.uploadedIds) ?await _loadMedia(id),
    ];
    if (items.isNotEmpty) _onMediaAdded?.call();
    final rejected = outcome.rejected.map((r) => r.message).toSet();
    return AttachOutcome(
      items: items,
      failed: outcome.failed + outcome.rejected.length,
      message: rejected.isEmpty ? null : rejected.join(' · '),
    );
  }

  @override
  Future<List<MediaItem>> library() async {
    final uid = _currentUid();
    if (uid == null) return const [];
    return _libraryFor(uid);
  }

  List<List<AttachmentRef>> _refsFor(
    AnalysisSession session,
    List<AnalysisMessage> messages,
  ) =>
      // A v15 session stored no attachments; its photo is the session's, on
      // the first user turn — `effectiveAttachments` restores that reading.
      effectiveAttachments(session.mediaId, [
        for (final m in messages)
          (role: m.role, attachmentsJson: m.attachmentsJson),
      ]);
}
