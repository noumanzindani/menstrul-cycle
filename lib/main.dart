import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/daily_log_repository.dart';
import 'data/reminder_repository.dart';
import 'data/settings_repository.dart';
import 'db/database.dart';
import 'models/prediction.dart';
import 'providers/log_provider.dart';
import 'providers/premium_provider.dart';
import 'providers/reminder_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/app_gate.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';
import 'services/prediction_service.dart';
import 'theme/app_theme.dart';

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
              PremiumProvider(SettingsRepository(database))..load(),
        ),
        // Derived, recomputed whenever logs or settings change.
        ProxyProvider2<LogProvider, SettingsProvider, PredictionResult>(
          update: (_, log, settings, _) => PredictionService.predict(
            log.cycles,
            fallbackCycleLength: settings.cycleLength,
            fallbackPeriodLength: settings.periodLength,
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
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'LunaTrack',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: const AppGate(),
          );
        },
      ),
    );
  }
}
