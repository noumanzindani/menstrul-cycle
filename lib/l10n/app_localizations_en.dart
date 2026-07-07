// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LunaTrack';

  @override
  String get actionSave => 'Save';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionDelete => 'Delete';

  @override
  String get navToday => 'Today';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navForecast => 'Forecast';

  @override
  String get navInsights => 'Insights';

  @override
  String get navSettings => 'Settings';

  @override
  String get disclaimerFull =>
      'Predictions are estimates and can be wrong. They are not a contraceptive method and do not replace medical advice.';

  @override
  String get disclaimerCompact =>
      'Estimates only — not a contraceptive method.';

  @override
  String get homeTitle => 'LunaTrack';

  @override
  String get homeLogToday => 'Log today';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'System default';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsLanguageTitle => 'App language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsSectionPremium => 'Premium';

  @override
  String get settingsPremiumActiveTitle => 'Premium active';

  @override
  String get settingsPremiumInactiveTitle => 'Go Premium';

  @override
  String get settingsPremiumActiveSubtitle => 'Ads removed — thank you!';

  @override
  String get settingsPremiumInactiveSubtitle => 'Remove ads and unlock extras';

  @override
  String get settingsSectionGoal => 'Goal';

  @override
  String get settingsGoalTrackTitle => 'Track my cycle';

  @override
  String get settingsGoalTrackSubtitle =>
      'Lead with your next period and phase';

  @override
  String get settingsGoalConceiveTitle => 'Try to conceive';

  @override
  String get settingsGoalConceiveSubtitle =>
      'Lead with fertile days and ovulation';

  @override
  String get settingsGoalPerimenopauseTitle => 'Perimenopause';

  @override
  String get settingsGoalPerimenopauseSubtitle =>
      'Track symptoms as cycles become irregular';

  @override
  String get settingsPregnancyTitle => 'Pregnancy';

  @override
  String get settingsPregnancyOn => 'Pregnancy tracking is on';

  @override
  String get settingsPregnancyOff => 'Track a pregnancy';

  @override
  String get settingsSectionCycleDefaults => 'Cycle defaults';

  @override
  String get settingsAvgCycleLength => 'Average cycle length';

  @override
  String get settingsAvgPeriodLength => 'Average period length';

  @override
  String get settingsUnitDays => 'days';

  @override
  String get settingsSectionReminders => 'Reminders';

  @override
  String get settingsRemindersTitle => 'Reminders';

  @override
  String get settingsRemindersSubtitle =>
      'Period, fertile window, and daily log';

  @override
  String get settingsSectionMedications => 'Medications';

  @override
  String get settingsMedicationsTitle => 'Medications & birth control';

  @override
  String get settingsMedicationsSubtitle =>
      'Track medication and set daily reminders';

  @override
  String get settingsSectionHealth => 'Health & wearables';

  @override
  String get settingsHealthImportTitle => 'Import temperature';

  @override
  String get settingsHealthImportSubtitle =>
      'Bring basal body temperature in from your device\'s health app';

  @override
  String settingsHealthImportDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Imported $count temperature readings',
      one: 'Imported 1 temperature reading',
      zero: 'No new temperature readings to import',
    );
    return '$_temp0';
  }

  @override
  String get settingsHealthImportUnavailable =>
      'Health Connect isn\'t set up on this device';

  @override
  String get settingsHealthImportDenied =>
      'Permission is needed to read your health data';

  @override
  String get settingsHealthImportError =>
      'Couldn\'t import right now — please try again';

  @override
  String get settingsGenderNeutralTitle => 'Gender-neutral language';

  @override
  String get settingsGenderNeutralSubtitle =>
      'Use inclusive wording throughout the app';

  @override
  String get settingsSectionPrivacy => 'Privacy';

  @override
  String get settingsAppLockTitle => 'App lock';

  @override
  String get settingsAppLockSubtitle => 'Require a PIN or biometrics to open';

  @override
  String get settingsDeleteTitle => 'Delete all my data';

  @override
  String get settingsDeleteSubtitle =>
      'Permanently erase everything on this device';

  @override
  String get settingsDeleteDialogTitle => 'Delete all data?';

  @override
  String get settingsDeleteDialogBody =>
      'This permanently erases every period, symptom, medication, reminder, and setting on this device. This cannot be undone.';

  @override
  String get settingsDeleteConfirm => 'Delete everything';

  @override
  String get settingsDeleteDone => 'All data deleted.';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsAboutBody =>
      'LunaTrack stores all your data privately on this device. Predictions are estimates and are not a contraceptive method or a substitute for medical advice.';
}
