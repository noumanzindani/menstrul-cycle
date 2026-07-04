import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';

void main() {
  group('sex logging shares the day-tags JSON but stays separated', () {
    test('kSexOptions keys are all sex_-prefixed', () {
      expect(kSexOptions, isNotEmpty);
      for (final o in kSexOptions) {
        expect(o.key, startsWith('sex_'),
            reason: 'sex keys must be prefixed so they can be separated');
      }
    });

    test('a sex key round-trips and does not leak into symptoms', () {
      final json = encodeSymptoms({'cramps', 'sex_protected'});
      expect(decodeSymptoms(json), {'cramps'}); // sex excluded from symptoms
      expect(decodeSex(json), 'sex_protected'); // sex read separately
    });

    test('no sex logged -> decodeSex returns null', () {
      expect(decodeSex(encodeSymptoms({'cramps'})), isNull);
    });

    test('decodeSex tolerates null/empty', () {
      expect(decodeSex(null), isNull);
      expect(decodeSex('{}'), isNull);
    });
  });
}
