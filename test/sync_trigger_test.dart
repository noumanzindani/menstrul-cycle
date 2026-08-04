import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository logs;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = DailyLogRepository(db);
    firestore = FakeFirebaseFirestore();
  });

  tearDown(() => db.close());

  SyncTrigger trigger() => SyncTrigger(
        db,
        firestore: () => firestore,
        deviceId: () async => 'device-1',
      );

  Future<Map<String, dynamic>?> remoteDay(DateTime date) async {
    final id =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final doc =
        await firestore.collection('users/uid-1/dailyLogs').doc(id).get();
    return doc.data();
  }

  group('unclaimed local data (fresh account/device pairing)', () {
    test('setUser does NOT push pre-existing local logs before consent',
        () async {
      await logs.upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );

      await trigger().setUser('uid-1');

      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });

    test('resolveClaim(upload: true) pushes the deferred local logs',
        () async {
      await logs.upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: true);

      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
    });

    test(
        'resolveClaim(upload: false) leaves the data unpushed even after a '
        'later syncNow (e.g. an app resume or a new edit)', () async {
      await logs.upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );

      final t = trigger();
      await t.setUser('uid-1');
      await t.resolveClaim(upload: false);
      // Simulate the app-resume hook and/or a debounced write firing later
      // in the same session.
      await t.syncNow();
      await t.syncNow();

      expect(await remoteDay(DateTime(2026, 1, 5)), isNull);
    });
  });

  group('no unclaimed data — sync proceeds automatically', () {
    test('a fresh device with no local logs syncs (pulls remote data) right '
        'away, with no claim prompt needed', () async {
      await firestore.collection('users/uid-1/dailyLogs').doc('2026-01-05').set({
        'date': '2026-01-05',
        'flow': FlowIntensity.medium.index,
        'symptoms': <String, dynamic>{},
        'updatedAt': DateTime(2026, 1, 5).millisecondsSinceEpoch,
      });

      await trigger().setUser('uid-1');

      final local = await logs.getForDate(DateTime(2026, 1, 5));
      expect(local, isNotNull);
    });

    test('a device that has already synced before proceeds automatically '
        'even with local rows present', () async {
      await logs.upsert(
        date: DateTime(2026, 1, 5),
        flow: FlowIntensity.medium,
        symptomsJson: '{}',
      );
      await db.getSettings();
      await (db.update(db.appSettings)..where((t) => t.id.equals(0))).write(
        AppSettingsCompanion(lastSyncedAt: Value(DateTime(2026, 1, 1))),
      );

      await trigger().setUser('uid-1');

      expect(await remoteDay(DateTime(2026, 1, 5)), isNotNull);
    });
  });

  test('setUser does not throw when Firebase has not been initialized',
      () async {
    // No Firebase app exists in this test binary (task 1b -- the console
    // setup -- is deliberately deferred). The DEFAULT constructor (no
    // `firestore`/`deviceId` overrides) touches the real `lunaFirestore()`,
    // which throws in that state; the trigger must swallow it and leave sync
    // disabled rather than crashing the app, since `LunaTrackApp.build` calls
    // `setUser` on every signed-in rebuild, including in widget tests that
    // sign a fake user in with no Firebase app configured at all.
    final t = SyncTrigger(db);
    await t.setUser('uid-1');
    await t.syncNow();
  });
}
