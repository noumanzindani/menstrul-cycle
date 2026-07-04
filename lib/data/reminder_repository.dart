import 'package:drift/drift.dart';

import '../db/database.dart';
import '../models/enums.dart';

/// Reads/writes reminder rows. v1 uses one row per smart-reminder type
/// (periodSoon / fertileWindow / logNudge).
class ReminderRepository {
  ReminderRepository(this._db);
  final AppDatabase _db;

  Future<List<Reminder>> getAll() => _db.select(_db.reminders).get();

  Future<Reminder?> getByType(ReminderType type) =>
      (_db.select(_db.reminders)..where((t) => t.type.equalsValue(type)))
          .getSingleOrNull();

  Future<void> upsert({
    required ReminderType type,
    required bool enabled,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    final existing = await getByType(type);
    if (existing == null) {
      await _db.into(_db.reminders).insert(
            RemindersCompanion.insert(
              type: type,
              hour: hour,
              minute: minute,
              enabled: Value(enabled),
              payload: Value(payload),
            ),
          );
    } else {
      await (_db.update(_db.reminders)..where((t) => t.id.equals(existing.id)))
          .write(
        RemindersCompanion(
          enabled: Value(enabled),
          hour: Value(hour),
          minute: Value(minute),
          payload: Value(payload),
        ),
      );
    }
  }
}
