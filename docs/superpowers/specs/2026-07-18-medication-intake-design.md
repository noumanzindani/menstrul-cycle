# Per-day medication intake + adherence — design

**Date:** 2026-07-18
**Status:** approved (design), pending implementation plan
**Closes:** the last unmet Clue Plus "Complete Cycle Overview" bullet — *Medications* — in LunaTrack.

## Problem

The Cycle Overview screen already rolls up bleeding, symptoms, emotions, pain,
lifestyle, and notes per cycle. **Medications** is absent because there is no
per-day intake record: the `Medications` table is a *catalog/schedule*
(name / type / schedule / enabled), never joined to a day. This design adds a
per-day "which medications did I take" fact, surfaces it in the Cycle Overview,
and adds a descriptive adherence view on Insights.

Scope selected by the user: **log intake + show in Cycle Overview + adherence
stats** (the middle of three depth options; the notification-shade "confirm from
reminder" tier is explicitly out of scope).

## Non-goals

- No new DB column and no `schemaVersion` bump — this is migration-free, like
  every v2 increment and like "Period ended" (`flow = none`).
- No adherence *percentage* against an assumed daily target (see §4).
- No medication-frequency field (daily/weekly/as-needed). That would be the
  correct enabler for a true adherence %, but it is a schema + editor change and
  is deferred.
- No notification-action ("Taken/Skip") intake logging. Deferred.

## 1. Data layer — migration-free, mirrors `habit_`

Per-day intake is stored as a namespaced key inside the existing
`DailyLogs.symptoms` JSON map, exactly like `sex_`, `cm_`, `vag_`, `shx_`,
`habit_`:

- **Key format:** `med_<id>` where `<id>` is the `Medications` row id
  (e.g. `med_3: true` = "took medication #3 that day").
- **`catalog.dart`:** add `const String kMedicationKeyPrefix = 'med_';` and
  append it to `kReservedTagPrefixes`, so `decodeSymptoms` filters it out (meds
  never pollute the symptom-chip list — same protection the other prefixes get).
- **Decode:** the existing `decodeGroup(json, kMedicationKeyPrefix)` returns the
  set of `med_<id>` keys for a day. No new helper needed.

**Why id, not name or type:** matches the codebase's stable-key discipline
(`MedicationType` keys "never rename"). The id survives a rename and
distinguishes two medications of the same type. Trade-off: a *deleted* medication
leaves orphaned `med_<id>` keys in old logs that can no longer resolve to a name;
those fall back to the generic label `"Medication"` (the same graceful default
`medicationTypeLabel` already returns). Orphaned keys are harmless — they simply
show as "Medication" in historical overviews.

## 2. Logging surface — chip group in `DayEntryForm`

A new **"Medications"** section in `lib/widgets/day_entry_form.dart`, rendered
with the existing `_FilterChips` widget (identical to the Lifestyle group): one
chip per configured medication, label = medication name, selecting a chip adds
`med_<id>` to a new `Set<String> _medications` field that is folded into the
`save()` flags set alongside `_habits`.

- **Med list injection:** `DayEntryForm` gains an optional constructor parameter
  `List<MedChip> medications = const []` (a tiny value type: `int id`,
  `String name`). The form does **not** read `MedicationProvider` from context —
  keeping it free of a second hard provider dependency so existing form/sheet
  widget tests stay pumpable unchanged. The two callers supply the list:
  - `calendar_screen.dart` `_DayEntrySheet` → reads `MedicationProvider` and
    passes enabled meds to `DayEntryForm`.
  - `day_log_screen.dart` `DayLogScreen` → same.
- **initState:** seed `_medications` from
  `decodeGroup(existing.symptoms, kMedicationKeyPrefix)` so an existing day's
  intake round-trips.
- **Visibility:** the section renders only when the passed `medications` list is
  non-empty. The list is scoped to **enabled** medications (`enabled == true`) —
  `enabled` already means "currently taking / not paused," so a med the user
  turned off will neither prompt a reminder nor clutter the day editor. A user
  with no medications configured sees no Medications section (unchanged editor).

## 3. Cycle Overview — the section that closes the gap

- **`lib/models/cycle_overview.dart`:** add
  `final List<LabeledCount> medications;` to `CycleOverview` (required, defaults
  to `const []` at the call site when empty). Remove/replace the doc comment that
  currently explains medications are *absent*.
- **`lib/services/cycle_overview_service.dart`:** `summarize` accepts the
  medication name lookup. Because the service is pure `(cycle, logs)` today, the
  id→name map is passed in as a parameter:
  `summarize(Cycle cycle, List<DailyLog> logs, {Map<int, String> medNames = const {}})`.
  For each in-cycle day, `decodeGroup(l.symptoms, kMedicationKeyPrefix)` yields
  `med_<id>` keys; strip the prefix, parse the id, tally days, and rank via the
  existing `_rank` helper with a label function that looks up `medNames[id]`
  (fallback `"Medication"`). Callers (`insights_screen.dart` cycle-history tap)
  build `medNames` from `MedicationProvider.items`.
- **`lib/screens/insights/cycle_overview_screen.dart`:** add a "Medications"
  `_Section` rendering `_Counts(items: o.medications)`, gated on
  `o.medications.isNotEmpty`, placed after Lifestyle and before Notes.

## 4. Adherence on Insights — descriptive, no fabricated %

**Chosen representation (option A):** a "Medications this cycle" card showing,
per enabled medication, the **count of days logged** in the most recent complete
cycle, drawn as a horizontal bar **scaled to the cycle length** (mirrors the
existing `_SymptomFrequencyList` `LinearProgressIndicator` bars). Label reads
`"logged 26 days"` — never a ratio, never a percentage.

**Rationale:** a true adherence % needs a per-med target frequency, which the
schema does not store. Rendering "26/28" would assume a *daily* target and be
invented precision for a weekly patch or an as-needed med — the same class of
false-precision error the project bans for fertility (CLAUDE.md guardrail). A
days-logged count is fully truthful with the data on hand.

- **New pure service** `lib/services/medication_adherence_service.dart`:
  `MedicationAdherenceService.forCycle(Cycle cycle, List<DailyLog> logs, List<Medication> meds)`
  → `MedicationAdherence` (`lib/models/medication_adherence.dart`): a list of
  `(medId, name, daysLogged, cycleLength)` entries for enabled meds that were
  logged ≥1 day in the cycle, ranked by `daysLogged` desc. Pure, deterministic,
  unit-testable with an in-memory DB.
- **New Insights widget** `_MedicationAdherenceList` in `insights_screen.dart`,
  under a "Medications this cycle" `_SectionLabel`, gated on
  `adherence.hasData`. Built from `MedicationProvider.items` +
  `CycleCalculator` cycles + `LogProvider.logs`. Because Insights must stay
  pumpable without extra providers, the section only renders when a
  `MedicationProvider` is present and returns data; absence → section hidden
  (no hard `!`), consistent with the screen's existing tolerant composition.

## 5. Testing (TDD — RED → GREEN throughout)

The suite is currently green (234 tests). New/extended tests, each written and
watched failing first:

1. `catalog` — `kMedicationKeyPrefix` is reserved (`decodeSymptoms` excludes a
   `med_<id>` key) and `decodeGroup` returns it.
2. `CycleOverviewService` — medication days are tallied per cycle, id→name
   mapping applied, orphaned id falls back to `"Medication"`, ranked desc.
3. `cycle_overview_screen` — the "Medications" section renders when present and
   is absent when the list is empty.
4. `DayEntryForm` — passing `medications` renders the chip group; toggling a chip
   and saving writes `med_<id>` into the day's `symptoms`; an existing
   `med_<id>` seeds the chip selected. No medications → no section.
5. `MedicationAdherenceService` — days-logged per enabled med for a cycle, cycle
   length as denominator context, disabled meds excluded, unlogged meds excluded.
6. Insights `_MedicationAdherenceList` — renders bars when data present; hidden
   otherwise; never a "%".

`flutter analyze` stays clean; `flutter test` stays green before done.

## 6. On-device verification

Same protocol as the prior features (respect the shared device, don't commandeer
another `flutter run`): configure a medication in Settings, log intake across a
couple of days, confirm the chip group in the day editor, the "Medications"
section in a Cycle Overview, and the "Medications this cycle" adherence bar on
Insights render correctly.

## Files touched

**New:**
- `lib/models/medication_adherence.dart`
- `lib/services/medication_adherence_service.dart`
- tests: catalog (extend), cycle-overview service (extend), cycle-overview
  screen (extend), day-entry-form med chips (new), adherence service (new),
  insights adherence widget (new).

**Modified:**
- `lib/common/catalog.dart` — `kMedicationKeyPrefix` + reserved list.
- `lib/widgets/day_entry_form.dart` — `medications` param, `_medications` set,
  Medications chip section, save/initState wiring.
- `lib/screens/calendar/calendar_screen.dart` — pass enabled meds into the form.
- `lib/screens/log/day_log_screen.dart` — pass enabled meds into the form.
- `lib/models/cycle_overview.dart` — `medications` field.
- `lib/services/cycle_overview_service.dart` — `medNames` param + tally.
- `lib/screens/insights/cycle_overview_screen.dart` — Medications section.
- `lib/screens/insights/insights_screen.dart` — adherence section + med-name map
  for the cycle-history → overview navigation.
