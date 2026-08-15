# menstrul_track

LunaTrack — a menstrual/period tracker built with Flutter. The on-device drift
database is the source of truth; when signed in, daily logs and preference
settings are mirrored to Firebase Firestore so they sync across devices.

See `CLAUDE.md` for the architecture and the non-obvious design decisions.

## Getting Started

```bash
flutter pub get
flutter run
flutter analyze
flutter test
```

A few resources if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

## Firebase setup

`android/app/google-services.json` is gitignored (`.gitignore` line 48) because
it identifies the Firebase project. To build from a fresh clone, download it
from the Firebase console for the project LunaTrack uses and place it at
`android/app/`.

**Firebase project: `teddy-2-20649`** — settled by the project owner on
2026-08-12. It is SHARED with unrelated apps, which is what every isolation
decision below is defending against. The Android app is `com.lunatrack.app`,
appId `1:454527030179:android:cefb1b772608f98a6cc016`.

LunaTrack uses a **named** Firestore database, `lunatrack-db`, not `(default)` —
`kLunaDatabaseId` in `lib/services/firestore_ref.dart`. `(default)` carries a
single ruleset for every app in a project, so a permissive rule written for an
unrelated app would expose menstrual logs. A named database has its own
independent ruleset. **Never call `FirebaseFirestore.instance`; always use
`lunaFirestore()`.**

> **Create a named database from the Firebase console, never from `gcloud`.**
> The first attempt (`gcloud firestore databases create lunatrack`) produced a
> database that ignored its ruleset entirely: the `cloud.firestore/lunatrack`
> release existed and pointed at the compiled rules, but the database denied
> every request, including under a literal `allow read: if true`. It was running
> deny-all, and no rules edit could reach it. See the doc comment on
> `kLunaDatabaseId` for the full account.

Media bytes live in a **dedicated bucket**, `gs://teddy-2-20649-lunatrack-media`
(`kLunaStorageBucket` in `lib/services/storage_ref.dart`), because Storage
rulesets are per-BUCKET and there is no named-database equivalent. `firebase.json`
MUST keep naming that bucket explicitly — a `"storage"` entry with no `bucket`
targets the project's default bucket and would overwrite an unrelated app's
ruleset.

### Firestore rules

`firestore.rules` is the ruleset for the named database. Every
rule matches on identity (`request.auth.uid == uid` in the document path), never
on `request.auth != null` alone: in a shared Firebase project every other app's
users hold a valid token against this database, so "is signed in" is not a
boundary.

Run the rules test suite against a **local** emulator (project id
`demo-lunatrack`; nothing contacts a remote project):

```bash
firebase_test/run.sh              # 29 rules tests
firebase_test/run.sh --mutants    # + prove each test discriminates
```

Requires Node 18+ and a JDK 21+. `run.sh` needs `firebase.json` at the repo
root, which is deliberately untracked — see the "not committed" note in
`.superpowers/sdd/2026-08-04-firebase-auth-sync/task-12-rules-report.md` for the
two JSON blocks it needs.

Deploying:

```bash
firebase deploy --only firestore:rules --project teddy-2-20649
firebase deploy --only storage      --project teddy-2-20649
```

Afterwards, confirm the co-tenant app's rulesets were untouched — the release
named `cloud.firestore` (no suffix) and `firebase.storage/teddy-2-20649.firebasestorage.app`
belong to another app and must never move:

```bash
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     -H "x-goog-user-project: teddy-2-20649" \
     https://firebaserules.googleapis.com/v1/projects/teddy-2-20649/releases
```

A deploy alone is not proof the rules are LIVE: a named database that was not
created through Firebase accepts the release and then ignores it. Verify by
signing in as a real user and reading an owned path — a `404` means the rules
passed and the document is simply absent, a `403` means they did not.

## Before publishing

These block a Play release. None of them are done.

- [ ] **Ship the account-deletion purge job.** The app records a deletion
      request at `deletionRequests/{uid}` with a 30-day `purgeAfter`. The
      scheduled job that carries it out now exists — `functions/purge.js` and
      `functions/index.js`, with emulator tests and a mutation check — but it is
      **not deployed**, and it needs `LUNA_STORAGE_BUCKET` set in its
      environment. **Google Play's in-app account-deletion requirement is
      UNMET until it ships**, and both `PRIVACY_POLICY.md` and
      `docs/account-deletion.md` currently have to disclose that the erasure is
      not automatic. `AccountDeletionService.deleteFirestoreData` is the
      executable specification of what the job must delete (every subcollection
      first, the `users/{uid}` document last).
- [ ] **Deploy `firestore.rules`** to the named `lunatrack-db` database and
      PROVE it is enforced (see "Firestore rules" above — a deploy to a
      wrongly-created database silently does nothing). Until then no access rule
      is enforced server-side. Verify afterwards that the `(default)` database's
      rules were not touched.
- [x] **Settle the Firebase project** — `teddy-2-20649`, decided 2026-08-12.
      `firebase.json` names the media bucket explicitly; keep it that way.
- [ ] **Move the Gemini API key off the device.** Photo descriptions call
      Google's Generative Language API directly, with the key supplied at build
      time via `--dart-define=LUNA_GEMINI_KEY=…` (`kGeminiApiKey` in
      `lib/services/media_analyzer.dart`). That keeps the key out of git and
      **does not** keep it out of the APK: it is compiled into the Dart snapshot
      as a plain string, and one `strings` call on `kernel_blob.bin` in the
      built APK recovers it — verified 2026-08-12. It is a billable endpoint,
      so anyone who unpacks the app can spend the owner's quota. Google's own
      per-app key restrictions do not close this: they are enforced through
      `X-Android-Package` / `X-Android-Cert` headers a plain `dart:io` request
      cannot send. The fix is a callable Cloud Function holding the key —
      `functions/` already exists, and it is also the only place the per-user
      daily cap can actually be enforced rather than merely observed. Deploy it
      with `--only functions:<name>` so the never-run, delete-authoritative
      `purgeDeletedAccounts` is not dragged live.
- [ ] **Play Data Safety form** — health data must be declared **collected AND
      transmitted**, tied to the user's identity. Declare sexual-activity and
      pregnancy data. "Data is encrypted in transit" is true; do **not** claim
      the cloud copy is end-to-end encrypted — it is stored in plaintext and is
      readable by the operator. **Photos must additionally be declared SHARED
      with a third party** once photo descriptions ship: tapping Describe
      transfers the image to Google. It is opt-in and off by default, which the
      form has a field for, but it is still a transfer.
- [ ] **Add `lib/firebase_options.dart` to `.gitignore`.** It holds a Firebase
      API key and is currently neither tracked nor ignored, so a `git add .`
      commits it. A Firebase client key is an identifier rather than a
      credential — access is decided by security rules, not by holding the
      string — so this is a hygiene fix, not the same severity as the Gemini key
      above.
- [ ] **Account deletion URL** — host `docs/account-deletion.md` publicly and
      enter the URL in the Play listing's data-deletion field. Replace the
      placeholder contact address in it and in `PRIVACY_POLICY.md`.
- [ ] **Host `PRIVACY_POLICY.md`** and enter the URL in Play Console → App
      content → Privacy policy.
- [ ] Real upload keystore (release is debug-signed today).
- [ ] Real AdMob app + unit IDs (currently Google **test** IDs).
- [ ] Real Play in-app product id for Premium.
