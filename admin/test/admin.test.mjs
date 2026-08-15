// Emulator tests for the LunaTrack operator panel.
//
//   admin/test/run.sh              the suite
//   admin/test/run.sh --mutants    + prove every test discriminates
//
// Nothing here contacts a remote Firebase project: the project id is
// `demo-lunatrack`, which `firebase-tools` treats as emulator-only, and there is
// deliberately no `.firebaserc` in this repo.
//
// The suite asserts the properties that make a hosted panel over menstrual-health
// data defensible at all:
//
//   * identity is a VERIFIED IAP assertion, backed by an allowlist
//   * the audit record is written BEFORE content, and a failed write blocks it
//   * pending-deletion accounts are flagged everywhere
//   * statistics are `count()` aggregations, not document sweeps
//   * the roster comes from Auth and survives the fact that `users/{uid}`
//     documents DO NOT EXIST — seeded explicitly, because that is the trap
//   * no endpoint writes health data, and no query searches it across users

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, beforeEach, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { AUDIT_COLLECTION, createAuditLog } from '../src/audit.js';
import { ConfigError, readConfig } from '../src/env.js';
import { MUTATING_METHODS, ReadOnlyViolation, readOnly } from '../src/readonly.js';
import { decodeDayTags } from '../src/records.js';
import { sweepAuthRoster } from '../src/stats.js';

import {
  AUDIENCE,
  IMPOSTOR_KEY,
  OWNER,
  clearAuth,
  clearFirestore,
  dayDoc,
  firebaseHandles,
  mintAssertion,
  seedAccount,
  signIn,
  startPanel,
} from './support.mjs';

// The existing rules harness, reused verbatim. Importing it rather than
// re-implementing it is what keeps the `adminAudit` assertion honest: it speaks
// the same wire protocol the Flutter app's SDK does.
import {
  assertDenied,
  clearData,
  getDoc,
  listDocs,
  loadRules,
  setDoc,
  user,
} from '../../firebase_test/emulator.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(here, '..', 'src');
const RULES = path.join(here, '..', '..', 'firestore.rules');

const DAY_MS = 24 * 60 * 60 * 1000;

let panel;

before(async () => {
  await clearAuth();
  await clearFirestore();
});

beforeEach(async () => {
  if (panel) {
    await panel.stop();
    panel = null;
  }
  await clearAuth();
  await clearFirestore();
});

after(async () => {
  if (panel) await panel.stop();
  await clearAuth();
  await clearFirestore();
});

/** Boots the panel and remembers it so `beforeEach` can tear it down. */
async function boot(options) {
  panel = await startPanel(options);
  return panel;
}

// =========================================================================
// 1. Identity — IAP is the front door and there is no other one
// =========================================================================

describe('identity: the verified IAP assertion', () => {
  test('a request with NO assertion header is refused', async () => {
    const app = await boot();
    const response = await app.get('/', { token: null });
    assert.equal(response.status, 401);
    assert.match(response.body, /no IAP assertion header present/);
  });

  test('an assertion signed by a DIFFERENT key is refused', async () => {
    const app = await boot();
    // Structurally perfect: right issuer, right audience, right kid, right
    // email, unexpired. Only the signature is wrong. If this passed, the
    // `x-goog-*` headers would be all that stood between a direct request and
    // somebody's menstrual history.
    const forged = mintAssertion({ kid: IMPOSTOR_KEY.kid, key: IMPOSTOR_KEY.privateKey });
    const response = await app.get('/', { token: forged });
    assert.equal(response.status, 401);
    assert.match(response.body, /signature is invalid/);
  });

  test('an assertion minted for ANOTHER service is refused', async () => {
    const app = await boot();
    const response = await app.get('/', {
      token: mintAssertion({ audience: '/projects/1/global/backendServices/somebody-else' }),
    });
    assert.equal(response.status, 401);
    assert.match(response.body, /another service/);
  });

  test('an "alg: none" assertion is refused', async () => {
    const app = await boot();
    const response = await app.get('/', {
      token: mintAssertion({ alg: 'none', sign: false }),
    });
    assert.equal(response.status, 401);
    assert.match(response.body, /unexpected assertion algorithm/);
  });

  test('an expired assertion is refused', async () => {
    const app = await boot();
    const past = Math.floor(Date.now() / 1000) - 7200;
    const response = await app.get('/', {
      token: mintAssertion({ iat: past, exp: past + 600 }),
    });
    assert.equal(response.status, 401);
    assert.match(response.body, /expired/);
  });

  test('an assertion from an issuer other than IAP is refused', async () => {
    const app = await boot();
    const response = await app.get('/', {
      token: mintAssertion({ issuer: 'https://accounts.google.com' }),
    });
    assert.equal(response.status, 401);
    assert.match(response.body, /unexpected assertion issuer/);
  });

  test('a VERIFIED identity that is not on the allowlist is refused', async () => {
    const app = await boot({ adminEmails: OWNER });
    const response = await app.get('/', {
      token: mintAssertion({ email: 'someone.else@example.com' }),
    });
    // 403, not 401: IAP did authenticate them. The allowlist is the second,
    // independent thing that has to be wrong before this panel opens.
    assert.equal(response.status, 403);
    assert.match(response.body, /Not an authorised operator/);
    // The allowlist's contents are not echoed to whoever asked.
    assert.doesNotMatch(response.body, new RegExp(OWNER));
  });

  test('the allowlisted operator is let in, case-insensitively', async () => {
    const app = await boot({ adminEmails: OWNER });
    const response = await app.get('/', {
      token: mintAssertion({ email: OWNER.toUpperCase() }),
    });
    assert.equal(response.status, 200);
  });

  test('a cross-origin form post is refused before anything is read', async () => {
    const app = await boot();
    const response = await app.post(
      '/users/alice/records',
      { reason: 'attacker supplied' },
      { headers: { origin: 'https://evil.example' } },
    );
    assert.equal(response.status, 403);
    assert.match(response.body, /Cross-origin/);
    assert.equal(
      app.log.some((entry) => entry.includes('dailyLogs')),
      false,
      'a cross-origin post must not reach any health record',
    );
  });

  test('/healthz needs no identity and discloses nothing', async () => {
    const app = await boot();
    const response = await app.get('/healthz', { token: null });
    assert.equal(response.status, 200);
    assert.equal(response.body, 'ok');
  });
});

describe('identity: configuration fails closed', () => {
  const base = {
    LUNATRACK_PROJECT_ID: 'demo-lunatrack',
    ADMIN_EMAILS: OWNER,
    IAP_AUDIENCE: AUDIENCE,
  };

  test('no project id refuses to start', () => {
    assert.throws(
      () => readConfig({ ...base, LUNATRACK_PROJECT_ID: undefined }),
      ConfigError,
    );
  });

  test('an empty allowlist refuses to start', () => {
    assert.throws(() => readConfig({ ...base, ADMIN_EMAILS: '  , ,' }), ConfigError);
  });

  test('no IAP audience refuses to start', () => {
    assert.throws(() => readConfig({ ...base, IAP_AUDIENCE: undefined }), ConfigError);
  });

  test('the dev identity bypass is refused without an emulator host', () => {
    assert.throws(
      () => readConfig({ ...base, ADMIN_DEV_UNSAFE_IDENTITY: OWNER }),
      /refused against a real database/,
    );
  });

  test('the dev identity bypass is honoured only alongside an emulator host', () => {
    const config = readConfig({
      ...base,
      ADMIN_DEV_UNSAFE_IDENTITY: OWNER,
      FIRESTORE_EMULATOR_HOST: '127.0.0.1:8099',
    });
    assert.equal(config.devIdentity, OWNER);
  });

  test('the project id is never defaulted', () => {
    // A hardcoded project id here would point the panel at whatever the
    // untracked root `firebase.json` names — currently an unrelated production
    // project. The owning project is an open decision; see CLAUDE.md.
    const sources = fs
      .readdirSync(SRC)
      .filter((name) => name.endsWith('.js'))
      .map((name) => fs.readFileSync(path.join(SRC, name), 'utf8'))
      .join('\n');
    assert.doesNotMatch(sources, /ride-with-purpose/);
    assert.doesNotMatch(sources, /projectId:\s*['"][a-z0-9-]+['"]/);
  });
});

// =========================================================================
// 2. The roster comes from Auth — because users/{uid} documents do not exist
// =========================================================================

describe('roster: sourced from Firebase Auth', () => {
  test('THE TRAP: users/{uid} documents do not exist, and the roster works anyway', async () => {
    const app = await boot();

    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedAccount(app.auth, { uid: 'bob', email: 'bob@example.com' });
    await seedAccount(app.auth, { uid: 'carol', email: 'carol@example.com' });

    // Exactly what `SyncService` does: SUBcollections only, parent never
    // written. This is the seeded trap, not an accident of the fixture.
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04' }));
    await app.raw.collection('users/bob/devices').doc('device-1').set({ logsCursor: null });

    // Prove the trap is real before relying on the workaround.
    const parents = await app.raw.collection('users').get();
    assert.equal(
      parents.size,
      0,
      'collection("users").get() must return ZERO — the app never writes the parent document',
    );

    const response = await app.get('/users');
    assert.equal(response.status, 200);
    for (const uid of ['alice', 'bob', 'carol']) {
      assert.match(response.body, new RegExp(uid), `roster is missing ${uid}`);
    }
    assert.match(response.body, /alice@example\.com/);
  });

  test('the roster carries no health data', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04', notes: 'cramps all morning', mood: 'anxious' }));

    const response = await app.get('/users');
    assert.equal(response.status, 200);
    assert.doesNotMatch(response.body, /cramps all morning/);
    assert.doesNotMatch(response.body, /anxious/);
    assert.equal(
      app.log.some((entry) => entry.includes('dailyLogs')),
      false,
      'rendering the roster must not touch dailyLogs at all',
    );
  });

  test('exact lookup by email and by uid', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedAccount(app.auth, { uid: 'bob', email: 'bob@example.com' });

    const byEmail = await app.get('/users?q=alice%40example.com');
    assert.match(byEmail.body, /alice@example\.com/);
    assert.doesNotMatch(byEmail.body, /bob@example\.com/);

    const byUid = await app.get('/users?q=bob');
    assert.match(byUid.body, /bob@example\.com/);
    assert.doesNotMatch(byUid.body, /alice@example\.com/);
  });

  test('NO cross-user search reaches any health field', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04', notes: 'cramps all morning', flow: 4 }));

    // "Find everyone who logged X" is not a support tool. Searching a note
    // fragment must find nobody, and must not read a log to decide that.
    const response = await app.get('/users?q=cramps');
    assert.equal(response.status, 200);
    assert.match(response.body, /No accounts matched/);
    assert.equal(
      app.log.some((entry) => entry.includes('dailyLogs')),
      false,
    );
  });

  test('every Firestore filter in src/ is on a key field, never on health content', () => {
    // Structural backstop for the behavioural test above. A cross-user harvest
    // needs exactly one thing: a filter on a health field, or a filter attached
    // to a collection-group query. Neither may exist anywhere in the source.
    //
    // `date` is allowed because it is the document key by another name
    // (`syncDocId` makes the id the ISO date) and is what newest-first paging
    // has to order on — Firestore has no descending key index. `flow`,
    // `symptoms`, `mood`, `notes`, `bbt` and `opk` are the health fields, and
    // none of them may ever appear here.
    const ALLOWED = ['FieldPath.documentId(', "'date'", '"date"'];
    const offenders = [];
    for (const name of fs.readdirSync(SRC).filter((f) => f.endsWith('.js'))) {
      const source = fs.readFileSync(path.join(SRC, name), 'utf8');
      for (const match of source.matchAll(/\.where\(\s*([^,]+),/g)) {
        const argument = match[1].trim();
        if (!ALLOWED.some((allowed) => argument.startsWith(allowed))) {
          offenders.push(`${name}: .where(${argument}, …)`);
        }
      }
      // A collection group is the only shape that can reach across users at
      // all, so it must never carry a filter — only `count()`.
      for (const match of source.matchAll(/collectionGroup\([^)]*\)[^;\n]*\.where\(/g)) {
        offenders.push(`${name}: filtered collection-group query — ${match[0]}`);
      }
    }
    assert.deepEqual(offenders, []);
  });
});

// =========================================================================
// 3. Deletion awareness
// =========================================================================

describe('pending account deletion is flagged everywhere', () => {
  const seedPending = async (app, uid) => {
    await app.raw.doc(`deletionRequests/${uid}`).set({
      uid,
      requestedAt: new Date(Date.now() - 2 * DAY_MS),
      purgeAfter: new Date(Date.now() + 28 * DAY_MS),
    });
  };

  test('the roster flags the account', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedAccount(app.auth, { uid: 'bob', email: 'bob@example.com' });
    await seedPending(app, 'alice');

    const response = await app.get('/users');
    assert.match(response.body, /PENDING DELETION/);
    // And only once — bob must not be flagged.
    assert.equal(response.body.match(/PENDING DELETION/g).length, 1);
  });

  test('the metadata view warns before anything else', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedPending(app, 'alice');

    const response = await app.get('/users/alice');
    assert.match(response.body, /This account has requested deletion/);
    assert.match(response.body, /believes their account is being deleted/);
  });

  test('the reason gate and the records view both warn', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedPending(app, 'alice');
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04' }));

    const gate = await app.get('/users/alice/records');
    assert.match(gate.body, /This account has requested deletion/);

    const records = await app.post('/users/alice/records', { reason: 'ticket 1' });
    assert.equal(records.status, 200);
    assert.match(records.body, /Pending account deletion/);
  });

  test('the dashboard counts pending deletions and subtracts them', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedAccount(app.auth, { uid: 'bob', email: 'bob@example.com' });
    await seedAccount(app.auth, { uid: 'carol', email: 'carol@example.com' });
    await seedPending(app, 'alice');

    const response = await app.get('/');
    assert.match(response.body, /<div class="n">1<\/div><div class="k">pending deletion requests/);
    assert.match(
      response.body,
      /<div class="n">2<\/div><div class="k">accounts not pending deletion/,
    );
  });
});

// =========================================================================
// 4. Statistics — count() aggregations, correct numbers
// =========================================================================

describe('statistics', () => {
  test('the dashboard reports correct numbers against seeded data', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedAccount(app.auth, { uid: 'bob', email: 'bob@example.com' });

    for (const date of ['2026-08-01', '2026-08-02', '2026-08-03']) {
      await app.raw.collection('users/alice/dailyLogs').doc(date).set(dayDoc({ date }));
    }
    await app.raw
      .collection('users/bob/dailyLogs')
      .doc('2026-07-30')
      .set(dayDoc({ date: '2026-07-30' }));
    await app.raw.doc('users/alice/settings/current').set({ updatedAt: Date.now() });
    await app.raw.doc('users/alice/devices/device-1').set({ logsCursor: new Date() });
    await app.raw.doc('users/alice/devices/device-2').set({ logsCursor: new Date() });
    await app.raw.doc('users/bob/deletions/2026-07-01').set({ date: '2026-07-01' });

    const response = await app.get('/');
    assert.equal(response.status, 200);
    assert.match(response.body, /<div class="n">2<\/div><div class="k">total accounts/);
    assert.match(
      response.body,
      /<div class="n">4<\/div><div class="k">total logged days \(all accounts\)/,
    );
    assert.match(
      response.body,
      /<div class="n">1<\/div><div class="k">accounts with synced settings/,
    );
    assert.match(
      response.body,
      /<div class="n">1<\/div><div class="k">local-only \/ never synced settings/,
    );
    assert.match(response.body, /<div class="n">2<\/div><div class="k">device cursor records/);
    assert.match(
      response.body,
      /<div class="n">1<\/div><div class="k">deletion markers \(days\)/,
    );
  });

  test('statistics use count() aggregation and NEVER sweep documents', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    for (const date of ['2026-08-01', '2026-08-02']) {
      await app.raw.collection('users/alice/dailyLogs').doc(date).set(dayDoc({ date }));
    }
    app.log.length = 0;

    await app.get('/');

    // The aggregation happened...
    assert.ok(
      app.log.includes('db.collectionGroup(dailyLogs).count'),
      `expected a count() over the dailyLogs collection group; trace was:\n${app.log.join('\n')}`,
    );
    // ...and no document sweep did. A full read of every log at 100k users is
    // ~40M reads (~$24) per refresh against ~40k (~$0.024) via count().
    assert.equal(
      app.log.includes('db.collectionGroup(dailyLogs).get'),
      false,
      'the dashboard must never read dailyLogs documents',
    );
    // Nor did any log content reach this process.
    assert.equal(
      app.log.some((entry) => /dailyLogs\)\.doc/.test(entry)),
      false,
    );
  });

  test('the dashboard renders no health data even when every account has some', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04', notes: 'secret note', mood: 'low' }));

    const response = await app.get('/');
    assert.doesNotMatch(response.body, /secret note/);
  });

  test('new/active buckets are computed from Auth metadata', async () => {
    const now = Date.parse('2026-08-07T00:00:00Z');
    const record = (uid, createdDaysAgo, seenDaysAgo) => ({
      uid,
      metadata: {
        creationTime: new Date(now - createdDaysAgo * DAY_MS).toUTCString(),
        lastRefreshTime:
          seenDaysAgo === null ? null : new Date(now - seenDaysAgo * DAY_MS).toUTCString(),
        lastSignInTime: null,
      },
    });
    const auth = {
      listUsers: async () => ({
        users: [
          record('a', 0.5, 0.5),
          record('b', 3, 3),
          record('c', 20, 20),
          record('d', 400, null),
        ],
        pageToken: undefined,
      }),
    };

    const swept = await sweepAuthRoster(auth, { now });
    assert.equal(swept.total, 4);
    assert.deepEqual(swept.newWithin, { 1: 1, 7: 2, 28: 3 });
    assert.deepEqual(swept.activeWithin, { 7: 2, 28: 3 });
  });

  test('activity windows are driven by REAL Auth metadata, not by row count', async () => {
    // The Auth emulator stamps `lastLoginAt` at creation, so "signed in" is not
    // what separates an active account from an idle one here — the WINDOW is.
    // Asking the same seeded data twice, from two vantage points in time, is
    // what proves the panel reads the timestamp at all: a panel that ignored it
    // would answer identically both times.
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedAccount(app.auth, { uid: 'bob', email: 'bob@example.com' });
    await signIn('alice@example.com');

    const today = await app.get('/');
    assert.match(today.body, /<div class="n">2<\/div><div class="k">active — last 7 days/);

    await panel.stop();
    panel = null;
    const later = await boot({ now: () => Date.now() + 10 * DAY_MS });
    const future = await later.get('/');
    // Ten days on, nobody has been seen inside 7 days, but everybody has inside 28.
    assert.match(future.body, /<div class="n">0<\/div><div class="k">active — last 7 days/);
    assert.match(future.body, /<div class="n">2<\/div><div class="k">active — last 28 days/);
    // And nobody is "new" in the last 24h any more either.
    assert.match(future.body, /<div class="n">0<\/div><div class="k">new — last 24h/);
  });
});

// =========================================================================
// 5. The audit record — written first, and load-bearing
// =========================================================================

describe('audit', () => {
  const seedDay = (app, uid = 'alice') =>
    app.raw
      .collection(`users/${uid}/dailyLogs`)
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04', notes: 'cramps all morning' }));

  test('the audit record is written BEFORE any health record is read', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedDay(app);
    app.log.length = 0;

    const response = await app.post('/users/alice/records', {
      reason: 'support ticket 412',
    });
    assert.equal(response.status, 200);
    assert.match(response.body, /cramps all morning/);

    // Both handles trace into ONE ordered log, so this is the real ordering,
    // not an assertion about a stand-in.
    const auditAt = app.log.findIndex((entry) => /audit\.collection\(adminAudit\).*create/.test(entry));
    const readAt = app.log.findIndex((entry) => /dailyLogs/.test(entry));
    assert.notEqual(auditAt, -1, `no audit write in trace:\n${app.log.join('\n')}`);
    assert.notEqual(readAt, -1, `no health read in trace:\n${app.log.join('\n')}`);
    assert.ok(
      auditAt < readAt,
      `audit write must precede the health read; trace was:\n${app.log.join('\n')}`,
    );
  });

  test('a FAILED audit write blocks the read entirely', async () => {
    const broken = {
      record: async () => {
        throw new Error('audit unavailable');
      },
    };
    const app = await boot({ audit: broken });
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedDay(app);
    app.log.length = 0;

    const response = await app.post('/users/alice/records', { reason: 'ticket 412' });
    assert.equal(response.status, 503);
    assert.match(response.body, /audit record could not be written/);
    assert.doesNotMatch(response.body, /cramps all morning/);
    assert.equal(
      app.log.some((entry) => /dailyLogs/.test(entry)),
      false,
      'no health record may be read when the audit write fails',
    );
  });

  test('an empty reason is refused, with no audit record and no read', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedDay(app);

    const response = await app.post('/users/alice/records', { reason: '   ' });
    assert.equal(response.status, 400);
    assert.match(response.body, /A reason is required/);
    assert.doesNotMatch(response.body, /cramps all morning/);

    const audits = await app.raw.collection(AUDIT_COLLECTION).get();
    assert.equal(
      audits.docs.filter((doc) => doc.data().view === 'record_browse').length,
      0,
    );

    // Two independent layers, asserted separately. The route's own 400 is the
    // friendly one; the audit log refusing to record a contentless reason is
    // what protects any FUTURE caller that forgets to check.
    await assert.rejects(
      createAuditLog(app.raw).record({
        actor: OWNER,
        targetUid: 'alice',
        view: 'record_browse',
        reason: '   ',
      }),
      /written reason is required/,
    );
  });

  test('the GET reason gate shows a form and NO content', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedDay(app);

    const response = await app.get('/users/alice/records');
    assert.equal(response.status, 200);
    assert.match(response.body, /name="reason"/);
    assert.doesNotMatch(response.body, /cramps all morning/);
  });

  test('the audit record names the actor, the target, the view and the reason', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await seedDay(app);

    await app.post('/users/alice/records', { reason: 'support ticket 412' });

    const audits = await app.raw.collection(AUDIT_COLLECTION).get();
    const entry = audits.docs.map((doc) => doc.data()).find((d) => d.view === 'record_browse');
    assert.ok(entry, 'no record_browse audit entry was written');
    assert.equal(entry.actor, OWNER);
    assert.equal(entry.targetUid, 'alice');
    assert.equal(entry.reason, 'support ticket 412');
    assert.ok(entry.at, 'the audit record must carry a server timestamp');
  });

  test('viewing account metadata is audited too, without demanding a reason', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });

    const response = await app.get('/users/alice');
    assert.equal(response.status, 200);

    const audits = await app.raw.collection(AUDIT_COLLECTION).get();
    const views = audits.docs.map((doc) => doc.data().view);
    assert.ok(views.includes('account_metadata'));
  });

  test('the audit collection is matched by NO rule, so app clients cannot touch it', async () => {
    // `firestore.rules` has no `match /{document=**}` catch-all, so a path no
    // rule names is denied. This asserts that property instead of assuming it —
    // and it is exactly why the panel needs ZERO change to the rules file.
    await loadRules(RULES);
    await clearData();
    const alice = user('alice');
    await assertDenied(
      getDoc(alice, `${AUDIT_COLLECTION}/some-entry`),
      'an app client reading an audit record',
    );
    await assertDenied(
      listDocs(alice, AUDIT_COLLECTION),
      'an app client listing the audit collection',
    );
    await assertDenied(
      setDoc(alice, `${AUDIT_COLLECTION}/forged`, { actor: 'me' }),
      'an app client forging an audit record',
    );
    await clearData();
  });
});

// =========================================================================
// 6. Read-only — no endpoint writes health data, ever
// =========================================================================

describe('read-only', () => {
  test('every mutating method throws on the panel handle', async () => {
    const app = await boot();
    const db = readOnly(app.raw, 'db');

    assert.throws(() => db.collection('users/alice/dailyLogs').doc('2026-08-04').set({}), ReadOnlyViolation);
    assert.throws(() => db.doc('users/alice/dailyLogs/2026-08-04').update({}), ReadOnlyViolation);
    assert.throws(() => db.doc('users/alice/dailyLogs/2026-08-04').delete(), ReadOnlyViolation);
    assert.throws(() => db.doc('users/alice/dailyLogs/2026-08-04').create({}), ReadOnlyViolation);
    assert.throws(() => db.collection('users/alice/dailyLogs').add({}), ReadOnlyViolation);
    assert.throws(() => db.batch(), ReadOnlyViolation);
    assert.throws(() => db.runTransaction(async () => {}), ReadOnlyViolation);
    assert.throws(() => db.bulkWriter(), ReadOnlyViolation);
    assert.throws(() => db.recursiveDelete(db.collection('users')), ReadOnlyViolation);
    // The set is not empty — an emptied denylist is a silently open handle.
    assert.ok(MUTATING_METHODS.size >= 8);
  });

  test('a snapshot cannot be used to escape back to a writable reference', async () => {
    const app = await boot();
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04' }));

    const db = readOnly(app.raw, 'db');
    const snapshot = await db.collection('users/alice/dailyLogs').get();
    assert.equal(snapshot.docs.length, 1);
    assert.throws(() => snapshot.docs[0].ref.delete(), ReadOnlyViolation);
    const single = await db.doc('users/alice/dailyLogs/2026-08-04').get();
    assert.throws(() => single.ref.set({}), ReadOnlyViolation);
  });

  test('driving EVERY endpoint leaves the users subtree byte-identical', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await app.raw
      .collection('users/alice/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04', notes: 'cramps all morning' }));
    await app.raw.doc('users/alice/settings/current').set({ updatedAt: 1 });
    await app.raw.doc('users/alice/devices/device-1').set({ logsCursor: new Date(1) });
    await app.raw.doc('users/alice/deletions/2026-07-01').set({ date: '2026-07-01' });
    await app.raw.doc('deletionRequests/alice').set({
      uid: 'alice',
      requestedAt: new Date(1),
      purgeAfter: new Date(2),
    });

    const snapshot = async () => {
      const parts = [];
      for (const name of ['dailyLogs', 'settings', 'devices', 'deletions']) {
        const docs = await app.raw.collection(`users/alice/${name}`).get();
        for (const doc of docs.docs) parts.push(`${doc.ref.path}=${JSON.stringify(doc.data())}`);
      }
      const request = await app.raw.doc('deletionRequests/alice').get();
      parts.push(`deletionRequests/alice=${JSON.stringify(request.data())}`);
      return parts.sort().join('\n');
    };

    const before = await snapshot();

    assert.equal((await app.get('/')).status, 200);
    assert.equal((await app.get('/users')).status, 200);
    assert.equal((await app.get('/users?q=alice')).status, 200);
    assert.equal((await app.get('/users/alice')).status, 200);
    assert.equal((await app.get('/users/alice/records')).status, 200);
    const records = await app.post('/users/alice/records', { reason: 'ticket 9' });
    assert.equal(records.status, 200);
    // Guard against a vacuous pass: the records page really did disclose content.
    assert.match(records.body, /cramps all morning/);

    assert.equal(await snapshot(), before, 'an endpoint mutated user data');

    // ...and the ONLY thing that was written is the audit trail.
    const audits = await app.raw.collection(AUDIT_COLLECTION).get();
    assert.ok(audits.size >= 1);
  });
});

// =========================================================================
// 7. Decoding the document shapes the app actually writes
// =========================================================================

describe('day decoding matches sync_mapper.dart', () => {
  test('reserved tag prefixes are grouped and 0-valued metrics are dropped', () => {
    const decoded = decodeDayTags({
      headache: true,
      cramps: true,
      sex_protected: true,
      med_ibuprofen: true,
      cm_eggwhite: true,
      pain: 6,
      // `0` means "unset" for EVERY numeric metric, weight included. Rendering
      // it as a reading would invent a measurement the user never made.
      weight: 0,
      water: 0,
      future_field: 'something new',
    });

    assert.deepEqual(decoded.symptoms, ['cramps', 'headache']);
    assert.deepEqual(
      decoded.groups.map((group) => `${group.label}:${group.values.join(',')}`).sort(),
      ['Cervical mucus:eggwhite', 'Medication taken:ibuprofen', 'Sexual activity:protected'],
    );
    assert.deepEqual(decoded.metrics, [{ key: 'pain', label: 'Pain (0–10)', value: 6 }]);
    assert.deepEqual(decoded.unrecognised, [
      { key: 'future_field', value: 'something new' },
    ]);
  });

  test('the full day view renders flow, symptoms, mood, notes, BBT and OPK', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    await app.raw.collection('users/alice/dailyLogs').doc('2026-08-04').set(
      dayDoc({
        date: '2026-08-04',
        flow: 4, // heavy
        mood: 'anxious',
        notes: 'cramps all morning',
        bbt: 36.7,
        opk: 'peak',
        symptoms: { headache: true, sex_unprotected: true, pain: 8 },
      }),
    );

    const response = await app.post('/users/alice/records', { reason: 'ticket 412' });
    assert.equal(response.status, 200);
    for (const expected of [
      '2026-08-04',
      'heavy',
      'anxious',
      'cramps all morning',
      '36.7',
      'peak',
      'headache',
      'unprotected',
      'Pain',
    ]) {
      assert.match(response.body, new RegExp(expected), `records view is missing ${expected}`);
    }
    // Current status is OBSERVED FACT only. The app's fertility guardrails are
    // structural (CLAUDE.md: never the word "safe" near fertility, no
    // synthesized percentage, qualitative bands only) and an operator panel
    // restating a calendar-method estimate as fact would be false precision at
    // one remove. So: no phase label, no band, no percentage, and never "safe".
    assert.match(response.body, /last logged day/);
    // Stripped of the stylesheet, which legitimately contains `width:100%`.
    const rendered = response.body.replace(/<style>[\s\S]*?<\/style>/, '');
    assert.doesNotMatch(rendered, /\bsafe\b/i);
    assert.doesNotMatch(rendered, /\d+\s?%/);
    assert.doesNotMatch(rendered, /luteal|follicular|ovulatory|cycle day/i);
  });
});

// =========================================================================
// 8. Account metadata resolves tickets without reading a log
// =========================================================================

describe('account metadata', () => {
  test('counts, date range, devices and settings, with no log content read', async () => {
    const app = await boot();
    await seedAccount(app.auth, { uid: 'alice', email: 'alice@example.com' });
    for (const date of ['2026-06-01', '2026-07-15', '2026-08-04']) {
      await app.raw
        .collection('users/alice/dailyLogs')
        .doc(date)
        .set(dayDoc({ date, notes: 'private note' }));
    }
    await app.raw.doc('users/alice/devices/device-1').set({
      logsCursor: new Date('2026-08-05T00:00:00Z'),
      deletionsCursor: new Date('2026-08-05T00:00:00Z'),
    });
    await app.raw.doc('users/alice/settings/current').set({
      updatedAt: Date.parse('2026-08-01T00:00:00Z'),
      pregnancyStartDate: Date.parse('2026-01-01T00:00:00Z'),
      themeMode: 'dark',
    });

    const response = await app.get('/users/alice');
    assert.equal(response.status, 200);
    assert.match(response.body, /<div class="n">3<\/div><div class="k">daily log documents/);
    assert.match(response.body, /2026-06-01/);
    assert.match(response.body, /2026-08-04/);
    assert.match(response.body, /device-1/);
    // No log content, and no preference content either — the settings read is a
    // two-field projection, so the pregnancy start date (health data) and the
    // theme never enter this process. Asserted on the VALUES, since the page
    // legitimately names the field to explain why it is not shown.
    assert.doesNotMatch(response.body, /private note/);
    assert.doesNotMatch(response.body, /2026-01-01/);
    assert.doesNotMatch(response.body, /<dd>dark<\/dd>/);

    // Not merely "not rendered" — not FETCHED. The trace shows the settings
    // read is a two-field projection, so the pregnancy start date never enters
    // this process at all.
    assert.ok(
      app.log.includes('db.collection(users/alice/settings).select(updatedAt)'),
      `settings must be read through a projection; trace was:\n${app.log.join('\n')}`,
    );
    assert.equal(
      app.log.includes('db.collection(users/alice/settings).get'),
      false,
      'the settings document must never be fetched whole',
    );
  });

  test('an orphaned subtree with no Auth user is reported as such', async () => {
    const app = await boot();
    await app.raw
      .collection('users/ghost/dailyLogs')
      .doc('2026-08-04')
      .set(dayDoc({ date: '2026-08-04' }));

    const response = await app.get('/users/ghost');
    assert.equal(response.status, 200);
    assert.match(response.body, /No Firebase Auth user for this uid/);
    assert.match(response.body, /<div class="n">1<\/div><div class="k">daily log documents/);
  });
});
