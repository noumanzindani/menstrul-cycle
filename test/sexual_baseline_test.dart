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
}
