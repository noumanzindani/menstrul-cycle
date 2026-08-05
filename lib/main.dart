import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
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
import 'services/firebase_availability.dart';
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
  // The ONE place this app decides whether Firebase is usable -- see
  // [initializeFirebase] and `FirebaseAvailability`'s doc comment. Everything
  // downstream (AuthProvider's construction, AccountSection's notice) reads
  // this single value; nothing re-derives it.
  final firebaseAvailable = await initializeFirebase();
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
  runApp(LunaTrackApp(database: db, firebaseAvailable: firebaseAvailable));
}

/// Initializes the default Firebase app, tolerating a build with no native
/// config (no `google-services.json` / `GoogleService-Info.plist`, and no
/// generated `lib/firebase_options.dart` -- neither exists at this HEAD; a
/// `flutterfire configure` pass to add them is tracked separately) and any
/// other runtime failure to reach Firebase. Returns whether it succeeded.
///
/// Deliberately calls the NO-OPTIONS form. Passing no `name`/`options` is what
/// lets this survive both today (no options file to import -- importing one
/// that doesn't exist would break the build outright) and after
/// `firebase_options.dart` lands, without this function needing to change:
/// `Firebase.initializeApp` forwards straight to the platform channel with
/// `options: null` (`firebase_core-4.13.0/lib/src/firebase.dart:79-82`), which
/// on Android falls back to reading the native `google-services.json` --
/// exactly the case that throws `[core/no-app]` when that file is absent,
/// which is the failure this function exists to survive rather than prevent.
///
/// This is the ONLY place in the app that calls `Firebase.initializeApp()`.
/// Every other Firebase touch point (`FirebaseAuthService`, `lunaFirestore()`,
/// `SyncTrigger.setUser`) either runs after this has already decided
/// [FirebaseAvailability], or independently tolerates `Firebase.app()`
/// throwing on its own (see their doc comments) -- this function does not
/// change or duplicate either of those existing guards.
Future<bool> initializeFirebase() async {
  try {
    await Firebase.initializeApp();
    return true;
  } catch (_) {
    return false;
  }
}

class LunaTrackApp extends StatelessWidget {
  const LunaTrackApp({
    super.key,
    required this.database,
    this.authService,
    this.syncTrigger,
    this.firebaseAvailable = true,
  });

  final AppDatabase database;

  /// Overridable for tests: [FirebaseAuthService] touches `FirebaseAuth.instance`
  /// in its constructor, which throws without a real Firebase app. Widget tests
  /// that pump this widget directly (see `test/widget_test.dart`) inject a fake
  /// here instead.
  final AuthService? authService;

  /// Whether `main()`'s `initializeFirebase()` succeeded -- the single fact
  /// this widget bases its degrade-gracefully behaviour on. See
  /// `FirebaseAvailability`'s doc comment for why this must not be re-derived
  /// anywhere else.
  ///
  /// Defaults to `true` because this widget cannot detect Firebase's real
  /// state on its own (only `main()` calls `Firebase.initializeApp()`); it can
  /// only be told. Most tests inject [authService] directly and never reach
  /// the `FirebaseAuthService()` this flag would otherwise gate, so the
  /// default is unobserved by them. Tests that specifically exercise the
  /// unavailable path set this explicitly (see
  /// `test/firebase_unavailable_test.dart`).
  final bool firebaseAvailable;

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
        // Read by `AccountSection` to show "Cloud sync unavailable on this
        // device" instead of the normal sync on/off tile -- the SAME value
        // that picks the AuthProvider's service just below, not a second
        // derivation of it.
        Provider<FirebaseAvailability>.value(
          value: FirebaseAvailability(firebaseAvailable),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            authService ??
                (firebaseAvailable
                    ? FirebaseAuthService()
                    : const UnavailableAuthService()),
          ),
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
            // `_LockRouteGuard` wraps `MaterialApp` — deliberately an
            // ANCESTOR of it, not a descendant — so its `WidgetsBindingObserver`
            // registers with the binding before `WidgetsApp`'s does. See its
            // doc comment for why that ordering is the whole fix for the
            // Android back button.
            return _LockRouteGuard(
              builder: (context, lockNotifier) => MaterialApp(
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
                // The app lock goes HERE, not inside `home:`. `builder` wraps
                // the Navigator, so `AppLock` covers every route — bottom
                // sheets, dialogs, pushed screens, snackbars — instead of only
                // the contents of the home route. Returning `LockScreen` from
                // `AppGate.build` (what this replaces) left every one of those
                // rendering on top of the lock. See `screens/lock/app_lock.dart`.
                //
                // Goes through `AppLock.wrap` — the SAME function every
                // widget-test harness that builds a lock calls — passing the
                // `lockNotifier` `_LockRouteGuard` owns as `wrap`'s optional
                // third argument. Harnesses that don't need back-button
                // coverage call `wrap` with just the first two and get `null`,
                // which `AppLock` treats as "skip the write"; this call is not
                // a second, hand-built construction of `AppLock` that merely
                // resembles what `wrap` does.
                builder: (context, child) =>
                    AppLock.wrap(context, child, lockNotifier),
                home: const HomeWidgetSync(child: AppGate()),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// An observer registered ABOVE `MaterialApp`, purely so its `didPopRoute` is
/// consulted before `WidgetsApp`'s own.
///
/// `WidgetsBinding.handlePopRoute` walks its observers in REGISTRATION order
/// and stops at the first one that returns `true` (see the doc comment at
/// `widgets/binding.dart:949` — it explicitly is NOT newest-first).
/// `_WidgetsAppState.initState` (inside `MaterialApp`) registers itself
/// before any of its descendants ever mount — `AppLock` included, since it
/// only exists inside `MaterialApp.builder`. So the only way to get first
/// refusal on the Android back button while the app lock is up is to
/// register an observer somewhere that mounts BEFORE `MaterialApp` does,
/// i.e. an ancestor of it. This widget is that ancestor.
///
/// It reads "is locked" from a single [LockFlag] it owns and hands down to
/// [builder] — the SAME flag [AppLock] writes to, both from `build` and, as
/// of the fix this class's `didPopRoute` doc describes, from the moment the
/// lock engages (see `AppLock.lockNotifier` and `_AppLockState._lock`). That
/// is the one and only place "is the lock up" is computed; this widget never
/// re-derives it.
class _LockRouteGuard extends StatefulWidget {
  const _LockRouteGuard({required this.builder});

  final Widget Function(BuildContext context, LockFlag lockNotifier) builder;

  @override
  State<_LockRouteGuard> createState() => _LockRouteGuardState();
}

class _LockRouteGuardState extends State<_LockRouteGuard>
    with WidgetsBindingObserver {
  final LockFlag _lockNotifier = LockFlag();

  @override
  void initState() {
    super.initState();
    // Must happen here, in an ancestor of `MaterialApp` — see the class doc
    // comment for why the registration ORDER is the entire point.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Swallows the Android back BUTTON while the lock is up. The app's
  /// Navigator is still there behind the lock, just offstage, and the system
  /// back button would otherwise reach and pop its hidden route stack —
  /// navigating an app the presser is not allowed to see, only deferred
  /// (not blocked) by the muted `TickerMode` until the lock next lifts.
  ///
  /// What this does NOT cover: Android 13+'s predictive-back GESTURE. The app
  /// targets SDK 36 (`android/app/build.gradle.kts`) with no
  /// `android:enableOnBackInvokedCallback="false"` opt-out
  /// (`AndroidManifest.xml`), and this class implements only [didPopRoute] —
  /// not `handleStartBackGesture`/`handleCommitBackGesture`
  /// (`widgets/binding.dart:993+`), which is the callback pair the predictive
  /// gesture actually drives. `_WidgetsAppState` derives
  /// `SystemNavigator.setFrameworkHandlesBack` from the Navigator's own route
  /// stack, independent of this observer, so on a device where the predictive
  /// gesture is live, a swipe-back while locked may bypass this guard
  /// entirely. SUSPECTED, not confirmed here — it needs a real API 36 device
  /// to observe, and is explicitly out of scope for this fix (the hardware/
  /// 3-button back button — [didPopRoute] — is what regressed and is what
  /// this class fixes).
  @override
  Future<bool> didPopRoute() async => _lockNotifier.value;

  @override
  Widget build(BuildContext context) => widget.builder(context, _lockNotifier);
}
