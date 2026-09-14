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
}
