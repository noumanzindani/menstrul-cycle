import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

void main() {
  test('med_ keys are reserved (excluded from symptom chips) and group-decodable',
      () {
    final json = encodeDayTags(flags: {'cramps', 'med_3', 'med_7'});

    // Not surfaced as a symptom.
    expect(decodeSymptoms(json), contains('cramps'));
    expect(decodeSymptoms(json), isNot(contains('med_3')));

    // Retrievable as its own group.
    expect(decodeGroup(json, kMedicationKeyPrefix), {'med_3', 'med_7'});
  });
}
