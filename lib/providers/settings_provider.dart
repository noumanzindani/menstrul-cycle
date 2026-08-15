import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../common/catalog.dart';
import '../common/tracking_categories.dart';
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
  String get language => _settings?.language ?? 'en';
  bool get onboardingComplete => _settings?.onboardingComplete ?? false;

  /// Null on a fresh install or a never-synced account — the signal
  /// `_AppGateState._maybePromptClaim` uses to tell a brand-new account from
  /// one that has already synced.
  DateTime? get lastSyncedAt => _settings?.lastSyncedAt;

  /// Display unit for weight. Stored values are always canonical kg; null in the
  /// column means "never chosen" and reads as kg.
  String get weightUnit => _settings?.weightUnit ?? kWeightUnitKg;

  /// The account that opted in to photo descriptions on THIS device, if any.
  ///
  /// Compared against the current uid by the caller rather than reduced to a
  /// bool here: "someone consented" and "this account consented" are different
  /// questions, and only the second one may open the feature.
  String? get analysisConsentUid => _settings?.analysisConsentUid;

  /// Daily-cap bookkeeping for photo descriptions. See `media_analysis.dart`.
  String? get analysisCountDay => _settings?.analysisCountDay;
  int? get analysisCountToday => _settings?.analysisCountToday;
  DateTime? get pregnancyStartDate => _settings?.pregnancyStartDate;
  bool get isPregnant =>
      mode == TrackingMode.pregnancy && pregnancyStartDate != null;

  /// Day-editor categories the user has switched on. A NULL column means the
  /// user has never customised this, so the registry defaults apply. An EMPTY
  /// array means they turned everything off — that is a real choice and must
  /// not be reset to defaults. Unknown ids (written by a newer build) and
  /// malformed JSON are ignored.
  Set<String> get enabledCategories {
    final raw = _settings?.trackingCategories;
    if (raw == null) return defaultEnabledCategoryIds();

    final known = {for (final c in kTrackingCategories) c.id};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return defaultEnabledCategoryIds();
      return {
        for (final e in decoded)
          if (e is String && known.contains(e)) e,
      };
    } on FormatException {
      return defaultEnabledCategoryIds();
    }
  }

  Future<void> setCategoryEnabled(String id, bool on) {
    final next = {...enabledCategories};
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return update(AppSettingsCompanion(
      trackingCategories: Value(jsonEncode(next.toList())),
    ));
  }

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

  /// Records that [uid] opted in to sending photos out for description.
  ///
  /// A real user edit, so it goes through [update] and stamps
  /// `settingsUpdatedAt` like any other preference. The column itself is not
  /// pushed (see `SyncService._pushSettings`) — the stamp is about local
  /// ordering, not about shipping the consent to another device.
  Future<void> setAnalysisConsent(String uid) =>
      update(AppSettingsCompanion(analysisConsentUid: Value(uid)));

  /// Withdraws the opt-in. Absence of a uid is the off state.
  Future<void> clearAnalysisConsent() =>
      update(const AppSettingsCompanion(analysisConsentUid: Value(null)));

  /// Advances the daily-cap counter.
  ///
  /// Deliberately `updateSyncState`, NOT [update]. This fires on every analysis
  /// — up to [kMaxAnalysesPerDay] times a day — and stamping `settingsUpdatedAt`
  /// each time would make every subsequent sync believe the user had edited
  /// their settings and push them again, forever. That is the exact failure the
  /// two-write-path split in `SettingsRepository` exists to prevent.
  Future<void> recordAnalysisUsage(String day, int count) async {
    await _repo.updateSyncState(
      AppSettingsCompanion(
        analysisCountDay: Value(day),
        analysisCountToday: Value(count),
      ),
    );
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

  /// The app language: a locale code (e.g. 'en') or 'system' to follow the OS.
  Future<void> setLanguage(String code) =>
      update(AppSettingsCompanion(language: Value(code)));

  /// Switches the weight DISPLAY unit only. Values stay in canonical kg, so this
  /// never rewrites logged data.
  Future<void> setWeightUnit(String unit) =>
      update(AppSettingsCompanion(weightUnit: Value(unit)));

  Future<void> completeOnboarding() =>
      update(const AppSettingsCompanion(onboardingComplete: Value(true)));

  /// Starts pregnancy tracking, dated from the last-period date [lmp]. Switches
  /// the app into pregnancy mode (period/fertility predictions are suppressed).
  Future<void> startPregnancy(DateTime lmp) => update(AppSettingsCompanion(
        mode: const Value(TrackingMode.pregnancy),
        pregnancyStartDate: Value(lmp),
      ));

  /// Ends pregnancy tracking and clears its data. Neutral, one-step, loss-safe —
  /// returns the app to cycle tracking; cycle history is untouched.
  Future<void> endPregnancy() => update(const AppSettingsCompanion(
        mode: Value(TrackingMode.track),
        pregnancyStartDate: Value(null),
      ));
}
