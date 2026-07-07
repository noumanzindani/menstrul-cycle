import 'package:drift/drift.dart';

import '../models/enums.dart';
import 'connection.dart';
import 'tables.dart';

part 'database.g.dart';

/// The app's single on-device database. All health data lives here and never
/// leaves the device.
@DriftDatabase(
  tables: [PeriodEntries, DailyLogs, Reminders, Medications, AppSettings],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openDatabaseConnection());

  /// For unit tests: pass an in-memory or custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Seed the single settings row so reads never return null.
          await into(appSettings).insert(
            const AppSettingsCompanion(id: Value(0)),
          );
        },
        // v1 → v2: pregnancy mode adds AppSettings.pregnancyStartDate. This is
        // the app's FIRST onUpgrade — additive only (one nullable column), so
        // existing rows are preserved untouched.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(appSettings, appSettings.pregnancyStartDate);
          }
        },
      );

  /// Wipes ALL user data and resets settings to defaults. Used by the
  /// in-app "delete all my data" control (no accounts, so this is the full
  /// right-to-erasure path).
  Future<void> deleteAllData() async {
    await transaction(() async {
      await delete(dailyLogs).go();
      await delete(periodEntries).go();
      await delete(reminders).go();
      await delete(medications).go();
      await delete(appSettings).go();
      await into(appSettings).insert(const AppSettingsCompanion(id: Value(0)));
    });
  }

  /// Returns the single settings row, creating it if it somehow doesn't exist.
  Future<AppSetting> getSettings() async {
    final existing = await (select(appSettings)
          ..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    if (existing != null) return existing;
    await into(appSettings).insert(const AppSettingsCompanion(id: Value(0)));
    return (select(appSettings)..where((t) => t.id.equals(0))).getSingle();
  }
}
