import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/premium_provider.dart';
import 'package:menstrul_track/screens/calendar/calendar_screen.dart';
import 'package:menstrul_track/services/prediction_service.dart';
import 'package:menstrul_track/theme/app_theme.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';

/// Regression: the combined calendar+entry surface must actually SHOW the entry
/// form when a day is selected. The ad-placement test only asserted the ad
/// disappears — it never asserted the form appears — so a panel that set
/// `_selectedDay` (hiding the ad/FAB) but rendered nothing passed green while
/// failing on-device.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  // Mirror the real app: CalendarScreen lives inside an IndexedStack inside the
  // shell Scaffold (with a bottom nav), NOT as a bare MaterialApp home. This is
  // the nesting that differs from ad_placement_test.
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
        home: Scaffold(
          body: IndexedStack(index: 0, children: [child]),
          bottomNavigationBar: const SizedBox(height: 80),
        ),
      ),
    );
  }

  testWidgets('selecting a day opens the entry form sheet with real height',
      (tester) async {
    // Seed an existing log for today — the device path where the day tapped
    // already has data (`_hadExisting == true`).
    final today = DateTime.now();
    await DailyLogRepository(db).upsert(
      date: DateTime(today.year, today.month, today.day),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );

    await tester.pumpWidget(wrapInShell(const CalendarScreen()));
    await tester.pumpAndSettle();

    // Open today's inline entry via the FAB (same action the ad test uses).
    await tester.tap(find.text('Log today'));
    await tester.pumpAndSettle();

    // The shared form must be present AND actually laid out with height.
    expect(find.byType(DayEntryForm), findsOneWidget);
    expect(find.text('Period ended today'), findsOneWidget);
    final size = tester.getSize(find.byType(DayEntryForm));
    expect(size.height, greaterThan(0),
        reason: 'inline entry form rendered zero-height');
  });
}
