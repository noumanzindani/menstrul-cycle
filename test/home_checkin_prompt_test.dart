import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/date_utils.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The Home dashboard surfaces a "Did your period start? / Has it ended?"
/// check-in and — critically — the one-tap negative records a confirmed
/// no-bleeding day (`flow = none`) for today. Period timing only, never "safe".
void main() {
  late AppDatabase db;
  late SettingsProvider settings;
  late LogProvider log;

  final cycles = [
    Cycle(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 5), lengthDays: 28),
    Cycle(start: DateTime(2026, 1, 29), end: DateTime(2026, 2, 2)),
  ];
  final prediction =
      PredictionService.predict(cycles, asOf: DateTime(2026, 1, 29));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    log = LogProvider(DailyLogRepository(db));
    await log.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, CheckInPrompt prompt) async {
    // Tall surface so the whole scrolling dashboard (incl. the month ring and
    // the trailing disclaimer) lays out and off-screen buttons stay tappable.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<LogProvider>.value(value: log),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<CycleNarrative>>.value(value: const []),
        Provider<OvulationConfirmation>.value(
            value: const OvulationConfirmation(null)),
        Provider<CheckInPrompt>.value(value: prompt),
        Provider<MonthRingData>.value(value: MonthRingData.empty(DateTime.now())),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('didItStart shows the start check-in, never says "safe"',
      (tester) async {
    await pump(tester, CheckInPrompt.didItStart);
    expect(find.text('Did your period start?'), findsOneWidget);
    expect(find.text('Not yet'), findsOneWidget);
    expect(find.text('Started — log it'), findsOneWidget);
    expect(find.textContaining('safe'), findsNothing);
    expect(find.textContaining('Safe'), findsNothing);
  });

  testWidgets('tapping "Not yet" records no bleeding (flow = none) for today',
      (tester) async {
    await pump(tester, CheckInPrompt.didItStart);
    final today = dateOnly(DateTime.now());
    expect(log.logForDate(today), isNull);

    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();

    expect(log.logForDate(today)?.flow, FlowIntensity.none);
  });

  testWidgets('hasItEnded shows the end check-in and "It ended" logs none',
      (tester) async {
    await pump(tester, CheckInPrompt.hasItEnded);
    expect(find.text('Are you still on your period?'), findsOneWidget);
    expect(find.text('It ended'), findsOneWidget);

    await tester.tap(find.text('It ended'));
    await tester.pumpAndSettle();

    final today = dateOnly(DateTime.now());
    expect(log.logForDate(today)?.flow, FlowIntensity.none);
  });

  testWidgets('no check-in card when the prompt is none', (tester) async {
    await pump(tester, CheckInPrompt.none);
    expect(find.text('Did your period start?'), findsNothing);
    expect(find.text('Are you still on your period?'), findsNothing);
  });
}
