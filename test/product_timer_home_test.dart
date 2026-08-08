import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/date_utils.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/product_session_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/month_ring.dart';
import 'package:menstrul_track/widgets/product_timer_card.dart';
import 'package:menstrul_track/widgets/product_timer_start_card.dart';

/// The timer card is the app's only live-ticking widget. Its presence is gated
/// on a session existing — which is not cosmetic: ~50 test files call
/// `pumpAndSettle`, and a Timer that keeps calling setState means the tree never
/// settles and every one of them would hang. No existing fixture has a session,
/// so the gate is what keeps them green.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;
  late LogProvider log;
  late ProductSessionProvider timer;

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
    timer = ProductSessionProvider(
        ProductSessionRepository(ReminderRepository(db)));
    await timer.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<LogProvider>.value(value: log),
        ChangeNotifierProvider<ProductSessionProvider>.value(value: timer),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<CycleNarrative>>.value(value: const []),
        Provider<OvulationConfirmation>.value(
            value: const OvulationConfirmation(null)),
        Provider<CheckInPrompt>.value(value: CheckInPrompt.none),
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

  testWidgets('Home with no active session settles and shows no timer card',
      (tester) async {
    // If this test ever hangs rather than fails, the ticker has escaped its
    // gate. Check that before debugging anything else.
    await pump(tester);

    expect(find.byType(ProductTimerCard), findsNothing);
    expect(find.text('Changed'), findsNothing);
  });

  testWidgets('Home shows the card while a session is running', (tester) async {
    await timer.start(ProductType.tampon,
        now: DateTime.now().subtract(const Duration(hours: 2)));
    await pump(tester);

    expect(find.byType(ProductTimerCard), findsOneWidget);
    expect(find.text('Tampon'), findsOneWidget);
    expect(find.textContaining('2h ago'), findsOneWidget);

    // Unmount so the card's Timer is cancelled before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the running card sits above the cycle ring', (tester) async {
    await timer.start(ProductType.cupOrDisc,
        now: DateTime.now().subtract(const Duration(hours: 1)));
    await pump(tester);

    final card = tester.getTopLeft(find.byType(ProductTimerCard));
    final ring = tester.getTopLeft(find.byType(MonthRing));
    expect(card.dy, lessThan(ring.dy),
        reason: 'something in use now outranks the month ring');

    await tester.pumpWidget(const SizedBox());
  });

  group('idle card gating', () {
    testWidgets('is absent on a day with no bleeding logged', (tester) async {
      await pump(tester);
      expect(find.byType(ProductTimerStartCard), findsNothing);
    });

    testWidgets('appears once bleeding is logged for today', (tester) async {
      await log.saveDay(
          date: dateOnly(DateTime.now()), flow: FlowIntensity.medium, symptomsJson: '{}');
      await pump(tester);

      expect(find.byType(ProductTimerStartCard), findsOneWidget);
      expect(find.text('Tampon'), findsOneWidget);
    });

    testWidgets('is absent on a day explicitly marked as no bleeding',
        (tester) async {
      await log.saveDay(
          date: dateOnly(DateTime.now()), flow: FlowIntensity.none, symptomsJson: '{}');
      await pump(tester);

      expect(find.byType(ProductTimerStartCard), findsNothing);
    });

    testWidgets('gives way to the running card once a timer starts',
        (tester) async {
      await log.saveDay(
          date: dateOnly(DateTime.now()), flow: FlowIntensity.heavy, symptomsJson: '{}');
      await timer.start(ProductType.pad, now: DateTime.now());
      await pump(tester);

      expect(find.byType(ProductTimerStartCard), findsNothing);
      expect(find.byType(ProductTimerCard), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a running session is carried into pregnancy mode, not orphaned',
      (tester) async {
    // _PregnancyHome replaces the entire dashboard. Without this the timer
    // would keep firing notifications with no visible card behind them.
    await timer.start(ProductType.cupOrDisc,
        now: DateTime.now().subtract(const Duration(hours: 3)));
    await settings.startPregnancy(DateTime.now().subtract(const Duration(days: 60)));
    await pump(tester);

    expect(find.byType(ProductTimerCard), findsOneWidget);
    expect(find.textContaining('weeks'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ending the session removes the card and the ticker with it',
      (tester) async {
    await timer.start(ProductType.pad,
        now: DateTime.now().subtract(const Duration(minutes: 30)));
    await pump(tester);
    expect(find.byType(ProductTimerCard), findsOneWidget);

    await tester.tap(find.text('Removed'));
    await tester.pumpAndSettle();

    expect(find.byType(ProductTimerCard), findsNothing);
    // No unmount needed: if the Timer outlived the card, the test fails here
    // with a pending-timer error.
  });
}
