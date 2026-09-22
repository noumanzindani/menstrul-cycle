import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/sync_service.dart';

/// `cycleRegularity` joins the settings document, and the `profileFields`
/// marker moves to 4 to say so.
///
/// The marker is the whole defence and the reason it is a VERSION rather than
/// a flag: a device on the previous build writes `3` perfectly truthfully — it
/// really does know every field up to the sexual baseline — while having never
/// heard of this column. A reader that treated "marker present" as "knows
/// everything" would let that device wipe an answer it was simply too old to
/// carry. Each generation gates on its OWN minimum.
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

  test('the answer is pushed, and the marker says this writer knows it',
      () async {
    await settings.update(
      const AppSettingsCompanion(cycleRegularity: Value(kRegularityRoughly)),
    );

    await sync.syncNow();

    final remote = await remoteSettings();
    expect(remote!['cycleRegularity'], kRegularityRoughly);
    expect(remote['profileFields'], greaterThanOrEqualTo(4),
        reason: 'a reader has no other way to tell this writer knew the '
            'column from one that had never heard of it');
  });

  test('a document from a writer that knows the column applies it', () async {
    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 4,
          'cycleRegularity': kRegularityIrregular,
        }));

    await sync.syncNow();

    expect((await settings.get()).cycleRegularity, kRegularityIrregular);
  });

  test('a document from the PREVIOUS generation cannot wipe the answer',
      () async {
    await settings.update(
      const AppSettingsCompanion(cycleRegularity: Value(kRegularityVeryRegular)),
    );

    // Marker 3: truthful for a build that shipped before this column existed.
    // It carries no `cycleRegularity` key at all, which is indistinguishable
    // from "the user cleared it" without the version.
    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 3,
        }));

    await sync.syncNow();

    expect((await settings.get()).cycleRegularity, kRegularityVeryRegular,
        reason: 'an older writer wiped an answer it never knew about');
  });

  test('a writer that knows the column CAN clear it', () async {
    await settings.update(
      const AppSettingsCompanion(cycleRegularity: Value(kRegularityIrregular)),
    );

    await firestore.doc('users/uid-1/settings/current').set(remoteDoc({
          'profileFields': 4,
          'cycleRegularity': null,
        }));

    await sync.syncNow();

    expect((await settings.get()).cycleRegularity, isNull,
        reason: 'a current writer saying null means the user really did clear '
            'it, which is the whole point of distinguishing the two');
  });
}
