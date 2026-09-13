import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

/// Structural guards for the gynaecological-intake groups (Tier 1 + Tier 2).
///
/// Two of these encode decisions that are easy to reverse by accident:
///
/// - The intimate group (masturbation, libido) is RESERVED, so it can never
///   reach the symptom chips, Insights symptom counts or the doctor PDF. It
///   syncs like every other day tag — that was a deliberate owner decision —
///   but "syncs" and "appears in a document you hand a clinician" are
///   different questions and only the first was answered yes.
/// - The heavy-bleeding markers are deliberately NOT reserved. They are the
///   red flags the report exists to carry, so they are plain symptom keys and
///   ride `decodeSymptoms` into the PDF like cramps or a migraine.
void main() {
  group('intimate group is reserved, not a symptom', () {
    test('masturbation and libido never read as symptoms', () {
      final json = encodeDayTags(
          flags: {'cramps', 'slf_masturbation', 'lbd_high'});

      expect(decodeSymptoms(json), {'cramps'});
      expect(decodeGroup(json, kIntimacyKeyPrefix), {'slf_masturbation'});
    });

    test('both new prefixes are registered as reserved', () {
      expect(kReservedTagPrefixes, contains(kIntimacyKeyPrefix));
      expect(kReservedTagPrefixes, contains(kLibidoKeyPrefix));
    });
  });

  group('libido: a three-point scale that does not blank the old boolean', () {
    test('the new single-select round-trips', () {
      expect(decodeLibido(encodeDayTags(flags: {'lbd_low'})), 'lbd_low');
      expect(decodeLibido(encodeDayTags(flags: {'lbd_medium'})), 'lbd_medium');
      expect(decodeLibido(encodeDayTags(flags: {'lbd_high'})), 'lbd_high');
    });

    test('a day logged under the OLD boolean still reads as high', () {
      // `shx_high_libido` shipped for months and users logged it. The day-tags
      // blob has no migration path, so the decoder is the only place this can
      // be honoured — and dropping it would silently blank real answers.
      final legacy = encodeDayTags(flags: {'shx_high_libido'});
      expect(decodeLibido(legacy), 'lbd_high');
    });

    test('the new key wins when a day carries both', () {
      final both =
          encodeDayTags(flags: {'shx_high_libido', 'lbd_low'});
      expect(decodeLibido(both), 'lbd_low');
    });

    test('no libido logged -> null, and null/empty are tolerated', () {
      expect(decodeLibido(encodeDayTags(flags: {'cramps'})), isNull);
      expect(decodeLibido(null), isNull);
      expect(decodeLibido(''), isNull);
      expect(decodeLibido('{'), isNull);
    });

    test('the old key is gone from the sexual-health chips', () {
      // Still decodable (above), just no longer offered — the scale replaced it.
      expect(kSexualHealthOptions.map((o) => o.key),
          isNot(contains('shx_high_libido')));
    });
  });

  group('Tier 2 red flags', () {
    test('bleeding after sex is a sexual-health flag, so PDF-excluded', () {
      expect(kSexualHealthOptions.map((o) => o.key),
          contains('shx_post_coital'));
      expect(decodeSymptoms(encodeDayTags(flags: {'shx_post_coital'})),
          isEmpty);
    });

    test('heavy-bleeding markers ARE plain symptoms, so they reach the PDF',
        () {
      final keys = kSymptomOptions.map((o) => o.key);
      expect(keys, contains(kSymptomLargeClots));
      expect(keys, contains(kSymptomSoakingHourly));

      final json =
          encodeDayTags(flags: {kSymptomLargeClots, kSymptomSoakingHourly});
      expect(decodeSymptoms(json),
          {kSymptomLargeClots, kSymptomSoakingHourly});
    });
  });

  group('Tier 1 profile vocabularies', () {
    test('contraception is a single-select with a real "none"', () {
      expect(kContraceptionOptions, isNotEmpty);
      expect(kContraceptionOptions.map((o) => o.key),
          contains(kContraceptionNone));
      for (final o in kContraceptionOptions) {
        expect(o.key, startsWith('contra_'));
      }
    });

    test('only the ovulation-suppressing methods are listed as such', () {
      // The set gates the fertile window (prediction_service). A method wrongly
      // in it silently removes a real signal; one wrongly out of it shows a
      // fertile window to somebody who does not ovulate.
      final known = {for (final o in kContraceptionOptions) o.key};
      expect(kOvulationSuppressingContraception, isNotEmpty);
      expect(known.containsAll(kOvulationSuppressingContraception), isTrue,
          reason: 'suppressing set names a method that is not offered');
      expect(kOvulationSuppressingContraception,
          isNot(contains(kContraceptionNone)));
      expect(kOvulationSuppressingContraception,
          isNot(contains('contra_copper_iud')),
          reason: 'a copper IUD is non-hormonal — ovulation continues');
    });

    test('diagnoses are a dx_-prefixed multi-select', () {
      expect(kDiagnosisOptions, isNotEmpty);
      for (final o in kDiagnosisOptions) {
        expect(o.key, startsWith('dx_'));
      }
    });
  });

  test('every new option key stays globally unique', () {
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
      ...kIntimacyOptions,
      ...kLibidoOptions,
      ...kContraceptionOptions,
      ...kDiagnosisOptions,
    ].map((o) => o.key).toList();
    expect(keys.toSet().length, keys.length,
        reason: 'duplicate option key across catalog lists');
  });

  test('every new option label stays globally unique', () {
    // find.text is exact-match and throws on multi-match, so a duplicate label
    // both confuses the UI and makes widget tests unwritable.
    final labels = [
      ...kSymptomOptions,
      ...kEmotionalOptions,
      ...kMoodOptions,
      ...kSexOptions,
      ...kDischargeOptions,
      ...kVaginalOptions,
      ...kSexualHealthOptions,
      ...kHabitOptions,
      ...kUrineOptions,
      ...kDigestionOptions,
      ...kSkinOptions,
      ...kIntimacyOptions,
      ...kLibidoOptions,
    ].map((o) => o.label).toList();
    expect(labels.toSet().length, labels.length,
        reason: 'duplicate option label across catalog lists');
  });
}
