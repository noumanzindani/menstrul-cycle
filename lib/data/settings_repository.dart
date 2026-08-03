import 'package:drift/drift.dart';

import '../db/database.dart';

/// Reads/writes the single app-settings row (id = 0).
class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  Future<AppSetting> get() => _db.getSettings();

  /// Applies a user-facing settings change and stamps `settingsUpdatedAt` so
  /// sync can tell a locally edited preference from a stale one.
  Future<void> update(AppSettingsCompanion changes) async {
    await _db.getSettings(); // ensure the row exists
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(0))).write(
      changes.copyWith(settingsUpdatedAt: Value(DateTime.now())),
    );
  }

  /// Writes sync bookkeeping ONLY. Deliberately does NOT stamp
  /// `settingsUpdatedAt`: advancing the sync high-water mark is not a user
  /// edit, and stamping it would make every sync look like a settings change
  /// and push endlessly.
  Future<void> updateSyncState(AppSettingsCompanion changes) async {
    await _db.getSettings();
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(0)))
        .write(changes);
  }
}
