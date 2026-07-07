import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/services/pregnancy_service.dart';

/// Pregnancy dating is Naegele's rule (LMP + 280 days), always presented as an
/// ESTIMATE. No medical or fetal content — just weeks/trimester for context.
void main() {
  final lmp = DateTime(2026, 1, 1);

  test('estimated due date is LMP + 280 days', () {
    expect(PregnancyService.estimatedDueDate(lmp),
        lmp.add(const Duration(days: 280)));
  });

  test('gestational age splits elapsed days into weeks + days', () {
    final ga =
        PregnancyService.gestationalAge(lmp, asOf: lmp.add(const Duration(days: 90)));
    expect(ga.weeks, 12);
    expect(ga.days, 6);
  });

  test('gestational age never goes negative before the start date', () {
    final ga = PregnancyService.gestationalAge(lmp,
        asOf: lmp.subtract(const Duration(days: 5)));
    expect(ga.weeks, 0);
    expect(ga.days, 0);
  });

  test('trimester boundaries (T1 <14 wk, T2 14–27, T3 >=28)', () {
    expect(PregnancyService.trimester(lmp, asOf: lmp.add(const Duration(days: 7 * 10))), 1);
    expect(PregnancyService.trimester(lmp, asOf: lmp.add(const Duration(days: 7 * 14))), 2);
    expect(PregnancyService.trimester(lmp, asOf: lmp.add(const Duration(days: 7 * 28))), 3);
  });
}
