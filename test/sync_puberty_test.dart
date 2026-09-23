import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/sync_service.dart';

/// The four puberty columns join the settings document under `profileFields`
/// marker 6. A marker-5 writer has never heard of them and must not wipe them.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeFirebaseFirestore firestore;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    firestore = FakeFirebaseFirestore();
    sync = SyncService(
      db: db,
      firestore: firestore,
      uid: 'uid-1',
      deviceId: 'device-1',
    );
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>?> remoteSettings() async =>
      (await firestore.doc('users/uid-1/settings/current').get()).data();

  Map<String, dynamic> remoteDoc(Map<String, dynamic> overrides) => {
        'mode': 0,
        'defaultCycleLength': 28,
        'defaultPeriodLength': 5,
        'themeMode': 'system',
        'language': 'en',
        'genderNeutralLanguage': false,
        'pregnancyStartDate': null,
        'trackingCategories': null,
        'weightUnit': null,
        'updatedAt':
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        ...overrides,
      };

  final on = DateTime(2026, 9, 1);

  Future<void> seedLocal() => settings.update(AppSettingsCompanion(
        breastStage: const Value('tan_b3'),
        pubicHairStage: const Value('tan_p2'),
        pubertyTiming: const Value('pub_early'),
        pubertyAnsweredOn: Value(on),
      ));

  test('the answers are pushed under marker 6', () async {
    await seedLocal();
    await sync.syncNow();

    final remote = await remoteSettings();
    expect(remote!['breastStage'], 'tan_b3');
    expect(remote['pubicHairStage'], 'tan_p2');
    expect(remote['pubertyTiming'], 'pub_early');
    expect(remote['pubertyAnsweredOn'], on.millisecondsSinceEpoch);
    expect(remote['profileFields'], greaterThanOrEqualTo(6));
  });

  test('a marker-6 document applies them', () async {
    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 6,
          'breastStage': 'tan_b5',
          'pubicHairStage': 'tan_p5',
          'pubertyTiming': 'pub_on_time',
          'pubertyAnsweredOn': on.millisecondsSinceEpoch,
        }));

    await sync.syncNow();

    final local = await settings.get();
    expect(local.breastStage, 'tan_b5');
    expect(local.pubicHairStage, 'tan_p5');
    expect(local.pubertyTiming, 'pub_on_time');
    expect(local.pubertyAnsweredOn, on);
  });

  test('a marker-5 document cannot wipe them', () async {
    await seedLocal();
    await firestore
        .doc('users/uid-1/settings/current')
        .set(remoteDoc({'profileFields': 5}));

    await sync.syncNow();

    final local = await settings.get();
    expect(local.breastStage, 'tan_b3',
        reason: 'an older writer wiped an answer it never knew about');
    expect(local.pubicHairStage, 'tan_p2');
    expect(local.pubertyTiming, 'pub_early');
    expect(local.pubertyAnsweredOn, on);
  });
}
