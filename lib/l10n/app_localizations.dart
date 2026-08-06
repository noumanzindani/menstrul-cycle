import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'LunaTrack'**
  String get appTitle;

  /// No description provided for @actionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @navToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// No description provided for @navCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get navCalendar;

  /// No description provided for @navForecast.
  ///
  /// In en, this message translates to:
  /// **'Forecast'**
  String get navForecast;

  /// No description provided for @navInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get navInsights;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @disclaimerFull.
  ///
  /// In en, this message translates to:
  /// **'Predictions are estimates and can be wrong. They are not a contraceptive method and do not replace medical advice.'**
  String get disclaimerFull;

  /// No description provided for @disclaimerCompact.
  ///
  /// In en, this message translates to:
  /// **'Estimates only — not a contraceptive method.'**
  String get disclaimerCompact;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'LunaTrack'**
  String get homeTitle;

  /// No description provided for @homeLogToday.
  ///
  /// In en, this message translates to:
  /// **'Log today'**
  String get homeLogToday;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsSectionPremium.
  ///
  /// In en, this message translates to:
  /// **'Premium'**
  String get settingsSectionPremium;

  /// No description provided for @settingsPremiumActiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium active'**
  String get settingsPremiumActiveTitle;

  /// No description provided for @settingsPremiumInactiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Go Premium'**
  String get settingsPremiumInactiveTitle;

  /// No description provided for @settingsPremiumActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ads removed — thank you!'**
  String get settingsPremiumActiveSubtitle;

  /// No description provided for @settingsPremiumInactiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remove ads and unlock extras'**
  String get settingsPremiumInactiveSubtitle;

  /// No description provided for @settingsSectionGoal.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get settingsSectionGoal;

  /// No description provided for @settingsGoalTrackTitle.
  ///
  /// In en, this message translates to:
  /// **'Track my cycle'**
  String get settingsGoalTrackTitle;

  /// No description provided for @settingsGoalTrackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lead with your next period and phase'**
  String get settingsGoalTrackSubtitle;

  /// No description provided for @settingsGoalConceiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Try to conceive'**
  String get settingsGoalConceiveTitle;

  /// No description provided for @settingsGoalConceiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Lead with fertile days and ovulation'**
  String get settingsGoalConceiveSubtitle;

  /// No description provided for @settingsGoalPerimenopauseTitle.
  ///
  /// In en, this message translates to:
  /// **'Perimenopause'**
  String get settingsGoalPerimenopauseTitle;

  /// No description provided for @settingsGoalPerimenopauseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track symptoms as cycles become irregular'**
  String get settingsGoalPerimenopauseSubtitle;

  /// No description provided for @settingsPregnancyTitle.
  ///
  /// In en, this message translates to:
  /// **'Pregnancy'**
  String get settingsPregnancyTitle;

  /// No description provided for @settingsPregnancyOn.
  ///
  /// In en, this message translates to:
  /// **'Pregnancy tracking is on'**
  String get settingsPregnancyOn;

  /// No description provided for @settingsPregnancyOff.
  ///
  /// In en, this message translates to:
  /// **'Track a pregnancy'**
  String get settingsPregnancyOff;

  /// No description provided for @settingsSectionCycleDefaults.
  ///
  /// In en, this message translates to:
  /// **'Cycle defaults'**
  String get settingsSectionCycleDefaults;

  /// No description provided for @settingsAvgCycleLength.
  ///
  /// In en, this message translates to:
  /// **'Average cycle length'**
  String get settingsAvgCycleLength;

  /// No description provided for @settingsAvgPeriodLength.
  ///
  /// In en, this message translates to:
  /// **'Average period length'**
  String get settingsAvgPeriodLength;

  /// No description provided for @settingsUnitDays.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get settingsUnitDays;

  /// No description provided for @settingsSectionReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsSectionReminders;

  /// No description provided for @settingsRemindersTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get settingsRemindersTitle;

  /// No description provided for @settingsRemindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Period, fertile window, and daily log'**
  String get settingsRemindersSubtitle;

  /// No description provided for @settingsSectionMedications.
  ///
  /// In en, this message translates to:
  /// **'Medications'**
  String get settingsSectionMedications;

  /// No description provided for @settingsMedicationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Medications & birth control'**
  String get settingsMedicationsTitle;

  /// No description provided for @settingsMedicationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track medication and set daily reminders'**
  String get settingsMedicationsSubtitle;

  /// No description provided for @settingsTrackingTitle.
  ///
  /// In en, this message translates to:
  /// **'Customize tracking'**
  String get settingsTrackingTitle;

  /// No description provided for @settingsTrackingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what appears when you log a day'**
  String get settingsTrackingSubtitle;

  /// No description provided for @settingsTrackingNote.
  ///
  /// In en, this message translates to:
  /// **'Turning a category off only hides it from the day editor. Anything you\'ve already logged is kept, not deleted.'**
  String get settingsTrackingNote;

  /// No description provided for @settingsSectionHealth.
  ///
  /// In en, this message translates to:
  /// **'Health & wearables'**
  String get settingsSectionHealth;

  /// No description provided for @settingsHealthImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import temperature'**
  String get settingsHealthImportTitle;

  /// No description provided for @settingsHealthImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bring basal body temperature in from your device\'s health app'**
  String get settingsHealthImportSubtitle;

  /// No description provided for @settingsHealthImportDone.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new temperature readings to import} =1{Imported 1 temperature reading} other{Imported {count} temperature readings}}'**
  String settingsHealthImportDone(int count);

  /// No description provided for @settingsHealthImportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Health Connect isn\'t set up on this device'**
  String get settingsHealthImportUnavailable;

  /// No description provided for @settingsHealthImportDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission is needed to read your health data'**
  String get settingsHealthImportDenied;

  /// No description provided for @settingsHealthImportError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import right now — please try again'**
  String get settingsHealthImportError;

  /// No description provided for @settingsGenderNeutralTitle.
  ///
  /// In en, this message translates to:
  /// **'Gender-neutral language'**
  String get settingsGenderNeutralTitle;

  /// No description provided for @settingsGenderNeutralSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use inclusive wording throughout the app'**
  String get settingsGenderNeutralSubtitle;

  /// No description provided for @settingsSectionPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsSectionPrivacy;

  /// No description provided for @settingsAppLockTitle.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLockTitle;

  /// No description provided for @settingsAppLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Require a PIN or biometrics to open'**
  String get settingsAppLockSubtitle;

  /// No description provided for @settingsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all my data'**
  String get settingsDeleteTitle;

  /// No description provided for @settingsDeleteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Erase this device and turn cloud sync off here'**
  String get settingsDeleteSubtitle;

  /// No description provided for @settingsDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete all data?'**
  String get settingsDeleteDialogTitle;

  /// No description provided for @settingsDeleteDialogBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently erases every period, symptom, medication, reminder and setting on this device, and turns cloud sync off for your account on this device — so nothing is downloaded back. This cannot be undone.\n\nYour account and the copy of your logs on our server are kept. You can turn sync back on any time under Account. To delete the server copy too, use Account → Request account deletion.'**
  String get settingsDeleteDialogBody;

  /// No description provided for @settingsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Erase this device'**
  String get settingsDeleteConfirm;

  /// No description provided for @settingsDeleteDone.
  ///
  /// In en, this message translates to:
  /// **'This device is erased and cloud sync is off here. Your account still has your logs.'**
  String get settingsDeleteDone;

  /// No description provided for @settingsSectionBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup & restore'**
  String get settingsSectionBackup;

  /// No description provided for @settingsBackupExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Back up my data'**
  String get settingsBackupExportTitle;

  /// No description provided for @settingsBackupExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save an encrypted file only you can open'**
  String get settingsBackupExportSubtitle;

  /// No description provided for @settingsBackupRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get settingsBackupRestoreTitle;

  /// No description provided for @settingsBackupRestoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replace current data from a backup file'**
  String get settingsBackupRestoreSubtitle;

  /// No description provided for @backupPassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a passphrase'**
  String get backupPassphraseTitle;

  /// No description provided for @backupPassphraseBody.
  ///
  /// In en, this message translates to:
  /// **'Your backup is encrypted with this passphrase. You\'ll need the exact passphrase to restore it — it is never stored or sent anywhere, so if you lose it the backup can\'t be opened.'**
  String get backupPassphraseBody;

  /// No description provided for @backupPassphraseHint.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get backupPassphraseHint;

  /// No description provided for @backupPassphraseConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm passphrase'**
  String get backupPassphraseConfirmHint;

  /// No description provided for @backupPassphraseMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passphrases don\'t match.'**
  String get backupPassphraseMismatch;

  /// No description provided for @backupPassphraseTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters.'**
  String get backupPassphraseTooShort;

  /// No description provided for @backupActionBackUp.
  ///
  /// In en, this message translates to:
  /// **'Back up'**
  String get backupActionBackUp;

  /// No description provided for @backupExportError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the backup — please try again.'**
  String get backupExportError;

  /// No description provided for @backupRestoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace all current data?'**
  String get backupRestoreConfirmTitle;

  /// No description provided for @backupRestoreConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Restoring overwrites everything currently in the app with the backup\'s contents. This can\'t be undone.'**
  String get backupRestoreConfirmBody;

  /// No description provided for @backupRestoreConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get backupRestoreConfirmAction;

  /// No description provided for @backupRestorePassphraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the backup\'s passphrase'**
  String get backupRestorePassphraseTitle;

  /// No description provided for @backupActionRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupActionRestore;

  /// No description provided for @backupRestoreDone.
  ///
  /// In en, this message translates to:
  /// **'Your data was restored.'**
  String get backupRestoreDone;

  /// No description provided for @backupRestoreWrongPass.
  ///
  /// In en, this message translates to:
  /// **'Wrong passphrase, or the file isn\'t a valid LunaTrack backup.'**
  String get backupRestoreWrongPass;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// No description provided for @settingsAboutBody.
  ///
  /// In en, this message translates to:
  /// **'LunaTrack stores your data in an encrypted database on this device and syncs it to your account. The synced copy is not end-to-end encrypted. Predictions are estimates and are not a contraceptive method or a substitute for medical advice.'**
  String get settingsAboutBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
