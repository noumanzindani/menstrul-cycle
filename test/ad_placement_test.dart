import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/calendar/calendar_screen.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/ad_banner.dart';

/// Council rule: ads must NEVER appear on the sensitive logging or insights
/// screens. This guards that placement decision structurally.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(
          create: (_) => LogProvider(DailyLogRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => PremiumProvider(SettingsRepository(db)),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  testWidgets('Day-log screen has no ad banner', (tester) async {
    await tester.pumpWidget(wrap(DayLogScreen(date: DateTime(2026, 1, 1))));
    await tester.pump();
    expect(find.byType(AdBanner), findsNothing);
  });

  testWidgets('Insights screen has no ad banner', (tester) async {
    await tester.pumpWidget(wrap(const InsightsScreen()));
    await tester.pump();
    expect(find.byType(AdBanner), findsNothing);
  });

  // The calendar IS an ad-allowed surface — but once its inline entry panel is
  // open it becomes a logging surface, and ads must never co-render with entry.
  Widget wrapCalendar(Widget child) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(
          create: (_) => LogProvider(DailyLogRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => PremiumProvider(SettingsRepository(db)),
        ),
        Provider<List<PredictedPeriod>>.value(value: const []),
        Provider<PredictionResult>.value(
          value: PredictionService.predict(const []),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  // Home reads a fuller set of derived models than the calendar does; they are
  // all supplied by `ProxyProvider`s in main.dart, so a bare pump would throw.
  Widget wrapHome(Widget child) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(SettingsRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => LogProvider(DailyLogRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => PremiumProvider(SettingsRepository(db)),
        ),
        Provider<PredictionResult>.value(
          value: PredictionService.predict(const []),
        ),
        Provider<List<CycleNarrative>>.value(value: const []),
        Provider<OvulationConfirmation>.value(
          value: const OvulationConfirmation(null),
        ),
        Provider<CheckInPrompt>.value(value: CheckInPrompt.none),
        Provider<MonthRingData>.value(
          value: MonthRingData.empty(DateTime(2026, 1, 1)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  testWidgets('Calendar hides its ad banner while an entry panel is open',
      (tester) async {
    await tester.pumpWidget(wrapCalendar(const CalendarScreen()));
    await tester.pumpAndSettle();

    // Banner is allowed while no panel is open.
    expect(find.byType(AdBanner), findsOneWidget);

    // Open today's inline entry — sensitive logging is now on screen.
    await tester.tap(find.text('Log today'));
    await tester.pumpAndSettle();

    expect(find.byType(AdBanner), findsNothing);
  });

  // Home's FAB was drawn ON TOP of the loaded banner on a real device: a
  // Scaffold lifts its floatingActionButton clear of `bottomNavigationBar`
  // and of nothing else, so a banner sitting in the body Column got covered.
  // An app control over an ad is both an accidental-click hazard and an
  // AdMob placement violation.
  //
  // STRUCTURAL, and deliberately so: `AdBanner` renders `SizedBox.shrink()`
  // until a real ad loads, which never happens under `flutter test`, so its
  // rect is always zero here and a geometric "these two do not intersect"
  // assertion would pass no matter where the banner lived. This asserts the
  // MECHANISM that earns the clearance instead — the slot the Scaffold
  // actually reserves for.
  testWidgets(
      'Home puts its ad banner in the Scaffold bottom slot, so the FAB is '
      'laid out clear of it rather than over it', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrapHome(const HomeScreen()));
    await tester.pumpAndSettle();

    // The FAB is the thing that was doing the covering — if it ever stops
    // being here, this test is guarding nothing and should be revisited.
    expect(find.byType(FloatingActionButton), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(scaffold.bottomNavigationBar, isNotNull,
        reason: 'the banner must occupy the slot the FAB is lifted above');
    expect(
      find.descendant(
        of: find.byWidget(scaffold.bottomNavigationBar!),
        matching: find.byType(AdBanner),
      ),
      findsOneWidget,
    );
  });
}
