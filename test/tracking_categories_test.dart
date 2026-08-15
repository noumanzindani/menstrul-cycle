import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/tracking_categories.dart';

void main() {
  test('ids are unique', () {
    final ids = kTrackingCategories.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('later-added categories default OFF, original ones default ON', () {
    Set<String> idsWhere(bool on) => kTrackingCategories
        .where((c) => c.defaultOn == on)
        .map((c) => c.id)
        .toSet();

    // Every category added after the original set ships OFF, so no existing
    // user's day editor grows a section unasked. Add new ids here on purpose —
    // an accidental `defaultOn: true` should break this test.
    expect(idsWhere(false), {
      kCatSleepQuality,
      kCatUrine,
      kCatDigestion,
      kCatSkin,
      kCatWeight,
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
