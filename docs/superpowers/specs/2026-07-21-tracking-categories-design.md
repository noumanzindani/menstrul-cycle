# Expanded Tracking Categories + "Customize tracking" — Design

**Date:** 2026-07-21
**Status:** Approved. Implementation plan to follow.
**Reviewed by:** four independent lenses — architecture, data/migration, privacy & health-safety, test strategy.

## Problem

Clue Plus differentiates on ~10 premium tracking categories (sleep quality, supplements, urine, vulva & vagina, and further wellness/reproductive tracking). Auditing LunaTrack against that list shows the gap is much narrower than it appears:

| Clue category | LunaTrack today |
|---|---|
| Supplements | **Already ships** — Medications supports a "Supplement / vitamin" type with per-day `med_<id>` intake |
| Vulva & vagina | Partial — `kVaginalOptions` has itching, burning, dryness, odor (`lib/common/catalog.dart:117`) |
| Sleep quality | Partial — `kMetricSleep` records *hours*; no quality rating |
| Urine | Missing |
| Wellness / reproductive | Already deep — habits, mood, emotional, sexual health, discharge, OPK, BBT, pain, water, energy, stress |

Genuine gaps: **sleep quality, urine, digestion, skin & hair**, and a wider **vulva & vagina** list.

## Decisions

### 1. Tracking stays free

`lib/screens/premium/premium_screen.dart:7` states *"Safety features are NEVER behind this paywall"*, and lines 11-14 record that the doctor PDF "is (and must stay) free — it is a health feature". Gating health tracking would reverse that guardrail. Premium remains ads-off only; no `PremiumProvider` read appears anywhere in this design. Differentiation on non-health extras is a separate future decision.

> Noted for later: if Premium ever gates **backup/restore**, that is arguably a data-safety feature. Paywalling the only route to get health data off a device whose encryption key is unrecoverable would sit uncomfortably against the same guardrail.

### 2. Users choose which categories appear

Adding four surfaces to an already-long day editor would degrade it for everyone. Instead, a **Customize tracking** settings screen lets users toggle categories; new categories default **off**, so no existing user's editor grows unasked. This mirrors what Clue itself does and reuses the enabled/disabled pattern already built for Medications.

### 3. Ship logging first, analysis second

Reserved-prefix data never reaches Insights — `decodeSymptoms` strips it, confirmed at `symptom_analysis_service.dart:20`, `insights_narrator.dart:124`, `cycle_overview_service.dart:54`, `insights_service.dart:198`. New categories would therefore be **write-only** on arrival.

This is not hypothetical: water, sleep, energy and stress are *already* write-only, referenced only at `day_entry_form.dart:58-61` and read by no service, screen or export.

So the work splits:

- **Phase A (this design)** — catalog additions, category registry, Customize tracking screen, day-editor gating. Additive; no migration of tracking data.
- **Phase B (separate spec)** — surface the new groups in Insights/Cycle Overview, fix the orphaned metrics, and handle the doctor PDF.

Shipping A first means a migration or export-UI problem cannot block tracking users may want now.

### 4. Doctor PDF deferred to Phase B, with export-time control

Originally this design routed urine/digestion/skin into the doctor PDF. Privacy review found that, as specified, data would enter a shared document permanently: disabling a category would not withdraw it, and the only remedy — `clear()` — deletes the entire day including flow, mood and notes. There is no export preview; `_exportPdf` (`insights_screen.dart:33-53`) builds and hands straight to the share sheet.

The PDF is the only unencrypted artefact that leaves the device, so this is the whole disclosure surface. Phase B will add an **export-time confirmation sheet** listing reportable groups as checkboxes, making disclosure an explicit act rather than a setting configured months earlier.

Phase B must also use an **explicit key whitelist**, never a prefix scan. `decodeGroup(prefix)` matches any future key under that namespace, so a later `skin_genital_rash`-style addition would ship into a shared document with no review step while every existing guard test still passed.

## Data design

All chip data rides in the existing `DailyLogs.symptoms` JSON via reserved prefixes — migration-free, exactly like `med_`:

```dart
const String kUrineKeyPrefix     = 'urn_';
const String kDigestionKeyPrefix = 'dig_';
const String kSkinKeyPrefix      = 'skin_';
const String kMetricSleepQuality = 'sleep_quality'; // 1–5 numeric metric
```

Option lists avoid duplicating existing **keys and labels**. `kSymptomOptions` already contains `acne`, `diarrhea`, `constipation`, `bloating`, `nausea`, and — critically — `swelling` labelled "Swelling". The widened vulva list therefore uses **"Vulval swelling"**, not "Swelling": an identical label would be ambiguous on screen and would break the test suite, where `find.text` is exact-match and throws on multi-match across 17 call sites.

The **category preference** is the only thing needing a migration: a nullable `TextColumn trackingCategories` on `AppSettings`, `schemaVersion` 2 → 3, additive `addColumn` in `onUpgrade` — the same shape as the existing v1→v2 migration. `null` means "use defaults", so no backfill.

Verified safe: `AppSettings` has no autoincrement, indices or `customConstraints`. Encryption is unaffected — `PRAGMA key` is issued in the `NativeDatabase(setup:)` callback (`connection.dart:86-99`) before any statement, so the migration runs on an already-unlocked connection and `ADD COLUMN` is a header-only change. Backup restore tolerates the missing key, since drift's generated `fromJson` yields `null` for absent nullables.

## The data-loss constraint

**`encodeDayTags` is a full replace, not a merge** (`lib/common/catalog.dart:156-163`). `save()` builds a fresh JSON object from form state; anything not held in state at save time is destroyed.

Therefore: **category filtering happens in `build` only.** `initState` must decode every group and iterate the **unfiltered** `_metricConfigs`; `save()` must re-encode everything.

The numeric path is the dangerous one. `_metricConfigs` feeds *both* the `initState` decode (`day_entry_form.dart:98`) and the `build` render (`:278`), while `save()` writes from `_metrics` alone (`:124-127`). Filtering that list at its definition or in `initState` means a disabled metric is never decoded, never in `_metrics`, and is silently dropped on the next save of that day.

Medications already demonstrate the correct shape: render-only gating at `:264`, unconditional decode at `:96` and re-encode at `:120`.

Two related truths the UI copy must respect:

- `clear()` is a **full row delete** (`:139` → `deleteForDate`), so it destroys hidden categories too.
- A day logged *only* with hidden-group data shows no calendar marker — `calendar_screen.dart:401-405` derives `hasOtherData` from `decodeSymptoms` only. Pre-existing (already true for habits, medications, vaginal); this widens it.

## User-facing copy

The claim must be accurate. In Phase A it is simple and uniform:

> Turning a category off only hides it from the day editor. Anything you've already logged is kept on this device.

It must **not** claim Insights or PDF visibility — neither is true for prefixed groups.

The screen itself must be localized: `settings_screen.dart` uses `context.l10n` 61 times. Chip labels stay hardcoded English, consistent with every existing option list (`day_entry_form.dart` uses l10n zero times).

## Scope boundaries

**Never toggleable, by deliberate decision:** Flow, "Period ended today", Pain, BBT/OPK, Notes — the app's core cycle and fertility data.

**Not in this design:** anything in Phase B; `PRIVACY_POLICY.md:28-31` (which states health symptoms are "excluded by default from the doctor-summary PDF") stays accurate for Phase A and is updated in Phase B alongside the export change.

## Success criteria

1. A user can enable Urine, Digestion, Skin & hair and Sleep quality, log them, and see them persist.
2. A user who enables nothing sees a day editor unchanged from today.
3. Disabling a category hides it and **never** loses previously logged values — including the numeric metric path.
4. The v2→v3 migration preserves existing logs, medications and settings on real hardware, including when it first runs in a background isolate from a notification action.
5. No health surface sits behind the paywall.
