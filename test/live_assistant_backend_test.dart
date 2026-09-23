import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/analysis_session_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/screens/assistant/analysis_chat_view.dart';
import 'package:menstrul_track/screens/assistant/assistant_backend.dart';
import 'package:menstrul_track/screens/assistant/live_assistant_backend.dart';
import 'package:menstrul_track/services/assistant_image_prep.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/services/media_analysis_service.dart';
import 'package:menstrul_track/services/media_analyzer.dart';
import 'package:menstrul_track/services/media_limits.dart';
import 'package:menstrul_track/services/media_picker_config.dart';
import 'package:menstrul_track/services/media_upload_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// Hand-written, like the service test's: records what the model was sent.
class _FakeAnalyzer implements MediaAnalyzer {
  int calls = 0;
  String answer = 'an answer';
  List<AnalysisTurn> lastHistory = const [];
  AnalysisTurn? lastNext;
  Map<String, InlineImage> lastImages = const {};
  String? lastHealthContext;

  /// Holds the reply in flight until completed.
  Completer<void>? gate;

  @override
  Future<AnalysisResult> analyze({
    List<AnalysisTurn> history = const [],
    required AnalysisTurn next,
    Map<String, InlineImage> images = const {},
    String? healthContext,
  }) async {
    calls++;
    lastHistory = history;
    lastNext = next;
    lastImages = images;
    lastHealthContext = healthContext;
    await gate?.future;
    return AnalysisResult(prose: answer);
  }
}

/// The conversation store, persistence and gating around the real service.
/// Real drift (in memory) and a real [MediaAnalysisService]; only the network
/// and the platform plugins are stood in for.
void main() {
  const uid = 'uid-1';
  late AppDatabase db;
  late AnalysisSessionRepository sessions;
  late SyncTrigger trigger;
  late _FakeAnalyzer analyzer;
  late Map<String, MediaItem> media;
  late List<String> originalLoads;
  late Set<String> failingLoads;
  late bool syncOn;
  String? consentUid;
  int? usageCount;
  String? usageDay;
  ClaimRecord? claim;
  MediaUploadOutcome Function()? upload;
  int? uploadLimit;

  MediaItem item(String id, {String kind = 'image'}) => MediaItem(
        id: id,
        uid: uid,
        kind: kind,
        storagePath: 'users/$uid/media/$id/original.${kind == 'image' ? 'jpg' : 'mp4'}',
        bytes: 10,
        capturedAt: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );

  LiveAssistantBackend build() => LiveAssistantBackend(
        available: true,
        service: (persistTurn) => MediaAnalysisService(
          analyzer: analyzer,
          trigger: trigger,
          consentUid: () => consentUid,
          consentVersion: () => kCurrentConsentVersion,
          readUsage: () => (day: usageDay, count: usageCount),
          writeUsage: (d, c) async {
            usageDay = d;
            usageCount = c;
          },
          persistTurn: persistTurn,
          available: true,
        ),
        sessions: sessions,
        currentUid: () => trigger.currentUid,
        loadMedia: (id) async => media[id],
        libraryFor: (uid) async => media.values.toList(),
        loadOriginal: (item) async {
          originalLoads.add(item.id);
          if (failingLoads.remove(item.id)) throw StateError('offline');
          return (Uint8List(64), 'image/jpeg');
        },
        healthContext: () => 'TRACKED',
        syncOn: (_) async => syncOn,
        pickAndUpload: upload == null
            ? null
            : (source, {limit}) async {
                uploadLimit = limit;
                return upload!();
              },
        prep: AssistantImagePrep(
          encoder: (s, {required maxEdge, required quality}) async =>
              Uint8List(8),
        ),
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessions = AnalysisSessionRepository(db);
    analyzer = _FakeAnalyzer();
    media = {'p1': item('p1'), 'p2': item('p2'), 'v1': item('v1', kind: 'video')};
    originalLoads = [];
    failingLoads = {};
    syncOn = true;
    consentUid = uid;
    usageCount = null;
    usageDay = null;
    upload = null;
    uploadLimit = null;
    claim = const ClaimRecord(uid: uid, declined: false);
    trigger = SyncTrigger(
      db,
      firestore: () => FakeFirebaseFirestore(),
      deviceId: () async => 'device-1',
      readClaim: () async => claim,
      writeClaim: (r) async => claim = r,
    );
    await trigger.setUser(uid);
  });

  tearDown(() => db.close());

  group('send', () {
    test('a first answer creates the conversation under the chat\'s own id',
        () async {
      final backend = build();
      final reply = await backend.send(
        conversationId: 'chat-1',
        text: '  when is my next period?  ',
      );

      expect(reply.kind, AssistantReplyKind.answer);
      expect(reply.text, 'an answer');
      final session = await sessions.byId('chat-1');
      expect(session!.uid, uid);
      expect(session.mediaId, '');
      expect(session.title, 'when is my next period?');
      final messages = await sessions.messagesFor('chat-1');
      expect(messages.map((m) => m.role), ['user', 'model']);
    });

    test('a text-only message still carries the tracked record', () async {
      await build().send(conversationId: 'chat-1', text: 'hi');
      expect(analyzer.lastHealthContext, 'TRACKED');
    });

    test('a Describe chat names its photo and has no title', () async {
      final backend = build();
      await backend.send(
        conversationId: 'chat-1',
        originMediaId: 'p1',
        text: '',
        attachments: [media['p1']!],
      );

      final session = await sessions.byId('chat-1');
      expect(session!.mediaId, 'p1');
      expect(session.title, isNull);
      expect(analyzer.lastNext!.text, kDefaultAnalysisQuestion);
      expect(await backend.conversationForMedia('p1'), 'chat-1');
    });

    test('photos are prepared before they are sent', () async {
      await build().send(
        conversationId: 'chat-1',
        text: 'look',
        attachments: [media['p1']!],
      );
      expect(analyzer.lastImages['p1']!.mimeType, 'image/jpeg');
      expect(analyzer.lastImages['p1']!.base64, isNotEmpty);
      final stored = await sessions.messagesFor('chat-1');
      expect(decodeAttachments(stored.first.attachmentsJson),
          [const AttachmentRef.image('p1')]);
    });

    test('a video is declined: nothing sent or counted, the pair is saved '
        'out of the model\'s sight', () async {
      final backend = build();
      final reply = await backend.send(
        conversationId: 'chat-1',
        text: 'what is this?',
        attachments: [media['v1']!, media['p1']!],
      );

      expect(reply.kind, AssistantReplyKind.declined);
      expect(reply.text, kVideoDeclinedNotice);
      expect(analyzer.calls, 0);
      expect(usageCount, isNull);
      expect(originalLoads, isEmpty,
          reason: 'a declined message never reads a byte of its photos');
      final messages = await sessions.messagesFor('chat-1');
      expect(messages.map((m) => m.includeInModel), [false, false]);
      expect(messages.first.messageText, 'what is this?');
      expect(decodeAttachments(messages.first.attachmentsJson), [
        const AttachmentRef.video('v1'),
        const AttachmentRef.image('p1'),
      ]);
      expect(messages.last.messageText, kVideoDeclinedNotice);
    });

    test('an unconsented video gets the consent block, and nothing is saved',
        () async {
      consentUid = null;
      final reply = await build().send(
        conversationId: 'chat-1',
        text: '',
        attachments: [media['v1']!],
      );
      expect(reply.kind, AssistantReplyKind.failed);
      expect(reply.text, messageForAnalysisBlock(AnalysisBlock.notConsented));
      expect(await sessions.byId('chat-1'), isNull);
    });

    test('a refusal is shown but never saved', () async {
      usageDay = analysisDayKey(DateTime.now());
      usageCount = kMaxAnalysesPerDay;
      final reply = await build().send(conversationId: 'chat-1', text: 'hi');

      expect(reply.kind, AssistantReplyKind.failed);
      expect(reply.text, messageForAnalysisBlock(AnalysisBlock.dailyCap));
      expect(await sessions.byId('chat-1'), isNull);
    });

    test('a conversation deleted while open is not brought back', () async {
      final backend = build();
      await backend.send(conversationId: 'chat-1', text: 'hi');
      await sessions.tombstone('chat-1');

      await backend.send(conversationId: 'chat-1', text: 'still there?');

      expect((await sessions.byId('chat-1'))!.deletedAt, isNotNull);
      expect(await sessions.messagesFor('chat-1'), isEmpty);
    });
    test('closing the chat mid-send still files the conversation under its '
        'photo, and keeps nothing in memory', () async {
      final backend = build();
      analyzer.gate = Completer();
      final sending = backend.send(
        conversationId: 'chat-1',
        originMediaId: 'p1',
        text: '',
        attachments: [media['p1']!],
      );
      // Let the send reach the model, then close the chat under it.
      await pumpEventQueue();
      expect(analyzer.calls, 1);
      backend.endConversation('chat-1');
      analyzer.gate!.complete();
      await sending;

      final session = await sessions.byId('chat-1');
      expect(session!.mediaId, 'p1');
      expect(session.title, isNull);
      expect(await backend.conversationForMedia('p1'), 'chat-1');
      expect(backend.service.turnsUsed('chat-1'), 0,
          reason: 'an ended conversation must not be rewritten into memory');

      // Nothing of the old conversation, photos included, rides along now.
      analyzer.gate = null;
      await backend.send(conversationId: 'chat-1', text: 'and?');
      expect(analyzer.lastHistory, isEmpty);
      expect(analyzer.lastImages, isEmpty);
    });

    test('a typed opener closed mid-send keeps its title', () async {
      final backend = build();
      analyzer.gate = Completer();
      final sending =
          backend.send(conversationId: 'chat-1', text: 'is this normal?');
      await pumpEventQueue();
      backend.endConversation('chat-1');
      analyzer.gate!.complete();
      await sending;

      expect((await sessions.byId('chat-1'))!.title, 'is this normal?');
    });

  });

  group('open', () {
    test('shows the saved turns, a removed photo and the declined notice',
        () async {
      final s = await sessions.create(
          uid: uid, consentVersion: kCurrentConsentVersion, id: 'chat-1');
      await sessions.append(
          sessionId: s.id,
          role: 'user',
          text: 'look',
          attachments: const [AttachmentRef.image('p1'), AttachmentRef.image('gone')]);
      await sessions.append(sessionId: s.id, role: 'model', text: 'I see.');
      await sessions.append(
          sessionId: s.id,
          role: 'user',
          text: '',
          attachments: const [AttachmentRef.video('v1')],
          includeInModel: false);
      await sessions.append(
          sessionId: s.id,
          role: 'model',
          text: kVideoDeclinedNotice,
          includeInModel: false);

      final entries = await build().open('chat-1');

      expect(entries.map((e) => e.kind), [
        ChatEntryKind.user,
        ChatEntryKind.reply,
        ChatEntryKind.user,
        ChatEntryKind.notice,
      ]);
      expect(entries.first.attachments.map((a) => a.removed), [false, true]);
      expect(entries[2].attachments.single.kind, AttachmentKind.video);
    });

    test('seeds the model\'s history and resends earlier photos', () async {
      final s = await sessions.create(
          uid: uid, consentVersion: kCurrentConsentVersion, id: 'chat-1');
      await sessions.append(
          sessionId: s.id,
          role: 'user',
          text: 'look',
          attachments: const [AttachmentRef.image('p1')]);
      await sessions.append(sessionId: s.id, role: 'model', text: 'I see.');

      final backend = build();
      await backend.open('chat-1');
      expect(originalLoads, isEmpty,
          reason: 'reading a transcript downloads nothing');

      await backend.send(conversationId: 'chat-1', text: 'and now?');

      expect(analyzer.lastHistory.map((t) => t.text), ['look', 'I see.']);
      expect(analyzer.lastImages.keys, ['p1']);
      expect(await sessions.messagesFor('chat-1'), hasLength(4));
    });

    test('a photo that fails to load is retried on the next send, and the '
        'ones that loaded are kept', () async {
      final s = await sessions.create(
          uid: uid, consentVersion: kCurrentConsentVersion, id: 'chat-1');
      await sessions.append(
          sessionId: s.id,
          role: 'user',
          text: 'look',
          attachments: const [
            AttachmentRef.image('p1'),
            AttachmentRef.image('p2'),
          ]);
      await sessions.append(sessionId: s.id, role: 'model', text: 'I see.');

      final backend = build();
      await backend.open('chat-1');
      failingLoads = {'p2'};

      final first = await backend.send(conversationId: 'chat-1', text: 'a');
      expect(first.kind, AssistantReplyKind.failed);
      expect(analyzer.calls, 0);

      final second = await backend.send(conversationId: 'chat-1', text: 'b');
      expect(second.kind, AssistantReplyKind.answer);
      expect(analyzer.lastImages.keys, unorderedEquals(['p1', 'p2']),
          reason: 'a photo that still exists is never sent as removed');
    });

    test('a v15 Describe session gets its photo on the first turn', () async {
      final s = await sessions.create(
          uid: uid,
          mediaId: 'p1',
          consentVersion: 6,
          id: 'chat-1');
      await sessions.append(sessionId: s.id, role: 'user', text: 'q');
      await sessions.append(sessionId: s.id, role: 'model', text: 'a');

      final entries = await build().open('chat-1');
      expect(entries.first.attachments.single.mediaId, 'p1');
    });
  });

  group('conversations', () {
    test('lists title, first answer and first attachment; skips deleted',
        () async {
      final backend = build();
      await backend.send(
          conversationId: 'a', text: 'about this', attachments: [media['p1']!]);
      analyzer.answer = 'second';
      await backend.send(conversationId: 'b', text: 'text only');
      await backend.send(conversationId: 'c', text: 'doomed');
      await backend.delete('c');

      final list = await backend.conversations();

      expect(list.map((c) => c.id), unorderedEquals(['a', 'b']));
      final a = list.firstWhere((c) => c.id == 'a');
      expect(a.title, 'about this');
      expect(a.subtitle, 'an answer');
      expect(a.firstAttachment, const AttachmentRef.image('p1'));
      expect(a.cover?.id, 'p1');
      final b = list.firstWhere((c) => c.id == 'b');
      expect(b.firstAttachment, isNull);
      expect(b.cover, isNull);
    });

    test('the first answer skips the declined notice', () async {
      final backend = build();
      await backend.send(
          conversationId: 'a', text: '', attachments: [media['v1']!]);
      await backend.send(conversationId: 'a', text: 'ok then');
      final a = (await backend.conversations()).single;
      expect(a.subtitle, 'an answer');
    });

    test('saving and deleting tell listeners the list changed', () async {
      final backend = build();
      var changes = 0;
      backend.changes.addListener(() => changes++);

      await backend.send(conversationId: 'a', text: 'hi');
      expect(changes, 1);
      await backend.send(
          conversationId: 'b', text: '', attachments: [media['v1']!]);
      expect(changes, 2);
      await backend.delete('a');
      expect(changes, 3);

      usageDay = analysisDayKey(DateTime.now());
      usageCount = kMaxAnalysesPerDay;
      await backend.send(conversationId: 'c', text: 'refused');
      expect(changes, 3, reason: 'nothing was saved');
    });

    test('delete tombstones the conversation', () async {
      final backend = build();
      await backend.send(conversationId: 'a', text: 'hi');
      await backend.delete('a');
      expect((await sessions.byId('a'))!.deletedAt, isNotNull);
      expect(await backend.conversations(), isEmpty);
    });

    test('signed out lists nothing, and reads as unavailable', () async {
      final backend = build();
      expect(backend.available, isTrue);
      await trigger.setUser(null);
      expect(await backend.conversations(), isEmpty);
      expect(backend.available, isFalse);
    });
  });

  group('capture', () {
    test('with sync off, says so and never opens the picker', () async {
      var picks = 0;
      upload = () {
        picks++;
        return const MediaUploadOutcome();
      };
      syncOn = false;

      final out = await build().capture(MediaSource.camera, limit: 3);

      expect(out.message, messageForAnalysisBlock(AnalysisBlock.syncOff));
      expect(picks, 0);
    });

    test('returns the uploaded items and counts what failed', () async {
      upload = () => const MediaUploadOutcome(
            uploadedIds: ['p2'],
            failed: 1,
            rejected: [MediaRejection(MediaRefusal.tooLarge)],
          );

      final out = await build().capture(MediaSource.library, limit: 4);

      expect(out.items.map((i) => i.id), ['p2']);
      expect(out.failed, 2);
      expect(uploadLimit, 4);
    });

    test('a cancelled pick is neither a failure nor a message', () async {
      upload = () => const MediaUploadOutcome();
      expect((await build().capture(MediaSource.camera, limit: 1)).cancelled,
          isTrue);
    });

    test('is not offered when there is no picker', () {
      expect(build().canCapture, isFalse);
      upload = () => const MediaUploadOutcome();
      expect(build().canCapture, isTrue);
    });
  });
}
