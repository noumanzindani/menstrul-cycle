import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

/// The migration-free "rich logging" model: symptoms, sensitive health groups,
/// and numeric metrics all share the one day-tags JSON blob. Booleans stay
/// `{key:true}`; sensitive groups are namespaced (and excluded from the doctor
/// PDF); numbers are stored as real JSON numbers.
void main() {
  group('day-tags encoding', () {
    test('encodeDayTags stores plain boolean flags as symptoms', () {
      final json = encodeDayTags(flags: {'cramps', 'headache'});
      expect(decodeSymptoms(json), {'cramps', 'headache'});
    });

    test('encodeDayTags stores numeric metrics; decodeNumber round-trips', () {
      final json = encodeDayTags(numbers: {'pain': 7, 'water': 5});
      expect(decodeNumber(json, 'pain'), 7);
      expect(decodeNumber(json, 'water'), 5);
      expect(decodeNumber(json, 'sleep'), isNull);
    });

    test('numeric metrics never leak into decodeSymptoms', () {
      final json = encodeDayTags(flags: {'cramps'}, numbers: {'pain': 8});
      expect(decodeSymptoms(json), {'cramps'});
    });

    test('decodeSingle returns the one selected namespaced key, else null', () {
      final json = encodeDayTags(flags: {'cm_creamy'});
      expect(decodeSingle(json, 'cm_'), 'cm_creamy');
      expect(decodeSingle(json, 'sex_'), isNull);
    });

    // Derived from kReservedTagPrefixes rather than a hardcoded list, so every
    // prefix added later is covered without anyone remembering to edit this.
    test('decodeSymptoms excludes every reserved (sensitive/grouped) prefix', () {
      for (final prefix in kReservedTagPrefixes) {
        final key = '${prefix}example';
        final json = encodeDayTags(flags: {'cramps', key});
        expect(decodeSymptoms(json), contains('cramps'));
        expect(decodeSymptoms(json), isNot(contains(key)),
            reason: '$prefix leaked into decodeSymptoms');
        expect(decodeGroup(json, prefix), {key});
      }
    });

    test('decodeSex keeps working via the generalized single-select', () {
      final json = encodeDayTags(flags: {'sex_unprotected'});
      expect(decodeSex(json), 'sex_unprotected');
    });

    test('decodeGroup returns all selected keys under a prefix', () {
      final json =
          encodeDayTags(flags: {'vag_itching', 'vag_burning', 'cramps'});
      expect(decodeGroup(json, 'vag_'), {'vag_itching', 'vag_burning'});
      expect(decodeGroup(json, 'shx_'), isEmpty);
    });
  });

  group('symptomLabel (doctor PDF must show labels, not raw keys)', () {
    test('resolves both physical and emotional symptom keys', () {
      expect(symptomLabel('cramps'), 'Cramps'); // physical
      expect(symptomLabel('mood_swings'), 'Mood swings'); // emotional
    });

    test('falls back to the raw key for anything unknown', () {
      expect(symptomLabel('legacy_unknown'), 'legacy_unknown');
    });
  });
}
