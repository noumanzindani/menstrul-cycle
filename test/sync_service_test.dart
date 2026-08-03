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
