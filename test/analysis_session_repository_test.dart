import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/analysis_session_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/media_analysis.dart';

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

    test('a chat started in the tab has no photo and an empty mediaId',
        () async {
      final s = await repo.create(uid: 'u1', consentVersion: 7);

      expect(s.mediaId, '');
      expect(s.title, isNull);
      expect(s.deletedAt, isNull);
      expect((await repo.allFor('u1')).single.id, s.id);
    });

    test('stores the title trimmed and cut to 60 characters', () async {
      final s = await repo.create(
          uid: 'u1', consentVersion: 7, title: '  ${'x' * 80}  ');
      expect(s.title, 'x' * 60);

      final blank =
          await repo.create(uid: 'u1', consentVersion: 7, title: '   ');
      expect(blank.title, isNull, reason: 'a blank title is no title');
    });

    test('cutting the title never splits a surrogate pair', () async {
      // 59 ASCII characters then an emoji, which is two UTF-16 code units: a
      // code-unit cut at 60 would leave half of it behind.
      final s = await repo.create(
          uid: 'u1', consentVersion: 7, title: '${'a' * 59}\u{1F338}tail');
      expect(s.title, '${'a' * 59}\u{1F338}');
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

    test('never matches a chat started without a photo', () async {
      await repo.create(uid: 'u1', consentVersion: 7);
      expect(await repo.forMedia(uid: 'u1', mediaId: ''), isNull);
    });

    test('skips a deleted conversation, so Describe starts a fresh one',
        () async {
      final s =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.tombstone(s.id);
      expect(await repo.forMedia(uid: 'u1', mediaId: 'm1'), isNull);
    });
  });

  group('allFor', () {
    test('leaves out deleted conversations', () async {
      final kept =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      final gone = await repo.create(uid: 'u1', consentVersion: 7);
      await repo.tombstone(gone.id);

      expect((await repo.allFor('u1')).map((s) => s.id), [kept.id]);
    });

    test("returns only the given uid's sessions", () async {
      await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.create(uid: 'u2', mediaId: 'm2', consentVersion: 2);

      final u1Sessions = await repo.allFor('u1');
      expect(u1Sessions, hasLength(1));
      expect(u1Sessions.single.mediaId, 'm1');
      expect(await repo.allFor('u2'), hasLength(1));
    });

    test('orders newest-created first when neither has been appended to',
        () async {
      final first =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      final second =
          await repo.create(uid: 'u1', mediaId: 'm2', consentVersion: 2);

      final sessions = await repo.allFor('u1');
      // Drift's default DateTime column storage truncates to whole seconds,
      // so two sessions created back-to-back in a test almost always tie on
      // updatedAt (equal to createdAt for a fresh session). This asserts the
      // tiebreak (insertion/rowid order) resolves that tie deterministically
      // toward "most recently created first" rather than leaving it to
      // undefined SQL sort order.
      expect(sessions.map((s) => s.id), [second.id, first.id]);
    });

    test('appending to the OLDER session moves it back to the front',
        () async {
      // Seeded directly (not through create()) with explicit, clearly
      // ordered `updatedAt` values in the past. create() stamps
      // DateTime.now(), and this DB's DateTime columns truncate to whole
      // seconds (confirmed empirically while building this repository) —
      // two create() calls in a fast test reliably tie on that column, so
      // trusting relative wall-clock order between them would make this
      // test flaky. test/sync_service_test.dart's `bumpMarkerForward` hits
      // the identical problem and solves it the same way: force an
      // unambiguous starting point directly, then exercise the real code
      // path under test.
      final older = DateTime(2020, 1, 1);
      final newer = DateTime(2020, 1, 2);
      await db.into(db.analysisSessions).insert(AnalysisSessionsCompanion.insert(
            id: 'a',
            uid: 'u1',
            mediaId: 'm1',
            consentVersion: 2,
            createdAt: Value(older),
            updatedAt: Value(older),
          ));
      await db.into(db.analysisSessions).insert(AnalysisSessionsCompanion.insert(
            id: 'b',
            uid: 'u1',
            mediaId: 'm2',
            consentVersion: 2,
            createdAt: Value(newer),
            updatedAt: Value(newer),
          ));

      // Before any activity, b (the more recently updated one) sorts first.
      expect((await repo.allFor('u1')).map((s) => s.id), ['b', 'a']);

      // Appending to a is "activity" on a — it must sort ahead of b
      // afterward even though b's stored updatedAt is later, because
      // append() bumps a's updatedAt to DateTime.now(), which — whatever the
      // real clock reads when this test runs — is unambiguously after
      // January 2020. This assertion fails if append() stops bumping
      // AnalysisSessions.updatedAt.
      await repo.append(sessionId: 'a', role: 'user', text: 'a follow-up');

      expect((await repo.allFor('u1')).map((s) => s.id), ['a', 'b']);
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
      expect(msgs.single.attachmentsJson, isNull,
          reason: 'a turn with no attachments stores none');
      expect(msgs.single.includeInModel, isTrue);
    });

    test('attachments round-trip as references only', () async {
      final s = await repo.create(uid: 'u1', consentVersion: 7);
      final photo = 'a' * 32;
      final video = 'b' * 32;
      await repo.append(
        sessionId: s.id,
        role: 'user',
        text: 'what about these?',
        attachments: [
          AttachmentRef.image(photo),
          AttachmentRef.video(video),
        ],
      );

      final msg = (await repo.messagesFor(s.id)).single;
      // The exact stored shape: ids and kinds, never bytes or URLs.
      expect(msg.attachmentsJson,
          '[{"mediaId":"$photo","kind":"image"},'
          '{"mediaId":"$video","kind":"video"}]');
      expect(decodeAttachments(msg.attachmentsJson),
          [AttachmentRef.image(photo), AttachmentRef.video(video)]);
    });

    test('stores includeInModel false for a turn the model must not see',
        () async {
      final s = await repo.create(uid: 'u1', consentVersion: 7);
      await repo.append(
          sessionId: s.id,
          role: 'model',
          text: 'a declined-video notice',
          includeInModel: false);

      expect((await repo.messagesFor(s.id)).single.includeInModel, isFalse);
    });
  });

  group('tombstone', () {
    test('marks the session deleted, bumps updatedAt and drops its messages',
        () async {
      final old = DateTime(2020, 1, 1);
      await db.into(db.analysisSessions).insert(AnalysisSessionsCompanion.insert(
            id: 'a',
            uid: 'u1',
            mediaId: '',
            consentVersion: 7,
            title: const Value('a title'),
            createdAt: Value(old),
            updatedAt: Value(old),
          ));
      await repo.append(sessionId: 'a', role: 'user', text: 'hi');
      // append() bumped updatedAt; pin it back so the tombstone's own bump is
      // what the assertion below observes.
      await (db.update(db.analysisSessions)..where((t) => t.id.equals('a')))
          .write(AnalysisSessionsCompanion(updatedAt: Value(old)));

      await repo.tombstone('a');

      // The row stays, so the next sync can push the deletion to other
      // devices; it is only hidden from every read.
      final row = await (db.select(db.analysisSessions)
            ..where((t) => t.id.equals('a')))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.updatedAt.isAfter(old), isTrue,
          reason: 'the push picks up rows by updatedAt');
      // The title is a verbatim copy of what the user typed; the row survives
      // only to carry the deletion, so it must not carry that text too.
      expect(row.title, isNull);
      expect(await repo.messagesFor('a'), isEmpty);
      expect(await repo.allFor('u1'), isEmpty);
    });

    test('leaves other sessions and their messages alone', () async {
      final keep = await repo.create(uid: 'u1', consentVersion: 7);
      final gone = await repo.create(uid: 'u1', consentVersion: 7);
      await repo.append(sessionId: keep.id, role: 'user', text: 'kept');
      await repo.append(sessionId: gone.id, role: 'user', text: 'gone');

      await repo.tombstone(gone.id);

      expect((await repo.messagesFor(keep.id)).single.messageText, 'kept');
      expect((await repo.allFor('u1')).map((s) => s.id), [keep.id]);
    });
  });

  group('deleteForMedia', () {
    test('tombstones the session and removes its messages', () async {
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

    test('keeps the tombstone row so the deletion can sync, minus its title',
        () async {
      final s = await repo.create(
          uid: 'u1', mediaId: 'm1', title: 'is this normal', consentVersion: 2);

      await repo.deleteForMedia('m1');

      final row = await (db.select(db.analysisSessions)
            ..where((t) => t.id.equals(s.id)))
          .getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.title, isNull);
    });

    test('also removes a conversation the photo was attached to later on',
        () async {
      final photo = 'c' * 32;
      final other = 'd' * 32;
      final s = await repo.create(uid: 'u1', consentVersion: 7);
      await repo.append(sessionId: s.id, role: 'user', text: 'hello');
      await repo.append(sessionId: s.id, role: 'model', text: 'hi');
      await repo.append(
          sessionId: s.id,
          role: 'user',
          text: 'and this?',
          attachments: [AttachmentRef.image(other), AttachmentRef.image(photo)]);
      final unrelated = await repo.create(uid: 'u1', consentVersion: 7);
      await repo.append(
          sessionId: unrelated.id,
          role: 'user',
          text: 'a different photo',
          attachments: [AttachmentRef.image(other)]);

      await repo.deleteForMedia(photo);

      expect((await repo.allFor('u1')).map((x) => x.id), [unrelated.id]);
      expect(await repo.messagesFor(s.id), isEmpty);
      expect(await repo.messagesFor(unrelated.id), hasLength(1));
    });

    test('finds a reference written with different JSON spacing', () async {
      // attachmentsJson syncs, and decodeAttachments accepts any client's
      // JSON — so the search must not depend on this encoder's exact
      // spelling of the object.
      final photo = 'e' * 32;
      final s = await repo.create(uid: 'u1', consentVersion: 7);
      await db.into(db.analysisMessages).insert(
            AnalysisMessagesCompanion.insert(
              id: 'foreign',
              sessionId: s.id,
              role: 'user',
              messageText: 'this one',
              attachmentsJson:
                  Value('[{"kind": "image", "mediaId": "$photo"}]'),
            ),
          );

      await repo.deleteForMedia(photo);

      expect(await repo.allFor('u1'), isEmpty);
    });

    test('treats the id literally, not as a LIKE pattern', () async {
      // `_` and `%` are LIKE wildcards. The id is bound, never interpolated,
      // and every candidate is re-checked against the decoded references, so
      // a wildcard-shaped id matches nothing it does not literally equal.
      final s = await repo.create(uid: 'u1', consentVersion: 7);
      await repo.append(
          sessionId: s.id,
          role: 'user',
          text: 'x',
          attachments: [const AttachmentRef.image('abc')]);

      await repo.deleteForMedia('a_c');
      await repo.deleteForMedia('%');

      expect((await repo.allFor('u1')).map((x) => x.id), [s.id]);
    });

    test('does not re-stamp a conversation that is already deleted',
        () async {
      final s =
          await repo.create(uid: 'u1', mediaId: 'm1', consentVersion: 2);
      await repo.tombstone(s.id);
      final first = DateTime(2020, 1, 1);
      await (db.update(db.analysisSessions)..where((t) => t.id.equals(s.id)))
          .write(AnalysisSessionsCompanion(
              deletedAt: Value(first), updatedAt: Value(first)));

      await repo.deleteForMedia('m1');

      final row = await (db.select(db.analysisSessions)
            ..where((t) => t.id.equals(s.id)))
          .getSingle();
      expect(row.deletedAt, first);
      expect(row.updatedAt, first);
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
