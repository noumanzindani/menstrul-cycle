import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/product_session_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/calendar/calendar_screen.dart';
import 'package:menstrul_track/screens/forecast/forecast_screen.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/month_ring_builder.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// Forecast left the bottom bar when the Assistant took index 2, so these two
/// entry points are now the ONLY way to reach it. A regression here would not
/// fail anything else: the screen still exists, it just becomes unreachable.
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

  Future<void> pump(WidgetTester tester, Widget screen) async {
    // Phone width, the real theme: a button that only fits at the 800px test
    // default is the failure CLAUDE.md's first design note describes.
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ring = MonthRingBuilder.build(
        logs: log.logs, prediction: prediction, today: DateTime.now());
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<LogProvider>.value(value: log),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        ChangeNotifierProvider<ProductSessionProvider>(
          create: (_) => ProductSessionProvider(
              ProductSessionRepository(ReminderRepository(db))),
        ),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<PredictedPeriod>>.value(value: const []),
        Provider<List<CycleNarrative>>.value(value: const []),
        Provider<OvulationConfirmation>.value(
            value: const OvulationConfirmation(null)),
        Provider<CheckInPrompt>.value(value: CheckInPrompt.none),
        Provider<MonthRingData>.value(value: ring),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Home cycle card opens Forecast', (tester) async {
    await pump(tester, const HomeScreen());
    final button = find.byKey(const Key('home-see-forecast'));
    expect(button, findsOneWidget);
    expect(find.text('See forecast'), findsOneWidget);

    // Inside the viewport, not clipped off the right edge at 360dp.
    final rect = tester.getRect(button);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(ForecastScreen), findsOneWidget);
  });

  testWidgets('Calendar app bar opens Forecast', (tester) async {
    await pump(tester, const CalendarScreen());
    final action = find.byKey(const Key('calendar-forecast-action'));
    expect(action, findsOneWidget);
    expect(find.byTooltip('Forecast'), findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.byType(ForecastScreen), findsOneWidget);
  });
}
