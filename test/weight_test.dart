import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/settings_provider.dart';

void main() {
  group('weight unit conversion', () {
    test('lb <-> kg round-trips within a rounding tolerance', () {
      expect(lbToKg(220), closeTo(99.79, 0.01));
      expect(kgToLb(100), closeTo(220.46, 0.01));
      expect(kgToLb(lbToKg(150)), closeTo(150, 0.001));
    });
  });

  group('parseWeightToKg', () {
    test('parses a kg value as-is', () {
      expect(parseWeightToKg('62.5', kWeightUnitKg), closeTo(62.5, 0.001));
    });

    test('converts a lb value to canonical kg', () {
      expect(parseWeightToKg('150', kWeightUnitLb), closeTo(68.04, 0.01));
    });

    test('returns null for blank or unparseable input', () {
      expect(parseWeightToKg('', kWeightUnitKg), isNull);
      expect(parseWeightToKg('   ', kWeightUnitKg), isNull);
      expect(parseWeightToKg('heavy', kWeightUnitKg), isNull);
    });

    test('refuses values outside 20-350 kg', () {
      expect(parseWeightToKg('19.9', kWeightUnitKg), isNull);
      expect(parseWeightToKg('350.1', kWeightUnitKg), isNull);
      expect(parseWeightToKg('0', kWeightUnitKg), isNull);
    });

    test('accepts the exact boundaries', () {
      expect(parseWeightToKg('20', kWeightUnitKg), closeTo(20, 0.001));
      expect(parseWeightToKg('350', kWeightUnitKg), closeTo(350, 0.001));
    });

    test('applies the range AFTER converting lb to kg', () {
      // 700 lb == 317.5 kg, inside the range despite the big number.
      expect(parseWeightToKg('700', kWeightUnitLb), closeTo(317.51, 0.01));
      // 800 lb == 362.8 kg, outside it.
      expect(parseWeightToKg('800', kWeightUnitLb), isNull);
    });
  });

  group('formatWeightFromKg', () {
    test('formats kg to one decimal, rounding', () {
      expect(formatWeightFromKg(62.58, kWeightUnitKg), '62.6');
      expect(formatWeightFromKg(62.44, kWeightUnitKg), '62.4');
    });

    test('rounds the STORED double, not the decimal literal', () {
      // 62.55 is held as 62.54999999999999715…, so one-decimal rounding goes
      // DOWN. Asserting '62.6' here would encode a decimal-half-up assumption
      // that IEEE-754 doubles never make. Do not "correct" this to 62.6.
      expect(formatWeightFromKg(62.55, kWeightUnitKg), '62.5');
    });

    test('formats kg as lb to one decimal', () {
      expect(formatWeightFromKg(68.04, kWeightUnitLb), '150.0');
    });
  });

  group('weight in the day-tags blob', () {
    test('round-trips as a JSON number under the weight key', () {
      final json = encodeDayTags(numbers: {kMetricWeight: 62.5});
      expect(decodeNumber(json, kMetricWeight), 62.5);
    });

    test('is not mistaken for a symptom flag', () {
      final json = encodeDayTags(
        flags: {'cramps'},
        numbers: {kMetricWeight: 62.5},
      );
      expect(decodeSymptoms(json), {'cramps'});
    });
  });

  group('SettingsProvider.weightUnit', () {
    late AppDatabase db;
    late SettingsProvider provider;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      provider = SettingsProvider(SettingsRepository(db));
      await provider.load();
    });

    tearDown(() => db.close());

    test('defaults to kg when never chosen', () {
      expect(provider.weightUnit, kWeightUnitKg);
    });

    test('persists a switch to lb', () async {
      await provider.setWeightUnit(kWeightUnitLb);
      expect(provider.weightUnit, kWeightUnitLb);

      final reloaded = SettingsProvider(SettingsRepository(db));
      await reloaded.load();
      expect(reloaded.weightUnit, kWeightUnitLb);
    });
  });
}
