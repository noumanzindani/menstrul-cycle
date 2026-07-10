import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/date_utils.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';
import 'package:menstrul_track/widgets/period_check_in_banner.dart';

/// The calendar day-sheet's contextual back-fill strip: on a predicted-start
/// date it offers "Didn't start"; mid-period it offers "Mark ended here". Either
/// records a confirmed no-bleeding day (flow = none) for THAT date.
void main() {
  late AppDatabase db;
  late LogProvider log;
  final date = DateTime(2026, 3, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    log = LogProvider(DailyLogRepository(db));
    await log.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, CheckInPrompt prompt) async {
    await tester.pumpWidget(MaterialApp(
      home: ChangeNotifierProvider<LogProvider>.value(
        value: log,
        child: Scaffold(
          body: PeriodCheckInBanner(prompt: prompt, date: date),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('didItStart offers "Didn\'t start" and marks the date no-bleeding',
      (tester) async {
    await pump(tester, CheckInPrompt.didItStart);
    expect(find.text("Didn't start"), findsOneWidget);
    expect(log.logForDate(date), isNull);

    await tester.tap(find.text("Didn't start"));
    await tester.pumpAndSettle();

    expect(log.logForDate(dateOnly(date))?.flow, FlowIntensity.none);
  });

  testWidgets('hasItEnded offers "Mark ended here"', (tester) async {
    await pump(tester, CheckInPrompt.hasItEnded);
    expect(find.text('Mark ended here'), findsOneWidget);
  });

  testWidgets('renders nothing when there is no check-in', (tester) async {
    await pump(tester, CheckInPrompt.none);
    expect(find.text("Didn't start"), findsNothing);
    expect(find.text('Mark ended here'), findsNothing);
  });
}
