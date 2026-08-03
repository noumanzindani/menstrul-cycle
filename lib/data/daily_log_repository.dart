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

  /// Records a confirmed flow for [date] without disturbing the rest of the row.
  /// Mirrors [setBbtIfEmpty]: it touches ONLY the `flow` column, so a day's
  /// symptoms/mood/notes/bbt/opk survive, and it never overwrites a flow already
  /// present. This is the write behind the one-tap check-in (both "Didn't start"
  /// and "Mark ended here" collapse to `FlowIntensity.none`): being single-column
  /// and atomic lets a background isolate write safely alongside the foreground
  /// UI, and the no-op-if-present rule makes stale-notification and double-tap
  /// answers self-healing — a logged flow of any kind IS the "answered" flag.
  /// Returns true if a value was written, false if the day already had a flow.
  Future<bool> setFlowIfEmpty({
    required DateTime date,
    required FlowIntensity flow,
  }) async {
    final d = dateOnly(date);
    final existing = await getForDate(d);
    if (existing == null) {
      await _db.into(_db.dailyLogs).insert(
            DailyLogsCompanion.insert(date: d, flow: Value(flow)),
          );
      return true;
    }
    if (existing.flow != null) return false; // the log is already the answer
    await (_db.update(_db.dailyLogs)..where((t) => t.id.equals(existing.id)))
        .write(DailyLogsCompanion(
      flow: Value(flow),
      updatedAt: Value(DateTime.now()),
    ));
    return true;
  }

  /// Deletes the log for [date] and records a tombstone in the SAME
  /// transaction. Without the tombstone a hard-deleted row is indistinguishable
  /// from one that never existed, and the next sync pull would resurrect it.
  Future<void> deleteForDate(DateTime date) async {
    final d = dateOnly(date);
    await _db.transaction(() async {
      await (_db.delete(_db.dailyLogs)..where((t) => t.date.equals(d))).go();
      // `date` is UNIQUE, so a repeat delete replaces rather than duplicates.
      final existing =
          await (_db.select(_db.syncTombstones)..where((t) => t.date.equals(d)))
              .getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.syncTombstones).insert(
              SyncTombstonesCompanion.insert(
                date: d,
                deletedAt: Value(DateTime.now()),
              ),
            );
      } else {
        await (_db.update(_db.syncTombstones)
              ..where((t) => t.date.equals(d)))
            .write(SyncTombstonesCompanion(
              deletedAt: Value(DateTime.now()),
            ));
      }
    });
  }

  /// Days deleted locally whose deletion has not yet reached Firestore.
  Future<List<SyncTombstone>> getTombstones() =>
      _db.select(_db.syncTombstones).get();

  /// Clears a tombstone after its remote document has been deleted.
  Future<void> clearTombstone(DateTime date) async {
    final d = dateOnly(date);
    await (_db.delete(_db.syncTombstones)..where((t) => t.date.equals(d))).go();
  }
}
