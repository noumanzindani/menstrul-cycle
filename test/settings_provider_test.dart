import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/settings_provider.dart';

void main() {
  late AppDatabase db;
  late SettingsProvider provider;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    provider = SettingsProvider(SettingsRepository(db));
    await provider.load();
  });
  tearDown(() => db.close());

  test('mode defaults to track', () {
    expect(provider.mode, TrackingMode.track);
  });

  test('setMode round-trips through the settings row', () async {
    await provider.setMode(TrackingMode.conceive);
    expect(provider.mode, TrackingMode.conceive);
  });

  group('profile fields', () {
    test('all four read null until the user answers', () {
      expect(provider.dateOfBirth, isNull);
      expect(provider.heightCm, isNull);
      expect(provider.profileWeightKg, isNull);
      expect(provider.menarcheAge, isNull);
    });

    test('each setter round-trips through the settings row', () async {
      await provider.setDateOfBirth(DateTime(1996, 4, 17));
      await provider.setHeightCm(168.5);
      await provider.setProfileWeightKg(61.2);
      await provider.setMenarcheAge(13);

      expect(provider.dateOfBirth, DateTime(1996, 4, 17));
      expect(provider.heightCm, 168.5);
      expect(provider.profileWeightKg, 61.2);
      expect(provider.menarcheAge, 13);
    });

    test('each setter clears its field when passed null', () async {
      await provider.setDateOfBirth(DateTime(1996, 4, 17));
      await provider.setHeightCm(168.5);
      await provider.setProfileWeightKg(61.2);
      await provider.setMenarcheAge(13);

      await provider.setDateOfBirth(null);
      await provider.setHeightCm(null);
      await provider.setProfileWeightKg(null);
      await provider.setMenarcheAge(null);

      expect(provider.dateOfBirth, isNull);
      expect(provider.heightCm, isNull);
      expect(provider.profileWeightKg, isNull);
      expect(provider.menarcheAge, isNull);
    });

    // These are user edits, so they must go through `update()` and stamp
    // `settingsUpdatedAt` — otherwise a sync cannot tell the locally entered
    // profile from a stale one and the newer value loses.
    test('setters stamp settingsUpdatedAt', () async {
      expect(provider.settings!.settingsUpdatedAt, isNull);

      await provider.setHeightCm(168.5);
      expect(provider.settings!.settingsUpdatedAt, isNotNull);
    });

    // The profile weight is a SEPARATE field from the per-day `weight` metric
    // that drives the 90-day trend chart. Writing one must never touch the
    // other, and it must not disturb the kg/lb display preference either.
    test('profile weight does not disturb the weight display unit', () async {
      await provider.setWeightUnit('lb');
      await provider.setProfileWeightKg(61.2);

      expect(provider.weightUnit, 'lb');
      expect(provider.profileWeightKg, 61.2);
    });
  });
}
