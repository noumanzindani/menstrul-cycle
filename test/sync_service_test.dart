// `show Value` avoids drift's Column/Table names colliding with flutter_test.
import 'package:drift/drift.dart' show LazyDatabase, Value;
import 'package:drift/native.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/sync_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository logs;
  late FakeFirebaseFirestore firestore;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = DailyLogRepository(db);
    firestore = FakeFirebaseFirestore();
    sync = SyncService(
      db: db,
      firestore: firestore,
      uid: 'uid-1',
      deviceId: 'device-1',
    );
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>?> remoteDay(String id) async {
    final doc =
        await firestore.collection('users/uid-1/dailyLogs').doc(id).get();
    return doc.data();
  }

  /// Puts the device in the state it is in on every run after its first: a
  /// non-null local `lastSyncedAt` (so the push gate is active and the pull is
  /// NOT a full sweep) plus the server-derived pull cursors a previous run
  /// would have committed. Seeding these separately is the point — the whole
  /// class of bug this suite guards is the two being conflated.
  Future<void> seedResumedDevice({
    required DateTime lastSyncedAt,
    Timestamp? logsCursor,
    Timestamp? deletionsCursor,
    String deviceId = 'device-1',
  }) async {
    await SettingsRepository(db).updateSyncState(
      AppSettingsCompanion(lastSyncedAt: Value(lastSyncedAt)),
    );
    await firestore.doc('users/uid-1/devices/$deviceId').set({
      'logsCursor': ?logsCursor,
      'deletionsCursor': ?deletionsCursor,
    });
  }

  /// Directly forces a just-created tombstone's `deletedAt` to be
  /// unambiguously after "now" -- and therefore after whatever `updatedAt`
  /// an earlier `sync.syncNow()` push wrote to the remote doc in the SAME
  /// test. This sidesteps this environment's tendency to tie a whole
  /// multi-step async chain (upsert -> sync -> delete) to the SAME
  /// millisecond, which would otherwise make the deletion LOSE to fix round
  /// 3's Finding 3 tie-break (an exact tie now keeps the remote/local edit,
  /// matching `_pullDeletions`'s own tie-break -- see the tie tests above).
  ///
  /// Returns the value as it is actually PERSISTED, read back from drift --
  /// not the in-memory `DateTime` that was written. Drift stores `DateTime`
  /// columns as whole unix SECONDS (this database does not set
  /// `storeDateTimeValuesAsText`), so sub-second precision is dropped at the
  /// storage boundary. The tombstone's real `deletedAt` -- the value the
  /// merge decision is made against, and the value `_pushTombstones` must
  /// write into the deletion marker -- is therefore the second-resolution one
  /// that comes back out of the table, and that is what callers must assert
  /// against.
  Future<DateTime> forceTombstoneWins(DateTime day) async {
    final forced = DateTime.now().add(const Duration(hours: 1));
    await (db.update(db.syncTombstones)..where((t) => t.date.equals(day)))
        .write(SyncTombstonesCompanion(deletedAt: Value(forced)));
    final stored =
        (await logs.getTombstones()).firstWhere((t) => t.date == day);
    return stored.deletedAt;
  }

  test('pushes a local day to users/{uid}/dailyLogs/{date}', () async {
    await logs.upsert(
      date: DateTime(2026, 8, 4),
      flow: FlowIntensity.medium,
      symptomsJson: '{"cramps":true}',
    );

    await sync.syncNow();

    final doc = await remoteDay('2026-08-04');
    expect(doc, isNotNull);
    expect(doc!['flow'], FlowIntensity.medium.index);
    expect(doc['symptoms']['cramps'], isTrue);
    expect(doc['deviceId'], 'device-1');
  });

  test('pulls a remote-only day into the local database', () async {
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-09').set({
      'date': '2026-08-09',
      'flow': FlowIntensity.light.index,
      'symptoms': <String, dynamic>{'headache': true},
      'updatedAt': DateTime(2026, 8, 9, 10).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    final local = await logs.getForDate(DateTime(2026, 8, 9));
    expect(local, isNotNull);
    expect(local!.flow, FlowIntensity.light);
    expect(local.symptoms, '{"headache":true}');
    // The pulled row must carry the REMOTE's own updatedAt, not a fresh
    // `DateTime.now()` stamped at pull time. If it didn't, every pulled day
    // would look locally-newer on the next sync and ping-pong between
    // devices forever -- this is the single most load-bearing property in
    // the file, and reverting `dailyLogFromMap`'s timestamp handling to
    // `DateTime.now()` would pass every other assertion in this suite.
    expect(local.updatedAt, DateTime(2026, 8, 9, 10));
  });

  test('a newer remote overwrites the local row', () async {
    final day = DateTime(2026, 8, 10);
    await logs.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');

    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-10').set({
      'date': '2026-08-10',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    expect((await logs.getForDate(day))!.flow, FlowIntensity.heavy);
  });

  test('an older remote does not clobber a newer local row', () async {
    final day = DateTime(2026, 8, 11);
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-11').set({
      'date': '2026-08-11',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2020, 1, 1).millisecondsSinceEpoch,
    });
    await logs.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');

    await sync.syncNow();

    expect((await logs.getForDate(day))!.flow, FlowIntensity.light);
  });

  test(
      'a document synced recently is still pulled even though its updatedAt '
      'is old (offline-then-reconnect)', () async {
    // A device can log (or delete) something OFFLINE, stamping `updatedAt`
    // with whatever the clock read at that moment, and only reconnect and
    // push much later. A peer's `since` -- captured from ITS OWN last sync,
    // which may well have happened AFTER that old `updatedAt` but BEFORE
    // this device finally reconnected -- must still see the write:
    // filtering the query on `updatedAt` would exclude it forever, since
    // `since` only ever advances. Offline-then-reconnect is a core scenario
    // for this app, not an edge case.
    // A RESUMED device, not a first sync: the pull is genuinely
    // cursor-scoped, so a query keyed off `updatedAt` really would exclude the
    // document below. Without the cursor this test would pass against any
    // implementation at all, since a first sync reads the whole collection.
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await seedResumedDevice(
      lastSyncedAt: yesterday,
      logsCursor: Timestamp.fromDate(yesterday),
    );

    await firestore.collection('users/uid-1/dailyLogs').doc('2026-01-01').set({
      'date': '2026-01-01',
      'flow': FlowIntensity.medium.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2020, 1, 1).millisecondsSinceEpoch, // far in the past
      'syncedAt': Timestamp.fromDate(DateTime.now()), // written just now
    });

    await sync.syncNow();

    expect(await logs.getForDate(DateTime(2026, 1, 1)), isNotNull);
  });

  test(
      'a device whose clock runs ahead of the server still pulls peer writes',
      () async {
    // The pull cutoff must be a value the SERVER produced. `lastSyncedAt` is
    // this device's own `DateTime.now()`; comparing it against server-stamped
    // `syncedAt` means a device running δ ahead queries
    // `syncedAt > server_now + δ` and never fetches anything a peer writes in
    // the next δ -- and never will, because the cutoff only advances. A device
    // syncing more often than δ pulls NOTHING, EVER. Here δ is a day, so the
    // failure is unambiguous rather than a race.
    await seedResumedDevice(
      lastSyncedAt: DateTime.now().add(const Duration(days: 1)),
      logsCursor: Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      deletionsCursor: Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );

    // A peer's write, server-stamped now -- i.e. BEFORE this device's clock.
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-02-02').set({
      'date': '2026-02-02',
      'flow': FlowIntensity.medium.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'syncedAt': Timestamp.fromDate(DateTime.now()),
    });

    await sync.syncNow();

    expect(await logs.getForDate(DateTime(2026, 2, 2)), isNotNull);
  });

  test(
      'the pull cursor advances to the newest server stamp actually observed, '
      'never to the device clock', () async {
    // The cursor is only ever a value the server itself produced and this
    // device actually applied, so it is by construction never ahead of the
    // server -- the property the test above depends on.
    final serverStamp = Timestamp.fromDate(DateTime(2026, 3, 3, 12));
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-03-03').set({
      'date': '2026-03-03',
      'flow': FlowIntensity.light.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 3, 3, 11).millisecondsSinceEpoch,
      'syncedAt': serverStamp,
    });

    await sync.syncNow();

    final cursorDoc = await firestore.doc('users/uid-1/devices/device-1').get();
    final logsCursor = cursorDoc.data()!['logsCursor'] as Timestamp;
    expect(logsCursor.toDate(), serverStamp.toDate());
  });

  test('a document whose server stamp lands exactly on the cursor is pulled',
      () async {
    // A strict `isGreaterThan` cutoff drops a document stamped exactly ON the
    // cursor, and because the cursor only ever advances it drops it
    // PERMANENTLY -- the same failure mode the push side was found to have.
    // Server stamps carry nanoseconds, but a cursor equal to a real stamp is
    // exactly what the inclusive bound produces on every subsequent run.
    final boundary = Timestamp.fromDate(DateTime(2026, 4, 4, 9));
    await seedResumedDevice(
      lastSyncedAt: DateTime(2026, 4, 4, 9),
      logsCursor: boundary,
      deletionsCursor: boundary,
    );

    await firestore.collection('users/uid-1/dailyLogs').doc('2026-04-04').set({
      'date': '2026-04-04',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 4, 4, 8).millisecondsSinceEpoch,
      'syncedAt': boundary,
    });

    await sync.syncNow();

    expect(await logs.getForDate(DateTime(2026, 4, 4)), isNotNull);
  });

  test('a document written before syncedAt existed is backfilled, not stranded',
      () async {
    // A Firestore range filter excludes documents that lack the ordered
    // field, so a document written before `syncedAt` existed (an older build,
    // a console write) is invisible to every cursor-scoped pull AND to the
    // retention sweep, which filters on the same field: never merged, never
    // pruned. A full sweep is the only run that can ever see it, so that is
    // where it gets its stamp.
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-05-05').set({
      'date': '2026-05-05',
      'flow': FlowIntensity.light.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 5, 5).millisecondsSinceEpoch,
      // no syncedAt
    });
    await firestore.collection('users/uid-1/deletions').doc('2026-05-06').set({
      'date': '2026-05-06',
      'deletedAt': DateTime(2026, 5, 6).millisecondsSinceEpoch,
      // no syncedAt
    });

    await sync.syncNow(); // a first sync: lastSyncedAt is null, so a full sweep

    final day =
        await firestore.collection('users/uid-1/dailyLogs').doc('2026-05-05').get();
    expect(day.data()!['syncedAt'], isA<Timestamp>());
    final marker =
        await firestore.collection('users/uid-1/deletions').doc('2026-05-06').get();
    expect(marker.data()!['syncedAt'], isA<Timestamp>());
  });

  test('one malformed remote day does not abort the pull of the others',
      () async {
    // `sync_mapper.dart`'s decoders throw rather than return null on a bad
    // shape (`dailyLogFromMap` splits and parses `date` directly). A single
    // bad document -- a partial write, a hand-edited console value, a field a
    // future app version wrote differently -- must cost ONE day, not the
    // whole run: an uncaught throw here aborts `syncNow()` before
    // `lastSyncedAt` advances, so every subsequent sync re-reads the same bad
    // document and dies at the same place, wedging sync permanently.
    await firestore.collection('users/uid-1/dailyLogs').doc('bad-doc').set({
      'date': 'not-a-date',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 8, 31).millisecondsSinceEpoch,
    });
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-31').set({
      'date': '2026-08-31',
      'flow': FlowIntensity.light.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 8, 31).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    // The good day landed...
    expect(await logs.getForDate(DateTime(2026, 8, 31)), isNotNull);
    // ...and the run completed rather than wedging on the bad one.
    expect((await SettingsRepository(db).get()).lastSyncedAt, isNotNull);
  });

  /// Makes the next write to `daily_logs` fail the way a real one can: this
  /// app opens a SECOND connection to the encrypted database from a
  /// background isolate (`CheckInWriter`), so a lock held past `busy_timeout`
  /// raises `SqliteException` on an ordinary insert. A trigger reproduces
  /// that precisely -- writes fail, reads keep working -- without needing a
  /// second isolate in the test.
  Future<void> breakDailyLogWrites() => db.customStatement(
        'CREATE TRIGGER simulated_lock BEFORE INSERT ON daily_logs '
        "BEGIN SELECT RAISE(ABORT, 'database is locked'); END;",
      );

  test('a database failure while applying a pull aborts the run, losing nothing',
      () async {
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-07-07').set({
      'date': '2026-07-07',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 7, 7).millisecondsSinceEpoch,
      'syncedAt': Timestamp.fromDate(DateTime.now()),
    });
    await breakDailyLogWrites();

    // Swallowing this would let the run COMPLETE: `lastSyncedAt` and the pull
    // cursor would both advance past a document that was never applied, and
    // the day would never be fetched again -- silent, permanent local data
    // loss, with nothing logged. Aborting is the self-healing outcome.
    await expectLater(sync.syncNow(), throwsA(isA<Exception>()));

    // Nothing was committed, so the next run retries the same window.
    expect((await SettingsRepository(db).get()).lastSyncedAt, isNull);
    final cursorDoc = await firestore.doc('users/uid-1/devices/device-1').get();
    expect(cursorDoc.exists, isFalse);
  });

  test('a failed tombstone restore keeps the tombstone so the day is retried',
      () async {
    final day = DateTime(2026, 7, 8);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow(); // a remote copy exists

    await logs.deleteForDate(day); // local delete + tombstone

    // A peer's edit, newer than the deletion: the tombstone LOSES, so
    // `_pushTombstones` must restore the day locally instead of deleting it.
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-07-08').set({
      'date': '2026-07-08',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      'syncedAt': Timestamp.fromDate(DateTime.now()),
    });
    await breakDailyLogWrites();

    await expectLater(sync.syncNow(), throwsA(isA<Exception>()));

    // Clearing the tombstone BEFORE the restore and then failing would leave
    // this device with no row, no tombstone, and a remote document it has
    // stopped asking about: the day is gone here permanently, with no retry
    // path. Restoring first means a failure leaves the tombstone standing.
    expect(await logs.getTombstones(), hasLength(1));
  });

  test(
      '_pushTombstones writes the tombstone\'s real deletedAt into the '
      'marker', () async {
    final day = DateTime(2026, 8, 30);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();

    await logs.deleteForDate(day);
    // Force (and capture) the tombstone's ACTUAL deletedAt -- see
    // `forceTombstoneWins` -- so the deletion definitely wins.
    final forcedDeletedAt = await forceTombstoneWins(day);

    await sync.syncNow();

    final markerDoc = await firestore
        .collection('users/uid-1/deletions')
        .doc('2026-08-30')
        .get();
    // Deliberately does not go through `bumpMarkerForward` (which overwrites
    // the value AFTER the fact) -- this asserts the value `_pushTombstones`
    // itself wrote from the tombstone, proving more than just "some marker
    // exists". The expectation is the tombstone's PERSISTED `deletedAt` (see
    // `forceTombstoneWins`): drift stores DateTimes at whole-second
    // resolution, so that -- not the pre-write in-memory value -- is the
    // tombstone's real `deletedAt`, and it must reach the marker unchanged
    // because every merge decision on the pull side is made against it.
    expect(markerDoc.data()!['deletedAt'], forcedDeletedAt.millisecondsSinceEpoch);
    // And it is the tombstone's own field, NOT the server-stamped `syncedAt`
    // (which is a Timestamp, and answers a different question: when the write
    // reached the server, used only to scope peers' pull queries).
    expect(markerDoc.data()!['syncedAt'], isA<Timestamp>());
  });

  test('an exact tie between a tombstone and a remote edit keeps the remote day',
      () async {
    final day = DateTime(2026, 9, 1);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();

    final remoteBefore = await remoteDay('2026-09-01');
    final tiedAt =
        DateTime.fromMillisecondsSinceEpoch(remoteBefore!['updatedAt'] as int);

    // Simulate a LOCAL deletion whose tombstone.deletedAt is EXACTLY tied
    // with the remote doc's updatedAt -- a genuine, reachable tie (this
    // file's own suite has hit same-millisecond timestamps in practice),
    // constructed directly since `DailyLogRepository.deleteForDate` cannot
    // be handed an explicit timestamp.
    await logs.deleteForDate(day);
    await (db.update(db.syncTombstones)..where((t) => t.date.equals(day)))
        .write(SyncTombstonesCompanion(deletedAt: Value(tiedAt)));

    await sync.syncNow();

    // The tie resolves the SAME way `_pullDeletions` resolves an exact
    // `local.updatedAt == deletedAt` tie (see the test below): the edit
    // wins, not the deletion. `_pushTombstones` used to disagree (`isAfter`
    // gave a tie to the deletion); this is the fix.
    expect(await remoteDay('2026-09-01'), isNotNull);
    expect(await logs.getForDate(day), isNotNull);
    expect(await logs.getTombstones(), isEmpty);
  });

  test(
      'an exact tie between a local row and a deletion marker keeps the '
      'local row', () async {
    final day = DateTime(2026, 9, 2);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();

    final local = await logs.getForDate(day);
    final tiedAt = local!.updatedAt;

    // The mirror-image of the push-side tie test above: a marker whose
    // deletedAt is EXACTLY tied with the local row's own updatedAt. Both
    // paths must resolve an exact tie the SAME way.
    await firestore.collection('users/uid-1/deletions').doc('2026-09-02').set({
      'date': '2026-09-02',
      'deletedAt': tiedAt.millisecondsSinceEpoch,
      'syncedAt':
          Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
    });

    await sync.syncNow();

    // Row IDENTITY, not just presence: asserting `getForDate(day) != null`
    // proves nothing here, because if the tie went the other way the row
    // would be deleted and then immediately RE-INSERTED by `_pullLogs` from
    // the remote document that is still there -- a different row, same day.
    // The surviving row must be the original one, never deleted at all.
    final survivor = await logs.getForDate(day);
    expect(survivor, isNotNull);
    expect(survivor!.id, local.id);
    // And the marker is gone, so the tie is not re-litigated every sync.
    final markerDoc = await firestore
        .collection('users/uid-1/deletions')
        .doc('2026-09-02')
        .get();
    expect(markerDoc.exists, isFalse);
  });

  test(
      'a peer edit newer than the resurrected day is not clobbered by the '
      'resurrect path', () async {
    // Device A deletes day X at t1. Device C edits X at t2 > t1 and pushes,
    // recreating the document. THIS device holds a local row at t3, with
    // t1 < t3 < t2 -- newer than the deletion, older than C's edit.
    //
    // Stamping `updatedAt = now()` to force a re-push (the previous round's
    // mechanism) makes this row look like t4 > t2: `_pullLogs`, later in this
    // same run, then keeps the STALE local content and `_pushLogs` re-pushes
    // it over C's newer edit. Buying a push by inflating the merge-decision
    // field destroys real data.
    final day = DateTime(2026, 6, 6);
    final deletedAt = DateTime(2026, 6, 6, 10); // t1
    final localEdit = DateTime(2026, 6, 6, 11); // t3
    final peerEdit = DateTime(2026, 6, 6, 12); // t2

    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: day,
          flow: const Value(FlowIntensity.light),
          updatedAt: Value(localEdit),
        ));

    // C's edit is what the remote document currently holds.
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-06-06').set({
      'date': '2026-06-06',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': peerEdit.millisecondsSinceEpoch,
      'syncedAt': Timestamp.fromDate(DateTime.now()),
    });
    // A's older deletion marker.
    await firestore.collection('users/uid-1/deletions').doc('2026-06-06').set({
      'date': '2026-06-06',
      'deletedAt': deletedAt.millisecondsSinceEpoch,
      'syncedAt': Timestamp.fromDate(DateTime.now()),
    });

    await sync.syncNow();

    // Whole-day last-write-wins, unchanged by the resurrect path: C's edit is
    // the newest version of the day, so it must survive remotely AND win
    // locally.
    expect((await remoteDay('2026-06-06'))!['flow'], FlowIntensity.heavy.index);
    expect((await logs.getForDate(day))!.flow, FlowIntensity.heavy);
  });

  test('a deleted day is removed remotely and the tombstone is cleared',
      () async {
    final day = DateTime(2026, 8, 12);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();
    expect(await remoteDay('2026-08-12'), isNotNull);

    await logs.deleteForDate(day);
    await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
    await sync.syncNow();

    expect(await remoteDay('2026-08-12'), isNull);
    expect(await logs.getTombstones(), isEmpty);
  });

  test('a remote edit newer than the deletion survives and returns locally',
      () async {
    final day = DateTime(2026, 8, 20);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow(); // pushes the day so a remote copy exists

    await logs.deleteForDate(day); // local delete + tombstone, deletedAt ~ now

    // Another device edits the SAME day after our deletion.
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-20').set({
      'date': '2026-08-20',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    // Whole-day last-write-wins: the remote edit is newer than the
    // deletion, so it wins -- the doc must NOT be deleted remotely, and the
    // day must come back locally via the normal pull.
    expect(await remoteDay('2026-08-20'), isNotNull);
    final local = await logs.getForDate(day);
    expect(local, isNotNull);
    expect(local!.flow, FlowIntensity.heavy);
    expect(await logs.getTombstones(), isEmpty);
  });

  test('a deletion newer than the remote edit deletes the remote day',
      () async {
    final day = DateTime(2026, 8, 21);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow(); // remote doc's updatedAt is from this push

    await logs.deleteForDate(day); // deletedAt is AFTER the remote doc's updatedAt
    await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
    await sync.syncNow();

    expect(await remoteDay('2026-08-21'), isNull);
    expect(await logs.getForDate(day), isNull);
    expect(await logs.getTombstones(), isEmpty);
  });

  test('a deleted day is not resurrected by the next pull', () async {
    final day = DateTime(2026, 8, 13);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();
    await logs.deleteForDate(day);
    await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
    await sync.syncNow();

    await sync.syncNow(); // a second pull must not bring it back

    expect(await logs.getForDate(day), isNull);
  });

  test('lastSyncedAt advances after a successful run', () async {
    final settings = SettingsRepository(db);
    expect((await settings.get()).lastSyncedAt, isNull);

    await logs.upsert(
      date: DateTime(2026, 8, 14),
      flow: FlowIntensity.light,
      symptomsJson: '{}',
    );
    await sync.syncNow();

    expect((await settings.get()).lastSyncedAt, isNotNull);
  });

  test(
      'a write landing during a run is still pushed on the next sync '
      '(lastSyncedAt is stamped at the run\'s START, not its end)', () async {
    // Drift persists DateTime columns as whole unix SECONDS, so the run's
    // start and its end are INDISTINGUISHABLE once stored unless the run
    // actually spans a second boundary -- which is why seeding a row an hour
    // ahead of `lastSyncedAt` (the previous version of this test) passed
    // whichever of the two values was stamped, and therefore tested nothing.
    //
    // A `LazyDatabase` whose factory sleeps makes the FIRST database access
    // inside `syncNow()` -- the settings read, which happens after the run
    // captures its start time -- take two seconds, deterministically. The row
    // below then sits 200ms after the run's start and at least a full second
    // before its end, so it lands on the correct side of one stamp and the
    // wrong side of the other, no matter where in the second the run began.
    final slowDb = AppDatabase.forTesting(LazyDatabase(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      return NativeDatabase.memory();
    }));
    addTearDown(slowDb.close);
    final slowSync = SyncService(
      db: slowDb,
      firestore: firestore,
      uid: 'uid-1',
      deviceId: 'device-slow',
    );

    final before = DateTime.now();
    await slowSync.syncNow(); // starts at `before`, ends >= before + 2s

    final day = DateTime(2026, 8, 29);
    // Direct drift insert (not `logs.upsert()`, whose internal
    // `DateTime.now()` this test needs independence from) at exactly the
    // position a write landing DURING that run would occupy. Stamping
    // `lastSyncedAt` with a post-run `DateTime.now()` -- the bug this guards
    // against -- puts this row BELOW the high-water mark, so `_pushLogs`
    // skips it, and because the mark only ever advances it is skipped
    // FOREVER.
    await slowDb.into(slowDb.dailyLogs).insert(DailyLogsCompanion.insert(
          date: day,
          flow: const Value(FlowIntensity.heavy),
          updatedAt: Value(before.add(const Duration(milliseconds: 200))),
        ));

    await slowSync.syncNow(); // must push it, not skip it

    final remote = await remoteDay('2026-08-29');
    expect(remote, isNotNull);
    expect(remote!['flow'], FlowIntensity.heavy.index);
  });

  test(
      'a row whose updatedAt ties exactly with lastSyncedAt is still pushed '
      '(drift stores DateTimes at whole-second resolution)', () async {
    // Drift persists `DateTime` columns as whole unix SECONDS, so BOTH
    // `lastSyncedAt` and a row's `updatedAt` come back out of the database
    // truncated to the second. Every edit made in the same second the sync
    // run started therefore reads back EXACTLY EQUAL to `since` -- not
    // merely close to it. A strictly-greater push gate (`!isAfter(since)` ->
    // skip) drops those rows, and because `lastSyncedAt` only ever advances,
    // it drops them PERMANENTLY: the row is never pushed again, and if
    // another device later writes that day, the pull destroys the local edit
    // outright. Same failure mode as the `startedAt` fix, reached through
    // storage resolution rather than through a post-run clock read.
    //
    // The tie is constructed from the stored value itself rather than by
    // racing the clock, so this is deterministic rather than
    // timing-dependent.
    await sync.syncNow(); // establishes lastSyncedAt
    final since = (await SettingsRepository(db).get()).lastSyncedAt!;

    final day = DateTime(2026, 9, 3);
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: day,
          flow: const Value(FlowIntensity.heavy),
          updatedAt: Value(since), // the exact tie
        ));

    await sync.syncNow();

    final remote = await remoteDay('2026-09-03');
    expect(remote, isNotNull);
    expect(remote!['flow'], FlowIntensity.heavy.index);
  });

  test('one user cannot see another user\'s collection path', () async {
    await logs.upsert(
      date: DateTime(2026, 8, 15),
      flow: FlowIntensity.light,
      symptomsJson: '{}',
    );
    await sync.syncNow();

    final other =
        await firestore.collection('users/uid-2/dailyLogs').get();
    expect(other.docs, isEmpty);
  });

  test('syncs preference settings but never device-local ones', () async {
    final settings = SettingsRepository(db);
    await settings.update(const AppSettingsCompanion(
      defaultCycleLength: Value(31),
      weightUnit: Value('lb'),
      premium: Value(true),
      appLockEnabled: Value(true),
    ));

    await sync.syncNow();

    final doc =
        await firestore.doc('users/uid-1/settings/current').get();
    expect(doc.data()!['defaultCycleLength'], 31);
    expect(doc.data()!['weightUnit'], 'lb');
    // Device-local concerns must NOT travel: `premium` is an IAP entitlement
    // tied to a Play account, and app lock is a per-device security choice.
    expect(doc.data()!.containsKey('premium'), isFalse);
    expect(doc.data()!.containsKey('appLockEnabled'), isFalse);
  });

  test('pulls newer remote settings into the local row', () async {
    final settings = SettingsRepository(db);
    await firestore.doc('users/uid-1/settings/current').set({
      'mode': TrackingMode.track.index,
      'defaultCycleLength': 33,
      'defaultPeriodLength': 5,
      'themeMode': 'system',
      'language': 'en',
      'genderNeutralLanguage': false,
      'pregnancyStartDate': null,
      'trackingCategories': null,
      'weightUnit': 'lb',
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    final local = await settings.get();
    expect(local.defaultCycleLength, 33);
    expect(local.weightUnit, 'lb');
  });

  test('a newer remote settings document is not clobbered by a stale local push',
      () async {
    final settings = SettingsRepository(db);
    // Local edit: bumps settingsUpdatedAt to "now", enabling the push path.
    await settings.update(const AppSettingsCompanion(
      defaultCycleLength: Value(21),
    ));

    // A remote change from another device, strictly newer than the local edit.
    await firestore.doc('users/uid-1/settings/current').set({
      'mode': TrackingMode.track.index,
      'defaultCycleLength': 40,
      'defaultPeriodLength': 5,
      'themeMode': 'system',
      'language': 'en',
      'genderNeutralLanguage': false,
      'pregnancyStartDate': null,
      'trackingCategories': null,
      'weightUnit': null,
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    // (a) the local row took the remote's newer value.
    expect((await settings.get()).defaultCycleLength, 40);

    // (b) the remote document still holds the remote's value -- a blind push
    // of the pre-sync local row (21) would have clobbered it before the pull
    // ever got a chance to compare timestamps. This assertion is the one
    // that actually catches the bug: without it, the test can pass while the
    // remote document has already been destroyed.
    final doc = await firestore.doc('users/uid-1/settings/current').get();
    expect(doc.data()!['defaultCycleLength'], 40);
  });

  test('a newer local settings change survives and still reaches the remote',
      () async {
    final settings = SettingsRepository(db);
    // A remote document, older than the local edit that follows.
    await firestore.doc('users/uid-1/settings/current').set({
      'mode': TrackingMode.track.index,
      'defaultCycleLength': 22,
      'defaultPeriodLength': 5,
      'themeMode': 'system',
      'language': 'en',
      'genderNeutralLanguage': false,
      'pregnancyStartDate': null,
      'trackingCategories': null,
      'weightUnit': null,
      'updatedAt': DateTime(2020, 1, 1).millisecondsSinceEpoch,
    });

    await settings.update(const AppSettingsCompanion(
      defaultCycleLength: Value(19),
    ));

    await sync.syncNow();

    // Local keeps its own, genuinely newer value.
    expect((await settings.get()).defaultCycleLength, 19);

    // And it still reaches the remote -- proving the pull-before-push reorder
    // did not simply invert the bug so that local changes are the ones lost.
    final doc = await firestore.doc('users/uid-1/settings/current').get();
    expect(doc.data()!['defaultCycleLength'], 19);
  });

  test('a settings pull with missing/malformed fields applies what it can '
      'and does not abort sync', () async {
    final settings = SettingsRepository(db);
    await firestore.doc('users/uid-1/settings/current').set({
      // 'mode' is missing entirely.
      'defaultCycleLength': 35, // present and well-typed.
      // 'defaultPeriodLength' is missing entirely.
      'themeMode': 'dark', // present and well-typed.
      'language': 12345, // present but the WRONG type (should be a String).
      'genderNeutralLanguage': true, // present and well-typed.
      'pregnancyStartDate': null,
      'trackingCategories': null,
      'weightUnit': 'kg',
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    // Must complete without throwing -- a plain `as int`/`as String` cast on
    // a missing or malformed field would abort syncNow() here, and every
    // subsequent run, since lastSyncedAt would never advance to move past it.
    await sync.syncNow();

    final local = await settings.get();
    // Present, well-typed fields are applied.
    expect(local.defaultCycleLength, 35);
    expect(local.themeMode, 'dark');
    expect(local.genderNeutralLanguage, isTrue);
    expect(local.weightUnit, 'kg');
    // Missing or malformed fields leave the column at its existing
    // (default, since this is a fresh row) value instead of throwing.
    expect(local.mode, TrackingMode.track);
    expect(local.defaultPeriodLength, 5);
    expect(local.language, 'en');
    // Sync completed and advanced the high-water mark -- it did not wedge.
    expect(local.lastSyncedAt, isNotNull);
  });

  group('cross-device deletion propagation', () {
    // A second SyncService over a SECOND in-memory database, sharing the
    // outer test's fake Firestore and uid -- simulating a second physical
    // device signed into the same account.
    late AppDatabase dbB;
    late DailyLogRepository logsB;
    late SyncService syncB;

    setUp(() {
      dbB = AppDatabase.forTesting(NativeDatabase.memory());
      logsB = DailyLogRepository(dbB);
      syncB = SyncService(
        db: dbB,
        firestore: firestore,
        uid: 'uid-1',
        deviceId: 'device-2',
      );
    });

    tearDown(() => dbB.close());

    // This sandboxed test environment can execute an entire multi-step async
    // chain (upsert -> sync -> sync -> delete -> sync) fast enough that
    // consecutive `DateTime.now()` calls -- even ones separated by a real
    // `Future.delayed` -- land on the SAME millisecond; confirmed by
    // instrumenting `_pushTombstones`/`_pullDeletions` during development,
    // where a marker's `deletedAt` and the `since` cutoff used to query it
    // printed as literally identical timestamps despite an inserted delay. A
    // real multi-device scenario has a network round trip between devices
    // and would never tie like this, but the tests must not depend on
    // relative wall-clock ordering to prove it: a tie would make a strict
    // `isGreaterThan` cutoff query exclude a same-millisecond marker forever
    // (`since` only ever advances). So, exactly like the rest of this file
    // already does for "definitely newer"/"definitely older" remote writes
    // (e.g. `DateTime.now().add(const Duration(hours: 1))`), the marker's
    // fields are forced to an EXPLICIT offset after it's written via the
    // real push flow, rather than trusted to already be correctly ordered.
    // Both `deletedAt` (the merge-decision field) and `syncedAt` (the
    // query-scoping field, since the fix-round-3 `syncedAt` change) are
    // bumped, since a test using this helper wants the marker to both WIN
    // the merge decision and be FOUND by the pull query.
    Future<void> bumpMarkerForward(String docId) async {
      final ref = firestore.collection('users/uid-1/deletions').doc(docId);
      final marker = (await ref.get()).data()!;
      final forward = DateTime.now().add(const Duration(hours: 1));
      await ref.set({
        ...marker,
        'deletedAt': forward.millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(forward),
      });
    }

    test('deleting a day on device A removes it from device B', () async {
      final day = DateTime(2026, 8, 25);
      await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
      await sync.syncNow(); // A pushes the day

      await syncB.syncNow(); // B pulls it
      expect(await logsB.getForDate(day), isNotNull);

      await logs.deleteForDate(day); // A deletes locally
      await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
      await sync.syncNow(); // A pushes the tombstone -> writes a deletion marker
      // Force the marker unambiguously ahead of B's local row and its
      // `since` cutoff -- see the comment on `bumpMarkerForward`.
      await bumpMarkerForward('2026-08-25');

      await syncB.syncNow(); // B pulls the deletion

      expect(await logsB.getForDate(day), isNull);
    });

    test(
        'a local edit newer than the marker survives on B and the remote '
        'marker is removed', () async {
      final day = DateTime(2026, 8, 26);
      await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
      await sync.syncNow();
      await syncB.syncNow();
      final pulled = await logsB.getForDate(day);
      expect(pulled, isNotNull);

      await logs.deleteForDate(day); // A deletes...
      await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
      await sync.syncNow(); // ...and pushes the marker.

      // `deletedAt` (the merge-decision field) and `syncedAt` (the
      // query-scoping field) are independent since fix round 3, so each is
      // placed deterministically relative to B's own recorded `since`
      // without needing them to agree with each other:
      //  - `syncedAt` must be strictly AFTER `sinceB`, or B's pull query
      //    would never even fetch this marker.
      //  - `deletedAt` must be strictly BEFORE B's upcoming local edit, or
      //    the deletion would win the merge decision instead of the edit.
      // Deriving both from B's own recorded `since` (rather than a fresh
      // `DateTime.now()`) keeps this ordered correctly regardless of how
      // the sandboxed clock behaves.
      final sinceB = (await SettingsRepository(dbB).get()).lastSyncedAt!;
      final markerSyncedAt = sinceB.add(const Duration(hours: 1));
      final markerDeletedAt = sinceB.add(const Duration(minutes: 30));
      final markerRef =
          firestore.collection('users/uid-1/deletions').doc('2026-08-26');
      final marker = (await markerRef.get()).data()!;
      await markerRef.set({
        ...marker,
        'deletedAt': markerDeletedAt.millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(markerSyncedAt),
      });

      // B's edit is explicitly newer than the marker's `deletedAt` -- written
      // directly against drift (not through `logsB.upsert()`, whose internal
      // `DateTime.now()` is exactly the value this whole test works around)
      // so the "local edit is newer" side of this scenario is as
      // deterministic as the marker side above.
      await (dbB.update(dbB.dailyLogs)..where((t) => t.id.equals(pulled!.id)))
          .write(DailyLogsCompanion(
        flow: const Value(FlowIntensity.heavy),
        updatedAt: Value(markerDeletedAt.add(const Duration(minutes: 15))),
      ));

      await syncB.syncNow();

      // B's edit is newer than the marker: it wins, and the day survives.
      final local = await logsB.getForDate(day);
      expect(local, isNotNull);
      expect(local!.flow, FlowIntensity.heavy);

      // The remote marker is gone, so it doesn't keep resurfacing on future
      // syncs (of B, or of any other device, including A).
      final markerDoc = await firestore
          .collection('users/uid-1/deletions')
          .doc('2026-08-26')
          .get();
      expect(markerDoc.exists, isFalse);
    });

    test('pulling a deletion does not create a local tombstone on B',
        () async {
      final day = DateTime(2026, 8, 27);
      await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
      await sync.syncNow();
      await syncB.syncNow();

      await logs.deleteForDate(day);
      await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
      await sync.syncNow();
      await bumpMarkerForward('2026-08-27');

      await syncB.syncNow();

      expect(await logsB.getForDate(day), isNull);
      // The loop guard: applying a pulled deletion must NOT route through
      // DailyLogRepository.deleteForDate, which would record a fresh local
      // tombstone on B -- and THAT would get pushed right back out as a new
      // marker, on every device, forever.
      expect(await logsB.getTombstones(), isEmpty);
    });

    test(
        'a deletion marker older than the retention cutoff is pruned; a '
        'recent one is not', () async {
      // Pruning keys off `syncedAt` (fix round 3, Finding 4), not
      // `deletedAt` -- a foreign device's own clock is not trustworthy for
      // this device's retention cutoff, but the server-stamped write time is.
      //
      // The two fields are seeded with DIVERGENT, deliberately CROSSED
      // values: each marker is old by one field and recent by the other. If
      // both were seeded with the same instant (as they were before), the
      // test would pass just as happily against a prune that queried
      // `deletedAt`, and so would not test the thing it names.
      final old = DateTime.now().subtract(const Duration(days: 181));
      final recent = DateTime.now().subtract(const Duration(days: 10));

      // Pruned: its SERVER stamp is old, even though the deleting device
      // claims it happened 10 days ago.
      await firestore.collection('users/uid-1/deletions').doc('2026-01-01').set({
        'date': '2026-01-01',
        'deletedAt': recent.millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(old),
      });
      // Kept: it reached the server 10 days ago, whatever its own clock says.
      await firestore.collection('users/uid-1/deletions').doc('2026-07-25').set({
        'date': '2026-07-25',
        'deletedAt': old.millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(recent),
      });

      await sync.syncNow(); // prunes as part of the sync run

      final oldDoc = await firestore
          .collection('users/uid-1/deletions')
          .doc('2026-01-01')
          .get();
      final recentDoc = await firestore
          .collection('users/uid-1/deletions')
          .doc('2026-07-25')
          .get();
      expect(oldDoc.exists, isFalse);
      expect(recentDoc.exists, isTrue);
    });

    test('the deleting device recovers a day resurrected by a peer',
        () async {
      final day = DateTime(2026, 8, 28);
      await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
      await sync.syncNow();
      await syncB.syncNow();
      final pulled = await logsB.getForDate(day);
      expect(pulled, isNotNull);

      await logs.deleteForDate(day); // A deletes...
      await forceTombstoneWins(day); // see forceTombstoneWins's doc comment
      await sync.syncNow(); // ...and pushes the marker.

      final sinceB = (await SettingsRepository(dbB).get()).lastSyncedAt!;

      // Put B's row a full hour BELOW B's own push gate. This is the ordinary
      // state of any day B synced on an earlier run, and it is what makes this
      // test discriminate: `_pushLogs` skips a row whose `updatedAt` predates
      // `since`, so the ONLY thing that can put the day back on the server is
      // the resurrect path republishing it. Leaving the row at whatever the
      // clock happened to produce made it tie with `since` at drift's
      // whole-second resolution, so the ordinary push re-sent it anyway and
      // the test passed with the resurrect republish deleted entirely.
      await (dbB.update(dbB.dailyLogs)..where((t) => t.id.equals(pulled!.id)))
          .write(DailyLogsCompanion(
        updatedAt: Value(sinceB.subtract(const Duration(hours: 1))),
      ));

      // The marker's `deletedAt` sits BELOW that, so B's row still wins the
      // merge decision and the resurrect/local-wins branch fires; its
      // `syncedAt` sits ABOVE B's cursor, so B's pull query actually finds it.
      // The two fields are independent (fix round 3), so each is placed
      // directly rather than trusting relative real-clock ordering -- see the
      // note on `bumpMarkerForward` above.
      final markerRef =
          firestore.collection('users/uid-1/deletions').doc('2026-08-28');
      final marker = (await markerRef.get()).data()!;
      await markerRef.set({
        ...marker,
        'deletedAt':
            sinceB.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(sinceB.add(const Duration(hours: 1))),
      });

      // B resurrects: its row wins, the stale marker is deleted, and the day
      // is republished from the row as it stands -- WITHOUT touching
      // `updatedAt`, which is every device's merge-decision field and not a
      // lever for buying a push.
      await syncB.syncNow();

      // Force A's own `since` safely into the past, so its next query is
      // guaranteed to include B's fresh re-push regardless of how tightly
      // packed the two devices' real clocks land in this environment.
      await SettingsRepository(db).updateSyncState(
        const AppSettingsCompanion(lastSyncedAt: Value(null)),
      );

      await sync.syncNow(); // A's NEXT sync must recover the day.

      final backOnA = await logs.getForDate(day);
      expect(backOnA, isNotNull);
      expect(backOnA!.flow, FlowIntensity.medium);
    });
  });

  test('signing out does not wipe local data', () async {
    // Design spec §7.3: sign-out must never delete the device's logs — a user
    // switching accounts would otherwise lose everything.
    await logs.upsert(
      date: DateTime(2026, 8, 16),
      flow: FlowIntensity.light,
      symptomsJson: '{}',
    );
    await sync.syncNow();

    // Tearing sync down is all that happens on sign-out.
    expect(await logs.getAll(), hasLength(1));
  });
}
