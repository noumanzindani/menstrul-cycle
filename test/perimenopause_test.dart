import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/insights.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/home/home_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// Perimenopause mode: erratic cycles → the calendar-based fertility estimate is
/// suppressed, replaced by an honest note. The load-bearing safety rule is that
/// hiding the fertile window must NEVER read as "safe" — so the note must state
/// pregnancy is still possible.
List<Cycle> _recentCycles() {
  final anchor = DateTime.now().subtract(const Duration(days: 6));
  return [
    Cycle(
        start: anchor.subtract(const Duration(days: 28)),
        end: anchor.subtract(const Duration(days: 24)),
        lengthDays: 28),
    Cycle(start: anchor, end: anchor.add(const Duration(days: 4))),
  ];
}

void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
    await settings.setMode(TrackingMode.perimenopause);
  });
  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    final prediction =
        PredictionService.predict(_recentCycles(), capConfidenceToLow: true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<CycleNarrative>>.value(value: const []),
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

  testWidgets('shows the still-fertile note and hides the fertile-window card',
      (tester) async {
    await pumpHome(tester);

    // The honest framing: fertility is unpredictable, but not zero.
    expect(find.textContaining('still become pregnant'), findsOneWidget);
    // The fertile-window card ("awareness only, not contraception") is gone —
    // a specific calendar window is false precision in perimenopause.
    expect(find.textContaining('awareness only'), findsNothing);
  });

  testWidgets('keeps the next-period estimate, flagged low confidence',
      (tester) async {
    await pumpHome(tester);

    // Utility preserved: the next-period card still renders...
    expect(find.textContaining('Period'), findsWidgets);
    // ...and it is honestly flagged low confidence (the cap reached the UI).
    expect(find.textContaining('Low confidence'), findsOneWidget);
  });
}
