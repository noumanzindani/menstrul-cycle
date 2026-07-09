import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The Home dashboard surfaces the single most-notable "Your patterns"
/// narrative as a highlight — but never the 'phase' one (the phase card already
/// says where the user is now), and nothing at all when data is thin.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  final cycles = [
    Cycle(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 5),
        lengthDays: 28),
    Cycle(start: DateTime(2026, 1, 29), end: DateTime(2026, 2, 2)),
  ];
  final prediction =
      PredictionService.predict(cycles, asOf: DateTime(2026, 1, 29));

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, List<CycleNarrative> narratives) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<CycleNarrative>>.value(value: narratives),
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

  testWidgets('shows the top pattern as a highlight', (tester) async {
    await pump(tester, const [
      CycleNarrative('cycle_trend',
          'Your last 3 cycles have run about 2 days shorter than the cycles before.'),
    ]);
    expect(find.textContaining('2 days shorter'), findsOneWidget);
  });

  testWidgets('does NOT highlight the phase narrative (the phase card covers it)',
      (tester) async {
    await pump(tester, const [
      CycleNarrative('phase', 'Day 18 of your cycle — your luteal phase, after ovulation.'),
    ]);
    expect(find.textContaining('after ovulation'), findsNothing);
  });

  testWidgets('shows no highlight when there are no patterns', (tester) async {
    await pump(tester, const []);
    expect(find.byIcon(Icons.insights_outlined), findsNothing);
  });
}
