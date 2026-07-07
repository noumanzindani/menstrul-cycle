import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/bbt_service.dart';

/// Symptothermal logging activates the dormant bbt/opk columns and adds a
/// non-diagnostic thermal-shift observation (used only for awareness — it never
/// feeds the guarded fertility band or claims contraceptive reliability).
void main() {
  DailyLog day(DateTime date, {double? bbt}) => DailyLog(
        id: 0,
        date: date,
        flow: null,
        symptoms: '{}',
        mood: null,
        notes: null,
        bbt: bbt,
        opk: null,
        createdAt: date,
        updatedAt: date,
      );

  group('BBT / OPK persistence', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('stores and reads a basal temperature and an OPK result', () async {
      final repo = DailyLogRepository(db);
      await repo.upsert(
        date: DateTime(2026, 3, 10),
        symptomsJson: '{}',
        bbt: 36.55,
        opk: 'positive',
      );
      final row = await repo.getForDate(DateTime(2026, 3, 10));
      expect(row?.bbt, 36.55);
      expect(row?.opk, 'positive');
    });
  });

  group('thermal-shift detection', () {
    final base = DateTime(2026, 3, 1);

    test('detects a sustained rise after the low phase', () {
      final logs = [
        for (var i = 0; i < 6; i++) day(base.add(Duration(days: i)), bbt: 36.4),
        for (var i = 6; i < 9; i++) day(base.add(Duration(days: i)), bbt: 36.7),
      ];
      expect(BbtService.thermalShift(logs), base.add(const Duration(days: 6)));
    });

    test('no shift for flat temperatures', () {
      final logs = [
        for (var i = 0; i < 12; i++) day(base.add(Duration(days: i)), bbt: 36.4),
      ];
      expect(BbtService.thermalShift(logs), isNull);
    });

    test('needs enough readings before claiming a shift', () {
      final logs = [
        for (var i = 0; i < 5; i++) day(base.add(Duration(days: i)), bbt: 36.4),
      ];
      expect(BbtService.thermalShift(logs), isNull);
    });

    test('a single spike is not a sustained shift', () {
      final logs = [
        for (var i = 0; i < 6; i++) day(base.add(Duration(days: i)), bbt: 36.4),
        day(base.add(const Duration(days: 6)), bbt: 36.8), // one high day
        day(base.add(const Duration(days: 7)), bbt: 36.4),
        day(base.add(const Duration(days: 8)), bbt: 36.4),
      ];
      expect(BbtService.thermalShift(logs), isNull);
    });
  });
}
