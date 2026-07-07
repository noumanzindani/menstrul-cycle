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
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// End-to-end wiring: an OPK that corroborates ovulation must actually UNLOCK
/// the Home fertility band (which would otherwise stay hidden at low
/// confidence), and label WHY. Without the OPK the band must remain hidden — the
/// positive-and-negative pair proves the gate reads `fertilityConfidence`.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  // Anchor so TODAY is ovulation day: last period start 14 days ago, one prior
  // complete 28-day cycle → base confidence `low`, ovulation ≈ today.
  final today = dateOnly(DateTime.now());
  final lastStart = today.subtract(const Duration(days: 14));
  final cycles = [
    Cycle(
        start: lastStart.subtract(const Duration(days: 28)),
        end: lastStart.subtract(const Duration(days: 24)),
        lengthDays: 28),
    Cycle(start: lastStart, end: lastStart.add(const Duration(days: 4))),
  ];

  DailyLog opkDay(DateTime date, String opk) => DailyLog(
        id: 0,
        date: date,
        flow: null,
        symptoms: '{}',
        mood: null,
        notes: null,
        bbt: null,
        opk: opk,
        createdAt: date,
        updatedAt: date,
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    await settings.setMode(TrackingMode.conceive);
  });
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester, PredictionResult prediction) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
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

  testWidgets('a corroborating OPK unlocks the band and labels why',
      (tester) async {
    final prediction =
        PredictionService.predict(cycles, logs: [opkDay(today, 'positive')]);
    // Guard the fixture: the chip stays low, only fertility is raised.
    expect(prediction.confidence, PredictionConfidence.low);
    expect(prediction.fertilityConfidence, PredictionConfidence.medium);

    await pumpHome(tester, prediction);

    // The band is now visible on the ovulation day...
    expect(find.textContaining('Most fertile today'), findsOneWidget);
    // ...and the app says WHY it appeared (still awareness, never a percentage).
    expect(find.textContaining('Confirmed by your recent ovulation test'),
        findsOneWidget);
  });

  testWidgets('without a corroborating OPK the band stays hidden at low',
      (tester) async {
    final prediction = PredictionService.predict(cycles);
    expect(prediction.fertilityConfidence, PredictionConfidence.low);

    await pumpHome(tester, prediction);

    // The fertile-window card still renders (awareness copy present)...
    expect(find.textContaining('awareness only'), findsOneWidget);
    // ...but the qualitative band and its corroboration note are suppressed.
    expect(find.textContaining('Most fertile today'), findsNothing);
    expect(find.textContaining('Confirmed by your recent ovulation test'),
        findsNothing);
  });
}
