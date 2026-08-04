// `show Value` avoids drift's Column/Table names colliding with flutter_test.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
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

  test('a deleted day is removed remotely and the tombstone is cleared',
      () async {
    final day = DateTime(2026, 8, 12);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();
    expect(await remoteDay('2026-08-12'), isNotNull);

    await logs.deleteForDate(day);
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
    // `deletedAt` is forced to an EXPLICIT offset after it's written via the
    // real push flow, rather than trusted to already be correctly ordered.
    Future<void> bumpMarkerForward(String docId) async {
      final ref = firestore.collection('users/uid-1/deletions').doc(docId);
      final marker = (await ref.get()).data()!;
      await ref.set({
        ...marker,
        'deletedAt':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
    }

    test('deleting a day on device A removes it from device B', () async {
      final day = DateTime(2026, 8, 25);
      await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
      await sync.syncNow(); // A pushes the day

      await syncB.syncNow(); // B pulls it
      expect(await logsB.getForDate(day), isNotNull);

      await logs.deleteForDate(day); // A deletes locally
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
      await sync.syncNow(); // ...and pushes the marker.

      // Place the marker strictly BETWEEN B's `since` (captured moments ago,
      // during B's first sync above) and the local edit that follows -- by
      // deriving it from B's own recorded `since` rather than a fresh
      // `DateTime.now()`, this is ordered correctly regardless of how the
      // sandboxed clock behaves.
      final sinceB = (await SettingsRepository(dbB).get()).lastSyncedAt!;
      final markerDeletedAt = sinceB.add(const Duration(minutes: 30));
      final markerRef =
          firestore.collection('users/uid-1/deletions').doc('2026-08-26');
      final marker = (await markerRef.get()).data()!;
      await markerRef
          .set({...marker, 'deletedAt': markerDeletedAt.millisecondsSinceEpoch});

      // B's edit is explicitly newer than the marker -- written directly
      // against drift (not through `logsB.upsert()`, whose internal
      // `DateTime.now()` is exactly the value this whole test works around)
      // so the "local edit is newer" side of this scenario is as
      // deterministic as the marker side above.
      await (dbB.update(dbB.dailyLogs)..where((t) => t.id.equals(pulled!.id)))
          .write(DailyLogsCompanion(
        flow: const Value(FlowIntensity.heavy),
        updatedAt: Value(markerDeletedAt.add(const Duration(minutes: 30))),
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
      final oldMillis = DateTime.now()
          .subtract(const Duration(days: 181))
          .millisecondsSinceEpoch;
      final recentMillis = DateTime.now()
          .subtract(const Duration(days: 10))
          .millisecondsSinceEpoch;

      await firestore.collection('users/uid-1/deletions').doc('2026-01-01').set({
        'date': '2026-01-01',
        'deletedAt': oldMillis,
      });
      await firestore.collection('users/uid-1/deletions').doc('2026-07-25').set({
        'date': '2026-07-25',
        'deletedAt': recentMillis,
      });

      await sync.syncNow(); // prunes as part of the tombstone-push step

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
