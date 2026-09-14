import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/analysis_session_repository.dart';
import 'package:menstrul_track/db/database.dart';

void main() {
  late AppDatabase db;
  late AnalysisSessionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AnalysisSessionRepository(db);
  });
  tearDown(() => db.close());

  group('create', () {
    test('persists the row and returns it, with consentVersion stored',
        () async {
      final s = await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);

      expect(s.uid, 'u1');
      expect(s.mediaId, 'm1');
      expect(s.consentVersion, 2);

      // Round-trips through a fresh read, not just the in-memory return.
      final found = await repo.forMedia(uid: 'u1', mediaId: 'm1');
      expect(found, isNotNull);
      expect(found!.id, s.id);
      expect(found.consentVersion, 2);
    });
  });

  group('forMedia', () {
    test('finds the session for the right uid and mediaId', () async {
      await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);

      final found = await repo.forMedia(uid: 'u1', mediaId: 'm1');
      expect(found, isNotNull);
      expect(found!.mediaId, 'm1');
    });

    test('returns null when no session exists for that media', () async {
      expect(await repo.forMedia(uid: 'u1', mediaId: 'nope'), isNull);
    });

    test("does not return another account's session for the same media id",
        () async {
      await repo.create(uid: 'u1', mediaId: 'shared', consentVersion: 2);
      expect(await repo.forMedia(uid: 'u2', mediaId: 'shared'), isNull);
    });
  });

  group('allFor', () {
    test("returns only the given uid's sessions", () async {
      await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.create(uid: 'u2', mediaId: 'm2', consentVersion: 2);

      final u1Sessions = await repo.allFor('u1');
      expect(u1Sessions, hasLength(1));
      expect(u1Sessions.single.mediaId, 'm1');
      expect(await repo.allFor('u2'), hasLength(1));
    });

    test('orders newest first', () async {
      final first =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      final second =
          await repo.create(uid: 'u1', mediaId: 'm2', consentVersion: 2);

      final sessions = await repo.allFor('u1');
      // Drift's default DateTime column storage truncates to whole seconds,
      // so two sessions created back-to-back in a test almost always tie on
      // createdAt. This asserts the tiebreak (insertion order) resolves that
      // tie deterministically toward "most recently created first" rather
      // than leaving it to undefined SQL sort order.
      expect(sessions.map((s) => s.id), [second.id, first.id]);
    });
  });

  group('messagesFor', () {
    test('returns messages in transcript order', () async {
      final s =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.append(sessionId: s.id, role: 'user', text: 'what is this');
      await repo.append(sessionId: s.id, role: 'model', text: 'a description');
      await repo.append(sessionId: s.id, role: 'user', text: 'and this part?');

      final msgs = await repo.messagesFor(s.id);
      expect(msgs.map((m) => m.role), ['user', 'model', 'user']);
      expect(msgs.map((m) => m.messageText),
          ['what is this', 'a description', 'and this part?']);
    });

    test('only returns turns for the requested session', () async {
      final a =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      final b =
          await repo.create(uid: 'u1', mediaId: 'm2', consentVersion: 2);
      await repo.append(sessionId: a.id, role: 'user', text: 'about a');
      await repo.append(sessionId: b.id, role: 'user', text: 'about b');

      expect((await repo.messagesFor(a.id)).map((m) => m.messageText),
          ['about a']);
      expect((await repo.messagesFor(b.id)).map((m) => m.messageText),
          ['about b']);
    });
  });

  group('append', () {
    test('persists role and body text, round-tripping through messagesFor',
        () async {
      final s =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.append(
          sessionId: s.id, role: 'model', text: 'a full description');

      final msgs = await repo.messagesFor(s.id);
      expect(msgs, hasLength(1));
      expect(msgs.single.role, 'model');
      expect(msgs.single.messageText, 'a full description');
      expect(msgs.single.sessionId, s.id);
    });
  });

  group('deleteForMedia', () {
    test('removes the session and its messages', () async {
      final s =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.append(sessionId: s.id, role: 'user', text: 'hi');
      await repo.append(sessionId: s.id, role: 'model', text: 'hello');

      await repo.deleteForMedia('m1');

      expect(await repo.allFor('u1'), isEmpty);
      expect(await repo.forMedia(uid: 'u1', mediaId: 'm1'), isNull);
      // The exact failure this method exists to prevent: an orphaned
      // transcript surviving the session (and photo) it was about.
      expect(await repo.messagesFor(s.id), isEmpty);
    });

    test("leaves other media's sessions untouched", () async {
      final keep = await repo.create(
          uid: 'u1', mediaId: 'keep-me', consentVersion: 2);
      await repo.create(uid: 'u1', mediaId: 'delete-me', consentVersion: 2);

      await repo.deleteForMedia('delete-me');

      final remaining = await repo.allFor('u1');
      expect(remaining.map((s) => s.id), [keep.id]);
    });
  });

  group('deleteExcept', () {
    test(
        "drops other accounts' sessions and messages, keeps the named uid's",
        () async {
      final kept =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      final dropped =
          await repo.create(uid: 'u2', mediaId: 'm2', consentVersion: 2);
      await repo.append(sessionId: dropped.id, role: 'user', text: 'hi');

      await repo.deleteExcept('u1');

      expect((await repo.allFor('u1')).map((s) => s.id), [kept.id]);
      expect(await repo.allFor('u2'), isEmpty);
      expect(await repo.messagesFor(dropped.id), isEmpty);
    });

    test('passing null drops every session', () async {
      await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.create(uid: 'u2', mediaId: 'm2', consentVersion: 2);

      await repo.deleteExcept(null);

      expect(await repo.allFor('u1'), isEmpty);
      expect(await repo.allFor('u2'), isEmpty);
    });
  });
}
