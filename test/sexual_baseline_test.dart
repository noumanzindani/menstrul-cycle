import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

/// The signup baseline: what is TYPICALLY true, asked once at onboarding.
///
/// Deliberately a separate thing from the day tags, never merged with them. The
/// baseline answers "how often, generally"; the logs answer "what happened on
/// the 3rd". Merging the two is how a field ends up disagreeing with itself,
/// which is the whole reason frequency questions were resisted in the first
/// place — the fix is to keep both and let each answer its own question.
///
/// Stored as ONE JSON column rather than five typed ones, matching
/// `trackingCategories` and `knownDiagnoses`: the question set will grow, and a
/// column per question means a migration per question.
void main() {
  group('codec', () {
    test('a full baseline round-trips', () {
      final json = encodeSexualBaseline(
        sexFrequency: 'freq_weekly',
        soloFrequency: 'freq_rarely',
        libido: kLibidoHigh,
        history: {'shx_pain', 'vag_dryness'},
      );
      final b = decodeSexualBaseline(json);

      expect(b.sexFrequency, 'freq_weekly');
      expect(b.soloFrequency, 'freq_rarely');
      expect(b.libido, kLibidoHigh);
      expect(b.history, {'shx_pain', 'vag_dryness'});
      expect(b.isEmpty, isFalse);
    });

    test('every field is independently skippable', () {
      final b = decodeSexualBaseline(
          encodeSexualBaseline(soloFrequency: 'freq_never'));
      expect(b.soloFrequency, 'freq_never');
      expect(b.sexFrequency, isNull);
      expect(b.libido, isNull);
      expect(b.history, isEmpty);
    });

    test('a wholly skipped baseline encodes to null, not an empty object', () {
      // Null is what "never asked" looks like in the column. An empty `{}`
      // would read as "asked and answered nothing", which is a different claim
      // and would print an empty section in the doctor report.
      expect(encodeSexualBaseline(), isNull);
    });

    test('decode tolerates null, junk and the wrong shape', () {
      for (final bad in [null, '', '{', '[]', '"nope"', '{"libido":7}']) {
        final b = decodeSexualBaseline(bad);
        expect(b.isEmpty, isTrue, reason: 'decoding $bad must not throw');
      }
    });

    test('values this build does not recognise are dropped, not surfaced', () {
      // Written by a newer build. Showing `freq_from_the_future` to a user, or
      // printing it in a clinical summary, is worse than omitting it.
      final b = decodeSexualBaseline(encodeSexualBaseline(
        sexFrequency: 'freq_from_the_future',
        libido: 'lbd_from_the_future',
        history: {'shx_pain', 'not_a_real_key'},
      ));
      expect(b.sexFrequency, isNull);
      expect(b.libido, isNull);
      expect(b.history, {'shx_pain'});
    });
  });

  group('vocabulary', () {
    test('frequency is a freq_-prefixed scale including never', () {
      expect(kFrequencyOptions, isNotEmpty);
      for (final o in kFrequencyOptions) {
        expect(o.key, startsWith('freq_'));
      }
      expect(kFrequencyOptions.map((o) => o.key), contains('freq_never'));
    });

    test('history reuses the day-tag keys rather than inventing new ones', () {
      // Same vocabulary as the day editor, so "ever had pain during sex" and
      // the `shx_pain` chip can never drift into meaning different things.
      final keys = kSexualHistoryOptions.map((o) => o.key).toSet();
      expect(keys, contains('shx_pain'));
      expect(keys, contains('shx_post_coital'));

      final dayKeys = {
        for (final o in [...kSexualHealthOptions, ...kVaginalOptions]) o.key,
      };
      expect(dayKeys.containsAll(keys), isTrue,
          reason: 'a history key that is not a day-tag key would be a second '
              'vocabulary for the same fact');
    });
  });

  group('the escape options that make a required answer answerable', () {
    // Every one of these sets is now MANDATORY at signup. A required question
    // whose options do not cover the user's true situation cannot be answered
    // honestly, and the wizard deadlocks — so each multi-select set needs a
    // key meaning "none of this applies to me".
    test('sexual history offers a none-of-these key', () {
      expect(kSexualHistoryOptions.map((o) => o.key), contains(kShxNone));
    });

    test("today's sexual-health chips offer a none-of-these key", () {
      expect(kSexualHealthOptions.map((o) => o.key), contains(kShxNone));
    });

    test('the intimacy chips offer a not-today key', () {
      // Without this the only option is `slf_masturbation`, so a required
      // answer would force the user to claim they masturbated today.
      expect(kIntimacyOptions.map((o) => o.key), contains(kSoloNone));
    });

    test('the escape labels do not collide with the existing None label', () {
      // `gyn_catalog_test` enforces globally unique labels because find.text is
      // exact-match; `kSexOptions` already owns the bare word "None".
      final labels = [
        ...kSexOptions,
        ...kSexualHealthOptions,
        ...kIntimacyOptions,
      ].map((o) => o.label).toList();
      expect(labels.toSet().length, labels.length);
    });
  });

  group('the solo-baseline questions added at signup', () {
    test('ways is a multi-select with a decline option', () {
      expect(kIntimacyWaysOptions, isNotEmpty);
      for (final o in kIntimacyWaysOptions) {
        expect(o.key, startsWith('slfw_'));
      }
      expect(kIntimacyWaysOptions.map((o) => o.key), contains(kSoloWayPrivate));
    });

    test('time-to-satisfaction is a single-select with a decline option', () {
      expect(kSatisfactionTimeOptions, isNotEmpty);
      for (final o in kSatisfactionTimeOptions) {
        expect(o.key, startsWith('sat_'));
      }
      expect(
          kSatisfactionTimeOptions.map((o) => o.key), contains(kSatPrivate));
    });

    test('both round-trip through the baseline column', () {
      final json = encodeSexualBaseline(
        soloWays: {'slfw_hands', 'slfw_toy'},
        satisfactionTime: 'sat_5_15',
      );
      final b = decodeSexualBaseline(json);

      expect(b.soloWays, {'slfw_hands', 'slfw_toy'});
      expect(b.satisfactionTime, 'sat_5_15');
      expect(b.isEmpty, isFalse);
    });

    test('an unknown key from a newer build reads as not-answered', () {
      // Matches the tolerant posture of every other field: a raw
      // `slfw_from_the_future` must never reach a clinical summary.
      final b = decodeSexualBaseline(
          '{"soloWays":["slfw_nonsense"],"satisfactionTime":"sat_nonsense"}');
      expect(b.soloWays, isEmpty);
      expect(b.satisfactionTime, isNull);
    });

    test('neither field alone stops an otherwise-empty baseline being null', () {
      // The encoder returns null for "nothing answered"; adding fields must not
      // quietly turn that into an empty object.
      expect(encodeSexualBaseline(), isNull);
    });
  });
}
