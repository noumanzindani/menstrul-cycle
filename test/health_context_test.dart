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
  String? knownDiagnoses,
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
      knownDiagnoses: knownDiagnoses,
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
    expect(out, contains('22.0'));
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
}
