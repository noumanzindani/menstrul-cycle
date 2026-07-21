import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

/// Structural guards for the expanded tracking catalog. The new groups ride the
/// existing day-tags JSON under reserved prefixes, so the invariants that keep
/// them out of the symptom chips (and the doctor PDF) have to be asserted, not
/// assumed from the naming convention.
void main() {
  test('new group keys are reserved and group-decodable', () {
    final json = encodeDayTags(
        flags: {'cramps', 'urn_frequent', 'dig_gas', 'skin_rash'});

    expect(decodeSymptoms(json), contains('cramps'));
    expect(decodeSymptoms(json), isNot(contains('urn_frequent')));
    expect(decodeSymptoms(json), isNot(contains('dig_gas')));
    expect(decodeSymptoms(json), isNot(contains('skin_rash')));

    expect(decodeGroup(json, kUrineKeyPrefix), {'urn_frequent'});
    expect(decodeGroup(json, kDigestionKeyPrefix), {'dig_gas'});
    expect(decodeGroup(json, kSkinKeyPrefix), {'skin_rash'});
  });

  test('sleep quality is a number, so it never reads as a symptom', () {
    final json = encodeDayTags(numbers: {kMetricSleepQuality: 4});
    expect(decodeSymptoms(json), isEmpty);
    expect(decodeNumber(json, kMetricSleepQuality), 4);
    // Distinct from sleep hours — exact-key lookup, no prefix confusion.
    expect(decodeNumber(json, kMetricSleep), isNull);
  });

  test('every option key is globally unique', () {
    final keys = [
      ...kSymptomOptions,
      ...kEmotionalOptions,
      ...kMoodOptions,
      ...kSexOptions,
      ...kDischargeOptions,
      ...kVaginalOptions,
      ...kSexualHealthOptions,
      ...kHabitOptions,
      ...kOpkOptions,
      ...kUrineOptions,
      ...kDigestionOptions,
      ...kSkinOptions,
    ].map((o) => o.key).toList();

    expect(keys.toSet().length, keys.length,
        reason: 'duplicate option key across catalog lists');
  });

  test('no NEW option label collides with an existing one', () {
    // find.text is exact-match and throws on multi-match, so a duplicate
    // label both confuses the UI and makes widget tests unwritable.
    final existing = [
      ...kSymptomOptions,
      ...kEmotionalOptions,
      ...kMoodOptions,
      ...kSexOptions,
      ...kDischargeOptions,
      ...kSexualHealthOptions,
      ...kHabitOptions,
    ].map((o) => o.label).toSet();

    final added = [
      ...kUrineOptions,
      ...kDigestionOptions,
      ...kSkinOptions,
      ...kVaginalOptions,
    ];

    for (final o in added) {
      expect(existing.contains(o.label), isFalse,
          reason: '"${o.label}" (${o.key}) duplicates an existing label');
    }
  });

  test('no new prefix would capture a pre-existing key', () {
    // A badly chosen prefix ("skin" without the underscore) would silently
    // pull existing symptoms out of decodeSymptoms and out of the doctor PDF.
    final legacy = [
      ...kSymptomOptions,
      ...kEmotionalOptions,
      ...kMoodOptions,
    ].map((o) => o.key);

    for (final p in [kUrineKeyPrefix, kDigestionKeyPrefix, kSkinKeyPrefix]) {
      for (final k in legacy) {
        expect(k.startsWith(p), isFalse,
            reason: '$k would be captured by prefix $p');
      }
    }
  });
}
