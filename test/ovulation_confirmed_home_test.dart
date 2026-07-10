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
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// Conceive-mode Home shows a retrospective "ovulation likely confirmed" note
/// when this cycle's temperatures shifted — framed for conception, NEVER as a
/// "safe" day, and only in Conceive mode.
void main() {
  late AppDatabase db;
  late SettingsProvider settings;

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
  });
  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester, {
    required TrackingMode mode,
    required OvulationConfirmation confirmation,
  }) async {
    await settings.setMode(mode);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<PremiumProvider>(
            create: (_) => PremiumProvider(SettingsRepository(db))),
        Provider<PredictionResult>.value(value: prediction),
        Provider<List<CycleNarrative>>.value(value: const []),
        Provider<OvulationConfirmation>.value(value: confirmation),
        Provider<CheckInPrompt>.value(value: CheckInPrompt.none),
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

  testWidgets('shows the confirmation note in Conceive mode, never saying "safe"',
      (tester) async {
    await pump(tester,
        mode: TrackingMode.conceive,
        confirmation: OvulationConfirmation(DateTime(2026, 1, 20)));

    expect(find.textContaining('Ovulation likely confirmed'), findsOneWidget);
    // The note itself carries the non-contraceptive caveat (this exact phrasing
    // is unique to the note; the disclaimer banner has its own wording).
    expect(find.textContaining('awareness, not a contraceptive method'),
        findsOneWidget);
    // The core guardrail: nothing on this surface reads as "safe".
    expect(find.textContaining('safe'), findsNothing);
    expect(find.textContaining('Safe'), findsNothing);
  });

  testWidgets('hides the note when there is no confirmed shift', (tester) async {
    await pump(tester,
        mode: TrackingMode.conceive,
        confirmation: const OvulationConfirmation(null));
    expect(find.textContaining('Ovulation likely confirmed'), findsNothing);
  });

  testWidgets('does not show in non-Conceive modes even if a shift exists',
      (tester) async {
    await pump(tester,
        mode: TrackingMode.track,
        confirmation: OvulationConfirmation(DateTime(2026, 1, 20)));
    expect(find.textContaining('Ovulation likely confirmed'), findsNothing);
  });
}
