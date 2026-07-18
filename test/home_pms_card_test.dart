import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/date_utils.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/month_ring.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// Home shows an upcoming-PMS-window card in Track/Perimenopause modes (period
/// timing, like the next-period card — not a fertility signal, so unlike the
/// Fertile card it is never confidence-gated). Conceive mode leads with
/// fertility instead and does not show it.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  final today = dateOnly(DateTime.now());
  // 7 periods of a regular 28-day cycle -> high confidence, real prediction.
  final cycles = <Cycle>[
    for (var i = 6; i >= 1; i--)
      Cycle(
        start: today.subtract(Duration(days: 28 * i)),
        end: today.subtract(Duration(days: 28 * i - 4)),
        lengthDays: 28,
      ),
    Cycle(start: today, end: today.add(const Duration(days: 4))),
  ];

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester, TrackingMode mode) async {
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    await settings.setMode(mode);
    final prediction = PredictionService.predict(cycles, asOf: today);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<CycleNarrative>>.value(value: const []),
        Provider<OvulationConfirmation>.value(
            value: const OvulationConfirmation(null)),
        Provider<CheckInPrompt>.value(value: CheckInPrompt.none),
        Provider<MonthRingData>.value(value: MonthRingData.empty(today)),
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

  testWidgets('Track mode shows the PMS window card', (tester) async {
    await pumpHome(tester, TrackingMode.track);
    await tester.scrollUntilVisible(
        find.textContaining('PMS window'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('PMS window'), findsOneWidget);
  });

  testWidgets('Perimenopause mode shows the PMS window card', (tester) async {
    await pumpHome(tester, TrackingMode.perimenopause);
    await tester.scrollUntilVisible(
        find.textContaining('PMS window'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('PMS window'), findsOneWidget);
  });

  testWidgets('Conceive mode does not show the PMS window card',
      (tester) async {
    await pumpHome(tester, TrackingMode.conceive);
    expect(find.textContaining('PMS window'), findsNothing);
  });
}
