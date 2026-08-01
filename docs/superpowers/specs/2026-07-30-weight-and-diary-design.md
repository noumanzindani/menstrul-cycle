# Weight tracking + readable diary — design spec

**Date:** 2026-07-30
**Status:** approved (design), pending implementation plan
**Schema impact:** `schemaVersion` 3 → 4 (one nullable `AppSettings` column)

## Context

Two items from the v3 backlog, scoped together because they touch the same three
files and ship in one pass:

- **Weight** was genuinely absent from the app.
- **Diary** existed only as a write-only `DailyLogs.notes` column: users can write
  a note for a day, but nothing anywhere lists notes back. The only way to re-read
  one is to navigate to that exact date on the calendar and open the day sheet.
  So "richer diary" is a *retrieval* problem, not an authoring one.

Deliberately **out of scope** (decided during brainstorming, not oversights):

- **BMI in any form.** BMI needs height (a profile value, not a per-day log) and
  its output is a *classification*. A judgeable body-composition label in a cycle
  tracker plausibly used by teenagers is the same class of harm as a synthesized
  fertility percentage, which this app already refuses on principle. No height
  field, no BMI figure, no bands, no "healthy range" vocabulary.
- Multiple timestamped diary entries per day. One note per day has not been shown
  to be the limitation; the inability to *read* notes has.
- The other seven backlog items (custom tags, i18n, sharing, educational content,
  wearables, in-app support, pregnancy milestones) — separate sub-projects, each
  needing its own spec.

## Part 1 — Weight

### Storage

`kMetricWeight = 'weight'` in `common/catalog.dart`, stored via the existing
day-tags blob as a real JSON number, always in **canonical kilograms**.

This rides the established metric seam (`encodeDayTags(numbers: {...})` /
`decodeNumber`) alongside `pain`, `water`, `sleep`, `energy`, `stress` and
`sleep_quality`. Consequences:

- **No `DailyLogs` migration.** Weight is log data and log data needs no schema
  change.
- **No signature changes** to `DailyLogRepository.upsert`, `LogProvider.saveDay`,
  or `DayEntryForm`'s persistence path — weight travels inside `symptomsJson`.
- `0` means unset, consistent with every other metric.

A typed `RealColumn weight` (mirroring `bbt`) was considered and rejected: `bbt`
earned its column by being pre-wired in v1's `onCreate`, whereas weight would
have to pay for a `DailyLogs` migration now, and SQL queryability buys nothing
because trends are computed in Dart over in-memory logs (as `BbtService` already
does).

### Units

Weight is the first metric with a unit, and the unit is a *global* preference, so
it cannot live in the per-day blob.

- New nullable `TextColumn weightUnit` on `AppSettings`: `'kg'` | `'lb'`.
  **null → kg** (null means "never chosen", not a distinct third state).
- Conversion happens only at the display boundary: `kg = lb × 0.45359237`,
  displayed to one decimal place.
- Storage stays canonical kg, so a user who switches units later does not produce
  a trend chart that mixes scales.
- `SettingsProvider.weightUnit` / `setWeightUnit`, exposed as a Settings toggle.

### Input validation

Stricter than other metrics by necessity. Water and sleep are small integers; a
fat-fingered weight of `700` would distort the trend chart's y-axis permanently.

- Accepted range: **20–350 kg** (44–772 lb).
- The bound is checked **after** converting the entered value to canonical kg, so
  the same rule applies in both units and there is no unit-dependent loophole.
- Out-of-range input is **refused with a visible message**, never silently
  clamped or stored.

Refusal requires an interface change: `DayEntryFormState.save()` currently returns
`Future<void>` and both hosts (`DayLogScreen._save` and the calendar sheet's
`_save`) unconditionally pop afterwards. It becomes **`Future<bool>`** — false
means validation failed and the form is showing an inline error, so the host must
*not* pop. Weight is the app's first field that can be invalid, so this seam does
not exist yet.

### Migration (the only schema change)

`schemaVersion` 3 → 4, following the pattern documented in `CLAUDE.md`.

**The v3 snapshot already exists** — `drift_schemas/drift_schema_v3.json` and
`test/generated_migrations/schema_v3.dart` are committed, and `GeneratedHelper`
already dispatches versions 2 and 3. So the usual "dump before bumping or lose it
forever" hazard does **not** apply here: the starting point for a v3→v4 test is
already captured. Order of work:

1. Add the column, bump to 4, add an **independent additive** `if (from < 4)`
   branch (not else-if), so a user on v1 still runs every intervening branch. One
   nullable column, no backfill.
2. `dart run build_runner build` to regenerate `database.g.dart`.
3. `dart run drift_dev schema dump lib/db/database.dart drift_schemas/` to emit
   `drift_schema_v4.json`, then
   `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
   to add `schema_v4.dart` and extend `GeneratedHelper`. The v4 dump is needed
   because `migrateAndValidate(db, 4)` validates the final shape against it — and
   it becomes the starting point for the *next* migration.
4. `test/db_migration_v4_test.dart` — drift's `SchemaVerifier` running the **real**
   `onUpgrade` against a v3 DB seeded with **non-default** rows.

**Background-isolate verification.** `CLAUDE.md` records the isolate migration
path as never verified and says to re-test at the next bump; this is that bump.
`CheckInWriter` opens a bare `AppDatabase()` from a notification action, so on a
v3→v4 update that isolate may run `onUpgrade` — possibly while the UI isolate
opens the same encrypted file. This is a device step, not a unit test.

### Tracking category

New `TrackingCategory(kCatWeight, 'Weight', defaultOn: false)` in
`common/tracking_categories.dart`. Off by default: weight is body-sensitive and
many users will not want the prompt.

Gating is **render-only**, per the existing invariant: `build` filters the
section, but decode and encode cover weight **unconditionally**. Omitting weight
from encode when the category is off would erase a previously logged weight on
the next save, because `encodeDayTags` is a full REPLACE of the blob. This has a
dedicated regression test.

### Surfaces

- **Day editor** (`widgets/day_entry_form.dart`) — a decimal `TextField` with a
  kg/lb suffix, mirroring the existing `_bbt` controller pattern (parse on save,
  prefill from `existing`). Gated by `kCatWeight`. It **cannot** join the existing
  `_metrics` map: that is a `Map<String, int>` driven by 0..max sliders, and weight
  needs one decimal place. So weight gets its own controller and is written into
  the `numbers` map separately, as a `double`. The controller holds the value in
  the *display* unit; conversion to canonical kg happens in `save()`.
- **Settings** — the kg/lb toggle, as a new item in the same section as
  "Customize tracking" (it configures tracking rather than app behaviour).
- **Insights** — a pure `WeightTrendService` over `LogProvider.logs` (same shape
  as `BbtService`), rendered with `fl_chart` like the existing `_BbtChart`.
  Requires ≥2 logged points to draw. The window is the **last 90 days**, or all
  readings if the first is more recent than that. Copy is strictly descriptive:
  latest value and net change across that window. No BMI, no bands, no judgement
  vocabulary.
- **Doctor PDF** — a compact weight row (latest + range). Clinically useful for
  thyroid/PCOS discussion, and cheap.
- **Not** on Home. Not in the home-screen widget.

## Part 2 — Diary timeline

### Data path

A new `DiaryScreen` filters `LogProvider.logs` for days whose `notes` is non-null
and non-blank, sorted newest-first. Search is a debounced, case-insensitive
substring match computed in Dart, matching **note text only** — not symptoms,
moods or dates.

No new repository method, no query, no schema change. `LogProvider` already loads
every log into memory via `_repo.getAll()`, so this is pure presentation over
existing state, and the filter/search logic is a pure function that can be tested
without pumping a widget.

### Entry point

A journal icon on the **Calendar app bar**, pushing `DiaryScreen`.

Bottom navigation is already at five destinations (Today / Calendar / Forecast /
Insights / Settings), which is Material's practical ceiling, so a sixth tab was
rejected. Calendar is the app's date-browsing surface and already owns
tap-a-day-to-edit, making it the strongest conceptual fit at zero navigation cost.

### Required refactor: extract the day-entry sheet

Tapping a diary row must open that day for editing, and the correct thing to open
is the sheet Calendar already uses — but `_DayEntrySheet` is private to
`calendar_screen.dart`.

Extract it to `widgets/day_entry_sheet.dart` as a public `DayEntrySheet` plus a
`showDayEntrySheet(context, date)` helper, and switch Calendar to the extracted
version.

**This is a move, not a tidy-up.** That sheet's structure is a hard-won fix, and
the following must survive verbatim:

- Its content is a `Scaffold` **on purpose** (form in `body`, Save in
  `bottomNavigationBar`). An inline panel below the viewport-filling month grid
  never lays out: a lazy `ListView` skips it, and eager variants crash with
  "BoxConstraints forces an infinite width" because a Material button will not lay
  out under a scroll/sheet's unbounded-width intrinsic pass.
- The `LogProvider` re-provide into the sheet route.
- The 0.85 screen-height cap.

`test/calendar_inline_entry_test.dart` exists to catch a regression here and must
stay green throughout the extraction.

### Row content

Date, a two-line note snippet, and the **cycle day** ("Cycle day 12"). Cycle day
is free — cycles are already computed in `LogProvider` — and it is what makes this
a *cycle* diary rather than a generic notes list.

### Empty state

When no day has a note, explain where notes come from rather than showing a blank
list.

## Guardrails

Two rules, both structurally tested:

1. **No `AdBanner` on the diary screen.** Personal free-text reflection belongs to
   the same family as logging and Insights, where ads are already banned. (The
   interstitial only fires on switching *into* Home, so a pushed route cannot
   trigger one — no change needed there.)
2. **Diary text never enters the doctor PDF.** Free text can contain anything —
   mental health, sexuality, abuse. Sex data is already excluded by default for
   exactly this reason. Auto-exporting a journal into a document handed to a
   clinician is a disclosure the user never consented to. Weight goes in the PDF;
   notes do not.

App-lock already covers the whole app, so the diary needs no separate gate.

Existing guardrails are untouched: this feature adds no fertility surface, no
percentage, and no new network permission.

## Testing

TDD (RED → GREEN → REFACTOR), asserting the **positive as well as the negative**
per the rule that produced `calendar_inline_entry_test.dart`.

| Test | Asserts |
|---|---|
| `weight_test.dart` | encode/decode round-trip; kg↔lb both directions; `0` = unset; out-of-range refused |
| `weight_trend_test.dart` | pure service: <2 points yields nothing; ordering; change over window; unset ignored |
| `db_migration_v4_test.dart` | `SchemaVerifier` v3→v4 against a v3 DB seeded with non-default rows |
| weight-category regression | with `kCatWeight` **off**, an existing logged weight survives a save |
| `diary_screen_test.dart` | only note-bearing days listed, newest-first; search filters; empty state; row tap opens the day sheet |
| ad placement | diary screen renders **no** `AdBanner` |
| PDF | weight row present **and** diary text absent |
| `calendar_inline_entry_test.dart` | stays green across the sheet extraction (regression) |

**Device verification** (cannot be unit-tested — in-memory DBs skip the cipher and
the encryption seam fails silently):

1. Install a v3 build, log data, then update to v4 and confirm data survives.
2. Tap a check-in notification action with the app killed across that update, to
   exercise the isolate `onUpgrade` path.
3. Confirm `databaseIsEncryptedAtRest()` still returns true after the bump.

## Files touched

**New**
- `lib/services/weight_trend_service.dart`
- `lib/screens/diary/diary_screen.dart`
- `lib/widgets/day_entry_sheet.dart` (extracted)
- `test/weight_test.dart`, `test/weight_trend_test.dart`,
  `test/db_migration_v4_test.dart`, `test/diary_screen_test.dart`
- `drift_schemas/` + `test/generated_migrations/` v3 snapshot

**Modified**
- `lib/common/catalog.dart` (`kMetricWeight`)
- `lib/common/tracking_categories.dart` (`kCatWeight`)
- `lib/db/tables.dart` (`AppSettings.weightUnit` only — `DailyLogs` is untouched),
  `lib/db/database.dart` (version + `onUpgrade` branch), then regenerate
  `database.g.dart` with `dart run build_runner build`
- `lib/providers/settings_provider.dart`, `lib/data/settings_repository.dart`
- `lib/widgets/day_entry_form.dart`
- `lib/screens/calendar/calendar_screen.dart` (app-bar action + use extracted sheet)
- `lib/screens/insights/insights_screen.dart`
- `lib/screens/settings/settings_screen.dart`
- `lib/services/pdf_report_service.dart`

## Open follow-ups (not this spec)

- New user-facing strings are hardcoded English, consistent with the rest of the
  app outside `settings_screen`. They join the deferred i18n sweep.
- `CLAUDE.md` needs its stale "Pregnancy mode — Deferred" section corrected (the
  feature is shipped) and "Habit chips" removed from the v3 backlog (also
  shipped). Unrelated to this work, but noted while surveying.
