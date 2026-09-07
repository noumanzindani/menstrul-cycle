import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../common/l10n.dart';
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
          SettingsGroup(
            title: l10n.settingsSectionGoal,
            children: [
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text("What I'm using LunaTrack for"),
                trailing: SettingsValue(_modeLabel(context, settings.mode)),
                onTap: () => _pickMode(context, settings),
              ),
              ListTile(
                leading: const Icon(Icons.pregnant_woman_outlined),
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
                icon: Icons.event_repeat_outlined,
                title: l10n.settingsAvgCycleLength,
                suffix: l10n.settingsUnitDays,
                value: settings.cycleLength,
                min: 21,
                max: 35,
                onChanged: settings.setCycleLength,
              ),
              _StepperTile(
                icon: Icons.water_drop_outlined,
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

/// A cycle/period default, shown as one row with a compact stepper pill on the
/// right. The pill keeps the ± controls (they are the only way to change these
/// numbers) while reading as the mock's single right-aligned value.
class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.icon,
    required this.title,
    required this.suffix,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
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
      leading: Icon(icon),
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
