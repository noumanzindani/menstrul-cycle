import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/settings_provider.dart';

import 'generated_migrations/schema.dart';

/// The app opens LIGHT unless the user says otherwise.
///
/// Three separate surfaces decide that, and they are tested separately because
/// changing one without the others is what makes a "default" only half true:
/// the column default (what a fresh install stores), the getter's fallback
/// (what the first frames of EVERY launch paint, because `main.dart` calls
/// `..load()` fire-and-forget and the row is not read yet), and the explicit
/// 'system' answer, which must keep meaning "follow the OS".
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('a fresh install stores light, not system', () async {
    expect((await db.getSettings()).themeMode, 'light');
  });

  test('a fresh install resolves to ThemeMode.light', () async {
    final provider = SettingsProvider(SettingsRepository(db));
    await provider.load();
    expect(provider.themeMode, ThemeMode.light);
  });

  test('before load() resolves to light, so no launch paints a dark frame '
      'while the settings row is still being read', () {
    // Deliberately NOT loaded: this is the state `main.dart` builds its first
    // frames in.
    expect(SettingsProvider(SettingsRepository(db)).themeMode, ThemeMode.light);
  });

  test('an explicit "system" choice still follows the OS', () async {
    final provider = SettingsProvider(SettingsRepository(db));
    await provider.load();
    await provider.setThemeMode(ThemeMode.system);
    expect(provider.themeMode, ThemeMode.system,
        reason: 'collapsing system into the light fallback would delete the '
            'System option from the picker without removing it from the UI');
  });

  test('an explicit dark choice survives', () async {
    final provider = SettingsProvider(SettingsRepository(db));
    await provider.load();
    await provider.setThemeMode(ThemeMode.dark);
    expect(provider.themeMode, ThemeMode.dark);
  });

  /// The seed must not depend on the `CREATE TABLE` default, because that
  /// default is frozen into each database at the moment it was created. A
  /// phone that installed the app at schema v12 still has
  /// `DEFAULT 'system'` on this column and always will -- no migration
  /// rewrites a default, and rebuilding the table to change one would be a
  /// destructive operation for a cosmetic gain.
  ///
  /// So "delete all my data" re-seeded the row from THAT table's default and
  /// handed a long-standing user system theme, while someone who installed the
  /// same build yesterday got light. Same build, same code path, two answers.
  test('a wipe on a database created at v12 still resets to light', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final old = await verifier.schemaAt(12);
    final upgraded = AppDatabase.forTesting(old.newConnection());
    addTearDown(upgraded.close);

    await upgraded.deleteAllData();

    expect((await upgraded.getSettings()).themeMode, 'light');
  });
}
