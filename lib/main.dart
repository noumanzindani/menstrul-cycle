import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/daily_log_repository.dart';
import 'data/medication_repository.dart';
import 'data/reminder_repository.dart';
import 'data/settings_repository.dart';
import 'common/l10n.dart';
import 'db/database.dart';
import 'models/insights.dart';
import 'models/month_ring.dart';
import 'models/prediction.dart';
import 'providers/auth_provider.dart';
import 'providers/log_provider.dart';
import 'providers/medication_provider.dart';
import 'providers/premium_provider.dart';
import 'providers/reminder_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/app_gate.dart';
import 'screens/lock/app_lock.dart';
import 'services/ad_service.dart';
import 'services/auth_service.dart';
import 'services/bbt_service.dart';
import 'services/cycle_check_in.dart';
import 'services/insights_narrator.dart';
import 'services/month_ring_builder.dart';
import 'services/notification_actions.dart';
import 'services/notification_service.dart';
import 'services/prediction_service.dart';
import 'services/sync_trigger.dart';
import 'theme/app_theme.dart';
import 'widgets/home_widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Register the notification action handlers. The background one runs the
  // one-tap check-in write in a killed-app isolate; the foreground one handles a
  // tap while the app is open. Both route through handleCheckInResponse.
  await NotificationService.init(
    onForegroundResponse: handleCheckInResponse,
    onBackgroundResponse: checkInNotificationBackgroundHandler,
  );
  // Ads init is fire-and-forget: the UI must not block on the network.
  unawaited(AdService.instance.initialize());
  final db = AppDatabase();
  runApp(LunaTrackApp(database: db));
}

class LunaTrackApp extends StatelessWidget {
  const LunaTrackApp({
    super.key,
    required this.database,
    this.authService,
    this.syncTrigger,
  });

  final AppDatabase database;

  /// Overridable for tests: [FirebaseAuthService] touches `FirebaseAuth.instance`
  /// in its constructor, which throws without a real Firebase app. Widget tests
  /// that pump this widget directly (see `test/widget_test.dart`) inject a fake
  /// here instead.
  final AuthService? authService;

  /// Overridable for tests, for the same class of reason: the default
  /// [SyncTrigger]'s claim-decision storage is `flutter_secure_storage`, whose
  /// platform channel has no handler under `flutter_tester` (it hangs rather
  /// than throwing). Injecting the whole trigger — rather than adding a
  /// storage parameter here — also lets a test observe [SyncTrigger] calls,
  /// which is how `test/sync_wiring_test.dart` proves the debounced-write
  /// provider below actually fires.
  final SyncTrigger? syncTrigger;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authService ?? FirebaseAuthService()),
        ),
        ChangeNotifierProvider(
          create: (_) => syncTrigger ?? SyncTrigger(database),
        ),
        ChangeNotifierProvider(
          create: (_) => LogProvider(DailyLogRepository(database))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(SettingsRepository(database))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => ReminderProvider(ReminderRepository(database))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              MedicationProvider(MedicationRepository(database))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              PremiumProvider(SettingsRepository(database))..load(),
        ),
        // Derived, recomputed whenever logs or settings change.
        ProxyProvider2<LogProvider, SettingsProvider, PredictionResult>(
          // The whole recompute (incl. the pregnancy/perimenopause suppressions
          // and symptothermal corroboration) lives in predictFromLogs, shared
          // with the background CheckInWriter so the two can never diverge.
          update: (_, log, settings, _) => PredictionService.predictFromLogs(
            logs: log.logs,
            mode: settings.mode,
            cycleLength: settings.cycleLength,
            periodLength: settings.periodLength,
          ),
        ),
        // Multi-month forecast: projects future periods from the user's entered
        // cycle length, anchored to their most recent period start.
        ProxyProvider2<PredictionResult, SettingsProvider,
            List<PredictedPeriod>>(
          update: (_, prediction, settings, _) {
            final anchor = prediction.lastPeriodStart;
            if (anchor == null) return const <PredictedPeriod>[];
            return PredictionService.projectFuturePeriods(
              anchorStart: anchor,
              cycleLength: settings.cycleLength,
              periodLength: settings.periodLength,
              count: 12,
            );
          },
        ),
        // Plain-language "Your patterns" narratives over the user's own data —
        // shared by Home (top highlight) and Insights. Pure/on-device.
        ProxyProvider2<LogProvider, PredictionResult, List<CycleNarrative>>(
          update: (_, log, prediction, _) => InsightsNarrator.narrate(
            cycles: log.cycles,
            logs: log.logs,
            currentCycleDay: prediction.cycleDay,
            currentPhase: prediction.currentPhase,
          ),
        ),
        // Retrospective ovulation confirmation from this cycle's BBT (Conceive
        // Home). Awareness only — a thermal shift means ovulation likely already
        // happened; never a "safe day".
        ProxyProvider2<LogProvider, PredictionResult, OvulationConfirmation>(
          update: (_, log, prediction, _) => OvulationConfirmation(
            BbtService.shiftInCurrentCycle(
                log.logs, prediction.lastPeriodStart),
          ),
        ),
        // Home check-in: should we ask "Did your period start?" / "Has it
        // ended?" today. At most once per day — a logged flow (bleeding OR an
        // explicit "no bleeding") answers it. Period timing only, no fertility.
        ProxyProvider2<LogProvider, PredictionResult, CheckInPrompt>(
          update: (_, log, prediction, _) => CycleCheckInService.evaluate(
            logs: log.logs,
            prediction: prediction,
            today: DateTime.now(),
          ),
        ),
        // Home month ring: one segment per day of the current month, coloured by
        // role. Fertility colouring runs through the confidence-gated band, so
        // it's suppressed below medium confidence / in perimenopause — never
        // implying a "safe" day.
        ProxyProvider2<LogProvider, PredictionResult, MonthRingData>(
          update: (_, log, prediction, _) => MonthRingBuilder.build(
            logs: log.logs,
            prediction: prediction,
            today: DateTime.now(),
          ),
        ),
        // Local writes schedule a debounced sync. Returns void because nothing
        // consumes it; it exists purely for the side effect of reacting to a
        // LogProvider change.
        //
        // `lazy: false` is load-bearing, not a tweak: a lazy provider builds
        // its value on first read, and nothing anywhere reads a `void`, so
        // `update` was NEVER called and local edits never triggered a sync at
        // all (they rode along on the next resume or launch). Sync is still
        // gated: `SyncTrigger.setUser` sets the claim gate before its first
        // `await`, and the debounce is 2 seconds, so the eager first call
        // cannot slip a push in ahead of the claim decision.
        ProxyProvider2<LogProvider, SyncTrigger, void>(
          lazy: false,
          update: (_, log, trigger, _) => trigger.scheduleSync(),
        ),
      ],
      child: Consumer2<AuthProvider, SyncTrigger>(
        builder: (context, auth, trigger, child) {
          // Fire-and-forget: the UI never blocks on sync. A null uid tears sync
          // down and leaves local data alone.
          trigger.setUser(auth.user?.uid);
          return child!;
        },
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            return MaterialApp(
              onGenerateTitle: (context) => context.l10n.appTitle,
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: settings.themeMode,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: settings.language == 'system'
                  ? null
                  : Locale(settings.language),
              // The app lock goes HERE, not inside `home:`. `builder` wraps the
              // Navigator, so `AppLock` covers every route — bottom sheets,
              // dialogs, pushed screens, snackbars — instead of only the
              // contents of the home route. Returning `LockScreen` from
              // `AppGate.build` (what this replaces) left every one of those
              // rendering on top of the lock. See `screens/lock/app_lock.dart`.
              builder: AppLock.wrap,
              home: const HomeWidgetSync(child: AppGate()),
            );
          },
        ),
      ),
    );
  }
}
