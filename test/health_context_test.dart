import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
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

  DailyLog makeLog({required DateTime date, String symptoms = '{}', String? mood, String? notes, FlowIntensity? flow}) =>
      DailyLog(
        id: 1,
        date: date,
        flow: flow,
        symptoms: symptoms,
        mood: mood,
        notes: notes,
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
      expect(line, contains('Egg white'));
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
  });
}
