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
    MediaItems,
    AnalysisSessions,
    AnalysisMessages,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openDatabaseConnection());

  /// For unit tests: pass an in-memory or custom executor.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Seed the single settings row so reads never return null.
          await into(appSettings).insert(
            const AppSettingsCompanion(
              id: Value(0),
              // Explicit, exactly like the other two seed sites. This was the
              // LAST path still leaning on the column default, and leaning on
              // it is what forced the declared schema to disagree with every
              // database created before the light default -- see the note on
              // `themeMode` in tables.dart.
              themeMode: Value(kDefaultThemeMode),
            ),
          );
        },
        // Every branch is additive-only (one nullable column each), so existing
        // rows are preserved untouched and no backfill is needed:
        //   v1 → v2: pregnancy mode adds AppSettings.pregnancyStartDate.
        //   v2 → v3: customizable tracking adds AppSettings.trackingCategories.
        //   v3 → v4: weight tracking adds AppSettings.weightUnit.
        //   v4 → v5: sync adds the SyncTombstones table + AppSettings.lastSyncedAt.
        //   v5 → v6: the media timeline adds the MediaItems table.
        //   v6 → v7: photo descriptions add AppSettings.analysisConsentUid
        //            plus the two daily-cap columns.
        //   v7 → v8: the user profile adds AppSettings.dateOfBirth, heightCm,
        //            profileWeightKg and menarcheAge. All four read NULL for an
        //            existing user, which is correct — nobody has been asked.
        //   v10 → v11: persisted photo-analysis conversations add the
        //            AnalysisSessions and AnalysisMessages tables plus
        //            AppSettings.analysisConsentVersion.
        // Branches are independent `if (from < n)` checks, not else-if, so a
        // user upgrading straight from v1 runs all of them.
        //
        // v4→v5 and v5→v6 are the only branches that create a table rather than
        // adding a nullable column. Both are still additive: no existing row is
        // read, rewritten or backfilled.
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
          if (from < 6) {
            await m.createTable(mediaItems);
          }
          if (from < 7) {
            await m.addColumn(appSettings, appSettings.analysisConsentUid);
            await m.addColumn(appSettings, appSettings.analysisCountDay);
            await m.addColumn(appSettings, appSettings.analysisCountToday);
          }
          if (from < 8) {
            await m.addColumn(appSettings, appSettings.dateOfBirth);
            await m.addColumn(appSettings, appSettings.heightCm);
            await m.addColumn(appSettings, appSettings.profileWeightKg);
            await m.addColumn(appSettings, appSettings.menarcheAge);
          }
          if (from < 9) {
            await m.addColumn(appSettings, appSettings.contraceptionMethod);
            await m
                .addColumn(appSettings, appSettings.contraceptionStartDate);
            await m.addColumn(appSettings, appSettings.knownDiagnoses);
            await m.addColumn(appSettings, appSettings.breastfeeding);
            await m.addColumn(appSettings, appSettings.breastfeedingSince);
          }
          if (from < 10) {
            await m.addColumn(appSettings, appSettings.sexualHealthBaseline);
          }
          if (from < 11) {
            await m.createTable(analysisSessions);
            await m.createTable(analysisMessages);
            // `createTable` is idempotent -- drift emits CREATE TABLE IF NOT
            // EXISTS -- but `addColumn` is NOT, because SQLite has no
            // ADD COLUMN IF NOT EXISTS. A database whose PHYSICAL schema
            // already carries this column while its recorded user_version is
            // still below 11 therefore threw "duplicate column name:
            // analysis_consent_version" on EVERY open, leaving the app stuck
            // on the splash spinner with no way out and no error shown.
            //
            // That state is reachable by installing a v11 build, then
            // installing an older v10 build over it: drift stamps
            // user_version back down without dropping the column it no longer
            // knows about, so the next v11 install re-runs this branch against
            // a column that is already there. Device-found 2026-09-18 on a
            // real populated database; the guard below is what makes the step
            // survive it.
            if (!await _appSettingsHasColumn('analysis_consent_version')) {
              await m.addColumn(
                  appSettings, appSettings.analysisConsentVersion);
            }
          }
          if (from < 12) {
            // Reminders and Medications become syncable. Both keyed on
            // `autoIncrement` until now, which is a LOCAL rowid and therefore
            // no identity at all across devices -- hence `syncId`. Neither
            // carried a timestamp, so there was nothing for `decideMerge` to
            // compare -- hence `updatedAt`. Both nullable, both backfilled
            // lazily by the push, so this branch reads no existing row.
            for (final step in [
              ('reminders', 'sync_id', () => m.addColumn(reminders, reminders.syncId)),
              ('reminders', 'updated_at',
                  () => m.addColumn(reminders, reminders.updatedAt)),
              ('medications', 'sync_id',
                  () => m.addColumn(medications, medications.syncId)),
              ('medications', 'updated_at',
                  () => m.addColumn(medications, medications.updatedAt)),
            ]) {
              if (!await _tableHasColumn(step.$1, step.$2)) await step.$3();
            }
          }
          if (from < 13) {
            // How much the user says her cycle varies. Backfilled by NOBODY:
            // an upgrading user was never asked, and null is the only honest
            // answer -- `cycleVariabilityPriorFor(null)` yields no prior, so
            // she keeps exactly the predictions she already had until she
            // answers in Settings.
            if (!await _appSettingsHasColumn('cycle_regularity')) {
              await m.addColumn(appSettings, appSettings.cycleRegularity);
            }
          }
          if (from < 14) {
            // Pregnant now, or in the last three months. Backfilled by NOBODY,
            // for the same reason as `cycle_regularity`: an upgrading user was
            // never asked, and "no" would be a claim she never made.
            for (final (name, column) in [
              ('pregnancy_status', appSettings.pregnancyStatus),
              ('pregnancy_status_date', appSettings.pregnancyStatusDate),
            ]) {
              if (!await _appSettingsHasColumn(name)) {
                await m.addColumn(appSettings, column);
              }
            }
          }
        },
      );

  /// True when `app_settings` already has a column named [column].
  Future<bool> _appSettingsHasColumn(String column) =>
      _tableHasColumn('app_settings', column);

  /// True when [table] already has a column named [column].
  ///
  /// Keeps `onUpgrade`'s ADD COLUMN steps idempotent: `createTable` is, because
  /// drift emits CREATE TABLE IF NOT EXISTS, but `addColumn` is not, because
  /// SQLite has no ADD COLUMN IF NOT EXISTS.
  ///
  /// [table] is INTERPOLATED, because PRAGMA cannot take a bound parameter for
  /// its target. Every caller passes a literal, and the assert keeps it that
  /// way: an identifier reaching here from anywhere else would be a SQL
  /// injection, so the shape is checked rather than trusted.
  Future<bool> _tableHasColumn(String table, String column) async {
    assert(RegExp(r'^[a-z_]+$').hasMatch(table), 'unsafe table name: $table');
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  /// Wipes all LOCAL user data and resets settings to defaults.
  ///
  /// **This method alone does not make a wipe stick.** Logs also live in
  /// Firestore under `users/{uid}`, and this resets `lastSyncedAt` to null,
  /// which makes the next sync a FULL sweep: the entire cloud history is
  /// pulled straight back down onto the device. That refill is still exactly
  /// what happens if anything calls this without first closing the sync gate —
  /// `test/sync_service_test.dart` ("what a local 'delete all my data' does
  /// and does not do") pins it deliberately, as a characterisation of this
  /// method, not of the UI control.
  ///
  /// **Both callers now close that gate themselves**, and neither one is a
  /// cloud deletion:
  ///
  /// - Settings → "Delete all my data" (`settings_screen.dart`) wraps this in
  ///   `SyncTrigger.suspend()` + `resolveClaim(upload: false)` +
  ///   `clearLunaFirestoreCache()` + `resume()`. The device stays empty and
  ///   sync stays off for that account here until the user turns it back on;
  ///   the account keeps its cloud copy.
  /// - Settings → Account → "Request account deletion"
  ///   (`account_section.dart`) records `deletionRequests/{uid}`, which stops
  ///   sync in both directions from every device (`SyncService.syncNow`) and
  ///   queues the account for a purge after
  ///   `AccountDeletionService.graceWindow`.
  ///
  /// This method also does not touch Firestore's own on-device cache, which is
  /// unencrypted and holds the same health documents — see
  /// `clearLunaFirestoreCache` (`services/firestore_ref.dart`), which both
  /// callers invoke.
  Future<void> deleteAllData() async {
    await transaction(() async {
      await delete(dailyLogs).go();
      await delete(periodEntries).go();
      await delete(reminders).go();
      await delete(medications).go();
      await delete(appSettings).go();
      // A pending tombstone is a not-yet-pushed deletion intent for a day
      // that no longer exists locally. Leaving it here means the NEXT
      // account signed into on this device (a fresh account after a deletion
      // request, or simply signing in as someone else) would push a bogus
      // deletion marker under ITS OWN Firestore path the moment sync first
      // runs — a stale local record leaking into an account that never
      // tracked that day.
      //
      // TRADE-OFF, deliberately taken: this also discards the intent for the
      // SAME account. A user who deletes day X, does not sync, then taps
      // "delete all my data" loses the pending deletion — day X survives in
      // the cloud and the next full sweep restores it locally. Both halves
      // are pinned by tests: `sync_tombstone_test.dart` (the tombstones are
      // cleared) and `sync_service_test.dart` (the day comes back). A
      // cross-ACCOUNT leak of one user's deletion dates into another user's
      // Firestore subtree is judged worse than one lost deletion within the
      // same account, which the user can simply repeat.
      //
      // This wipe also resets `lastSyncedAt`/`settingsUpdatedAt` to null via
      // the fresh `appSettings` row below — see the note on `lastSyncedAt` in
      // this method's own doc comment for what that means for the next sync.
      await delete(syncTombstones).go();
      // Media rows AND their cached thumbnail blobs. The thumbnails are the
      // only decoded bodily imagery this database holds, so leaving them would
      // make "everything on this device is erased" false in the most visible
      // way possible.
      //
      // This clears the local replica only. The Storage objects and the
      // Firestore metadata documents are untouched, exactly as `dailyLogs`
      // leaves the cloud copy untouched — erasing those is the separate
      // account-deletion flow. Note the two things drift cannot reach and the
      // CALLERS must: the downloaded-media file cache (`MediaCache.clear()`,
      // which is plain file I/O and has no place inside a drift transaction)
      // and Firestore's own unencrypted on-device cache
      // (`clearLunaFirestoreCache`).
      await delete(mediaItems).go();
      // Saved conversations about photographs. Persisting transcripts was a
      // deliberate reversal of the original in-memory design, and this is one
      // of the four erasure paths that reversal owes — leaving them would make
      // "everything on this device is erased" false in the most sensitive way.
      // Messages first: they carry a foreign key (sessionId) to the row
      // deleted next.
      await delete(analysisMessages).go();
      await delete(analysisSessions).go();
      await into(appSettings).insert(AppSettingsCompanion(
        id: const Value(0),
        // Explicit, NOT left to the column default: that default is frozen
        // into a database when it is created, so an install predating the
        // light default would re-seed itself to 'system' here forever.
        themeMode: const Value(kDefaultThemeMode),
      ));
    });
  }

  /// Returns the single settings row, creating it if it somehow doesn't exist.
  Future<AppSetting> getSettings() async {
    final existing = await (select(appSettings)
          ..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    if (existing != null) return existing;
    await into(appSettings).insert(AppSettingsCompanion(
      id: const Value(0),
      // Explicit, NOT left to the column default: that default is frozen
      // into a database when it is created, so an install predating the
      // light default would re-seed itself to 'system' here forever.
      themeMode: const Value(kDefaultThemeMode),
    ));
    return (select(appSettings)..where((t) => t.id.equals(0))).getSingle();
  }
}
