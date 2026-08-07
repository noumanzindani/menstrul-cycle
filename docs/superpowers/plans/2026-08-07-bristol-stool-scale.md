# Bristol Stool Scale Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Bristol Stool Scale — a 7-point ordinal bowel-form scale drawn as a `CustomPainter` — to the LunaTrack day editor, with a doctor-PDF section, no image assets and no schema migration.

**Architecture:** The type rides the existing day-tags JSON blob as an unprefixed numeric metric `bristol` (1–7, `0` = unset), exactly like `pain` and `weight`. It is decoded into the day editor's existing `_metrics` map, so `save()` needs no change at all. A new `kCatBristol` tracking category (`defaultOn: false`) gates rendering. A pure `BristolSummary` aggregator feeds one new PDF section reporting distribution and mode — never a mean.

**Tech Stack:** Flutter, `provider`, `drift` (unchanged — `schemaVersion` stays 5), `pdf`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-07-bristol-stool-scale-design.md` (commit `d47ef4c`)

## Global Constraints

- **Migration-free.** `schemaVersion` stays **5**. No new column, no `drift_schemas` snapshot, no `SchemaVerifier` test. If you find yourself editing `lib/db/database.dart`, stop — the design is wrong.
- **No image assets.** The app ships zero runtime images and has no `assets:` block in `pubspec.yaml`. Do not add one. All seven shapes are drawn with `Canvas`.
- **No new dependencies.** Ask before adding any.
- **No diagnostic banding, anywhere.** The clinical bands (1–2 constipation, 3–5 normal, 6–7 diarrhoea) must not appear in the UI, in semantics labels, or in the PDF. The Lewis & Heaton *descriptors* ("separate hard lumps") are descriptive and DO appear. Same rule as the banned BMI classification and the banned fertility percentage.
- **Never a mean of an ordinal scale.** Averaging types 1 and 7 yields "type 4 — smooth and soft", inventing a normal reading out of two abnormal ones, in a document handed to a clinician.
- **`encodeDayTags` is a full REPLACE.** Every group must be decoded in `initState` and re-encoded on save regardless of category gating. Gating is render-only.
- **Never `Random()` in a painter** — not even seeded inside `paint()`.
- **Conventional Commits** (`feat:` / `fix:` / `test:` / `docs:` / `chore:`). Branch is `feat/firebase-auth-sync`; do not create a new branch, do not push.
- **Baseline: 531 tests green.** Run `flutter test` before starting. If it is not 531/0, stop and report.

---

### Task 1: Catalog foundation

**Files:**
- Modify: `lib/common/catalog.dart`
- Test: `test/bristol_test.dart` (create)

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `const String kMetricBristol`; `const Set<String> kNumericMetricKeys`; `int clampBristol(num? raw)`; `class BristolType { final int value; final String descriptor; }`; `const List<BristolType> kBristolTypes` (7 entries, values 1–7 ascending); `const Set<String> kLegacyDigestionKeys`

- [ ] **Step 1: Write the failing tests**

Create `test/bristol_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

void main() {
  group('bristol encoding', () {
    test('round-trips as an unprefixed JSON number', () {
      final json = encodeDayTags(numbers: {kMetricBristol: 4});
      expect(json, contains('"bristol":4'));
      expect(decodeNumber(json, kMetricBristol), 4);
    });

    test('a numeric bristol never reads as a symptom', () {
      final json = encodeDayTags(numbers: {kMetricBristol: 4});
      expect(decodeSymptoms(json), isEmpty);
    });

    // THE hardening test. A hand-rolled REST write can put a boolean here:
    // firestore.rules does no field validation and SyncMapper accepts whatever
    // map comes back. Without the explicit allow-list this reaches the doctor
    // PDF as the raw key "bristol".
    test('a BOOLEAN bristol still never reads as a symptom', () {
      expect(decodeSymptoms(jsonEncode({'bristol': true})), isEmpty);
      expect(decodeSymptoms(jsonEncode(['bristol'])), isEmpty);
    });

    test('kNumericMetricKeys collides with no symptom key', () {
      final symptomKeys = {
        for (final o in [...kSymptomOptions, ...kEmotionalOptions]) o.key,
      };
      expect(kNumericMetricKeys.intersection(symptomKeys), isEmpty);
    });

    test('the digestion group does not capture bristol', () {
      final json =
          encodeDayTags(flags: {'dig_gas'}, numbers: {kMetricBristol: 4});
      expect(decodeGroup(json, kDigestionKeyPrefix), {'dig_gas'});
    });
  });

  group('clampBristol', () {
    test('null and 0 are unset', () {
      expect(clampBristol(null), 0);
      expect(clampBristol(0), 0);
    });

    test('out-of-range and fractional values are unset', () {
      expect(clampBristol(9), 0);
      expect(clampBristol(8), 0);
      expect(clampBristol(-1), 0);
      expect(clampBristol(3.5), 0);
    });

    test('1 through 7 pass through', () {
      for (var i = 1; i <= 7; i++) {
        expect(clampBristol(i), i);
      }
    });
  });

  group('kBristolTypes', () {
    test('is exactly seven entries, values 1..7 ascending', () {
      expect(kBristolTypes.length, 7);
      expect([for (final t in kBristolTypes) t.value], [1, 2, 3, 4, 5, 6, 7]);
    });

    test('descriptors collide with no existing option label', () {
      final labels = {
        for (final o in [
          ...kSymptomOptions,
          ...kEmotionalOptions,
          ...kSexOptions,
          ...kDischargeOptions,
          ...kVaginalOptions,
          ...kSexualHealthOptions,
          ...kHabitOptions,
          ...kUrineOptions,
          ...kDigestionOptions,
          ...kSkinOptions,
        ])
          o.label,
      };
      for (final t in kBristolTypes) {
        expect(labels.contains(t.descriptor), isFalse, reason: t.descriptor);
      }
    });

    test('carries no diagnostic banding word', () {
      final banned = RegExp(r'constipat|diarrh|normal|abnormal|IBS',
          caseSensitive: false);
      for (final t in kBristolTypes) {
        expect(banned.hasMatch(t.descriptor), isFalse, reason: t.descriptor);
      }
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/bristol_test.dart`
Expected: FAIL — `Undefined name 'kMetricBristol'` and friends (compile error).

- [ ] **Step 3: Add the constants and helper to `lib/common/catalog.dart`**

Add beside the other `kMetric*` constants (immediately after `kMetricWeight` at ~`:87`):

```dart
/// Bristol Stool Scale type for the day: an ORDINAL 1–7 (Lewis & Heaton, 1997).
/// `0` means unset, the same convention every other numeric metric uses — the
/// scale has no type 0, so nothing had to be invented. Deliberately UNPREFIXED:
/// it is a number rather than a flag, and unlike the rest of the `dig_` group it
/// DOES belong in the doctor PDF.
const String kMetricBristol = 'bristol'; // 1–7, 0 = unset
```

Then, immediately after the `kMetric*` block:

```dart
/// Every numeric day-metric key. [decodeSymptoms] filters these EXPLICITLY
/// rather than relying on them not being `== true`, because the stored value's
/// type is not ours to guarantee: `firestore.rules` does no field validation and
/// `SyncMapper.dailyLogFromMap` accepts whatever map comes back, so a
/// hand-rolled REST write of `{"bristol": true}` would otherwise reach the
/// symptom-frequency table and print in the doctor PDF as the raw key.
///
/// Must stay disjoint from every symptom key — [encodeDayTags] writes flags
/// first and numbers second into one map literal, so a key in both silently
/// loses its boolean with no error. `test/bristol_test.dart` guards that.
const Set<String> kNumericMetricKeys = {
  kMetricPain,
  kMetricWater,
  kMetricSleep,
  kMetricEnergy,
  kMetricStress,
  kMetricSleepQuality,
  kMetricWeight,
  kMetricBristol,
};

/// One point on the Bristol Stool Scale.
///
/// Descriptors only. The clinical BANDS (1–2 constipation, 3–5 normal, 6–7
/// diarrhoea) are deliberately absent everywhere — in the app AND in the doctor
/// PDF. An instrument's reading is the user's data; an interpretation of it is a
/// claim this app is not qualified to make. Same rule as the banned BMI
/// classification and the banned fertility percentage.
class BristolType {
  const BristolType(this.value, this.descriptor);

  /// 1..7.
  final int value;
  final String descriptor;
}

const List<BristolType> kBristolTypes = [
  BristolType(1, 'Separate hard lumps'),
  BristolType(2, 'Lumpy and sausage-shaped'),
  BristolType(3, 'Sausage-shaped with cracks'),
  BristolType(4, 'Smooth and soft, sausage-shaped'),
  BristolType(5, 'Soft blobs with clear edges'),
  BristolType(6, 'Fluffy pieces with ragged edges'),
  BristolType(7, 'Watery, no solid pieces'),
];

/// The stored Bristol type as an int in 1..7, or 0 when unset, absent, or out of
/// range. A restored backup or a sync from a tampered or newer client can carry
/// `9` or `3.5`; unclamped, those would highlight no row, survive the save, and
/// print in the doctor PDF.
int clampBristol(num? raw) {
  if (raw == null) return 0;
  final v = raw.toInt();
  if (v != raw) return 0; // 3.5 is not a type
  return (v >= 1 && v <= 7) ? v : 0;
}
```

Add beside `kDigestionKeyPrefix`'s option list (after `kDigestionOptions` at ~`:215`):

```dart
/// Superseded by the Bristol scale, and rendered ONLY on days where they are
/// already set. They are still decoded and re-encoded like every other key:
/// removing them outright would strand existing values, because [decodeGroup]
/// loads any `dig_` key into the editor's state and `save()` writes it back —
/// leaving them invisible in the picker and impossible to untick.
const Set<String> kLegacyDigestionKeys = {'dig_hard_stool', 'dig_loose_stool'};
```

- [ ] **Step 4: Harden `decodeSymptoms`**

In `lib/common/catalog.dart`, replace both `.where((k) => !_isReserved(k))` filters (the Map branch at ~`:257` and the List branch at ~`:263`) with:

```dart
          .where((k) => !_isReserved(k) && !kNumericMetricKeys.contains(k))
```

- [ ] **Step 5: Rewrite the two comments this falsifies**

`catalog.dart:80-82` currently says numeric metrics "never satisfy the `== true` symptom check, so they are naturally excluded from [decodeSymptoms]". Replace with:

```dart
/// Numeric day-metric keys (stored as real JSON numbers, not booleans, in the
/// same day-tags blob). [decodeSymptoms] excludes them via the explicit
/// [kNumericMetricKeys] allow-list — NOT merely because a number fails the
/// `== true` check, which is a property of the stored value rather than of the
/// key, and therefore not a boundary a hostile or corrupt write must respect.
```

`catalog.dart:206-208` currently says the digestion group "deliberately excludes diarrhea/constipation/bloating/nausea — those are already plain symptoms in [kSymptomOptions] and must not be restated under a second key". Replace with:

```dart
/// Digestion / bowel (boolean multi-select, [kDigestionKeyPrefix]). Deliberately
/// excludes diarrhea/constipation/bloating/nausea — those are already plain
/// symptoms in [kSymptomOptions] and must not be restated under a second key.
///
/// `dig_hard_stool` and `dig_loose_stool` ARE now restated, by the Bristol scale
/// ([kMetricBristol]) which describes the same fact more precisely. That overlap
/// is deliberate and bounded: they are listed in [kLegacyDigestionKeys] and
/// render only where already set, so no NEW duplicate can be created, and the
/// doctor PDF sources bowel form from Bristol alone so nothing double-counts.
/// `dig_no_bm` is NOT superseded — Bristol describes only stool that exists.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/bristol_test.dart`
Expected: PASS (11 tests)

- [ ] **Step 7: Run the full suite for regressions**

Run: `flutter test`
Expected: 542 passed, 0 failed. (531 baseline + 11.) The `decodeSymptoms` change is the risky part — if any existing test fails, a metric key was reaching the symptom list and something depended on it. Report rather than paper over.

- [ ] **Step 8: Verify the discrimination proofs**

For each, make the edit, run `flutter test test/bristol_test.dart`, confirm the named test goes RED, then restore:

| Revert | Must fail |
|---|---|
| `kMetricBristol = 'dig_bristol'` | `round-trips as an unprefixed JSON number` |
| drop `&& !kNumericMetricKeys.contains(k)` from both branches | `a BOOLEAN bristol still never reads as a symptom` |
| add `'headache'` to `kNumericMetricKeys` | `kNumericMetricKeys collides with no symptom key` |
| `clampBristol` returns `raw.toInt()` unguarded | `out-of-range and fractional values are unset` |
| change a descriptor to `'Normal, sausage-shaped'` | `carries no diagnostic banding word` |

Note honestly: `a numeric bristol never reads as a symptom` has **no unique revert** — it is guarded by both the `== true` check and the allow-list. It is defence-in-depth, kept deliberately, not a discriminating test.

- [ ] **Step 9: Commit**

```bash
git add lib/common/catalog.dart test/bristol_test.dart
git commit -m "feat(bristol): add the Bristol metric key, types and clamp

Encodes the Bristol Stool Scale as an unprefixed numeric day-metric
(1-7, 0 = unset), the kMetricPain pattern, so no schema change is needed.

Also converts decodeSymptoms' exclusion of numeric metrics from an
accidental property (a number is not == true) into an explicit
kNumericMetricKeys allow-list. The value's type is not ours to guarantee:
firestore.rules does no field validation, so {\"bristol\": true} written
via raw REST would otherwise print in the doctor PDF as a raw key."
```

---

### Task 2: `BristolSummary` aggregator

**Files:**
- Create: `lib/services/bristol_summary.dart`
- Test: `test/bristol_summary_test.dart` (create)

**Interfaces:**
- Consumes: `kMetricBristol`, `clampBristol`, `decodeNumber` (Task 1)
- Produces: `class BristolSummary` with fields `Map<int, int> countsByType`, `int totalReadings`, `List<int> mostCommonTypes`, `DateTime firstDate`, `DateTime lastDate`; and `static BristolSummary? compute(List<DailyLog> logs)`

- [ ] **Step 1: Write the failing tests**

Create `test/bristol_summary_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/bristol_summary.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> log(int day, {num? bristol}) => repo.upsert(
        date: DateTime(2026, 5, day),
        flow: null,
        symptomsJson: encodeDayTags(
          numbers: {if (bristol != null) kMetricBristol: bristol},
        ),
      );

  Future<List<DailyLog>> all() => repo.getAll();

  test('returns null when no day carries a reading', () async {
    await log(1);
    await log(2);
    expect(BristolSummary.compute(await all()), isNull);
  });

  test('counts each logged type and spans the dates', () async {
    await log(3, bristol: 4);
    await log(5, bristol: 4);
    await log(9, bristol: 2);

    final s = BristolSummary.compute(await all())!;
    expect(s.countsByType, {4: 2, 2: 1});
    expect(s.totalReadings, 3);
    expect(s.firstDate, DateTime(2026, 5, 3));
    expect(s.lastDate, DateTime(2026, 5, 9));
  });

  // Bristol is ORDINAL. A user who logged 1 and 7 had constipation and
  // diarrhoea; reporting "4 — smooth and soft" to a clinician would invent a
  // normal reading out of two abnormal ones.
  test('reports the mode, never a mean', () async {
    await log(1, bristol: 1);
    await log(2, bristol: 7);

    final s = BristolSummary.compute(await all())!;
    expect(s.mostCommonTypes, [1, 7]);
    expect(s.countsByType.containsKey(4), isFalse);
  });

  test('a clear single mode reports one type', () async {
    await log(1, bristol: 3);
    await log(2, bristol: 3);
    await log(3, bristol: 6);

    expect(BristolSummary.compute(await all())!.mostCommonTypes, [3]);
  });

  test('out-of-range stored values are ignored', () async {
    await log(1, bristol: 9);
    await log(2, bristol: 3.5);
    await log(3, bristol: 4);

    final s = BristolSummary.compute(await all())!;
    expect(s.countsByType, {4: 1});
    expect(s.totalReadings, 1);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/bristol_summary_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../bristol_summary.dart'`

The read-all method is `DailyLogRepository.getAll()` (`lib/data/daily_log_repository.dart:13`). Do not add a new repository method.

- [ ] **Step 3: Write the implementation**

Create `lib/services/bristol_summary.dart`:

```dart
import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';

/// A descriptive summary of logged Bristol Stool Scale readings.
///
/// Reports the DISTRIBUTION and the most common type(s), and deliberately no
/// mean: the scale is ORDINAL, so averaging types 1 and 7 would produce
/// "type 4 — smooth and soft", inventing a normal reading out of two abnormal
/// ones. In a document handed to a clinician that is a statistical error, not a
/// rounding choice.
///
/// No banding and no interpretation — see [BristolType].
class BristolSummary {
  const BristolSummary({
    required this.countsByType,
    required this.totalReadings,
    required this.mostCommonTypes,
    required this.firstDate,
    required this.lastDate,
  });

  /// Type (1–7) → days logged with it. Only types actually logged are keys.
  final Map<int, int> countsByType;

  final int totalReadings;

  /// Every type tied for the highest count, ascending. Ties report ALL of them
  /// rather than picking one: a tie between 1 and 6 is clinically meaningful and
  /// collapsing it to a single "most common" would hide exactly that.
  final List<int> mostCommonTypes;

  final DateTime firstDate;
  final DateTime lastDate;

  /// Null when no day carries a reading, so the caller renders nothing at all
  /// rather than an empty heading.
  static BristolSummary? compute(List<DailyLog> logs) {
    final counts = <int, int>{};
    DateTime? first;
    DateTime? last;

    for (final l in logs) {
      final type = clampBristol(decodeNumber(l.symptoms, kMetricBristol));
      if (type == 0) continue;
      counts[type] = (counts[type] ?? 0) + 1;
      final d = dateOnly(l.date);
      if (first == null || d.isBefore(first)) first = d;
      if (last == null || d.isAfter(last)) last = d;
    }

    if (counts.isEmpty) return null;

    final highest = counts.values.reduce((a, b) => a > b ? a : b);
    final modes = [
      for (final e in counts.entries)
        if (e.value == highest) e.key,
    ]..sort();

    return BristolSummary(
      countsByType: Map.unmodifiable(counts),
      totalReadings: counts.values.reduce((a, b) => a + b),
      mostCommonTypes: List.unmodifiable(modes),
      firstDate: first!,
      lastDate: last!,
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/bristol_summary_test.dart`
Expected: PASS (5 tests)

- [ ] **Step 5: Verify the discrimination proof for the mode test**

Replace the `modes` computation with a mean:

```dart
    final mean = (counts.entries
                .map((e) => e.key * e.value)
                .reduce((a, b) => a + b) /
            counts.values.reduce((a, b) => a + b))
        .round();
    final modes = [mean];
```

Run: `flutter test test/bristol_summary_test.dart`
Expected: `reports the mode, never a mean` FAILS — mean of {1, 7} is 4. Restore the real implementation.

- [ ] **Step 6: Commit**

```bash
git add lib/services/bristol_summary.dart test/bristol_summary_test.dart
git commit -m "feat(bristol): add the BristolSummary aggregator

Distribution plus mode, and deliberately no mean: the scale is ordinal,
so averaging types 1 and 7 yields 'type 4 - smooth and soft', inventing a
normal reading out of two abnormal ones. Ties report every tied type."
```

---

### Task 3: The `kCatBristol` tracking category

**Files:**
- Modify: `lib/common/tracking_categories.dart`
- Modify: `lib/screens/settings/tracking_categories_screen.dart:8-12` (copy only)
- Test: `test/bristol_category_test.dart` (create)

**Interfaces:**
- Consumes: nothing
- Produces: `const String kCatBristol = 'bristol_scale';`

Note the id is `'bristol_scale'`, **not** `'bristol'` — the metric key is already `'bristol'` and the two namespaces are stored separately but read side by side; distinct strings keep grep and debugging unambiguous.

- [ ] **Step 1: Write the failing test**

Create `test/bristol_category_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/tracking_categories.dart';

void main() {
  test('kCatBristol is registered', () {
    // NB: kAllCategoryIds lives in day_entry_form.dart, not here — assert
    // against the registry itself.
    expect(
      kTrackingCategories.any((c) => c.id == kCatBristol),
      isTrue,
    );
  });

  // tracking_categories.dart:16 — "New categories ship OFF so no existing
  // user's day editor grows unasked." A user who enabled Digestion for gas and
  // heartburn chips must not get seven silhouettes on the next update.
  test('kCatBristol ships OFF', () {
    expect(defaultEnabledCategoryIds().contains(kCatBristol), isFalse);
  });

  test('its id does not collide with the metric key', () {
    expect(kCatBristol, isNot('bristol'));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/bristol_category_test.dart`
Expected: FAIL — `Undefined name 'kCatBristol'`

- [ ] **Step 3: Register the category**

In `lib/common/tracking_categories.dart`, add after `const String kCatWeight = 'weight';`:

```dart
const String kCatBristol = 'bristol_scale';
```

And add to `kTrackingCategories`, immediately after the `kCatDigestion` entry so Settings lists it beside Digestion:

```dart
  TrackingCategory(kCatBristol, 'Stool form (Bristol scale)', defaultOn: false),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/bristol_category_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Fix the Settings copy**

Open `lib/screens/settings/tracking_categories_screen.dart`. The explanatory note at `:8-12` promises hidden data is never deleted, but does not say it is still exported. Amend that string so it also reads (keep the existing sentence, append):

> Anything you've already logged is kept, not deleted — and it still appears in your doctor summary.

The same string lives in `lib/l10n/app_en.arb` as `settingsTrackingNote`. Update **both**, then regenerate:

Run: `flutter gen-l10n`

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: 550 passed, 0 failed.

If a test asserts on the old `settingsTrackingNote` text, update that assertion — it is a copy change, not a behaviour change.

- [ ] **Step 7: Commit**

```bash
git add lib/common/tracking_categories.dart lib/screens/settings/tracking_categories_screen.dart lib/l10n/ test/bristol_category_test.dart
git commit -m "feat(bristol): register kCatBristol, defaultOn false

Its own category rather than riding kCatDigestion, per the contract at
tracking_categories.dart:16 - a user who enabled Digestion for gas and
heartburn chips must not get seven silhouettes unasked.

Also amends the Customize tracking note, which promised hidden data is
never deleted without mentioning it is still exported to the PDF."
```

---

### Task 4: The picker widget and painter

**Files:**
- Create: `lib/widgets/bristol_scale_picker.dart`
- Test: `test/bristol_picker_test.dart` (create)

**Interfaces:**
- Consumes: `kBristolTypes`, `BristolType`, `clampBristol` (Task 1)
- Produces: `class BristolScalePicker extends StatefulWidget` with `final int value` and `final ValueChanged<int> onChanged`; `class BristolShapePainter extends CustomPainter` with public `final int type`, `final Color fill`, `final Color stroke`
- Widget keys later tasks rely on: `Key('bristol-disclosure')`, `Key('bristol-clear')`, `Key('bristol-1')` … `Key('bristol-7')`

- [ ] **Step 1: Write the failing tests**

Create `test/bristol_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/widgets/bristol_scale_picker.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    int value = 0,
    required ValueChanged<int> onChanged,
    double textScale = 1.0,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SingleChildScrollView(
                child: BristolScalePicker(value: value, onChanged: onChanged),
              ),
            ),
          ),
        ),
      );

  testWidgets('is collapsed until the disclosure is tapped', (tester) async {
    await pump(tester, onChanged: (_) {});

    expect(find.byKey(const Key('bristol-4')), findsNothing);
    expect(find.text('Not logged'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bristol-disclosure')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bristol-4')), findsOneWidget);
  });

  testWidgets('exposes seven distinct tap targets when expanded',
      (tester) async {
    await pump(tester, onChanged: (_) {});
    await tester.tap(find.byKey(const Key('bristol-disclosure')));
    await tester.pumpAndSettle();

    for (var i = 1; i <= 7; i++) {
      expect(find.byKey(Key('bristol-$i')), findsOneWidget, reason: 'type $i');
    }
  });

  testWidgets('tapping a type reports it', (tester) async {
    int? reported;
    await pump(tester, onChanged: (v) => reported = v);
    await tester.tap(find.byKey(const Key('bristol-disclosure')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bristol-4')));
    expect(reported, 4);
  });

  testWidgets('re-tapping the selected type clears it', (tester) async {
    int? reported;
    await pump(tester, value: 4, onChanged: (v) => reported = v);
    await tester.tap(find.byKey(const Key('bristol-disclosure')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bristol-4')));
    expect(reported, 0);
  });

  testWidgets('offers an explicit Clear only when a value is set',
      (tester) async {
    int? reported;
    await pump(tester, onChanged: (v) => reported = v);
    expect(find.byKey(const Key('bristol-clear')), findsNothing);

    await pump(tester, value: 6, onChanged: (v) => reported = v);
    expect(find.byKey(const Key('bristol-clear')), findsOneWidget);

    await tester.tap(find.byKey(const Key('bristol-clear')));
    expect(reported, 0);
  });

  testWidgets('the collapsed row shows the selected descriptor',
      (tester) async {
    await pump(tester, value: 4, onChanged: (_) {});
    expect(find.textContaining('Type 4'), findsOneWidget);
    expect(find.textContaining('Smooth and soft'), findsOneWidget);
  });

  testWidgets('does not overflow at textScaleFactor 2.0', (tester) async {
    await pump(tester, value: 3, onChanged: (_) {}, textScale: 2.0);
    await tester.tap(find.byKey(const Key('bristol-disclosure')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('BristolShapePainter.shouldRepaint', () {
    const fill = Color(0xFFEEEEEE);
    const stroke = Color(0xFF333333);

    test('false for identical input', () {
      const a = BristolShapePainter(type: 3, fill: fill, stroke: stroke);
      const b = BristolShapePainter(type: 3, fill: fill, stroke: stroke);
      expect(a.shouldRepaint(b), isFalse);
    });

    test('true when the type changes', () {
      const a = BristolShapePainter(type: 3, fill: fill, stroke: stroke);
      const b = BristolShapePainter(type: 4, fill: fill, stroke: stroke);
      expect(a.shouldRepaint(b), isTrue);
    });

    // Returning false here is a dark-mode bug: the rebuilt painter carries new
    // colours and the render object would never repaint.
    test('true when only the colours change', () {
      const a = BristolShapePainter(type: 3, fill: fill, stroke: stroke);
      const b = BristolShapePainter(
          type: 3, fill: Color(0xFF222222), stroke: Color(0xFFDDDDDD));
      expect(a.shouldRepaint(b), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/bristol_picker_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../bristol_scale_picker.dart'`

- [ ] **Step 3: Write the widget**

Create `lib/widgets/bristol_scale_picker.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../common/catalog.dart';

/// The Bristol Stool Scale as seven tappable, drawn rows.
///
/// Collapsed by default. With every category enabled the day editor is already
/// 19 sections; seven full-width illustrated rows is roughly another viewport,
/// and keeping them behind a disclosure also means nothing recognisable is on
/// screen until the user chooses to open it.
///
/// The drawings are decorative — every row carries a visible "Type N" plus its
/// descriptor, and the semantics label repeats both, so meaning never depends on
/// reading a shape.
class BristolScalePicker extends StatefulWidget {
  const BristolScalePicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 1–7, or 0 when unset.
  final int value;

  /// Reports the new value; 0 means the user cleared it.
  final ValueChanged<int> onChanged;

  @override
  State<BristolScalePicker> createState() => _BristolScalePickerState();
}

class _BristolScalePickerState extends State<BristolScalePicker> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selected = clampBristol(widget.value);
    final summary = selected == 0
        ? 'Not logged'
        : 'Type $selected — ${kBristolTypes[selected - 1].descriptor}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          key: const Key('bristol-disclosure'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(summary, style: text.bodyMedium)),
                if (selected > 0)
                  TextButton(
                    key: const Key('bristol-clear'),
                    onPressed: () => widget.onChanged(0),
                    child: const Text('Clear'),
                  ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          for (final t in kBristolTypes)
            _BristolRow(
              type: t,
              selected: selected == t.value,
              onTap: () =>
                  widget.onChanged(selected == t.value ? 0 : t.value),
            ),
          const SizedBox(height: 4),
          Text(
            'hard ←→ loose',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _BristolRow extends StatelessWidget {
  const _BristolRow({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final BristolType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Scale the diagram with the user's text size so it is not lost at large
    // scales, capped so it cannot swallow the row. No fixed row HEIGHT — that is
    // what overflows at textScaler 2.0.
    final box = MediaQuery.textScalerOf(context).scale(40).clamp(40.0, 72.0);

    return MergeSemantics(
      child: Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: selected,
        label: 'Type ${type.value} — ${type.descriptor}',
        hint: selected ? 'Selected. Activate to clear' : null,
        child: InkWell(
          key: Key('bristol-${type.value}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    // Explicit size: a CustomPaint with a null child and no size
                    // defaults to Size.zero and paints nothing.
                    width: box * 1.4,
                    height: box,
                    child: CustomPaint(
                      painter: BristolShapePainter(
                        type: type.value,
                        fill: selected
                            ? scheme.onSecondaryContainer.withValues(alpha: 0.18)
                            : scheme.surfaceContainerHighest,
                        stroke: selected
                            ? scheme.onSecondaryContainer
                            : scheme.outline,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type ${type.value}', style: text.labelLarge),
                      Text(
                        type.descriptor,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check, color: scheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the painter**

Append to the same file:

```dart
/// Draws one Bristol silhouette in unit space (0..1), scaled to the canvas.
///
/// Every shape is a `static const` control-point set built once into a cached
/// [Path]. NEVER `Random()` — not even seeded inside [paint]: that allocates per
/// frame and silently reshapes types 2 and 6 on any reorder of draw calls, so
/// nothing repeatable could ever be asserted about them.
class BristolShapePainter extends CustomPainter {
  const BristolShapePainter({
    required this.type,
    required this.fill,
    required this.stroke,
  });

  final int type;
  final Color fill;
  final Color stroke;

  static final Map<int, List<Path>> _cache = {};

  static List<Path> _pathsFor(int type) =>
      _cache.putIfAbsent(type, () => _build(type));

  static List<Path> _build(int type) {
    switch (type) {
      case 1: // separate hard lumps
        return [
          for (final cx in const [0.25, 0.5, 0.75])
            Path()
              ..addOval(
                  Rect.fromCircle(center: Offset(cx, 0.5), radius: 0.075)),
        ];
      case 2: // lumpy sausage
        final p = Path()
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTRB(0.10, 0.34, 0.90, 0.66),
            const Radius.circular(0.16),
          ));
        for (final cx in const [0.26, 0.44, 0.62, 0.78]) {
          p.addOval(Rect.fromCircle(center: Offset(cx, 0.5), radius: 0.115));
        }
        return [p];
      case 3: // sausage with cracks
        return [
          Path()
            ..addRRect(RRect.fromRectAndRadius(
              const Rect.fromLTRB(0.08, 0.36, 0.92, 0.64),
              const Radius.circular(0.14),
            )),
          for (final x in const [0.34, 0.52, 0.70])
            Path()
              ..moveTo(x, 0.38)
              ..lineTo(x - 0.03, 0.62),
        ];
      case 4: // smooth sausage
        return [
          Path()
            ..addRRect(RRect.fromRectAndRadius(
              const Rect.fromLTRB(0.06, 0.37, 0.94, 0.63),
              const Radius.circular(0.13),
            )),
        ];
      case 5: // soft blobs, clear edges
        return [
          for (final cx in const [0.24, 0.5, 0.76])
            Path()
              ..addRRect(RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(cx, 0.5), width: 0.22, height: 0.26),
                const Radius.circular(0.10),
              )),
        ];
      case 6: // fluffy, ragged edges
        const radii = [
          0.30, 0.22, 0.28, 0.19, 0.31, 0.21,
          0.27, 0.18, 0.29, 0.23, 0.26, 0.20,
        ];
        final p = Path();
        for (var i = 0; i < radii.length; i++) {
          final a = (i / radii.length) * 2 * math.pi;
          final pt = Offset(
            0.5 + math.cos(a) * radii[i] * 1.6,
            0.5 + math.sin(a) * radii[i],
          );
          if (i == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        return [p..close()];
      default: // 7 — watery, no solid pieces
        final p = Path()..moveTo(0.05, 0.44);
        for (var i = 0; i <= 8; i++) {
          final x = 0.05 + (0.90 * i / 8);
          p.lineTo(x, 0.44 + (i.isEven ? -0.05 : 0.05));
        }
        for (var i = 8; i >= 0; i--) {
          final x = 0.05 + (0.90 * i / 8);
          p.lineTo(x, 0.60 + (i.isEven ? -0.05 : 0.05));
        }
        return [p..close()];
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width, size.height);

    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    // Stroke width is in unit space, so divide by the scale or it thickens with
    // the canvas.
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / size.width;

    for (final path in _pathsFor(type)) {
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(BristolShapePainter old) =>
      old.type != type || old.fill != fill || old.stroke != stroke;
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/bristol_picker_test.dart`
Expected: PASS (10 tests)

- [ ] **Step 6: Verify the discrimination proofs**

| Revert | Must fail |
|---|---|
| `for (var i = 1; i <= 6; i++)` — i.e. drop `kBristolTypes.last` | `exposes seven distinct tap targets when expanded` |
| `onTap: () => widget.onChanged(t.value)` (no clear branch) | `re-tapping the selected type clears it` |
| `shouldRepaint => old.type != type` only | `true when only the colours change` |
| wrap the row in `SizedBox(height: 48, ...)` | `does not overflow at textScaleFactor 2.0` |
| remove the `SizedBox` around `CustomPaint` | none — see the note below |

**Honest note:** no test catches the missing `SizedBox`. A zero-size `CustomPaint` still builds, still hit-tests through its parent `InkWell`, and throws nothing — it simply draws nothing. That is one of the things only a device check finds.

- [ ] **Step 7: Run analyze and the full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; 560 passed, 0 failed.

- [ ] **Step 8: Commit**

```bash
git add lib/widgets/bristol_scale_picker.dart test/bristol_picker_test.dart
git commit -m "feat(bristol): add the collapsed seven-row scale picker

Silhouettes are static const control points cached into Paths - never
Random(), not even seeded inside paint(), which would reshape types 2
and 6 per frame and make them unassertable.

Colours come from ColorScheme, not the PhaseColors extension: those are
cycle-phase semantics and borrowing luteal amber for stool is a semantic
lie. shouldRepaint compares every colour field, since returning false
there is a dark-mode bug."
```

---

### Task 5: Day-editor integration

**Files:**
- Modify: `lib/widgets/day_entry_form.dart` — imports, `initState` (~`:140`), the group render loop (~`:377-393`), the header doc comment (~`:19-20`), the `_metricConfigs` comment (`:86-88`)
- Test: `test/bristol_form_test.dart` (create)

**Interfaces:**
- Consumes: `kMetricBristol`, `clampBristol`, `kLegacyDigestionKeys` (Task 1); `kCatBristol` (Task 3); `BristolScalePicker` (Task 4)
- Produces: nothing new; Bristol lives in the existing `_metrics` map

- [ ] **Step 1: Write the failing tests**

Create `test/bristol_form_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late LogProvider logs;
  final day = DateTime(2026, 3, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = LogProvider(DailyLogRepository(db));
    await logs.load();
  });

  tearDown(() => db.close());

  Future<GlobalKey<DayEntryFormState>> pump(
    WidgetTester tester, {
    Set<String>? categories,
  }) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(
          home: Scaffold(
            body: DayEntryForm(key: key, date: day, categories: categories),
          ),
        ),
      ),
    );
    return key;
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) => tester
      .dragUntilVisible(target, find.byType(ListView), const Offset(0, -300));

  final disclosure = find.byKey(const Key('bristol-disclosure'));

  Future<void> openPicker(WidgetTester tester) async {
    await scrollTo(tester, disclosure);
    await tester.tap(disclosure);
    await tester.pumpAndSettle();
  }

  testWidgets('renders the picker when the category is on', (tester) async {
    await pump(tester, categories: {kCatBristol});
    await openPicker(tester);

    expect(find.byKey(const Key('bristol-4')), findsOneWidget);
  });

  testWidgets('hides the picker when the category is off', (tester) async {
    await pump(tester, categories: const <String>{});

    // Scroll to Notes FIRST, or an absent picker is confused with "below the
    // fold" and the assertion is vacuous.
    await scrollTo(tester, find.text('Notes'));
    expect(disclosure, findsNothing);
  });

  testWidgets('tapping type 4 saves bristol = 4', (tester) async {
    final key = await pump(tester, categories: {kCatBristol});
    await openPicker(tester);

    await tester.tap(find.byKey(const Key('bristol-4')));
    await tester.pumpAndSettle();
    expect(await key.currentState!.save(), isTrue);

    expect(decodeNumber(logs.logForDate(day)!.symptoms, kMetricBristol), 4);
  });

  testWidgets('clearing omits the key rather than writing 0', (tester) async {
    await DailyLogRepository(db).upsert(
      date: day,
      flow: null,
      symptomsJson: encodeDayTags(numbers: {kMetricBristol: 4}),
    );
    await logs.load();

    final key = await pump(tester, categories: {kCatBristol});
    await scrollTo(tester, find.byKey(const Key('bristol-clear')));
    await tester.tap(find.byKey(const Key('bristol-clear')));
    await tester.pumpAndSettle();
    expect(await key.currentState!.save(), isTrue);

    final saved = logs.logForDate(day)!;
    expect(saved.symptoms, isNot(contains('bristol')));
    expect(decodeNumber(saved.symptoms, kMetricBristol), isNull);
  });

  testWidgets('re-opening shows the stored type selected', (tester) async {
    await DailyLogRepository(db).upsert(
      date: day,
      flow: null,
      symptomsJson: encodeDayTags(numbers: {kMetricBristol: 6}),
    );
    await logs.load();

    await pump(tester, categories: {kCatBristol});
    await scrollTo(tester, disclosure);

    expect(find.textContaining('Fluffy pieces'), findsOneWidget);
  });

  testWidgets(
      'REGRESSION: a logged Bristol survives saving with the category off',
      (tester) async {
    await DailyLogRepository(db).upsert(
      date: day,
      flow: null,
      symptomsJson: encodeDayTags(
        flags: {'dig_gas'},
        numbers: {kMetricBristol: 5},
      ),
    );
    await logs.load();

    final key = await pump(tester, categories: const <String>{});

    // Type a note so the save definitely WRITES. Without this the assertion
    // below passes even if save() early-returns or saveDay no-ops, because the
    // original row is simply left untouched — the test would prove nothing
    // about the decode.
    await scrollTo(tester, find.text('Notes'));
    await tester.enterText(find.byKey(const Key('notes-field')), 'proof');
    expect(await key.currentState!.save(), isTrue);

    final saved = logs.logForDate(day)!;
    expect(saved.notes, 'proof'); // the REPLACE really happened
    expect(decodeNumber(saved.symptoms, kMetricBristol), 5);
    expect(decodeGroup(saved.symptoms, kDigestionKeyPrefix), {'dig_gas'});
  });

  testWidgets('legacy dig_ form keys render only where already set',
      (tester) async {
    // A fresh day must not offer them.
    await pump(tester, categories: {kCatDigestion});
    await scrollTo(tester, find.text('Digestion'));
    expect(find.text('Hard stool'), findsNothing);
    expect(find.text('No bowel movement'), findsOneWidget);

    // A day that already has one must still be able to untick it.
    await DailyLogRepository(db).upsert(
      date: day,
      flow: null,
      symptomsJson: encodeDayTags(flags: {'dig_hard_stool'}),
    );
    await logs.load();

    await pump(tester, categories: {kCatDigestion});
    await scrollTo(tester, find.text('Digestion'));
    expect(find.text('Hard stool'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/bristol_form_test.dart`
Expected: FAIL — the picker is not rendered.

**`Key('notes-field')` does not exist yet** — `day_entry_form.dart:416` has only `Key('weight-field')`. Add it to the notes `TextField`, following that same convention. The regression test in Step 7 depends on it.

- [ ] **Step 3: Decode Bristol in `initState`**

In `lib/widgets/day_entry_form.dart`, immediately after the `kMetricPain` line (~`:140`):

```dart
    _metrics[kMetricPain] = decodeNumber(tags, kMetricPain)?.round() ?? 0;
    // Bristol lives in _metrics, not a bespoke field, so save()'s existing
    // `numbers` loop emits it with no change. Decoded unconditionally, like
    // every other group: the blob is fully REPLACED on save.
    _metrics[kMetricBristol] = clampBristol(decodeNumber(tags, kMetricBristol));
```

Add the import:

```dart
import 'bristol_scale_picker.dart';
```

- [ ] **Step 4: Unroll the group loop and render the picker**

Replace the whole block at `:377-393` (the comment `// Structurally identical groups…` plus the `for (final g in [...])` loop) with:

```dart
        // Urine, Digestion and Skin were one loop while they were structurally
        // identical. Digestion no longer is — it filters legacy keys — and the
        // Bristol picker must sit directly beneath it, so all three are written
        // out to keep the original section order.
        if (_cats.contains(kCatUrine)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Urine'),
          _FilterChips(
            options: kUrineOptions,
            isSelected: _urine.contains,
            onToggle: (key, sel) =>
                setState(() => sel ? _urine.add(key) : _urine.remove(key)),
          ),
        ],
        if (_cats.contains(kCatDigestion)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Digestion'),
          _FilterChips(
            // dig_hard_stool / dig_loose_stool are superseded by the Bristol
            // scale, so they are offered only where already set: existing values
            // stay untickable, but no NEW duplicate can be created.
            options: [
              for (final o in kDigestionOptions)
                if (!kLegacyDigestionKeys.contains(o.key) ||
                    _digestion.contains(o.key))
                  o,
            ],
            isSelected: _digestion.contains,
            onToggle: (key, sel) => setState(
                () => sel ? _digestion.add(key) : _digestion.remove(key)),
          ),
        ],
        if (_cats.contains(kCatBristol)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Stool form (Bristol scale)'),
          BristolScalePicker(
            value: _metrics[kMetricBristol] ?? 0,
            onChanged: (v) => setState(() => _metrics[kMetricBristol] = v),
          ),
        ],
        if (_cats.contains(kCatSkin)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Skin & hair'),
          _FilterChips(
            options: kSkinOptions,
            isSelected: _skin.contains,
            onToggle: (key, sel) =>
                setState(() => sel ? _skin.add(key) : _skin.remove(key)),
          ),
        ],
```

- [ ] **Step 5: Fix the two stale comments**

`day_entry_form.dart:86-88` currently claims never filtering `_metricConfigs` is the invariant. It is not — `kMetricPain`, `kMetricWeight` and now `kMetricBristol` all live outside it. Replace with:

```dart
/// Numeric metrics rendered as 0..max sliders; 0 means "not logged".
///
/// This is a RENDER list, not the set of metrics. `pain`, `weight` and `bristol`
/// are decoded and saved without appearing here. The real invariant is: every
/// metric is decoded into `_metrics` in initState and emitted by the `numbers`
/// loop in save(). Dropping an entry from either of those erases that metric on
/// the next save.
```

In the class doc comment at `:19-20`, add `bristol` to the parenthesised metric list.

- [ ] **Step 6: Run to verify it passes**

Run: `flutter test test/bristol_form_test.dart`
Expected: PASS (7 tests)

- [ ] **Step 7: Verify the regression test's discrimination proof**

Delete the `_metrics[kMetricBristol] = clampBristol(...)` line added in Step 3.

Run: `flutter test test/bristol_form_test.dart`
Expected: `REGRESSION: a logged Bristol survives saving with the category off` FAILS (Bristol becomes 0, is filtered by `if (e.value > 0)`, and is erased), while the other six stay GREEN. Restore the line.

Then verify the anti-hollowness claim: remove the two `notes` lines from that test and re-run with the decode still deleted. It should now **pass** — demonstrating why the note assertion is load-bearing. Restore both.

- [ ] **Step 8: Run analyze and the full suite**

Run: `flutter analyze && flutter test`
Expected: analyze clean; 567 passed, 0 failed.

Section order must be unchanged for existing users: Urine → Digestion → Skin, with Bristol inserted between Digestion and Skin. If `test/tracking_categories_test.dart` or a form test asserts on order, confirm it still matches.

- [ ] **Step 9: Commit**

```bash
git add lib/widgets/day_entry_form.dart test/bristol_form_test.dart
git commit -m "feat(bristol): render the picker in the day editor

Bristol goes in the existing _metrics map, so save() needs no change at
all - a bespoke field would spread the full-REPLACE invariant across
three sites and is how it would get silently erased.

Unrolls the Urine/Digestion/Skin loop: Digestion now filters legacy keys
so it is no longer structurally identical, and Bristol has to sit
directly beneath it without reordering the existing sections."
```

---

### Task 6: The D7 guardrail test

**Files:**
- Test: `test/bristol_guardrail_test.dart` (create)

**Interfaces:**
- Consumes: `kBristolTypes` (Task 1), `BristolScalePicker` (Task 4)
- Produces: nothing

- [ ] **Step 1: Write the test**

This one is written last and must pass immediately — it is a structural guard over code that already exists, not a TDD cycle.

A naive repo-wide scan is useless: `constipation` and `diarrhea` are legitimate `kSymptomOptions` keys and labels. The scan requires **co-occurrence** of a diagnostic frame with a condition word.

Create `test/bristol_guardrail_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/widgets/bristol_scale_picker.dart';

void main() {
  // Bristol's clinical bands (1-2 constipation, 3-5 normal, 6-7 diarrhoea) are
  // the app diagnosing. The Lewis & Heaton DESCRIPTORS are the instrument and
  // are fine. This scan must not fire on the legitimate plain symptom keys
  // 'constipation' and 'diarrhea'.
  final diagnosticFraming = RegExp(
    r"'[^']*\b(likely|indicates?|suggests?|means|sign of|consistent with|"
    r"normal|abnormal)\b[^']*\b(constipat\w*|diarrh\w*)\b[^']*'",
    caseSensitive: false,
  );

  final namedConditions = RegExp(
    r'\b(severe constipation|chronic diarrh\w*|IBS|Crohn|coeliac|celiac|'
    r'irritable bowel)\b',
    caseSensitive: false,
  );

  Iterable<File> dartFilesIn(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('no diagnostic framing in quoted UI strings', () {
    final offenders = <String>[];
    for (final dir in ['lib/widgets', 'lib/screens', 'lib/services']) {
      for (final f in dartFilesIn(dir)) {
        final src = f.readAsStringSync();
        for (final m in diagnosticFraming.allMatches(src)) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
        for (final m in namedConditions.allMatches(src)) {
          offenders.add('${f.path}: ${m.group(0)}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the plain constipation symptom option is untouched by the scan', () {
    // Proves the regex is not simply matching the bare word: this string exists
    // in the catalog and must stay legal.
    expect(diagnosticFraming.hasMatch("TrackOption('constipation', "
        "'Constipation')"), isFalse);
    expect(
      kSymptomOptions.any((o) => o.key == 'constipation'),
      isTrue,
      reason: 'the option this test protects must still exist',
    );
  });

  testWidgets('no semantics label carries a banding word', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BristolScalePicker(value: 0, onChanged: (_) {}),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('bristol-disclosure')));
    await tester.pumpAndSettle();

    final banned =
        RegExp(r'constipat|diarrh|abnormal|\bnormal\b', caseSensitive: false);
    for (var i = 1; i <= 7; i++) {
      final node = tester.getSemantics(find.byKey(Key('bristol-$i')));
      expect(banned.hasMatch(node.label), isFalse,
          reason: 'type $i label: ${node.label}');
    }
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/bristol_guardrail_test.dart`
Expected: PASS (3 tests). If `no diagnostic framing in quoted UI strings` fails on pre-existing copy, **report the offending line rather than weakening the regex** — it may be a real finding in existing code.

- [ ] **Step 3: Verify the discrimination proof**

Temporarily change one descriptor in `catalog.dart` to `'Separate hard lumps — likely constipation'` and add a `Text('Type 1 indicates constipation')` to `bristol_scale_picker.dart`.

Run: `flutter test test/bristol_guardrail_test.dart`
Expected: `no diagnostic framing in quoted UI strings` AND `no semantics label carries a banding word` both FAIL. The pre-existing `TrackOption('constipation', 'Constipation')` must NOT be reported. Restore both.

- [ ] **Step 4: Commit**

```bash
git add test/bristol_guardrail_test.dart
git commit -m "test(bristol): guard against diagnostic banding copy

Scans for a diagnostic FRAME co-occurring with a condition word rather
than the bare word, because 'constipation' and 'diarrhea' are legitimate
plain symptom keys - a naive scan would fire on the catalog itself. A
second test asserts that exact string stays legal, so the regex cannot
be silently loosened into uselessness."
```

---

### Task 7: The doctor-PDF section

**Files:**
- Modify: `lib/services/pdf_report_service.dart`
- Test: `test/bristol_pdf_test.dart` (create)

**Interfaces:**
- Consumes: `BristolSummary.compute` (Task 2), `kBristolTypes` (Task 1)
- Produces: nothing

- [ ] **Step 1: Write the failing tests**

Look at `test/weight_trend_service_test.dart:107-150` first — it is the size-delta + injected-`generatedOn` precedent this mirrors.

Create `test/bristol_pdf_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/insights_service.dart';
import 'package:menstrul_track/services/pdf_report_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  final generatedOn = DateTime(2026, 6, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> log(int day, {num? bristol}) => repo.upsert(
        date: DateTime(2026, 5, day),
        flow: null,
        symptomsJson: encodeDayTags(
          flags: {'cramps'},
          numbers: {if (bristol != null) kMetricBristol: bristol},
        ),
      );

  Future<int> pdfSize() async {
    final bytes = await PdfReportService.build(
      insights: InsightsService.analyze(const []),
      cycles: const [],
      generatedOn: generatedOn,
      logs: await repo.getAll(),
    );
    return bytes.length;
  }

  test('bristol never enters the symptom-frequency table', () async {
    await log(3, bristol: 4);
    final counts = PdfReportService.symptomCounts(await repo.getAll());

    expect(counts.containsKey(kMetricBristol), isFalse);
    expect(counts.containsKey('cramps'), isTrue); // the table isn't just empty
  });

  // The pdf package compresses text streams, so a byte search finds nothing
  // even for headings that ARE present. Size delta is the only available signal,
  // and it is weak on its own - it proves bytes were added, not that they are
  // Bristol. The paired negative is what gives it value: it catches a section
  // header rendering unconditionally. Real content assertions live on
  // BristolSummary in test/bristol_summary_test.dart.
  test('adds a section only when there are readings', () async {
    await log(3);
    await log(4);
    final without = await pdfSize();

    await log(3, bristol: 4);
    await log(4, bristol: 6);
    final with_ = await pdfSize();

    expect(with_, greaterThan(without));
  });

  test('no readings produces a byte-identical report', () async {
    await log(3);
    final a = await pdfSize();
    await log(4);
    final b = await pdfSize();
    final c = await pdfSize();

    expect(c, b); // deterministic: generatedOn is injected
    expect(b, greaterThan(a)); // and the doc does vary with real content
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/bristol_pdf_test.dart`
Expected: `adds a section only when there are readings` FAILS — sizes are equal, because nothing renders Bristol yet.

`bristol never enters the symptom-frequency table` should already PASS from Task 1. `symptomCounts` is a public static on `PdfReportService` (`:205`); `test/pdf_report_service_test.dart:29` is the calling convention.

- [ ] **Step 3: Add the section**

In `lib/services/pdf_report_service.dart`, add the import:

```dart
import 'bristol_summary.dart';
```

Beside the `weight` computation (~`:40`):

```dart
    // Bowel form. Distribution and mode only — NEVER a mean: the scale is
    // ordinal, so averaging types 1 and 7 would report "type 4 — smooth and
    // soft" and invent a normal reading out of two abnormal ones. No banding:
    // the descriptors are the instrument, the bands would be a diagnosis.
    final bristol = BristolSummary.compute(logs);
```

Then, immediately after the `if (weight != null) ...[ … ],` block (~`:141`):

```dart
          if (bristol != null) ...[
            pw.SizedBox(height: 16),
            pw.Text('Stool form (Bristol scale)',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(
              '${bristol.totalReadings} day(s) recorded, '
              '${df.format(bristol.firstDate)} – ${df.format(bristol.lastDate)}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              headers: const ['Type', 'Description', 'Days'],
              data: [
                for (final t in kBristolTypes)
                  if (bristol.countsByType.containsKey(t.value))
                    [
                      '${t.value}',
                      t.descriptor,
                      '${bristol.countsByType[t.value]}',
                    ],
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Most frequent: '
              '${bristol.mostCommonTypes.map((t) => 'type $t').join(', ')}.',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/bristol_pdf_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Verify the discrimination proof**

Change `if (bristol != null)` to `if (true)` and give the summary a fallback. Run the tests: `no readings produces a byte-identical report` must FAIL (an empty header renders unconditionally). Restore.

- [ ] **Step 6: Run the guardrail and full suite**

Run: `flutter test test/bristol_guardrail_test.dart && flutter analyze && flutter test`
Expected: guardrail still green (the new PDF strings must carry no banding); analyze clean; 573 passed, 0 failed.

- [ ] **Step 7: Commit**

```bash
git add lib/services/pdf_report_service.dart test/bristol_pdf_test.dart
git commit -m "feat(bristol): add the stool-form section to the doctor PDF

Distribution plus most-frequent type(s), with the date span and reading
count. No mean, and no banding - the descriptors are the instrument, the
bands would be the app diagnosing.

Renders nothing at all when no day carries a reading, which the paired
byte-identical test guards."
```

---

### Task 8: Collateral fixes and documentation

**Files:**
- Modify: `lib/screens/calendar/calendar_screen.dart:324-329`
- Modify: `admin/src/paths.js` (`NUMERIC_METRICS`, ~`:86`)
- Modify: `PRIVACY_POLICY.md`, `docs/account-deletion.md`, `CLAUDE.md`, `README.md`
- Test: add to `test/bristol_form_test.dart`

**Interfaces:**
- Consumes: `kNumericMetricKeys` (Task 1)
- Produces: nothing

- [ ] **Step 1: Write the failing calendar test**

Append to `test/bristol_form_test.dart`:

```dart
  test('a day with only a numeric metric counts as logged content', () {
    // calendar_screen gates its content dot on this. Before the fix a
    // Bristol-only day rendered as empty while a row existed, so the day looked
    // unlogged but "Clear this day" appeared on reopen.
    final json = encodeDayTags(numbers: {kMetricBristol: 3});
    expect(decodeSymptoms(json), isEmpty); // still not a symptom
    expect(hasLoggedMetrics(json), isTrue);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/bristol_form_test.dart`
Expected: FAIL — `Undefined name 'hasLoggedMetrics'`

- [ ] **Step 3: Add the helper and use it**

In `lib/common/catalog.dart`, after `clampBristol`:

```dart
/// Whether the day-tags blob carries any numeric metric with a real value.
/// The calendar's "this day has content" dot needs this: numeric metrics are
/// excluded from [decodeSymptoms] by design, so a day whose only content is a
/// weight or a Bristol type would otherwise render as empty.
bool hasLoggedMetrics(String? json) =>
    kNumericMetricKeys.any((k) => (decodeNumber(json, k) ?? 0) > 0);
```

In `lib/screens/calendar/calendar_screen.dart`, extend `hasOtherData` (~`:324`):

```dart
    final hasOtherData = log != null &&
        !bleeding &&
        (decodeSymptoms(log!.symptoms).isNotEmpty ||
            hasLoggedMetrics(log!.symptoms) ||
            log!.mood != null ||
            (log!.notes?.isNotEmpty ?? false) ||
            flow != null);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/bristol_form_test.dart && flutter test test/calendar_inline_entry_test.dart`
Expected: PASS both.

- [ ] **Step 5: Fix the operator panel**

In `admin/src/paths.js`, add to `NUMERIC_METRICS` (~`:86`) so `records.js` stops routing it to `unrecognised`:

```js
  bristol: 'Stool form (Bristol 1–7)',
```

Run: `cd admin && ./test/run.sh`
Expected: 44 passed. (Requires JDK 21 on `PATH`: `export PATH="$(/usr/libexec/java_home -v 21+)/bin:$PATH"`.)

- [ ] **Step 6: Update the disclosure documents**

- `PRIVACY_POLICY.md` — add "digestive/bowel form" to **both** data-category enumerations, and add an explicit line that bowel form **is** included in the doctor-summary PDF. The current text promises sensitive data is excluded by default; that becomes misleading without this.
- `docs/account-deletion.md` — add bowel data to the erased list.
- `README.md` — under Play Data Safety, note digestive data as collected **and** transmitted. No new Play category is needed (Health and fitness covers it).
- `CLAUDE.md` — add `bristol` to the numeric-metric key list in "Key design decisions", and add a short Bristol bullet to "Shipped".

- [ ] **Step 7: Run everything**

Run: `flutter analyze && flutter test`
Expected: analyze clean; 574 passed, 0 failed.

- [ ] **Step 8: Commit**

```bash
git add lib/common/catalog.dart lib/screens/calendar/calendar_screen.dart admin/src/paths.js test/bristol_form_test.dart PRIVACY_POLICY.md docs/account-deletion.md README.md CLAUDE.md
git commit -m "fix(bristol): calendar dot, operator panel and disclosures

A day whose only content was a numeric metric rendered as empty on the
calendar while a row existed - pre-existing for weight and dig_ keys,
but Bristol makes it user-visible.

Also teaches the operator panel the new metric key, and adds bowel form
to both disclosure documents, including an explicit line that it IS in
the doctor PDF (the policy otherwise promises sensitive data is excluded
by default)."
```

---

## Device verification (blocks merge — cannot be automated)

None of this is assertable in a widget test. Run the app on a device with `kCatBristol` enabled:

- [ ] Each of the seven silhouettes is recognisable as what it depicts at normal phone density
- [ ] The unselected shapes are actually visible — a missing `SizedBox` around `CustomPaint` draws nothing and throws nothing
- [ ] Light **and** dark mode both render correctly (the `shouldRepaint` colour comparison is what makes the dark switch repaint)
- [ ] Selecting, re-tapping to clear, and the explicit Clear button all work, and survive closing and reopening the day
- [ ] The picker works from **both** hosts: the full-screen day editor and the calendar bottom sheet
- [ ] TalkBack reads "Type 4, smooth and soft, sausage-shaped, selected" sensibly
- [ ] Seven rows are comfortable to tap on a 360dp-wide screen

## Self-review notes

- **Spec coverage:** D1 → Task 1 (`kLegacyDigestionKeys`) + Task 5 (render filter). D2 → Tasks 2, 7. D3 → Task 1. D4 → Task 4. D5 → Task 3. D6 → Task 5. D7 → Tasks 1, 6. D8 → Task 4. D9 → Task 4. D10 → Task 8.
- **Known gap, deliberate:** the spec's deferred PDF pre-share consent sheet is not in this plan. It is a change to the whole export flow, tracked separately.
- **Known gap, deliberate:** discoverability of a `defaultOn: false` category is unaddressed, as the spec's Risks section states.
- **Test count:** 531 baseline → ~574. Every test names its reversion line except the two flagged honestly as defence-in-depth (`a numeric bristol never reads as a symptom`) and unprovable (`the missing SizedBox`).
