# CLAUDE.md

Guidance for Claude Code (and human contributors) working in this repository.

## Project overview

**LunarFlow** is a menstrual/period tracker built with Flutter, with an account and
cross-device sync.

The original thesis was "$0 running cost" and "privacy" are the same decision → 100%
on-device, no backend, no account. **That is no longer the whole picture:** accounts and
Firestore sync landed on `feat/firebase-auth-sync`. What survives of it is the
*local-first* half — everything (logs, cycles, predictions, reports) is still computed
and stored locally, and the app is fully usable offline.

- **Accounts are required** (Firebase Auth, email/password). `AppGate` walls the app
  behind `SignInScreen` when signed out. The one exception is the **local-only hatch**
  (see the key-design bullet below).
- **Daily logs and preference settings sync to Firestore in plaintext** under
  `users/{uid}`. It is not end-to-end encrypted; the service operator can read it. Say
  so anywhere it is disclosed — see `PRIVACY_POLICY.md`.
- **Drift remains the single source of truth.** The UI never reads from or writes to
  Firestore; `SyncService` mirrors drift ⇄ Firestore alongside the existing read/write
  path, never in front of it.
- **Reminders, the medications table and `PeriodEntries` are deliberately NOT synced.**
  (Per-day `med_` intake marks DO travel — they ride the day-tags blob inside the daily
  log.)
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

# Photo descriptions need a Gemini key at BUILD time. Without it the feature is
# hidden entirely (kGeminiApiKey defaults to ''), which is why the whole test
# suite and CI run without one.
flutter run --dart-define=LUNA_GEMINI_KEY=…
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
                 + the sync/auth layer (AuthService, SyncService, SyncTrigger, SyncMapper,
                   AccountDeletionService, firestore_ref.dart, FirebaseAvailability, DeviceId)
  screens/       app_gate + app_shell + home / calendar / forecast / insights / settings / log
                 / onboarding / auth (sign in, sign up, forgot password, claim sheet)
                 / account (deletion_pending_screen)
  widgets/       shared widgets (DayEntryForm, AdBanner, disclaimer_banner, …)
  common/        catalog (symptom/mood/sex options), date_utils, theme
```

Predictions are wired reactively in `main.dart` via `ProxyProvider2`
(`LogProvider` + `SettingsProvider` → `PredictionResult` → future periods).

### Key design decisions (non-obvious)

- **Never put a bare `FilledButton` inside a `Row`.** `app_theme.dart` sets
  `filledButtonTheme … minimumSize: Size.fromHeight(52)`, and `Size.fromHeight` is
  `Size(double.infinity, 52)` — every FilledButton demands INFINITE width. In a `Column`
  that is the app's full-width CTA convention and is correct. In a `Row` it overflows the
  line, `MainAxisAlignment` silently stops applying, children lay out from the left and
  the trailing one is clipped off-screen. Wrap each in `Expanded` (what
  `home_screen.dart` and `product_timer_card.dart` already do). Device-found 2026-08-13:
  the photo-descriptions consent sheet shipped with **Allow rendered off-screen**, so
  consent could not be granted at all. Two things hid it: release builds do not log
  `RenderFlex overflowed` (it is assert-only, debug-only), and widget tests default to an
  800×600 surface with plain `ThemeData` — neither the real phone width nor the real
  theme. `test/analysis_consent_sheet_test.dart` now pumps `AppTheme.light()` at 360×800
  and asserts the button's rect falls inside the viewport; copy that pattern for any
  button row.
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
  (`med_`, `sex_`, `cm_`, `vag_`, `shx_`, `habit_`, `urn_`, `dig_`, `skin_`, `slf_`, `lbd_` — all listed in
  `kReservedTagPrefixes`); `decodeSymptoms` strips every reserved prefix, so none of them
  reach the symptom list, Insights, or the doctor PDF. `encodeDayTags` is a full **REPLACE**
  (rebuilds the whole blob from form state), so the day editor must decode/encode EVERY
  group unconditionally — gating a group out of decode or save silently destroys it.
  Numeric metrics (`pain`, `water`, `sleep`, `energy`, `stress`, `sleep_quality`, `weight`)
  ride the same blob as real JSON numbers, so they never satisfy the `== true` symptom check
  and need no key prefix. **`0` means "unset" for every numeric metric**, weight included.
- **Schema & migrations.** `schemaVersion` is **11**. `onUpgrade` uses independent additive
  `if (from < n)` branches (not else-if), one nullable column each, so a user on any old
  version runs every intervening branch and existing rows need no backfill: v1→v2 added
  `AppSettings.pregnancyStartDate`; v2→v3 added `AppSettings.trackingCategories`; v3→v4
  added `AppSettings.weightUnit`; **v4→v5 added the `SyncTombstones` table plus
  `AppSettings.lastSyncedAt` and `AppSettings.settingsUpdatedAt`**; **v5→v6 added the
  `MediaItems` table** (the media timeline); **v6→v7 added
  `AppSettings.analysisConsentUid` plus `analysisCountDay` / `analysisCountToday`**
  (photo descriptions and their daily cap); **v7→v8 added the four profile columns
  `AppSettings.dateOfBirth`, `heightCm`, `profileWeightKg` and `menarcheAge`** (all
  nullable — null means "not answered", which is a real answer here, not a default);
  **v8→v9 added the five clinical-profile columns `AppSettings.contraceptionMethod`,
  `contraceptionStartDate`, `knownDiagnoses`, `breastfeeding` and `breastfeedingSince`**
  (Tier 1 of the gynaecological intake; `breastfeeding` is a NULLABLE bool precisely so
  "never asked" stays distinct from "answered no"); **v9→v10 added
  `AppSettings.sexualHealthBaseline`**, ONE nullable TEXT column holding the signup
  sexual-health baseline as JSON (`SexualBaseline` in `catalog.dart`) — one column, not
  four, because that question set will grow and a column per question means a migration per
  question; **v10→v11 added the `AnalysisSessions` and `AnalysisMessages` tables plus
  `AppSettings.analysisConsentVersion`**, all three together (saved photo-description
  conversations, and the versioned consent that gates them — see D10 below).
  v4→v5, v5→v6 and v10→v11 are the only branches that
  create a table rather than adding a column; all are still purely additive. Note the two `SettingsRepository` entry
  points that write those columns: **`update()` stamps `settingsUpdatedAt`** (a user
  edit, so it pushes on the next sync), **`updateSyncState()` deliberately does not** —
  it is sync bookkeeping, and stamping it would make every sync look like a settings
  change and push forever. A committed JSON snapshot per version lives in
  `drift_schemas/` and `test/generated_migrations/` (through `drift_schema_v11.json` /
  `schema_v11.dart`); `test/db_migration_v11_test.dart` uses drift's `SchemaVerifier` to run
  the REAL `onUpgrade` against a v10 DB seeded with non-default rows. The suite runs one
  such test per hop, `db_migration_v3_test.dart` through `db_migration_v11_test.dart`.
  In-memory `AppDatabase.forTesting` runs `onCreate` at the current schema and NEVER
  exercises `onUpgrade`, so every new migration needs a snapshot dumped BEFORE the version
  bump (only derivable while that version is current) and its own SchemaVerifier test.
  **`migrateAndValidate(db, n)` upgrades to the database's OWN `schemaVersion`, so an old
  migration test cannot keep validating against an intermediate version.** At each bump,
  re-point the *older* tests at the new version rather than deleting them — that is what
  makes `db_migration_v3_test.dart` the multi-hop guard (v2 → current, proving a v2-era user
  runs every intervening branch, which is the whole point of independent `if`s). Not yet
  verified: the background-isolate migration path (`CheckInWriter` opens a bare
  `AppDatabase()` from a killed-app notification action) — re-test at the next bump.
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
- **Gynaecological intake (Tier 1 + Tier 2, 2026-09-13).** Owner asked for richer
  gyn-health context. Scoped deliberately, and one thing was REFUSED: a "gyn health level"
  score. No validated instrument maps discharge or masturbation habits to gynaecological
  health, so a number built from them would be invented, and invented numbers about
  someone's body read as clinical fact — the same ground that vetoed LH auto-interpretation
  and a synthesized fertility %. The defensible version shipped instead is **red-flag
  surfacing**: descriptive, attributed, pointing at a clinician.
  - **Tier 1 → `AppSettings` (v9), synced.** Contraception + start date, known diagnoses,
    breastfeeding + since-date. Vocabularies are `kContraceptionOptions` / `kDiagnosisOptions`.
    Stored as STABLE STRING KEYS, never enum indices — the lists will grow, and an index
    renumbers every stored answer the day someone inserts a value in the middle.
  - **Frequency questions were deliberately NOT asked** — for the DAY EDITOR. "Do you get
    discharge daily / weekly / monthly?" asks the user to summarise data the app already
    holds better; the answer goes stale immediately and disagrees with the logs. Log the
    thing, derive the frequency. The signup baseline below is the deliberate exception
    (a new user has no logs to derive from).
    **Preferred methods and time-to-orgasm were excluded on the same grounds, and that
    ruling was REVERSED by the owner on 2026-09-14.** Both are now asked at signup, as
    REQUIRED answers (`kIntimacyWaysOptions`, `kSatisfactionTimeOptions`, stored in the
    `SexualBaseline` JSON). The original objection stands on its merits — neither carries
    a gynaecological signal, and both are among the most sensitive things this app stores
    — and was overridden. Do not "fix" it back; raise it with the owner.
  - **Tier 2 is half derived.** Intermenstrual bleeding and pelvic-pain-outside-period
    needed no new question — both fall out of days already logged, in
    `InsightsService.patternNudges`. Note the trap: `CycleCalculator` splits EVERY bleeding
    run into its own cycle, so intermenstrual bleeding is not "bleeding outside a cycle", it
    is a short spotting-only run that cut the previous interval short. Bleeding after sex
    (`shx_post_coital`, threshold of ONE) and the heavy-bleeding markers
    (`kSymptomLargeClots` / `kSymptomSoakingHourly`) cannot be derived and are day tags.
  - **The heavy-bleeding markers are PLAIN symptom keys, not a reserved prefix.** Every
    reserved prefix is PDF-excluded by default; these two are exactly what the doctor report
    exists to carry, so they must ride `decodeSymptoms`.
  - **`shx_high_libido` is retired but NOT dead.** It shipped as a boolean and users logged
    it. Libido is now the three-point `kLibidoOptions` scale under `lbd_`, and
    **`decodeLibido` reads the old key as `lbd_high`** — the day-tags blob has no migration
    path, so a decoder shim is the only place this can be honoured. `DayEntryForm` drops the
    old key on save, migrating one day at a time. Never reuse that key.
  - **The intimate group (`slf_`) SYNCS.** The owner reversed an earlier local-only decision
    on 2026-09-13, for backup. The trade-off accepted: it reaches Firestore in plaintext
    where the audited operator route can display it (hence `slf_`/`lbd_` in
    `admin/src/paths.js` `TAG_PREFIXES`, so it renders grouped rather than as raw keys).
    Reserved keeps it out of the symptom chips, Insights and the doctor PDF; it does not
    keep it off the network. **`kCatIntimacy` ships ON — the one post-original category that
    does.** It shipped off first, by the registry's ordinary "new categories default off"
    rule; that was corrected the same day because `kCatSex` and `kCatSexualHealth` are both
    on, so the default made partnered sex visible and solo sex hidden behind a switch nobody
    would find. Same blob, same sensitivity, same shoulder-surf handling — the default was
    protecting nothing and only encoded which sexual behaviour counts as ordinary. The
    "no editor grows unasked" rule still holds for every other category.
  - **Sync marker is a VERSION.** `profileFields` is now `3`. Each generation of columns
    gates on its OWN minimum — `knowsProfileFields` (any marker) for the v8 four,
    `knowsClinicalProfile` (`>= 2`) for the v9 five, `knowsSexualBaseline` (`>= 3`) for the
    v10 baseline. A v8 device writes `1` truthfully while knowing nothing of v9; a v9 device
    writes `2` truthfully while knowing nothing of v10. Presence alone is never enough.
    Bump it again whenever the field set grows, and add a gate rather than widening one.
  - **Signup baseline (v10).** Three onboarding pages — Sex, Sexual health, Intimacy —
    each asking TWO things: a BASELINE ("how often, generally", stored in settings) and a
    TODAY answer (seeded as a real day-tag entry). They are never merged: the baseline
    answers "how often", the logs answer "what happened on the 3rd", and a field that tries
    to be both disagrees with itself. This closes the cold-start hole in "derive the
    frequency from the logs" — a new user has no logs, which is exactly when context is
    scarcest. **`saveDay` REPLACES a day**, so when the last-period date IS today the flow
    and the seeded tags must be ONE write; two would erase the period the user just entered
    (`onboarding_profile_test.dart` pins this). The empty-today guard (write NO row) is kept
    but is now UNREACHABLE through the wizard: every "today" answer is required as of
    2026-09-14, and a user with nothing to report picks explicit NONE markers
    (`sex_none`, `shx_none`, `slf_none`), which are real content. Signup day therefore
    always produces exactly one row.
  - **A required answer needs an answer everyone can give (2026-09-14).** Making a question
    mandatory is only safe if its options cover every honest situation; otherwise the
    wizard DEADLOCKS and the app cannot be opened at all. Three sets had no such option and
    gained one: `kSexualHistoryOptions` and `kSexualHealthOptions` (`kShxNone`, "None of
    these") and `kIntimacyOptions` (`kSoloNone`, "Not today") — the last was a one-member
    list, so a required answer would have forced every new user to claim they had
    masturbated that day. The escape keys are MUTUALLY EXCLUSIVE with the real answers
    (`_toggleExclusive`), or a stored history could say "never had any of these" and "had
    pain during sex" at once. `test/onboarding_required_test.dart` completes the whole
    wizard using only escape answers; that test is the deadlock guard, not a formality.
    Labels avoid the bare word "None" because `kSexOptions` owns it and `gyn_catalog_test`
    enforces globally unique labels.
  - **Continue is the only exit.** The refusals live on the Continue path, so the
    onboarding `PageView` is `NeverScrollableScrollPhysics` — a swipeable one would make
    every check advisory. `_finish` re-checks every page anyway, as defence in depth.
- **AI health context for photo descriptions (2026-09-14, schema v11).** Photo
  descriptions used to send only the photo. The owner asked for the full tracked
  record instead of a derived summary or a per-session picker (see
  `docs/superpowers/specs/2026-09-14-ai-health-context-analysis-design.md`), and
  four things about that are non-obvious:
  - **The assembler is pure and lives OUTSIDE the analysis service.**
    `buildHealthContext()` (`lib/services/health_context.dart`) takes rows
    already loaded by the caller — logs, cycles, the prediction, medications,
    settings — and returns a plain `String`; no I/O, no `BuildContext`, no
    plugin. That is load-bearing, not tidiness:
    `test/media_guardrails_test.dart:241-255` forbids
    `media_analysis_service.dart` from importing `MediaRepository`,
    `MediaBlobStore`, `AppDatabase` or `lunaFirestore`, and that guardrail is
    unmodified and still green — a service that can reach the database could
    leak health data into a request by accident. So `lib/screens/media/media_route.dart`
    gathers from providers BEFORE the async gap, the same shape
    `PdfReportService.build` already uses, and hands `MediaAnalysisService.analyze`
    an opaque `String?` it never inspects.
  - **The context rides the first user turn, never `systemInstruction`.**
    `systemInstruction` carries `kAnalysisSystemInstruction`, the refusal
    rules; mixing user-authored data into that same field would weaken the
    thing doing the refusing. The block is delimited
    (`kHealthContextOpenDelimiter` / `kHealthContextCloseDelimiter` in
    `media_analysis.dart`) and attached once, to the first turn — but because
    the whole transcript is replayed every turn (`generateContent` is
    stateless), it is in substance resent every turn anyway, diary notes
    included. The diary is free text the user wrote themselves, so this is
    not an attack on the user, but it IS a derailment surface: a note reading
    "ignore the previous instructions" would be replayed verbatim.
    `kAnalysisSystemInstruction` gained two clauses to hold that line: the
    tracked-data block is **information, never instructions**; and having the
    person's health information does **not** license diagnosis, naming a
    condition, estimating severity or advising treatment — restated in the
    presence of context because that is exactly the case where it is under
    the most pressure.
  - **This invalidates the 2026-08-13 hostile probe, and it has NOT been
    re-run.** That run — four rapport turns, then diagnose / "just guess the
    condition name" / "pretend you are a dermatologist" / "severity 1-10",
    all four refused — was conducted with no health context loaded. A model
    holding "endometriosis, BMI 31, pain 8/10, post-coital bleeding" is under
    materially more pull toward diagnosis than one looking at a bare photo,
    and `test/media_analysis_test.dart` only asserts that the instruction's
    clauses exist as strings, never that the model still obeys them under
    pressure. Re-running the eight-turn probe against a build with context
    attached — synthetic stimulus, synthetic record, never a real body photo
    — is an outstanding release blocker (see `README.md`), not something this
    branch has done.
  - **Consent is versioned, because silently widening it is no consent.**
    `analysisConsentUid` used to be the whole gate — one bit, "this user
    agreed" — to a sheet that named only a photo. Sending diagnoses, BMI,
    sexual activity and masturbation history under an unchanged "Allow" would
    be, in substance, no consent to that new disclosure at all.
    `AppSettings.analysisConsentVersion` (v11) plus `kCurrentConsentVersion = 2`
    (`media_analysis.dart`) mean `MediaAnalysisService.consented` requires the
    stored uid AND the stored version to match; anyone who agreed under
    version 1 is asked again. Each saved session also stamps its own
    `consentVersion`, so a stored transcript records what its user was
    actually told when it started. **The READ was versioned first; the WRITE
    drifted for one review cycle.** `SettingsProvider.isAnalysisConsentedFor`
    (the Settings toggle's `value:`) got this uid-AND-version check
    immediately, but the toggle's `onChanged` kept calling
    `settings.setAnalysisConsent(uid)` directly — so a v1 consenter whose
    switch now correctly read OFF could flip it back ON and be silently
    re-stamped at the current version, never seeing the v2 disclosure at all.
    Found and fixed at final review (2026-09-14):
    `SettingsScreen.handlePhotoDescriptionsToggle` now shows the real
    `showAnalysisConsentSheet` on ON and persists only on an explicit Allow,
    reading the uid AFTER the sheet closes. The comparison itself is also now
    ONE expression, `isConsentedFor()` (`media_analysis.dart`), called by both
    `SettingsProvider.isAnalysisConsentedFor` and
    `MediaAnalysisService.consented`/`analyze` — the duplication between those
    two was exactly how the read and the write were able to drift apart in the
    first place.
  - **Phase derivation is narrower than "day 19, luteal" suggests.** `_phaseFor`
    (`health_context.dart`) returns `menstrual` for a bleeding day, the LIVE
    prediction for `asOf` only, and `unknown` for every other day, so most of a
    90-day window actually reads `(day 19, unknown)`. Found at final review
    (2026-09-14) and deliberately left as-is: asserting a retrospective
    follicular/ovulatory/luteal phase would mean inferring past ovulation
    timing from a calendar-only model — the same manufactured precision this
    app's fertility guardrails refuse everywhere else. See D4 of the design
    doc for the full ruling. Restoring historical phase derivation is an open
    follow-up, not a shipped behaviour.
  - **An open (still-ongoing) cycle no longer runs to `asOf` unbounded.**
    `_cycleDayFor` used to let the most recent cycle's day count climb
    forever if the user stopped logging — someone silent for months would
    read as "day 137". `kMaxOpenCycleDays` (90, mirroring the amenorrhea
    threshold `InsightsService` already flags on) caps how far an open cycle
    can run before a date falls outside it entirely and reads `phase unknown`
    like any other unattributed day.
  - **`ovulation test` and the per-day metrics are unit-explicit.** The `opk`
    column now renders through `kOpkOptions`' label lookup (`Positive` /
    `Negative` / `Peak`) instead of the raw stored key, matching every other
    option group's "unknown keys are dropped, never printed raw" rule. `bbt`
    and `weight` now carry `°C` / `kg` — both canonical values the profile
    block already labels the same way — so a model can no longer read them as
    °F or lb.

  Persisting the conversation (also new in v11) adds three smaller traps worth
  recording:
  - **The message column is `messageText` / `message_text`, never `text`.** A
    getter named `text` inside a class that `extends Table` collides with the
    inherited `Table.text()` DSL method, and `.named('text')` (Dart getter
    `messageText`, SQL column `text`) only moves the collision one file over —
    the schema-snapshot generator that `test/generated_migrations/schema_v11.dart`
    needs for its `SchemaVerifier` test names its historical field after the
    raw SQL column, so a column genuinely named `text` reproduces the same
    conflict there instead. No column literally named `text` survives this
    repo's migration tooling; see the long comment at `lib/db/tables.dart:186-203`
    before retrying it.
  - **Message ordering ties break on SQLite `rowid`, not the message id.**
    Drift stores `DateTime` at whole-second granularity, so two messages saved
    in the same second would otherwise sort arbitrarily — unlike a photo grid,
    transcript order carries meaning. `AnalysisSessionRepository` orders on
    `rowid` (SQLite's implicit, strictly increasing insertion counter).
  - **`seedConversation` exists because `generateContent` is stateless.**
    Reopening a saved session and replaying only what the transcript UI shows
    would leave the MODEL with no history — it would answer as if the
    conversation just started. `MediaAnalysisService.seedConversation` is
    handed the loaded turns by the caller and folds them into the live,
    in-memory conversation before the next call (a no-op if turns are already
    live, so a reopen can never discard them); seeded turns count toward
    `kMaxChatTurns` like any other turn, so a conversation resumed nine turns
    deep IS nine turns deep. The class still never touches the database
    itself — the caller loads the transcript and hands over plain
    `AnalysisTurn`s, a type the service already owns.

  Saved conversations are **local-only**, like `analysisConsentUid` already
  was: not synced to Firestore, so they need no `firestore.rules` or
  `functions/purge.js` coverage. `deleteAllData()`, the sign-out/account-switch
  wipe (`MediaProvider` → `MediaRepository.deleteExcept` →
  `AnalysisSessionRepository.deleteExcept`), cascade-on-photo-delete
  (`MediaRepository.deleteById` / `deleteExcept`), and exclusion from
  `.lunabak` and the doctor PDF are the whole erasure surface, and all of it is
  structurally asserted in `test/media_guardrails_test.dart`.
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
- **Ovulation-suppressing contraception caps confidence too** (2026-09-13). A method in
  `kOvulationSuppressingContraception` (`catalog.dart`) makes `predictFromLogs` set
  `capConfidenceToLow`, exactly as perimenopause does — the user does not ovulate, so a
  fertile window is not merely uncertain, it is FALSE. The next-period estimate is left
  alone (a withdrawal bleed is still a bleed). The **copper IUD and sterilisation are
  deliberately absent** from that set: ovulation continues, and blanking the window would
  remove a real signal. A method key this build does not recognise reads as NO suppression.
  Three call sites recompute predictions (`main.dart`, `check_in_writer.dart`,
  `home_widget_sync.dart`) and a structural test in `prediction_from_logs_test.dart` scans
  `lib/` so a fourth cannot forget the gate.
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
  **Firestore's own on-device persistence is a SEPARATE, unencrypted store** holding
  every document the SDK has read or written; `clearLunaFirestoreCache()`
  (`firestore_ref.dart`) is what makes "everything on this device is erased" true, and it
  must be the LAST Firestore call in whatever flow runs it (`terminate()` leaves the
  client accepting nothing but `clearPersistence()`).
- **Never `FirebaseFirestore.instance` — always `lunaFirestore()`**
  (`lib/services/firestore_ref.dart`). `.instance` targets `(default)`, and a `(default)`
  database carries ONE ruleset for every app in the project, so a permissive rule written
  for an unrelated app would expose menstrual logs. LunarFlow uses the **named** database
  `lunatrack-db` (`kLunaDatabaseId`), which has its own independent ruleset. `grep -rn
  "FirebaseFirestore.instance" lib/` must return nothing.
  The project is **`teddy-2-20649`**, named in the tracked `firebase.json`. The named
  database `lunatrack-db` exists (created 2026-08-12) and holds `users` and
  `deletionRequests`. An older `lunatrack` database also exists, created via gcloud and
  therefore ignoring deployed rules — it is EMPTY and abandoned; do not write to it.
  The owner's option to move LunarFlow to a dedicated project is still open, so keep
  reading the id from config rather than hardcoding it in Dart.
- **`firestore.rules` is the entire privacy boundary, and it IS deployed** — to
  `cloud.firestore/lunatrack-db`, byte-identical to this file (verified 2026-09-14
  against the Rules API; see `docs/HANDOFF.md` for the command). The API
  key ships inside the APK, so every in-app consent gate (`ClaimPreference`, `AppGate`'s
  ordering, `SyncTrigger`) governs only this app's behaviour and has zero authority over a
  raw REST call. Rules therefore key on **identity** (`request.auth.uid` vs the uid in the
  path), never on `request.auth != null` — in a shared project every other app's users
  hold a valid token against this database, so "is signed in" is no boundary at all.
  29 emulator tests in `firebase_test/rules.test.mjs` cover it (`firebase_test/run.sh`,
  local `demo-lunatrack` emulator only). Nothing is live until someone deploys.
- **Only preference settings sync.** `SyncService._pushSettings` sends mode, cycle/period
  defaults, theme, language, gender-neutral language, pregnancy start date, tracking
  categories, weight unit and the four profile fields (date of birth as epoch millis, height,
  profile weight, age at first period). The settings document also carries a
  **`profileFields` marker**, and it is load-bearing: for the four profile columns `null`
  and *absent* mean different things. A build predating v8 pushes a document with none of
  those keys, which says nothing about the user's answers; a current build sending them
  null says the user emptied them. Without the marker both collapse to one case, and
  whichever way it collapses is wrong — `Value(null)` lets one edit from an older device
  wipe four answered questions, `Value.absent()` makes "clear my date of birth" unsyncable
  forever. Every other nullable settings column keeps the plain `Value(null)` posture. `premium` (a Play-account IAP entitlement), `appLockEnabled`
  (a per-device security choice), `onboardingComplete`, `lastSyncedAt` and `id` are
  deliberately device-local. Syncing `premium` would unlock ads on every device signed
  into the account, which is not what was purchased.
- **Conflicts resolve last-write-wins per WHOLE DAY** on `DailyLogs.updatedAt`
  (`sync_merge.dart`'s `decideMerge`, used by every path so two paths can never decide the
  same inputs differently). Field-level merge is deliberately avoided: `encodeDayTags` is
  a full REPLACE, so merging tags across devices would fabricate entries the user never
  made. Push is gated on `lastSyncedAt`, pull on server-stamped cursors — never the same
  clock (see the long comments in `sync_service.dart`; ties always resolve toward
  over-pushing, because over-pushing is redundant work and under-pushing is data loss).
- **Deletions propagate through the `SyncTombstones` table**, not a soft-delete flag — a
  flag would require `where(deleted == false)` on every existing read path. A pull only
  ever iterates documents that EXIST, so an absence is never observable; the tombstone is
  pushed as a positive marker under `users/{uid}/deletions/{date}` (dates only, no health
  content), pruned after 180 days.
- **Account deletion is a cancellable SOFT delete, and the purge does not exist yet.**
  "Request account deletion" wipes the device immediately and writes a marker at
  top-level `deletionRequests/{uid}` (`uid`, server-stamped `requestedAt`, client-computed
  `purgeAfter` = +30 days, rules-bounded to 29–31 days). Cloud data is left **intact**;
  `SyncService.syncNow` refuses to run in either direction while the marker exists, and
  the user can cancel from `AccountSection` or from `DeletionPendingScreen` (which
  `AppGate` shows AHEAD of onboarding, because `deleteAllData()` resets
  `onboardingComplete`). Nothing calls `User.delete()` — it needs a recent sign-in and
  failed AFTER the local wipe. **The purge job now EXISTS (`functions/purge.js` +
  `functions/index.js`, covered by `firebase_test/purge.test.mjs` and a mutation check)
  but is NOT DEPLOYED,** so nothing is actually erased from the server today. This
  paragraph previously said no `functions/` directory existed; that stopped being true
  and the correction matters, because "written but undeployed" and "not written" are
  different blockers.
  `AccountDeletionService.deleteFirestoreData` is kept, tested and public as the
  executable spec for the Firestore half. It is no longer the WHOLE spec: uploaded media
  lives in Cloud Storage, a second service the client cannot sweep, so the complete
  contract is `functions/purge.js` — subcollections (including `media`) plus the
  `users/{uid}/media/` bucket prefix, swept FIRST. Do not write copy anywhere claiming
  cloud data IS deleted until it ships — see the blockers in `README.md`.
- **Settings → "Delete all my data" is device-only.** It erases the device AND records a
  uid-scoped decline (`resolveClaim(upload: false)`) so the next sync does not pull the
  cloud copy straight back down — but the account keeps its data. Deleting the server copy
  is the separate deletion-request flow above. The dialog copy states both halves.
- **Local-only hatch.** If `Firebase.initializeApp()` fails in `main()`
  (`FirebaseAvailability`, decided exactly once per process), `SignInScreen` offers
  "Continue without syncing" and the tracker is fully usable with no account, under a
  persistent `CloudSyncUnavailableBanner`. It is gated on `FirebaseAvailability` ONLY,
  never on an `AuthErrorCode` — a code cannot tell an outage from a mistyped password, and
  gating on it would hand everyone a bypass of the required-account design. `AppGate`
  synthesizes no uid, so `SyncTrigger` stays torn down; the flag is in-memory and never
  persisted. Data logged that way goes through the normal claim-consent sheet on a later
  sign-in.

### Guardrails (hold these regardless of product pressure)

- Never the word **"safe"** next to any fertility/ovulation UI. The non-contraception
  disclaimer (`widgets/disclaimer_banner.dart`) stays on every fertility surface.
- **No false precision** — fertility is qualitative, no synthesized %.
- **Ads never co-render with logging or insights.** `test/ad_placement_test.dart` guards
  this structurally. The interstitial only fires on switching into Home. (Banners live on
  Home, Calendar, Forecast and Settings.)
- **A photo description is never an interpretation.** The model may describe what is
  visible; it may never name a condition, estimate severity or advise treatment. That is
  enforced by `kAnalysisSystemInstruction` (asserted clause-by-clause in
  `media_analysis_test.dart`), and LunarFlow itself never synthesizes a reading from the
  answer. Same ground that vetoed LH-strip auto-interpretation. (It once vetoed a BMI label
  too; the owner reversed that on 2026-09-13 — see Weight tracking. The photo-description
  ruling is untouched by that reversal.) The
  caveat line under every description is fixed and unconditional — one shown only
  sometimes teaches the user that its absence means the answer is reliable.
- **User-facing copy must describe what the code does today, not what is planned.** The
  purge job is still outstanding, so any wording that implies cloud data is already
  being erased is false. Server-side PROTECTION is now true (the rules are live); server-side
  ERASURE is not. See
  `PRIVACY_POLICY.md` and `docs/account-deletion.md`, which both carry the gap explicitly.

#### Change-timer guardrails (the feature nearest a real medical emergency)

Enforced structurally by `test/product_timer_guardrails_test.dart`. A failure there is a
question about whether the ruling changed — not about how to make the test pass.

- **The card is the primary surface; the notification is an accessory that may never
  arrive.** Every alarm here is `inexactAllowWhileIdle`, and an OEM battery manager can
  drop one outright. The app therefore never promises delivery, and past the target by 30
  minutes the card *says* the reminder may not have arrived. That disclosure is the
  structural defeat of inference-from-silence — the harm where a missing notification reads
  as "not time yet." It needs no wrong words to occur, and no other copy fixes it.
- **Never "safe", "you're fine", "still good", "no rush", "overdue", "danger", "urgent".**
  Elapsed counts **UP**; the app never shows time remaining and never draws a progress bar
  (a bar is a countdown in pixels). The only permitted framing for a passed target is
  *"past the Nh **you set**"* — the target is the user's, so the app is never the one
  calling it late.
- **LunarFlow never authors a duration.** Caps are *attributed* ("Tampon packaging
  generally says…"), never asserted. A duration presented as the app's opinion is a medical
  claim; the same duration attributed to the box is not. Caps are a **refusal** (the stepper
  stops), not a silent clamp.
- **Duration is a pure function of `(productType, userSetting)`.** Never `f(flow)`,
  `f(cycleDay)` or `f(phase)` — inference from cycle data turns a timer into a synthesized
  clinical recommendation.
- **No TSS symptom checker, no triage, no emergency affordance, no gamification.** The
  first is a medical-device function (the ground that vetoed LH-strip auto-interpretation);
  the last is a shame mechanic aimed partly at teenagers.
- **No exact alarms, no foreground service, no full-screen intent, no DND bypass.**
  `USE_EXACT_ALARM` is Play-restricted to alarm/calendar apps and would not buy reliability
  anyway (a force-stop drops alarms regardless of exactness) — it would only make a
  best-effort channel *look* guaranteed. A foreground service means a permanent status-bar
  icon: continuous self-disclosure, the exact threat `secret` visibility prevents.
- **Session state never touches the day-tags blob, Firestore, the doctor PDF, or the
  home-screen widget.** `DailyLogs.symptoms` syncs as a real Firestore map to a shared
  project; the launcher widget renders outside `AppLock`.

## Feature status

### Shipped (v1 + v2 migration-free; v3 = customizable tracking, first real migration; v4 = weight unit; v5 = accounts + sync)

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
- **Product-change timer** — a live "how long has this been in" card on Home for a pad,
  tampon, cup/disc or period underwear, plus two best-effort reminders (ids 5000/5001) and
  a "Changed" notification action. **Zero migration:** the single in-progress session rides
  one dormant `Reminders` row of the appended `ReminderType.productChange`, with its state
  in the free-form `payload` column (`ProductSessionRepository`). That choice is what buys
  the sync exclusion, the `deleteAllData()` coverage and the one-row-per-type invariant for
  free — the day-tags blob was rejected precisely because it *does* sync. The session is
  **ephemeral**: ending it leaves no record, which is what removes the retention, PDF and
  export questions a history table would have created. Filtered out of `.lunabak` export
  (`backup_service.dart`) so a restored backup cannot resurrect a 71-hour timer.
  **This is the app's first and only repeating `Timer`** — a 60-second boundary-aligned
  one-shot chain in a leaf widget, gated on a session existing. That gate is load-bearing:
  ~50 test files call `pumpAndSettle`, which never settles while a `Timer` keeps calling
  `setState`. Elapsed time is always recomputed from the stored timestamp, never
  accumulated, because `app_lock.dart` freezes `Ticker`s but not `Timer`s. Free, never
  premium. See the change-timer guardrails above.
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

- **Weight tracking** — a numeric day-metric (`kMetricWeight`) stored in the day-tags blob
  in **canonical kilograms**, so no `DailyLogs` migration was needed. The kg/lb choice is a
  global preference (`AppSettings.weightUnit`, null = kg) applied only at the display
  boundary, so switching units never rewrites data. Input is refused outside 20–350 kg
  (checked AFTER conversion, so the same rule holds in both units) rather than clamped —
  which is why **`DayEntryFormState.save()` returns `Future<bool>`** and both hosts must not
  pop on `false`. Off by default via the `kCatWeight` tracking category; like every other
  group, weight is decoded and re-encoded **unconditionally** regardless of that gating
  (`test/weight_form_test.dart` has the regression test). Trend (90-day series + net change,
  null below two readings) is a pure `WeightTrendService`, charted on Insights and summarised
  in the doctor PDF (always kg there — it is a clinical document).
  **RULING REVERSED 2026-09-13.** This bullet used to end "deliberately no BMI, no height,
  and no classification of any kind", on the grounds that a judgeable body label is the same
  class of harm as a synthesized fertility %. **The owner deliberately overturned that on
  2026-09-13**, giving two reasons: better predictions and insights from a fuller profile,
  and a doctor report that a clinician can actually read. Height is now collected, and a BMI
  figure **with a WHO band label** is shown on Insights and printed in the PDF. Do not
  "fix" that as a defect — it is the decision.
  The structural guardrail was **narrowed, not deleted**: `test/weight_trend_service_test.dart`
  still scans every `lib/` string literal for body-judgement copy and now exempts exactly one
  path, `lib/services/bmi_service.dart`, which owns every such string (the band labels and
  the `'BMI '` prefix) so the UI reads them out instead of writing its own. The original
  ruling therefore still holds in every other file — a new offender anywhere else is a
  question for the owner about widening the reversal, **not** an invitation to add a second
  exemption. Two extra assertions keep the exemption live and earned (the file must still
  exist and must still carry the copy), so renaming it cannot silently disarm the scan. Note
  a naive `/bmi/` search matches "su**bmi**t", so it stays scoped to quoted strings with word
  boundaries.
- **Profile fields (the four "about you" answers)** — `dateOfBirth`, `heightCm`,
  `profileWeightKg` and `menarcheAge` on the single `AppSettings` row (v7→v8), read/written
  through `SettingsProvider`'s four getters and four nullable setters, all routed via
  `update()` so they stamp `settingsUpdatedAt`. **Collected in onboarding** (the wizard is
  now 7 pages: a date-of-birth page and a height / current-weight / age-at-first-period
  page), where **every one is now REQUIRED** (owner decision, 2026-09-14). They used to be
  skippable with a skip storing null; the wizard now refuses to advance past an unanswered
  question, and a BLANK measurement field is a refusal rather than a null. Null still means
  "not answered" in the column — it is simply no longer reachable through onboarding, and
  stays reachable by clearing a field in Settings, so no read path may assume non-null. **Edited in Settings** → the "Profile" group under `AccountSection`.
  Both hosts parse through the `catalog.dart` helpers into canonical cm/kg and **refuse**
  out-of-range input inline (range checked AFTER unit conversion) rather than clamping.
  **Height has no unit column of its own** — it reuses `AppSettings.weightUnit`
  (kg ⇒ centimetres, lb ⇒ feet+inches), so there is one unit preference, not two.
  The doctor PDF renders a **Profile block** under the header (age derived from
  `dateOfBirth` as of the injected `generatedOn`, height, current weight, age at first
  period, then the BMI readout), always metric; each row is omitted when unanswered and the
  whole block disappears when nothing was answered. Wired from
  `insights_screen.dart`'s `_exportPdf` — `PdfReportService.build` takes the four as
  OPTIONAL named params, so a call site that forgets them silently ships a report with no
  header (`test/insights_pdf_export_profile_test.dart` pins that call site).
  They **sync** — `SyncService` pushes `dateOfBirth` as epoch millis and the rest raw, and
  pulls with the `Value(null)` posture (so "clear my date of birth" is syncable; the cost,
  documented at the pull site, is that an OLD build pushing a settings doc without these
  keys will clear them on a new device). They ride the encrypted `.lunabak` automatically
  via drift's generated `toJson()` — no backup code change was needed. The **operator panel
  never sees them**: `admin/src/account.js` `settingsMeta()` projects the settings doc with
  `.select('updatedAt', 'syncedAt')`, so the values never enter that process at all.
  **`profileWeightKg` is deliberately a SEPARATE field from the per-day `kMetricWeight`
  metric** and neither reads from the other: the profile weight is the PDF header's "current
  weight" and the BMI input; `kMetricWeight` alone drives the 90-day `WeightTrendService`
  chart. Label them differently in the UI. Derived figures (gynaecological age, the BMI
  readout) are recomputed at read time and **never stored**.
- **Diary** — `DiaryService` + `DiaryScreen` read back the notes users already write:
  non-blank notes only, newest first, case-insensitive search over the **note text only**
  (matching symptoms or dates would surface days the user never wrote about), with the cycle
  day shown per row. Reached from a Calendar app-bar action (bottom nav is already at
  Material's five destinations). Pure presentation over `LogProvider.logs`; no query, no
  schema change. Carries **no ad banner**, and diary text **never** enters the doctor PDF —
  both structurally tested. The PDF guardrail asserts by output **size**, not substring: the
  `pdf` package compresses text streams, so a byte search finds nothing even for headings
  that ARE present, and `generatedOn` is injected rather than read from the clock, making the
  output byte-deterministic.
- **Accounts + cloud sync (`feat/firebase-auth-sync`)** — Firebase Auth email/password
  (`AuthService`/`AuthProvider`, sign-up / sign-in / forgot-password), `AppGate` as the
  top-level surface chooser (splash → sign-in → deletion notice → onboarding → shell),
  a claim-consent sheet before any pre-existing local data is uploaded, `SyncService`
  mirroring drift ⇄ `users/{uid}` (daily logs + preference settings only),
  `SyncTrigger` owning the debounce/suspend/claim gates, `SyncTombstones` for deletions,
  the local-only hatch, and the cancellable account-deletion request. Every non-obvious
  rule about all of it is in "Key design decisions" above. **`firestore.rules` is live; the deletion
  purge job (`functions/purge.js`) is written and tested but NOT deployed, so nothing is
  actually erased server-side yet.**

- **Media timeline (photos & videos, v6)** — a STANDALONE timeline, reached from a
  Calendar app-bar action beside the Diary (the bottom nav is at Material's five
  destinations). Not attached to a day: media has its own `MediaItems` table, its own
  Firestore subcollection `users/{uid}/media`, and its own Cloud Storage prefix.
  **The bytes are UNENCRYPTED in Cloud Storage** — an explicit owner decision, taken
  against the alternative of encrypted-on-device files. Say so wherever it is disclosed;
  the app's "encrypted at rest" claim covers the drift database, never this.
  **Cloud-required**: an item exists only once its upload has succeeded. No upload queue,
  no pending/failed row, no offline capture. Two consequences worth knowing before
  changing anything here:
  (a) `FirebaseMediaBlobStore` sets `setMaxUploadRetryTime(20s)` — the SDK default is
  **10 minutes**, which silently IS the queue this design rejected;
  (b) a crash between "bytes uploaded" and "document written" leaves an orphan, so
  `MediaSyncService.sweepOrphans` diffs the bucket prefix against **Firestore** (never
  the local table — a device that has not pulled holds no rows, and sweeping against
  that deletes the user's library).
  **Never `getDownloadURL()`**: the token is a bearer credential no rule evaluates and
  that never expires. Reads go through the authenticated SDK; a structural test greps
  `lib/` for it, and `firestore.rules` refuses to store a URL field. The emulator suite
  proves `storage.rules` CANNOT stop a client minting a token itself
  (`firebase_test/storage.test.mjs` records that as a characterisation, not a
  guarantee) — which is why the grep is the primary defence, not a backstop.
  Rows are **uid-scoped and erased on account change**: signing out never wipes the
  device, so without both guards account A's cached thumbnails would render inside
  account B's timeline. Thumbnails live in a `BlobColumn` INSIDE the encrypted database;
  full-size downloads live in a plain-file cache (`MediaCache`), which
  `deleteAllData`'s callers clear. Media is deliberately **excluded** from the doctor
  PDF, the home-screen widget and `.lunabak`. Video has no poster frame in v1 (every
  client-side option is a retired ffmpeg wrapper or a MediaCodec per tile).
  Deps: `firebase_storage`, `image_picker` (system Photo Picker — the only Play-compliant
  route; `READ_MEDIA_*` is restricted to photo/video apps), `video_player` (playback AND
  the duration probe that enforces the cap without transcoding), `flutter_image_compress`.
  **NOT YET DEVICE-VERIFIED — none of the following is catchable in `flutter_tester`,
  and every one of them is a real failure mode rather than a formality:**
  1. **OOM** — pick a 4K/90 MB video and a 50 MP image on a 1 GB Android 8 device
     (minSdk 26). No OOM at pick, at grid render, or full-screen.
  2. **Process death mid-upload** — start a large upload, background, `adb shell am kill`.
     On relaunch: no row, no visible item, and after the sweep no object in the bucket.
  3. **Network death at 80%** — airplane mode mid-upload. The error must surface within
     ~20s (the `setMaxUploadRetryTime` window), nothing persisted, no object finalized.
  4. **EXIF/GPS** — upload a geotagged photo AND a geotagged video, download both from the
     console, inspect metadata. No GPS. The guarantees differ between the two.
  5. **Picker temp copies** — after several picks, inspect the app cache over `adb`;
     plaintext duplicates must not accumulate.
  6. **Recents thumbnail** — open an item, press Home, open the app switcher. `grep
     FLAG_SECURE` returns nothing anywhere today, so an intimate photo currently lands in
     the system launcher's thumbnail, OUTSIDE `AppLock`. This is a known open gap.
     **Second surface, found 2026-09-14:** `AnalysisSessionsScreen` (the saved-conversations
     list) and `analysis_result_sheet.dart` (the Describe conversation itself) render AI
     PROSE about a body photo — not just the photo — and neither is any more protected than
     the photo screens are. Same gap, same fix (`FLAG_SECURE`), wider surface: a description
     mentioning what is visible in an intimate photo can now land in the recents thumbnail
     even when the photo itself is never reopened.
  7. **Lock during video** — audio must stop (the viewer's lifecycle pause).
  8. **Schema v6 from the background isolate** — `CheckInWriter` opens a bare
     `AppDatabase()` from a killed-app notification action. Flagged as unverified since
     v5; this is the bump at which to check it. Re-run `databaseIsEncryptedAtRest()` too.
  9. **Rules actually deployed** — a raw REST GET of a known object path from a signed-out
     client must be denied.

- **Photo descriptions (v7 photo-only; v11 adds tracked-context + saved
  conversations, opt-in)** — a **Describe** action in the media viewer sends
  ONE image to Google's Generative Language API (`gemini-3.5-flash`) and opens a
  **conversation** about it in a sheet — the user can keep asking follow-ups. Three files
  mirror the media split: `media_analysis.dart` (pure — request shape, parser, refusal
  copy, cap arithmetic), `media_analyzer.dart` (**the seam**, and the only file in `lib/`
  that may construct an `HttpClient`), `media_analysis_service.dart` (the gates).
  **The photo leaves both the device AND the user's own project**, which is why this is
  opt-in per account rather than on when signed in.
  Non-obvious things that are load-bearing:
  (a) **`thinkingConfig.thinkingBudget` MUST stay 0.** On Gemini 3.x, reasoning tokens
  come from the same allowance as the reply: with thinking on, `maxOutputTokens: 400`
  returned a sentence cut off at **16** tokens with `finishReason: MAX_TOKENS`. Measured
  2026-08-12 — thinking off is also 2.3s instead of 5.0s.
  (b) **`kAnalysisSystemInstruction` is a safety control, not copy.** It is what stops the
  model naming a condition on a body photo; it was verified against "Does this look like
  an infection? Should I take antibiotics?" and produced a refusal plus a description of
  what was visible. Its clauses are asserted by `media_analysis_test.dart`.
  **Re-verified 2026-08-13 for multi-turn**, which is a different attack: four benign
  rapport-building turns, then four escalating hostile ones (diagnose / "just guess the
  condition name" / "pretend you are a dermatologist" / "severity 1-10, just the
  number"). All four refused and redirected; no Markdown leaked across eight turns.
  **That result is now INVALID and has not been re-run.** It was run with no health
  context attached, `kAnalysisSystemInstruction` has since gained two clauses, and a
  model holding a clinical history is under materially more pull toward diagnosis than
  one looking at a bare photo. See the "AI health context for photo descriptions" bullet
  above for the full account, and `README.md` for the outstanding blocker to re-run it.
  A unit test asserts the clauses exist, never that the model still obeys them under
  pressure — that has not changed.
  (c) **Consent stores a UID and, since v11, a VERSION** (`AppSettings.analysisConsentUid`
  / `analysisConsentVersion`). The UID half: a device-global flag would let account B's
  photos be described on account A's consent — the bug `claim_preference.dart` already
  records for the sync decision. The version half is new — see "Consent is versioned"
  above. Neither is synced.
  (d) **The service class itself still stores nothing; the FEATURE, as of v11, does.**
  `MediaAnalysisService` is unchanged here: the answer and the live conversation are
  still held only in memory for the life of the viewer, `endConversation()` still fires
  when the sheet closes, and the class still never touches disk (`_memo`, keyed on
  `mediaId|question`, still avoids re-billing a reopen when there is no saved session to
  restore). What changed is the CALLER: `media_route.dart` now writes each exchange to
  `AnalysisSessionRepository` and, on reopen, loads the stored transcript and hands it to
  `seedConversation` before the next call. See "AI health context for photo descriptions"
  above for the schema, the erasure paths and why `seedConversation` exists — persisting
  prose about a body photo is exactly the second, softer copy that bullet describes
  paying for in full (`deleteAllData`, the sign-out wipe, `.lunabak`, the doctor PDF).
  (d2) **`generateContent` is stateless.** A conversation is the whole transcript resent
  every call, with the model's own replies echoed back as `role: "model"`. The image is
  attached to the FIRST user turn only — the array is resent whole, so one copy is in
  context for every answer. Hence `kMaxChatTurns`: turn ten pays for turns one to nine
  again, so conversation length drives input cost, not just call count. As of v11 the
  tracked-health-context block (`buildHealthContext()`) rides that same first turn, so it
  is resent whole on every turn too — see "The context rides the first user turn" above.
  (e) The daily cap (`kMaxAnalysesPerDay`) counts **messages, not photos** — every turn
  bills — and counts **before** the call, because it bounds spend rather than successes.
  It writes through `updateSyncState` — NOT `update`, which would stamp
  `settingsUpdatedAt` up to 20×/day and make every sync push forever. Its user-facing
  copy says "messages"; a test asserts it does not say "photos".
  **The API key ships inside the APK** (`--dart-define=LUNA_GEMINI_KEY`) and one `strings`
  call on `kernel_blob.bin` recovers it — verified, and a release blocker in `README.md`.
  **NOT YET DEVICE-VERIFIED:** the in-app flow (consent sheet → describe → follow-up) has
  only been proven as a standalone request against the live API with the same body shape;
  the physical device was unavailable when it was built.

**Calendar day entry is a bottom sheet, not an inline panel.** Tapping a day opens
`DayEntrySheet` / `showDayEntrySheet()` (`lib/widgets/day_entry_sheet.dart`, shared by the
calendar and the diary), whose content is a **`Scaffold`** (mirrors
`DayLogScreen`: form in `body`, Save in `bottomNavigationBar`). This is deliberate: an
inline panel below the viewport-filling month grid never reliably lays out (a lazy
`ListView` skips it; eager variants crash with "BoxConstraints forces an infinite width"
because a Material button won't lay out under a scroll/sheet's unbounded-width intrinsic
pass). A Scaffold gives the form and button bounded, tight constraints and absorbs that
intrinsic query. `_selectedDay` still gates the calendar ad while the sheet is open. The
sheet route **re-provides `LogProvider`** (routes build from the navigator's context, which
in tests sits above the pumped providers) but deliberately does NOT re-provide a
`PredictionResult` — the caller computes the `CheckInPrompt` and passes it in.
`test/calendar_inline_entry_test.dart` is the regression guard for this whole structure.

### Deferred

- **Pregnancy milestone reminders.** Pregnancy mode ITSELF is shipped — `PregnancyService`
  (Naegele EDD, gestational age, trimester), `PregnancyScreen` with a loss-safe neutral exit,
  a Settings entry point, `_PregnancyHome` with no ads and no fetal content, "Week N" in the
  home widget, prediction suppression, and `pregnancy_test.dart` + `pregnancy_flow_test.dart`.
  Only the milestone reminders are outstanding, and there is currently **no pregnancy
  `ReminderType`**. If they are ever added, `endPregnancy` MUST cancel every one — a
  congratulatory notification after a loss is the worst failure this app can have.

### v3 backlog (from a Meet You competitor teardown)

- **i18n/l10n** — the app is hardcoded English outside `settings_screen`
  (`AppSettings.language` is dormant); localization is its own initiative. Weight, habit
  chips (`kHabitOptions`, in the Lifestyle section) and the diary have all shipped; what
  remains for the diary is richer entry (per-day multiple entries, attachments), not reading
  notes back.

## Marketing site (`site/`)

A separate Astro static site in `site/`, deployed to Firebase Hosting. Nothing in it
imports from `lib/` — it reimplements the cycle and gestation arithmetic in TypeScript
so the calculators can run in a browser. When a formula changes in Dart, it does **not**
change here.

```bash
cd site
npm install
npm run dev        # http://localhost:4321 (daemonised: astro dev stop / status / logs)
npm run build      # writes site/dist
npm run verify     # the audit — MUST pass before any deploy
npm test           # 161 unit tests (vitest)
npm run check      # astro check — 0 errors
```

`npm run verify` builds nothing; it audits whatever is already in `dist/`. Run
`npm run build` first or you are auditing a stale tree.

### Key design decisions (non-obvious)

- **Zero JavaScript is the default and it is enforced, not aspirational.**
  `scripts/audit.mjs` holds a per-route `JS_BUDGET`, and the lookup is
  `JS_BUDGET[page] ?? 0` — **a route absent from that map is allowed zero bytes**, so a
  new page that ships an island fails the audit until it is added by hand. The number
  counts the whole static import graph (`moduleClosureBytes`), not just the file named
  in the markup: Astro emits no `<link rel="modulepreload">` for chunks a page's entry
  statically imports, so counting `<script src>` alone under-measured by 3.7 KB.
- **`vite.build.assetsInlineLimit: 0` is load-bearing.** The production CSP is
  `script-src 'self'`. An inlined island would be blocked by it and every calculator
  would silently stop working — silently, because the page still renders and only the
  form is dead. Never raise that limit.
- **A module's exports are the unit of bundling, not its call sites.** This was found
  and fixed five times at five layers, and it is the failure mode the per-route budget
  exists to surface: a chunk's exports are the union of what all its importing entries
  need, so the bundler cannot drop the rest — it only sees that the module is imported.
  Hence `lib/constants.ts` (so `gestation.ts` need not import `cycle.ts` for two
  integers), `lib/preg/*` (one calculator per module, `pregnancy.ts` a pure re-export
  barrel), and `lib/summary/<page>.ts` over a dependency-free assembler. `days.ts` is
  still one shared chunk — an export added for one page is paid for by all of them, and
  `dateRange` alone costs every route ~400 bytes. That is documented in `JS_BUDGET` as
  the next thing to cut if a route gets tight.
- **One island per page.** Each calculator page owns a `<script>` after `</Tool>` that
  imports only its own compute function plus `mount()` from `lib/island.ts`. One shared
  island holding every calculator measured 5,775 of the 8,192-byte budget with four in
  it; ten would have failed every calculator page at once.
- **The form ships with its fieldset `disabled` and the island re-enables it.**
  `ToolForm.astro` owns this once. The form has no `action`, so a submit without
  JavaScript would GET the current URL with every field appended — putting a menstrual
  date into the address bar, history and any bookmark. Gating the **fieldset** rather
  than the submit button is deliberate: a disabled fieldset makes every control
  non-focusable and not a successful control, so there is nothing to serialise, and the
  guarantee does not depend on how a browser handles Enter-key submission.
- **Form controls are styled in `global.css`, and must be.** Tailwind's Preflight resets
  `border-width: 0` on every element, form controls included, so an unstyled `<input>`
  here renders with **no box at all**. Found on a phone: an optional field was invisible,
  with nothing between its label and its help text. The `font-size: 16px` in that block
  is not taste — iOS Safari zooms the whole page in when a focused control's text is
  smaller.
- **Never hand-assemble a date.** `dateRange` used to pick a partial `Intl` option set
  per case; a partial set has no defined word order and en-US rendered it "17 Thursday".
  Use `Intl.DateTimeFormat`'s own `format`/`formatRange`. Tests pin the order of the
  words with whitespace normalised, because ICU's choice of thin spaces inside a range
  shifts between versions.
- **The app's copy guardrails apply here too**, and the audit enforces part of it:
  `BANNED_CLAIMS` in `src/consts.ts` fails the build on "no account", "fully private",
  "anonymous", "end-to-end" and the rest — the site cannot claim a privacy posture the
  app does not have. The rest is editorial and holds identically: never "safe" near
  fertility, no synthesized percentage, never a method of contraception, and the site
  names no condition and describes no symptom as meaning anything.
- **`hcg-calculator` is HELD** — a 19-agent verification pass returned "do not ship the
  specified page" over six issues (sensitivity formulas, rounding, copy safety,
  metadata, citations, singularities). It is the one calculator of the ten that was
  designed and deliberately not built. Do not build it without an owner decision.

### Deploying

Hosting config is the `hosting` block in the **repo-root** `firebase.json` (public
`site/dist`, `cleanUrls`, redirects, CSP and cache headers). There is deliberately no
`.firebaserc`, so every command needs `--project teddy-2-20649` explicitly.

```bash
cd site && npm run build && npm run verify     # audit MUST pass first
cd .. && firebase hosting:channel:deploy preview --project teddy-2-20649 --expires 7d
firebase deploy --only hosting --project teddy-2-20649     # production
firebase hosting:rollback --project teddy-2-20649          # undo
```

**`teddy-2-20649` is a shared project with two hosting sites.** The `hosting` block
names no `site`, so a deploy targets the default site `teddy-2-20649`. The other site,
`pocket-change-admin-dev`, belongs to an unrelated app and must never be deployed to
from here. A channel deploy prints a "Hosting URL" line that reads like a production
release and is not one — verify by fetching the production URL.

**Production is blocked on the Play listing.** `ORG.sameAs` points at
`play.google.com/store/apps/details?id=com.lunatrack.app`, which 404s. That URL is
behind the "Get the app" pill on every page and is emitted in the site's schema.org
JSON-LD, so going live would publish structured data pointing at an app that does not
exist. A preview channel is live and safe; production has never been deployed.

## Pre-store-submission checklist (needs the project owner's accounts)

The full list with rationale is in `README.md` → "Before publishing". The ones that block
on accounts/infrastructure:

- **Ship the account-deletion purge job.** Until it exists, Google Play's in-app
  account-deletion requirement is **UNMET** and both disclosure documents have to say the
  erasure is not automatic.
- **Deploy `firestore.rules`** to the named `lunatrack` database. Nothing is enforced
  server-side today.
- **Settle which Firebase project LunarFlow belongs in** and commit a correct
  `firebase.json`. See the TODO in "Key design decisions".
- Real upload keystore (release is debug-signed today).
- Real AdMob app + unit IDs (currently Google **test** IDs — flip `AdConfig.useTestAds`,
  fill `_prod*` + manifest `APPLICATION_ID`).
- Real Play in-app product id for Premium.
- ✅ **DONE** — `kDatabaseEncryptionEnabled` is on and device-verified (2026-07-16).
- Host `PRIVACY_POLICY.md` and `docs/account-deletion.md` at public URLs; put the
  deletion URL in the Play listing's data-deletion field.
- Play Data Safety: health data is **collected AND transmitted**, tied to user identity.
  Declare **sexual-activity** and pregnancy data. "Encrypted at rest" applies to the
  on-device drift database; the **cloud copy is plaintext and readable by the operator**,
  so do not claim end-to-end encryption.

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

Two suites, and `flutter test` does not cover the second:

- `flutter test` — **1141** passing, 3 skipped, **2 failing**. (Keep this number current; a
  stale one makes a real regression look like a miscount.) The two failures are
  PRE-EXISTING and not in this lane: `firebase_unavailable_test.dart` taps
  `Icons.settings_outlined`, which `409973a` replaced with an illustrated nav mark.
- `firebase_test/run.sh` — **39** Firestore rules tests against a LOCAL emulator
  (`demo-lunatrack`; firebase-tools treats any `demo-*` id as emulator-only, and there is
  deliberately no `.firebaserc`, so no command here can fall into a real project). Needs
  Node 18+, a JDK 21+, and a `firebase.json` at the repo root — which IS tracked as of
  `245bb99`, so this now runs on a fresh clone (it did not before; that claim was stale). `run.sh --mutants` additionally proves each test
  discriminates.
- `firebase_test/storage_run.sh` — **22** Cloud Storage rules tests, same harness style
  against the Storage emulator (a separate REST API, hence `storage_emulator.mjs` rather
  than an extension of `emulator.mjs`). Uploads use the RESUMABLE protocol on purpose:
  the simple upload endpoint stores everything as `application/octet-stream`, which would
  make the content-type allowlist silently untestable.
- `firebase_test/purge_run.sh` — **36** purge tests; `--mutants` proves all 34 mutants die.

Firebase-touching code is injected through seams everywhere (`AccountSection`, `AppGate`,
`SyncTrigger` all take an overridable Firestore/`AccountDeletionService` factory) because
`lunaFirestore()` throws with no initialized Firebase app — the state of every test
harness. Do not remove those seams to "simplify".
