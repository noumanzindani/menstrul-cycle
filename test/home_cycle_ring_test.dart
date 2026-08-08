import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
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
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/month_ring_builder.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/disclaimer_banner.dart';
import 'package:menstrul_track/widgets/month_ring.dart';

/// The month ring is a fertility surface on Home. It must render there, sit on a
/// surface that still carries the non-contraception DisclaimerBanner, and never
/// render the word "safe" or a numeric percentage.
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

  Future<void> pump(WidgetTester tester) async {
    // Tall surface so the whole scrolling dashboard (incl. the trailing
    // disclaimer under the ring) lays out for structural assertions.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final ring = MonthRingBuilder.build(
        logs: log.logs, prediction: prediction, today: DateTime.now());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<LogProvider>.value(value: log),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        // Home reads the in-progress product-change session. No fixture here
        // starts one, which is what keeps the card's Timer — and therefore
        // pumpAndSettle — out of this test.
        ChangeNotifierProvider<ProductSessionProvider>(
          create: (_) => ProductSessionProvider(
              ProductSessionRepository(ReminderRepository(db))),
        ),
        Provider<PredictionResult>.value(value: prediction),
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
        home: const HomeScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Home renders the month ring with the disclaimer and no "safe"',
      (tester) async {
    await pump(tester);
    expect(find.byType(MonthRing), findsOneWidget);
    expect(find.byType(DisclaimerBanner), findsOneWidget);
    expect(find.textContaining('safe'), findsNothing);
    expect(find.textContaining('Safe'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });
}
