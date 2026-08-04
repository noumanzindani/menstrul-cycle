// `show Value` avoids drift's Column/Table names colliding with flutter_test.
import 'package:drift/drift.dart' show Value;
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
    final since = DateTime.now().subtract(const Duration(days: 1));
    await SettingsRepository(db).updateSyncState(
      AppSettingsCompanion(lastSyncedAt: Value(since)),
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

    expect(await logs.getForDate(day), isNotNull);
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
    // A genuinely concurrent write landing WHILE syncNow() executes isn't
    // stageable in this environment: fake Firestore and drift both run
    // synchronously within the test's single execution context, with no
    // real threads. Falling back to the documented alternative: construct a
    // row whose updatedAt falls strictly after a completed run's OWN
    // startedAt -- exactly the position a write landing DURING that run
    // would occupy -- and assert the FOLLOWING run still pushes it.
    await sync.syncNow(); // establishes an initial lastSyncedAt

    final runStart = (await SettingsRepository(db).get()).lastSyncedAt!;

    final day = DateTime(2026, 8, 29);
    // Direct drift insert (not `logs.upsert()`, whose internal
    // `DateTime.now()` this test needs independence from) with `updatedAt`
    // fixed at a value strictly after `runStart` -- exactly the position a
    // write landing DURING that run would occupy. If `lastSyncedAt` had
    // instead been stamped with a `DateTime.now()` taken AFTER the run
    // finished (the bug this guards against), this row's updatedAt could
    // sit BELOW that later stamp and get skipped by `_pushLogs` forever.
    await db.into(db.dailyLogs).insert(DailyLogsCompanion.insert(
          date: day,
          flow: const Value(FlowIntensity.heavy),
          updatedAt: Value(runStart.add(const Duration(hours: 1))),
        ));

    await sync.syncNow(); // must push it, not skip it

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
      final old = DateTime.now().subtract(const Duration(days: 181));
      final recent = DateTime.now().subtract(const Duration(days: 10));

      await firestore.collection('users/uid-1/deletions').doc('2026-01-01').set({
        'date': '2026-01-01',
        'deletedAt': old.millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(old),
      });
      await firestore.collection('users/uid-1/deletions').doc('2026-07-25').set({
        'date': '2026-07-25',
        'deletedAt': recent.millisecondsSinceEpoch,
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

      // Force the marker's `deletedAt` safely BEFORE B's row's (unbumped)
      // updatedAt, so the resurrect/local-wins branch fires, and its
      // `syncedAt` safely AFTER B's own `since`, so B's pull query actually
      // finds the marker -- decoupled, deterministic control over the two
      // fields fix round 3 separated. See the note on `bumpMarkerForward`
      // above about why relative real-clock ordering cannot be trusted here.
      final sinceB = (await SettingsRepository(dbB).get()).lastSyncedAt!;
      final markerRef =
          firestore.collection('users/uid-1/deletions').doc('2026-08-28');
      final marker = (await markerRef.get()).data()!;
      await markerRef.set({
        ...marker,
        'deletedAt': pulled!.updatedAt
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
        'syncedAt': Timestamp.fromDate(sinceB.add(const Duration(hours: 1))),
      });

      // B resurrects: local wins (its row's updatedAt is after the
      // now-adjusted deletedAt), deletes the stale marker, bumps its row's
      // updatedAt to "now" (Finding 2's fix), and re-pushes. B's row was
      // ALREADY fully synced from its own earlier push above -- i.e. its
      // pre-bump `updatedAt` already sits at/below B's own `since` for this
      // very sync call -- which is exactly the condition Finding 2 guards:
      // without the updatedAt bump, `_pushLogs`'s own since-based gate would
      // see "nothing changed" and never re-push it, even though the remote
      // copy was just destroyed by A's tombstone and must be recreated.
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
