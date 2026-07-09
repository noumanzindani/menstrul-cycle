# LunaTrack — HANDOFF / RESUME HERE

> **Read this first after a fresh `git clone`.** It is the single source of "where
> we are and what to do next." Everything ephemeral that does **not** survive a clone
> — the session memory (`.remember/`, which lives *above* the repo root), the private
> planning notes, and the roadmap — is folded in below so nothing is lost.
>
> The authoritative *engineering* reference is [`CLAUDE.md`](./CLAUDE.md) (committed).
> This file is the *continuity* reference: status, roadmap, and decisions.

**Last updated:** 2026-07-07 · **State:** v3 complete, green.

---

## ⏱️ YOU ARE HERE

LunaTrack **v3 is code-complete and green** — `123/123` tests pass, `flutter analyze`
is clean, and `flutter build apk --debug` assembles. Everything through **Phase 3**
(below) is done. The working tree compiles; nothing is committed-then-broken.

**Phase 4 in progress.** ✅ #2 **On-device insights narratives** shipped
(`InsightsNarrator` + Insights/Home/PDF surfaces, 143/143 tests). Still open:
**#1 encryption flip** (your device-verify gate), #3 local backup, #4 `AD_ID` strip.
See [Phase 4](#-phase-4--next-start-here).

To get back to work:

```bash
flutter pub get
flutter test          # expect: All tests passed! (123)
flutter analyze       # expect: No issues found!
flutter run           # on a connected Android device
```

Regeneration (only when needed): `flutter gen-l10n` after editing `lib/l10n/*.arb`;
`dart run build_runner build` **only** if the drift schema changes.

---

## The product in one breath (thesis — never violate)

**"$0 running cost" and "privacy" are the same decision → 100% on-device, no backend,
no account, no network sync.** Everything (logs, cycles, predictions, reports) is
computed and stored locally. Headline claim: *"a period tracker that works fully
offline, needs no account, and can't see your data."*

- **Platform:** Android-first (Play one-time $25). iOS deferred ($99/yr is the only
  real running cost).
- **Monetization:** non-personalized AdMob (Google **test** IDs today; **banned from
  the logging and insights screens**) + a one-time **Premium** IAP that removes ads.

### Guardrails (hold these regardless of product pressure)

- Never the word **"safe"** next to any fertility/ovulation UI.
- **No false precision** — fertility is a qualitative **band**, never a `%`.
- **Ads never co-render with logging or insights** (`test/ad_placement_test.dart`
  guards this structurally).
- **Never paywall a safety feature** — the doctor PDF stays free.
- **Non-diagnostic framing always.** Perimenopause and pregnancy must never let a
  hidden fertile window read as "safe" (peri copy states *"You can still become
  pregnant — cycle timing is not a reliable guide."*).
- **Bright-line:** if a feature needs `INTERNET` **for user data**, it breaks the
  thesis. ⚠️ The *merged* release manifest already contains `INTERNET` (from
  `google_mobile_ads` + `in_app_purchase`), so the honest claim is **"your data never
  leaves the device,"** NOT "the app has no network access." Non-personalized ads send
  no health data.

---

## Roadmap — phase history + what's next

### Phase 1 — v1 MVP ✅
Daily logging (flow/symptoms/mood/notes), calendar, calendar-method predictions +
Home, local timezone-aware reminders, insights + doctor PDF export, PIN + biometric
app-lock, onboarding, delete-all-data, privacy-policy draft, AdMob (test IDs) +
one-time Premium IAP, custom moon icon.

### Phase 2 — v2 "Meet You" parity ✅
Track / Conceive **modes**, sexual-activity logging + "Period ended" toggle, ovulation
calendar marker + qualitative **fertility band** (never a number), combined
calendar+entry (bottom-sheet redesign — see `CLAUDE.md`), extended doctor PDF.

### Phase 3 — v3 feature-universe build ✅ (where we've just been)
Driven by a ~300-feature audit + a 3-seat council (Product / Safety / Feasibility).
All migration-free except pregnancy:
- **Phase-0 privacy fixes:** `allowBackup="false"`, calendar disclaimer, paywall-copy
  honesty, sex-data declared in privacy policy.
- **Expanded logging** (cats 4–8) — symptoms/discharge(`cm_`)/vaginal(`vag_`)/sexual-
  health(`shx_`)/lifestyle(`habit_`) + numeric metrics, all in the day-tags JSON.
- **Medication / birth-control tracking** (dormant `Medications` table) + reminders.
- **PCOS / endo / PMDD nudges** — non-scored, non-diagnostic, confidence-gated.
- **Custom reminders** (dormant `Reminders.title`/`recurrence` + `ReminderType.custom`).
- **Symptothermal fertility** — BBT input + `fl_chart` chart, cervical-mucus scale,
  OPK/LH logging, thermal-shift observation, **and OPK→confidence corroboration**
  (`OvulationSignalService` → `PredictionResult.fertilityConfidence`).
- **Pregnancy mode** — the app's **first DB migration** (`schemaVersion` 1→2, adds
  `pregnancyStartDate`), Naegele EDD, loss-safe one-tap exit.
- **Perimenopause mode** — one lever (`capConfidenceToLow`) self-suppresses fertility.
- **Health Connect / HealthKit** BBT import (on-device OS API, not a backend).
- **Home-screen widget** (Android native complete; iOS documented).
- **i18n infrastructure** (flutter_localizations + ARB; English only; bulk sweep
  deferred — see [Deferred](#deferred--rejected)).
- **Encryption prepped** (build hook wired; flag still OFF — see Phase 4).

### ▶ Phase 4 — NEXT (start here)

Ordered by leverage. Items 1–5 are pure Dart / on-device (no accounts needed); item 8
needs the owner's store accounts.

| # | Task | Effort | Why now |
|---|------|--------|---------|
| 1 | **Encryption ON** — flip `kDatabaseEncryptionEnabled` in `lib/db/connection.dart`, `flutter run` on a device, confirm `databaseIsEncryptedAtRest()` == true, then declare encryption in `PRIVACY_POLICY.md` + Play Data Safety. | S (user-verify) | The named unblocker. Sensitive data (sex/pregnancy/lab) shouldn't ship at-rest-plaintext. App is unpublished → no rekey needed (encrypted build uses a fresh `lunatrack_enc.db`). |
| 2 | ✅ **DONE — On-device insights narratives** (`InsightsNarrator`): cycle/period trends, regularity, phase, symptom↔phase correlation → Insights section + Home highlight + doctor-PDF "Cycle patterns". Pure Dart, 20 new tests. | — | Council's #1 value pick. Shipped. |
| 3 | **Local backup / restore** — encrypted file export/import the user controls (dormant `AppSettings.lastBackup`). **No cloud** (breaks thesis). | M (+1 file/share dep — ask first) | Most-requested "backup" desire at $0 infra. |
| 4 | **`AD_ID` permission strip** — `<uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove"/>` (app uses non-personalized ads). Verify with an APK build. | XS | Cheap trust/hardening; the ad-ID perm is a mismatch for non-personalized ads. |
| 5 | **Conceive-Home thermal-shift echo** (optional) — surface `BbtService.thermalShift` retrospectively on Conceive Home (already in Insights). Safety-sensitive copy → own test. | S | Deferred sub-item from the symptothermal work. |
| 6 | **i18n bulk sweep** (~150 strings / 14 files) — deferred until a real 2nd language is on the table. Concrete resume map in [Deferred](#deferred--rejected). | L | Zero user-visible change; pure infra debt. |
| 7 | **First-migration batching** (Phase C) — when a typed column genuinely beats JSON (weight, first-class cervical-mucus), do ONE `2→3` `onUpgrade` adding all anticipated columns; test against a real v2 DB on device. | M | Only run untested upgrade code once, deliberately. |
| 8 | **Store submission** (needs owner accounts) — real upload keystore, real AdMob app+unit IDs (flip `AdConfig.useTestAds`), real Play IAP `lunatrack_premium`, host `PRIVACY_POLICY.md` at a URL, Data Safety + content-rating forms. | — | Ship it. |

### Deferred / rejected

- **Permanently rejected on thesis grounds** (need a server → break "$0 + can't see
  your data"): cloud AI chat assistant, cloud backup / multi-device sync, partner mode,
  telemedicine, community forum. Council ruling is documented and unanimous.
- **Vetoed (safety):** LH-strip auto-interpretation (medical-device fn — manual photo
  diary only), medication-interaction alerts (Apple 1.4.1 licensed-data), any
  conception-**%** (false precision → "safe day" hazard).
- **i18n bulk sweep — resume map:** (a) mechanical, agent-safe screens: reminders(19),
  medications(17), onboarding(10), home(10), premium(6), calendar(5), forecast(3),
  lock(4), setup_lock(4), day_log(2); (b) hand-only safety copy:
  `pregnancy_screen`(9), `insights_screen`(9)+nudges, `pdf_report_service`(8); (c)
  thorny design-refactor: `catalog.dart` labels are `const` English with no
  `BuildContext` (`symptomLabel(key)` feeds the PDF) → needs a key→l10n redesign at the
  widget layer, not a swap. ARB is owned centrally in `lib/l10n/app_en.arb`.

---

## Architecture cheat-sheet (authoritative version: `CLAUDE.md`)

```
lib/
  db/            drift DB + connection (encryption seam'd — flag OFF)
  data/          repositories (DailyLog, Settings, Medication, Reminder)
  models/        enums + hand-written models (prediction, cycle, insights, medication)
  providers/     ChangeNotifier state (Log, Settings, Premium, Reminder, Medication)
  services/      pure logic (Prediction, Cycle, Insights, Bbt, OvulationSignal,
                 Pregnancy, HealthImport, HomeWidget, Pdf, Ad, Notification, Lock, Iap)
  screens/       home / calendar / forecast / insights / settings / log / onboarding
                 / medications / pregnancy / reminders / premium
  widgets/       DayEntryForm, AdBanner, disclaimer_banner, home_widget_sync
  common/        catalog (day-tags JSON model), date_utils, l10n, collection helpers
  l10n/          app_en.arb + generated app_localizations.dart
```

**Predictions** are wired reactively in `main.dart` via `ProxyProvider2`
(`LogProvider` + `SettingsProvider` → `PredictionResult` → future periods).

### Non-obvious decisions (why the code is the way it is)

- **Two confidences, deliberately split.** `PredictionResult.confidence` gates the
  next-period chip; `.fertilityConfidence` gates the fertility band + ovulation marker.
  A corroborating OPK raises **only** `fertilityConfidence`, one notch, and never while
  perimenopause caps — so it can't overstate next-period precision or manufacture a
  "safe" day. (`OvulationSignalService`, `PredictionService.predict(logs:)`.)
- **Cycles are derived, not stored.** `CycleCalculator` groups consecutive bleeding
  days (1-day gap tolerance). `PeriodEntries` exists but is intentionally unused.
- **"Period ended" = write `flow = FlowIntensity.none`** for that day (not a separate
  table).
- **Everything trackable lives in the `symptoms` TEXT column as day-tags JSON**
  (`{key:true}` + numeric keys), namespaced (`sex_`/`cm_`/`vag_`/`shx_`/`habit_`).
  Reserved prefixes are excluded from `decodeSymptoms` → kept out of the doctor PDF.
  This is why most features were **migration-free**.
- **DB encryption is a build hook** (`sqlite3mc` via `pubspec` `hooks.user_defines`)
  that only compiles on a real device. In-memory test DBs never exercise the cipher —
  hence the mandatory on-device `databaseIsEncryptedAtRest()` check.
- **Merged-manifest ground truth:** the shipped release perms include `INTERNET`,
  ad/attribution perms, `BILLING`, `health.READ_BODY_TEMPERATURE`, notifications,
  biometrics. INTERNET comes from ads/IAP, not our code. (See the bright-line note
  above.)

---

## Store-submission checklist (needs the owner's accounts)

- [ ] Real upload keystore (release is debug-signed today).
- [ ] Real AdMob app + unit IDs — flip `AdConfig.useTestAds`, fill `_prod*` + manifest
      `APPLICATION_ID` (currently Google **test** IDs).
- [ ] Real Play in-app product id for Premium (`lunatrack_premium`).
- [ ] **Encryption ON + device-verified** before sex/pregnancy data ships (Phase 4 #1).
- [ ] Host `PRIVACY_POLICY.md` at a URL; declare sexual-activity (+ pregnancy) data in
      Play Data Safety / Apple label; confirm auto-backup uploads no plaintext DB.
- [ ] iOS later: `PrivacyInfo.xcprivacy`, real bundle id, HealthKit entitlement, the
      WidgetKit target (source in `WIDGET_INTEGRATION.md`).

---

## Appendix — session memory folded in (lost on clone otherwise)

> Verbatim from `../.remember/` (which sits **above** the git root). Kept here so the
> narrative history survives a clone. Timestamps are session-local.

### `now.md`
```
## 05:52 — Shipped 6 LunaTrack v2 features (Sex/modes/ovulation/band/calendar-entry/PDF);
found + fixed critical inline-entry bug (lazy ListView never built panel) via bottom-sheet
redesign + regression test; 45 tests green; pushed GitHub w/ CLAUDE.md context.
## 05:54 — Audited 300 features w/ council (AI on-device only); Phase A shipped
(logging/meds/nudges/reminders/BBT) + pregnancy (1st migration) + perimenopause + Health
import + home widget; l10n complete; 105/105 tests, device-verified.
```

### `recent.md`
```
## 2026-07-04 — Built 6 LunaTrack features (Track/Conceive modes, Sex/Period-ended logging,
calendar, ovulation marker, fertility band, PDF export); 45/45 tests; device flows verified;
calendar rendering regression fixed.
## 2026-07-06 — LunaTrack code-complete; feature audit vs 25-category catalog planned.
```

### `today-2026-07-07.md`
```
- Council (prod/safety/feasibility): AI on-device-only, reject cloud; prioritize
  symptothermal-fertility, widget, meds, Health-Connect-import, i18n; gaps: plaintext-DB
  cloud-backup, missing INTERNET-perm reasoning (later corrected: merged manifest DOES have
  INTERNET from ads).
- Phase-0 privacy deployed (allowBackup=false, disclaimer, paywall, policy); 46/46 tests.
- Phase A: logging (21+8 symptoms), med/BC tracking, PCOS/endo/PMDD nudges, custom reminders,
  BBT; TDD.
- Pregnancy (schema 1→2), i18n infra (Settings exemplar; ~150 strings deferred).
- Shipped: Perimenopause (fertility-cap), BBT-import (Dart/minSdk26), home-widget (Android);
  89→105→123 tests; health v13.3.1, home_widget v0.9.3; $0/on-device maintained.
- Symptothermal completed: OPK→fertilityConfidence corroboration (123/123).
```

### Where the full plan lives (not in the repo)
The complete feature-universe audit + council rulings + build sequence was authored at
`~/.claude/plans/tender-growing-kahan.md` on the build machine. Its load-bearing
content — the backend line, the AI on-device-only ruling, the safety-sensitive feature
rulings, and the build sequence — is summarized in the [Roadmap](#roadmap--phase-history--whats-next)
and [Deferred / rejected](#deferred--rejected) sections above.
```
