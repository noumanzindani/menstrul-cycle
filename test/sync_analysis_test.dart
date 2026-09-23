// `show Value` avoids drift's Column/Table names colliding with flutter_test.
import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseException, Timestamp;
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/analysis_session_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/media_analysis.dart';
import 'package:menstrul_track/services/sync_service.dart';

/// A Firestore that denies WRITES to one document, the way a per-document
/// rule (the staged "a tombstone stays a tombstone" rule, say) denies a single
/// write while the rest of the collection is fine.
///
/// `FakeFirebaseFirestore` has no rules engine of its own that throws a real
/// `permission-denied`; its hook throws a bare `Exception`. This double
/// replaces that hook with the error the real SDK raises. `method` is the
/// fake's own `Method` enum, left untyped so the test does not import a
/// transitive package; only its name is read.
class _DocDenyingFirestore extends FakeFirebaseFirestore {
  _DocDenyingFirestore(this.deniedPath);

  final String deniedPath;

  @override
  Future<void> maybeThrowSecurityException(String path, method) async {
    if (path == deniedPath && '$method' != 'Method.read') {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
    }
    return super.maybeThrowSecurityException(path, method);
  }
}

const _sessions = 'users/uid-1/analysisSessions';
const _messages = 'users/uid-1/analysisMessages';

void main() {
  late AppDatabase db;
  late AnalysisSessionRepository repo;
  late FakeFirebaseFirestore firestore;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AnalysisSessionRepository(db);
    firestore = FakeFirebaseFirestore();
    sync = SyncService(
      db: db,
      firestore: firestore,
      uid: 'uid-1',
      deviceId: 'device-1',
    );
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>?> remote(String path) async =>
      (await firestore.doc(path).get()).data();

  Future<List<String>> remoteIds(String collection) async =>
      (await firestore.collection(collection).get())
          .docs
          .map((d) => d.id)
          .toList();

  Future<AnalysisSession?> local(String id) => (db.select(
        db.analysisSessions,
      )..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Pins a session's `updatedAt`, as if it were last touched on [at].
  Future<void> backdate(String id, DateTime at) =>
      (db.update(db.analysisSessions)..where((t) => t.id.equals(id)))
          .write(AnalysisSessionsCompanion(updatedAt: Value(at)));

  /// A session document as a peer would have pushed it.
  Map<String, dynamic> peerSession({
    String mediaId = '',
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? title,
  }) =>
      {
        'uid': 'uid-1',
        'mediaId': mediaId,
        'consentVersion': 7,
        'createdAt': DateTime(2026, 9, 1).millisecondsSinceEpoch,
        'updatedAt': (updatedAt ?? DateTime(2026, 9, 2)).millisecondsSinceEpoch,
        'title': ?title,
        if (deletedAt != null) 'deletedAt': deletedAt.millisecondsSinceEpoch,
        'syncedAt': Timestamp.now(),
      };

  Map<String, dynamic> peerMessage(String sessionId, String text) => {
        'sessionId': sessionId,
        'role': 'user',
        'messageText': text,
        'createdAt': DateTime(2026, 9, 2).millisecondsSinceEpoch,
        'updatedAt': DateTime(2026, 9, 2).millisecondsSinceEpoch,
        'syncedAt': Timestamp.now(),
      };

  group('push', () {
    test(
      "another account's conversation on this device is never pushed",
      () async {
        // Signing out does not wipe the device, so a second account's rows can
        // sit in the same tables. Pushing them under THIS uid would copy one
        // person's conversation about their body into another person's cloud.
        final mine = await repo.create(uid: 'uid-1', consentVersion: 7);
        final theirs = await repo.create(uid: 'uid-2', consentVersion: 7);
        await repo.append(sessionId: mine.id, role: 'user', text: 'mine');
        await repo.append(sessionId: theirs.id, role: 'user', text: 'theirs');

        await sync.syncNow();

        expect(await remoteIds(_sessions), [mine.id]);
        final texts = (await firestore.collection(_messages).get())
            .docs
            .map((d) => d['messageText'])
            .toList();
        expect(
          texts,
          ['mine'],
          reason: 'message documents carry no uid, so they must be filtered '
              'through the session they belong to',
        );
      },
    );

    test(
      'a live conversation pushes its title, attachments and flag',
      () async {
        final s = await repo.create(
          uid: 'uid-1',
          title: 'is this normal',
          consentVersion: 7,
        );
        await repo.append(
          sessionId: s.id,
          role: 'user',
          text: 'look',
          attachments: [AttachmentRef.image('a' * 32)],
        );

        await sync.syncNow();

        expect(
          (await remote('$_sessions/${s.id}'))!['title'],
          'is this normal',
        );
        final msg = (await firestore.collection(_messages).get()).docs.single;
        expect(msg['attachments'], [
          {'mediaId': 'a' * 32, 'kind': 'image'},
        ]);
        expect(msg['includeInModel'], isTrue);
      },
    );

    test(
      'a tombstone is pushed in full shape and its messages are deleted',
      () async {
        final doomed = await repo.create(
          uid: 'uid-1',
          mediaId: 'media-1',
          title: 'hi',
          consentVersion: 7,
        );
        final kept = await repo.create(uid: 'uid-1', consentVersion: 7);
        await repo.append(sessionId: doomed.id, role: 'user', text: 'one');
        await repo.append(sessionId: doomed.id, role: 'model', text: 'two');
        await repo.append(sessionId: kept.id, role: 'user', text: 'keep me');
        await sync.syncNow();
        expect(await remoteIds(_messages), hasLength(3));

        // Deleted offline, after the conversation had already been backed up.
        await repo.tombstone(doomed.id);
        await sync.syncNow();

        final doc = (await remote('$_sessions/${doomed.id}'))!;
        expect(doc['deletedAt'], isA<int>());
        expect(
          doc['mediaId'],
          'media-1',
          reason: 'a v15 client would store an empty ghost row without it',
        );
        expect(doc['consentVersion'], 7);
        expect(doc['createdAt'], isA<int>());
        expect(
          doc.containsKey('title'),
          isFalse,
          reason: "the user's own first words outlived their delete",
        );
        final left = (await firestore.collection(_messages).get())
            .docs
            .map((d) => d['messageText'])
            .toList();
        expect(left, ['keep me']);
      },
    );
  });

  group('pull', () {
    test('a pulled tombstone deletes the conversation here too', () async {
      final s = await repo.create(
        uid: 'uid-1',
        title: 'on this phone',
        consentVersion: 7,
      );
      await repo.append(sessionId: s.id, role: 'user', text: 'hello');

      await firestore.doc('$_sessions/${s.id}').set(
            peerSession(
              updatedAt: DateTime(2026, 9, 3),
              deletedAt: DateTime(2026, 9, 3),
            ),
          );

      await sync.syncNow();

      final row = (await local(s.id))!;
      expect(row.deletedAt, isNotNull);
      expect(row.title, isNull);
      expect(await repo.messagesFor(s.id), isEmpty);
      expect(await repo.allFor('uid-1'), isEmpty);
    });

    test(
      'a tombstone for a conversation never seen here is kept, hidden',
      () async {
        // Kept as a row, not skipped: it is what stops a later stale copy of
        // the same conversation from arriving as a live one.
        await firestore
            .doc('$_sessions/s-gone')
            .set(peerSession(deletedAt: DateTime(2026, 9, 3)));

        await sync.syncNow();

        expect((await local('s-gone'))!.deletedAt, isNotNull);
        expect(await repo.allFor('uid-1'), isEmpty);
      },
    );

    test(
      'a message arriving under a deleted conversation is dropped',
      () async {
        final s = await repo.create(uid: 'uid-1', consentVersion: 7);
        await repo.tombstone(s.id);
        await firestore.doc('$_messages/m-late').set(peerMessage(s.id, 'late'));

        await sync.syncNow();

        expect(await repo.messagesFor(s.id), isEmpty);
      },
    );

    test('a stale v15 copy cannot resurrect a deleted conversation', () async {
      // A v15 device knows nothing of `deletedAt`. When it next appends to
      // this conversation it `set()`s the whole old-shape document, wiping
      // the tombstone remotely. This device must keep its own tombstone AND
      // write it back, or every other device would see the chat come back.
      final s = await repo.create(uid: 'uid-1', consentVersion: 7);
      await repo.tombstone(s.id);
      await (db.update(
        db.analysisSessions,
      )..where((t) => t.id.equals(s.id)))
          .write(
        AnalysisSessionsCompanion(updatedAt: Value(DateTime(2026, 9, 1))),
      );
      // Already synced past the tombstone, so on its own it would never be
      // pushed again.
      await SettingsRepository(db).updateSyncState(
        AppSettingsCompanion(lastSyncedAt: Value(DateTime(2026, 9, 10))),
      );
      await firestore.doc('$_sessions/${s.id}').set(
            peerSession(updatedAt: DateTime(2026, 9, 11), title: 'back again'),
          );
      await firestore
          .doc('$_messages/m-v15')
          .set(peerMessage(s.id, 'from the old phone'));

      await sync.syncNow();

      final row = (await local(s.id))!;
      expect(row.deletedAt, isNotNull, reason: 'the stale copy undeleted it');
      expect(row.title, isNull);
      expect(await repo.messagesFor(s.id), isEmpty);
      final doc = (await remote('$_sessions/${s.id}'))!;
      expect(
        doc['deletedAt'],
        isA<int>(),
        reason: 'the tombstone was not re-asserted remotely',
      );
      expect(doc.containsKey('title'), isFalse);
      expect(
        await remoteIds(_messages),
        isEmpty,
        reason: "the v15 device's message outlived the delete remotely",
      );
    });

    test(
      'a late message under a deleted conversation is removed remotely too',
      () async {
        // The tombstone is already in the cloud and was synced past long ago,
        // so this run has no reason to push it again. A v15 device, which
        // never learned of the delete, then pushes one more turn: plaintext
        // user text, sitting in the cloud after the user deleted it.
        final s = await repo.create(uid: 'uid-1', consentVersion: 7);
        await repo.tombstone(s.id);
        await backdate(s.id, DateTime(2026, 9, 1));
        await sync.syncNow();
        expect((await remote('$_sessions/${s.id}'))!['deletedAt'], isA<int>());
        await SettingsRepository(db).updateSyncState(
          AppSettingsCompanion(lastSyncedAt: Value(DateTime(2026, 9, 10))),
        );
        await firestore.doc('$_messages/m-late').set(peerMessage(s.id, 'late'));

        await sync.syncNow();

        expect(await repo.messagesFor(s.id), isEmpty);
        expect(
          await remoteIds(_messages),
          isEmpty,
          reason: 'the late turn outlived the delete in the cloud',
        );
      },
    );

    test(
      'a v15 device on the same account lets a re-asserted tombstone settle',
      () async {
        // A v15 client, reduced to what its sync does to one session: pull
        // any document stamped at or after its cursor and keep the REMOTE
        // `updatedAt` (never `deletedAt`, which it has not heard of), then
        // re-`set()` the old shape if that `updatedAt` is not before the start
        // of its previous run.
        //
        // Real runs are seconds apart; these are milliseconds apart, and
        // drift stores a DateTime to the second. The v15 clock is set an hour
        // back so each of its runs still starts after this device's previous
        // one, as it would on real hardware.
        final s = await repo.create(uid: 'uid-1', consentVersion: 7);
        await repo.tombstone(s.id);
        await backdate(s.id, DateTime(2026, 9, 1));
        await sync.syncNow();

        final path = '$_sessions/${s.id}';
        Timestamp? v15Cursor;
        var v15UpdatedAt = DateTime(2026, 8, 30);
        // Its last sync predates the delete.
        var v15Since = DateTime(2026, 8, 15);
        var v15Writes = 0;
        Future<void> v15Sync() async {
          final startedAt =
              DateTime.now().subtract(const Duration(hours: 1));
          final doc = (await remote(path))!;
          final stamped = doc['syncedAt'] as Timestamp;
          if (v15Cursor == null || stamped.compareTo(v15Cursor!) >= 0) {
            v15UpdatedAt =
                DateTime.fromMillisecondsSinceEpoch(doc['updatedAt'] as int);
            v15Cursor = stamped;
          }
          if (!v15UpdatedAt.isBefore(v15Since)) {
            v15Writes++;
            await firestore.doc(path).set({
              'uid': 'uid-1',
              'mediaId': '',
              'consentVersion': 7,
              'createdAt': doc['createdAt'],
              'updatedAt': v15UpdatedAt.millisecondsSinceEpoch,
              'syncedAt': Timestamp.now(),
            });
          }
          v15Since = startedAt;
        }

        // The first round is the unavoidable one: the v15 device re-sends
        // the stale copy once, and this device writes the tombstone back.
        await v15Sync();
        expect(v15Writes, 1);
        await sync.syncNow();
        expect((await remote(path))!['deletedAt'], isA<int>());
        final settled = (await remote(path))!;

        for (var i = 0; i < 3; i++) {
          await v15Sync();
          await sync.syncNow();
        }

        expect(
          v15Writes,
          1,
          reason: 'the v15 device keeps re-sending its stale copy',
        );
        final doc = (await remote(path))!;
        expect(doc['deletedAt'], isA<int>());
        expect(
          doc['syncedAt'],
          settled['syncedAt'],
          reason: 'the tombstone is still being rewritten on every sync',
        );
        expect(
          doc['updatedAt'],
          DateTime(2026, 9, 1).millisecondsSinceEpoch,
          reason: 're-asserting moved the tombstone forward in time',
        );
        expect((await local(s.id))!.deletedAt, isNotNull);
      },
    );

    test('an old-format conversation is accepted as it is', () async {
      await firestore
          .doc('$_sessions/s-old')
          .set(peerSession(mediaId: 'media-1'));
      await firestore
          .doc('$_messages/m-old')
          .set(peerMessage('s-old', 'what is this'));

      await sync.syncNow();

      final session = (await repo.allFor('uid-1')).single;
      expect(session.mediaId, 'media-1');
      expect(session.title, isNull);
      expect(session.deletedAt, isNull);
      final message = (await repo.messagesFor('s-old')).single;
      expect(message.attachmentsJson, isNull);
      expect(message.includeInModel, isTrue);
    });

    test(
      'a v15 copy without a title does not erase the one stored here',
      () async {
        final s = await repo.create(
          uid: 'uid-1',
          title: 'my own words',
          consentVersion: 7,
        );
        await firestore
            .doc('$_sessions/${s.id}')
            .set(peerSession(updatedAt: DateTime(2026, 9, 30)));

        await sync.syncNow();

        expect((await local(s.id))!.title, 'my own words');
      },
    );
  });

  group('a denied document', () {
    test('does not abort the sync, and the rest still pushes', () async {
      final a = await repo.create(uid: 'uid-1', consentVersion: 7);
      final b = await repo.create(uid: 'uid-1', consentVersion: 7);
      final denying = _DocDenyingFirestore('$_sessions/${a.id}');
      final guarded = SyncService(
        db: db,
        firestore: denying,
        uid: 'uid-1',
        deviceId: 'device-1',
      );

      await guarded.syncNow();

      final pushed = (await denying.collection(_sessions).get())
          .docs
          .map((d) => d.id)
          .toList();
      expect(pushed, [b.id]);
      expect(
        (await db.getSettings()).lastSyncedAt,
        isNotNull,
        reason: 'one denied document stalled the whole sync',
      );
    });

    test('any other failure still aborts, so it is retried', () async {
      // Only `permission-denied` is tolerated: it never heals on retry. A
      // network error does, and must keep the push window open.
      final a = await repo.create(uid: 'uid-1', consentVersion: 7);
      final failing = _FailingFirestore('$_sessions/${a.id}');
      final guarded = SyncService(
        db: db,
        firestore: failing,
        uid: 'uid-1',
        deviceId: 'device-1',
      );

      await expectLater(guarded.syncNow(), throwsA(isA<FirebaseException>()));
      expect((await db.getSettings()).lastSyncedAt, isNull);
    });
  });
}

/// Fails one document with a transient error rather than a denial.
class _FailingFirestore extends FakeFirebaseFirestore {
  _FailingFirestore(this.failingPath);

  final String failingPath;

  @override
  Future<void> maybeThrowSecurityException(String path, method) async {
    if (path == failingPath) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return super.maybeThrowSecurityException(path, method);
  }
}
