import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/sync_service.dart';

/// `pregnancyStatus` and `pregnancyStatusDate` join the settings document, and
/// the `profileFields` marker moves to 5 to say so. Same defence as marker 4:
/// a previous-generation writer truthfully writes `4` and has never heard of
/// these columns, so it must not be able to wipe them.
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

  /// The shared shape of a settings document, minus whatever a test overrides.
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

  final birth = DateTime(2026, 8, 10);

  test('the answer is pushed, and the marker says this writer knows it',
      () async {
    await settings.update(AppSettingsCompanion(
      pregnancyStatus: const Value(kPregnancyBirth),
      pregnancyStatusDate: Value(birth),
    ));

    await sync.syncNow();

    final remote = await remoteSettings();
    expect(remote!['pregnancyStatus'], kPregnancyBirth);
    expect(remote['pregnancyStatusDate'], birth.millisecondsSinceEpoch);
    expect(remote['profileFields'], greaterThanOrEqualTo(5));
  });

  test('a document from a writer that knows the columns applies them',
      () async {
    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 5,
          'pregnancyStatus': kPregnancyLoss,
          'pregnancyStatusDate': birth.millisecondsSinceEpoch,
        }));

    await sync.syncNow();

    final local = await settings.get();
    expect(local.pregnancyStatus, kPregnancyLoss);
    expect(local.pregnancyStatusDate, birth);
  });

  test('a document from the PREVIOUS generation cannot wipe the answer',
      () async {
    await settings.update(AppSettingsCompanion(
      pregnancyStatus: const Value(kPregnancyNow),
      pregnancyStatusDate: Value(birth),
    ));

    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 4,
          'cycleRegularity': kRegularityRoughly,
        }));

    await sync.syncNow();

    final local = await settings.get();
    expect(local.pregnancyStatus, kPregnancyNow,
        reason: 'an older writer wiped an answer it never knew about');
    expect(local.pregnancyStatusDate, birth);
    expect(local.cycleRegularity, kRegularityRoughly,
        reason: 'marker 4 still applies the columns it does know');
  });

  test('a writer that knows the columns CAN clear them', () async {
    await settings.update(AppSettingsCompanion(
      pregnancyStatus: const Value(kPregnancyBirth),
      pregnancyStatusDate: Value(birth),
    ));

    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 5,
          'pregnancyStatus': null,
          'pregnancyStatusDate': null,
        }));

    await sync.syncNow();

    final local = await settings.get();
    expect(local.pregnancyStatus, isNull);
    expect(local.pregnancyStatusDate, isNull);
  });
}
