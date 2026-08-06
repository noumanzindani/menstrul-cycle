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
 *  TODO — PROJECT ID IS NOT SETTLED. NOTHING HERE IS DEPLOYED.
 * =====================================================================
 *
 * No project id appears in this file, anywhere in `functions/`, or in the test
 * suite, and none may be added. The owning Firebase project is an open decision
 * (see CLAUDE.md, "the Firebase project id is NOT settled"): `firebase.json` and
 * `lib/firebase_options.dart` currently name `ride-with-purpose`, a CLIENT's
 * production project reached by an unauthorised action and pending cleanup,
 * while `lib/services/firestore_ref.dart` names `hbgapp-c3c88`.
 *
 * `initializeApp()` with no arguments takes the project from the ambient
 * runtime — `FIREBASE_CONFIG` / `GOOGLE_CLOUD_PROJECT`, which the Cloud
 * Functions runtime sets for you — so this code is correct in whichever project
 * it eventually lands in. The project is chosen ONCE, at deploy time, by the
 * human running:
 *
 *     firebase deploy --only functions --project <THE-DECIDED-PROJECT-ID>
 *
 * Deploying this into `ride-with-purpose` would give it delete authority over a
 * client's production data. Do not deploy until the project decision is made.
 */

const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
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
const LUNA_DATABASE_ID = 'lunatrack';

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
 * Region is deliberately not pinned: it should match the region of the
 * `lunatrack` database once the project is decided, and guessing it here would
 * be a cross-region read on every document this job deletes.
 */
exports.purgeDeletedAccounts = onSchedule(
  {
    schedule: 'every 24 hours',
    timeZone: 'Etc/UTC',
    // The sweep pages through up to 200 accounts' subcollections in one run.
    timeoutSeconds: 540,
    memory: '256MiB',
    retryCount: 0,
  },
  async () => {
    const summary = await purgeExpiredRequests({
      firestore: getFirestore(app, LUNA_DATABASE_ID),
      deleteAuthUser: (uid) => getAuth(app).deleteUser(uid),
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
