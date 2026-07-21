# CLAUDE.md

Guidance for Claude Code (and human contributors) working in this repository.

## Project overview

**LunaTrack** is a private, on-device menstrual/period tracker built with Flutter.

Core thesis: **"$0 running cost" and "privacy" are the same decision** → 100% on-device
data, no backend, no account, no network sync. Everything (logs, cycles, predictions,
reports) is computed and stored locally.

- **Platform:** Android-first (Play one-time $25). iOS deferred (the $99/yr Apple fee is
  the only real running cost).
- **Monetization:** AdMob (non-personalized ads, **banned from the logging and insights
  screens**) + a one-time **Premium** in-app purchase that removes ads.

## Commands

```bash
flutter pub get
flutter run                 # run on a connected device/emulator
flutter analyze             # static analysis (keep clean)
flutter test                # run all tests
flutter test test/foo_test.dart
flutter build apk --debug   # or: --release
flutter build appbundle --release
```

No `build_runner` is needed for day-to-day work unless the **drift** schema changes
(hand-written models are used where possible to avoid codegen).

## Architecture

State management is **`provider` (`ChangeNotifier`)**; persistence is **`drift`** (SQLite,
on-device) as the single source of truth.

```
lib/
  db/            drift database + connection (encryption is seam'd — see below)
  data/          repositories over drift (DailyLogRepository, SettingsRepository)
  models/        enums + hand-written model classes (prediction, cycle, insights)
  providers/     ChangeNotifier state (LogProvider, SettingsProvider, PremiumProvider, …)
  services/      pure logic (PredictionService, CycleCalculator, InsightsService, PdfReportService, AdService)
  screens/       app_shell + home / calendar / forecast / insights / settings / log / onboarding
  widgets/       shared widgets (DayEntryForm, AdBanner, disclaimer_banner, …)
  common/        catalog (symptom/mood/sex options), date_utils, theme
```

Predictions are wired reactively in `main.dart` via `ProxyProvider2`
(`LogProvider` + `SettingsProvider` → `PredictionResult` → future periods).

### Key design decisions (non-obvious)

- **Cycles are derived, not stored.** The user logs daily flow; `CycleCalculator` groups
  consecutive bleeding days (1-day gap tolerance) into cycles. A `PeriodEntries` table
  exists but is intentionally **unused** — activating it would create a second source of
  truth for cycle boundaries.
- **"Period ended" = write `flow = FlowIntensity.none` for that day.** `none.isBleeding`
  is false, so `CycleCalculator` terminates the run at the prior bleeding day. Do not use
  `PeriodEntries` for this.
- **Sex logging shares the `symptoms` JSON**, namespaced with a `sex_` key prefix
  (`common/catalog.dart`: `kSexKeyPrefix`, `decodeSex`). `decodeSymptoms` filters `sex_`
  keys out, so sex never pollutes the symptom-chip list — and it is **excluded by default
  from the doctor PDF**. JSON-object storage (`{key:true}`) is used so tags extend with
  zero migration. **Many groups now ride this one blob** under reserved key prefixes
  (`med_`, `sex_`, `cm_`, `vag_`, `shx_`, `habit_`, `urn_`, `dig_`, `skin_` — all listed in
  `kReservedTagPrefixes`); `decodeSymptoms` strips every reserved prefix, so none of them
  reach the symptom list, Insights, or the doctor PDF. `encodeDayTags` is a full **REPLACE**
  (rebuilds the whole blob from form state), so the day editor must decode/encode EVERY
  group unconditionally — gating a group out of decode or save silently destroys it.
- **Schema & migrations.** `schemaVersion` is **3**. `onUpgrade` uses independent additive
  `if (from < n)` branches (not else-if), one nullable column each, so a user on any old
  version runs every intervening branch and existing rows need no backfill: v1→v2 added
  `AppSettings.pregnancyStartDate`; v2→v3 added `AppSettings.trackingCategories`. A committed
  JSON snapshot per version lives in `drift_schemas/` and `test/generated_migrations/`;
  `test/db_migration_v3_test.dart` uses drift's `SchemaVerifier` to run the REAL `onUpgrade`
  against a v2 DB seeded with non-default rows. In-memory `AppDatabase.forTesting` runs
  `onCreate` at the current schema and NEVER exercises `onUpgrade`, so every new migration
  needs a snapshot dumped BEFORE the version bump (only derivable while that version is
  current) and its own SchemaVerifier test. Not yet verified: the background-isolate
  migration path (`CheckInWriter` opens a bare `AppDatabase()` from a killed-app
  notification action) — re-test at the next bump.
- **Customizable tracking (Phase A).** The day editor renders sections gated by a registry
  of `TrackingCategory` ids (`common/tracking_categories.dart`); Settings → "Customize
  tracking" (`screens/settings/tracking_categories_screen.dart`) toggles them, persisted as
  a JSON id array in `AppSettings.trackingCategories`. **null column = use registry defaults;
  empty array = user turned everything off** (a real choice — never conflate the two).
  Gating is **render-only** (`build` filters by category); decode and encode always cover
  all groups. `DayEntryForm.categories` is nullable: `null` = "no opinion, show everything"
  so the form stays pumpable without a `SettingsProvider`. All tracking is FREE (no
  `PremiumProvider` read anywhere in this feature). Flow, Period-ended, Mood, Pain, BBT/OPK
  and Notes are core cycle/fertility data and deliberately NOT toggleable.
- **Prediction is the calendar method**, always labelled an estimate and **never a
  contraceptive method**. Fertile window is awareness-only.
- **Fertility indicator is a qualitative band, never a number** (`FertilityBand` enum,
  `PredictionService.fertilityBand`). A precise "%" from a calendar-only estimate is false
  precision that reads as a "safe day" — an Apple 1.4.1 / Play health-misinformation /
  real-user-harm risk. The ovulation marker and band are **confidence-gated**: suppressed
  below `PredictionConfidence.medium`.
- **Two confidences, deliberately split.** `PredictionResult.confidence` gates the
  next-period chip; `.fertilityConfidence` gates the band + ovulation marker. Symptothermal
  corroboration (`OvulationSignalService`) raises ONLY `fertilityConfidence`, one notch, so
  a single OPK unlocks the band when actionable without overstating next-period precision.
  It only ever RAISES, is skipped while `capConfidenceToLow` is set (perimenopause cap is
  the ceiling), and the band still self-suppresses outside the window — so it can never
  manufacture a "safe" reading. `fertilityConfidence` falls back to `confidence` when unset.
- **DB encryption is ON and device-verified** (2026-07-16).
  `sqlcipher_flutter_libs`/`sqlite3_flutter_libs` are no-op stubs in `sqlite3` v3;
  encryption is a build hook (`hooks.user_defines.sqlite3.source: sqlite3mc` in pubspec)
  that only compiles on a real device. `kDatabaseEncryptionEnabled` in
  `lib/db/connection.dart` is `true`; the DB key is a random 256-bit passphrase in the OS
  keystore (`flutter_secure_storage`), and the encrypted file is a *separate* filename
  (`lunatrack_enc.db` vs the old `lunatrack.db`) so enabling it created a fresh DB rather
  than failing to open a plaintext one — safe only because the app never shipped.
  **This seam fails SILENTLY:** if the native cipher build isn't active, `PRAGMA key`
  no-ops on stock sqlite3 and the file stays plaintext while the app believes otherwise.
  Tests can't catch it (in-memory DBs skip the cipher) — re-verify on a device with
  `databaseIsEncryptedAtRest()` if you touch `connection.dart` or the pubspec hook.

### Guardrails (hold these regardless of product pressure)

- Never the word **"safe"** next to any fertility/ovulation UI. The non-contraception
  disclaimer (`widgets/disclaimer_banner.dart`) stays on every fertility surface.
- **No false precision** — fertility is qualitative, no synthesized %.
- **Ads never co-render with logging or insights.** `test/ad_placement_test.dart` guards
  this structurally. The interstitial only fires on switching into Home.

## Feature status

### Shipped (v1 + v2 migration-free; v3 = customizable tracking, first real migration)

- Daily logging (flow, symptoms, mood, sex, notes) + "Period ended" toggle
- Combined calendar + entry, predictions + Home, reminders, insights + doctor PDF export
- App-lock, onboarding, delete-all-data, privacy-policy draft
- AdMob (Google **test** IDs) + one-time Premium IAP
- Track / Conceive **modes** (`AppSettings.mode`); Conceive reorders Home to lead with
  fertility. Ovulation calendar marker + qualitative fertility band. Extended doctor PDF
  (symptom/mood frequency + estimated fertility; sex excluded).
- **Symptothermal fertility** — BBT numeric input + `fl_chart` chart; cervical-mucus
  quality (`cm_*`); OPK/LH result (`opk` column); non-diagnostic thermal-shift observation
  (`BbtService`, 3-over-6 rule, awareness-only in Insights). A positive/peak OPK near the
  estimated ovulation **corroborates** the calendar and raises the fertility band ONE
  confidence notch (`OvulationSignalService` → `PredictionResult.fertilityConfidence`).
  In **Conceive mode only**, a thermal shift in the *current* cycle
  (`BbtService.shiftInCurrentCycle` → `OvulationConfirmation` provider) surfaces a Home
  note ("ovulation likely confirmed around …") — framed for conception planning, carrying
  the non-contraceptive caveat, and NEVER "safe".
- **On-device insights narratives ("Your patterns")** — `InsightsNarrator` (pure, no deps,
  `services/insights_narrator.dart`) turns the user's own data into plain-language
  `CycleNarrative`s: cycle-length trend (recent 3 vs earlier), regularity, period-length
  trend, current phase, and **symptom↔phase correlation** ("you most often log headaches
  around your luteal phase"). Descriptive, never diagnostic; each gated on enough data.
  Surfaces: a "Your patterns" section on Insights (inline, no phase), a Home highlight card
  (shared `ProxyProvider2` → `List<CycleNarrative>`, top non-phase narrative), and a "Cycle
  patterns" section in the doctor PDF. Branded "insights," not "AI."
- **Local backup & restore** (`services/backup_service.dart`) — Settings → "Backup &
  restore". Serializes all tables (drift `toJson`/`fromJson`) → **AES-256-GCM + PBKDF2**
  passphrase encryption (`BackupCrypto`) → `.lunabak` file shared via `share_plus`. Restore
  picks a file (`file_picker`), confirms (destructive), decrypts, and replaces all data in
  one transaction — a wrong passphrase throws before any write, so data is never lost. **No
  cloud, no server** — the user owns the file. Deps: `share_plus`, `file_picker`,
  `cryptography` (existing `crypto` can't encrypt).
- **Period check-ins ("Did it start? / Has it ended?")** — a pure `CycleCheckInService`
  (`services/cycle_check_in.dart`) decides, from logs + prediction + today, which single
  prompt (if any) to surface. Both answers collapse to the one primitive
  `flow = FlowIntensity.none` (a confirmed no-bleeding day — the same as "Period ended
  today"), so there is **no new column or migration**, and a logged flow of ANY kind
  silences the prompt for the day (the log itself is the "answered" flag). Surfaces: a Home
  prompt card (one-tap "Not yet"/"It ended", or "log it" → the ad-free day editor); the
  shared `PeriodCheckInBanner` on the calendar day-sheet, which back-fills any date
  (express lane: mark no-bleeding + close, so it never fights the form's Save); and a
  concrete "N days late" count on the Home next-period card. Period timing only — no
  fertility framing, the "safe" guardrail is untouched.
- **Home month ring ("cycle glance")** — a `CustomPaint` ring on the Home dashboard (top,
  right after the phase card): one arc segment per day of the CURRENT month, today's date +
  cycle day + phase in the centre, today's segment dotted. A pure `MonthRingBuilder`
  (`services/month_ring_builder.dart`) maps logs + prediction + today → `MonthRingData`
  (`models/month_ring.dart`), exposed via a `ProxyProvider2` (main.dart) like the other
  derived Home models. **Migration-free.** Per-day precedence: logged bleeding → predicted
  next-period run → fertile/ovulation → normal. Colours come from the `PhaseColors` theme
  extension (same tokens as the calendar), so light/dark adapt. **The fertility guardrail is
  structural, not incidental:** fertile/ovulation roles are assigned SOLELY through the
  confidence-gated `PredictionService.fertilityBand(confidence: fertilityConfidence)`, so
  they vanish below medium confidence, outside the window, on null data, and under the
  perimenopause cap — the ring can't imply a "safe" day. The legend shows Fertile/Ovulation
  entries only when a matching segment is actually painted (each gated on `hasFertile` /
  `hasOvulation` separately, so a window straddling the month boundary never shows a key
  with no arc). Display-only (no inline logging → never co-renders with the ad banner); the
  trailing `DisclaimerBanner` covers it.

- **One-tap check-in from the notification shade (Phase A)** — answer the daily
  period check-in ("Didn't start" / "Mark ended here") from the notification
  action **without opening the app**. A pure **precomputed horizon**
  (`services/check_in_notifications.dart`, `CheckInHorizon.plan`) replaces the old
  single repeating log-nudge: because `CycleCheckInService.evaluate` is pure in
  `(logs, prediction, day)` and logs can't change while the app is closed, it
  precomputes one one-shot notification per day for the next **14 days** — the
  check-in question if there is one, else the generic nudge — carrying the right
  copy + action baked in. Rescheduled on app foreground/resume
  (`HomeWidgetSync`) and inside the background handler after a write. Tapping the
  action runs `notification_actions.dart`'s `@pragma('vm:entry-point')` handler in
  a **background isolate** (app may be killed): it inits plugins, then
  `CheckInWriter.answerNoBleeding` opens the **encrypted** DB on a second
  connection and calls `DailyLogRepository.setFlowIfEmpty` (single-column, atomic,
  no-op if a flow is already logged — so stale/double-tap answers self-heal, the
  log IS the "answered" flag), recomputes + reschedules + pushes the widget. Key
  properties: notifications are **`visibility: secret`** (cycle state never hits
  the lock screen — and, as a bonus, "only answerable after unlock" means the
  keystore is always available to the writer); the action uses
  `cancelNotification: false` and the handler dismisses **only on a successful
  write**, so a failed write leaves the question standing as its own retry (no
  "couldn't save" copy); `PRAGMA busy_timeout = 5000` lets the second connection
  wait rather than throw (no WAL sidecar). The horizon is **gated on the existing
  `ReminderType.logNudge` toggle** — disabled means nothing is scheduled
  (regression guard: never resurrect notifications the user turned off). The
  prediction recompute both the foreground and the isolate run is the SINGLE
  `PredictionService.predictFromLogs` (mode suppressions in one place, so they
  can't diverge). **Migration-free.** Copy is verbatim from `PeriodCheckInBanner`
  — period timing only, no fertility framing (structural guardrail test). The
  isolate→keystore→cipher path **cannot be unit-tested** (same reason encryption
  can't) — **verify on a device**: fire the check-in, tap the action with the app
  killed, confirm the day is written, the widget refreshes, and the notification
  is cancelled. **iOS** notification actions come via a `DarwinNotificationCategory`
  (generic "Confirm" label); the iOS home-widget button is Phase B, deferred.

**Calendar day entry is a bottom sheet, not an inline panel.** Tapping a day opens
`_DayEntrySheet` (in `calendar_screen.dart`), whose content is a **`Scaffold`** (mirrors
`DayLogScreen`: form in `body`, Save in `bottomNavigationBar`). This is deliberate: an
inline panel below the viewport-filling month grid never reliably lays out (a lazy
`ListView` skips it; eager variants crash with "BoxConstraints forces an infinite width"
because a Material button won't lay out under a scroll/sheet's unbounded-width intrinsic
pass). A Scaffold gives the form and button bounded, tight constraints and absorbs that
intrinsic query. `_selectedDay` still gates the calendar ad while the sheet is open.

### Deferred

- **Pregnancy mode** — its own release. The migration scaffolding now exists (schema is at
  **v3** with a tested `onUpgrade` and `drift_schemas/` snapshots — see "Schema & migrations"
  above), so this needs only its own additive `if (from < 4)` branch + column (and a v3
  snapshot dumped before the bump), a `PregnancyService` (Naegele EDD), and loss-safe UX
  (neutral wording, no
  celebratory UI, instant stop of pregnancy notifications on exit, one-tap exit + delete).

### v3 backlog (from a Meet You competitor teardown)

- Weight, Habit chips, richer Diary. **i18n/l10n** — the app is currently hardcoded
  English (`AppSettings.language` is dormant); localization is its own initiative.

## Pre-store-submission checklist (needs the project owner's accounts)

- Real upload keystore (release is debug-signed today).
- Real AdMob app + unit IDs (currently Google **test** IDs — flip `AdConfig.useTestAds`,
  fill `_prod*` + manifest `APPLICATION_ID`).
- Real Play in-app product id for Premium.
- ✅ **DONE** — `kDatabaseEncryptionEnabled` is on and device-verified (2026-07-16).
- Host the privacy policy at a URL; declare **sexual-activity** (and later pregnancy) data
  in Play Data Safety / Apple privacy nutrition label + tick "Data is encrypted at rest"
  (now true, and backed by the on-device header check).

## Package gotchas (all currently resolved)

- `flutter_local_notifications` v22 uses all-named params (`zonedSchedule(id:,
  scheduledDate:, notificationDetails:, …)`); needs `isCoreLibraryDesugaringEnabled` +
  `desugar_jdk_libs` in `android/app/build.gradle.kts`.
- `flutter_timezone` returns `TimezoneInfo` (use `.identifier`).
- `local_auth` 3.x `authenticate` takes bool params directly (`biometricOnly:`,
  `persistAcrossBackgrounding:`); `MainActivity` must extend `FlutterFragmentActivity`.

## Testing

TDD is the norm (RED → GREEN → REFACTOR). Tests use
`AppDatabase.forTesting(NativeDatabase.memory())`. When adding UI behind a state flag,
assert the **positive** (the thing appears) as well as the negative — see
`test/calendar_inline_entry_test.dart`, which exists because an earlier ad-placement test
only checked that the ad hid, not that the entry form actually rendered.
