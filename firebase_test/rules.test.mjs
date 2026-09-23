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
//   users/{uid}/analysisSessions    SyncService._remoteSessions
//   users/{uid}/analysisMessages    SyncService._remoteMessages
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
import fs from 'node:fs';
import os from 'node:os';
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
const MEDIA_ID = '0123456789abcdef0123456789abcdef';
const MEDIA = `users/alice/media/${MEDIA_ID}`;

/** A live media document, exactly as `MediaUploadService` writes it. */
const mediaDoc = (overrides = {}) => ({
  id: MEDIA_ID,
  kind: 'image',
  storagePath: `users/alice/media/${MEDIA_ID}/original.jpg`,
  thumbPath: `users/alice/media/${MEDIA_ID}/thumb.jpg`,
  bytes: 20481,
  capturedAt: 1780000000000,
  createdAt: 1780000000000,
  updatedAt: 1780000000000,
  deviceId: 'device-1',
  ...overrides,
});

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


describe('users/{uid}/media — uploaded photos and videos', () => {
  test('the owner can write, read, list and delete their own media', async () => {
    await assertAllowed(setDoc(alice, MEDIA, mediaDoc()), 'alice writing media');
    await assertAllowed(getDoc(alice, MEDIA), 'alice reading her media');
    await assertAllowed(
      listDocs(alice, 'users/alice/media'),
      'alice listing her own media',
    );
    await assertAllowed(deleteDoc(alice, MEDIA), 'alice deleting her media');
  });

  test('the owner can write a deletion tombstone', async () => {
    await assertAllowed(
      setDoc(alice, MEDIA, { id: MEDIA_ID, deletedAt: 1780000009000 }),
      'alice tombstoning her own media',
    );
  });

  test('another signed-in user CANNOT read, list, write or delete it', async () => {
    await seed(MEDIA, mediaDoc());
    await assertDenied(getDoc(mallory, MEDIA), "mallory reading alice's media");
    await assertDenied(
      listDocs(mallory, 'users/alice/media'),
      "mallory listing alice's media",
    );
    await assertDenied(
      setDoc(mallory, MEDIA, mediaDoc()),
      "mallory writing into alice's media",
    );
    await assertDenied(
      deleteDoc(mallory, MEDIA),
      "mallory deleting alice's media",
    );
  });

  test('an unauthenticated caller CANNOT read it', async () => {
    await seed(MEDIA, mediaDoc());
    await assertDenied(getDoc(nobody, MEDIA), 'anonymous reading media');
  });

  test('a stored download URL is REFUSED', async () => {
    // A Firebase download token is a bearer credential no rule evaluates and
    // that never expires. The client is built never to mint one; this is the
    // half a compromised or modified client cannot skip.
    for (const field of ['downloadUrl', 'downloadURL', 'url', 'token']) {
      await assertDenied(
        setDoc(alice, MEDIA, mediaDoc({ [field]: 'https://example.test/x' })),
        `alice storing a ${field}`,
      );
    }
  });

  test('a storagePath pointing at ANOTHER account is refused', async () => {
    await assertDenied(
      setDoc(
        alice,
        MEDIA,
        mediaDoc({ storagePath: `users/mallory/media/${MEDIA_ID}/original.jpg` }),
      ),
      "alice claiming an object under mallory's prefix",
    );
  });

  test('an unknown kind is refused', async () => {
    await assertDenied(
      setDoc(alice, MEDIA, mediaDoc({ kind: 'document' })),
      'alice writing an unrecognised media kind',
    );
  });

  test('a document id that disagrees with the id field is refused', async () => {
    await assertDenied(
      setDoc(alice, MEDIA, mediaDoc({ id: 'something-else' })),
      'alice writing a mismatched id',
    );
  });

  test('a smuggled extra field is refused', async () => {
    // `users/{uid}/media` is a collection the owner fully controls, so without
    // hasOnly it is a place to park arbitrary data that the purge — which
    // sweeps a fixed field-agnostic list — would delete, but which nothing
    // validates in the meantime.
    await assertDenied(
      setDoc(alice, MEDIA, mediaDoc({ note: 'x'.repeat(64) })),
      'alice smuggling an extra field',
    );
  });

  test('a subcollection outside the enumerated set is refused entirely', async () => {
    // The regression guard on removing `match /{document=**}`. Anything not
    // named in the ruleset is denied, so nothing can be written into a path the
    // purge does not sweep.
    await assertDenied(
      setDoc(alice, 'users/alice/scratch/anything', { a: 1 }),
      'alice writing to an unmodelled subcollection',
    );
  });
});


// --- assistant conversations ---------------------------------------------

const SESSION_ID = 'fedcba9876543210fedcba9876543210';
const SESSION = `users/alice/analysisSessions/${SESSION_ID}`;
const MESSAGE = 'users/alice/analysisMessages/0000000000000000000000000000000a';
const PHOTO_ID = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const VIDEO_ID = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/** A session exactly as `analysisSessionToMap` writes it. */
const sessionDoc = (overrides = {}) => ({
  uid: 'alice',
  mediaId: '',
  consentVersion: 7,
  createdAt: 1780000000000,
  updatedAt: 1780000000000,
  title: 'is this normal',
  ...overrides,
});

/** The v16 tombstone: the full shape plus deletedAt, and no title. */
const tombstoneDoc = () => {
  const { title, ...rest } = sessionDoc({ updatedAt: 1780000009000 });
  return { ...rest, deletedAt: 1780000009000 };
};

/** A message exactly as `analysisMessageToMap` writes it (v16). */
const messageDoc = (overrides = {}) => ({
  sessionId: SESSION_ID,
  role: 'user',
  messageText: 'what is this',
  createdAt: 1780000000000,
  updatedAt: 1780000000000,
  attachments: [
    { mediaId: PHOTO_ID, kind: 'image' },
    { mediaId: VIDEO_ID, kind: 'video' },
  ],
  includeInModel: true,
  ...overrides,
});

/** The same message as a v15 client writes it: no v16 fields at all. */
const v15MessageDoc = () => {
  const { attachments, includeInModel, ...rest } = messageDoc();
  return rest;
};

describe('users/{uid}/analysis* — assistant conversations', () => {
  test('the owner can write, read and list her own conversation', async () => {
    await assertAllowed(setDoc(alice, SESSION, sessionDoc()), 'alice writing a session');
    await assertAllowed(setDoc(alice, MESSAGE, messageDoc()), 'alice writing a message');
    await assertAllowed(getDoc(alice, SESSION), 'alice reading her session');
    await assertAllowed(
      listDocs(alice, 'users/alice/analysisMessages'),
      'alice listing her messages',
    );
  });

  test('a v15 client can still write its old-shape message', async () => {
    await assertAllowed(
      setDoc(alice, MESSAGE, v15MessageDoc()),
      'a v15 client writing a message with no attachments field',
    );
  });

  test('the owner can push a tombstone and delete its messages', async () => {
    await seed(SESSION, sessionDoc());
    await seed(MESSAGE, messageDoc());
    await assertAllowed(setDoc(alice, SESSION, tombstoneDoc()), 'alice tombstoning a session');
    await assertAllowed(deleteDoc(alice, MESSAGE), "alice deleting the tombstone's message");
  });

  test('another signed-in user CANNOT read or write a conversation', async () => {
    await seed(SESSION, sessionDoc());
    await seed(MESSAGE, messageDoc());
    await assertDenied(getDoc(mallory, SESSION), "mallory reading alice's session");
    await assertDenied(getDoc(mallory, MESSAGE), "mallory reading alice's message");
    await assertDenied(
      setDoc(mallory, SESSION, sessionDoc()),
      "mallory writing alice's session",
    );
    await assertDenied(
      setDoc(mallory, MESSAGE, messageDoc()),
      "mallory writing alice's message",
    );
    await assertDenied(
      deleteDoc(mallory, MESSAGE),
      "mallory deleting alice's message",
    );
  });

  test('an attachment carrying a URL key is refused', async () => {
    for (const field of ['url', 'downloadUrl', 'downloadURL', 'token']) {
      await assertDenied(
        setDoc(
          alice,
          MESSAGE,
          messageDoc({
            attachments: [
              { mediaId: PHOTO_ID, kind: 'image', [field]: 'https://example.test/x' },
            ],
          }),
        ),
        `alice storing a ${field} on an attachment`,
      );
    }
  });

  test('an attachment whose mediaId is not a media id is refused', async () => {
    await assertDenied(
      setDoc(
        alice,
        MESSAGE,
        messageDoc({
          attachments: [{ mediaId: 'https://example.test/x', kind: 'image' }],
        }),
      ),
      'alice parking a URL in mediaId',
    );
  });

  test('an attachment of an unknown kind is refused', async () => {
    await assertDenied(
      setDoc(
        alice,
        MESSAGE,
        messageDoc({ attachments: [{ mediaId: PHOTO_ID, kind: 'document' }] }),
      ),
      'alice attaching an unrecognised kind',
    );
  });

  test('a later attachment is checked, not only the first', async () => {
    await assertDenied(
      setDoc(
        alice,
        MESSAGE,
        messageDoc({
          attachments: [
            { mediaId: PHOTO_ID, kind: 'image' },
            { mediaId: PHOTO_ID, kind: 'image' },
            { mediaId: PHOTO_ID, kind: 'image' },
            { mediaId: PHOTO_ID, kind: 'image' },
            { mediaId: PHOTO_ID, kind: 'image' },
            { mediaId: PHOTO_ID, kind: 'image', url: 'https://example.test/x' },
          ],
        }),
      ),
      'alice hiding a URL in the last permitted attachment',
    );
  });

  test('attachments that are not a list are refused', async () => {
    await assertDenied(
      setDoc(alice, MESSAGE, messageDoc({ attachments: 'https://example.test/x' })),
      'alice storing attachments as a string',
    );
  });

  test('more attachments than the cap are refused', async () => {
    const seven = Array.from({ length: 7 }, () => ({ mediaId: PHOTO_ID, kind: 'image' }));
    await assertDenied(
      setDoc(alice, MESSAGE, messageDoc({ attachments: seven })),
      'alice attaching seven references',
    );
  });

  test('a smuggled extra field on a message is refused', async () => {
    await assertDenied(
      setDoc(alice, MESSAGE, messageDoc({ downloadUrl: 'https://example.test/x' })),
      'alice storing a URL beside the message',
    );
  });

  test('a v15 set() over a tombstone is still allowed while the stricter rules are staged', async () => {
    // Characterisation, not an endorsement: this is the write the staged rule
    // below refuses. It stays allowed until the minimum client is v16, because
    // a v15 client that is denied here aborts its whole sync.
    await seed(SESSION, tombstoneDoc());
    await assertAllowed(
      setDoc(alice, SESSION, sessionDoc()),
      'a v15 client re-setting a tombstoned session',
    );
  });
});

/**
 * `firestore.rules` with the STAGED analysis block switched on: the live
 * block removed and the `//S ` lines uncommented — exactly the edit the rules
 * file tells whoever enables it to make.
 */
function stagedRules(source) {
  const begin = source.indexOf('// BEGIN live-analysis');
  const end = source.indexOf('// END live-analysis');
  if (begin < 0 || end < 0 || !source.includes('//S ')) {
    throw new Error('firestore.rules no longer has the staged analysis markers');
  }
  const withoutLive = source.slice(0, begin) + source.slice(end);
  return withoutLive.replace(/^(\s*)\/\/S ?/gm, '$1');
}

describe('STAGED analysis rules (enable once the minimum client is v16)', () => {
  const file = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), 'lunatrack-staged-')),
    'staged.rules',
  );

  before(() => {
    fs.writeFileSync(file, stagedRules(fs.readFileSync(RULES, 'utf8')));
    return loadRules(file);
  });
  after(() => loadRules(RULES));

  test('staged: the owner can still do everything a v16 client does', async () => {
    await assertAllowed(setDoc(alice, SESSION, sessionDoc()), 'alice writing a session');
    await assertAllowed(setDoc(alice, MESSAGE, messageDoc()), 'alice writing a message');
    await assertAllowed(setDoc(alice, SESSION, tombstoneDoc()), 'alice tombstoning it');
    await assertAllowed(setDoc(alice, SESSION, tombstoneDoc()), 'alice re-pushing the tombstone');
    await assertAllowed(deleteDoc(alice, MESSAGE), 'alice deleting its message');
  });

  test('staged: a session naming another owner is refused', async () => {
    await assertDenied(
      setDoc(alice, SESSION, sessionDoc({ uid: 'mallory' })),
      "alice writing a session that claims mallory's uid",
    );
  });

  test('staged: a write that drops deletedAt from a tombstone is refused', async () => {
    await seed(SESSION, tombstoneDoc());
    await assertDenied(
      setDoc(alice, SESSION, sessionDoc()),
      'a stale v15 set() resurrecting a deleted conversation',
    );
  });

  test('staged: a new message under a deleted conversation is refused', async () => {
    await seed(SESSION, tombstoneDoc());
    await assertDenied(
      setDoc(alice, MESSAGE, messageDoc()),
      'a message pushed under a tombstoned session',
    );
  });

  test('staged: a message under a live or not-yet-synced session is allowed', async () => {
    await assertAllowed(
      setDoc(alice, MESSAGE, messageDoc()),
      'a message whose session has not landed yet',
    );
    await seed(SESSION, sessionDoc());
    await assertAllowed(
      setDoc(alice, 'users/alice/analysisMessages/0000000000000000000000000000000b', messageDoc()),
      'a message under a live session',
    );
  });

  test('staged: attachment validation still applies', async () => {
    await assertDenied(
      setDoc(
        alice,
        MESSAGE,
        messageDoc({ attachments: [{ mediaId: 'https://example.test/x', kind: 'image' }] }),
      ),
      'a URL in mediaId under the staged rules',
    );
  });
});
