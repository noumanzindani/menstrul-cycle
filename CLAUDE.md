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
  zero migration.
- **Prediction is the calendar method**, always labelled an estimate and **never a
  contraceptive method**. Fertile window is awareness-only.
- **Fertility indicator is a qualitative band, never a number** (`FertilityBand` enum,
  `PredictionService.fertilityBand`). A precise "%" from a calendar-only estimate is false
  precision that reads as a "safe day" — an Apple 1.4.1 / Play health-misinformation /
  real-user-harm risk. The ovulation marker and band are **confidence-gated**: suppressed
  below `PredictionConfidence.medium`.
- **DB encryption is seam'd, not on.** `sqlcipher_flutter_libs`/`sqlite3_flutter_libs` are
  no-op stubs in `sqlite3` v3; encryption is a build hook
  (`hooks.user_defines.sqlite3.source: sqlite3mc` in pubspec) that only compiles on a real
  device. The flag `kDatabaseEncryptionEnabled` in `lib/db/connection.dart` gates it —
  flip + verify during a device build before shipping sensitive data.

### Guardrails (hold these regardless of product pressure)

- Never the word **"safe"** next to any fertility/ovulation UI. The non-contraception
  disclaimer (`widgets/disclaimer_banner.dart`) stays on every fertility surface.
- **No false precision** — fertility is qualitative, no synthesized %.
- **Ads never co-render with logging or insights.** `test/ad_placement_test.dart` guards
  this structurally. The interstitial only fires on switching into Home.

## Feature status

### Shipped (v1 + v2, all v2 increments migration-free)

- Daily logging (flow, symptoms, mood, sex, notes) + "Period ended" toggle
- Combined calendar + entry, predictions + Home, reminders, insights + doctor PDF export
- App-lock, onboarding, delete-all-data, privacy-policy draft
- AdMob (Google **test** IDs) + one-time Premium IAP
- Track / Conceive **modes** (`AppSettings.mode`); Conceive reorders Home to lead with
  fertility. Ovulation calendar marker + qualitative fertility band. Extended doctor PDF
  (symptom/mood frequency + estimated fertility; sex excluded).

**Calendar day entry is a bottom sheet, not an inline panel.** Tapping a day opens
`_DayEntrySheet` (in `calendar_screen.dart`), whose content is a **`Scaffold`** (mirrors
`DayLogScreen`: form in `body`, Save in `bottomNavigationBar`). This is deliberate: an
inline panel below the viewport-filling month grid never reliably lays out (a lazy
`ListView` skips it; eager variants crash with "BoxConstraints forces an infinite width"
because a Material button won't lay out under a scroll/sheet's unbounded-width intrinsic
pass). A Scaffold gives the form and button bounded, tight constraints and absorbs that
intrinsic query. `_selectedDay` still gates the calendar ad while the sheet is open.

### Deferred

- **Pregnancy mode** — its own release. Needs the one DB migration (`schemaVersion` bump +
  `onUpgrade`), a `PregnancyService` (Naegele EDD), and loss-safe UX (neutral wording, no
  celebratory UI, instant stop of pregnancy notifications on exit, one-tap exit + delete).

### v3 backlog (from a Meet You competitor teardown)

- **Symptothermal fertility** — numeric BBT + cervical-mucus quality. The dormant
  `DailyLogs.bbt` / `.opk` columns are pre-wired for exactly this; adding UI + a
  thermal-shift refinement upgrades Conceive mode from calendar-only toward a real
  biological signal (still not contraception-grade without clinical validation).
- Weight, Habit chips, richer Diary. **i18n/l10n** — the app is currently hardcoded
  English (`AppSettings.language` is dormant); localization is its own initiative.

## Pre-store-submission checklist (needs the project owner's accounts)

- Real upload keystore (release is debug-signed today).
- Real AdMob app + unit IDs (currently Google **test** IDs — flip `AdConfig.useTestAds`,
  fill `_prod*` + manifest `APPLICATION_ID`).
- Real Play in-app product id for Premium.
- Turn on `kDatabaseEncryptionEnabled` + verify on a device build before sex/pregnancy
  data ships.
- Host the privacy policy at a URL; declare **sexual-activity** (and later pregnancy) data
  in Play Data Safety / Apple privacy nutrition label; verify Android auto-backup does not
  upload a plaintext DB.

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
