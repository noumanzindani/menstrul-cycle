import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/medication_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository logRepo;
  late MedicationRepository medRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logRepo = DailyLogRepository(db);
    medRepo = MedicationRepository(db);
  });
  tearDown(() => db.close());

  /// Two period runs → the first cycle is complete (Jan 1 → Jan 29).
  Future<void> seedCycleWith(Set<String> Function(int day) flagsForDay) async {
    for (final d in [1, 2, 3]) {
      await logRepo.upsert(
        date: DateTime(2026, 1, d),
        flow: FlowIntensity.medium,
        symptomsJson: encodeDayTags(flags: flagsForDay(d)),
      );
    }
    await logRepo.upsert(
      date: DateTime(2026, 1, 29),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(),
    );
  }

  Future<void> pumpInsights(WidgetTester tester,
      {bool withMedProvider = true}) async {
    final logs = LogProvider(logRepo);
    await logs.load();
    final meds = MedicationProvider(medRepo);
    await meds.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        if (withMedProvider)
          ChangeNotifierProvider<MedicationProvider>.value(value: meds),
      ],
      child: const MaterialApp(home: InsightsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a Medications this cycle bar, never a percentage',
      (tester) async {
    final ironId = await medRepo.add(name: 'Iron', enabled: true);
    await seedCycleWith((_) => {'med_$ironId'});
    await pumpInsights(tester);

    await tester.dragUntilVisible(
      find.text('Medications this cycle'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medications this cycle'), findsOneWidget);
    expect(find.text('Iron'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing); // no false precision
  });

  testWidgets('no medication intake logged -> section hidden', (tester) async {
    await medRepo.add(name: 'Iron', enabled: true);
    await seedCycleWith((_) => const {});
    await pumpInsights(tester);

    expect(find.text('Medications this cycle'), findsNothing);
  });

  testWidgets('no MedicationProvider -> screen still renders, section hidden',
      (tester) async {
    final ironId = await medRepo.add(name: 'Iron', enabled: true);
    await seedCycleWith((_) => {'med_$ironId'});
    await pumpInsights(tester, withMedProvider: false);

    expect(tester.takeException(), isNull);
    expect(find.text('Medications this cycle'), findsNothing);
  });
}
