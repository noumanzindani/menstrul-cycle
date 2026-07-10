import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/daily_log_repository.dart';
import 'data/medication_repository.dart';
import 'data/reminder_repository.dart';
import 'data/settings_repository.dart';
import 'common/l10n.dart';
import 'db/database.dart';
import 'models/cycle.dart';
import 'models/enums.dart';
import 'models/insights.dart';
import 'models/prediction.dart';
import 'providers/log_provider.dart';
import 'providers/medication_provider.dart';
import 'providers/premium_provider.dart';
import 'providers/reminder_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/app_gate.dart';
import 'services/ad_service.dart';
import 'services/bbt_service.dart';
import 'services/cycle_check_in.dart';
import 'services/insights_narrator.dart';
import 'services/notification_service.dart';
import 'services/prediction_service.dart';
import 'theme/app_theme.dart';
import 'widgets/home_widget_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  // Ads init is fire-and-forget: the UI must not block on the network.
  unawaited(AdService.instance.initialize());
  final db = AppDatabase();
  runApp(LunaTrackApp(database: db));
}

class LunaTrackApp extends StatelessWidget {
  const LunaTrackApp({super.key, required this.database});

  final AppDatabase database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: database),
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
          update: (_, log, settings, _) => PredictionService.predict(
            // Suppress all period/fertility predictions during pregnancy.
            settings.mode == TrackingMode.pregnancy
                ? const <Cycle>[]
                : log.cycles,
            fallbackCycleLength: settings.cycleLength,
            fallbackPeriodLength: settings.periodLength,
            // Perimenopause: erratic cycles → cap confidence to low, which
            // self-suppresses the ovulation marker + fertility band app-wide.
            capConfidenceToLow: settings.mode == TrackingMode.perimenopause,
            // Symptothermal: a positive/peak OPK near ovulation corroborates the
            // estimate and unlocks the fertility band one confidence notch.
            logs: settings.mode == TrackingMode.pregnancy
                ? const <DailyLog>[]
                : log.logs,
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
      ],
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
            home: const HomeWidgetSync(child: AppGate()),
          );
        },
      ),
    );
  }
}
