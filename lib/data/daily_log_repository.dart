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

  /// Insert or update the single log for [date]. [bbt]/[opk] carry the
  /// symptothermal fields (basal temperature and ovulation-test result).
  Future<void> upsert({
    required DateTime date,
    FlowIntensity? flow,
    required String symptomsJson,
    String? mood,
    String? notes,
    double? bbt,
    String? opk,
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
              bbt: Value(bbt),
              opk: Value(opk),
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
          bbt: Value(bbt),
          opk: Value(opk),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Non-destructively records a basal temperature for [date], used by the
  /// Health Connect / HealthKit import. Unlike [upsert] (which rewrites the
  /// whole row), this touches ONLY the `bbt` column, so a day's flow/symptoms
  /// survive. It never overwrites a value already present — a hand-entered BBT
  /// always wins over an imported one. Returns true if a value was written,
  /// false if the day already had a BBT and was left untouched.
  Future<bool> setBbtIfEmpty({
    required DateTime date,
    required double bbt,
  }) async {
    final d = dateOnly(date);
    final existing = await getForDate(d);
    if (existing == null) {
      await _db.into(_db.dailyLogs).insert(
            DailyLogsCompanion.insert(date: d, bbt: Value(bbt)),
          );
      return true;
    }
    if (existing.bbt != null) return false; // respect the user's own reading
    await (_db.update(_db.dailyLogs)..where((t) => t.id.equals(existing.id)))
        .write(DailyLogsCompanion(
      bbt: Value(bbt),
      updatedAt: Value(DateTime.now()),
    ));
    return true;
  }

  Future<void> deleteForDate(DateTime date) async {
    final d = dateOnly(date);
    await (_db.delete(_db.dailyLogs)..where((t) => t.date.equals(d))).go();
  }
}
