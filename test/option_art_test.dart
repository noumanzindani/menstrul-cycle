import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/option_art.dart';
import 'package:menstrul_track/models/enums.dart';

/// Every catalog key must be classified, every declared asset must exist, and
/// the exclusions must stay exclusions. These are pure — no DB, no pump — so
/// they run in milliseconds and are the cheapest guard in the suite.

/// Marks rendered as full-colour raster, with NO tint (`TrackArt._isRaster`).
///
/// Listed here rather than derived from the extension so that adding one is a
/// deliberate act with a visible diff. Each entry gives up three things the
/// tint provides free: the mark stops following the label colour, stops
/// adapting to the dark theme, and stops dimming when the chip is disabled.
const kRasterArt = <String>{
  // Owner decision 2026-09-14: the illustration itself is the mark. Symptoms,
  // emotional, mood, discharge, skin, OPK and habits are now ENTIRELY raster.
  // The tinted `.svg` chips left are `vag_discomfort`, the urine and digestion
  // groups, and the shared medication mark.
  'assets/track/cramps.png',
  'assets/track/acne.png',
  'assets/track/fatigue.png',
  'assets/track/nausea.png',
  'assets/track/backache.png',
  'assets/track/cravings.png',
  'assets/track/bloating.png',
  'assets/track/insomnia.png',
  'assets/track/diarrhea.png',
  'assets/track/constipation.png',
  'assets/track/dizziness.png',
  'assets/track/discharge.png',
  'assets/track/migraine.png',
  'assets/track/hot_flashes.png',
  'assets/track/night_sweats.png',
  'assets/track/pelvic_pain.png',
  'assets/track/leg_pain.png',
  'assets/track/swelling.png',
  'assets/track/fever.png',
  'assets/track/chills.png',
  // Both of these were in kNoArtKeys until the owner supplied art and reversed
  // the exclusion; see the notes at each in `option_art.dart`. Listed here so
  // that reversal is one visible line in the diff rather than an absence.
  'assets/track/tender_breasts.png',
  'assets/track/clots_large.png',
  'assets/track/headache.png',
  'assets/track/soaking_hourly.png',
  // kEmotionalOptions, complete.
  'assets/track/mood_swings.png',
  'assets/track/anxiety.png',
  'assets/track/low_mood.png',
  'assets/track/irritability.png',
  'assets/track/sensitive_emotional.png',
  'assets/track/tearful.png',
  'assets/track/low_motivation.png',
  'assets/track/brain_fog.png',
  // kMoodOptions, five of eight; anxious / irritable / angry are still SVG.
  'assets/track/calm.png',
  'assets/track/happy.png',
  'assets/track/energetic.png',
  'assets/track/sensitive.png',
  'assets/track/sad.png',
  'assets/track/anxious.png',
  'assets/track/irritable.png',
  // kDischargeOptions, complete.
  'assets/track/cm_dry.png',
  'assets/track/cm_sticky.png',
  'assets/track/cm_creamy.png',
  'assets/track/cm_watery.png',
  'assets/track/cm_eggwhite.png',
  // kVaginalOptions, six of seven.
  'assets/track/vag_itching.png',
  'assets/track/vag_burning.png',
  'assets/track/vag_dryness.png',
  'assets/track/vag_odor.png',
  'assets/track/vag_swelling.png',
  'assets/track/vag_lumps.png',
  // kSkinOptions, complete.
  'assets/track/skin_dry.png',
  'assets/track/skin_oily.png',
  'assets/track/skin_itchy.png',
  'assets/track/skin_rash.png',
  'assets/track/skin_hair_loss.png',
  'assets/track/skin_hair_oily.png',
  // kMoodOptions completed, plus kOpkOptions and kHabitOptions entire.
  'assets/track/angry.png',
  'assets/track/negative.png',
  'assets/track/positive.png',
  'assets/track/peak.png',
  'assets/track/habit_exercise.png',
  'assets/track/habit_caffeine.png',
  'assets/track/habit_alcohol.png',
  'assets/track/habit_smoking.png',
  'assets/track/habit_meditation.png',
  // Reversed out of kNoArtKeys by the owner, 2026-09-14.
  'assets/track/shx_condom.png',
  'assets/track/lbd_low.png',
  'assets/track/lbd_medium.png',
  'assets/track/lbd_high.png',
  // Not chips: the Wellbeing steppers and the BBT field. Listed here because
  // TrackArt renders them through the same raster branch.
  'assets/track/metric_water.png',
  'assets/track/metric_sleep.png',
  'assets/track/metric_energy.png',
  'assets/track/metric_stress.png',
  'assets/track/bbt.png',
  // Vaginal group completed, plus three more reversals out of kNoArtKeys.
  'assets/track/vag_discomfort.png',
  'assets/track/sex_none.png',
  'assets/track/sex_protected.png',
  'assets/track/slf_masturbation.png',
  // Not chips either: the product-change timer.
  'assets/track/product_pad.png',
  'assets/track/product_tampon.png',
};

void main() {
  const allLists = <List<TrackOption>>[
    kSymptomOptions,
    kMoodOptions,
    kSexOptions,
    kEmotionalOptions,
    kDischargeOptions,
    kVaginalOptions,
    kSexualHealthOptions,
    kOpkOptions,
    kHabitOptions,
    kUrineOptions,
    kDigestionOptions,
    kSkinOptions,
    kIntimacyOptions,
    kLibidoOptions,
  ];
  final allKeys = [for (final l in allLists) ...l.map((o) => o.key)];

  group('option art classification', () {
    // THE anti-decay mechanism. Dart cannot exhaustively check a String-keyed
    // map, so without this the failure mode is one bare chip sitting among six
    // decorated neighbours that nobody notices for months. Adding a
    // TrackOption without deciding its art now fails loudly, naming the key.
    test('every catalog key is classified exactly once', () {
      final unclassified = <String>[];
      final doubleClassified = <String>[];
      for (final key in allKeys) {
        final n =
            (kOptionArt.containsKey(key) ? 1 : 0) +
            (kNoArtKeys.contains(key) ? 1 : 0);
        if (n == 0) unclassified.add(key);
        if (n > 1) doubleClassified.add(key);
      }
      expect(
        unclassified,
        isEmpty,
        reason: 'add these to kOptionArt or kNoArtKeys',
      );
      expect(doubleClassified, isEmpty, reason: 'these are in both art sets');
    });

    // Now that the art is complete, the partition is exhaustive: 78 drawn + 11
    // deliberately undrawn. Asserting the totals makes an accidental DELETION
    // fail, which the per-key partition above cannot catch — dropping a key
    // from the catalog and from kOptionArt together leaves it consistent.
    test('the partition covers the whole catalog and nothing else', () {
      expect(kOptionArt.length + kNoArtKeys.length, allKeys.length);
      expect(kOptionArt.keys.toSet().intersection(kNoArtKeys), isEmpty);
    });

    // Guards against the sets drifting to reference options that no longer
    // exist — the reverse decay of the test above.
    test('no art set references a key that is not in the catalog', () {
      final known = allKeys.toSet();
      final ghosts = [
        ...kOptionArt.keys,
        ...kNoArtKeys,
      ].where((k) => !known.contains(k));
      expect(ghosts, isEmpty);
    });

    // The exclusions are a harm decision (shoulder-surf legibility), not a
    // backlog item. This is the only mechanical way to hold them: a test cannot
    // fail because a drawing is undignified, but it can fail because a drawing
    // exists at all where one was forbidden.
    //
    // Pinned as a LITERAL list, which it did not used to be. Until 2026-09-14
    // kNoArtKeys equalled exactly kSex + kSexualHealth + kIntimacy + kLibido
    // and was asserted against the catalog. The owner then supplied art for
    // `shx_condom` and all three `lbd_` levels, and a derived assertion cannot
    // express "those four left and nothing else may". Writing the survivors out
    // by hand keeps BOTH directions guarded: drawing one of these fails, and
    // parking an unrelated key here under cover of a harm decision fails too.
    test('exactly these keys stay text-only', () {
      const textOnly = {
        // Held for LEGIBILITY, not shoulder-surf — see option_art.dart.
        'sex_unprotected',
        // Shoulder-surf, and no art has been supplied for these.
        'shx_emergency',
        'shx_pain',
        'shx_post_coital',
      };
      expect(kNoArtKeys, textOnly);
      for (final k in textOnly) {
        expect(kOptionArt.containsKey(k), isFalse, reason: '$k was drawn');
        expect(artFor(k), isNull);
      }
    });

    // The four that left are asserted POSITIVELY, so the reversal is a fact the
    // suite states rather than an absence. Silently losing one would otherwise
    // look identical to it never having been drawn.
    test('the four reversed sensitive keys do have art', () {
      for (final k in [
        'shx_condom',
        'lbd_low',
        'lbd_medium',
        'lbd_high',
        'sex_none',
        'sex_protected',
        'slf_masturbation',
      ]) {
        expect(artFor(k), isNotNull, reason: '$k lost its art');
        expect(kNoArtKeys.contains(k), isFalse);
      }
    });
  });

  group('art assets', () {
    // flutter analyze never reads pubspec's assets: block, and a missing file
    // is a RUNTIME exception. This turns that into a test failure.
    test('every declared asset exists on disk', () {
      final missing = [
        ...kOptionArt.values,
        kMedicationArt,
        // Not chips, but just as fatal at runtime if the file is gone.
        ...kMetricArt.values,
        kBbtArt,
        ...kProductArt.values,
      ].where((p) => !File(p).existsSync());
      expect(missing, isEmpty);
    });

    test('no two options share an asset', () {
      final paths = kOptionArt.values.toList();
      expect(
        paths.toSet().length,
        paths.length,
        reason: 'a duplicated path is almost always a copy-paste slip',
      );
    });

    // BlendMode.srcIn flattens the drawing to a single tint, so a multi-colour
    // file silently loses its palette. Cheap structural proxy: the art is
    // authored with one ink colour.
    //
    // Raster marks are exempt because TrackArt does not tint them at all -- but
    // the exemption is ENUMERATED, never inferred from the extension alone. A
    // `.png` is otherwise a way to skip the monochrome rule by accident, which
    // is exactly the kind of silent opt-out this suite exists to prevent.
    test('every tinted asset is monochrome', () {
      final offenders = <String>[];
      for (final p in [
        ...kOptionArt.values,
        kMedicationArt,
        ...kMetricArt.values,
        kBbtArt,
        ...kProductArt.values,
      ]) {
        if (kRasterArt.contains(p)) continue;
        final colours = RegExp(r'(?:fill|stroke)="(#[0-9a-fA-F]{3,8})"')
            .allMatches(File(p).readAsStringSync())
            .map((m) => m.group(1)!.toLowerCase())
            .toSet();
        if (colours.length > 1) offenders.add('$p -> $colours');
      }
      expect(offenders, isEmpty);
    });

    // The other half of the exemption, and the half that actually bites: a new
    // raster asset must be added to kRasterArt deliberately. Without this, any
    // future `.png` skips the monochrome check merely by existing.
    test('every non-SVG asset is a declared raster mark', () {
      final undeclared = [
        ...kOptionArt.values,
        kMedicationArt,
        ...kMetricArt.values,
        kBbtArt,
        ...kProductArt.values,
      ].where((p) => !p.endsWith('.svg') && !kRasterArt.contains(p));
      expect(
        undeclared,
        isEmpty,
        reason: 'add it to kRasterArt, and accept that it will not tint',
      );
    });

    // And the reverse: listing an SVG as raster would exempt a file the tint
    // DOES apply to, quietly disabling the monochrome guarantee for it.
    test('no SVG is declared a raster mark', () {
      expect(kRasterArt.where((p) => p.endsWith('.svg')), isEmpty);
    });

    // `none` is the "Period ended today" switch, not a chip. An empty drop
    // beside it would read as a sixth intensity.
    test('flow fill covers every selectable intensity and not none', () {
      for (final f in FlowIntensity.values) {
        expect(
          kFlowFill.containsKey(f),
          f != FlowIntensity.none,
          reason: 'flow fill mismatch for $f',
        );
      }
    });

    // The ramp is the ordinal: a pair out of order, or a level at/above the one
    // after it, would make a heavier flow read as lighter.
    test('flow fill rises strictly with intensity and ends full', () {
      final fills = kFlowFill.values.toList();
      for (var i = 1; i < fills.length; i++) {
        expect(fills[i], greaterThan(fills[i - 1]),
            reason: 'level $i does not exceed level ${i - 1}');
      }
      expect(fills.first, greaterThan(0));
      expect(fills.last, 1.0, reason: 'flooding must fill the droplet');
    });
  });

  group('artFor', () {
    test('resolves a mapped key', () {
      expect(artFor('cramps'), 'assets/track/cramps.png');
    });

    // Medications are user-created and unbounded, so they can never be in
    // kOptionArt. Without the prefix branch they fall through to null and the
    // Medications section renders as blank chips beside a decorated one.
    test('every user-created medication key resolves to the generic icon', () {
      expect(artFor('${kMedicationKeyPrefix}17'), kMedicationArt);
      expect(
        artFor('${kMedicationKeyPrefix}whatever-the-user-typed'),
        kMedicationArt,
      );
    });

    test('an unknown or not-yet-drawn key is null, not a crash', () {
      expect(artFor('shx_emergency'), isNull); // still excluded
      expect(artFor('no_such_key_at_all'), isNull);
    });
  });
}
