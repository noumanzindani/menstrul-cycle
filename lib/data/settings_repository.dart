import '../db/database.dart';

/// Reads/writes the single app-settings row (id = 0).
class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  Future<AppSetting> get() => _db.getSettings();

  Future<void> update(AppSettingsCompanion changes) async {
    await _db.getSettings(); // ensure the row exists
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(0)))
        .write(changes);
  }
}
