import 'package:drift/drift.dart';

import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/enums.dart';

/// All reads/writes for daily logs. Days are keyed at local midnight, and the
/// `date` column is UNIQUE, so there is at most one log per day.
class DailyLogRepository {
  DailyLogRepository(this._db);
  final AppDatabase _db;

  Future<List<DailyLog>> getAll() => _db.select(_db.dailyLogs).get();

  Future<DailyLog?> getForDate(DateTime date) {
    final d = dateOnly(date);
    return (_db.select(_db.dailyLogs)..where((t) => t.date.equals(d)))
        .getSingleOrNull();
  }

  /// Insert or update the single log for [date].
  Future<void> upsert({
    required DateTime date,
    FlowIntensity? flow,
    required String symptomsJson,
    String? mood,
    String? notes,
  }) async {
    final d = dateOnly(date);
    final existing = await getForDate(d);
    if (existing == null) {
      await _db.into(_db.dailyLogs).insert(
            DailyLogsCompanion.insert(
              date: d,
              flow: Value(flow),
              symptoms: Value(symptomsJson),
              mood: Value(mood),
              notes: Value(notes),
            ),
          );
    } else {
      await (_db.update(_db.dailyLogs)..where((t) => t.id.equals(existing.id)))
          .write(
        DailyLogsCompanion(
          flow: Value(flow),
          symptoms: Value(symptomsJson),
          mood: Value(mood),
          notes: Value(notes),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<void> deleteForDate(DateTime date) async {
    final d = dateOnly(date);
    await (_db.delete(_db.dailyLogs)..where((t) => t.date.equals(d))).go();
  }
}
