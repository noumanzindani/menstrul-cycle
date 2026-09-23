import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/assistant/analysis_chat_view.dart';
import 'package:menstrul_track/screens/assistant/assistant_backend.dart';
import 'package:menstrul_track/services/media_picker_config.dart';

/// A hand-written [AssistantBackend] for widget tests. Every call is recorded
/// in [calls], in order, so a test can assert what happened and in what
/// sequence (consent before the ad, the ad before the send).
class FakeAssistantBackend implements AssistantBackend {
  FakeAssistantBackend({
    this.available = true,
    this.needsConsent = false,
    this.messagesLeft = 20,
    this.canCapture = true,
    this.consentGranted = true,
    this.adEarned = true,
    this.saved = const {},
    List<AssistantConversation> conversations = const [],
    this.libraryItems = const [],
  }) : list = List.of(conversations);

  final List<String> calls = [];

  @override
  bool available;
  @override
  bool needsConsent;
  @override
  int messagesLeft;
  @override
  bool canCapture;

  bool consentGranted;
  bool adEarned;

  /// Stored transcripts by conversation id, for [open].
  Map<String, List<ChatEntry>> saved;

  /// What [conversations] returns. Mutable, so [delete] can remove from it.
  final List<AssistantConversation> list;

  List<MediaItem> libraryItems;

  /// The next reply [send] gives. A [Completer] holds it in flight.
  AssistantReply reply = const AssistantReply(AssistantReplyKind.answer, 'An answer.');
  Completer<AssistantReply>? gate;

  /// Every send, as it was made.
  final List<
      ({
        String conversationId,
        String originMediaId,
        String text,
        List<MediaItem> attachments,
      })> sends = [];

  /// What [capture] resolves to. A [Completer] holds the upload in flight.
  AttachOutcome captureOutcome = const AttachOutcome();
  Completer<AttachOutcome>? captureGate;

  /// Held uploads handed out one per [capture], in order, ahead of
  /// [captureGate]: for overlapping captures that resolve differently.
  final List<Completer<AttachOutcome>> captureQueue = [];
  final List<int> captureLimits = [];
  int? lastCaptureLimit;

  final List<String> ended = [];
  final List<String> deleted = [];

  String? forMedia;

  final _changes = ValueNotifier<int>(0);

  @override
  Listenable get changes => _changes;

  /// What a save or delete made somewhere else looks like to a listener.
  void changed() => _changes.value++;

  @override
  String newConversationId() => 'new-chat';

  @override
  Future<bool> requestConsent(BuildContext context) async {
    calls.add('consent');
    if (consentGranted) needsConsent = false;
    return consentGranted;
  }

  @override
  Future<bool> earnConversation(BuildContext context) async {
    calls.add('ad');
    return adEarned;
  }

  /// What [preflight] answers. Its calls are counted in [preflights], not
  /// [calls], so the gate-order assertions stay about the gates the user sees.
  String? preflightBlock;
  int preflights = 0;

  @override
  Future<String?> preflight({
    String? conversationId,
    List<MediaItem> attachments = const [],
  }) async {
    preflights++;
    return preflightBlock;
  }

  @override
  Future<List<AssistantConversation>> conversations() async {
    calls.add('list');
    return List.of(list);
  }

  @override
  Future<String?> conversationForMedia(String mediaId) async => forMedia;

  @override
  Future<List<ChatEntry>> open(String conversationId) async {
    calls.add('open');
    return saved[conversationId] ?? const [];
  }

  @override
  Future<void> delete(String conversationId) async {
    deleted.add(conversationId);
    list.removeWhere((c) => c.id == conversationId);
  }

  @override
  Future<AssistantReply> send({
    required String conversationId,
    String originMediaId = '',
    required String text,
    List<MediaItem> attachments = const [],
  }) async {
    calls.add('send');
    sends.add((
      conversationId: conversationId,
      originMediaId: originMediaId,
      text: text,
      attachments: attachments,
    ));
    final result = await (gate?.future ?? Future.value(reply));
    if (result.kind == AssistantReplyKind.answer && messagesLeft > 0) {
      messagesLeft--;
    }
    return result;
  }

  @override
  Future<AttachOutcome> capture(MediaSource source, {required int limit}) async {
    calls.add('capture:${source.name}');
    lastCaptureLimit = limit;
    captureLimits.add(limit);
    if (captureQueue.isNotEmpty) return captureQueue.removeAt(0).future;
    return captureGate?.future ?? captureOutcome;
  }

  @override
  Future<List<MediaItem>> library() async => libraryItems;

  @override
  void endConversation(String conversationId) => ended.add(conversationId);
}

/// A stored item, image by default, with a real one-pixel thumbnail.
MediaItem fakeMedia(String id, {String kind = 'image', int? durationMs}) =>
    MediaItem(
      id: id,
      uid: 'u1',
      kind: kind,
      storagePath: 'users/u1/media/$id/original.jpg',
      bytes: 10,
      durationMs: durationMs,
      capturedAt: DateTime(2026, 9, 1),
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      thumbnail: kind == 'image' ? Uint8List.fromList(tinyPng) : null,
    );

/// The smallest valid PNG, so `Image.memory` has something real to decode.
const List<int> tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
