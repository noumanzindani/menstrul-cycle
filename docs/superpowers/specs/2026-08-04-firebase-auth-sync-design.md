# Firebase Auth + Firestore sync — design

**Date:** 2026-08-04
**Branch:** `feat/firebase-auth-sync` (branched from `feat/weight-and-diary`, which carries schema v4)
**Status:** approved design, pending implementation plan

---

## 1. Why this exists, and what it changes

LunaTrack shipped on an explicit thesis, stated at the top of `CLAUDE.md`:

> "$0 running cost" and "privacy" are the same decision → 100% on-device data, no
> backend, no account, no network sync.

**This design deliberately reverses that.** The owner wants user accounts and
cross-device sync, and chose plaintext Firestore storage over end-to-end encryption
after the trade-off was presented. That is a product decision, not an oversight, and
it is recorded here so nobody later "fixes" it back.

Consequences accepted:

- Menstrual health records leave the device and are readable by anyone with Firebase
  console access to the project, or by anyone who exploits a mistake in the security
  rules.
- `PRIVACY_POLICY.md` and the Play Data Safety declaration become materially false
  until rewritten. Rewriting them is **in scope for this work**, not a follow-up.
- `CLAUDE.md`'s core-thesis paragraph must be rewritten in the same change.

### Goals

1. Email/password accounts, required at first launch.
2. A user's `DailyLogs` and `AppSettings` follow them to a new device.
3. The app remains fully usable offline once signed in.
4. One user's data is unreadable by any other user.

### Non-goals (explicitly cut)

Google / Apple / anonymous sign-in; social or sharing features; server-side analytics
over log content; Cloud Functions; encrypted-blob cloud backup; multi-user or
partner-sharing accounts; web or desktop clients; syncing `Reminders`, `Medications`,
or `PeriodEntries` (see §4.3).

---

## 2. Firebase configuration

| Item | Value | Note |
|---|---|---|
| Project | `hbgapp-c3c88` ("HBGapp") | Shared with 4 unrelated products |
| Firestore database | **named** `lunatrack` | **Not** `(default)` — see §2.1 |
| Android app | `com.lunatrack.app` | Must match `applicationId`, not the `com.example.menstrul_track` namespace |
| Auth provider | Email/Password | Enable in console. **Do not disable other providers** — provider settings are project-wide, and the other four apps may depend on them |
| Region | Same location as the project's existing `(default)` database | Read it off the console before creating; fixed at creation and cannot be changed later |

### 2.1 Why a named database, not `(default)`

`hbgapp-c3c88` already hosts 9 registered apps across 4 unrelated products
(HabitBeGone, habitbegone_admin, school_managment, pocket_change).

Two project-wide facts drove this decision:

- **Firestore's `(default)` database has exactly one ruleset for the entire project.**
  A permissive clause written for any other app — the common
  `match /{document=**} { allow read: if request.auth != null; }` — would expose
  LunaTrack's menstrual logs to every signed-in user of all four other products.
  A **named** database carries its own independent ruleset, removing that coupling.

- **Firebase Auth's user pool is per-project and cannot be partitioned.** LunaTrack
  therefore shares its user list with the other four apps. A `school_managment`
  account can sign into LunaTrack using the same email and password, and will land on
  an empty LunaTrack dataset (rules key on `uid`, so no data leaks). This is an
  accepted residual risk of reusing the project; the only full fix is a dedicated
  Firebase project, which was offered and declined.

**Residual risk, stated plainly:** account enumeration is shared across the five
products. Someone who learns an email is registered in `hbgapp-c3c88` learns nothing
about *which* app it belongs to, but password-reset emails will originate from the
shared project identity. If this later matters, migrating to a dedicated project means
re-creating accounts — it is not a data export.

### 2.2 Flutter wiring for a named database

`FirebaseFirestore.instance` targets `(default)` and **must not be used**. The one
accessor for the whole app:

```dart
// lib/services/firestore_ref.dart
final db = FirebaseFirestore.instanceFor(
  app: Firebase.app(),
  databaseId: 'lunatrack',
);
```

Everything else imports this. A direct `FirebaseFirestore.instance` call anywhere in
`lib/` writes to the wrong database, under the wrong ruleset — an analyzer-visible
mistake worth a lint or a grep in review.

### 2.3 Build changes (Android)

- `android/settings.gradle.kts`: add
  `id("com.google.gms.google-services") version "4.4.2" apply false`
- `android/app/build.gradle.kts`: add `id("com.google.gms.google-services")` to the
  `plugins` block.
- Replace `android/app/google-services.json`. The file currently present belongs to an
  unrelated project (`rwp-ride-with-purpose`, packages `com.apps.rwp.*`) and is stale
  cruft; it is gitignored (`.gitignore:48`) so it was never committed. Delete it and
  drop in the `com.lunatrack.app` file from `hbgapp-c3c88`.
- `minSdk` is already 26 (raised for Health Connect), clearing `cloud_firestore`'s
  floor of 23. **No minSdk change needed.**
- Because `google-services.json` is gitignored, `README.md` must document how a fresh
  clone obtains it, or the project will not build for anyone else.

### 2.4 New dependencies (approved)

`firebase_core`, `firebase_auth`, `cloud_firestore`. Roughly 3–4 MB added to the APK.
No `google_sign_in` (email/password only). No new Dart dev-dependencies; rules tests
need Node + the Firebase emulator (§8.1).

---

## 3. Firestore data model

```
[lunatrack]/users/{uid}
    ├─ (document fields)  { email, createdAt, appSchemaVersion }
    ├─ settings/current   { …AppSettings mirror… , updatedAt }
    └─ dailyLogs/{YYYY-MM-DD}
           { date, flow, symptoms, mood, notes, bbt, opk,
             createdAt, updatedAt, deviceId }
```

**Document ID is the ISO-8601 local date** (`2026-08-04`). This mirrors the existing
`uniqueKeys => [{date}]` constraint on `DailyLogs`, making writes naturally
idempotent — a day cannot be duplicated, and a re-push overwrites cleanly with no
duplicate-detection logic.

Field notes:

- `symptoms` is stored as a **Firestore map**, decoded from the local JSON `TEXT`
  column. Storing it as a raw JSON string would work but forfeits any future ability
  to query it and is opaque in the console.
- `flow` is the `FlowIntensity` **enum index** (`int?`), matching `intEnum` locally.
  Storing the name instead would break silently if the enum is reordered; storing the
  index breaks loudly on an out-of-range value, which the decoder must handle.
- `deviceId` is a stable per-install UUID (generated once, stored in
  `flutter_secure_storage`). It is diagnostic only — it never participates in merge
  decisions.
- No `deleted` field. Deletions are tombstones (§4.4).

### 3.1 Deliberately not synced

`Reminders` are local notification schedules bound to a device's timezone and
notification IDs — syncing them would fire duplicate or wrongly-timed notifications on
a second device. `Medications` and `PeriodEntries` are excluded because
`PeriodEntries` is documented as intentionally unused (activating it would create a
second source of truth for cycle boundaries) and `Medications` has no UI yet.

**Cycles, predictions, and insights are never synced** — `CycleCalculator` derives them
from `DailyLogs`, so they regenerate correctly on any device that has the logs. This is
a direct payoff of the existing "cycles are derived, not stored" decision.

---

## 4. Architecture

### 4.1 Drift stays the source of truth

Every UI read and write continues to go through the existing path. Sync is a mirror
bolted alongside, never in front:

```
UI ──> LogProvider ──> DailyLogRepository ──> drift   (unchanged)
                                                │
                                          SyncService ⇄ Firestore [lunatrack]
```

This is the central architectural choice. Making Firestore the primary store would mean
rewriting every provider and repository, would make the app unusable during a network
stall, and would put a paid dependency in the hot path of logging a symptom. Mirroring
keeps the offline behaviour that already works and confines all new failure modes to
one service.

### 4.2 New files

| File | Responsibility |
|---|---|
| `lib/services/firestore_ref.dart` | The single named-database accessor (§2.2) |
| `lib/services/auth_service.dart` | `signUp`, `signIn`, `signOut`, `sendPasswordReset`, `deleteAccount`. Wraps `FirebaseAuth`; maps `FirebaseAuthException` codes to app-level errors |
| `lib/providers/auth_provider.dart` | `ChangeNotifier` exposing `AuthState { unknown, signedOut, signedIn }`, driven by `authStateChanges()` |
| `lib/services/sync_service.dart` | Push, pull, merge, tombstones, `lastSyncedAt` bookkeeping |
| `lib/services/sync_mapper.dart` | Pure `DailyLog ⇄ Map<String, dynamic>` conversion. Pure so it is unit-testable with no Firebase |
| `lib/screens/auth/sign_in_screen.dart` | Email + password, link to sign-up and reset |
| `lib/screens/auth/sign_up_screen.dart` | Email, password, confirm; inline validation |
| `lib/screens/auth/forgot_password_screen.dart` | Reset-email request + confirmation state |
| `lib/screens/settings/account_section.dart` | Signed-in email, sync status, sign out, delete account |
| `firestore.rules` | §5 |
| `firebase.json`, `.firebaserc` | Rules deploy config, targeting the `lunatrack` database |

### 4.3 Schema v5 migration

`schemaVersion` 4 → 5, following the existing additive `if (from < n)` pattern in
`lib/db/database.dart` (independent `if`s, never `else if`, so a user on v1 runs every
intervening branch):

```dart
if (from < 5) {
  await m.createTable(syncTombstones);
  await m.addColumn(appSettings, appSettings.lastSyncedAt);
}
```

Two additions, both purely additive:

- **`SyncTombstones`** — `date` (unique), `deletedAt`.
- **`AppSettings.lastSyncedAt`** — nullable `DateTime`; null means "never synced", which
  correctly triggers a full initial pull.

`DailyLogs` needs **no new columns**. It already carries `updatedAt`
(`tables.dart:28`), and all three write paths maintain it
(`daily_log_repository.dart:56, 84, 114`). The LWW infrastructure predates this design.

A committed schema snapshot `drift_schemas/drift_schema_v5.json` plus a v4→v5 migration
test joins the existing generated-migration suite.

### 4.4 Deletions use tombstones, not a flag

`DailyLogRepository.deleteForDate` (`:119-122`) performs a hard `DELETE`. A hard-deleted
row is indistinguishable from a row that never existed, so the next pull would happily
resurrect it from the server.

The fix is a separate `SyncTombstones` table rather than a `deleted` boolean on
`DailyLogs`. A boolean would require adding `..where((t) => t.deleted.equals(false))` to
**every existing read path** — repositories, `CycleCalculator` inputs, insights, diary,
PDF export. Missing a single one silently resurfaces deleted days in, for example, a
doctor's report. A tombstone table leaves all existing queries untouched and confines
the new concept to `SyncService`.

`deleteForDate` gains one line: write a tombstone inside the same transaction as the
delete. Push then deletes the remote document and clears the tombstone.

### 4.5 Sync algorithm

Triggered on: sign-in, app resume, and after any local write (debounced ~2s).

```
push:
  local rows WHERE updatedAt > lastSyncedAt  → set() to dailyLogs/{date}
  tombstones                                 → delete() remote doc, then clear tombstone
pull:
  remote docs WHERE updatedAt > lastSyncedAt → merge into drift (§6)
commit:
  lastSyncedAt = max(updatedAt seen)         → only after both halves succeed
```

`lastSyncedAt` advances **only on full success**. A partial failure leaves it untouched,
so the next run re-attempts the same window. Re-pushing an already-pushed day is
harmless because writes are keyed by date and idempotent — the design tolerates
duplicate work but never data loss.

Firestore's own offline persistence stays **enabled** as a network-flakiness buffer, but
it is explicitly *not* the offline story: drift is. The app must work fully offline even
if the Firestore cache is empty.

---

## 5. Security rules — the entire privacy boundary

With plaintext storage, this file is the only thing between one user's menstrual
history and every other account in a five-product Firebase project. It is the most
safety-critical code in the repository.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/lunatrack/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

- `request.auth.uid == userId`, **never** a bare `request.auth != null`. The latter is
  the single most common Firestore vulnerability and, in a shared project, would expose
  data to four other apps' users.
- No public read path exists at any depth.
- Server-side field validation is intentionally omitted: the client is the only writer
  and a malicious user can only corrupt their own data.

---

## 6. Conflict resolution: last-write-wins per day

The merge unit is one day document, compared on `updatedAt`. Later timestamp wins the
whole document.

Field-level merge was considered and rejected. `encodeDayTags` is a full **REPLACE** —
it rebuilds the entire `symptoms` blob from form state — so merging individual tags
from two devices would synthesise a tag set that the user never authored on either
device. Given the blob also carries medication, sex, cervical-mucus, urine, digestion,
skin, and habit keys under reserved prefixes, a bad merge produces a plausible-looking
but fabricated health record. Whole-document LWW can lose an edit; field merge can
invent one. For a health log, losing is safer than inventing.

**Accepted cost:** if the same day is edited offline on two devices, the edit that syncs
later overwrites the other completely. For a single-user tracker, concurrent
same-day multi-device edits are rare. This is a documented v1 limitation, not a bug to
be reported later.

**Clock-skew caveat:** `updatedAt` is written from device time
(`DateTime.now()`), so a device with a badly wrong clock can win or lose merges
incorrectly. Using Firestore `serverTimestamp()` would fix ordering but is unavailable
offline, which is precisely when it is needed. Device time is the accepted trade;
sync must never crash on a future-dated `updatedAt`.

---

## 7. Auth flow, onboarding, and existing installs

### 7.1 Gate

`AuthProvider.state` drives `app_shell`: `unknown` → splash, `signedOut` → sign-in,
`signedIn` → the existing app. Sign-in is required at first launch, per the product
decision.

### 7.2 Existing local data (the upgrade case)

Anyone already running LunaTrack has local logs and no account. On upgrade they hit a
sign-in wall in front of their own data — a bad experience and a plausible one-star
review if handled carelessly.

On the **first successful sign-in or sign-up on a device with existing local rows**,
the app shows an explicit prompt:

> "You have N days logged on this device. Add them to this account?"

Accepting pushes local rows to the new `uid`. Declining leaves them local and untouched
— it must never delete them. Because rows key on date, the merge is the ordinary §6
path with no special case.

### 7.3 Sign-out

Sign-out **must not wipe local drift data** — a user signing out to switch accounts
would otherwise lose everything. Local data persists; the §7.2 prompt handles it if a
different account signs in next.

---

## 8. Compliance work (mandatory, in scope)

Introducing accounts triggers store obligations that did not previously apply:

1. **In-app account deletion** (Google Play User Data policy). Must delete the entire
   `users/{uid}` Firestore subtree *and* the Auth user. Deleting only the Auth user
   orphans the health data — a policy violation and a real privacy failure.
   Client-side recursive subcollection delete is required (no Cloud Functions in scope);
   the flow must be resumable, because a mid-delete crash otherwise leaves an orphaned
   subtree with no signed-in user able to reach it.
2. **Web-accessible deletion URL** — Play requires an off-app deletion request route in
   the store listing.
3. **`PRIVACY_POLICY.md` rewritten.** "No data leaves your device" becomes false the
   moment this ships. Must disclose: what is collected (menstrual and symptom health
   data), that it is transmitted and stored on Google Cloud infrastructure, retention,
   and the deletion route.
4. **Play Data Safety form** updated to declare health data as collected *and*
   transmitted, with the account-deletion route.
5. **`CLAUDE.md` core-thesis paragraph rewritten** to describe the account-based
   architecture, so future contributors are not working from a false premise.
6. **Existing `deleteAllData()`** (`database.dart:53`) must be re-examined: it is
   documented as "the full right-to-erasure path", which stops being true once data
   also lives server-side.

---

## 9. Testing

### 9.1 Security rules (highest value)

Emulator-based tests using `@firebase/rules-unit-testing`, asserting at minimum:

- A signed-in user **can** read and write `users/{ownUid}/dailyLogs/*`.
- A signed-in user **cannot** read `users/{otherUid}/dailyLogs/*` — the cross-tenant
  test that catches the classic mistake.
- An unauthenticated client can read nothing.

### 9.2 Dart tests

- `sync_mapper` round-trip: `DailyLog → Map → DailyLog` preserves every field,
  including an empty `symptoms` blob, a null `flow`, and all reserved tag prefixes.
- Merge logic (pure function over two timestamped records): local-newer, remote-newer,
  equal timestamps, and a future-dated remote `updatedAt`.
- Tombstone behaviour: delete then sync does not resurrect the day.
- v4→v5 migration, added to the existing multi-hop generated-migration suite.
- Auth screens: widget tests against a fake `AuthService` — no network.
- **Regression guard:** the full existing suite (308 tests) must stay green. Sync is
  additive; any existing failure means the mirror leaked into the primary path.

---

## 10. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Rules mistake exposes all users' health data | Critical | `uid == userId`; emulator cross-tenant tests in §9.1 |
| Shared Auth pool with 4 unrelated apps | Medium | Accepted; named DB isolates data. Dedicated project offered and declined |
| A stray `FirebaseFirestore.instance` writes to `(default)` | High | Single accessor in `firestore_ref.dart`; grep in review |
| Concurrent same-day edit loses data | Low | Documented LWW limitation (§6) |
| Required-account wall frustrates existing users | Medium | §7.2 claim-your-data prompt |
| Account deletion leaves orphaned subtree | High | Resumable recursive delete (§8.1) |
| Privacy policy false at ship time | Critical | §8 is in scope, gated before release |
| Wrong `google-services.json` (RWP leftover) | Low | Deleted and replaced in §2.3 |

---

## 11. Open item

The existing `(default)` database ruleset in `hbgapp-c3c88` was **not** audited — doing
so requires setting an active Firebase project, which was deferred until this design was
approved. It does not block implementation, since LunaTrack uses an isolated named
database. It is worth a look regardless: if the other four apps' rules are permissive,
that is someone's live exposure, just not LunaTrack's.
