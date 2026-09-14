import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../common/l10n.dart';
import '../../common/option_art.dart';
import '../../common/tracking_categories.dart';
import '../../data/daily_log_repository.dart';
import '../../db/database.dart';
import '../../models/enums.dart';
import '../../providers/auth_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/premium_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/backup_service.dart';
import '../../services/firestore_ref.dart';
import '../../services/health_import_service.dart';
import '../../services/lock_service.dart';
import '../../services/media_analyzer.dart' show analysisAvailable;
import '../../services/media_cache.dart';
import '../../services/notification_service.dart';
import '../../services/sync_trigger.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/track_art.dart';
import '../lock/setup_lock_screen.dart';
import '../medications/medications_screen.dart';
import 'account_section.dart';
import 'settings_group.dart';
import 'tracking_categories_screen.dart';
import '../pregnancy/pregnancy_screen.dart';
import '../premium/premium_screen.dart';
import '../reminders/reminders_screen.dart';

/// App settings: appearance, cycle defaults (feed prediction when history is
/// thin), reminders, and the required disclaimer/about.
///
/// ## Layout
///
/// One scrolling list of **grouped rows**: a small uppercase accent-coloured
/// header, then its rows separated by hairlines inset past the icon column, and
/// whitespace (not a full-width `Divider`) between groups. Rows that choose a
/// value show that value on the RIGHT and open a picker; rows that go somewhere
/// keep a chevron. That split is the whole navigational grammar of the screen —
/// see `docs/design/stitch/06-settings.html`.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.clearFirestoreCache = clearLunaFirestoreCache,
    this.clearPin = LockService.clearPin,
    this.cancelNotifications = NotificationService.cancelAll,
    this.clearMediaCache = _clearMediaCache,
  });

  /// Deletes downloaded photos and videos from the on-disk cache.
  ///
  /// Not part of `AppDatabase.deleteAllData()` on purpose: that is a pure drift
  /// transaction, run against in-memory databases in tests where
  /// `path_provider` has no platform-channel handler. Injectable for the same
  /// reason [clearPin] is.
  ///
  /// Without this, "delete all my data" wipes the media ROWS and leaves the
  /// full-size files sitting in the cache directory — the most visible possible
  /// way for that promise to be false.
  final Future<void> Function() clearMediaCache;

  static Future<void> _clearMediaCache() => MediaCache().clear();

  /// Wipes Firestore's unencrypted on-device cache as part of "delete all my
  /// data" — see [clearLunaFirestoreCache].
  ///
  /// Injectable because `FakeFirebaseFirestore.clearPersistence()` wipes the
  /// whole fake database (server side included), so a test could not otherwise
  /// assert that this control leaves the cloud copy alone.
  final Future<void> Function() clearFirestoreCache;

  /// These two are injectable for the reason `AccountSection`'s identical pair
  /// is (see its doc comment): `flutter_secure_storage` and the local
  /// notifications plugin have no platform-channel handler under
  /// `flutter_tester` on this host, and the former HANGS rather than throwing —
  /// which `pumpAndSettle` does not detect, because it waits on frames, not on
  /// a stalled channel call. Without these seams the "delete all my data"
  /// control could not be tested at all.
  final Future<void> Function() clearPin;
  final Future<void> Function() cancelNotifications;

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          // Icon + centred title, then the destructive action as one
          // full-width button with Cancel beneath it. A `FilledButton` demands
          // infinite width (`filledButtonTheme.minimumSize`), so `actions`
          // always lays out vertically here — this ordering is what puts the
          // prominent control on top rather than under the quiet one.
          icon: Icon(Icons.delete_outline, color: scheme.error),
          title: Text(ctx.l10n.settingsDeleteDialogTitle),
          content: Text(
            ctx.l10n.settingsDeleteDialogBody,
            textAlign: TextAlign.start,
          ),
          actionsOverflowAlignment: OverflowBarAlignment.center,
          actionsOverflowButtonSpacing: 4,
          actions: [
            FilledButton(
              key: const Key('settings.confirmDeleteAll'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.settingsDeleteConfirm),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.actionCancel),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    // Capture everything that needs `context` BEFORE the async gaps.
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();
    final meds = context.read<MedicationProvider>();
    final trigger = context.read<SyncTrigger>();
    final uid = context.read<AuthProvider>().user?.uid;
    final messenger = ScaffoldMessenger.of(context);
    final deletedMsg = context.l10n.settingsDeleteDone;

    // FIRST, before anything is deleted. Without this the control undid
    // itself: `deleteAllData` nulls `lastSyncedAt`, a null `since` makes the
    // next run a FULL sweep, and the wipe itself ARMS that run (`logs.load()`
    // below notifies `LogProvider`, which `main.dart` turns into a
    // `scheduleSync`). A reviewer executed it: local 0, then local 2 and
    // cloud 2. `suspend()` also awaits any run already in flight, so when it
    // returns this device is provably not writing.
    await trigger.suspend();
    // The durable half. `suspend()` lasts one session; this is the same
    // uid-scoped record the claim prompt writes, so the decision survives a
    // relaunch and `SyncTrigger.setUser` re-applies the gate on every future
    // sign-in until the user reverses it from Settings → Account.
    //
    // This is deliberately NOT a cloud deletion. The account keeps its copy —
    // erasing that is what "Request account deletion" is for, and that path
    // has a 30-day cancellable window precisely because an irreversible cloud
    // wipe must not hang off a control that historically only touched the
    // device. The dialog copy states both halves.
    if (uid != null) await trigger.resolveClaim(upload: false);

    await db.deleteAllData();
    // Before the Firestore cache clear below, which must stay the LAST
    // Firestore call in this flow. This one is plain file I/O with no ordering
    // constraint of its own, so it goes here where it cannot be skipped by an
    // early return further down. Swallowed for the same reason: a cache that
    // cannot be read is a cache with nothing to lose.
    try {
      await clearMediaCache();
    } catch (_) {}
    await clearPin();
    // Cancel every scheduled notification — cycle reminders AND the dynamic
    // per-medication ones (whose ids we no longer know after the wipe).
    await cancelNotifications();
    await settings.load();
    await logs.load();
    await meds.load();

    // The other half of "everything on this device": drift is encrypted at
    // rest, Firestore's own on-device persistence is NOT, and it physically
    // holds copies of `users/{uid}/dailyLogs` and the settings document. This
    // control promises erasure, so it has to clear that store too. See
    // [clearLunaFirestoreCache] for why it can only run once nothing else in
    // this flow needs Firestore.
    //
    // Swallowed: the database is already empty by now, and it throws on a
    // build with no Firebase app — where there is no cache to clear.
    try {
      await clearFirestoreCache();
    } catch (_) {}

    // Lifts the session-scoped hold, and ONLY that: `resume()` re-runs
    // `setUser`'s evaluation from scratch, which reads the decline recorded
    // above and leaves the sync gate closed. Without it the trigger would stay
    // suspended, and Settings → Account's "Turn on" would record consent while
    // `syncNow()` silently refused to run. Deliberately after the cache clear,
    // so the fresh `SyncService` is built against a client that has already
    // been terminated and restarted rather than a dead one.
    await trigger.resume();

    messenger.showSnackBar(
      SnackBar(content: Text(deletedMsg)),
    );
  }

  static String _localeName(String code) => switch (code) {
        'en' => 'English',
        _ => code,
      };

  Future<void> _pickLanguage(
      BuildContext context, SettingsProvider settings) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.settingsLanguageTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'system'),
            child: Text(ctx.l10n.settingsLanguageSystem),
          ),
          for (final loc in AppLocalizations.supportedLocales)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, loc.languageCode),
              child: Text(_localeName(loc.languageCode)),
            ),
        ],
      ),
    );
    if (chosen != null) await settings.setLanguage(chosen);
  }

  String _themeLabel(BuildContext context, ThemeMode mode) => switch (mode) {
        ThemeMode.system => context.l10n.settingsThemeSystem,
        ThemeMode.light => context.l10n.settingsThemeLight,
        ThemeMode.dark => context.l10n.settingsThemeDark,
      };

  /// Theme is a one-of-three choice, so it reads as a single row carrying its
  /// current value rather than three radios eating half the screen — the same
  /// shape the language and weight-unit rows already had.
  Future<void> _pickTheme(BuildContext context, SettingsProvider settings) async {
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.settingsSectionAppearance),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: settings.themeMode,
            onChanged: (m) => Navigator.pop(ctx, m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  value: ThemeMode.system,
                  title: Text(ctx.l10n.settingsThemeSystem),
                ),
                RadioListTile(
                  value: ThemeMode.light,
                  title: Text(ctx.l10n.settingsThemeLight),
                ),
                RadioListTile(
                  value: ThemeMode.dark,
                  title: Text(ctx.l10n.settingsThemeDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await settings.setThemeMode(picked);
  }

  String _modeLabel(BuildContext context, TrackingMode mode) => switch (mode) {
        TrackingMode.track => context.l10n.settingsGoalTrackTitle,
        TrackingMode.conceive => context.l10n.settingsGoalConceiveTitle,
        TrackingMode.perimenopause =>
          context.l10n.settingsGoalPerimenopauseTitle,
        // Not one of the three radios in [_pickMode] — pregnancy mode is
        // entered and left from `PregnancyScreen`, so the row still has to be
        // able to NAME it while it is the active mode.
        TrackingMode.pregnancy => context.l10n.settingsPregnancyTitle,
      };

  /// The mode picker keeps every option's explanatory subtitle — those lines
  /// are what tell a user that Conceive reorders Home and that Perimenopause
  /// caps prediction confidence, so they move into the dialog rather than being
  /// dropped when the three radios collapse into one row.
  Future<void> _pickMode(BuildContext context, SettingsProvider settings) async {
    final picked = await showDialog<TrackingMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.settingsSectionGoal),
        children: [
          RadioGroup<TrackingMode>(
            groupValue: settings.mode,
            onChanged: (m) => Navigator.pop(ctx, m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  value: TrackingMode.track,
                  title: Text(ctx.l10n.settingsGoalTrackTitle),
                  subtitle: Text(ctx.l10n.settingsGoalTrackSubtitle),
                ),
                RadioListTile(
                  value: TrackingMode.conceive,
                  title: Text(ctx.l10n.settingsGoalConceiveTitle),
                  subtitle: Text(ctx.l10n.settingsGoalConceiveSubtitle),
                ),
                RadioListTile(
                  value: TrackingMode.perimenopause,
                  title: Text(ctx.l10n.settingsGoalPerimenopauseTitle),
                  subtitle: Text(ctx.l10n.settingsGoalPerimenopauseSubtitle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await settings.setMode(picked);
  }

  /// Picks the weight DISPLAY unit. Logged values are canonical kg either way,
  /// so switching is purely cosmetic and never rewrites data.
  Future<void> _pickWeightUnit(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Weight unit'),
        children: [
          RadioGroup<String>(
            groupValue: settings.weightUnit,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  value: kWeightUnitKg,
                  title: Text('Kilograms (kg)'),
                ),
                RadioListTile(
                  value: kWeightUnitLb,
                  title: Text('Pounds (lb)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await settings.setWeightUnit(picked);
  }

  /// Pulls basal body temperature from Health Connect / HealthKit into the log.
  /// Native + device-only; the read path is local IPC (no network), so it keeps
  /// the app's no-backend promise. Captures context-derived values before the
  /// async gaps.
  Future<void> _importHealth(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final repo = DailyLogRepository(context.read<AppDatabase>());
    final logs = context.read<LogProvider>();

    final outcome =
        await HealthImportService().importTemperatures(repo: repo);
    await logs.load(); // surface any newly imported BBT immediately

    final message = switch (outcome.status) {
      HealthImportStatus.ok =>
        l10n.settingsHealthImportDone(outcome.result!.imported),
      HealthImportStatus.unavailable => l10n.settingsHealthImportUnavailable,
      HealthImportStatus.permissionDenied => l10n.settingsHealthImportDenied,
      HealthImportStatus.error => l10n.settingsHealthImportError,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Exports all data to a passphrase-encrypted file and opens the share sheet.
  /// No cloud — the user chooses where the file goes.
  Future<void> _exportBackup(BuildContext context) async {
    final pass = await showDialog<String>(
      context: context,
      builder: (_) => const _PassphraseDialog(confirm: true),
    );
    if (pass == null || !context.mounted) return;

    final db = context.read<AppDatabase>();
    final messenger = ScaffoldMessenger.of(context);
    final errorMsg = context.l10n.backupExportError;
    try {
      await BackupService.exportToFile(db, pass);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(errorMsg)));
    }
  }

  /// Restores from a user-picked encrypted file. DESTRUCTIVE — confirmed first,
  /// and the decrypt happens before any write, so a wrong passphrase changes
  /// nothing.
  Future<void> _restoreBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.restore_outlined),
        title: Text(ctx.l10n.backupRestoreConfirmTitle),
        content: Text(
          ctx.l10n.backupRestoreConfirmBody,
          textAlign: TextAlign.start,
        ),
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowButtonSpacing: 4,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.backupRestoreConfirmAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.actionCancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final bytes = await BackupService.pickBackupBytes();
    if (bytes == null || !context.mounted) return;

    final pass = await showDialog<String>(
      context: context,
      builder: (_) => _PassphraseDialog(
        title: context.l10n.backupRestorePassphraseTitle,
        action: context.l10n.backupActionRestore,
      ),
    );
    if (pass == null || !context.mounted) return;

    // Capture everything context-derived BEFORE the async gaps.
    final db = context.read<AppDatabase>();
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();
    final meds = context.read<MedicationProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final doneMsg = context.l10n.backupRestoreDone;
    final failMsg = context.l10n.backupRestoreWrongPass;

    try {
      await BackupService.importEncrypted(db, bytes, pass);
      // Imported reminders differ from whatever was scheduled; clear stale ones
      // (they reschedule when the user next edits reminders).
      await NotificationService.cancelAll();
      await settings.load();
      await logs.load();
      await meds.load();
      messenger.showSnackBar(SnackBar(content: Text(doneMsg)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failMsg)));
    }
  }

  /// Canonical [cm] rendered for [unit].
  ///
  /// Feet-and-inches already carries its own marks (`5'5"`), so the unit is
  /// appended only for centimetres. That is also why the range refusal takes
  /// both bounds PRE-FORMATTED rather than appending a bare `$unit` the way the
  /// day form's weight message does — under lb it would read `between 2'7" and
  /// 8'2" lb`.
  static String _heightLabel(BuildContext context, double cm, String unit) =>
      unit == kWeightUnitLb
          ? formatHeightFromCm(cm, unit)
          : '${formatHeightFromCm(cm, unit)} '
              '${context.l10n.settingsProfileHeightUnitCm}';

  /// Canonical [kg] rendered for [unit]. Unlike height, both weight units need
  /// the suffix — `62.5` alone says nothing.
  static String _weightLabel(double kg, String unit) =>
      '${formatWeightFromKg(kg, unit)} $unit';

  /// Date of birth — a FULL date, never a year or an age, so it stays correct
  /// as time passes.
  ///
  /// Same shape as the app's only other date picker
  /// (`pregnancy_screen.dart`), `helpText` included. With nothing stored the
  /// picker OPENS 25 years back: that is where the wheel starts, not a default
  /// — nothing is written unless the user confirms a date.
  Future<void> _pickDateOfBirth(
      BuildContext context, SettingsProvider settings) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: settings.dateOfBirth ??
          DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      helpText: context.l10n.settingsProfileDobHelp,
    );
    if (picked != null) await settings.setDateOfBirth(picked);
  }

  /// Height, stored in canonical CENTIMETRES.
  ///
  /// Out of range is a REFUSAL: `parseHeightToCm` returns null, the dialog
  /// shows the inline error and stays open, and nothing is written — the same
  /// contract as `DayEntryFormState.save()`, never a silent clamp. The range is
  /// checked AFTER the ft/in → cm conversion, inside the parser.
  Future<void> _editHeight(
      BuildContext context, SettingsProvider settings) async {
    final l10n = context.l10n;
    final unit = settings.weightUnit;
    final lo = _heightLabel(context, kMinHeightCm, unit);
    final hi = _heightLabel(context, kMaxHeightCm, unit);
    final cm = settings.heightCm;
    final result = await showDialog<_MeasureResult>(
      context: context,
      builder: (_) => _MeasureDialog(
        fieldKey: const Key('settings.profile.heightField'),
        title: l10n.settingsProfileHeightTitle,
        suffix: unit == kWeightUnitLb
            ? l10n.settingsProfileHeightUnitFtIn
            : l10n.settingsProfileHeightUnitCm,
        initial: cm == null ? '' : formatHeightFromCm(cm, unit),
        // Feet and inches needs the ' and " characters, so it cannot use the
        // numeric keyboard.
        keyboardType: unit == kWeightUnitLb
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        parse: (raw) => parseHeightToCm(raw, unit),
        rangeError: l10n.settingsProfileHeightRange(lo, hi),
      ),
    );
    if (result != null) await settings.setHeightCm(result.value);
  }

  /// The profile's "current weight", in canonical KILOGRAMS.
  ///
  /// A SEPARATE value from the per-day `kMetricWeight` the day editor logs and
  /// the 90-day trend chart reads. Neither ever reads from the other, and the
  /// row is labelled so they cannot be mistaken for one field.
  Future<void> _editProfileWeight(
      BuildContext context, SettingsProvider settings) async {
    final l10n = context.l10n;
    final unit = settings.weightUnit;
    final kg = settings.profileWeightKg;
    final result = await showDialog<_MeasureResult>(
      context: context,
      builder: (_) => _MeasureDialog(
        fieldKey: const Key('settings.profile.weightField'),
        title: l10n.settingsProfileWeightTitle,
        suffix: unit,
        initial: kg == null ? '' : formatWeightFromKg(kg, unit),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        parse: (raw) => parseWeightToKg(raw, unit),
        rangeError: l10n.settingsProfileWeightRange(
          _weightLabel(kMinWeightKg, unit),
          _weightLabel(kMaxWeightKg, unit),
        ),
      ),
    );
    if (result != null) await settings.setProfileWeightKg(result.value);
  }

  Future<void> _editMenarcheAge(
      BuildContext context, SettingsProvider settings) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => _MenarcheDialog(initial: settings.menarcheAge),
    );
    if (picked != null) await settings.setMenarcheAge(picked);
  }


  /// The label for [key] in [options], or null when it is unanswered or was
  /// written by a newer build. Never falls back to the raw key: a screen
  /// showing `contra_combined_pill` to a user is worse than showing nothing.
  static String? _optionLabel(List<TrackOption> options, String? key) {
    if (key == null) return null;
    for (final o in options) {
      if (o.key == key) return o.label;
    }
    return null;
  }

  /// Contraception method. The one row on this screen that changes what the
  /// app PREDICTS: a method in `kOvulationSuppressingContraception` caps
  /// prediction confidence to low, which removes the fertile window app-wide.
  ///
  /// The dialog scrolls — thirteen methods do not fit a phone dialog, and a
  /// `SimpleDialog` does not scroll its children for you.
  Future<void> _pickContraception(
      BuildContext context, SettingsProvider settings) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.l10n.settingsClinicalContraceptionTitle),
        children: [
          SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: RadioGroup<String>(
                groupValue: settings.contraceptionMethod,
                onChanged: (m) => Navigator.pop(ctx, m),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final o in kContraceptionOptions)
                      RadioListTile(value: o.key, title: Text(o.label)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    // Keeps any existing start date when the method is unchanged; a genuinely
    // new method drops it, since a date belonging to the previous method would
    // be worse than none.
    if (picked != null) {
      await settings.setContraception(
        picked,
        startDate: picked == settings.contraceptionMethod
            ? settings.contraceptionStartDate
            : null,
      );
    }
  }

  Future<void> _pickContraceptionStart(
      BuildContext context, SettingsProvider settings) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: settings.contraceptionStartDate ?? now,
      firstDate: DateTime(now.year - 50),
      lastDate: now,
      helpText: context.l10n.settingsClinicalContraceptionStartHelp,
    );
    if (picked != null) {
      await settings.setContraception(settings.contraceptionMethod,
          startDate: picked);
    }
  }

  /// Diagnoses already given by a clinician. A multi-select, so it commits on
  /// Save rather than on each tap — unlike every single-select dialog here,
  /// which commits on the tap that also closes it.
  Future<void> _editDiagnoses(
      BuildContext context, SettingsProvider settings) async {
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _DiagnosesDialog(initial: settings.knownDiagnoses),
    );
    if (picked != null) await settings.setKnownDiagnoses(picked);
  }

  /// Breastfeeding. THREE states, and the third is not decoration: null means
  /// nobody asked, and the doctor report must not print "no" on its behalf.
  Future<void> _pickBreastfeeding(
      BuildContext context, SettingsProvider settings) async {
    final l10n = context.l10n;
    final picked = await showDialog<_Tristate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.settingsClinicalBreastfeedingTitle),
        children: [
          RadioGroup<_Tristate>(
            groupValue: _Tristate.of(settings.breastfeeding),
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile(
                  value: _Tristate.yes,
                  title: Text(l10n.settingsClinicalBreastfeedingYes),
                ),
                RadioListTile(
                  value: _Tristate.no,
                  title: Text(l10n.settingsClinicalBreastfeedingNo),
                ),
                RadioListTile(
                  value: _Tristate.unknown,
                  title: Text(l10n.settingsClinicalContraceptionNotAsked),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) {
      await settings.setBreastfeeding(picked.value,
          since: settings.breastfeedingSince);
    }
  }

  Future<void> _pickBreastfeedingSince(
      BuildContext context, SettingsProvider settings) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: settings.breastfeedingSince ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      helpText: context.l10n.settingsClinicalBreastfeedingSinceHelp,
    );
    if (picked != null) {
      await settings.setBreastfeeding(true, since: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final premium = context.watch<PremiumProvider>();
    // Nullable read: `AuthProvider` is absent from several settings test
    // harnesses, and its absence means the same thing a signed-out user does.
    final uid = context.watch<AuthProvider?>()?.user?.uid;
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      bottomNavigationBar: const SafeArea(child: AdBanner()),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          const AccountSection(),
          // Beside the identity row, because this is the rest of "who I am".
          //
          // Every row CHOOSES a value, so every row carries a `SettingsValue`
          // and opens a picker — no chevrons here (see the grammar note on this
          // class). All four are unanswered until the user answers them: the
          // profile is skippable and nothing invents a stand-in.
          //
          // The rows are direct `SettingsGroup` children on purpose; wrapping
          // them in a `Column` would hand the group one child and silently lose
          // the hairlines between them (account_section.dart:613-620).
          SettingsGroup(
            title: l10n.settingsSectionProfile,
            children: [
              ListTile(
                leading: const TrackArt(path: kDobArt),
                title: Text(l10n.settingsProfileDobTitle),
                // A full date reads long ("Monday, September 15, 2001"), and a
                // `ListTile` hands its trailing widget the intrinsic width it
                // asks for. Unbounded, that starves the title on a 360dp phone
                // — the width class of bug this project has already shipped
                // once (see the FilledButton-in-a-Row note in CLAUDE.md, found
                // on a device because tests default to an 800x600 surface).
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: SettingsValue(
                    settings.dateOfBirth == null
                        ? l10n.settingsProfileNotSet
                        : MaterialLocalizations.of(context)
                            .formatFullDate(settings.dateOfBirth!),
                  ),
                ),
                onTap: () => _pickDateOfBirth(context, settings),
              ),
              ListTile(
                leading: const TrackArt(path: kHeightArt),
                title: Text(l10n.settingsProfileHeightTitle),
                trailing: SettingsValue(
                  settings.heightCm == null
                      ? l10n.settingsProfileNotSet
                      : _heightLabel(
                          context, settings.heightCm!, settings.weightUnit),
                ),
                onTap: () => _editHeight(context, settings),
              ),
              ListTile(
                leading: const TrackArt(path: kWeightArt),
                title: Text(l10n.settingsProfileWeightTitle),
                // The subtitle is load-bearing, not decoration: this is NOT the
                // weight the day editor logs, and two fields called "Weight"
                // would read as one.
                subtitle: Text(l10n.settingsProfileWeightSubtitle),
                trailing: SettingsValue(
                  settings.profileWeightKg == null
                      ? l10n.settingsProfileNotSet
                      : _weightLabel(
                          settings.profileWeightKg!, settings.weightUnit),
                ),
                onTap: () => _editProfileWeight(context, settings),
              ),
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: Text(l10n.settingsProfileMenarcheTitle),
                trailing: SettingsValue(
                  settings.menarcheAge == null
                      ? l10n.settingsProfileNotSet
                      : '${settings.menarcheAge} '
                          '${l10n.settingsProfileUnitYears}',
                ),
                onTap: () => _editMenarcheAge(context, settings),
              ),
            ],
          ),
          // Health context (Tier 1). Ongoing clinical state rather than
          // anything that happens on a day, which is why it lives in settings
          // and not the day editor.
          //
          // Every row here distinguishes "never asked" from a real answer. The
          // contraception row is the one with teeth: an ovulation-suppressing
          // method removes the fertile window app-wide, so the row says so
          // rather than letting an estimate disappear unexplained.
          SettingsGroup(
            title: l10n.settingsSectionClinical,
            children: [
              ListTile(
                leading: const TrackArt(path: kContraceptionArt),
                title: Text(l10n.settingsClinicalContraceptionTitle),
                subtitle: settings.suppressesOvulation
                    ? Text(l10n.settingsClinicalFertilityPaused)
                    : null,
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 168),
                  child: SettingsValue(
                    _optionLabel(kContraceptionOptions,
                            settings.contraceptionMethod) ??
                        l10n.settingsClinicalContraceptionNotAsked,
                  ),
                ),
                onTap: () => _pickContraception(context, settings),
              ),
              // Only meaningful once a method other than "none" is recorded —
              // a start date for no contraception says nothing.
              if (settings.contraceptionMethod != null &&
                  settings.contraceptionMethod != kContraceptionNone)
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: Text(l10n.settingsClinicalContraceptionStartTitle),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: SettingsValue(
                      settings.contraceptionStartDate == null
                          ? l10n.settingsProfileNotSet
                          : MaterialLocalizations.of(context)
                              .formatFullDate(settings.contraceptionStartDate!),
                    ),
                  ),
                  onTap: () => _pickContraceptionStart(context, settings),
                ),
              ListTile(
                leading: const TrackArt(path: kDiagnosesArt),
                title: Text(l10n.settingsClinicalDiagnosesTitle),
                subtitle: Text(l10n.settingsClinicalDiagnosesSubtitle),
                trailing: SettingsValue(
                  settings.knownDiagnoses.isEmpty
                      ? l10n.settingsClinicalDiagnosesNone
                      : l10n.settingsClinicalDiagnosesCount(
                          settings.knownDiagnoses.length),
                ),
                onTap: () => _editDiagnoses(context, settings),
              ),
              ListTile(
                leading: const TrackArt(path: kBreastfeedingArt),
                title: Text(l10n.settingsClinicalBreastfeedingTitle),
                trailing: SettingsValue(switch (settings.breastfeeding) {
                  true => l10n.settingsClinicalBreastfeedingYes,
                  false => l10n.settingsClinicalBreastfeedingNo,
                  null => l10n.settingsClinicalContraceptionNotAsked,
                }),
                onTap: () => _pickBreastfeeding(context, settings),
              ),
              if (settings.breastfeeding == true)
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: Text(l10n.settingsClinicalBreastfeedingSinceTitle),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: SettingsValue(
                      settings.breastfeedingSince == null
                          ? l10n.settingsProfileNotSet
                          : MaterialLocalizations.of(context)
                              .formatFullDate(settings.breastfeedingSince!),
                    ),
                  ),
                  onTap: () => _pickBreastfeedingSince(context, settings),
                ),
            ],
          ),
          // Outside the card, as a caption. The app collects this to give the
          // user better context and a report they can hand over — it is not a
          // screening tool, and this is the only place that says so in the
          // same glance as the questions.
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(
              l10n.settingsClinicalNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
          SettingsGroup(
            title: l10n.settingsSectionGoal,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text("What I'm using LunarFlow for"),
                trailing: SettingsValue(_modeLabel(context, settings.mode)),
                onTap: () => _pickMode(context, settings),
              ),
              ListTile(
                leading: const TrackArt(path: kPregnancyArt),
                title: Text(l10n.settingsPregnancyTitle),
                subtitle: Text(settings.isPregnant
                    ? l10n.settingsPregnancyOn
                    : l10n.settingsPregnancyOff),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PregnancyScreen()),
                ),
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.settingsSectionCycleDefaults,
            children: [
              _StepperTile(
                art: kCycleLengthArt,
                title: l10n.settingsAvgCycleLength,
                suffix: l10n.settingsUnitDays,
                value: settings.cycleLength,
                min: 21,
                max: 35,
                onChanged: settings.setCycleLength,
              ),
              _StepperTile(
                art: kPeriodLengthArt,
                title: l10n.settingsAvgPeriodLength,
                suffix: l10n.settingsUnitDays,
                value: settings.periodLength,
                min: 2,
                max: 10,
                onChanged: settings.setPeriodLength,
              ),
            ],
          ),
          SettingsGroup(
            // No ARB key for this heading yet; the screen is otherwise
            // localized, so this is the one string to move into `app_en.arb`
            // when the i18n initiative lands.
            title: 'Tracking',
            children: [
              ListTile(
                leading: const Icon(Icons.tune),
                title: Text(l10n.settingsTrackingTitle),
                subtitle: Text(
                  '${settings.enabledCategories.length} of '
                  '${kTrackingCategories.length} sections on',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const TrackingCategoriesScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.medication_outlined),
                title: Text(l10n.settingsMedicationsTitle),
                subtitle: Text(l10n.settingsMedicationsSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MedicationsScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(l10n.settingsRemindersTitle),
                subtitle: Text(l10n.settingsRemindersSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RemindersScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.scale_outlined),
                title: const Text('Weight unit'),
                trailing: SettingsValue(
                  settings.weightUnit == kWeightUnitLb
                      ? 'Pounds (lb)'
                      : 'Kilograms (kg)',
                ),
                onTap: () => _pickWeightUnit(context),
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.settingsSectionHealth,
            children: [
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(l10n.settingsHealthImportTitle),
                subtitle: Text(l10n.settingsHealthImportSubtitle),
                trailing: const Icon(Icons.download_outlined),
                onTap: () => _importHealth(context),
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.settingsSectionAppearance,
            children: [
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: Text(l10n.settingsSectionAppearance),
                trailing:
                    SettingsValue(_themeLabel(context, settings.themeMode)),
                onTap: () => _pickTheme(context, settings),
              ),
              ListTile(
                leading: const Icon(Icons.language_outlined),
                title: Text(l10n.settingsLanguageTitle),
                trailing: SettingsValue(settings.language == 'system'
                    ? l10n.settingsLanguageSystem
                    : _localeName(settings.language)),
                onTap: () => _pickLanguage(context, settings),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.diversity_3_outlined),
                title: Text(l10n.settingsGenderNeutralTitle),
                subtitle: Text(l10n.settingsGenderNeutralSubtitle),
                value: settings.genderNeutralLanguage,
                onChanged: settings.setGenderNeutralLanguage,
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.settingsSectionBackup,
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: Text(l10n.settingsBackupExportTitle),
                subtitle: Text(l10n.settingsBackupExportSubtitle),
                trailing: const Icon(Icons.ios_share),
                onTap: () => _exportBackup(context),
              ),
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: Text(l10n.settingsBackupRestoreTitle),
                subtitle: Text(l10n.settingsBackupRestoreSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _restoreBackup(context),
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.settingsSectionPrivacy,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: Text(l10n.settingsAppLockTitle),
                subtitle: Text(l10n.settingsAppLockSubtitle),
                value: settings.appLockEnabled,
                onChanged: (v) async {
                  if (v) {
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) => const SetupLockScreen()),
                    );
                  } else {
                    await LockService.clearPin();
                    await settings.setAppLock(false);
                  }
                },
              ),
              // Photo descriptions. Off unless the CURRENT account turned it on
              // — `analysisConsentUid` holds a uid, not a bool, so another
              // account's consent on this device reads as off here and cannot
              // be withdrawn from the wrong account either.
              //
              // Rendered only when a key was compiled in: with no backend the
              // switch would toggle a preference that does nothing, which is
              // worse than its absence.
              if (analysisAvailable)
                SwitchListTile(
                  key: const Key('settings.imageAnalysis'),
                  secondary: const Icon(Icons.auto_awesome_outlined),
                  title: Text(l10n.settingsPhotoDescriptionsTitle),
                  subtitle: Text(l10n.settingsPhotoDescriptionsSubtitle),
                  value: uid != null && settings.analysisConsentUid == uid,
                  onChanged: uid == null
                      ? null
                      : (v) async {
                          if (v) {
                            await settings.setAnalysisConsent(uid);
                          } else {
                            await settings.clearAnalysisConsent();
                          }
                        },
                ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text(
                  l10n.settingsDeleteTitle,
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: Text(l10n.settingsDeleteSubtitle),
                onTap: () => _confirmDeleteAll(context),
              ),
            ],
          ),
          SettingsGroup(
            title: l10n.settingsSectionAbout,
            children: [
              ListTile(
                leading: Icon(
                  premium.isPremium
                      ? Icons.workspace_premium
                      : Icons.workspace_premium_outlined,
                ),
                title: Text(premium.isPremium
                    ? l10n.settingsPremiumActiveTitle
                    : l10n.settingsPremiumInactiveTitle),
                subtitle: Text(premium.isPremium
                    ? l10n.settingsPremiumActiveSubtitle
                    : l10n.settingsPremiumInactiveSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: SettingsFinePrint(null),
          ),
        ],
      ),
    );
  }
}

/// Prompts for a backup passphrase. With [confirm], requires a matching second
/// field (export); otherwise a single field (restore). Returns the passphrase,
/// or null if cancelled. The passphrase is never persisted.
class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({this.title, this.action, this.confirm = false});
  final String? title;
  final String? action;
  final bool confirm;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pass.text;
    if (p.length < 6) {
      setState(() => _error = context.l10n.backupPassphraseTooShort);
      return;
    }
    if (widget.confirm && p != _confirm.text) {
      setState(() => _error = context.l10n.backupPassphraseMismatch);
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title ?? l10n.backupPassphraseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.confirm) ...[
            Text(l10n.backupPassphraseBody,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _pass,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.backupPassphraseHint,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l10n.backupPassphraseConfirmHint,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.action ?? l10n.backupActionBackUp),
        ),
      ],
    );
  }
}

/// What a [_MeasureDialog] returns.
///
/// A null [value] means the user CLEARED the field (submitted it blank); a null
/// RESULT from `showDialog` means they cancelled. Collapsing the two would make
/// Cancel erase a stored answer — which is why this wrapper exists instead of
/// returning a bare `double?`.
class _MeasureResult {
  const _MeasureResult(this.value);

  /// The canonical-unit value to store, or null to clear the field.
  final double? value;
}

/// One numeric profile measurement (height, current weight) behind a dialog.
///
/// The refusal contract is the point of this widget: [parse] returns null for
/// anything outside the plausible range — checked AFTER unit conversion, inside
/// the parser — and the dialog then shows [rangeError] inline and STAYS OPEN
/// with the typed text intact. Nothing is written and nothing is clamped, the
/// same posture as `DayEntryFormState.save()` returning false.
class _MeasureDialog extends StatefulWidget {
  const _MeasureDialog({
    required this.fieldKey,
    required this.title,
    required this.suffix,
    required this.initial,
    required this.keyboardType,
    required this.parse,
    required this.rangeError,
  });

  final Key fieldKey;
  final String title;

  /// Unit drawn inside the field, so the value itself never carries one.
  final String suffix;
  final String initial;
  final TextInputType keyboardType;

  /// Parses the typed text into the CANONICAL unit, or null to refuse it.
  final double? Function(String) parse;

  /// Shown when [parse] refuses. Carries both bounds already formatted for the
  /// user's unit, marks and suffix included.
  final String rangeError;

  @override
  State<_MeasureDialog> createState() => _MeasureDialogState();
}

class _MeasureDialogState extends State<_MeasureDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    // Blank is a CLEAR, not a refusal — the setters take a nullable argument so
    // one entry point both sets and unanswers. Only non-blank text can be out
    // of range, exactly as `DayEntryFormState.save()` guards its parse.
    if (raw.isEmpty) {
      Navigator.pop(context, const _MeasureResult(null));
      return;
    }
    final parsed = widget.parse(raw);
    if (parsed == null) {
      setState(() => _error = widget.rangeError);
      return;
    }
    Navigator.pop(context, _MeasureResult(parsed));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextFormField(
        key: widget.fieldKey,
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          suffixText: widget.suffix,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        onFieldSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.actionSave)),
      ],
    );
  }
}

/// Plausible bounds for an age at menarche, and where the stepper starts when
/// the question has never been answered. The start is an interaction seed, NOT
/// a stored default: the row reads "Not set" until the user taps Save.
const int _kMinMenarcheAge = 8;
const int _kMaxMenarcheAge = 20;
const int _kMenarcheSeed = 13;

/// Age at first period, as a stepper behind a dialog.
///
/// Bounds are enforced by DISABLING the button, never by clamping a value the
/// user asked for — the same rule `_StepperTile` follows for the cycle
/// defaults, and the same rule the product timer's caps follow.
/// The three states of a nullable bool, as something a `RadioGroup` can hold.
/// A `RadioGroup<bool?>` cannot express "unanswered" as a distinct option — the
/// null group value already means "nothing selected" — so the third state needs
/// a value of its own.
enum _Tristate {
  yes(true),
  no(false),
  unknown(null);

  const _Tristate(this.value);
  final bool? value;

  static _Tristate of(bool? v) => switch (v) {
        true => _Tristate.yes,
        false => _Tristate.no,
        null => _Tristate.unknown,
      };
}

/// Diagnoses a clinician has already given. A MULTI-select, so unlike every
/// single-select dialog on this screen it commits on Save rather than on the
/// tap that closes it — otherwise each tick would be a separate write, and a
/// separate sync push.
class _DiagnosesDialog extends StatefulWidget {
  const _DiagnosesDialog({required this.initial});

  final Set<String> initial;

  @override
  State<_DiagnosesDialog> createState() => _DiagnosesDialogState();
}

class _DiagnosesDialogState extends State<_DiagnosesDialog> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.settingsClinicalDiagnosesTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final o in kDiagnosisOptions)
                CheckboxListTile(
                  value: _selected.contains(o.key),
                  title: Text(o.label),
                  // Control forced to the TRAILING edge so `secondary` lands at
                  // the leading one. Left as `platform` the checkbox takes the
                  // leading slot and the mark is pushed to the right, which
                  // would read as a second control rather than as a label.
                  controlAffinity: ListTileControlAffinity.trailing,
                  secondary: kDiagnosisArt[o.key] == null
                      ? null
                      : TrackArt(path: kDiagnosisArt[o.key]!),
                  onChanged: (on) => setState(() =>
                      on == true ? _selected.add(o.key) : _selected.remove(o.key)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          // An EMPTY set is a real answer ("asked, none"), so it is returned
          // rather than treated as a cancel.
          onPressed: () => Navigator.pop(context, _selected),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}

class _MenarcheDialog extends StatefulWidget {
  const _MenarcheDialog({this.initial});

  final int? initial;

  @override
  State<_MenarcheDialog> createState() => _MenarcheDialogState();
}

class _MenarcheDialogState extends State<_MenarcheDialog> {
  late int _value = widget.initial ?? _kMenarcheSeed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.settingsProfileMenarcheTitle),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const Key('settings.profile.menarcheMinus'),
            icon: const Icon(Icons.remove),
            onPressed: _value > _kMinMenarcheAge
                ? () => setState(() => _value--)
                : null,
          ),
          Text(
            '$_value ${l10n.settingsProfileUnitYears}',
            style: theme.textTheme.titleMedium,
          ),
          IconButton(
            key: const Key('settings.profile.menarchePlus'),
            icon: const Icon(Icons.add),
            onPressed: _value < _kMaxMenarcheAge
                ? () => setState(() => _value++)
                : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _value),
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}

/// A cycle/period default, shown as one row with a compact stepper pill on the
/// right. The pill keeps the ± controls (they are the only way to change these
/// numbers) while reading as the mock's single right-aligned value.
///
/// Takes an ASSET PATH rather than an [IconData] because both of its two call
/// sites are illustrated; a nullable glyph fallback would be dead configuration
/// from the day it was written. Restore one if a third cycle default ever lands
/// without art — do not reach for a placeholder mark, which would say something
/// wrong rather than nothing.
class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.art,
    required this.title,
    required this.suffix,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String art;
  final String title;
  final String suffix;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: TrackArt(path: art),
      title: Text(title),
      trailing: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: const Icon(Icons.remove),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Text(
              '$value $suffix',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              icon: const Icon(Icons.add),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}
