# Bristol Stool Scale — design

Date: 2026-08-07
Status: approved design, not yet implemented
Reviewed by: a five-seat council (UI, security, code review, test architecture, QA), all
returning *sound-with-changes*. Where seats disagreed, the resolution and its reasoning are
recorded inline.

## Problem

The day editor records bowel state three coarse ways that cannot express *form*:
`dig_hard_stool`, `dig_loose_stool`, `dig_no_bm` (`catalog.dart:209-215`). Bowel form is
cycle-linked (luteal constipation, menstrual diarrhoea, IBS overlap) and the Bristol Stool
Scale is the published clinical instrument for it — a 7-point ordinal scale (Lewis & Heaton,
1997) that a GP or gastroenterologist already reads without explanation.

Adding it is worth doing because the app has no asset pipeline to amortise artwork against
(zero runtime images, zero Lottie, no `assets:` block in `pubspec.yaml`), so the diagram is
cheaper to draw in code than to license or commission.

## Non-goals

- No drift schema change. This is migration-free; `schemaVersion` stays 5.
- No diagnostic output of any kind (see D7).
- No Bristol-driven `PatternNudge` in `insights_service.dart`.
- Not touching the doctor PDF's existing sections, beyond adding one.

## Decisions

### D1 — Additive, with legacy-only rendering for the two superseded keys

Bristol does not replace anything and no stored data is ever rewritten.

`dig_hard_stool` and `dig_loose_stool` become **legacy-only options**: rendered *only on days
where they are already set*. Concretely, the Digestion chip list is built as
`kDigestionOptions.where((o) => !kLegacyDigestionKeys.contains(o.key) || _digestion.contains(o.key))`
— so a user who already ticked one can untick it, and nobody can newly set one. `dig_no_bm`
stays a permanent, always-rendered option — Bristol describes only stool that exists, so
"didn't go" has no Bristol type and is genuinely orthogonal.

Note the interaction with category gating: if `kCatDigestion` is off, legacy chips are not
rendered at all, so clearing one requires re-enabling that category. That is the pre-existing
behaviour of every hidden category and the reason for D10's Settings copy fix, not a new
problem introduced here.

*Why not simply keep all three rendered:* three controls for one fact, none updating the
others, landing in different report sections. `catalog.dart:206-208` already states the
codebase's position — the digestion group deliberately excludes diarrhea/constipation because
"those are already plain symptoms in `kSymptomOptions` and must not be restated under a second
key." Bristol 1-2 / 6-7 versus `dig_hard_stool` / `dig_loose_stool` is a *truer* duplicate than
the case that comment already forbids.

*Why not simply delete them from the option list:* `decodeGroup(tags, 'dig_')` loads **any**
`dig_` key into `_digestion` and `save()` re-encodes it. Dropping them from
`kDigestionOptions` would strand every existing value — invisible in the picker and impossible
to untick. Legacy-only rendering is what satisfies both constraints.

`catalog.dart:206-208`'s comment must be rewritten to record this deliberate overlap and name
Bristol as the single source for the PDF section, so nothing double-counts.

### D2 — Included in the doctor PDF, as distribution and mode, never a mean

Bristol is the one genuinely clinical field in the digestion group and belongs in a document
handed to a doctor.

**It must never report an average.** Bristol is *ordinal*: a user logging type 1 and type 7 has
had constipation and diarrhoea, not "type 4 — smooth and soft." A mean would invent a normal
reading out of two abnormal ones, in a clinical document.

The section reports: the date span, the number of days with a reading, the count per type, and
the most common type(s). Ties report **every** tied type rather than picking one.

Gating: the section renders only when at least one day in the report window has a non-zero
value, and is omitted entirely otherwise — no empty heading.

*Follow-up raised by the security seat, deliberately out of scope here:* `insights_screen.dart`
builds the full-history PDF and calls `Printing.sharePdf` immediately, with no preview and no
section list. Bristol 6-7 alongside the existing weight-trend section supports a
purging/laxative-misuse inference the user never asserted; type 1-2 alongside the pain metric
supports a bowel-endometriosis inference. A pre-share confirmation listing the PDF's sections
is the right fix, but it is a change to the whole export flow and is tracked separately, not
folded into this feature.

### D3 — Encoding: unprefixed numeric day-metric `bristol`, 1-7, `0` = unset

`const String kMetricBristol = 'bristol';` beside the other `kMetric*` constants
(`catalog.dart:83-89`). Stored as a real JSON number in the existing day-tags blob. Never a
literal.

The app-wide "`0` means unset" convention fits exactly — Bristol has no type 0 — so there is no
sentinel to invent and no nullable column.

Rejected alternatives, re-derived independently by the code-review seat:

- **`dig_bristol_1..7` single-select.** `decodeSingle` matches `e.value == true`, so seven
  booleans discard ordinality; nothing could count or trend a type without a key→int side
  table. It also sits under the namespace whose purpose is PDF exclusion, so D2 would need a
  carve-out in `decodeSymptoms`' contract.
- **Prefixed numeric `dig_bristol`.** Safe but pointless: two overlapping exclusion mechanisms
  on one key, and no metric is prefixed today.
- **A real `DailyLogs.bristol` INT column.** The only serious rival — correct typing,
  queryable. Rejected on cost: one nullable column means a v6 bump, a `drift_schemas` snapshot
  dumped *before* the bump, a new `SchemaVerifier` test, and re-pointing
  `db_migration_v3_test.dart`. The blob exists precisely to avoid that.

**Hardening — the exclusion becomes explicit rather than accidental.** Today an unprefixed
numeric stays out of `decodeSymptoms` only by failing the `== true` test. That is a
*type-based* boundary, and the type is not ours to guarantee: `firestore.rules:53-58` is
`allow read, write: if isOwner(userId)` with no field validation, and `sync_mapper.dart:60`
accepts whatever map comes back. A raw REST write of `{"bristol": true}` is boolean-true and
unprefixed, so it would reach the symptom-frequency table and print in the doctor PDF as the
literal string `bristol` via `symptomLabel`'s raw-key fallback (`catalog.dart:328`). Self
-injection only — tampering, not a confidentiality break — but into a clinical document.

Therefore:

- Add `const Set<String> kNumericMetricKeys = {kMetricPain, kMetricWater, kMetricSleep,
  kMetricEnergy, kMetricStress, kMetricSleepQuality, kMetricWeight, kMetricBristol};`
- `decodeSymptoms` filters `!_isReserved(k) && !kNumericMetricKeys.contains(k)` in **both**
  branches, including the legacy-list branch at `catalog.dart:260`.
- A test asserts `kNumericMetricKeys` is disjoint from the union of `kSymptomOptions` and
  `kEmotionalOptions` keys. `encodeDayTags` writes flags first and numbers second into one map
  literal (`catalog.dart:238-241`), so a key in both silently loses its boolean with no error.
- `catalog.dart:80-82`'s "they never satisfy the `== true` symptom check" comment becomes false
  once this lands and must be rewritten.

### D4 — A CustomPainter picker, seven keyed rows

New `lib/widgets/bristol_scale_picker.dart`. Follows `month_ring.dart`, the app's only existing
`CustomPainter`.

Structure: **seven separate keyed tap targets**, each wrapping its own `CustomPaint`, not one
painter doing internal hit-testing (which would be testable only by pixel arithmetic and would
break at any text scale). Each row is `Key('bristol-$n')` + `MergeSemantics` +
`Semantics(button: true, inMutuallyExclusiveGroup: true, selected: …, label: 'Type N — <descriptor>')`.
The `CustomPaint` itself carries no semantics — the drawing is decorative and the visible
"Type N" text plus descriptor carries the meaning.

Required properties:

- **Explicit size.** `CustomPaint` with a null child and no `size` defaults to `Size.zero` and
  paints nothing. Wrap in a `SizedBox` or pass `size:`.
- **Determinism.** Types 2 and 6 need irregular edges. Never `Random()` — not even
  `Random(seed)` inside `paint()`, which allocates per frame and reshapes silently on any
  reorder of draw calls. Use `static const` unit-space (0..1) control points per type, built
  once into a `static final Map<int, Path>`, then `canvas.scale(size.width, size.height)`. Set
  `paint.strokeWidth = w / scale` or the stroke thickens with the canvas.
- **`shouldRepaint`** compares `type`, `selected` **and every colour field**, per
  `month_ring.dart:191-200`. Returning `false` is a dark-mode bug: the new painter carries new
  colours and the render object never repaints.
- **Colours** resolve in `build` and are passed in; the painter never touches `BuildContext`.
  Use `ColorScheme`, **not** the `PhaseColors` extension — those are cycle-phase semantics and
  borrowing luteal amber for stool is a semantic lie. Unselected must not use the ring's
  `onSurface` at 0.10 alpha (~1.1:1) when the shape *is* the meaning: `outline` stroke over
  `surfaceContainerHighest` fill (≥3:1, WCAG 1.4.11); selected is `secondaryContainer` fill
  with `onSecondaryContainer` stroke, plus a non-colour marker (check icon or ring). No
  hardcoded hex.
- **Text scale.** No fixed row height. Text `Expanded` so it wraps; paint box scales via
  `MediaQuery.textScalerOf(context).scale(40).clamp(40, 72)`. Minimum 48dp tap target at 1.0.
- Ban `IntrinsicHeight` / `IntrinsicWidth` / `Table` / nested horizontal scrollers inside the
  picker. (The documented "BoxConstraints forces an infinite width" crash does **not** apply
  here — both hosts put the form in a `Scaffold` body, so the `ListView` hands each row a tight
  width, and `RenderCustomPaint` with no child has intrinsic width 0. The ban is to keep it
  that way.)

Descriptors (paraphrased from Lewis & Heaton, kept distinct from every existing `TrackOption`
label — `tracking_catalog_test.dart:55` enforces label uniqueness):

| Type | Descriptor |
|---|---|
| 1 | Separate hard lumps |
| 2 | Lumpy and sausage-shaped |
| 3 | Sausage-shaped with cracks |
| 4 | Smooth and soft, sausage-shaped |
| 5 | Soft blobs with clear edges |
| 6 | Fluffy pieces with ragged edges |
| 7 | Watery, no solid pieces |

An axis label reads `hard ←→ loose`. That is descriptive, not diagnostic.

### D5 — Its own tracking category, `kCatBristol`, `defaultOn: false`

**Reversed from the original design**, which put it inside `kCatDigestion`.
`tracking_categories.dart:16` states the contract: *"New categories ship OFF so no existing
user's day editor grows unasked."* A user who enabled Digestion for gas and heartburn chips
would get seven silhouettes on the next update without being asked. `kCatSleepQuality` is the
precedent for splitting one distinct control out of a shared section.

`TrackingCategory(kCatBristol, 'Stool form (Bristol scale)', defaultOn: false)`, rendered
directly beneath the Digestion block.

This means the Digestion block must be lifted out of the shared three-tuple render loop at
`day_entry_form.dart:379-393` (Urine and Skin stay in it) so Bristol lands under Digestion
rather than under "Skin & hair". Update the `:377-378` comment accordingly.

### D6 — Bristol lives in `_metrics`; `save()` needs no change

Decoded in `initState` on the line beside `kMetricPain` (`day_entry_form.dart:140`):

```dart
_metrics[kMetricBristol] = _clampBristol(decodeNumber(tags, kMetricBristol));
```

`save()`'s existing loop already emits every entry in `_metrics` whose value is `> 0`
(`day_entry_form.dart:199-201`), so **no change to `save()` is required**. A bespoke
`int? _bristol` field would spread the invariant across three sites and is exactly how it would
get silently erased.

`_metricConfigs` renders 0..max sliders and Bristol must not be a slider, so Bristol does not
join that list — which is fine: `kMetricPain` and `kMetricWeight` already live outside it. The
`:86-88` comment currently claims "NEVER filter this list" is the invariant. It is not. The real
invariant is *every metric is decoded into `_metrics` in `initState` and emitted by the
`numbers` loop*. Rewrite that comment.

**Clamping.** `decodeNumber` returns any `num`. A restored backup or a sync from a future or
tampered client can carry `9` or `3.5`, which would highlight no silhouette, persist through
save, and print in the PDF. `_clampBristol` returns the value only when it is an integer in
1..7, else 0.

### D7 — Descriptors yes, bands never, everywhere

The Lewis & Heaton descriptors ("separate hard lumps", "fluffy pieces with ragged edges") **are**
the instrument and are descriptive. They appear on the picker, in the semantics labels, and in
the PDF row. Without them a bare "5" is clinically inert and the field is decorative.

The *bands* — 1-2 = constipation, 3-5 = normal, 6-7 = diarrhoea — are the app diagnosing. They
are banned in the UI **and in the PDF**, which resolves an ambiguity the original decision left
open. Same class of harm as this project's banned BMI classification and banned fertility
percentage: an instrument's raw reading is the user's data, an interpretation of it is a claim
the app is not qualified to make.

No Bristol-driven `PatternNudge` in `insights_service.dart:139-193`.

### D8 — The unset path (new; QA called the omission a blocker)

`0` = unset, and nothing in the original design let a user get back to it. Tap a silhouette,
save, reopen — the only removal was "Clear this day", which destroys flow, notes and every
other group.

Both affordances ship:

1. Re-tapping the selected row clears to 0 (the `_SingleChips` convention at
   `day_entry_form.dart:495`, but it must be written explicitly: `_bristol == t ? 0 : t`, since
   a raw `InkWell` does not get this free the way `ChoiceChip` does).
2. A visible "Clear" action rendered only when a value is set, mirroring the metric sliders' `—`.

### D9 — Collapsed by default, expanding inline

With every category on, the day editor is already 19 sections, ~85 chips, 6 sliders and 3 text
fields. Seven full-width illustrated rows is roughly another viewport.

The picker renders collapsed as a single row — `Stool form — Not logged ›`, or the selected
descriptor — and expands **in place**.

*Deviation from the QA seat's recommendation, which was a sub-sheet:* from the calendar the day
editor is itself a bottom sheet (`day_entry_sheet.dart`), and CLAUDE.md documents a painful
history of layout failures in that host. A sheet inside a sheet buys a "Cancel = no write" path
that D8's re-tap-to-clear already provides, at real structural risk. Inline disclosure gives the
same length saving and the same dignity benefit — nothing recognisable is on screen until the
user opens it.

### D10 — Collateral fixes

- **Calendar content dot.** `calendar_screen.dart:324-329` computes `hasOtherData` from
  `decodeSymptoms` / mood / notes / flow, so a Bristol-only day renders as empty while a row
  exists. Include numeric metrics in that test. Pre-existing for `dig_*` and weight; Bristol
  makes it user-visible.
- **Operator panel.** `admin/src/paths.js:86`'s `NUMERIC_METRICS` has no `bristol`, so
  `records.js:56` routes it to `unrecognised` and renders a raw key/value pair. Add
  `bristol: 'Stool form (Bristol 1–7)'`.
- **Settings copy.** `tracking_categories_screen.dart:8-12` promises hidden data is "never
  deleted". It is also still included in reports — say so.
- **Release note.** A device still on an older build re-encodes the blob without `bristol` and
  last-write-wins pushes that. Inherent to every additive key (weight included), not new here,
  but worth stating.

## Files

Create:

- `lib/widgets/bristol_scale_picker.dart`
- `lib/services/bristol_summary.dart` — pure aggregator, `WeightTrendService` shape
- `test/bristol_test.dart`, `test/bristol_form_test.dart`, `test/bristol_picker_test.dart`,
  `test/bristol_guardrail_test.dart`, `test/bristol_pdf_test.dart`

Modify:

- `lib/common/catalog.dart` — `kMetricBristol`, `kNumericMetricKeys`, `decodeSymptoms` filter,
  `_clampBristol`, Bristol descriptors, rewrite the `:80-82` and `:206-208` comments
- `lib/common/tracking_categories.dart` — `kCatBristol`
- `lib/widgets/day_entry_form.dart` — decode into `_metrics`, lift Digestion out of the render
  loop, render the picker, legacy-only `dig_hard_stool` / `dig_loose_stool`, rewrite `:86-88`
- `lib/services/pdf_report_service.dart` — the Bristol section
- `lib/screens/calendar/calendar_screen.dart` — content dot
- `lib/screens/settings/tracking_categories_screen.dart` — copy
- `admin/src/paths.js` — `NUMERIC_METRICS`
- `PRIVACY_POLICY.md` — add digestive/bowel form to both category enumerations, and an explicit
  line that bowel form **is** included in the doctor PDF (the current text promises sensitive
  data is excluded by default)
- `docs/account-deletion.md` — add bowel data to the erased list
- `CLAUDE.md`, `README.md` — the metric key list; note digestive data as collected+transmitted

## Testing

Baseline is 531 Dart tests, verified green on this tree. Roughly 22 added → ~553.

Every test below names the single line whose reversion turns it red. A test whose covering fix
can be reverted while it stays green is hollow; this project has caught eleven of those.

**Pure — `test/bristol_test.dart`**

1. Round-trips as an unprefixed JSON number. *Revert:* rename the constant to `'dig_bristol'`.
2. Never reads as a symptom. *Revert:* encode via `flags:` instead of `numbers:`.
3. `{"bristol": true}` is still not a symptom — the D3 hardening. *Revert:* the
   `kNumericMetricKeys` filter in `decodeSymptoms`.
4. `kNumericMetricKeys` is disjoint from the symptom key sets. *Revert:* add a colliding key.
5. `decodeGroup(json, 'dig_')` does not capture `bristol`, and `bristol` is not a prefix of any
   existing key.
6. `0` and absent are indistinguishable on read: `_clampBristol(null) == 0` and
   `decodeNumber` of a blob with no `bristol` key returns null. (The "save omits 0" half of
   this belongs to the form and is asserted in test 14a below — `encodeDayTags` itself does
   *not* filter zeros, the `if (e.value > 0)` guard lives in `save()`.)
7. Out-of-range (`9`, `3.5`, `-1`) clamps to unset. *Revert:* `_clampBristol`.
8. Bristol option labels are unique against every existing `TrackOption` label.
9-11. `BristolSummary`: counts per type · `compute` returns null when no day in the window has a
   non-zero value · **reports mode, never a mean**. *Revert:* `mode` → `average`; the test fails
   on `[1, 7]` by asserting no `4` is produced. Tied modes report every tied type, ascending.

**Form — `test/bristol_form_test.dart`** (mirrors `weight_form_test.dart`)

12. Renders seven types when `kCatBristol` is on.
13. Hidden when off — **must scroll to Notes first**, or "not built" is confused with "below the
    fold" (the `weight_form_test.dart:81` anti-vacuity trick).
14. Tapping type 4 saves `bristol = 4`.
14a. Clearing the selection omits the key entirely from the saved blob rather than writing
    `bristol: 0`. *Revert:* the `if (e.value > 0)` filter at `day_entry_form.dart:200`.
15. Re-tapping the selected type clears to unset (D8).
16. Re-opening shows the stored type selected. *Revert:* the `initState` decode.
17. **Regression: a logged Bristol survives saving with the category OFF.** Seed a day with
    `dig_gas` + `bristol: 5`; pump with `categories: const <String>{}`; **type a note**; save;
    assert `bristol == 5` **and** `dig_gas` survived **and** the note landed.
    *Why the obvious version is hollow:* seed → pump gated-off → save → assert `bristol` is
    still 5 passes even if `save()` early-returns or `saveDay` no-ops, because the original row
    is simply untouched. The note assertion is the discriminator — it proves a full REPLACE
    actually landed. *Revert:* the `initState` decode line; 12-16 all stay green.
18. Same shape with the category ON but untouched — catches a decode that happens in `build`
    rather than `initState`.

**Guardrail — `test/bristol_guardrail_test.dart`** (D7)

19. No diagnostic framing in quoted string literals. A naive scan is useless — `constipation`
    and `diarrhea` are legitimate `kSymptomOptions` keys. Require *co-occurrence* of a
    diagnostic frame (`likely|indicates|suggests|means|sign of|consistent with|normal|abnormal`)
    with a condition word (`constipat\w*|diarrh\w*|IBS|bowel disease`), plus a hard-deny list
    scoped to `lib/widgets/` and `lib/screens/` for `severe constipation|chronic diarrh|IBS|
    Crohn|coeliac|celiac`. *Revert:* add `'Type 1 likely means constipation'` to the picker; the
    existing `TrackOption('constipation', 'Constipation')` must stay green.
20. The seven semantics labels contain no banding word — the accessibility surface is where
    diagnostic copy usually sneaks in.

**PDF — `test/bristol_pdf_test.dart`**

21. Bristol is absent from the symptom-frequency table — a real assertion on
    `symptomCounts(logs)`, not a byte search.
22. The section appears when there are readings (size delta, `generatedOn` injected), paired
    with: no readings → byte-identical to baseline. The size assertion is weak by itself — it
    proves bytes were added, not that they are Bristol — which is why the substantive content
    assertions live on the pure aggregator in 9-11. The paired negative is what gives it value:
    it catches an empty section header rendering unconditionally.

**Picker — `test/bristol_picker_test.dart`**

23. Seven distinct keyed tap targets. *Revert:* a loop bound of 6.
24. `shouldRepaint` true across a selection change, false for identical input — catches both a
    `=> true` stub (jank) and a `=> false` stub (stale selection in dark mode).
25. No overflow at `textScaleFactor` 2.0. *Revert:* a fixed row height.

**Deliberately not written:** golden files. They would need a pinned `AppTheme`, a fixed surface
size and a loaded font, they are host-renderer-sensitive, and the repo has zero goldens today —
introducing the modality for one widget is not worth it. Also skipped: asserting a `CustomPaint`
exists, which an empty painter satisfies.

**Not testable — verify on device or drop:** whether the seven silhouettes are recognisable as
what they depict and non-repellent at phone density; TalkBack pronunciation of the labels;
tap ergonomics for seven rows on a 360dp screen. Tests 23 and 25 prove only that the widgets
exist and do not overflow.

## Risks

- The silhouettes may read badly at phone density. Unassertable in any test; a device check
  gates the merge.
- The PDF section's byte-size test is a smoke test. Mitigated by putting the real assertions on
  the pure aggregator.
- `kCatBristol` ships off, so the feature is invisible until a user opts in via Settings ›
  Customize tracking. That is the deliberate contract at `tracking_categories.dart:16`, but it
  does mean discoverability is unaddressed by this design.
