import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/services/media_analysis_service.dart';
import 'package:menstrul_track/services/media_analyzer.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// A stand-in for the network. File-private and hand-written — this repo has no
/// mockito or mocktail in dev_dependencies, and the seam exists precisely so a
/// fake like this is all a test needs.
class _FakeAnalyzer implements MediaAnalyzer {
  _FakeAnalyzer({this.answer = 'a description', this.throws});

  final String answer;

  /// Mutable so one test can fail a single turn mid-conversation and then
  /// recover, which is the case that proves a failure leaves no dangling turn.
  Object? throws;
  int calls = 0;
  String? lastQuestion;

  /// The conversation the service handed over on the most recent call. This is
  /// the whole point of the fake for multi-turn: the transcript is private
  /// state, and this is where it becomes observable.
  List<AnalysisTurn> lastHistory = const [];

  @override
  Future<AnalysisResult> analyze({
    required Uint8List bytes,
    required String mimeType,
    required String question,
    List<AnalysisTurn> history = const [],
  }) async {
    calls++;
    lastQuestion = question;
    lastHistory = history;
    if (throws != null) throw throws!;
    return AnalysisResult(prose: answer);
  }
}

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late SyncTrigger trigger;
  late _FakeAnalyzer analyzer;
  ClaimRecord? claim;

  const uid = 'uid-1';

  // Mutable consent + usage, standing in for the AppSettings columns.
  String? consentUid;
  String? usageDay;
  int? usageCount;

  Future<SyncTrigger> buildTrigger(String? signedIn) async {
    final t = SyncTrigger(
      db,
      firestore: () => firestore,
      deviceId: () async => 'device-1',
      readClaim: () async => claim,
      writeClaim: (r) async => claim = r,
    );
    await t.setUser(signedIn);
    return t;
  }

  MediaAnalysisService buildService({DateTime? now}) => MediaAnalysisService(
        analyzer: analyzer,
        trigger: trigger,
        consentUid: () => consentUid,
        readUsage: () => (day: usageDay, count: usageCount),
        writeUsage: (d, c) async {
          usageDay = d;
          usageCount = c;
        },
        now: () => now ?? DateTime(2026, 8, 12, 10),
        available: true,
      );

  Future<AnalysisOutcome> run(
    MediaAnalysisService service, {
    String id = 'media-1',
    bool isImage = true,
    int bytes = 1024,
    String? question,
  }) =>
      service.analyze(
        mediaId: id,
        bytes: Uint8List(bytes),
        mimeType: 'image/jpeg',
        isImage: isImage,
        question: question,
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    analyzer = _FakeAnalyzer();
    claim = const ClaimRecord(uid: uid, declined: false);
    consentUid = uid;
    usageDay = null;
    usageCount = null;
    trigger = await buildTrigger(uid);
  });

  tearDown(() async => db.close());

  group('gates, narrow to broad', () {
    test('signed out', () async {
      trigger = await buildTrigger(null);
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notSignedIn);
      expect(analyzer.calls, 0);
    });

    test('a declined uid on record reports syncDeclined, not writesBlocked',
        () async {
      claim = const ClaimRecord(uid: uid, declined: true);
      trigger = await buildTrigger(uid);
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.syncDeclined);
      expect(analyzer.calls, 0);
    });

    test('no consent on record', () async {
      consentUid = null;
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(analyzer.calls, 0);
    });

    test("another account's consent is not this account's consent", () async {
      // The reason the column stores a uid rather than a bool. A device-global
      // flag would let account B's photos be described on account A's consent.
      consentUid = 'someone-else';
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(analyzer.calls, 0);
    });

    test('videos are never sent', () async {
      final outcome = await run(buildService(), isImage: false);
      expect(outcome.blocked, AnalysisBlock.notAnImage);
      expect(analyzer.calls, 0);
    });

    test('an oversized image is refused before the network', () async {
      final outcome = await run(buildService(), bytes: kMaxAnalysisBytes + 1);
      expect(outcome.blocked, AnalysisBlock.tooLarge);
      expect(analyzer.calls, 0);
    });

    test('no key compiled in', () async {
      final service = MediaAnalysisService(
        analyzer: analyzer,
        trigger: trigger,
        consentUid: () => consentUid,
        readUsage: () => (day: usageDay, count: usageCount),
        writeUsage: (d, c) async {},
        available: false,
      );
      final outcome = await run(service);
      expect(outcome.blocked, AnalysisBlock.unavailable);
      expect(analyzer.calls, 0);
    });

    test('a fully gated-through request reaches the analyzer', () async {
      // The positive case. Without it, every test above would pass against a
      // service that refuses everything.
      final outcome = await run(buildService());
      expect(outcome.blocked, isNull);
      expect(outcome.result?.prose, 'a description');
      expect(analyzer.calls, 1);
    });

    test("the model's answer reaches the caller unaltered", () async {
      // The service must not summarise, trim or reword what came back. Anything
      // it added would be LunaTrack authoring a reading of a body photo.
      analyzer = _FakeAnalyzer(answer: 'Two green trees on a rocky shoreline.');
      final outcome = await run(buildService());
      expect(outcome.result?.prose, 'Two green trees on a rocky shoreline.');
    });
  });

  group('daily cap', () {
    test('blocks at the ceiling', () async {
      usageDay = '2026-08-12';
      usageCount = kMaxAnalysesPerDay;
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.dailyCap);
      expect(analyzer.calls, 0);
    });

    test('yesterday\'s count does not carry over', () async {
      usageDay = '2026-08-11';
      usageCount = kMaxAnalysesPerDay;
      final outcome = await run(buildService());
      expect(outcome.blocked, isNull);
      expect(usageDay, '2026-08-12');
      expect(usageCount, 1);
    });

    test('counts BEFORE the call, so a failure still bills', () async {
      // The cap bounds spend, not successes: a crash mid-request would
      // otherwise leave a billed call uncounted.
      analyzer = _FakeAnalyzer(throws: const AnalysisException('boom'));
      final outcome = await run(buildService());
      expect(outcome.error, 'boom');
      expect(usageCount, 1);
    });

    test('remainingToday reflects the stored count', () async {
      usageDay = '2026-08-12';
      usageCount = 3;
      expect(buildService().remainingToday, kMaxAnalysesPerDay - 3);
    });
  });

  group('memo', () {
    test('re-opening the same photo is not re-billed', () async {
      final service = buildService();
      await run(service);
      service.endConversation('media-1'); // the sheet closed
      await run(service);
      expect(analyzer.calls, 1);
      // Served before the cap is consulted, so a repeat view costs nothing.
      expect(usageCount, 1);
    });

    test('a memo hit still seeds the conversation', () async {
      // Otherwise re-opening a photo and asking "and the other one?" would send
      // that phrase with nothing for it to refer to.
      final service = buildService();
      await run(service);
      service.endConversation('media-1');
      await run(service);
      expect(service.turnsUsed('media-1'), 1);
    });

    test('mid-conversation the memo is not consulted', () async {
      // The same words at turn four mean something different than at turn one,
      // so replaying the earlier answer would look like the model ignoring the
      // conversation.
      final service = buildService();
      await run(service, question: 'and the other one');
      await run(service, question: 'something else');
      await run(service, question: 'and the other one');
      expect(analyzer.calls, 3);
    });

    test('a different question is a different request', () async {
      final service = buildService();
      await run(service, question: 'what colour is it');
      await run(service, question: 'how many are there');
      expect(analyzer.calls, 2);
      expect(analyzer.lastQuestion, 'how many are there');
    });

    test('a blank question becomes the default', () async {
      await run(buildService(), question: '   ');
      expect(analyzer.lastQuestion, kDefaultAnalysisQuestion);
    });
  });

  group('conversation', () {
    test('the opening question is sent with no history', () async {
      await run(buildService());
      expect(analyzer.lastHistory, isEmpty);
    });

    test('a follow-up carries the exchange before it', () async {
      final service = buildService();
      await run(service, question: 'what colour is it');
      await run(service, question: 'how many are there');

      // Without this the second question is a cold start and "there" has no
      // referent — which is what the single-shot version actually did.
      expect(analyzer.lastHistory.length, 2);
      expect(analyzer.lastHistory[0].role, AnalysisRole.user);
      expect(analyzer.lastHistory[0].text, 'what colour is it');
      expect(analyzer.lastHistory[1].role, AnalysisRole.model);
      expect(analyzer.lastHistory[1].text, 'a description');
    });

    test('the transcript grows by one exchange per turn', () async {
      final service = buildService();
      await run(service, question: 'one');
      await run(service, question: 'two');
      await run(service, question: 'three');
      expect(analyzer.lastHistory.length, 4);
      expect(service.turnsUsed('media-1'), 3);
    });

    test('each photo has its own conversation', () async {
      final service = buildService();
      await run(service, id: 'media-1', question: 'about the first');
      await run(service, id: 'media-2', question: 'about the second');
      expect(analyzer.lastHistory, isEmpty);
      expect(service.turnsUsed('media-2'), 1);
    });

    test('a failed turn does not enter the transcript', () async {
      // Appending a user turn with no model reply would break the alternation
      // the API expects, and the next question would be sent against a
      // conversation that never happened.
      final service = buildService();
      await run(service, question: 'first');
      analyzer.throws = const AnalysisException('boom');
      await run(service, question: 'second');
      analyzer.throws = null;
      await run(service, question: 'third');

      expect(analyzer.lastHistory.length, 2);
      expect(analyzer.lastHistory[0].text, 'first');
    });

    test('blocks at the turn cap', () async {
      final service = buildService();
      for (var i = 0; i < kMaxChatTurns; i++) {
        await run(service, question: 'question $i');
      }
      final outcome = await run(service, question: 'one too many');
      expect(outcome.blocked, AnalysisBlock.turnCap);
      expect(analyzer.calls, kMaxChatTurns);
    });

    test('endConversation forgets it, so re-opening starts over', () async {
      final service = buildService();
      await run(service, question: 'what colour is it');
      service.endConversation('media-1');
      expect(service.turnsUsed('media-1'), 0);
      await run(service, question: 'how many are there');
      expect(analyzer.lastHistory, isEmpty);
    });
  });

  group('failures', () {
    test('an AnalysisException surfaces its own copy', () async {
      analyzer = _FakeAnalyzer(throws: const AnalysisException('no answer'));
      final outcome = await run(buildService());
      expect(outcome.error, 'no answer');
      expect(outcome.result, isNull);
    });

    test('an unexpected throw never leaks the object', () async {
      // A raw error can carry the request, and the request carries the image.
      analyzer = _FakeAnalyzer(throws: StateError('contains/the/photo/path'));
      final outcome = await run(buildService());
      expect(outcome.error, 'Something went wrong. Try again.');
      expect(outcome.error, isNot(contains('photo/path')));
    });
  });

  group('consented', () {
    test('true only for the signed-in uid', () async {
      expect(buildService().consented, isTrue);
      consentUid = 'other';
      expect(buildService().consented, isFalse);
      consentUid = null;
      expect(buildService().consented, isFalse);
    });

    test('false when signed out', () async {
      trigger = await buildTrigger(null);
      expect(buildService().consented, isFalse);
    });
  });
}
