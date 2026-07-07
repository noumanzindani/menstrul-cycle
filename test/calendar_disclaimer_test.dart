import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/screens/calendar/calendar_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/disclaimer_banner.dart';

/// Guardrail: the calendar overlays a fertile window / ovulation estimate, so
/// the non-contraception [DisclaimerBanner] must render on it — the same rule
/// already enforced on Home and Forecast. This closes the gap where the
/// calendar showed fertility shading with no disclaimer beside it.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Widget wrapInShell(Widget child) {
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
        home: Scaffold(
          body: IndexedStack(index: 0, children: [child]),
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
  }

  testWidgets('calendar shows the non-contraception disclaimer',
      (tester) async {
    await tester.pumpWidget(wrapInShell(const CalendarScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(DisclaimerBanner), findsOneWidget);
  });
}
