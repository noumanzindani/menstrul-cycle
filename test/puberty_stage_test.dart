import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/puberty_stage.dart';

void main() {
  final answered = DateTime(2026, 9, 23);
  DateTime bornAged(int years) => DateTime(2026 - years, 1, 1);

  PubertyAssessment? assess(String? b, String? p, {int? age}) => assessPuberty(
        breastStage: b,
        pubicStage: p,
        dateOfBirth: age == null ? null : bornAged(age),
        answeredOn: answered,
      );

  test('stage keys map to 1-5; unknown keys map to null', () {
    expect(pubertyStageNumber('tan_b1'), 1);
    expect(pubertyStageNumber('tan_p5'), 5);
    expect(pubertyStageNumber('tan_b_prefer_not'), isNull,
        reason: 'the removed opt-out reads as unanswered, not as a stage');
    expect(pubertyStageNumber('tan_b9'), isNull);
    expect(pubertyStageNumber(null), isNull);
  });

  test('nothing to assess when both stages are unanswered', () {
    expect(assess(null, null, age: 12), isNull);
  });

  test('neither stage list offers an opt-out', () {
    expect(kBreastStageOptions.map((o) => o.stage), [1, 2, 3, 4, 5]);
    expect(kPubicStageOptions.map((o) => o.stage), [1, 2, 3, 4, 5]);
  });

  test('an adult at B5/P5 is typical', () {
    final a = assess('tan_b5', 'tan_p5', age: 30)!;
    expect(a.typical, isTrue);
    expect(a.label, 'Typical for age');
  });

  test('B3 at 8 is early; B3 at 9 is not', () {
    expect(assess('tan_b3', null, age: 8)!.flags, {PubertyFlag.early});
    expect(assess('tan_b3', null, age: 9)!.typical, isTrue);
  });

  test('P2 at 8 is within range (the cut-off is BEFORE 8)', () {
    expect(assess(null, 'tan_p2', age: 8)!.typical, isTrue);
  });

  test('B1 at 13 is delayed; B1 at 12 is not', () {
    expect(assess('tan_b1', null, age: 13)!.flags, {PubertyFlag.delayed});
    expect(assess('tan_b1', null, age: 12)!.typical, isTrue);
  });

  test('P1 is allowed until 14', () {
    expect(assess(null, 'tan_p1', age: 13)!.typical, isTrue);
    expect(assess(null, 'tan_p1', age: 14)!.flags, {PubertyFlag.delayed});
  });

  test('stages two or more apart are discordant, with or without an age', () {
    expect(assess('tan_b4', 'tan_p2')!.flags, {PubertyFlag.discordant});
    expect(assess('tan_b3', 'tan_p2')!.typical, isTrue);
    expect(assess('tan_b1', 'tan_p3', age: 13)!.flags,
        {PubertyFlag.delayed, PubertyFlag.discordant});
    expect(assess('tan_b1', 'tan_p3', age: 13)!.label,
        'Later than usual; B and P out of step');
  });

  test('age is taken at the ANSWER date, not today', () {
    // Turned 13 on 2026-10-01, answered a week before: still 12 then.
    final a = assessPuberty(
      breastStage: 'tan_b1',
      pubicStage: null,
      dateOfBirth: DateTime(2013, 10, 1),
      answeredOn: answered,
    )!;
    expect(a.typical, isTrue);
  });

  test('without a birth date only discordance can be read', () {
    expect(assess('tan_b1', 'tan_p1')!.typical, isTrue);
  });
}
