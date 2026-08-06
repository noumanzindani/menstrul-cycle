# LunaTrack operator panel

A small server-rendered web panel for the owner of LunaTrack: business metrics,
per-user support lookup, and full browse of a user's synced health records.

Node + Express, Firebase Admin SDK, server-side only. Deployable to Cloud Run.

---

## ⚠️ This service MUST run behind Google Cloud IAP. It is unsafe without it.

There is **no login page**. No password form, no session cookie, no auth
endpoint. Authentication is entirely Google Cloud **Identity-Aware Proxy**: IAP
signs the operator in with their Google account (so their existing Google MFA
becomes the second factor) and forwards a short-lived, Google-signed JWT
assertion. This service verifies that assertion's signature, issuer, audience
and expiry, then checks the email against a one-entry allowlist (`ADMIN_EMAILS`)
as defence in depth.

**If this container is reachable without IAP in front of it, treat it as a
breach.** The Admin SDK bypasses Firestore security rules completely, so a
request that gets past the identity middleware can read every user's menstrual
history. The middleware is the only thing standing there, and it is the *second*
line — IAP is the first. Specifically:

- Deploy with **ingress restricted** so the service is only reachable through
  the load balancer / IAP, never on its raw `*.run.app` URL.
- Deploy with **`--no-allow-unauthenticated`**.
- Do not add a "dev mode" bypass to the deployed configuration. The one that
  exists (`ADMIN_DEV_UNSAFE_IDENTITY`) refuses to work unless
  `FIRESTORE_EMULATOR_HOST` is also set, so it cannot be switched on against a
  real database — keep it that way.

The browser is never given a Firebase credential, the Admin SDK, a client SDK or
a raw Firestore handle. It receives HTML this process rendered, with a CSP of
`default-src 'none'` and no JavaScript at all.

---

## What the panel can and cannot see

**It can see, and does show:**

- Every account in Firebase Auth: uid, email, created, last seen, disabled.
- Aggregate counts: total accounts, new per day/week, 7- and 28-day active,
  total logged days across all accounts, accounts with synced settings, device
  cursor records, deletion markers, pending deletion requests.
- Per account: document counts, earliest and latest logged date, device list
  with pull cursors, settings sync timestamps, deletion state.
- Per account, behind an audited and reason-gated door: **the full content of
  every synced day** — flow, symptoms, sexual activity, cervical mucus, mood,
  free-text notes, BBT, OPK/LH, medications taken, lifestyle habits, numeric
  metrics including weight, plus per-day created/updated/synced timestamps and
  the writing device id.

**It cannot see:**

- Anything the app never syncs. Reminders, the medications table and
  `PeriodEntries` are deliberately not synced and exist only on the device.
- Anything on a **local-only** install (the offline hatch, or a user who never
  signed in). Nothing about them reaches Firestore, so nothing about them
  reaches here.
- The content of a **deleted** day. Only the deletion marker (a date) survives.
- Predictions, cycle day, phase or fertility state. Those are computed by the
  app's own Dart services from local data and are deliberately not
  re-implemented here.

**It cannot do:**

- Write anything to health data. The Firestore handle every view receives is
  wrapped so that `set`, `update`, `delete`, `create`, `add`, `batch`,
  `bulkWriter`, `runTransaction` and `recursiveDelete` all throw before reaching
  the network — including via `snapshot.ref`. The **only** writer in the process
  is the audit log. An operator write to somebody's menstrual log would be
  unfalsifiable from the user's side, which is why the guard is structural and
  not a convention.
- Search across users on any health field. There is no "find everyone who logged
  X". Lookups are exact, by email or uid, and record browse is per-uid only.

---

## The audit log

Every view of a specific account is written to the top-level `adminAudit`
collection **before** the content is fetched, and the read is awaited — so a
failed audit write means **no records are read at all** (HTTP 503). Record
browse additionally requires a free-text reason typed by the operator; an empty
one is refused before anything is read.

Each record holds `actor` (the verified operator email), `targetUid`, `view`,
`reason`, `path` and a server-stamped `at`. Documents get auto-ids and are
written with `.create()`, so no call can overwrite an earlier record, and the
module exposes no update or delete.

`firestore.rules` has **no `match /{document=**}` catch-all**, so a path that no
rule names is denied to every client. `adminAudit` is named by no rule.
App clients therefore cannot read it, list it or forge entries — and **the panel
needs zero changes to `firestore.rules`**, which is why that file is byte-for-byte
unchanged and all 29 existing emulator tests keep their exact meaning. The suite
asserts the denial rather than assuming it.

---

## Environment variables

| Variable | Required | Meaning |
|---|---|---|
| `LUNATRACK_PROJECT_ID` | **yes** | Firebase/GCP project id. `GOOGLE_CLOUD_PROJECT` is accepted as a fallback (Cloud Run sets it). **There is no default — see the TODO below.** |
| `ADMIN_EMAILS` | **yes** | Comma-separated allowlist. One entry for a solo operator. Compared case-insensitively. |
| `IAP_AUDIENCE` | **yes** (unless the emulator bypass is active) | The IAP JWT audience. Load balancer: `/projects/PROJECT_NUMBER/global/backendServices/BACKEND_SERVICE_ID`. Cloud Run direct IAP: `/projects/PROJECT_NUMBER/locations/REGION/services/SERVICE_NAME`. |
| `LUNATRACK_DATABASE_ID` | no (`lunatrack`) | The **named** Firestore database. Never `(default)` — see below. |
| `PORT` | no (`8080`) | Cloud Run sets this. |
| `ADMIN_PAGE_SIZE` | no (`25`) | Roster rows per page. |
| `ADMIN_MAX_ROSTER_SWEEP` | no (`50000`) | Cap on accounts paged through for the dashboard. Beyond it the totals are reported as truncated rather than silently wrong. |
| `ADMIN_DEV_UNSAFE_IDENTITY` | no | **Local emulator only.** Skips IAP verification and pretends this email is the operator. Refuses to work unless `FIRESTORE_EMULATOR_HOST` is also set; startup fails loudly otherwise. |

### TODO — the owning Firebase project is not settled

Nothing here hardcodes a project id, on purpose. `CLAUDE.md` records that
`lib/services/firestore_ref.dart` names one project, the untracked root
`firebase.json` names a **different, unrelated production project**
(`ride-with-purpose`), and the owner has an open decision about moving LunaTrack
to a dedicated project. It is also unverified whether the named `lunatrack`
database has actually been created. **Settle that before deploying**, then set
`LUNATRACK_PROJECT_ID` explicitly.

The panel reads the **named** database `lunatrack` (`kLunaDatabaseId`), not
`(default)`, for the same reason the app does: a `(default)` database carries one
ruleset for every app in the project. Pointing this at `(default)` would read a
different database and quietly report zeros.

---

## Running locally against the emulator

Requires Node 20+, a JDK 21+ (for the emulators) and the Firebase CLI.

```bash
cd admin
npm install                      # firebase-admin + express only

# the test suite (Firestore + Auth emulators, project demo-lunatrack)
./test/run.sh

# the suite plus the mutation check that proves each test discriminates
./test/run.sh --mutants
```

To click around the panel by hand against the emulator:

```bash
cd admin
export JAVA_HOME="$(/usr/libexec/java_home -v 21+)"   # macOS; skip if java is already 21+
firebase emulators:exec --only firestore,auth --project demo-lunatrack \
  --config ./firebase.json \
  'LUNATRACK_PROJECT_ID=demo-lunatrack \
   ADMIN_EMAILS=you@example.com \
   ADMIN_DEV_UNSAFE_IDENTITY=you@example.com \
   node src/server.js'
```

Then open <http://localhost:8080>. The emulator starts empty, so seed some
accounts and days first (see `test/support.mjs` for the exact document shapes).

Note `admin/firebase.json` is the panel's **own** emulator config on its own
ports (Firestore 8099, Auth 9098) so it can run alongside `firebase_test/run.sh`
(Firestore 8098). The repo's untracked root `firebase.json` is not touched by
anything here.

---

## Deploying — steps the owner runs, personally

Nothing in this repo deploys anything, and nothing here has ever contacted a
remote Firebase project. These are the commands **you** run, after deciding
which project LunaTrack belongs in.

1. **Settle the project.** Resolve the project-id TODO above. Confirm the named
   `lunatrack` Firestore database exists in that project.

2. **Create a runtime service account** with the least privilege that works:
   - `roles/datastore.viewer` — reading Firestore.
   - `roles/firebaseauth.viewer` — `listUsers` / `getUser`.
   - plus write access to the `adminAudit` collection. Firestore IAM is not
     collection-scoped, so in practice this means `roles/datastore.user`. If you
     want reads to stay genuinely read-only at the IAM layer, put the audit log
     in a second Firestore database and grant per-database roles.

3. **Build and deploy to Cloud Run**, private:

   ```bash
   gcloud run deploy lunatrack-admin \
     --source admin \
     --region YOUR_REGION \
     --project YOUR_PROJECT \
     --service-account lunatrack-admin@YOUR_PROJECT.iam.gserviceaccount.com \
     --no-allow-unauthenticated \
     --ingress internal-and-cloud-load-balancing \
     --set-env-vars LUNATRACK_PROJECT_ID=YOUR_PROJECT,ADMIN_EMAILS=you@example.com
   ```

   `IAP_AUDIENCE` is deliberately not set yet — you do not know it until IAP
   exists.

4. **Put IAP in front of it.** Either enable IAP directly on the Cloud Run
   service, or front it with an external HTTPS load balancer with a serverless
   NEG and enable IAP on the backend service. Grant
   `roles/iap.httpsResourceAccessor` to **your account only**.

5. **Set the audience and redeploy:**

   ```bash
   gcloud run services update lunatrack-admin --region YOUR_REGION \
     --update-env-vars IAP_AUDIENCE=/projects/PROJECT_NUMBER/global/backendServices/BACKEND_ID
   ```

6. **Verify the door before trusting it.** From a machine with no IAP session,
   `curl` the service's direct URL. You must get a Google sign-in redirect or a
   403 from Cloud Run — never a page from this app. Then sign in as a Google
   account that is *not* in `ADMIN_EMAILS` and confirm you get
   `403 Not an authorised operator`.

7. **Check the audit log works** before doing any real support work: open one
   account's records, then confirm an `adminAudit` document appeared with your
   email and your reason.

---

## Cost notes

Statistics are `count()` aggregations, never document sweeps. At 100k accounts
with ~400 days each, a sweep that reads every document to count them is roughly
40M reads — about **$24 per dashboard refresh**. The same numbers via `count()`
bill about one read per 1000 documents counted: ~40k reads, about **$0.024**.
Any metric added to the dashboard must be expressible as an aggregation.

The account roster comes from Firebase Auth `listUsers()`, which costs no
Firestore reads at all and touches no health record.

## Indexes

**No composite index is required, and there is no `firestore.indexes.json`.**
Every query either aggregates with `count()` (no ordering) or orders and filters
on the `date` field of `dailyLogs`/`deletions`, which Firestore's automatic
single-field indexes already cover in both directions.

One measured constraint drove that design: **Firestore has no descending key
index.** `orderBy(FieldPath.documentId(), 'desc')` — and `limitToLast()` with an
ascending key order, which the client implements as a reversed scan — both fail
with `FAILED_PRECONDITION: Firestore does not support descending key scans`.
Newest-first paging therefore orders on the `date` *field* rather than the
document id, even though `syncDocId` makes the id the same value.

The caveat, which the records page states on screen: a Firestore order filter
silently excludes documents that lack the ordered field, so a `dailyLogs`
document written without `date` would be invisible to the browse view. The page
shows the collection's true `count()` alongside the page so a shortfall is
visible rather than silent.

## Known gaps

- The **account-deletion purge job does not exist** (see `CLAUDE.md`). Accounts
  with a `deletionRequests/{uid}` marker still have all their cloud data. The
  panel flags them loudly on every view, but it cannot make the erasure real.
- `firestore.rules` is **not deployed**. That does not affect this panel (the
  Admin SDK bypasses rules), but it does mean the `adminAudit` collection's
  client-side inaccessibility is only guaranteed once the rules are live.
- Audit records are never pruned. That is deliberate — but decide a retention
  policy before the collection grows.
