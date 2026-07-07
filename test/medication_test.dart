import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/medication.dart';

/// Medication / birth-control tracking activates the previously dormant
/// Medications table. The reminder config rides in the existing `schedule`
/// column as JSON, so there is no schema migration.
void main() {
  group('MedicationSchedule', () {
    test('encodes and decodes a daily reminder time', () {
      const s = MedicationSchedule(hour: 8, minute: 30);
      final round = MedicationSchedule.decode(s.encode());
      expect(round, isNotNull);
      expect(round!.hour, 8);
      expect(round.minute, 30);
      expect(round.remind, isTrue);
    });

    test('decode returns null for a medication with no schedule', () {
      expect(MedicationSchedule.decode(null), isNull);
      expect(MedicationSchedule.decode(''), isNull);
    });

    test('a reminder can be switched off while keeping the time', () {
      const s = MedicationSchedule(hour: 21, minute: 0, remind: false);
      expect(MedicationSchedule.decode(s.encode())!.remind, isFalse);
    });
  });

  group('MedicationRepository', () {
    late AppDatabase db;
    late MedicationRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = MedicationRepository(db);
    });
    tearDown(() => db.close());

    test('adds a medication and reads it back', () async {
      final id = await repo.add(
        name: 'Iron supplement',
        type: MedicationType.supplement,
        schedule: const MedicationSchedule(hour: 9, minute: 0).encode(),
      );
      final all = await repo.getAll();
      expect(all, hasLength(1));
      expect(all.single.id, id);
      expect(all.single.name, 'Iron supplement');
      expect(all.single.type, MedicationType.supplement);
      expect(all.single.enabled, isTrue);
    });

    test('updates name, type, schedule and enabled', () async {
      final id = await repo.add(name: 'Pill', type: MedicationType.pill);
      await repo.update(
        id: id,
        name: 'Combined pill',
        type: MedicationType.pill,
        schedule: const MedicationSchedule(hour: 22, minute: 15).encode(),
        enabled: false,
      );
      final row = (await repo.getAll()).single;
      expect(row.name, 'Combined pill');
      expect(row.enabled, isFalse);
      expect(MedicationSchedule.decode(row.schedule)!.hour, 22);
    });

    test('removes a medication', () async {
      final id = await repo.add(name: 'Vitamin D', type: MedicationType.supplement);
      await repo.remove(id);
      expect(await repo.getAll(), isEmpty);
    });
  });
}
