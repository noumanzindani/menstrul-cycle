import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/tracking_categories.dart';

void main() {
  test('ids are unique', () {
    final ids = kTrackingCategories.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('the four new categories default OFF, existing ones default ON', () {
    Set<String> idsWhere(bool on) => kTrackingCategories
        .where((c) => c.defaultOn == on)
        .map((c) => c.id)
        .toSet();

    expect(idsWhere(false), {
      kCatSleepQuality,
      kCatUrine,
      kCatDigestion,
      kCatSkin,
    });
    expect(idsWhere(true), contains(kCatPhysicalSymptoms));
    expect(idsWhere(true), contains(kCatMedications));
  });

  test('defaultEnabledCategoryIds returns exactly the defaultOn ids', () {
    expect(
      defaultEnabledCategoryIds(),
      kTrackingCategories.where((c) => c.defaultOn).map((c) => c.id).toSet(),
    );
  });

  test('every category has a non-empty label', () {
    for (final c in kTrackingCategories) {
      expect(c.label.trim(), isNotEmpty, reason: '${c.id} has no label');
    }
  });
}
