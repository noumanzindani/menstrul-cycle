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

**Verified against the live Firebase project 2026-09-14:** `firestore.rules` and
`storage.rules` are BOTH deployed — to `cloud.firestore/lunatrack-db` and
`firebase.storage/teddy-2-20649-lunatrack-media` — and both are byte-identical to the
files in this repo that the emulator suite tests. Earlier notes in `CLAUDE.md` and in
this document claimed they were undeployed; that was wrong, and the emulator suite
cannot tell the difference, so re-check it directly rather than trusting prose:

```bash
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" -H "x-goog-user-project: teddy-2-20649" \
  https://firebaserules.googleapis.com/v1/projects/teddy-2-20649/releases
# then GET .../rulesets/<id> and diff its source against the local file
```

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
- **The account-deletion purge job is DEPLOYED** (2026-09-14) as
  `purgeDeletedAccounts`, us-central1, 2nd gen, scheduled every 24 hours via
  `firebase-schedule-purgeDeletedAccounts-us-central1` (ENABLED). Play's in-app
  deletion requirement is met on the server side; the remaining publication
  blockers are in `README.md`.
  **Never run a bare `firebase deploy --only functions` here.** The project is shared
  with an unrelated donations app that has 19 live functions (`registerNgo`,
  `createDonationIntent`, `deleteMyAccount`, …); a bare functions deploy prunes
  everything absent from local source and would delete all of them. Two guards are in
  place — the `lunatrack` codebase in `firebase.json`, and the name filter:
  `firebase deploy --only functions:lunatrack:purgeDeletedAccounts`. Use both.
- **Not yet observed doing real work.** Deploy-time facts are verified (ACTIVE,
  region, runtime, `LUNA_STORAGE_BUCKET` set, scheduler ENABLED, runtime SA holds
  `roles/editor`), but no invocation has been watched end-to-end, so nothing yet
  proves it reaches the NAMED `lunatrack-db` rather than `(default)` — the exact
  silent failure the `LUNA_DATABASE_ID` comment in `functions/index.js` exists to
  prevent. It runs daily on its own; check a run before trusting it:
  `gcloud functions logs read purgeDeletedAccounts --region us-central1 --project teddy-2-20649`
  The queue is safe to watch: the single pending marker is not due until 2026-10-13.
- **Firebase Auth deletion is PROJECT-WIDE and the Auth pool is shared.** The client
  never deletes the Auth account; only this job does. So a person who uses both
  LunaTrack and the donations app and deletes their LunaTrack account loses the
  identity the other app knows them by. Deleting the account is what makes "delete my
  account" honest, so the fix is a dedicated project, not skipping the delete. Accepted
  and documented, not an oversight — but it is a real cross-app consequence.
- **Node.js 20 is decommissioned 2026-10-30**; after that this function cannot be
  redeployed without upgrading the runtime (and `firebase-functions` is a major version
  behind). That is a hard deadline roughly six weeks out, not a lint warning.
- **The Firebase project is `teddy-2-20649`**, named in the tracked `firebase.json`.
  Moving LunaTrack to a dedicated project is still an open owner decision, so keep
  reading the id from config rather than hardcoding it in Dart.
- An old `lunatrack` database (gcloud-created, so deployed rules do not take effect on
  it) still exists alongside the real `lunatrack-db`. It is EMPTY — no exposure — but it
  is a loaded footgun if anything ever points at it. Worth deleting.
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
