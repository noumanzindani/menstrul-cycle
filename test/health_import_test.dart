import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/health_import_service.dart';

/// Importing temperature from Health Connect / HealthKit must be NON-destructive:
/// it fills only empty BBT days and never overwrites a value the user typed by
/// hand, nor clobbers the day's flow/symptoms/mood (the reason it can't reuse
/// the whole-row `upsert`).
void main() {
  group('DailyLogRepository.setBbtIfEmpty', () {
    late AppDatabase db;
    late DailyLogRepository repo;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DailyLogRepository(db);
    });
    tearDown(() => db.close());

    test('creates a bbt-only row when the day has no log', () async {
      final wrote = await repo.setBbtIfEmpty(date: DateTime(2026, 3, 1), bbt: 36.5);
      expect(wrote, isTrue);
      final row = await repo.getForDate(DateTime(2026, 3, 1));
      expect(row?.bbt, 36.5);
      expect(row?.flow, isNull);
    });

    test('fills an empty bbt WITHOUT clobbering existing flow/symptoms', () async {
      await repo.upsert(
        date: DateTime(2026, 3, 2),
        flow: FlowIntensity.medium,
        symptomsJson: '{"cramps":true}',
        mood: 'happy',
      );
      final wrote = await repo.setBbtIfEmpty(date: DateTime(2026, 3, 2), bbt: 36.6);
      expect(wrote, isTrue);
      final row = await repo.getForDate(DateTime(2026, 3, 2));
      expect(row?.bbt, 36.6);
      expect(row?.flow, FlowIntensity.medium); // preserved
      expect(row?.symptoms, '{"cramps":true}'); // preserved
      expect(row?.mood, 'happy'); // preserved
    });

    test('never overwrites a hand-entered bbt', () async {
      await repo.upsert(
        date: DateTime(2026, 3, 3),
        symptomsJson: '{}',
        bbt: 36.80, // the user's own reading
      );
      final wrote = await repo.setBbtIfEmpty(date: DateTime(2026, 3, 3), bbt: 36.5);
      expect(wrote, isFalse);
      final row = await repo.getForDate(DateTime(2026, 3, 3));
      expect(row?.bbt, 36.80); // untouched
    });
  });

  group('HealthImportService pure logic', () {
    test('earliestPerDay keeps the first reading of each day (waking BBT)', () {
      final samples = <TemperatureSample>[
        (time: DateTime(2026, 3, 1, 9, 30), celsius: 36.9), // later, ignore
        (time: DateTime(2026, 3, 1, 6, 15), celsius: 36.4), // earliest -> BBT
        (time: DateTime(2026, 3, 2, 7, 0), celsius: 36.6),
      ];
      final byDay = HealthImportService.earliestPerDay(samples);
      expect(byDay[DateTime(2026, 3, 1)], 36.4);
      expect(byDay[DateTime(2026, 3, 2)], 36.6);
      expect(byDay.length, 2);
    });

    test('applyTemperatureSamples fills empties and reports skips', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repo = DailyLogRepository(db);
      addTearDown(db.close);
      // Day 1 already has a manual reading -> must be skipped.
      await repo.upsert(date: DateTime(2026, 3, 1), symptomsJson: '{}', bbt: 36.7);

      final result = await HealthImportService.applyTemperatureSamples(
        samples: [
          (time: DateTime(2026, 3, 1, 6, 0), celsius: 36.2),
          (time: DateTime(2026, 3, 2, 6, 0), celsius: 36.5),
        ],
        repo: repo,
      );

      expect(result.imported, 1); // only day 2
      expect(result.skipped, 1); // day 1 was manual
      expect((await repo.getForDate(DateTime(2026, 3, 1)))?.bbt, 36.7); // kept
      expect((await repo.getForDate(DateTime(2026, 3, 2)))?.bbt, 36.5);
    });
  });
}
