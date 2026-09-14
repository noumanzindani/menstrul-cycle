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
  /// The user's profile: date of birth, height in canonical CENTIMETRES,
  /// current weight in canonical KILOGRAMS, and the age in years at menarche.
  /// Every one is null until the user answers — the profile is skippable, and
  /// a missing answer is never stood in for by a guess.
  ///
  /// [profileWeightKg] is NOT the per-day `weight` metric that drives the
  /// 90-day trend chart; that one lives in the day-tags blob and is read
  /// through `LogProvider`. Never let one stand in for the other.
  DateTime? get dateOfBirth => _settings?.dateOfBirth;
  double? get heightCm => _settings?.heightCm;
  double? get profileWeightKg => _settings?.profileWeightKg;
  int? get menarcheAge => _settings?.menarcheAge;

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

  /// Sets the date of birth, or clears it when [dob] is null.
  ///
  /// A user edit, so it routes through [update] and stamps `settingsUpdatedAt`
  /// — the same as every other preference. Callers are responsible for
  /// REFUSING an implausible value (see the range rules at the display
  /// boundary); this writes whatever it is given, including null to clear.
  Future<void> setDateOfBirth(DateTime? dob) =>
      update(AppSettingsCompanion(dateOfBirth: Value(dob)));

  /// Sets the height in canonical CENTIMETRES, or clears it when [cm] is null.
  /// Any ft/in entry must already have been converted by the caller, and the
  /// plausibility check must happen AFTER that conversion.
  Future<void> setHeightCm(double? cm) =>
      update(AppSettingsCompanion(heightCm: Value(cm)));

  /// Sets the profile weight in canonical KILOGRAMS, or clears it when [kg] is
  /// null. Any lb entry must already have been converted by the caller.
  ///
  /// This is the "what do you weigh" profile answer that feeds the doctor PDF
  /// header and the BMI readout. It deliberately does NOT touch the per-day
  /// `weight` metric behind the trend chart, and nothing may make the two read
  /// from each other.
  Future<void> setProfileWeightKg(double? kg) =>
      update(AppSettingsCompanion(profileWeightKg: Value(kg)));

  /// Sets the age in years at the first period, or clears it when [years] is
  /// null.
  Future<void> setMenarcheAge(int? years) =>
      update(AppSettingsCompanion(menarcheAge: Value(years)));

  /// The clinical profile: contraception method and when it started, diagnoses
  /// the user has already been given, and breastfeeding status.
  ///
  /// Every one is null until answered, and here that distinction does real
  /// work: [contraceptionMethod] of null means "never asked", while
  /// [kContraceptionNone] means "using nothing". Only the second may be printed
  /// in a doctor report, and only the second says anything about the user.
  String? get contraceptionMethod => _settings?.contraceptionMethod;
  DateTime? get contraceptionStartDate => _settings?.contraceptionStartDate;

  /// True when the method in use suppresses ovulation, which makes a predicted
  /// fertile window meaningless. Read by `main.dart` and the background
  /// isolate, both of which hand it to `PredictionService.predictFromLogs`.
  bool get suppressesOvulation =>
      kOvulationSuppressingContraception.contains(contraceptionMethod);

  /// Diagnoses the user has been told they have, decoded from the JSON array.
  ///
  /// Same tolerant posture as [enabledCategories]: malformed JSON, a non-list,
  /// and ids written by a newer build all read as "nothing known" rather than
  /// throwing. A settings getter that can throw takes the whole screen down.
  Set<String> get knownDiagnoses {
    final raw = _settings?.knownDiagnoses;
    if (raw == null) return const {};
    final known = {for (final o in kDiagnosisOptions) o.key};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {
        for (final e in decoded)
          if (e is String && known.contains(e)) e,
      };
    } on FormatException {
      return const {};
    }
  }

  /// Null = never asked, false = answered no, true = answered yes. Never
  /// collapse the first two: a doctor report that prints "not breastfeeding"
  /// for somebody who was never asked has invented a clinical fact.
  bool? get breastfeeding => _settings?.breastfeeding;
  DateTime? get breastfeedingSince => _settings?.breastfeedingSince;

  /// Sets the contraception method (a `contra_` key) and optionally when it
  /// started. Passing null for [method] clears the answer back to "never
  /// asked"; `kContraceptionNone` is how "using nothing" is recorded.
  Future<void> setContraception(String? method, {DateTime? startDate}) =>
      update(AppSettingsCompanion(
        contraceptionMethod: Value(method),
        // Clearing the method clears its date too. A start date belonging to a
        // method that is no longer recorded is worse than no date: it would
        // print in the report attached to nothing.
        contraceptionStartDate:
            method == null ? const Value(null) : Value(startDate),
      ));

  /// Replaces the set of known diagnoses. An EMPTY set is written as an empty
  /// array, not null — "I was asked and have none" is a real answer.
  Future<void> setKnownDiagnoses(Set<String> ids) => update(
        AppSettingsCompanion(knownDiagnoses: Value(jsonEncode(ids.toList()))),
      );

  /// The signup sexual-health baseline. Decoded on every read rather than
  /// cached: the column is the single source of truth, and a cache here is a
  /// second one that goes stale on the next sync pull.
  SexualBaseline get sexualBaseline =>
      decodeSexualBaseline(_settings?.sexualHealthBaseline);

  /// Stores the baseline. A wholly-skipped one writes NULL, not `{}` — see
  /// [encodeSexualBaseline] for why the two must stay distinguishable.
  Future<void> setSexualBaseline({
    String? sexFrequency,
    String? soloFrequency,
    String? libido,
    Set<String> history = const {},
    Set<String> soloWays = const {},
    String? satisfactionTime,
  }) =>
      update(AppSettingsCompanion(
        sexualHealthBaseline: Value(encodeSexualBaseline(
          sexFrequency: sexFrequency,
          soloFrequency: soloFrequency,
          libido: libido,
          history: history,
          soloWays: soloWays,
          satisfactionTime: satisfactionTime,
        )),
      ));

  /// Sets breastfeeding status, or clears it to "never asked" with null.
  Future<void> setBreastfeeding(bool? value, {DateTime? since}) =>
      update(AppSettingsCompanion(
        breastfeeding: Value(value),
        // Same rule as the contraception date, plus one more: answering "no"
        // must drop a since-date left over from a previous "yes".
        breastfeedingSince:
            value == true ? Value(since) : const Value(null),
      ));

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
