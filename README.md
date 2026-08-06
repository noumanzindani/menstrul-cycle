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

> **TODO — which Firebase project LunaTrack belongs in is not settled.** The
> repo currently disagrees with itself: `lib/services/firestore_ref.dart`'s doc
> comment names one project, while the untracked `firebase.json` and
> `lib/firebase_options.dart` name a different one. Neither is committed as the
> answer. Ask the project owner before generating config, and fill this section
> in once it is decided — do not guess.

LunaTrack uses a **named** Firestore database, `lunatrack`, not `(default)` —
`kLunaDatabaseId` in `lib/services/firestore_ref.dart`. `(default)` carries a
single ruleset for every app in a project, so a permissive rule written for an
unrelated app would expose menstrual logs. A named database has its own
independent ruleset. **Never call `FirebaseFirestore.instance`; always use
`lunaFirestore()`.** Whether that database has actually been created is not
verified in this repo.

### Firestore rules

`firestore.rules` is the ruleset for the named database. It is a local file and
**has not been deployed** — nothing in the cloud is enforcing it today. Every
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

Deploying, once the project question above is answered:

```bash
firebase deploy --only firestore:rules --project <the-project-that-owns-lunatrack>
```

## Before publishing

These block a Play release. None of them are done.

- [ ] **Ship the account-deletion purge job.** The app records a deletion
      request at `deletionRequests/{uid}` with a 30-day `purgeAfter`, but no
      scheduled job exists to carry it out — there is no `functions/` directory
      in this repo. **Google Play's in-app account-deletion requirement is
      UNMET until it ships**, and both `PRIVACY_POLICY.md` and
      `docs/account-deletion.md` currently have to disclose that the erasure is
      not automatic. `AccountDeletionService.deleteFirestoreData` is the
      executable specification of what the job must delete (every subcollection
      first, the `users/{uid}` document last).
- [ ] **Deploy `firestore.rules`** to the named `lunatrack` database. Until
      then no access rule is enforced server-side. Verify afterwards in the
      console that the `(default)` database's rules were not touched.
- [ ] **Settle the Firebase project** (see the TODO above) and commit a correct
      `firebase.json`.
- [ ] **Play Data Safety form** — health data must be declared **collected AND
      transmitted**, tied to the user's identity. Declare sexual-activity and
      pregnancy data. "Data is encrypted in transit" is true; do **not** claim
      the cloud copy is end-to-end encrypted — it is stored in plaintext and is
      readable by the operator.
- [ ] **Account deletion URL** — host `docs/account-deletion.md` publicly and
      enter the URL in the Play listing's data-deletion field. Replace the
      placeholder contact address in it and in `PRIVACY_POLICY.md`.
- [ ] **Host `PRIVACY_POLICY.md`** and enter the URL in Play Console → App
      content → Privacy policy.
- [ ] Real upload keystore (release is debug-signed today).
- [ ] Real AdMob app + unit IDs (currently Google **test** IDs).
- [ ] Real Play in-app product id for Premium.
