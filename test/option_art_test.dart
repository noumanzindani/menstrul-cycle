import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/option_art.dart';
import 'package:menstrul_track/models/enums.dart';

/// Every catalog key must be classified, every declared asset must exist, and
/// the exclusions must stay exclusions. These are pure — no DB, no pump — so
/// they run in milliseconds and are the cheapest guard in the suite.
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

    // Now that the art is complete, the partition is exhaustive: 75 drawn + 8
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
    test('sexual-activity and sexual-health options have NO art', () {
      for (final o in [...kSexOptions, ...kSexualHealthOptions]) {
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
    test('every asset is monochrome so it can be tinted', () {
      final offenders = <String>[];
      for (final p in [
        ...kOptionArt.values,
        kMedicationArt,
      ]) {
        final colours = RegExp(r'(?:fill|stroke)="(#[0-9a-fA-F]{3,8})"')
            .allMatches(File(p).readAsStringSync())
            .map((m) => m.group(1)!.toLowerCase())
            .toSet();
        if (colours.length > 1) offenders.add('$p -> $colours');
      }
      expect(offenders, isEmpty);
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
      expect(artFor('cramps'), 'assets/track/cramps.svg');
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
