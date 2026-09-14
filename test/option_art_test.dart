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
  // Owner decision 2026-09-14: the illustration itself is the mark. This now
  // covers every symptom option except `headache`, which is still the old
  // single-colour glyph, and `soaking_hourly`, which has no art at all.
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

    // Now that the art is complete, the partition is exhaustive: 77 drawn + 12
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
    test('sexual-activity, sexual-health and intimate options have NO art',
        () {
      for (final o in [
        ...kSexOptions,
        ...kSexualHealthOptions,
        // The intimate group joins the same rule it was added under, rather
        // than relying on nobody drawing for it later.
        ...kIntimacyOptions,
        ...kLibidoOptions,
      ]) {
        expect(
          kOptionArt.containsKey(o.key),
          isFalse,
          reason: '${o.key} must stay text-only',
        );
        expect(artFor(o.key), isNull);
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
      expect(artFor('sex_protected'), isNull); // excluded
      expect(artFor('no_such_key_at_all'), isNull);
    });
  });
}
