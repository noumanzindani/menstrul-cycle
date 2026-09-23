import 'package:flutter/widgets.dart';

import '../../db/database.dart';
import '../../services/media_analysis.dart';
import '../../services/media_picker_config.dart';
import 'analysis_chat_view.dart';

/// A saved conversation, as the conversation list shows it.
class AssistantConversation {
  const AssistantConversation({
    required this.id,
    required this.updatedAt,
    this.title,
    this.subtitle,
    this.firstAttachment,
    this.cover,
  });

  final String id;
  final DateTime updatedAt;

  /// The first thing the user typed. Null for a conversation that opened
  /// with a photo and no words, which the list calls a photo description.
  final String? title;

  /// The first answer.
  final String? subtitle;

  /// What the conversation first attached, if anything.
  final AttachmentRef? firstAttachment;

  /// The stored item behind [firstAttachment], for its thumbnail. Null when
  /// there was no attachment or it has since been deleted.
  final MediaItem? cover;
}

/// How a send ended.
enum AssistantReplyKind {
  /// The model answered.
  answer,

  /// The message attached a video and was declined on the device: nothing was
  /// sent, nothing counted, and the pair was saved so the chat shows it.
  declined,

  /// Refused or failed. [AssistantReply.text] is user-facing copy, and
  /// nothing was saved.
  failed,
}

class AssistantReply {
  const AssistantReply(this.kind, this.text);

  final AssistantReplyKind kind;
  final String text;
}

/// What an attach from the camera or the system picker produced.
class AttachOutcome {
  const AttachOutcome({this.items = const [], this.failed = 0, this.message});

  /// Uploaded, saved to Photos & videos, and ready to attach.
  final List<MediaItem> items;

  /// How many were picked but did not upload.
  final int failed;

  /// Why nothing was attempted, or what was refused. User-facing copy.
  final String? message;

  /// The user backed out of the picker: nothing picked, nothing to report.
  bool get cancelled => items.isEmpty && failed == 0 && message == null;
}

/// Everything the assistant screens need from outside themselves.
///
/// An interface so the screens pump in a widget test against a hand-written
/// fake: the real one (`LiveAssistantBackend`) holds the analysis service,
/// the conversation store, the uploader and the picker, none of which can run
/// under `flutter_tester`. The rules those depend on — gates, persistence,
/// what is sent — are tested against the live one directly.
abstract class AssistantBackend {
  /// A key is compiled in and Firebase is up. False shows a neutral
  /// unavailable state instead of a chat that could only fail.
  bool get available;

  /// The account has not agreed to the current consent disclosure.
  bool get needsConsent;

  /// Messages today's cap still allows.
  int get messagesLeft;

  /// Whether the camera and the system picker can be offered at all.
  bool get canCapture;

  /// A fresh conversation id, held by a new chat from the moment it opens.
  String newConversationId();

  /// Shows the consent sheet and records the answer. True = may proceed.
  Future<bool> requestConsent(BuildContext context);

  /// The rewarded-ad gate for a new conversation. True = may proceed.
  Future<bool> earnConversation(BuildContext context);

  /// This account's conversations, most recently active first.
  Future<List<AssistantConversation>> conversations();

  /// The conversation that started from [mediaId], if there is one.
  Future<String?> conversationForMedia(String mediaId);

  /// Loads a saved conversation for display, and seeds the model's history
  /// with it so the next message carries its context.
  Future<List<ChatEntry>> open(String conversationId);

  /// Deletes a conversation everywhere it is synced.
  Future<void> delete(String conversationId);

  /// Sends [text] with [attachments] as the next message of
  /// [conversationId]. [originMediaId] is the photo a Describe chat started
  /// from, `''` otherwise; it only matters on the message that creates the
  /// conversation.
  Future<AssistantReply> send({
    required String conversationId,
    String originMediaId = '',
    required String text,
    List<MediaItem> attachments = const [],
  });

  /// Takes a photo or video, or picks from the system picker, and uploads it
  /// to Photos & videos. At most [limit] items.
  Future<AttachOutcome> capture(MediaSource source, {required int limit});

  /// What is already in Photos & videos, newest first.
  Future<List<MediaItem>> library();

  /// Forgets [conversationId]'s in-memory history. Called when its chat
  /// closes, so reopening it resumes from storage.
  void endConversation(String conversationId);
}

/// The words a message is sent and saved with.
///
/// A message with only photos asks the default question, which is what the
/// model is sent and so what the transcript shows. A message with a video is
/// never sent, so it keeps exactly what was typed — possibly nothing.
String sentTextFor(String typed, {required bool hasVideo}) =>
    hasVideo ? typed.trim() : normalizeQuestion(typed);
