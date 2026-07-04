import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../data/settings_repository.dart';
import '../db/database.dart';
import '../models/enums.dart';

/// Exposes the app-settings row and helpers to update common fields.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider(this._repo);
  final SettingsRepository _repo;

  AppSetting? _settings;
  AppSetting? get settings => _settings;
  bool get loaded => _settings != null;

  int get cycleLength => _settings?.defaultCycleLength ?? 28;
  int get periodLength => _settings?.defaultPeriodLength ?? 5;
  TrackingMode get mode => _settings?.mode ?? TrackingMode.track;
  bool get premium => _settings?.premium ?? false;
  bool get appLockEnabled => _settings?.appLockEnabled ?? false;
  bool get genderNeutralLanguage => _settings?.genderNeutralLanguage ?? false;
  bool get onboardingComplete => _settings?.onboardingComplete ?? false;

  ThemeMode get themeMode => switch (_settings?.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> load() async {
    _settings = await _repo.get();
    notifyListeners();
  }

  Future<void> update(AppSettingsCompanion changes) async {
    await _repo.update(changes);
    _settings = await _repo.get();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) => update(
        AppSettingsCompanion(
          themeMode: Value(switch (mode) {
            ThemeMode.light => 'light',
            ThemeMode.dark => 'dark',
            ThemeMode.system => 'system',
          }),
        ),
      );

  Future<void> setMode(TrackingMode mode) =>
      update(AppSettingsCompanion(mode: Value(mode)));

  Future<void> setCycleLength(int days) =>
      update(AppSettingsCompanion(defaultCycleLength: Value(days)));

  Future<void> setPeriodLength(int days) =>
      update(AppSettingsCompanion(defaultPeriodLength: Value(days)));

  Future<void> setAppLock(bool enabled) =>
      update(AppSettingsCompanion(appLockEnabled: Value(enabled)));

  Future<void> setGenderNeutralLanguage(bool v) =>
      update(AppSettingsCompanion(genderNeutralLanguage: Value(v)));

  Future<void> completeOnboarding() =>
      update(const AppSettingsCompanion(onboardingComplete: Value(true)));
}
