import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  late LogProvider logs;
  final date = DateTime(2026, 3, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    await logs.load();
  });
  tearDown(() => db.close());

  Widget wrap(GlobalKey<DayEntryFormState> key) =>
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(
          home: Scaffold(
            body: DayEntryForm(
              key: key,
              date: date,
              medications: const [MedChip(5, 'Vitamin D')],
            ),
          ),
        ),
      );

  testWidgets('toggling a medication chip writes med_<id> on save',
      (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(key));
    await tester.pumpAndSettle();

    // The Medications section is below the fold of the form's ListView, so
    // scroll it into view first (same pattern as other below-the-fold chip
    // groups in this form — see rich_logging_form_test.dart).
    await tester.dragUntilVisible(
      find.text('Vitamin D'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    // The chip is shown by name.
    expect(find.text('Vitamin D'), findsOneWidget);

    await tester.tap(find.text('Vitamin D'));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    final saved = logs.logForDate(date);
    expect(decodeGroup(saved?.symptoms, kMedicationKeyPrefix), {'med_5'});
  });

  testWidgets('no medications configured → no Medications section',
      (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(ChangeNotifierProvider<LogProvider>.value(
      value: logs,
      child: MaterialApp(
        home: Scaffold(body: DayEntryForm(key: key, date: date)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Medications'), findsNothing);
  });
}
