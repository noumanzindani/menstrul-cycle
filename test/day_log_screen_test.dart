import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/medication_provider.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';

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

  testWidgets('"Period ended today" toggle saves the day as no-bleeding (flow none)',
      (tester) async {
    final date = DateTime(2026, 5, 10);
    await tester.pumpWidget(wrap(DayLogScreen(date: date)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Period ended today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(logs.logForDate(date)?.flow, FlowIntensity.none);
  });

  testWidgets('logging a Sex option persists it without polluting symptoms',
      (tester) async {
    final date = DateTime(2026, 5, 11);
    await tester.pumpWidget(wrap(DayLogScreen(date: date)));
    await tester.pumpAndSettle();

    // Sex chips sit below the fold — scroll them into view first.
    await tester.dragUntilVisible(
      find.text('Protected'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Protected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = logs.logForDate(date);
    expect(saved, isNotNull);
    // Sex is stored in the tags JSON but must not surface as a symptom.
    expect(saved!.symptoms.contains('sex_protected'), isTrue);
  });

  testWidgets('day log screen shows configured medication chips',
      (tester) async {
    final medRepo = MedicationRepository(db);
    await medRepo.add(name: 'Iron', enabled: true);
    await medRepo.add(name: 'Retired pill', enabled: false);
    final meds = MedicationProvider(medRepo);
    await meds.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        ChangeNotifierProvider<MedicationProvider>.value(value: meds),
      ],
      child: MaterialApp(home: DayLogScreen(date: DateTime(2026, 3, 10))),
    ));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Iron'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Iron'), findsOneWidget);
    // Disabled medications are not offered for intake.
    expect(find.text('Retired pill'), findsNothing);
  });
}
