import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/screens/calendar/calendar_screen.dart';
import 'package:menstrul_track/theme/app_theme.dart';

/// The calendar shows a PMS shading + legend entry for the days just before a
/// predicted period, alongside the existing period/predicted/fertile/ovulation
/// markers. PMS is period-timing (like the predicted-period run), not a
/// fertility signal, so — unlike Ovulation — it is not confidence-gated.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget wrapInShell(Widget child) {
    final period = PredictedPeriod(
      start: DateTime(2026, 7, 30),
      end: DateTime(2026, 8, 3),
      ovulation: DateTime(2026, 7, 16),
      fertileStart: DateTime(2026, 7, 11),
      fertileEnd: DateTime(2026, 7, 17),
      pmsStart: DateTime(2026, 7, 25),
      pmsEnd: DateTime(2026, 7, 29),
    );
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(
          create: (_) => LogProvider(DailyLogRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => PremiumProvider(SettingsRepository(db)),
        ),
        Provider<List<PredictedPeriod>>.value(value: [period]),
        Provider<PredictionResult>.value(
          value: PredictionResult(
            averageCycleLength: 28,
            cycleVariabilityDays: 1,
            averagePeriodLength: 5,
            cyclesTracked: 3,
            confidence: PredictionConfidence.medium,
            lastPeriodStart: DateTime(2026, 7, 2),
            cycleDay: 14,
            currentPhase: CyclePhase.ovulatory,
            nextPeriodStart: period.start,
            nextPeriodWindowStart: period.start,
            nextPeriodWindowEnd: period.start,
            ovulationDay: period.ovulation,
            fertileWindowStart: period.fertileStart,
            fertileWindowEnd: period.fertileEnd,
            pmsWindowStart: period.pmsStart,
            pmsWindowEnd: period.pmsEnd,
            fertilityConfidence: PredictionConfidence.medium,
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: IndexedStack(index: 0, children: [child]),
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
  }

  testWidgets('calendar shows a PMS legend entry', (tester) async {
    await tester.pumpWidget(wrapInShell(const CalendarScreen()));
    await tester.pumpAndSettle();

    // The legend sits below the month grid inside the scrolling list. The
    // month grid is itself a (non-scrolling) Scrollable, so the outer list
    // must be targeted explicitly.
    await tester.scrollUntilVisible(
      find.textContaining('PMS'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('PMS'), findsOneWidget);
  });
}
