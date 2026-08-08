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

  /// Removes every row of [type]. Used by the product-change session, which is
  /// deleted rather than disabled when it ends — a session that is over should
  /// leave no row at all, so nothing can resurrect it.
  Future<void> deleteByType(ReminderType type) async {
    await (_db.delete(_db.reminders)..where((t) => t.type.equalsValue(type)))
        .go();
  }

  // --- Custom reminders (many rows of ReminderType.custom, each user-titled).
  // These use the dormant `title`/`recurrence` columns and, unlike the smart
  // reminders, are not one-per-type — so they have their own CRUD.

  Future<List<Reminder>> getCustom() => (_db.select(_db.reminders)
        ..where((t) => t.type.equalsValue(ReminderType.custom)))
      .get();

  Future<int> addCustom({
    required String title,
    required int hour,
    required int minute,
  }) =>
      _db.into(_db.reminders).insert(
            RemindersCompanion.insert(
              type: ReminderType.custom,
              hour: hour,
              minute: minute,
              enabled: const Value(true),
              title: Value(title),
              recurrence: const Value('daily'),
            ),
          );

  Future<void> updateCustom({
    required int id,
    required String title,
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    await (_db.update(_db.reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        title: Value(title),
        hour: Value(hour),
        minute: Value(minute),
        enabled: Value(enabled),
      ),
    );
  }

  Future<void> deleteCustom(int id) async {
    await (_db.delete(_db.reminders)..where((t) => t.id.equals(id))).go();
  }
}
