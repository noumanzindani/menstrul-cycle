import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/cycle_calculator.dart';
import 'package:menstrul_track/services/medication_adherence_service.dart';

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

  test('counts days each enabled medication was logged in the cycle', () async {
    final ironId = await medRepo.add(name: 'Iron', enabled: true);
    final oldId = await medRepo.add(name: 'Stopped', enabled: false);

    // Two period runs so the first cycle has a known length (Jan 1 → Jan 29).
    for (final d in [1, 2, 3]) {
      await logRepo.upsert(
        date: DateTime(2026, 1, d),
        flow: FlowIntensity.medium,
        symptomsJson: encodeDayTags(
            flags: d < 3 ? {'med_$ironId', 'med_$oldId'} : {'med_$ironId'}),
      );
    }
    await logRepo.upsert(
      date: DateTime(2026, 1, 29),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(),
    );

    final logs = await logRepo.getAll();
    final meds = await medRepo.getAll();
    final firstCycle = CycleCalculator.computeCycles(logs).first;

    final adherence =
        MedicationAdherenceService.forCycle(firstCycle, logs, meds);

    expect(adherence.hasData, isTrue);
    expect(adherence.entries, hasLength(1)); // disabled med excluded
    final iron = adherence.entries.single;
    expect(iron.medId, ironId);
    expect(iron.name, 'Iron');
    expect(iron.daysLogged, 3);
    expect(iron.cycleLength, 28);
  });

  test('orders entries by days logged (descending), then by name', () async {
    final ironId = await medRepo.add(name: 'Iron', enabled: true);
    final zincId = await medRepo.add(name: 'Zinc', enabled: true);
    final calciumId = await medRepo.add(name: 'Calcium', enabled: true);

    // Iron 1 day, Zinc 3 days, Calcium 3 days -> Calcium, Zinc, Iron.
    for (final d in [1, 2, 3]) {
      await logRepo.upsert(
        date: DateTime(2026, 1, d),
        flow: FlowIntensity.medium,
        symptomsJson: encodeDayTags(flags: {
          'med_$zincId',
          'med_$calciumId',
          if (d == 1) 'med_$ironId',
        }),
      );
    }
    await logRepo.upsert(
      date: DateTime(2026, 1, 29),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(),
    );

    final logs = await logRepo.getAll();
    final cycle = CycleCalculator.computeCycles(logs).first;
    final adherence = MedicationAdherenceService.forCycle(
        cycle, logs, await medRepo.getAll());

    expect(adherence.entries.map((e) => e.name).toList(),
        ['Calcium', 'Zinc', 'Iron']);
  });

  test('intake logged outside the cycle window is not counted', () async {
    final ironId = await medRepo.add(name: 'Iron', enabled: true);

    await logRepo.upsert(
      date: DateTime(2026, 1, 1),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(flags: {'med_$ironId'}),
    );
    // Day inside the first cycle.
    await logRepo.upsert(
      date: DateTime(2026, 1, 15),
      symptomsJson: encodeDayTags(flags: {'med_$ironId'}),
    );
    // Next period starts the second cycle; this intake belongs to it.
    await logRepo.upsert(
      date: DateTime(2026, 1, 29),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(flags: {'med_$ironId'}),
    );

    final logs = await logRepo.getAll();
    final cycle = CycleCalculator.computeCycles(logs).first;
    final adherence = MedicationAdherenceService.forCycle(
        cycle, logs, await medRepo.getAll());

    expect(adherence.entries.single.daysLogged, 2); // Jan 1 + Jan 15, not Jan 29
  });

  test('no medication intake logged -> hasData is false', () async {
    await medRepo.add(name: 'Iron', enabled: true);
    await logRepo.upsert(
      date: DateTime(2026, 1, 1),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(),
    );
    await logRepo.upsert(
      date: DateTime(2026, 1, 29),
      flow: FlowIntensity.medium,
      symptomsJson: encodeDayTags(),
    );

    final logs = await logRepo.getAll();
    final cycle = CycleCalculator.computeCycles(logs).first;
    final adherence = MedicationAdherenceService.forCycle(
        cycle, logs, await medRepo.getAll());

    expect(adherence.hasData, isFalse);
    expect(adherence.entries, isEmpty);
  });
}
