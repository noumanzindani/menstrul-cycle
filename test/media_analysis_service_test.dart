import 'dart:io';
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

  /// The turn being asked, exactly as the service built it.
  AnalysisTurn? lastNext;

  String? get lastQuestion => lastNext?.text;

  /// The conversation the service handed over on the most recent call. This is
  /// the whole point of the fake for multi-turn: the transcript is private
  /// state, and this is where it becomes observable.
  List<AnalysisTurn> lastHistory = const [];

  /// Every prepared image the request could inline, by media id.
  Map<String, InlineImage> lastImages = const {};

  /// The health context the service handed over on the most recent call —
  /// observable proof the service forwards it verbatim rather than parsing,
  /// logging or dropping it.
  String? lastHealthContext;

  @override
  Future<AnalysisResult> analyze({
    List<AnalysisTurn> history = const [],
    required AnalysisTurn next,
    Map<String, InlineImage> images = const {},
    String? healthContext,
  }) async {
    calls++;
    lastNext = next;
    lastHistory = history;
    lastImages = images;
    lastHealthContext = healthContext;
    if (throws != null) throw throws!;
    return AnalysisResult(prose: answer);
  }
}

/// Stands in for the `persistAnalysisTurn` wiring built in `media_route.dart`
/// against `AnalysisSessionRepository`: resolves an existing session for a
/// mediaId (or creates one) and appends turns to it as PURE inserts — this
/// deliberately mirrors `AnalysisSessionRepository.append`, which has no
/// dedup of its own, so a caller-side mistake that re-persists an
/// already-saved exchange shows up here as an observable duplicate rather
/// than being silently absorbed. Lets tests observe persistence — including
/// session resumption and the memo-hit skip — without a database.
class _FakeSessionStore {
  final Map<String, String> sessionIdByConversation = {};
  int createCount = 0;
  final List<
      ({
        String sessionId,
        String role,
        String text,
        List<AttachmentRef> attachments,
      })> messages = [];

  Future<void> persistTurn({
    required String conversationId,
    required String question,
    required List<AttachmentRef> attachments,
    required String answer,
    required bool isMemoHit,
  }) async {
    final existingId = sessionIdByConversation[conversationId];
    // Mirrors persistAnalysisTurn's own early return: a memo hit re-serves an
    // exchange already shown once before, and when a session already exists
    // it already holds that opening exchange — appending it again would be a
    // duplicate. See the doc comment on that function in media_route.dart.
    if (isMemoHit && existingId != null) return;
    final sessionId = existingId ?? _createSession(conversationId);
    messages.add((
      sessionId: sessionId,
      role: 'user',
      text: question,
      attachments: attachments,
    ));
    messages.add((
      sessionId: sessionId,
      role: 'model',
      text: answer,
      attachments: const <AttachmentRef>[],
    ));
  }

  String _createSession(String conversationId) {
    createCount++;
    final id = 'session-$createCount';
    sessionIdByConversation[conversationId] = id;
    return id;
  }
}

AnalysisAttachment _photo(String id, {int bytes = 1024, String? mime}) =>
    AnalysisAttachment.image(
      mediaId: id,
      mimeType: mime ?? 'image/jpeg',
      bytes: Uint8List(bytes),
    );

void main() {
  late AppDatabase db;
  late FakeFirebaseFirestore firestore;
  late SyncTrigger trigger;
  late _FakeAnalyzer analyzer;
  late _FakeSessionStore sessionStore;
  ClaimRecord? claim;

  const uid = 'uid-1';

  // Mutable consent + usage, standing in for the AppSettings columns.
  String? consentUid;
  int? consentVersion;
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

  // Mutable so a test can roll the clock over midnight mid-service.
  DateTime clock = DateTime(2026, 8, 12, 10);

  MediaAnalysisService buildService({DateTime? now}) {
    if (now != null) clock = now;
    return MediaAnalysisService(
      analyzer: analyzer,
      trigger: trigger,
      consentUid: () => consentUid,
      consentVersion: () => consentVersion,
      readUsage: () => (day: usageDay, count: usageCount),
      writeUsage: (d, c) async {
        usageDay = d;
        usageCount = c;
      },
      persistTurn: sessionStore.persistTurn,
      now: () => clock,
      available: true,
    );
  }

  /// One send, Describe-shaped by default: [id] is both the conversation and
  /// its photo, and the photo rides the opening turn only — which is what
  /// `media_route.dart` does. Pass [attachments] to send something else.
  Future<AnalysisOutcome> run(
    MediaAnalysisService service, {
    String id = 'media-1',
    int bytes = 1024,
    List<AnalysisAttachment>? attachments,
    String? question,
    String? healthContext,
  }) =>
      service.analyze(
        conversationId: id,
        attachments: attachments ??
            (service.turnsUsed(id) == 0 ? [_photo(id, bytes: bytes)] : const []),
        question: question,
        healthContext: healthContext,
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    firestore = FakeFirebaseFirestore();
    analyzer = _FakeAnalyzer();
    sessionStore = _FakeSessionStore();
    claim = const ClaimRecord(uid: uid, declined: false);
    consentUid = uid;
    consentVersion = kCurrentConsentVersion;
    usageDay = null;
    usageCount = null;
    clock = DateTime(2026, 8, 12, 10);
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

    test('a v1 consenter is not consented — the request now carries the '
        'whole health record, not just a photo', () async {
      consentVersion = 1;
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(analyzer.calls, 0);
    });

    test('a v3 consenter is asked again — v4 adds the signup sexual-health '
        'answers and the goal', () async {
      consentVersion = 3;
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(analyzer.calls, 0);
    });

    test('a v4 consenter is asked again — v5 adds a recent pregnancy, birth '
        'or pregnancy loss', () async {
      consentVersion = 4;
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(analyzer.calls, 0);
    });

    test('a null version (never consented) reports notConsented', () async {
      consentVersion = null;
      final outcome = await run(buildService());
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(analyzer.calls, 0);
    });

    test('an attachment the model cannot read is notAnImage', () async {
      final outcome = await run(
        buildService(),
        attachments: [_photo('m1', mime: 'application/octet-stream')],
      );
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
        consentVersion: () => consentVersion,
        readUsage: () => (day: usageDay, count: usageCount),
        writeUsage: (d, c) async {},
        persistTurn: sessionStore.persistTurn,
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
      // it added would be LunarFlow authoring a reading of a body photo.
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

  group('resuming a saved conversation', () {
    // A resumed session is read from storage into a FRESH service instance —
    // one is built once per timeline route, so `_transcripts` starts empty
    // regardless of what a previous route instance ever held. Without
    // `seedConversation`, a follow-up asked after resuming would be sent with
    // `history: []`, and the model would answer as though the conversation
    // the user can see on screen never happened.
    test('a follow-up after resuming carries the full prior history',
        () async {
      final service = buildService();
      service.seedConversation('media-1', const [
        AnalysisTurn.user('what colour is it'),
        AnalysisTurn.model('It is pink.'),
        AnalysisTurn.user('how many are there'),
        AnalysisTurn.model('Three.'),
      ]);

      await run(service, question: 'and the shape?');

      expect(analyzer.lastHistory.length, 4);
      expect(analyzer.lastHistory[0].role, AnalysisRole.user);
      expect(analyzer.lastHistory[0].text, 'what colour is it');
      expect(analyzer.lastHistory[1].text, 'It is pink.');
      expect(analyzer.lastHistory[2].text, 'how many are there');
      expect(analyzer.lastHistory[3].text, 'Three.');
      expect(analyzer.lastQuestion, 'and the shape?');
    });

    test('seeded turns count toward the turn cap', () async {
      // A conversation resumed already nine turns deep IS nine turns deep —
      // undercounting it would hand out more billed turns than the cap
      // intends, which is exactly what an unseeded `_transcripts` map did.
      final service = buildService();
      final seeded = <AnalysisTurn>[];
      for (var i = 0; i < kMaxChatTurns; i++) {
        seeded.add(AnalysisTurn.user('question $i'));
        seeded.add(AnalysisTurn.model('answer $i'));
      }
      service.seedConversation('media-1', seeded);

      expect(service.turnsUsed('media-1'), kMaxChatTurns);

      final outcome = await run(service, question: 'one too many');
      expect(outcome.blocked, AnalysisBlock.turnCap);
      // Blocked before any network call — the cap check happens before the
      // analyzer is ever reached.
      expect(analyzer.calls, 0);
    });

    test('seeding with no turns is a no-op', () async {
      final service = buildService();
      service.seedConversation('media-1', const []);
      await run(service);
      expect(analyzer.lastHistory, isEmpty);
    });

    test('does not overwrite an already-live conversation', () async {
      final service = buildService();
      await run(service, question: 'first');
      service.seedConversation('media-1', const [
        AnalysisTurn.user('stale question'),
        AnalysisTurn.model('stale answer'),
      ]);
      await run(service, question: 'second');
      expect(analyzer.lastHistory.length, 2);
      expect(analyzer.lastHistory[0].text, 'first');
      expect(analyzer.lastHistory[1].text, 'a description');
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

    test('a v1 consenter is treated as not consented', () {
      consentVersion = 1;
      expect(buildService().consented, isFalse);
    });

    test('a current-version consenter is consented', () {
      consentVersion = kCurrentConsentVersion;
      expect(buildService().consented, isTrue);
    });

    test('a null version (never consented) is not consented', () {
      consentVersion = null;
      expect(buildService().consented, isFalse);
    });

    test(
        "a stored uid belonging to a different account is not consented "
        'regardless of version', () {
      consentUid = 'someone-else';
      consentVersion = kCurrentConsentVersion;
      expect(buildService().consented, isFalse);
    });
  });

  group('health context', () {
    test('forwards the context verbatim to the analyzer', () async {
      final service = buildService();
      await run(
        service,
        healthContext: '<<<TRACKED_DATA\nAge: 30\nEND_TRACKED_DATA>>>',
      );
      expect(analyzer.lastHealthContext, contains('Age: 30'));
    });

    test('forwards the photo as a reference plus its prepared bytes',
        () async {
      await run(buildService(), id: 'media-7', bytes: 3);
      expect(analyzer.lastNext?.attachments, [
        const AttachmentRef.image('media-7'),
      ]);
      expect(analyzer.lastImages.keys, ['media-7']);
      expect(analyzer.lastImages['media-7']?.base64, 'AAAA');
      expect(analyzer.lastImages['media-7']?.mimeType, 'image/jpeg');
    });

    test('a null health context still works and forwards null', () async {
      final outcome = await run(buildService());
      expect(outcome.blocked, isNull);
      expect(outcome.error, isNull);
      expect(analyzer.lastHealthContext, isNull);
    });

    test('the service still cannot reach the database', () {
      final src = File('lib/services/media_analysis_service.dart').readAsStringSync();
      for (final banned in const [
        'media_repository', 'media_blob_store', 'db/database', 'firestore_ref',
      ]) {
        expect(src.contains(banned), isFalse, reason: 'must not import $banned');
      }
    });
  });

  group('persistence', () {
    test('a successful turn persists both the user turn and the model reply',
        () async {
      final service = buildService();
      await run(service, question: 'what is this');

      expect(sessionStore.messages.length, 2);
      expect(sessionStore.messages[0].role, 'user');
      expect(sessionStore.messages[0].text, 'what is this');
      expect(sessionStore.messages[1].role, 'model');
      expect(sessionStore.messages[1].text, 'a description');
    });

    test('an error is not persisted', () async {
      analyzer = _FakeAnalyzer(throws: const AnalysisException('boom'));
      final service = buildService();
      await run(service, question: 'what is this');
      expect(sessionStore.messages, isEmpty);
    });

    test('a request blocked before the network is not persisted', () async {
      consentUid = null;
      final service = buildService();
      await run(service, question: 'what is this');
      expect(sessionStore.messages, isEmpty);
    });

    test(
        're-opening a photo that already has a session resumes it rather '
        'than creating a second', () async {
      final service = buildService();
      await run(service, question: 'first');
      service.endConversation('media-1'); // the sheet closed
      await run(service, question: 'second');

      expect(sessionStore.createCount, 1);
      expect(sessionStore.messages.length, 4);
      expect(
        sessionStore.messages.every((m) => m.sessionId == 'session-1'),
        isTrue,
      );
    });

    test(
        'a memo hit does not duplicate the exchange when a session already '
        'exists', () async {
      // This is the regression this group exists to guard: re-opening a
      // photo and re-asking its exact opening question serves the answer
      // from the in-memory memo rather than the network, but the SAME
      // exchange was already saved the first time. Persisting it again would
      // insert an exact duplicate pair — the live transcript never repeats
      // it, so the saved one must not either.
      final service = buildService();
      await run(service, question: 'what is this');
      expect(sessionStore.messages.length, 2); // the original save

      service.endConversation('media-1'); // the sheet closed
      await run(service, question: 'what is this'); // a memo hit

      expect(sessionStore.createCount, 1);
      expect(sessionStore.messages.length, 2);
    });

    test('a memo hit is still persisted when no session exists yet',
        () async {
      // The one case a blanket skip would break: the session was deleted
      // independently of the in-memory memo (e.g. `deleteForMedia` ran, or
      // this is a fresh MediaAnalysisService instance whose memo somehow
      // still has the entry). Skipping here would leave a later follow-up
      // with no opening turn to attach to — worse than a duplicate.
      final service = buildService();
      await run(service, question: 'what is this');
      expect(sessionStore.messages.length, 2);

      // Simulate the session having been deleted out from under the memo.
      sessionStore.sessionIdByConversation.remove('media-1');

      service.endConversation('media-1');
      await run(service, question: 'what is this'); // a memo hit, no session

      expect(sessionStore.createCount, 2);
      expect(sessionStore.messages.length, 4);
      expect(sessionStore.messages.last.sessionId, 'session-2');
    });
  });

  group('video is declined on the device', () {
    test('after consent: nothing is sent and nothing is counted', () async {
      final service = buildService();
      final outcome = await run(
        service,
        attachments: const [AnalysisAttachment.video('v1')],
        question: 'what is in this video',
      );
      expect(outcome.videoDeclined, isTrue);
      expect(outcome.blocked, isNull);
      expect(outcome.error, isNull);
      expect(analyzer.calls, 0);
      expect(usageCount, isNull);
      // The caller persists the declined pair; the service does not.
      expect(sessionStore.messages, isEmpty);
      expect(service.turnsUsed('media-1'), 0);
    });

    test('a photo sent alongside a video is not sent either', () async {
      final outcome = await run(
        buildService(),
        attachments: [_photo('p1'), const AnalysisAttachment.video('v1')],
      );
      expect(outcome.videoDeclined, isTrue);
      expect(analyzer.calls, 0);
    });

    test('a user without consent gets the consent block, not a declined pair',
        () async {
      consentUid = null;
      final outcome = await run(
        buildService(),
        attachments: const [AnalysisAttachment.video('v1')],
      );
      expect(outcome.blocked, AnalysisBlock.notConsented);
      expect(outcome.videoDeclined, isFalse);
    });

    test('the declined pair does not count toward the turn cap', () async {
      final service = buildService();
      service.seedConversation('c1', [
        for (var i = 0; i < kMaxChatTurns - 1; i++) ...[
          AnalysisTurn.user('question $i'),
          AnalysisTurn.model('answer $i'),
        ],
        const AnalysisTurn.user(
          'this video',
          attachments: [AttachmentRef.video('v1')],
          includeInModel: false,
        ),
        const AnalysisTurn.model('declined', includeInModel: false),
      ]);
      expect(service.turnsUsed('c1'), kMaxChatTurns - 1);

      final last = await run(service, id: 'c1', attachments: const []);
      expect(last.blocked, isNull);
      final over = await run(service, id: 'c1', attachments: const []);
      expect(over.blocked, AnalysisBlock.turnCap);
    });
  });

  group('conversations keyed by id, not by photo', () {
    test('a text-only conversation reaches the analyzer with no images',
        () async {
      final outcome = await run(
        buildService(),
        id: 'c1',
        attachments: const [],
        question: 'is a 35 day cycle normal',
      );
      expect(outcome.result?.prose, 'a description');
      expect(analyzer.lastNext?.attachments, isEmpty);
      expect(analyzer.lastImages, isEmpty);
    });

    test('earlier photos stay available to every later turn', () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: [_photo('p1')]);
      await run(service, id: 'c1', attachments: [_photo('p2')]);
      await run(service, id: 'c1', attachments: const [], question: 'compare');

      expect(analyzer.lastNext?.attachments, isEmpty);
      expect(analyzer.lastImages.keys, unorderedEquals(['p1', 'p2']));
      expect(analyzer.lastHistory[0].attachments, [
        const AttachmentRef.image('p1'),
      ]);
      expect(analyzer.lastHistory[2].attachments, [
        const AttachmentRef.image('p2'),
      ]);
    });

    test('a resumed conversation gets its images from the caller', () async {
      final service = buildService();
      service.seedConversation(
        'c1',
        const [
          AnalysisTurn.user('this', attachments: [AttachmentRef.image('p1')]),
          AnalysisTurn.model('A rash.'),
        ],
        images: const {
          'p1': InlineImage(mimeType: 'image/jpeg', base64: 'QUJD'),
        },
      );
      await run(service, id: 'c1', attachments: const []);
      expect(analyzer.lastImages['p1']?.base64, 'QUJD');
    });

    test('a photo the caller no longer has is simply absent', () async {
      // The builder turns a missing id into the deleted-photo placeholder.
      final service = buildService();
      service.seedConversation('c1', const [
        AnalysisTurn.user('this', attachments: [AttachmentRef.image('gone')]),
        AnalysisTurn.model('A rash.'),
      ]);
      await run(service, id: 'c1', attachments: const []);
      expect(analyzer.lastImages.containsKey('gone'), isFalse);
      expect(analyzer.calls, 1);
    });

    test('a successful turn persists its attachment references', () async {
      await run(
        buildService(),
        id: 'c1',
        attachments: [_photo('p1'), _photo('p2')],
      );
      expect(sessionStore.messages.first.attachments, const [
        AttachmentRef.image('p1'),
        AttachmentRef.image('p2'),
      ]);
      expect(sessionStore.sessionIdByConversation.keys, ['c1']);
    });

    test('a failed turn leaves no photo behind for the next one', () async {
      final service = buildService();
      analyzer.throws = const AnalysisException('boom');
      await run(service, id: 'c1', attachments: [_photo('p1')]);
      analyzer.throws = null;
      await run(service, id: 'c1', attachments: const []);
      expect(analyzer.lastHistory, isEmpty);
      expect(analyzer.lastImages, isEmpty);
    });
  });

  group('photo caps', () {
    test('more than $kMaxImagesPerMessage photos in one message', () async {
      final outcome = await run(
        buildService(),
        id: 'c1',
        attachments: [
          for (var i = 0; i <= kMaxImagesPerMessage; i++) _photo('p$i'),
        ],
      );
      expect(outcome.blocked, AnalysisBlock.tooManyPhotos);
      expect(analyzer.calls, 0);
    });

    test('more than $kMaxImagesPerConversation photos in one conversation',
        () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: [
        for (var i = 0; i < kMaxImagesPerMessage; i++) _photo('p$i'),
      ]);
      final outcome = await run(service, id: 'c1', attachments: [
        _photo('q1'),
        _photo('q2'),
      ]);
      expect(outcome.blocked, AnalysisBlock.tooManyPhotos);
      expect(analyzer.calls, 1);
      expect(usageCount, 1);
    });

    test('re-attaching a photo already in the conversation is not a new one',
        () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: [
        for (var i = 0; i < kMaxImagesPerMessage; i++) _photo('p$i'),
      ]);
      final outcome = await run(service, id: 'c1', attachments: [
        _photo('p0'),
        _photo('q1'),
      ]);
      expect(outcome.blocked, isNull);
    });

    test('photos that would overflow the inline budget are refused',
        () async {
      // Two 4 MB photos are ~10.7 MB of base64; a third pushes the resent
      // conversation past kMaxInlineRequestBytes.
      final service = buildService();
      const mb = 1024 * 1024;
      await run(service, id: 'c1', attachments: [
        _photo('p1', bytes: 4 * mb),
        _photo('p2', bytes: 4 * mb),
      ]);
      final outcome = await run(service, id: 'c1', attachments: [
        _photo('p3', bytes: 2 * mb),
      ]);
      expect(outcome.blocked, AnalysisBlock.tooLarge);
      expect(analyzer.calls, 1);
      expect(usageCount, 1);
    });
  });

  group('memo (v16)', () {
    test('keyed by the sorted photo ids, not by the conversation', () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: [_photo('a'), _photo('b')]);
      final outcome =
          await run(service, id: 'c2', attachments: [_photo('b'), _photo('a')]);
      expect(analyzer.calls, 1);
      expect(outcome.result?.prose, 'a description');
      expect(service.turnsUsed('c2'), 1);
    });

    test('a text-only opener is never memoized', () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: const [], question: 'hi');
      await run(service, id: 'c2', attachments: const [], question: 'hi');
      expect(analyzer.calls, 2);
    });

    test('holds at most $kAnalysisMemoSize openers, least recent out first',
        () async {
      final service = buildService();
      for (var i = 0; i <= kAnalysisMemoSize; i++) {
        usageCount = null; // one more opener than the daily cap allows
        await run(service, id: 'c$i', attachments: [_photo('p$i')]);
      }
      expect(analyzer.calls, kAnalysisMemoSize + 1);
      // p0 was evicted by the last opener; p1 is still held.
      await run(service, id: 'again-1', attachments: [_photo('p1')]);
      expect(analyzer.calls, kAnalysisMemoSize + 1);
      usageCount = null;
      await run(service, id: 'again-0', attachments: [_photo('p0')]);
      expect(analyzer.calls, kAnalysisMemoSize + 2);
    });

    test('is cleared when the signed-in account changes', () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: [_photo('p1')]);

      claim = const ClaimRecord(uid: 'uid-2', declined: false);
      consentUid = 'uid-2';
      await trigger.setUser('uid-2');

      await run(service, id: 'c2', attachments: [_photo('p1')]);
      expect(analyzer.calls, 2);
    });

    test('is cleared when the day rolls over', () async {
      final service = buildService();
      await run(service, id: 'c1', attachments: [_photo('p1')]);
      clock = DateTime(2026, 8, 13, 9);
      await run(service, id: 'c2', attachments: [_photo('p1')]);
      expect(analyzer.calls, 2);
    });
  });
}
