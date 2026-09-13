'use strict';

/**
 * LunaTrack Cloud Functions — the deployable wiring.
 *
 * All decision logic lives in `./purge.js`, which takes its Firestore handle,
 * its Auth deleter, its clock and its logger as arguments and imports nothing.
 * This file is the only place that touches the Firebase SDKs, and it is
 * deliberately thin: everything here is configuration, and configuration is the
 * part that cannot be covered by the emulator suite.
 *
 * =====================================================================
 *  DEPLOYED to `teddy-2-20649` (project settled 2026-08-12). This job has
 *  DELETE authority over Firestore documents, Storage objects and Auth
 *  accounts. Read the two hazards below before changing anything here.
 * =====================================================================
 *
 * Still no project id appears in this file, anywhere in `functions/`, or in the
 * test suite, and none may be added. `initializeApp()` with no arguments takes
 * the project from the ambient runtime — `FIREBASE_CONFIG` /
 * `GOOGLE_CLOUD_PROJECT`, which the Cloud Functions runtime sets for you — so
 * this code stays correct if LunaTrack later moves to a dedicated project. The
 * project is chosen at deploy time, by the human running:
 *
 *     firebase deploy --only functions:lunatrack:purgeDeletedAccounts \
 *       --project <THE-PROJECT-ID>
 *
 * HAZARD 1 — never a BARE `--only functions` here. `teddy-2-20649` is shared
 * with an unrelated donations app that has 19 live functions. An unfiltered
 * functions deploy prunes everything absent from this source tree and would
 * delete all of them. The `lunatrack` codebase in `firebase.json` is the second
 * guard; the name filter above is the first. Use both.
 *
 * HAZARD 2 — `deleteAuthUser` below is PROJECT-WIDE. Firebase Auth is not
 * per-database, so the Auth pool is shared with that same donations app. A
 * person who uses both apps and deletes their LunaTrack account loses the
 * identity the other app knows them by. Deleting the Auth account is what makes
 * "delete my account" honest, so the fix is not to skip it — it is a dedicated
 * project, which remains an open owner decision. Until then this is an accepted,
 * documented risk, not an oversight.
 */

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');

const { purgeExpiredRequests } = require('./purge');

/**
 * The NAMED Firestore database LunaTrack owns — `kLunaDatabaseId` in
 * `lib/services/firestore_ref.dart`.
 *
 * This is a DATABASE id, not a project id, and it must be stated: Firestore's
 * `(default)` database carries ONE ruleset for every app in a project, which is
 * why LunaTrack uses a named database in the first place. `getFirestore(app)`
 * would silently target `(default)` and this job would then sweep an empty
 * database and report success while every user's data survived.
 */
const LUNA_DATABASE_ID = 'lunatrack-db';

/**
 * The DEDICATED Cloud Storage bucket holding uploaded media —
 * `kLunaStorageBucket` in `lib/services/storage_ref.dart`.
 *
 * Read from the environment (`functions/.env`), not hardcoded, because a bucket
 * name embeds the project id and no project id may appear in this directory --
 * that rule outlives the project decision, so this job stays correct if
 * LunaTrack moves to a dedicated project.
 *
 * Deliberately NOT defaulted to the project's default bucket. A default would
 * make a misconfigured deploy sweep the wrong bucket and report success while
 * every user's photographs survived — the same failure `LUNA_DATABASE_ID` above
 * exists to prevent, with a worse payload. Absent, the purge fails loudly and
 * the markers are retained for the next run.
 */
const LUNA_STORAGE_BUCKET = process.env.LUNA_STORAGE_BUCKET;

const app = initializeApp();

/**
 * The scheduled account-deletion purge.
 *
 * Erases every account whose 30-day grace window has elapsed: the Firestore
 * subtree under `users/{uid}`, then the Firebase Auth account, then the
 * `deletionRequests/{uid}` marker. See the header of `./purge.js` for the
 * ordering guarantees and for why the deadline is re-derived server-side.
 *
 * Daily is the right cadence: the grace window is 30 days, so a purge that runs
 * up to 24 hours after the deadline is well inside what the user was told, and
 * an hourly schedule would only add invocations that find an empty queue.
 *
 * Retries are left off. The sweep is idempotent and resumable, so a failed run
 * costs at most one day's delay and the next run picks the same markers up —
 * whereas an automatic retry storm against a Firestore outage burns quota
 * re-attempting deletes that will keep failing.
 *
 * Region is pinned to `us-central1`, which is inside `nam5` — the multi-region
 * the `lunatrack-db` database actually lives in (verified 2026-09-14). Leaving
 * it unpinned happens to default to the same place today, but a default is not
 * a decision: an unpinned function that later moves would do a cross-region read
 * on every document it deletes, silently and at cost.
 */
exports.purgeDeletedAccounts = onSchedule(
  {
    schedule: 'every 24 hours',
    timeZone: 'Etc/UTC',
    region: 'us-central1',
    // The sweep pages through up to 200 accounts' subcollections in one run.
    timeoutSeconds: 540,
    memory: '256MiB',
    retryCount: 0,
  },
  async () => {
    const summary = await purgeExpiredRequests({
      firestore: getFirestore(app, LUNA_DATABASE_ID),
      deleteAuthUser: (uid) => getAuth(app).deleteUser(uid),
      // The DEDICATED media bucket, never the project default — the same
      // argument as LUNA_DATABASE_ID one line up. Storage rulesets are
      // per-bucket, and this project's default bucket is shared with unrelated
      // apps, so LunaTrack's media lives in a bucket it alone governs.
      // `LUNA_STORAGE_BUCKET` is read from the environment for the same reason
      // no project id is hardcoded anywhere in this directory.
      deleteStoragePrefix: (prefix) =>
        getStorage(app)
          .bucket(LUNA_STORAGE_BUCKET)
          .deleteFiles({ prefix, force: true }),
      logger,
    });

    // Surface a bad sweep as a failed invocation so it shows up in the
    // function's error rate rather than only inside a log line nobody reads.
    if (summary.failed.length > 0) {
      throw new Error(
        `account purge: ${summary.failed.length} of ${summary.found} ` +
          'account(s) failed to purge; markers are retained for the next run',
      );
    }
  },
);
