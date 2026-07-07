import 'package:drift/drift.dart';

import '../db/database.dart';

/// CRUD for medications / birth control. The daily-reminder config rides in the
/// `schedule` column as JSON (see `MedicationSchedule`), so activating this
/// feature needs no schema migration.
class MedicationRepository {
  MedicationRepository(this._db);
  final AppDatabase _db;

  Future<List<Medication>> getAll() => _db.select(_db.medications).get();

  /// Inserts a medication and returns its new row id.
  Future<int> add({
    required String name,
    String? type,
    String? schedule,
    bool enabled = true,
  }) {
    return _db.into(_db.medications).insert(
          MedicationsCompanion.insert(
            name: name,
            type: Value(type),
            schedule: Value(schedule),
            enabled: Value(enabled),
          ),
        );
  }

  Future<void> update({
    required int id,
    required String name,
    String? type,
    String? schedule,
    required bool enabled,
  }) async {
    await (_db.update(_db.medications)..where((t) => t.id.equals(id))).write(
      MedicationsCompanion(
        name: Value(name),
        type: Value(type),
        schedule: Value(schedule),
        enabled: Value(enabled),
      ),
    );
  }

  Future<void> remove(int id) async {
    await (_db.delete(_db.medications)..where((t) => t.id.equals(id))).go();
  }
}
