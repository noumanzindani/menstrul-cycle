# Handoff — resume work from a fresh clone

Written 2026-09-13. Read this first, then `CLAUDE.md` (architecture + every
non-obvious decision) and `README.md` (§ Before publishing).

This file answers three questions `CLAUDE.md` deliberately does not: **what a
fresh clone is missing, what is in flight right now, and what is unverified.**
Keep it current — a stale handoff is worse than none, because it is trusted.

---

## 1. A fresh clone does NOT build. Supply these first.

Two Firebase files are gitignored on purpose and must be restored by hand.
Without them `Firebase.initializeApp()` throws and `AppGate` drops the whole app
into the local-only hatch, so every sync/auth path is unreachable and the media
timeline (and therefore photo descriptions) cannot be opened at all.

| File | `.gitignore` | How to get it |
|---|---|---|
| `android/app/google-services.json` | line 48 | Firebase console → project settings → Android app |
| `lib/firebase_options.dart` | line 58 | `flutterfire configure` |

Not required to build, but required for the features that use them:

| What | How |
|---|---|
| Photo descriptions / the AI chat | `--dart-define=LUNA_GEMINI_KEY=…` at BUILD time. `String.fromEnvironment` is a compile-time const, so this cannot be set at runtime and a build without it hides the feature entirely (`analysisAvailable` is false). |
| Release signing | `android/key.properties` — absent. Release is debug-signed today. |
| iOS | `ios/Runner/GoogleService-Info.plist` — absent. iOS is deferred. |

`firebase.json` IS tracked (since `245bb99`), so `firebase_test/run.sh` works on
a fresh clone. There is deliberately no `.firebaserc`, which is what keeps every
emulator command pinned to the `demo-lunatrack` fake project.

```bash
flutter pub get
flutter analyze          # must stay clean
flutter test             # 1109 tests
cd admin && ./test/run.sh   # 44 tests, needs JDK 21+ on PATH (not just JAVA_HOME)
```

`build_runner` is only needed when the drift schema changes:

```bash
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/db/database.dart drift_schemas/      # BEFORE the next bump
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

---

## 2. Where the work stands

Branch `feat/stitch-redesign`. Schema is at **v10**. Two workstreams run in
parallel on this branch and should not be mixed in one commit:

- **the Flutter app** (`lib/`, `test/`, `android/`, `ios/`, `admin/`)
- **the marketing site** (`site/`, `docs/superpowers/`)

Commit by explicit path (`git commit -- lib/ test/ …`), never `git add .` — the
two lanes are frequently dirty at the same time.

### Landed recently (newest first)

| Commit | |
|---|---|
| `97571bb` | In-app capture — take a photo / record a video from the media timeline |
| `e9789e5` | Signup sexual-health baseline (schema v9 → v10), three onboarding pages |
| `beb9849` | `kCatIntimacy` defaults ON, matching partnered sex |
| `b49f5bb` | Gynaecological intake Tier 1 + Tier 2 (schema v8 → v9) |
| `0e2680f` | Sync marker fix — an old build's settings push no longer clears profile fields |
| `fc9e2f1` | Profile fields: date of birth, height, weight, age at first period (v7 → v8) |

Every design decision behind these is in `CLAUDE.md`; this list is only for
orienting in `git log`.

---

## 3. Unverified on hardware

Everything below passes tests and has never run on a physical device. Each one
is a class `flutter_tester` structurally cannot reach.

1. **The capture sheet** (`97571bb`). Tests prove the sheet dispatches the right
   `MediaSource`; nothing proves `ACTION_IMAGE_CAPTURE` resolves on a real
   handset or that a usable file comes back.
2. **Photo descriptions / the AI chat — never run in-app, ever.** Only proven as
   a standalone request against the live API with the same body shape. Needs a
   `LUNA_GEMINI_KEY` build, a signed-in account, and an uploaded photo.
3. **Settings → Health context** (contraception, diagnoses, breastfeeding rows).
4. **The background-isolate migration path.** `CheckInWriter` opens a bare
   `AppDatabase()` from a killed-app notification action. Flagged unverified
   since v5 and still is, now four schema bumps later. Re-run
   `databaseIsEncryptedAtRest()` at the same time.
5. **The nine media device-test items** listed in `CLAUDE.md` (OOM, process
   death mid-upload, EXIF/GPS, recents thumbnail, …).

**Verified on device 2026-09-13:** the v8→v9 and v9→v10 migrations against a
real encrypted database; the day editor incl. the new libido scale, bleeding
after sex, and the Intimacy section; `android.permission.CAMERA` absent from the
*installed* package (`dumpsys package … requested permissions` — the only
reading that reflects what the OS enforces).

### Device notes

The OnePlus (`cdc8bb52`) drops off USB when connected through the shared hub —
it re-enumerates on every command and any sustained transfer dies. Plug it into
a port on the Mac directly. Confirm with `ioreg -p IOUSB -w0`: a USB address of
`@0214…` means it is back on the hub; `@0220…` is the direct port. Ten
consecutive `adb shell echo` probes should all pass before attempting an install.

---

## 4. Open decisions and known gaps

- **`site/scripts/audit.mjs:5` cites `docs/research/flo-health-teardown.md`, a
  path that is not in this repository.** That document is deliberately withheld
  from the public remote; the pointer advertises its existence. Two more public
  files (`docs/superpowers/plans/2026-09-13-lunatrack-site.md` and the matching
  spec) carry ~57 references to the same research. The rendered site is clean —
  this is a repository-only exposure. Owner decision outstanding.
- **The account-deletion purge job is written but NOT deployed**
  (`functions/purge.js`), so Play's in-app deletion requirement is unmet.
- **`firestore.rules` is NOT deployed.** Nothing is enforced server-side today.
- **The Firebase project id is unsettled** — do not hardcode one anywhere.
- Release keystore, real AdMob ids, real IAP product id, hosted privacy-policy
  and deletion URLs: all outstanding. See `README.md` § Before publishing.

---

## 5. Things that will bite you

Short list of traps that have already cost time here. The reasoning for each is
in `CLAUDE.md`; these are the ones worth knowing before you touch anything.

- **`encodeDayTags` is a full REPLACE.** The day editor must decode and re-encode
  every group unconditionally. Gating a group out of decode or save destroys it.
- **`saveDay` replaces a whole day.** Two writes to one date means the second
  erases the first.
- **`migrateAndValidate(db, n)` upgrades to the database's OWN `schemaVersion`**,
  so at every bump the older migration tests must be re-pointed, not deleted.
- **Dump the drift schema snapshot BEFORE bumping the version** — it is only
  derivable while that version is current.
- **The sync `profileFields` marker is a VERSION, not a flag.** Each generation
  of columns gates on its own minimum. Widening an existing gate silently wipes
  a newer generation's data on an older device's push.
- **Never declare `android.permission.CAMERA`.** It makes
  `ACTION_IMAGE_CAPTURE` require a grant the app never requests, breaking capture
  at runtime. iOS wants the exact opposite and needs its usage strings or it
  crashes. Both are asserted in `test/media_guardrails_test.dart`.
- **Never a bare `FilledButton` in a `Row`** — the theme gives it infinite width.
  This shipped a consent button off-screen once.
