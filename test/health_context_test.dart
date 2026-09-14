import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/cycle.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/health_context.dart';

AppSetting _settings({
  DateTime? dateOfBirth,
  double? heightCm,
  double? profileWeightKg,
  int? menarcheAge,
  String? contraceptionMethod,
  DateTime? contraceptionStartDate,
  String? knownDiagnoses,
  bool? breastfeeding,
  DateTime? breastfeedingSince,
}) =>
    AppSetting(
      id: 0,
      mode: TrackingMode.track,
      defaultCycleLength: 28,
      defaultPeriodLength: 5,
      themeMode: 'system',
      language: 'en',
      genderNeutralLanguage: false,
      appLockEnabled: false,
      premium: false,
      onboardingComplete: true,
      dateOfBirth: dateOfBirth,
      heightCm: heightCm,
      profileWeightKg: profileWeightKg,
      menarcheAge: menarcheAge,
      contraceptionMethod: contraceptionMethod,
      contraceptionStartDate: contraceptionStartDate,
      knownDiagnoses: knownDiagnoses,
      breastfeeding: breastfeeding,
      breastfeedingSince: breastfeedingSince,
    );

void main() {
  final asOf = DateTime(2026, 9, 14);

  test('an empty profile produces an empty block', () {
    expect(buildProfileBlock(settings: _settings(), asOf: asOf), isEmpty);
  });

  test('age is years only, never the date of birth', () {
    final out = buildProfileBlock(
      settings: _settings(dateOfBirth: DateTime(1996, 3, 2)),
      asOf: asOf,
    );
    expect(out, contains('Age: 30'));
    expect(out, isNot(contains('1996')));
  });

  test('the readout line appears verbatim when height and weight are present', () {
    final out = buildProfileBlock(
      settings: _settings(heightCm: 165, profileWeightKg: 60),
      asOf: asOf,
    );
    expect(out, contains('Height: 165 cm'));
    expect(out, contains('Current weight: 60.0 kg'));
    final lines = out.split('\n');
    expect(lines.any((line) => line.contains('22.0')), isTrue,
        reason: 'Complete readout line with 22.0 should be present');
  });

  test('diagnoses render as labels, and unknown keys are dropped', () {
    final out = buildProfileBlock(
      settings: _settings(
        knownDiagnoses: jsonEncode(['dx_pcos', 'dx_not_a_real_key']),
      ),
      asOf: asOf,
    );
    expect(out, contains('PCOS'));
    expect(out, isNot(contains('dx_not_a_real_key')));
    expect(out, isNot(contains('dx_pcos')));
  });

  test('contraception renders with label when method is set', () {
    final out = buildProfileBlock(
      settings: _settings(contraceptionMethod: 'contra_combined_pill'),
      asOf: asOf,
    );
    expect(out, contains('Contraception:'));
    expect(out, contains('Combined pill'));
    expect(out, isNot(contains('contra_combined_pill')));
  });

  test('contraception without start date omits the date', () {
    final out = buildProfileBlock(
      settings: _settings(contraceptionMethod: 'contra_combined_pill'),
      asOf: asOf,
    );
    expect(out, contains('Contraception: Combined pill'));
    expect(out, isNot(contains('since')));
  });

  test('contraception with start date includes the date', () {
    final startDate = DateTime(2024, 6, 15);
    final out = buildProfileBlock(
      settings: _settings(
        contraceptionMethod: 'contra_combined_pill',
        contraceptionStartDate: startDate,
      ),
      asOf: asOf,
    );
    expect(out, contains('Contraception: Combined pill'));
    expect(out, contains('since 2024-06-15'));
  });

  test('breastfeeding true is rendered', () {
    final out = buildProfileBlock(
      settings: _settings(breastfeeding: true),
      asOf: asOf,
    );
    expect(out, contains('Breastfeeding: yes'));
  });

  test('breastfeeding true with since date includes the date', () {
    final sinceDate = DateTime(2024, 8, 20);
    final out = buildProfileBlock(
      settings: _settings(
        breastfeeding: true,
        breastfeedingSince: sinceDate,
      ),
      asOf: asOf,
    );
    expect(out, contains('Breastfeeding: yes'));
    expect(out, contains('since 2024-08-20'));
  });

  test('breastfeeding false is rendered', () {
    final out = buildProfileBlock(
      settings: _settings(breastfeeding: false),
      asOf: asOf,
    );
    expect(out, contains('Breastfeeding: no'));
  });

  test('breastfeeding null (never asked) emits nothing', () {
    final out = buildProfileBlock(
      settings: _settings(breastfeeding: null),
      asOf: asOf,
    );
    expect(out, isEmpty);
  });

  test('malformed JSON in knownDiagnoses is treated as absent', () {
    final out = buildProfileBlock(
      settings: _settings(knownDiagnoses: '{this is not valid json [}'),
      asOf: asOf,
    );
    expect(out, isEmpty,
        reason: 'Malformed JSON should degrade gracefully to empty output');
  });

  test('empty array in knownDiagnoses produces no diagnoses line', () {
    final out = buildProfileBlock(
      settings: _settings(knownDiagnoses: jsonEncode([])),
      asOf: asOf,
    );
    expect(out, isEmpty);
  });

  DailyLog makeLog({
    required DateTime date,
    String symptoms = '{}',
    String? mood,
    String? notes,
    FlowIntensity? flow,
    double? bbt,
    String? opk,
  }) =>
      DailyLog(
        id: 1,
        date: date,
        flow: flow,
        symptoms: symptoms,
        mood: mood,
        notes: notes,
        bbt: bbt,
        opk: opk,
        createdAt: date,
        updatedAt: date,
      );

  group('day lines', () {
    test('labels the day with cycle day and phase', () {
      final line = buildDayLine(
        log: makeLog(date: DateTime(2026, 9, 1)),
        cycleDay: 19,
        phase: CyclePhase.luteal,
        medicationNames: const {},
      );
      expect(line, contains('day 19'));
      expect(line, contains('luteal'));
    });

    test('a day outside any cycle is labelled unknown, never guessed', () {
      final line = buildDayLine(
        log: makeLog(date: DateTime(2026, 9, 1)),
        cycleDay: null,
        phase: CyclePhase.unknown,
        medicationNames: const {},
      );
      expect(line, contains('phase unknown'));
      expect(line, isNot(contains('day null')));
    });

    test('carries the reserved groups the doctor PDF excludes', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({
            'cm_eggwhite': true,
            'slf_masturbation': true,
            'sex_unprotected': true,
            'vag_itching': true,
          }),
        ),
        cycleDay: 14,
        phase: CyclePhase.ovulatory,
        medicationNames: const {},
      );
      expect(line, contains('Egg-white'));
      expect(line, contains('Masturbation'));
      expect(line, contains('Unprotected'));
      expect(line, contains('Itching'));
    });

    test('a zero metric is omitted, never sent as a reading', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'pain': 0, 'weight': 0, 'sleep': 7}),
        ),
        cycleDay: 3,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, isNot(contains('pain')));
      expect(line, isNot(contains('weight')));
      expect(line, contains('sleep 7'));
    });

    test('libido modern encoding (lbd_ prefix)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'lbd_high': true}),
        ),
        cycleDay: 10,
        phase: CyclePhase.follicular,
        medicationNames: const {},
      );
      expect(line, contains('libido:'));
      expect(line, contains('High'));
    });

    test('libido legacy encoding (shx_high_libido)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'shx_high_libido': true}),
        ),
        cycleDay: 10,
        phase: CyclePhase.follicular,
        medicationNames: const {},
      );
      expect(line, contains('libido:'));
      expect(line, contains('High'));
    });

    test('sexual health group (shx_ prefix)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'shx_condom': true}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('sexual health:'));
      expect(line, contains('Condom'));
    });

    test('urinary group (urn_ prefix)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'urn_frequent': true}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('urinary:'));
      expect(line, contains('Frequent'));
    });

    test('digestion group (dig_ prefix)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'dig_gas': true}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('digestion:'));
      expect(line, contains('Gas'));
    });

    test('skin group (skin_ prefix)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'skin_oily': true}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('skin:'));
    });

    test('habits group (habit_ prefix)', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'habit_exercise': true}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('habits:'));
    });

    test('medication mapping via medicationNames', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'med_0': true, 'med_1': true}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {0: 'Ibuprofen', 1: 'Acetaminophen'},
      );
      expect(line, contains('medication taken:'));
      expect(line, contains('Ibuprofen'));
      expect(line, contains('Acetaminophen'));
    });

    test('flow intensity renders by name', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          flow: FlowIntensity.heavy,
        ),
        cycleDay: 2,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('flow:'));
      expect(line, contains('heavy'));
    });

    test('mood renders with label lookup', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          mood: 'irritable',
        ),
        cycleDay: 14,
        phase: CyclePhase.ovulatory,
        medicationNames: const {},
      );
      expect(line, contains('mood:'));
      expect(line, contains('Irritable'));
    });

    test('bbt temperature reading carries an explicit Celsius unit', () {
      // Unlabelled, a model could read the canonical-Celsius value as
      // Fahrenheit — the day entry form's own BBT field carries a `°C`
      // suffix, so the context sent about it must too.
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          bbt: 36.7,
        ),
        cycleDay: 15,
        phase: CyclePhase.luteal,
        medicationNames: const {},
      );
      expect(line, contains('temperature 36.7°C'));
    });

    test('opk ovulation test result renders through the label lookup', () {
      // Was previously the one place in this file that printed the stored
      // key raw instead of through `kOpkOptions` — the raw key happens to be
      // lowercase ('positive'), the label capitalised ('Positive'), so this
      // also pins that the label — not the column value — is what ships.
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          opk: 'positive',
        ),
        cycleDay: 14,
        phase: CyclePhase.ovulatory,
        medicationNames: const {},
      );
      expect(line, contains('ovulation test: Positive'));
    });

    test('an unrecognised opk value is dropped, never printed raw', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          opk: 'some_future_key',
        ),
        cycleDay: 14,
        phase: CyclePhase.ovulatory,
        medicationNames: const {},
      );
      expect(line, isNot(contains('ovulation test')));
      expect(line, isNot(contains('some_future_key')));
    });

    test('plain symptom from decodeSymptoms path', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'cramps': true}),
        ),
        cycleDay: 2,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('symptoms:'));
      expect(line, contains('Cramps'));
    });

    test('user notes are included and trimmed', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          notes: '  test note  ',
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('note: test note'));
      expect(line, isNot(contains('  ')));
    });

    test('empty notes are omitted', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          notes: '   ',
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, isNot(contains('note')));
    });

    test('metrics water, energy, stress, sleep_quality are included when non-zero', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({
            'water': 8,
            'energy': 4,
            'stress': 3,
            'sleep_quality': 5,
          }),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('water 8'));
      expect(line, contains('energy 4'));
      expect(line, contains('stress 3'));
      expect(line, contains('sleep_quality 5'));
    });

    test('metrics water, energy, stress, sleep_quality are omitted when zero', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({
            'water': 0,
            'energy': 0,
            'stress': 0,
            'sleep_quality': 0,
          }),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, isNot(contains('water')));
      expect(line, isNot(contains('energy')));
      expect(line, isNot(contains('stress')));
      expect(line, isNot(contains('sleep_quality')));
    });

    test('weight metric carries an explicit kg unit', () {
      // Unlabelled, a model could read the canonical-kg value as pounds —
      // the profile block already says `kg` for the same value, so the
      // per-day metric must too.
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({'weight': 62.5}),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('weight 62.5 kg'));
    });

    test('unknown option keys are dropped, never printed raw', () {
      final line = buildDayLine(
        log: makeLog(
          date: DateTime(2026, 9, 1),
          symptoms: jsonEncode({
            'vag_unknown_key': true,
            'vag_itching': true,
          }),
        ),
        cycleDay: 5,
        phase: CyclePhase.menstrual,
        medicationNames: const {},
      );
      expect(line, contains('vaginal:'));
      expect(line, contains('Itching'));
      expect(line, isNot(contains('unknown_key')));
      expect(line, isNot(contains('vag_unknown_key')));
    });
  });

  group('full context', () {
    test('is empty when there is nothing to say', () {
      final out = buildHealthContext(
        logs: const [],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, isEmpty);
    });

    test('is delimited so the model can tell data from instructions', () {
      final out = buildHealthContext(
        logs: [makeLog(date: DateTime(2026, 9, 10), flow: FlowIntensity.light)],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, startsWith(kHealthContextOpenDelimiter));
      expect(out, endsWith(kHealthContextCloseDelimiter));
    });

    test('window boundary: retains log at exactly asOf - windowDays', () {
      // asOf = 2026-09-14, windowDays = 90 → cutoff = 2026-06-16
      final atBoundary = DateTime(2026, 6, 16);
      final beforeBoundary = DateTime(2026, 6, 15);
      final out = buildHealthContext(
        logs: [
          makeLog(date: atBoundary, flow: FlowIntensity.light),
          makeLog(date: beforeBoundary, flow: FlowIntensity.light),
        ],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
        windowDays: 90,
      );
      expect(out, contains('2026-06-16'));
      expect(out, isNot(contains('2026-06-15')));
    });

    test('drops days older than the window', () {
      final out = buildHealthContext(
        logs: [
          makeLog(date: DateTime(2026, 9, 10), flow: FlowIntensity.light),
          makeLog(date: DateTime(2025, 1, 1), flow: FlowIntensity.light),
        ],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, contains('2026-09-10'));
      expect(out, isNot(contains('2025-01-01')));
    });

    test('prediction: null does not crash or invent data', () {
      final out = buildHealthContext(
        logs: [makeLog(date: DateTime(2026, 9, 10), flow: FlowIntensity.light)],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, isNotEmpty);
      expect(out, isNot(contains('Cycle summary')));
    });

    test('cycleDay inside a completed cycle is computed correctly', () {
      final cycle = Cycle(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 19),
        lengthDays: 28,
      );
      final log = makeLog(date: DateTime(2026, 8, 20)); // day 6 of cycle
      final out = buildHealthContext(
        logs: [log],
        cycles: [cycle],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, contains('day 6'));
    });

    test('cycleDay in open cycle after period ends is computed correctly', () {
      // Open cycle: period 8/15-8/19, runs to asOf (2026-09-14)
      final openCycle = Cycle(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 19),
        lengthDays: null, // open
      );
      final log = makeLog(date: DateTime(2026, 9, 10)); // day 27 of open cycle
      final out = buildHealthContext(
        logs: [log],
        cycles: [openCycle],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, contains('day 27'));
    });

    test('an open cycle stops attributing days past a plausible ceiling', () {
      // Someone stopped logging for months: the only cycle on record started
      // 2026-01-01, well over kMaxOpenCycleDays (90) before asOf
      // (2026-09-14). Without a ceiling, `asOf` would read as "day 257" —
      // a number no real cycle produces. Capped, it falls outside the open
      // cycle entirely and reads "(phase unknown)" like any other
      // unattributed day.
      final openCycle = Cycle(
        start: DateTime(2026, 1, 1),
        end: DateTime(2026, 1, 5),
        lengthDays: null, // open
      );
      final log = makeLog(date: asOf);
      final out = buildHealthContext(
        logs: [log],
        cycles: [openCycle],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, isNot(contains('day 257')));
      expect(out, contains('(phase unknown)'));
    });

    test('days outside any cycle are marked phase unknown', () {
      final cycle = Cycle(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 19),
        lengthDays: 28,
      );
      final beforeCycle = makeLog(date: DateTime(2026, 8, 1));
      final out = buildHealthContext(
        logs: [beforeCycle],
        cycles: [cycle],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, contains('phase unknown'));
    });

    test('prediction: null with non-empty cycles does not guess phases', () {
      final cycle = Cycle(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 19),
        lengthDays: null,
      );
      // Day in open cycle but no prediction → should be unknown, not guessed
      final dayAfterPeriod = makeLog(date: DateTime(2026, 9, 10));
      final out = buildHealthContext(
        logs: [dayAfterPeriod],
        cycles: [cycle],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      // Day 27 of cycle, phase unknown because no prediction for today
      // When cycleDay is set, phase renders as "day N, unknown" not "phase unknown"
      expect(out, contains('day 27'));
      expect(out, contains('unknown'));
    });

    test('only asOf date uses live prediction phase, not DateTime.now()', () {
      // Use an asOf far from today to ensure test fails if code reverts to DateTime.now()
      final testAsOf = DateTime(2020, 3, 15);
      final cycle = Cycle(
        start: DateTime(2020, 3, 1),
        end: DateTime(2020, 3, 5),
        lengthDays: 28,
      );
      final pred = PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 2.0,
        averagePeriodLength: 5,
        cyclesTracked: 1,
        confidence: PredictionConfidence.low,
        lastPeriodStart: DateTime(2020, 3, 1),
        cycleDay: 15,
        currentPhase: CyclePhase.luteal,
        nextPeriodStart: DateTime(2020, 3, 29),
        nextPeriodWindowStart: DateTime(2020, 3, 28),
        nextPeriodWindowEnd: DateTime(2020, 3, 30),
        ovulationDay: DateTime(2020, 3, 15),
        fertileWindowStart: DateTime(2020, 3, 13),
        fertileWindowEnd: DateTime(2020, 3, 17),
        pmsWindowStart: DateTime(2020, 3, 24),
        pmsWindowEnd: DateTime(2020, 3, 28),
      );
      // testAsOf gets live prediction phase
      final onTestDate = makeLog(date: testAsOf);
      // Historical date does not
      final historical = makeLog(date: DateTime(2020, 3, 10));
      final out = buildHealthContext(
        logs: [historical, onTestDate],
        cycles: [cycle],
        prediction: pred,
        medications: const [],
        settings: _settings(),
        asOf: testAsOf,
      );
      // testAsOf (day 15) should show luteal (from prediction)
      final lines = out.split('\n');
      final testDateLine = lines.firstWhere((l) => l.contains('2020-03-15'));
      expect(testDateLine, contains('luteal'));
      // Historical date should show unknown (no prediction for past dates)
      final historicalLine = lines.firstWhere((l) => l.contains('2020-03-10'));
      expect(historicalLine, contains('unknown'));
    });

    test('empty logs with non-empty profile shows profile only', () {
      final out = buildHealthContext(
        logs: const [],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(
          dateOfBirth: DateTime(1996, 3, 2),
          heightCm: 165,
          profileWeightKg: 60,
        ),
        asOf: asOf,
      );
      expect(out, contains('About this person'));
      expect(out, contains('Age: 30'));
      expect(out, isNot(contains('Daily log')));
    });

    test('medication id→name map is built and used in daily lines', () {
      // Test that medications list is converted to id→name map
      // and that map is actually passed to buildDayLine.
      final log = makeLog(
        date: DateTime(2026, 9, 10),
        symptoms: jsonEncode({'med_7': true, 'med_99': true}),
      );
      // Create actual Medication objects with specific ids and names
      final med7 = Medication(
        id: 7,
        name: 'Metformin',
        type: null,
        schedule: null,
        enabled: true,
      );
      final med99 = Medication(
        id: 99,
        name: 'Aspirin',
        type: null,
        schedule: null,
        enabled: true,
      );
      final out = buildHealthContext(
        logs: [log],
        cycles: const [],
        prediction: null,
        medications: [med7, med99],
        settings: _settings(),
        asOf: asOf,
      );
      // The medication names must appear in the output
      expect(out, contains('medication taken:'));
      expect(out, contains('Metformin'));
      expect(out, contains('Aspirin'));
    });

    test('asOf carries no time component; midnight is used for boundaries',
        () {
      // Test with an asOf that has a time component (noon).
      final asOfWithTime = DateTime(2026, 9, 14, 12, 30);
      final atBoundary = DateTime(2026, 6, 16); // Exactly 90 days before midnight
      final out = buildHealthContext(
        logs: [makeLog(date: atBoundary)],
        cycles: const [],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOfWithTime,
        windowDays: 90,
      );
      // The boundary should still work because asOf is normalized to midnight.
      expect(out, contains('2026-06-16'));
    });

    test('period (menstrual) phase is returned for days in cycle bleeding window',
        () {
      final cycle = Cycle(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 19),
        lengthDays: 28,
      );
      final periodDay = makeLog(date: DateTime(2026, 8, 17));
      final out = buildHealthContext(
        logs: [periodDay],
        cycles: [cycle],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, contains('menstrual'));
    });

    test('multi-cycle boundary: cycles[i+1].start branch executes with multiple cycles',
        () {
      // Two completed cycles; a cycle runs from start to day-before-next-start
      final cycle1 = Cycle(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 5),
        lengthDays: 28,
      );
      final cycle2 = Cycle(
        start: DateTime(2026, 7, 29),
        end: DateTime(2026, 8, 2),
        lengthDays: 28,
      );
      final dayInCycle1Period = makeLog(date: DateTime(2026, 7, 3)); // day 3
      final dayInCycle1PostPeriod = makeLog(date: DateTime(2026, 7, 15)); // day 15, post-period but still in cycle1
      final dayInCycle2 = makeLog(date: DateTime(2026, 7, 30)); // day 2 of cycle2
      final dayBeforeCycle1 = makeLog(date: DateTime(2026, 6, 30)); // before any cycle
      final out = buildHealthContext(
        logs: [dayBeforeCycle1, dayInCycle1Period, dayInCycle1PostPeriod, dayInCycle2],
        cycles: [cycle1, cycle2],
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      final lines = out.split('\n');
      // Day before cycle1 should show phase unknown
      final beforeLine = lines.firstWhere((l) => l.contains('2026-06-30'));
      expect(beforeLine, contains('phase unknown'));
      // Day in cycle1 period should show day 3
      final cycle1PeriodLine = lines.firstWhere((l) => l.contains('2026-07-03'));
      expect(cycle1PeriodLine, contains('day 3'));
      // Day in cycle1 post-period should show day 15
      final cycle1PostLine = lines.firstWhere((l) => l.contains('2026-07-15'));
      expect(cycle1PostLine, contains('day 15'));
      // Day in cycle2 should show day 2
      final cycle2Line = lines.firstWhere((l) => l.contains('2026-07-30'));
      expect(cycle2Line, contains('day 2'));
    });

    test('cycle-summary renders when prediction has cyclesTracked > 0', () {
      final pred = PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1.5,
        averagePeriodLength: 5,
        cyclesTracked: 3,
        confidence: PredictionConfidence.medium,
        lastPeriodStart: DateTime(2026, 9, 1),
        cycleDay: 13,
        currentPhase: CyclePhase.follicular,
        nextPeriodStart: DateTime(2026, 9, 29),
        nextPeriodWindowStart: DateTime(2026, 9, 28),
        nextPeriodWindowEnd: DateTime(2026, 9, 30),
        ovulationDay: DateTime(2026, 9, 15),
        fertileWindowStart: DateTime(2026, 9, 13),
        fertileWindowEnd: DateTime(2026, 9, 17),
        pmsWindowStart: DateTime(2026, 9, 24),
        pmsWindowEnd: DateTime(2026, 9, 28),
      );
      final out = buildHealthContext(
        logs: [makeLog(date: DateTime(2026, 9, 10))],
        cycles: const [],
        prediction: pred,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      expect(out, contains('Cycle summary'));
      expect(out, contains('Cycles tracked: 3'));
      expect(out, contains('Average cycle length: 28 days'));
      expect(out, contains('Average period length: 5 days'));
    });

    test('out-of-order cycles are sorted internally and work correctly', () {
      // Pass cycles in reverse order to test internal sorting
      final cycle2 = Cycle(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 19),
        lengthDays: 28,
      );
      final cycle1 = Cycle(
        start: DateTime(2026, 7, 18),
        end: DateTime(2026, 7, 22),
        lengthDays: 28,
      );
      // Pass in reverse order (cycle2, cycle1)
      final dayInCycle1 = makeLog(date: DateTime(2026, 7, 20)); // should be day 3
      final out = buildHealthContext(
        logs: [dayInCycle1],
        cycles: [cycle2, cycle1], // reversed order
        prediction: null,
        medications: const [],
        settings: _settings(),
        asOf: asOf,
      );
      // Even with reversed input, day should be correctly computed as day 3
      expect(out, contains('day 3'));
    });
  });
}
