import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

/// The one-tap check-in writes a confirmed no-bleeding day from a background
/// isolate. It must touch ONLY the `flow` column (never clobber symptoms/mood/
/// notes/bbt/opk the user logged), and must no-op when a flow of any kind is
/// already present — because a logged flow IS the "answered" flag, this makes
/// stale-notification and double-tap cases self-healing with no dedupe state.
void main() {
  group('DailyLogRepository.setFlowIfEmpty', () {
    late AppDatabase db;
    late DailyLogRepository repo;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = DailyLogRepository(db);
    });
    tearDown(() => db.close());

    test('creates a flow-only row when the day has no log', () async {
      final wrote = await repo.setFlowIfEmpty(
        date: DateTime(2026, 3, 1),
        flow: FlowIntensity.none,
      );
      expect(wrote, isTrue);
      final row = await repo.getForDate(DateTime(2026, 3, 1));
      expect(row?.flow, FlowIntensity.none);
    });

    test('fills an empty flow WITHOUT clobbering symptoms/mood/notes/bbt/opk',
        () async {
      await repo.upsert(
        date: DateTime(2026, 3, 2),
        // flow deliberately null: a day logged with everything BUT flow
        symptomsJson: '{"cramps":true}',
        mood: 'happy',
        notes: 'busy day',
        bbt: 36.6,
        opk: 'positive',
      );
      final wrote = await repo.setFlowIfEmpty(
        date: DateTime(2026, 3, 2),
        flow: FlowIntensity.none,
      );
      expect(wrote, isTrue);
      final row = await repo.getForDate(DateTime(2026, 3, 2));
      expect(row?.flow, FlowIntensity.none); // written
      expect(row?.symptoms, '{"cramps":true}'); // preserved
      expect(row?.mood, 'happy'); // preserved
      expect(row?.notes, 'busy day'); // preserved
      expect(row?.bbt, 36.6); // preserved
      expect(row?.opk, 'positive'); // preserved
    });

    test('no-ops when a flow is already present (stale/double-tap safe)',
        () async {
      await repo.upsert(
        date: DateTime(2026, 3, 3),
        flow: FlowIntensity.medium, // the user already logged bleeding
        symptomsJson: '{}',
      );
      final wrote = await repo.setFlowIfEmpty(
        date: DateTime(2026, 3, 3),
        flow: FlowIntensity.none,
      );
      expect(wrote, isFalse); // did not write
      final row = await repo.getForDate(DateTime(2026, 3, 3));
      expect(row?.flow, FlowIntensity.medium); // untouched
    });
  });
}
