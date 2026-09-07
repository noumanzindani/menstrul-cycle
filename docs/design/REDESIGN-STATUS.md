# LunaTrack redesign — status and outstanding work

Last updated 2026-09-07.

The Stitch-driven visual redesign landed across the Flutter screens. This file
records what is **done**, what is **deliberately not done**, and what is **still
owed** — including the device-verification checks that no test in this repo can
perform. It is the companion to `docs/design/2026-09-07-stitch-ui-brief.md` (the
design brief) and `docs/design/stitch/README.md` (how the mocks were made).

---

## 1. What shipped

A visual refinement pass over 8 screen groups, driven by the 35 mocks in
`docs/design/stitch/`. Presentation only: no business logic, provider wiring,
repository call or route was changed, and `lib/theme/app_theme.dart` was not
touched — it already matched the design system exactly (seed `#F7A8C4`, both
phase palettes, cards 20dp/elevation 0, filled buttons 52dp/16dp, chips 12dp).

`flutter analyze` clean · **906/906 tests pass** · guardrail suites untouched.

New shared component: `lib/screens/settings/settings_group.dart` —
`SettingsGroup` / `SettingsValue` / `SettingsFinePrint`, the grammar the
settings, account, reminders and tracking-categories screens are now built from.

### Two findings worth carrying forward

**A live guardrail breach was found in shipped code.** `product_timer_card.dart`
coloured the elapsed figure `scheme.error` — red — once past the user's set
target. The council ruling bans red as an alert colour outright, and the change
timer is the feature nearest a real medical emergency. Removed: the display line
is now identical in size, weight and colour either side of the target, and only
the wording changes.

**The "revert, never edit the guardrail test" rule caught a real regression.**
The redesign restacked the photo-consent buttons from `Row` + `Expanded` into a
full-width `Column`, reasoning correctly that a bare `FilledButton` in a `Row`
demands infinite width. But that added 94px to a fixed-height bottom sheet and
pushed **both** buttons past the viewport bottom (`Not now` at y=844 on an 800px
surface), so consent could be neither granted nor declined — the 2026-08-13
device bug again, rotated 90°. `analysis_consent_sheet.dart` was reverted to
HEAD; the test was not touched. The pre-existing `Row` + `Expanded` was already
the correct fix for the infinite-width trap.

The lesson is the rule itself: a plausible rationale is exactly what lets this
class of regression survive review. A guardrail failure is a question about
whether the ruling changed, not a test to update.

---

## 2. Outstanding — design set

### 2.1 Dark mode: design system exists, screens do not

A Stitch design system carries one `colorMode`, so light cannot be re-themed. A
dark system was created — **`assets/8873628026339279935`** ("LunaTrack — dark",
`colorMode: DARK`, `TONAL_SPOT`, seed `#F7A8C4`, neutral `#1C1B1B`) — carrying
the dark phase palette as primary.

**No dark screens were generated.** All five attempts (Today, Calendar,
Insights, Day log, Settings) failed. See §2.2.

This is lower priority than it looks: the app's dark mode **works today** and was
confirmed on the device, because the implementation uses `ColorScheme` /
`PhaseColors` tokens rather than the mocks' literal hex. Dark mocks would be a
review aid, not a prerequisite.

### 2.2 The Stitch API constraint (read before re-exporting anything)

`generate_screen_from_text` **succeeds on small screens and fails on large ones.**
Every failure is the same opaque `Network failure connecting to Stitch API:
fetch failed`. Evidence from 12 calls: sign-in 6.8KB OK (twice), photo-describe
sheet 7.8KB OK, single card 3.8KB OK; Today (~10KB+) failed 5×, day-log minimal
(~11KB) failed 4×, dark Settings failed.

Ruled out by deliberate test, not argument:

- **Not prompt size** — a 1.6KB prompt failed, a 1.66KB prompt succeeded.
- **Not endpoint down / rate limit / quota** — the byte-identical sign-in prompt
  was re-sent after six consecutive failures and succeeded immediately.
  Cooldowns of 90s / 150s / 300s changed nothing.
- **Not model-specific** — `GEMINI_3_FLASH` fails on the same screens as
  `GEMINI_3_1_PRO`.
- **Not literal `<svg>`/`<circle>` in the prompt, and not menstrual vocabulary** —
  the successful single-card generation is titled "Next period card (low
  confidence)" and is full of the same words.

Heuristic: **a failure returns fast, a success returns slow.** You can tell them
apart before the result lands.

**A timed-out generation is unrecoverable.** The tool docs say poll `get_screen`,
but `get_screen` needs an id that only arrives in the response you did not get.
`list_screens` still returns `{}`. `get_project`'s `updateTime` does move, which
confirms a call landed and nothing more.

**The workaround that worked: ask Stitch for a COMPONENT, then assemble the page
locally.** Files 36 and 38 use a genuinely Stitch-generated "Next period" card
(screen `ad37f368375d41df98d1d26a09bf14cd`) retokenised onto each palette.

### 2.3 New mocks added (36–42)

| File | Source | Screen |
|---|---|---|
| `36-today-first-run-date.html` | composed locally | Today, first run with a date — estimate tagged low-confidence |
| `37-today-first-run-no-date.html` | composed locally | Today, first run, "I'm not sure" — honest emptiness |
| `38-today-low-confidence.html` | composed locally | Today, low confidence, established user |
| `39-calendar-day-sheet.html` | composed locally | Calendar with the day sheet open |
| `40-day-log-minimal.html` | composed locally | Day log, core sections only |
| `41-sign-in-no-hatch.html` | **Stitch** | Sign in without the local-only hatch |
| `42-photo-describe-limit.html` | **Stitch** | Description sheet, daily cap reached |

A ring defect was found and fixed while building these, invisible to any text
scan: in screen 36 today is the **first** day of the follicular run, so the
dotted today-marker was painted in the same colour as the run beneath it and
vanished. General rule now recorded: **a dotted day only reads if the run under
it is lighter than the dots.**

### 2.4 Mock defects to fix in the design set

Found during the implementation audit. Each is a mock that is wrong about the
app, not an app that is wrong about the mock — so each was **declined**, not
implemented.

- **`02-calendar.html`** paints a solid fertile fill on Sept 10–12 but places
  the ovulation dot on Sept 13, **outside** that window. Real ovulation always
  sits inside the fertile window it is derived from. Same class of defect as the
  Today-ring contradiction already recorded in `stitch/README.md`.
- **`32-pregnancy.html`** ships a 320×50 advertisement slot on the pregnancy
  screen. That contradicts the brief's own S26, CLAUDE.md's loss-safe rule, and
  an existing test asserting `AdBanner` finds nothing there.
- **`32-pregnancy.html`** also adds a "Weeks to go — 26 weeks" card the brief
  never asked for: a countdown to a birth, on the one screen required to be
  survivable after a loss.
- **`09-sign-in.html`** carries the tagline *"Your cycle, kept private."* That is
  a promise the app cannot keep — daily logs and settings sync to Firestore in
  plaintext and the operator can read them, and uploaded media is unencrypted in
  Cloud Storage.
- **`20-deletion-pending.html`** states "Everything on this device has already
  been erased." True only on the device that made the request; the same screen
  renders on a second device that was never wiped.
- **`26-claim-data-sheet.html`** labels the decline "Keep the account's data" and
  draws a drag handle plus a "Decide later" third answer. The sheet is
  deliberately non-dismissible (`isDismissible: false`, `enableDrag: false`,
  `PopScope(canPop: false)`) and has no third answer.
- **`17-cycle-overview.html`** is a mock of a screen that does not exist — a
  four-phase education view with fertility content. `CycleOverviewScreen` is a
  historical per-cycle rollup with no fertility content at all.
- **`27/33` app lock** draw a fixed 6-dot and 4-dot PIN indicator respectively.
  The app enforces a minimum of 4 digits and **no maximum**, so any fixed-length
  indicator is wrong for some users. `33` also offers "Forgot PIN?" — no
  recovery flow exists, and inventing one is a security decision, not a styling
  one.
- **`05-forecast.html`** fades cards 2–5 to 85/70/55/40% opacity. At 55% and
  below the body text falls under WCAG AA in the mock's own render.
- **`13-reminders.html`** renders a fake collapsed lock-screen notification.
  Every channel sets `visibility: NotificationVisibility.secret`; a mock implying
  otherwise teaches the wrong thing about what the lock screen shows.

### 2.5 Secondary variants still not drawn

Light mode: the disabled-composer description sheet exists (42), but the calendar
day-sheet, minimal day log and first-run Today states are locally composed rather
than Stitch-native — fine as artefacts, worth regenerating if the API recovers.

---

## 3. Outstanding — device verification

Checks that `flutter_tester` structurally cannot perform. Device: OnePlus Nord
N200 5G (`DE2118`, Android 12 / API 31, arm64-v8a).

| # | Check | Status |
|---|---|---|
| **A** | Database encrypted at rest | ✅ **PASS** — header `ec e4 57 93 …`, not `SQLite format 3\0`; no legacy plaintext DB; keystore entry present; key round-trips across a cold start |
| **D9** | `firestore.rules` / `storage.rules` deployed **and enforced** | ✅ **PASS** — 403 `PERMISSION_DENIED` on all four unauthenticated probes (health-log read, media subtree list, `deletionRequests` enumeration, Storage object fetch) |
| **C** | One-tap check-in from the notification shade, app killed | ⬜ not run |
| **D1** | OOM on a 4K/~90 MB video and a 50 MP image | ⬜ not run |
| **D2** | Process death mid-upload, then orphan sweep | ⬜ not run |
| **D3** | Network death at 80% — must fail within ~20s | ⬜ not run |
| **D4** | EXIF/GPS stripped from photo **and** video | ⬜ not run — needs `exiftool`, not installed |
| **D5** | Picker temp copies accumulating in the cache | ⬜ not run |
| **D6** | Recents thumbnail | ⬜ not run — **expected to FAIL**, `FLAG_SECURE` appears nowhere |
| **D7** | Lock during video playback stops audio | ⬜ not run |
| **B / D8** | Schema migration from the background isolate | ⬜ not run — needs a device DB at schema ≤6, which a clean install never produces |
| **E** | Photo descriptions end-to-end | ⬜ blocked — no `LUNA_GEMINI_KEY` in this build, so `analysisAvailable` is false and the Describe action does not render |

**Setup note for check C:** onboarding must be completed with the last period set
to **≈30 days ago**. That makes `nextPeriodStart` fall today-or-earlier, which is
the only way `CycleCheckInService.evaluate` produces the `didItStart` prompt —
and without that prompt the notification ships with no action button, so C cannot
run at all.

---

## 4. Documentation corrections owed

`CLAUDE.md` and `README.md` are **wrong about the backend**. Verified read-only
against the live project `teddy-2-20649` on 2026-09-07:

| Claim in the docs | Reality |
|---|---|
| `firestore.rules` "written but NOT deployed" | **Deployed** to `lunatrack-db`, byte-identical to the repo file (`diff` clean, media block and `downloadUrl` guard present) |
| `storage.rules` not deployed | **Deployed** to `teddy-2-20649-lunatrack-media`, byte-identical |
| `lunatrack-db` existence unverified | **Exists**, created 2026-08-12 |
| Media bucket may not be Firebase-linked | **Is** Firebase-linked |
| Firebase project id "NOT settled" | Settled: `teddy-2-20649`, consistent everywhere |
| `(default)` at risk from a LunaTrack deploy | **Untouched** — holds an unrelated donations/NGO app's rules |
| Purge job | **Confirmed still not deployed** — this one is accurate |

Also worth recording: **this Firebase project is shared with a live donations/NGO
app, and Auth is project-wide.** Creating a LunaTrack account fires that app's v1
`onUserCreated` trigger and leaves a stray user doc in its `(default)` database.

---

## 5. Release blockers still open

Unchanged by this work; the full list with rationale is in `README.md` →
"Before publishing". Still outstanding:

- **Ship the account-deletion purge job.** Written (`functions/purge.js`, covered
  by `firebase_test/purge.test.mjs`) but **not deployed**, so Google Play's
  in-app account-deletion requirement is unmet and both disclosure documents must
  keep saying the erasure is not automatic.
- Real upload keystore (release is debug-signed today).
- Real AdMob app + unit IDs (currently Google **test** IDs).
- Real Play in-app product id for Premium.
- The Gemini API key ships inside the APK — one `strings` call on
  `kernel_blob.bin` recovers it.
- Host `PRIVACY_POLICY.md` and `docs/account-deletion.md` at public URLs.

---

## 6. Known repo-hygiene items

- **`lib/` is 97/136 files unformatted** against the installed Dart 3.11
  formatter — the tree was written under the older style. Running `dart format`
  on individual files therefore produces large style-only diffs; it was
  deliberately **not** run during this pass for that reason. Reformatting is a
  separate, whole-repo commit if it is wanted at all.
- **i18n:** every string added by this redesign is a hardcoded English literal.
  `AppSettings.language` remains dormant project-wide; localisation is its own
  initiative (v3 backlog).
