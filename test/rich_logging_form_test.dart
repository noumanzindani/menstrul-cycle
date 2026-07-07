import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';

/// The rich-logging pass (cat 4–8): the day form must capture discharge quality
/// (single-select) and vaginal-health flags (multi-select), persist them into
/// the day-tags JSON, and keep these sensitive groups OUT of the plain-symptom
/// set (so they stay out of the doctor PDF by default).
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

  testWidgets('discharge quality + vaginal-health flag persist, excluded from symptoms',
      (tester) async {
    final date = DateTime(2026, 6, 2);
    await tester.pumpWidget(wrap(DayLogScreen(date: date)));
    await tester.pumpAndSettle();

    Future<void> tapBelowFold(String label) async {
      await tester.dragUntilVisible(
        find.text(label),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await tapBelowFold('Creamy'); // discharge quality (single-select)
    await tapBelowFold('Itching'); // vaginal-health flag (multi-select)

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = logs.logForDate(date);
    expect(saved, isNotNull);
    expect(decodeSingle(saved!.symptoms, kDischargeKeyPrefix), 'cm_creamy');
    expect(decodeGroup(saved.symptoms, kVaginalKeyPrefix), contains('vag_itching'));
    // Sensitive groups must never surface as plain symptoms (doctor PDF).
    expect(decodeSymptoms(saved.symptoms), isEmpty);
  });
}
