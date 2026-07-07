import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';

/// Symptothermal: the day form captures a basal temperature and an OPK result
/// into the (previously dormant) bbt/opk columns.
void main() {
  late AppDatabase db;
  late LogProvider logs;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = LogProvider(DailyLogRepository(db));
    await logs.load();
  });
  tearDown(() => db.close());

  Widget wrap(Widget child) => ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(home: child),
      );

  testWidgets('logs a basal temperature and an OPK result', (tester) async {
    final date = DateTime(2026, 6, 3);
    await tester.pumpWidget(wrap(DayLogScreen(date: date)));
    await tester.pumpAndSettle();

    final bbtField = find.byWidgetPredicate((w) =>
        w is TextField && w.decoration?.labelText == 'Basal body temperature');
    await tester.dragUntilVisible(
        bbtField, find.byType(ListView), const Offset(0, -300));
    await tester.enterText(bbtField, '36.6');

    await tester.dragUntilVisible(
        find.text('Positive'), find.byType(ListView), const Offset(0, -300));
    await tester.tap(find.text('Positive'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = logs.logForDate(date);
    expect(saved?.bbt, 36.6);
    expect(saved?.opk, 'positive');
  });
}
