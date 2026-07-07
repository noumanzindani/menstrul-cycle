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
import 'package:menstrul_track/screens/insights/insights_screen.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';
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
}
