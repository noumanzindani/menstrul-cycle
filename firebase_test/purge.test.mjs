// Emulator tests for the scheduled account-deletion purge (`functions/purge.js`).
//
// Run with:  firebase_test/purge_run.sh
//
// The purge is the half of "delete my account" that nothing in the app can do:
// the client only ever writes a marker at `deletionRequests/{uid}`, and until
// this job runs, cloud data is never actually erased. Google Play's in-app
// account-deletion requirement is unmet without it.
//
// What is asserted here was read out of the code, not out of a plan. The
// executable specification is `lib/services/account_deletion_service.dart`:
//
//   deletionRequests/{uid}          the work queue  (uid, requestedAt, purgeAfter)
//   users/{uid}/dailyLogs/{date}    \
//   users/{uid}/settings/current     |  AccountDeletionService.subcollections,
//   users/{uid}/deletions/{date}     |  swept FIRST
//   users/{uid}/devices/{deviceId}  /
//   users/{uid}                     the root document, deleted LAST
//
// Two of those orderings are load-bearing and are tested as such:
//
//   * subcollections before the root document — so a crash leaves the root
//     present and the job is resumable (`deleteFirestoreData`'s doc comment);
//   * everything before the marker — the marker IS the work queue entry, so
//     deleting it early would strand whatever had not finished, permanently.
//
// Each test's discriminating power is proved separately: `purge_mutation_check.mjs`
// re-runs this whole suite against copies of `purge.js` with one guarantee
// removed at a time and fails if the corresponding test still passes.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { after, afterEach, before, beforeEach, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { clearData, seed } from './emulator.mjs';
import {
  authUserExists,
  clearAuth,
  createAuthUser,
  deleteAuthUser,
  docExists,
  firestore,
  firestoreFailingOn,
  idsIn,
  purge,
  PURGE_MODULE,
  recordingLogger,
} from './purge_emulator.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const DART_SPEC = path.join(
  here,
  '..',
  'lib',
  'services',
  'account_deletion_service.dart',
);

/**
 * The deployable wiring under test.
 *
 * `LUNA_WIRING_FILE` lets `purge_mutation_check.mjs` point the two structural
 * tests below at a mutated copy of `functions/index.js`, so they are proved to
 * discriminate the same way every other test here is. Same trick as
 * `LUNA_PURGE_MODULE` and, in the rules suite, `LUNA_RULES_FILE`.
 */
const WIRING =
  process.env.LUNA_WIRING_FILE ?? path.join(here, '..', 'functions', 'index.js');

const DAY_MS = 24 * 60 * 60 * 1000;
const inDays = (days) => new Date(Date.now() + days * DAY_MS);

/**
 * The subcollection list and the grace window, read out of the Dart file rather
 * than retyped.
 *
 * `AccountDeletionService.subcollections` is public *specifically* so tests can
 * enumerate it instead of duplicating the literal, and its doc says adding a
 * subcollection without adding it there silently leaves data behind. The JS
 * purge cannot import Dart, so it necessarily restates both values — and this
 * parser is what makes that restatement checkable instead of hopeful.
 */
function dartSpec() {
  const source = fs.readFileSync(DART_SPEC, 'utf8');

  const listMatch = source.match(/static const subcollections = \[([^\]]*)\]/);
  assert.ok(listMatch, 'could not find `subcollections` in the Dart spec');
  const subcollections = [...listMatch[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
  assert.ok(subcollections.length > 0, 'parsed an empty subcollection list');

  const graceMatch = source.match(
    /static const Duration graceWindow = Duration\(days: (\d+)\)/,
  );
  assert.ok(graceMatch, 'could not find `graceWindow` in the Dart spec');

  return { subcollections, graceWindowDays: Number(graceMatch[1]) };
}

const SPEC = dartSpec();

/** A day document shaped like `sync_mapper.dart`'s `dailyLogToMap`. */
const dayLog = {
  date: '2026-08-04',
  flow: 2,
  notes: 'cramps all morning',
  updatedAt: Date.now(),
};

/** One document in every subcollection the Dart spec names, plus the root doc. */
async function seedUserData(uid, { rootDocument = true } = {}) {
  await seed(`users/${uid}/dailyLogs/2026-08-04`, dayLog);
  await seed(`users/${uid}/settings/current`, { defaultCycleLength: 28 });
  await seed(`users/${uid}/deletions/2026-07-01`, { date: '2026-07-01' });
  await seed(`users/${uid}/devices/device-1`, { logsCursor: inDays(-1) });
  // Any subcollection the Dart spec grows beyond the four above still gets
  // seeded, so a purge that does not know about it fails this file.
  for (const name of SPEC.subcollections) {
    await seed(`users/${uid}/${name}/spec-probe`, { seeded: true });
  }
  // In production this document usually does NOT exist — `SyncService` only
  // ever writes subcollections (see the council's measured finding). Both cases
  // are covered; this is the one where it does.
  if (rootDocument) await seed(`users/${uid}`, { createdAt: inDays(-90) });
}

/**
 * A pending deletion request. Defaults to one that is genuinely due.
 *
 * [bodyUid] exists so a test can make the client-written `uid` FIELD disagree
 * with the document id, which `firestore.rules` forbids but the Admin SDK path
 * never checks.
 */
async function seedRequest(
  uid,
  { requestedAt = inDays(-31), purgeAfter = inDays(-1), bodyUid = uid } = {},
) {
  const marker = { uid: bodyUid };
  if (requestedAt !== null) marker.requestedAt = requestedAt;
  if (purgeAfter !== null) marker.purgeAfter = purgeAfter;
  await seed(`deletionRequests/${uid}`, marker);
}

/** A whole account queued for deletion: data, marker and an Auth account. */
async function seedExpiredAccount(uid, options = {}) {
  await seedUserData(uid, options);
  await seedRequest(uid, options);
  await createAuthUser(uid);
}

/** Runs the sweep with the production wiring unless a test overrides a part. */
const run = (overrides = {}) =>
  purge.purgeExpiredRequests({
    firestore,
    deleteAuthUser,
    logger: recordingLogger(),
    ...overrides,
  });

/** Asserts nothing about [uid] was touched. */
async function assertAccountIntact(uid) {
  for (const name of SPEC.subcollections) {
    assert.notDeepEqual(
      await idsIn(`users/${uid}/${name}`),
      [],
      `users/${uid}/${name} was emptied but should not have been`,
    );
  }
  assert.equal(await docExists(`users/${uid}`), true, 'root document deleted');
  assert.equal(
    await docExists(`deletionRequests/${uid}`),
    true,
    'the marker was deleted',
  );
  assert.equal(await authUserExists(uid), true, 'the Auth user was deleted');
}

/** Asserts every trace of [uid] is gone. */
async function assertAccountErased(uid) {
  for (const name of SPEC.subcollections) {
    assert.deepEqual(
      await idsIn(`users/${uid}/${name}`),
      [],
      `users/${uid}/${name} survived the purge`,
    );
  }
  assert.equal(
    await docExists(`users/${uid}`),
    false,
    'the users/{uid} root document survived the purge',
  );
  assert.equal(
    await docExists(`deletionRequests/${uid}`),
    false,
    'the deletion marker survived the purge',
  );
  assert.equal(
    await authUserExists(uid),
    false,
    'the Firebase Auth user survived the purge',
  );
}

before(async () => {
  await clearData();
  await clearAuth();
});
beforeEach(async () => {
  await clearData();
  await clearAuth();
});
afterEach(async () => {
  await clearData();
  await clearAuth();
});
after(async () => {
  await clearData();
  await clearAuth();
});

describe('the expired queue', () => {
  test('a marker past its deadline erases the whole account', async () => {
    await seedExpiredAccount('alice');

    const summary = await run();

    assert.equal(summary.found, 1);
    assert.equal(summary.purged, 1);
    assert.deepEqual(summary.skipped, []);
    assert.deepEqual(summary.failed, []);
    await assertAccountErased('alice');
  });

  test('a marker still inside the grace window is not collected at all', async () => {
    // The user is mid-grace-window and can still cancel. Purging here destroys
    // data the user was promised 30 days to change their mind about.
    await seedExpiredAccount('alice', {
      requestedAt: inDays(-2),
      purgeAfter: inDays(28),
    });

    const summary = await run();

    assert.equal(summary.found, 0, 'a future deadline must not be queried up');
    assert.equal(summary.purged, 0);
    await assertAccountIntact('alice');
  });

  test('an empty queue is a clean no-op', async () => {
    const summary = await run();

    assert.deepEqual(summary, {
      found: 0,
      purged: 0,
      skipped: [],
      failed: [],
    });
  });

  test('the sweep is limited, and takes the oldest deadlines first', async () => {
    // A limit is what keeps one invocation bounded; ordering by `purgeAfter` is
    // what stops the same head-of-queue accounts being re-picked forever while
    // an older one starves.
    await seedExpiredAccount('oldest', {
      requestedAt: inDays(-40),
      purgeAfter: inDays(-9),
    });
    await seedExpiredAccount('middle', {
      requestedAt: inDays(-35),
      purgeAfter: inDays(-5),
    });
    await seedExpiredAccount('newest', {
      requestedAt: inDays(-31),
      purgeAfter: inDays(-1),
    });

    const summary = await run({ limit: 2 });

    assert.equal(summary.found, 2);
    assert.equal(summary.purged, 2);
    await assertAccountErased('oldest');
    await assertAccountErased('middle');
    await assertAccountIntact('newest');
  });

  test('an unrelated account is untouched', async () => {
    await seedExpiredAccount('alice');
    await seedUserData('bob');
    await createAuthUser('bob');

    await run();

    await assertAccountErased('alice');
    for (const name of SPEC.subcollections) {
      assert.notDeepEqual(await idsIn(`users/bob/${name}`), []);
    }
    assert.equal(await docExists('users/bob'), true);
    assert.equal(await authUserExists('bob'), true);
  });
});

describe('the server-side re-derivation', () => {
  test('a purgeAfter that disagrees with requestedAt + graceWindow does not purge early', async () => {
    // THE reason this check exists: the Admin SDK bypasses security rules, so
    // the 29-31 day bounds `firestore.rules` puts on `purgeAfter` do not run on
    // this path at all. A marker that got a past `purgeAfter` past the rules —
    // a rules regression, a console edit, an admin-SDK write, a future app
    // version — must not be able to trigger an immediate irreversible purge.
    await seedExpiredAccount('alice', {
      requestedAt: inDays(-1),
      purgeAfter: inDays(-1),
    });

    const summary = await run();

    assert.equal(summary.found, 1, 'the marker should still be collected');
    assert.equal(summary.purged, 0, 'it must NOT have been purged');
    assert.deepEqual(
      summary.skipped.map((entry) => entry.reason),
      ['not-due'],
    );
    await assertAccountIntact('alice');
  });

  test('a marker with no requestedAt is never purged', async () => {
    // `requestedAt` is server-stamped and is the only trustworthy basis for the
    // deadline. With it missing or malformed the window cannot be verified, and
    // an unverifiable irreversible delete fails CLOSED: the data stays, the
    // marker stays, and the skip is logged for a human.
    await seedExpiredAccount('alice', { requestedAt: null });

    const summary = await run();

    assert.equal(summary.found, 1);
    assert.equal(summary.purged, 0);
    assert.deepEqual(
      summary.skipped.map((entry) => entry.reason),
      ['unverifiable-requestedAt'],
    );
    await assertAccountIntact('alice');
  });

  test('a requestedAt of the wrong type is never purged', async () => {
    await seedExpiredAccount('alice', { requestedAt: 'last tuesday' });

    const summary = await run();

    assert.equal(summary.purged, 0);
    assert.deepEqual(
      summary.skipped.map((entry) => entry.reason),
      ['unverifiable-requestedAt'],
    );
    await assertAccountIntact('alice');
  });

  test('the document id decides whose account is purged, not the uid field', async () => {
    // `firestore.rules` enforces `request.resource.data.uid == uid` on create,
    // but the Admin SDK does not evaluate rules, so this job cannot lean on it.
    // If the body's `uid` were trusted, a single marker would be a request to
    // erase SOMEONE ELSE's account — the most destructive bug this file could
    // have, and one that reads as harmless.
    await seedExpiredAccount('alice', { bodyUid: 'victim' });
    await seedUserData('victim');
    await createAuthUser('victim');

    const summary = await run();

    assert.equal(summary.purged, 1);
    await assertAccountErased('alice');
    for (const name of SPEC.subcollections) {
      assert.notDeepEqual(
        await idsIn(`users/victim/${name}`),
        [],
        `users/victim/${name} was erased by someone else's marker`,
      );
    }
    assert.equal(await docExists('users/victim'), true);
    assert.equal(await authUserExists('victim'), true);
  });

  test('a marker exactly at requestedAt + graceWindow is due', async () => {
    // The boundary is inclusive: the user was promised erasure after the
    // window, and an off-by-one here silently strands every account whose
    // deadline lands on the sweep instant.
    const requestedAt = inDays(-SPEC.graceWindowDays);
    await seedExpiredAccount('alice', { requestedAt, purgeAfter: inDays(-1) });

    const summary = await run({
      now: new Date(requestedAt.getTime() + SPEC.graceWindowDays * DAY_MS),
    });

    assert.equal(summary.purged, 1);
    await assertAccountErased('alice');
  });
});

describe('the subtree sweep', () => {
  test('every subcollection the Dart spec names is emptied', async () => {
    // Seeded from `AccountDeletionService.subcollections` itself, so adding a
    // subcollection there and forgetting the purge fails HERE rather than
    // leaving menstrual data on the server after an erasure request.
    await seedExpiredAccount('alice');
    for (const name of SPEC.subcollections) {
      assert.notDeepEqual(await idsIn(`users/alice/${name}`), [], name);
    }

    await run();

    for (const name of SPEC.subcollections) {
      assert.deepEqual(
        await idsIn(`users/alice/${name}`),
        [],
        `users/alice/${name} still holds documents after the purge`,
      );
    }
  });

  test('a subcollection larger than one page is fully emptied', async () => {
    // A long-running user has thousands of days. A single unpaged read is both
    // a memory risk and, with a naive implementation, a partial delete that
    // leaves health data behind while reporting success.
    await seedExpiredAccount('alice');
    const writes = firestore.batch();
    for (let i = 0; i < 320; i += 1) {
      const day = String(i).padStart(3, '0');
      writes.set(firestore.doc(`users/alice/dailyLogs/2025-01-${day}`), dayLog);
    }
    await writes.commit();

    await run();

    assert.deepEqual(await idsIn('users/alice/dailyLogs'), []);
  });

  test('the root users/{uid} document is deleted', async () => {
    // Firestore does not cascade: deleting subcollection documents leaves the
    // parent, and deleting the parent leaves the subcollections.
    await seedExpiredAccount('alice');
    assert.equal(await docExists('users/alice'), true);

    await run();

    assert.equal(await docExists('users/alice'), false);
  });

  test('an account with no root document purges anyway', async () => {
    // The normal production shape: `SyncService` only ever writes
    // subcollections, so `users/{uid}` usually does not exist.
    await seedExpiredAccount('alice', { rootDocument: false });
    assert.equal(await docExists('users/alice'), false);

    const summary = await run();

    assert.equal(summary.purged, 1);
    await assertAccountErased('alice');
  });

  test('the marker itself is deleted — the Dart sweep does not do it', async () => {
    // `deleteFirestoreData` deletes `users/{uid}` and its subcollections and
    // NOTHING else. The marker is a top-level document outside that subtree, so
    // a purge that merely reproduced the Dart method would leave a permanent
    // record that this account asked to be deleted — and would re-pick it every
    // sweep, forever.
    await seedExpiredAccount('alice');

    await run();

    assert.equal(await docExists('deletionRequests/alice'), false);
    assert.deepEqual(await idsIn('deletionRequests'), []);
  });

  test('the Firebase Auth account is deleted', async () => {
    await seedExpiredAccount('alice');
    assert.equal(await authUserExists('alice'), true);

    await run();

    assert.equal(await authUserExists('alice'), false);
  });

  test('an account whose Auth user is already gone still purges', async () => {
    // Idempotency: a re-run after a crash, or a user who deleted themselves.
    await seedUserData('alice');
    await seedRequest('alice');

    const summary = await run();

    assert.equal(summary.purged, 1);
    assert.deepEqual(summary.failed, []);
    await assertAccountErased('alice');
  });
});

describe('crash safety', () => {
  test('a crash mid-sweep leaves the root document, the marker and the Auth user', async () => {
    // The resumability property `deleteFirestoreData` documents. What must
    // survive an interrupted run is the evidence that the job is unfinished:
    // the marker (the queue entry) above all.
    await seedExpiredAccount('alice');
    const stopAt = SPEC.subcollections[SPEC.subcollections.length - 1];

    const summary = await run({
      firestore: firestoreFailingOn((p) => p.endsWith(`/${stopAt}`)),
    });

    assert.equal(summary.purged, 0);
    assert.equal(summary.failed.length, 1);
    assert.deepEqual(
      await idsIn(`users/alice/${SPEC.subcollections[0]}`),
      [],
      'the sweep should have got as far as the first subcollection',
    );
    assert.notDeepEqual(
      await idsIn(`users/alice/${stopAt}`),
      [],
      'the crashed subcollection should be untouched',
    );
    assert.equal(
      await docExists('users/alice'),
      true,
      'the root document must survive so the account is still findable',
    );
    assert.equal(
      await docExists('deletionRequests/alice'),
      true,
      'the marker must survive — it is the work queue entry',
    );
    assert.equal(
      await authUserExists('alice'),
      true,
      'the Auth account must survive: it is deleted after the data, not before',
    );
  });

  test('re-running after a crash finishes the job', async () => {
    await seedExpiredAccount('alice');
    const stopAt = SPEC.subcollections[SPEC.subcollections.length - 1];
    await run({ firestore: firestoreFailingOn((p) => p.endsWith(`/${stopAt}`)) });

    const summary = await run();

    assert.equal(summary.found, 1, 'the crashed account is still in the queue');
    assert.equal(summary.purged, 1);
    await assertAccountErased('alice');
  });

  test('a failure deleting the Auth user leaves the marker for the next run', async () => {
    // Auth deletion sits between the data and the marker. If it fails, the
    // account still exists and the job is NOT done, so the queue entry must
    // stay — otherwise a signed-in session survives with no way to find it.
    await seedExpiredAccount('alice');

    const summary = await run({
      deleteAuthUser: () => {
        throw new Error('simulated auth outage');
      },
    });

    assert.equal(summary.purged, 0);
    assert.equal(summary.failed.length, 1);
    assert.equal(
      await docExists('deletionRequests/alice'),
      true,
      'the marker must survive a failed Auth deletion',
    );
    assert.equal(await authUserExists('alice'), true);

    const retry = await run();
    assert.equal(retry.purged, 1);
    await assertAccountErased('alice');
  });

  test('one account failing does not stop the others', async () => {
    await seedExpiredAccount('doomed', {
      requestedAt: inDays(-40),
      purgeAfter: inDays(-9),
    });
    await seedExpiredAccount('healthy');

    const summary = await run({
      deleteAuthUser: (uid) => {
        if (uid === 'doomed') throw new Error('simulated auth outage');
        return deleteAuthUser(uid);
      },
    });

    assert.equal(summary.found, 2);
    assert.equal(summary.purged, 1);
    assert.equal(summary.failed.length, 1);
    await assertAccountErased('healthy');
    assert.equal(await docExists('deletionRequests/doomed'), true);
  });

  test('re-running over an already-purged account does nothing', async () => {
    await seedExpiredAccount('alice');
    await run();

    const summary = await run();

    assert.deepEqual(summary, { found: 0, purged: 0, skipped: [], failed: [] });
  });
});

describe('logging', () => {
  /**
   * The one summary line of a sweep.
   *
   * Asserted per OUTCOME (clean / skips / failures) rather than once, because
   * the three outcomes take three different log branches — the mutation check
   * caught an earlier version of these tests that only ever exercised one of
   * them and so passed with the other two deleted.
   */
  function summaryOf(logger) {
    const summaries = logger.entries.filter(
      (entry) => entry.payload && typeof entry.payload.found === 'number',
    );
    assert.equal(summaries.length, 1, 'exactly one summary line expected');
    return summaries[0];
  }

  const counts = (entry) => ({
    found: entry.payload.found,
    purged: entry.payload.purged,
    skipped: entry.payload.skipped,
    failed: entry.payload.failed,
  });

  test('a clean sweep logs found / purged / skipped / failed counts', async () => {
    await seedExpiredAccount('alice');
    const logger = recordingLogger();

    await run({ logger });

    const entry = summaryOf(logger);
    assert.equal(entry.level, 'info');
    assert.deepEqual(counts(entry), {
      found: 1,
      purged: 1,
      skipped: 0,
      failed: 0,
    });
  });

  test('a sweep with skips logs the counts and the skip reason', async () => {
    // A skipped marker is a request that is NOT being honoured. It has to be
    // visible, or an account sits in the queue forever with nobody aware.
    await seedExpiredAccount('alice');
    await seedExpiredAccount('bob', { requestedAt: inDays(-1) });
    const logger = recordingLogger();

    await run({ logger });

    const entry = summaryOf(logger);
    assert.equal(entry.level, 'warn');
    assert.deepEqual(counts(entry), {
      found: 2,
      purged: 1,
      skipped: 1,
      failed: 0,
    });
    assert.match(
      JSON.stringify(entry.payload),
      /not-due/,
      'the skip reason must be logged',
    );
  });

  test('a sweep with failures logs the counts and the failure reason', async () => {
    await seedExpiredAccount('alice');
    const logger = recordingLogger();

    await run({
      logger,
      deleteAuthUser: () => {
        throw new Error('simulated auth outage');
      },
    });

    const entry = summaryOf(logger);
    assert.equal(entry.level, 'error');
    assert.deepEqual(counts(entry), {
      found: 1,
      purged: 0,
      skipped: 0,
      failed: 1,
    });
    assert.match(
      JSON.stringify(entry.payload),
      /simulated auth outage/,
      'the failure reason must be logged',
    );
  });

  test('logs never carry a plaintext uid or anything from a document body', async () => {
    // A log line is the one place this job could quietly re-publish exactly what
    // it was asked to erase. Cloud Logging is retained, exported and readable by
    // anyone with project log access.
    const uid = 'uid-e2e7c1f0-do-not-log-me';
    await seedExpiredAccount(uid, { requestedAt: inDays(-1) });
    await seedExpiredAccount('bob');
    const logger = recordingLogger();

    await run({ logger });

    const text = JSON.stringify(logger.entries);
    assert.doesNotMatch(text, /do-not-log-me/, 'a uid was logged in plaintext');
    assert.doesNotMatch(text, /cramps all morning/, 'a document body was logged');
    assert.doesNotMatch(text, /2026-08-04/, 'a logged date leaked into the logs');
  });

  test('an error message quoting the uid is redacted before it is logged', async () => {
    // Firestore and Auth errors routinely quote the document path or the
    // account they failed on. That puts a plaintext uid inside a string that
    // otherwise looks perfectly safe to log verbatim — and failures are exactly
    // when someone goes looking at the logs.
    const uid = 'uid-9b31ca77-do-not-log-me';
    await seedExpiredAccount(uid);
    const logger = recordingLogger();

    const summary = await run({
      logger,
      deleteAuthUser: (target) => {
        throw new Error(`auth backend rejected account ${target}`);
      },
    });

    assert.equal(summary.failed.length, 1);
    const text = JSON.stringify([logger.entries, summary]);
    assert.match(text, /auth backend rejected account/, 'the reason was lost');
    assert.doesNotMatch(text, /do-not-log-me/, 'the uid survived into the log');
  });
});

describe('agreement with the Dart executable spec', () => {
  test('the subcollection list matches AccountDeletionService.subcollections', async () => {
    // The JS purge cannot import Dart, so it restates this list. That is the
    // one duplicated literal in the design, and this is the guard on it: adding
    // `users/{uid}/foo` to the Dart list without adding it here means the purge
    // silently leaves `foo` behind after an erasure request.
    assert.deepEqual(purge.SUBCOLLECTIONS, SPEC.subcollections);
  });

  test('the grace window matches AccountDeletionService.graceWindow', async () => {
    assert.equal(purge.GRACE_WINDOW_DAYS, SPEC.graceWindowDays);
  });

  test('the deployable wiring targets the NAMED lunatrack database', async () => {
    // `getFirestore(app)` alone targets `(default)`, whose ruleset is shared
    // with every other app in the project — the exact thing the named database
    // exists to avoid. Worse, the purge would then sweep an empty database and
    // report a clean run while every user's data survived.
    const refSource = fs.readFileSync(
      path.join(here, '..', 'lib', 'services', 'firestore_ref.dart'),
      'utf8',
    );
    const expected = refSource.match(
      /const String kLunaDatabaseId = '([^']+)'/,
    );
    assert.ok(expected, 'could not find `kLunaDatabaseId` in firestore_ref.dart');

    const wiring = fs.readFileSync(WIRING, 'utf8');
    const actual = wiring.match(/const LUNA_DATABASE_ID = '([^']+)'/);
    assert.ok(actual, 'could not find `LUNA_DATABASE_ID` in functions/index.js');
    assert.equal(actual[1], expected[1]);
    assert.match(
      wiring,
      /getFirestore\(app, LUNA_DATABASE_ID\)/,
      'the Firestore handle must be built from LUNA_DATABASE_ID',
    );
  });

  test('no Firebase project id is hardcoded in functions/ or in this suite', async () => {
    // The owning project is an OPEN DECISION. `firebase.json` currently names
    // `ride-with-purpose`, a client's production project; deploying a job with
    // delete authority there would put it over someone else's live data. The
    // project must come from the ambient environment / `--project` at deploy
    // time, so a literal anywhere in this code is a defect, not a shortcut.
    //
    // Asserted against CODE, with comments stripped: `index.js`'s TODO block
    // deliberately names `ride-with-purpose` as the project that must NOT
    // receive this deploy, and a scan that forbade the string outright would
    // force that warning to be deleted — which is backwards.
    const stripComments = (source) =>
      source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

    const code = [
      WIRING,
      PURGE_MODULE,
      path.join(here, 'purge_emulator.mjs'),
    ].map((file) => [path.basename(file), stripComments(fs.readFileSync(file, 'utf8'))]);

    const config = [
      path.join(here, '..', 'functions', 'package.json'),
      path.join(here, 'purge.firebase.json'),
      path.join(here, 'purge_run.sh'),
    ].map((file) => [path.basename(file), fs.readFileSync(file, 'utf8')]);

    for (const [name, source] of [...code, ...config]) {
      for (const project of [/ride-with-purpose/, /hbgapp-c3c88/]) {
        assert.doesNotMatch(
          source,
          project,
          `${name} names a real Firebase project`,
        );
      }
    }

    // Nothing deployable may pin a project at all, not even a placeholder.
    // (`purge_emulator.mjs` is excluded: it legitimately sets the emulator's
    // `demo-` project, and takes even that from `emulator.mjs`'s constant
    // rather than a literal of its own.)
    for (const [name, source] of [...code.slice(0, 2), ...config]) {
      assert.doesNotMatch(
        source,
        /projectId\s*[:=]/,
        `${name} pins a project id`,
      );
    }
  });

  test('the queue collection matches AccountDeletionService.requestsCollection', async () => {
    const source = fs.readFileSync(DART_SPEC, 'utf8');
    const match = source.match(
      /static const String requestsCollection = '([^']+)'/,
    );
    assert.ok(match, 'could not find `requestsCollection` in the Dart spec');
    assert.equal(purge.REQUESTS_COLLECTION, match[1]);
  });
});
