import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/services/media_analysis.dart';

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

  group('pregnancy status', () {
    test('never asked reads as null, not "no"', () {
      expect(provider.pregnancyStatus, isNull);
      expect(provider.pregnancyStatusDate, isNull);
    });

    test('an answer and its date round-trip', () async {
      final when = DateTime(2026, 8, 10);
      await provider.setPregnancyStatus(kPregnancyBirth, date: when);
      expect(provider.pregnancyStatus, kPregnancyBirth);
      expect(provider.pregnancyStatusDate, when);
    });

    test('changing the answer replaces a stale date', () async {
      await provider.setPregnancyStatus(kPregnancyBirth,
          date: DateTime(2026, 8, 10));
      await provider.setPregnancyStatus(kPregnancyNone,
          date: DateTime(2026, 9, 1));
      expect(provider.pregnancyStatus, kPregnancyNone);
      expect(provider.pregnancyStatusDate, DateTime(2026, 9, 1));
    });

    test('clearing the answer clears the date with it', () async {
      await provider.setPregnancyStatus(kPregnancyLoss,
          date: DateTime(2026, 8, 10));
      await provider.setPregnancyStatus(null);
      expect(provider.pregnancyStatus, isNull);
      expect(provider.pregnancyStatusDate, isNull);
    });
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

  group('analysis consent', () {
    test('is unset until the user opts in', () {
      expect(provider.analysisConsentUid, isNull);
      expect(provider.analysisConsentVersion, isNull);
    });

    test('setAnalysisConsent persists both the uid and the current version',
        () async {
      await provider.setAnalysisConsent('uid-1');

      expect(provider.analysisConsentUid, 'uid-1');
      expect(provider.analysisConsentVersion, kCurrentConsentVersion);
    });

    test('setAnalysisConsent can record an explicit version', () async {
      // Exercised by nothing in production today, but the parameter exists
      // precisely so a caller is never forced to claim consent to the
      // CURRENT disclosure when recording an older one.
      await provider.setAnalysisConsent('uid-1', version: 1);

      expect(provider.analysisConsentUid, 'uid-1');
      expect(provider.analysisConsentVersion, 1);
    });

    test('clearAnalysisConsent withdraws both the uid and the version',
        () async {
      await provider.setAnalysisConsent('uid-1');
      await provider.clearAnalysisConsent();

      expect(provider.analysisConsentUid, isNull);
      expect(provider.analysisConsentVersion, isNull);
    });

    // isAnalysisConsentedFor is what the Settings "Photo descriptions" toggle
    // reads, and it must mirror MediaAnalysisService.consented's own check
    // exactly (uid match AND current-version match) — a consent toggle that
    // disagrees with the real gate is a trust problem on a consent surface.
    group('isAnalysisConsentedFor', () {
      test('a v1 consenter reads as NOT consented', () async {
        await provider.setAnalysisConsent('uid-1', version: 1);
        expect(provider.isAnalysisConsentedFor('uid-1'), isFalse);
      });

      test('a v2 (current) consenter reads as consented', () async {
        await provider.setAnalysisConsent('uid-1');
        expect(provider.isAnalysisConsentedFor('uid-1'), isTrue);
      });

      test("another account's consent does not read as this account's",
          () async {
        await provider.setAnalysisConsent('uid-1');
        expect(provider.isAnalysisConsentedFor('uid-2'), isFalse);
      });

      test('a null uid (signed out) never reads as consented', () async {
        await provider.setAnalysisConsent('uid-1');
        expect(provider.isAnalysisConsentedFor(null), isFalse);
      });

      test('never consented reads as not consented', () {
        expect(provider.isAnalysisConsentedFor('uid-1'), isFalse);
      });
    });
  });
}
