import 'package:drift/drift.dart';

import '../models/enums.dart';
import 'connection.dart';
import 'tables.dart';

part 'database.g.dart';

/// The app's single on-device database. All health data lives here and never
/// leaves the device.
@DriftDatabase(
  tables: [
    PeriodEntries,
    DailyLogs,
    Reminders,
    Medications,
    AppSettings,
    SyncTombstones,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openDatabaseConnection());

  /// For unit tests: pass an in-memory or custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Seed the single settings row so reads never return null.
          await into(appSettings).insert(
            const AppSettingsCompanion(id: Value(0)),
          );
        },
        // Every branch is additive-only (one nullable column each), so existing
        // rows are preserved untouched and no backfill is needed:
        //   v1 → v2: pregnancy mode adds AppSettings.pregnancyStartDate.
        //   v2 → v3: customizable tracking adds AppSettings.trackingCategories.
        //   v3 → v4: weight tracking adds AppSettings.weightUnit.
        //   v4 → v5: sync adds the SyncTombstones table + AppSettings.lastSyncedAt.
        // Branches are independent `if (from < n)` checks, not else-if, so a
        // user upgrading straight from v1 runs all of them.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(appSettings, appSettings.pregnancyStartDate);
          }
          if (from < 3) {
            await m.addColumn(appSettings, appSettings.trackingCategories);
          }
          if (from < 4) {
            await m.addColumn(appSettings, appSettings.weightUnit);
          }
          if (from < 5) {
            await m.createTable(syncTombstones);
            await m.addColumn(appSettings, appSettings.lastSyncedAt);
            await m.addColumn(appSettings, appSettings.settingsUpdatedAt);
          }
        },
      );

  /// Wipes all LOCAL user data and resets settings to defaults.
  ///
  /// This is NOT the full right-to-erasure path any more — logs also live in
  /// Firestore under `users/{uid}`. Erasure means
  /// `AccountDeletionService.deleteFirestoreData()` AND this. The in-app
  /// "delete all my data" control clears the device; "Delete account"
  /// (Settings → Account) does both.
  Future<void> deleteAllData() async {
    await transaction(() async {
      await delete(dailyLogs).go();
      await delete(periodEntries).go();
      await delete(reminders).go();
      await delete(medications).go();
      await delete(appSettings).go();
      // A pending tombstone is a not-yet-pushed deletion intent for a day
      // that no longer exists locally. Leaving it here means the NEXT
      // account signed into on this device (a fresh account after "delete
      // account", or simply signing in as someone else) would push a bogus
      // deletion marker under ITS OWN Firestore path the moment sync first
      // runs — a stale local record leaking into an account that never
      // tracked that day. This wipe also resets `lastSyncedAt`/
      // `settingsUpdatedAt` to null via the fresh `appSettings` row below,
      // which is what makes "delete account" not leave a stale sync
      // high-water mark behind either.
      await delete(syncTombstones).go();
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
