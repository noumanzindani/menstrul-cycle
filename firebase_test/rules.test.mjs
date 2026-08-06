// Emulator tests for `firestore.rules`.
//
// Run with:  firebase_test/run.sh
//
// Every path asserted here was read out of the app, not out of a plan:
//
//   users/{uid}                     AccountDeletionService.deleteFirestoreData
//   users/{uid}/dailyLogs/{date}    SyncService._remoteLogs
//   users/{uid}/settings/current    SyncService._remoteSettings
//   users/{uid}/deletions/{date}    SyncService._remoteDeletions
//   users/{uid}/devices/{deviceId}  SyncService._deviceDoc
//   deletionRequests/{uid}          AccountDeletionService
//
// `alice` is the account under test. `mallory` is a signed-in user who is NOT
// alice — in a Firebase project whose Auth pool is shared with unrelated apps,
// that is every one of their users, holding a perfectly valid token. The
// negative cases are the point of this file; the positive ones only exist so a
// rule that denies a legitimate client cannot pass unnoticed.
//
// Each test's discriminating power is proved separately: `mutation_check.mjs`
// re-runs this whole suite against rulesets with one guard removed at a time
// and fails if the corresponding test still passes.

import { after, before, beforeEach, describe, test } from 'node:test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  anonymous,
  assertAllowed,
  assertDenied,
  clearData,
  deleteDoc,
  getDoc,
  listDocs,
  loadRules,
  readAsAdmin,
  runQuery,
  seed,
  setDoc,
  setDocWithServerTime,
  user,
} from './emulator.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const RULES =
  process.env.LUNA_RULES_FILE ?? path.join(here, '..', 'firestore.rules');

const alice = user('alice');
const mallory = user('mallory');
const nobody = anonymous();

const DAY_MS = 24 * 60 * 60 * 1000;
const inDays = (days) => new Date(Date.now() + days * DAY_MS);

// A day document shaped like `sync_mapper.dart`'s `dailyLogToMap`.
const dayLog = {
  date: '2026-08-04',
  flow: 2,
  notes: 'cramps all morning',
  updatedAt: Date.now(),
};

const DAY = 'users/alice/dailyLogs/2026-08-04';
const SETTINGS = 'users/alice/settings/current';
const DELETION_MARKER = 'users/alice/deletions/2026-08-04';
const DEVICE = 'users/alice/devices/device-1';
const REQUEST = 'deletionRequests/alice';

// `AccountDeletionService.requestDeletion`'s payload: three fields, `purgeAfter`
// exactly `graceWindow` (30 days) out, `requestedAt` server-stamped.
const validRequest = (uid = 'alice') => ({ uid, purgeAfter: inDays(30) });

const request = (as, uid, data) =>
  setDocWithServerTime(as, `deletionRequests/${uid}`, data, ['requestedAt']);

before(() => loadRules(RULES));
beforeEach(() => clearData());
after(() => clearData());

describe('users/{uid} — the health data', () => {
  test('the owner can write, read and delete their own day log', async () => {
    await assertAllowed(setDoc(alice, DAY, dayLog), 'alice writing her day log');
    await assertAllowed(getDoc(alice, DAY), 'alice reading her day log');
    await assertAllowed(deleteDoc(alice, DAY), 'alice deleting her day log');
  });

  test('the owner can run the cursor-scoped pull query SyncService uses', async () => {
    await seed(DAY, dayLog);
    await assertAllowed(
      runQuery(alice, 'users/alice', {
        from: [{ collectionId: 'dailyLogs' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'syncedAt' },
            op: 'GREATER_THAN_OR_EQUAL',
            value: { timestampValue: inDays(-1).toISOString() },
          },
        },
      }),
      'alice pulling her own dailyLogs since a cursor',
    );
  });

  test('another signed-in user CANNOT read a day log', async () => {
    await seed(DAY, dayLog);
    await assertDenied(getDoc(mallory, DAY), "mallory reading alice's day log");
  });

  test('another signed-in user CANNOT list a day-log collection', async () => {
    await seed(DAY, dayLog);
    await assertDenied(
      listDocs(mallory, 'users/alice/dailyLogs'),
      "mallory listing alice's dailyLogs",
    );
  });

  test('another signed-in user CANNOT write a day log', async () => {
    await assertDenied(
      setDoc(mallory, DAY, dayLog),
      "mallory writing into alice's dailyLogs",
    );
    const after = await readAsAdmin(DAY);
    if (after.status === 200) throw new Error('the denied write still landed');
  });

  test('another signed-in user CANNOT delete a day log', async () => {
    await seed(DAY, dayLog);
    await assertDenied(
      deleteDoc(mallory, DAY),
      "mallory deleting alice's day log",
    );
    const after = await readAsAdmin(DAY);
    if (after.status !== 200) throw new Error('the denied delete still landed');
  });

  test('an unauthenticated client can read nothing', async () => {
    await seed(DAY, dayLog);
    await assertDenied(getDoc(nobody, DAY), 'an anonymous read of a day log');
  });

  test('an unauthenticated client can write nothing', async () => {
    await assertDenied(setDoc(nobody, DAY, dayLog), 'an anonymous day-log write');
  });

  test('settings/current is protected by the same identity rule', async () => {
    await assertAllowed(
      setDoc(alice, SETTINGS, { defaultCycleLength: 28, updatedAt: Date.now() }),
      'alice writing her settings',
    );
    await assertAllowed(getDoc(alice, SETTINGS), 'alice reading her settings');
    await assertDenied(
      getDoc(mallory, SETTINGS),
      "mallory reading alice's settings",
    );
    await assertDenied(
      setDoc(mallory, SETTINGS, { defaultCycleLength: 99 }),
      "mallory writing alice's settings",
    );
  });

  test('the deletions markers are protected by the same identity rule', async () => {
    // Each marker's document id IS a date the user tracked, so the collection
    // is a record of which days they logged even though it holds no symptoms.
    await assertAllowed(
      setDoc(alice, DELETION_MARKER, { date: '2026-08-04', deletedAt: 1 }),
      'alice writing her own deletion marker',
    );
    await assertAllowed(
      listDocs(alice, 'users/alice/deletions'),
      'alice listing her own deletion markers',
    );
    await assertDenied(
      listDocs(mallory, 'users/alice/deletions'),
      "mallory listing alice's deletion markers",
    );
    await assertDenied(
      deleteDoc(mallory, DELETION_MARKER),
      "mallory deleting alice's deletion marker",
    );
  });

  test('the per-device pull cursors are protected by the same identity rule', async () => {
    await assertAllowed(
      setDoc(alice, DEVICE, { logsCursor: new Date() }),
      'alice writing her own device cursor',
    );
    await assertAllowed(getDoc(alice, DEVICE), 'alice reading her device cursor');
    // A roster of every device that ever signed into the account.
    await assertDenied(
      getDoc(mallory, DEVICE),
      "mallory reading alice's device cursor",
    );
    await assertDenied(
      setDoc(mallory, DEVICE, { logsCursor: new Date(0) }),
      "mallory poisoning alice's pull cursor",
    );
  });

  test('the owner can delete their own users/{uid} document (the purge sweep)', async () => {
    // `AccountDeletionService.deleteFirestoreData` ends with
    // `firestore.doc('users/$uid').delete()`, and `users/{uid}/{document=**}`
    // does NOT match that parent document.
    await seed('users/alice', { anything: true });
    await assertAllowed(
      deleteDoc(alice, 'users/alice'),
      'alice deleting her own user document',
    );
  });

  test('another signed-in user CANNOT touch the users/{uid} document', async () => {
    await seed('users/alice', { anything: true });
    await assertDenied(
      getDoc(mallory, 'users/alice'),
      "mallory reading alice's user document",
    );
    await assertDenied(
      deleteDoc(mallory, 'users/alice'),
      "mallory deleting alice's user document",
    );
  });

  test('nobody can enumerate the users collection', async () => {
    await seed(DAY, dayLog);
    await assertDenied(listDocs(alice, 'users'), 'alice listing all users');
    await assertDenied(listDocs(nobody, 'users'), 'an anonymous list of all users');
  });

  test('a collection-group query cannot harvest everyone\'s day logs', async () => {
    // The shape that would sweep every account at once. Measured behaviour
    // (see `mutation_check.mjs`): a rule rooted at `/users/{userId}/…` never
    // authorises a collection-group query no matter how permissive its
    // condition, so this test is NOT killed by opening the users subtree — it
    // is killed by adding a root-level `match /{path=**}` catch-all, which is
    // exactly the ruleset edit that would make the harvest work.
    await seed(DAY, dayLog);
    await assertDenied(
      runQuery(mallory, '', {
        from: [{ collectionId: 'dailyLogs', allDescendants: true }],
      }),
      'a collection-group query across every dailyLogs collection',
    );
    await assertDenied(
      runQuery(alice, '', {
        from: [{ collectionId: 'dailyLogs', allDescendants: true }],
      }),
      'a collection-group query run by a legitimate account',
    );
  });
});

describe('deletionRequests/{uid} — the purge queue', () => {
  test('the owner can record a deletion request', async () => {
    await assertAllowed(
      request(alice, 'alice', validRequest()),
      'alice recording her deletion request',
    );
    await assertAllowed(getDoc(alice, REQUEST), 'alice reading her own request');
  });

  test('the collection can NEVER be listed, not even by an owner', async () => {
    // A list permission here is a roster of every account pending deletion.
    await seed(REQUEST, { uid: 'alice', purgeAfter: inDays(30) });
    await assertDenied(
      listDocs(alice, 'deletionRequests'),
      'alice listing the deletion queue',
    );
    await assertDenied(
      runQuery(alice, '', { from: [{ collectionId: 'deletionRequests' }] }),
      'alice querying the deletion queue',
    );
    await assertDenied(
      runQuery(nobody, '', { from: [{ collectionId: 'deletionRequests' }] }),
      'an anonymous query of the deletion queue',
    );
  });

  test('another signed-in user CANNOT read a deletion request', async () => {
    await seed(REQUEST, { uid: 'alice', purgeAfter: inDays(30) });
    await assertDenied(
      getDoc(mallory, REQUEST),
      "mallory reading alice's deletion request",
    );
    await assertDenied(
      getDoc(nobody, REQUEST),
      'an anonymous read of a deletion request',
    );
  });

  test('another signed-in user CANNOT record a request against someone else', async () => {
    // Forcing a stranger's account into a pending-deletion state suspends their
    // sync for the whole grace window and queues their data for erasure.
    await assertDenied(
      request(mallory, 'alice', validRequest('alice')),
      "mallory requesting deletion of alice's account",
    );
    await assertDenied(
      request(nobody, 'alice', validRequest('alice')),
      'an anonymous deletion request',
    );
  });

  test('a request carrying an extra field is refused', async () => {
    await assertDenied(
      request(alice, 'alice', { ...validRequest(), smuggled: 'x'.repeat(64) }),
      'a deletion request with an extra field',
    );
  });

  test('a request missing purgeAfter is refused', async () => {
    await assertDenied(
      request(alice, 'alice', { uid: 'alice' }),
      'a deletion request with no deadline',
    );
  });

  test('a request whose uid does not match its path is refused', async () => {
    await assertDenied(
      request(alice, 'alice', { uid: 'mallory', purgeAfter: inDays(30) }),
      "a deletion request claiming someone else's uid",
    );
  });

  test('a client-chosen requestedAt is refused', async () => {
    // `requestedAt` is the audit trail of WHEN. Left to the client it is a
    // number the attacker picks, and a backdated one makes an already-expired
    // request.
    await assertDenied(
      setDoc(alice, REQUEST, {
        uid: 'alice',
        requestedAt: new Date(),
        purgeAfter: inDays(30),
      }),
      'a deletion request with a client-stamped requestedAt',
    );
    await assertDenied(
      setDoc(alice, REQUEST, {
        uid: 'alice',
        requestedAt: inDays(-3650),
        purgeAfter: inDays(30),
      }),
      'a deletion request with a backdated requestedAt',
    );
  });

  test('a purgeAfter in the past is refused', async () => {
    // An immediate purge: the data is destroyed with no grace window and the
    // cancel path is never reachable.
    await assertDenied(
      request(alice, 'alice', { uid: 'alice', purgeAfter: inDays(-1) }),
      'a deletion request whose deadline has already passed',
    );
  });

  test('a purgeAfter far in the future is refused', async () => {
    // A marker that suppresses sync forever and is never collected.
    await assertDenied(
      request(alice, 'alice', { uid: 'alice', purgeAfter: inDays(3650) }),
      'a deletion request with a deadline centuries out',
    );
  });

  test('a purgeAfter that is not a timestamp is refused', async () => {
    await assertDenied(
      request(alice, 'alice', { uid: 'alice', purgeAfter: 'soon' }),
      'a deletion request with a non-timestamp deadline',
    );
  });

  test('an existing request cannot be overwritten', async () => {
    // Re-requesting must not slide the deadline the user was promised, and an
    // overwrite is how an attacker with a foothold would extend or erase it.
    const promised = inDays(30);
    await seed(REQUEST, { uid: 'alice', requestedAt: new Date(), purgeAfter: promised });
    await assertDenied(
      request(alice, 'alice', { uid: 'alice', purgeAfter: inDays(30) }),
      'alice overwriting her own pending request',
    );
    const stored = await readAsAdmin(REQUEST);
    if (!stored.body.includes(promised.toISOString().replace(/\.000Z$/, 'Z'))) {
      throw new Error(`the promised deadline was modified: ${stored.body}`);
    }
  });

  test('the owner can cancel a pending request, twice, and a stranger cannot', async () => {
    // The cancel path (`AccountSection._cancelDeletion` / the deletion-pending
    // screen) is a plain `delete()`; denying it would strand every user who
    // changed their mind inside the grace window.
    await seed(REQUEST, { uid: 'alice', purgeAfter: inDays(30) });
    await assertDenied(
      deleteDoc(mallory, REQUEST),
      "mallory cancelling alice's deletion request",
    );
    await assertAllowed(
      deleteDoc(alice, REQUEST),
      'alice cancelling her own deletion request',
    );
    await assertAllowed(
      deleteDoc(alice, REQUEST),
      'alice cancelling an already-cancelled request (idempotent)',
    );
  });
});

describe('everything else', () => {
  test('an unrelated top-level collection is denied by default', async () => {
    // No `match /{document=**}` catch-all: anything the app does not use is
    // unreachable, for owners and strangers alike.
    await assertDenied(
      setDoc(alice, 'scratch/doc-1', { anything: true }),
      'alice writing outside the modelled paths',
    );
    await assertDenied(
      getDoc(alice, 'scratch/doc-1'),
      'alice reading outside the modelled paths',
    );
    await assertDenied(
      listDocs(alice, 'scratch'),
      'alice listing outside the modelled paths',
    );
  });
});
