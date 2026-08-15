// Harness for the operator-panel suite.
//
// Same posture as `firebase_test/emulator.mjs`: everything runs against a LOCAL
// emulator under the project id `demo-lunatrack`, whose `demo-` prefix is what
// makes `firebase-tools` refuse to resolve it against production. Nothing here
// contacts a remote Firebase project, and there is deliberately no `.firebaserc`
// anywhere in the repo for a command to fall back on.
//
// Dependencies: `firebase-admin` and `express` only (both pre-authorised), plus
// Node built-ins. No test framework, no HTTP client library, no JWT library.

import crypto from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { createApp } from '../src/app.js';
import { createAuditLog } from '../src/audit.js';
import { parseAdminEmails } from '../src/env.js';
import { readOnly } from '../src/readonly.js';
import { requireAdminIdentity, IAP_ISSUER } from '../src/iap.js';

export const PROJECT_ID = 'demo-lunatrack';
export const DATABASE_ID = 'lunatrack';
export const AUDIENCE = '/projects/000000000000/global/backendServices/test';
export const OWNER = 'owner@example.com';

const AUTH_HOST = () =>
  `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9098'}`;

// --- a signing key that is NOT Google's -----------------------------------

/**
 * A P-256 keypair standing in for Google's IAP signer, plus a second, unrelated
 * one used to forge assertions.
 *
 * The forgery test is the point of having two: a token that is structurally
 * perfect, unexpired, correctly addressed and signed by the wrong key must be
 * refused. That is the only thing separating "IAP verified this" from "somebody
 * sent a header".
 */
function keypair(kid) {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ec', {
    namedCurve: 'P-256',
  });
  const jwk = { ...publicKey.export({ format: 'jwk' }), kid, alg: 'ES256', use: 'sig' };
  return { kid, privateKey, jwk };
}

export const GOOGLE_KEY = keypair('test-iap-key');
export const IMPOSTOR_KEY = keypair('test-iap-key'); // same kid, different key

export const JWKS = { keys: [GOOGLE_KEY.jwk] };

const b64 = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');

/** Mints an IAP-shaped assertion. Every field is overridable so tests can break one at a time. */
export function mintAssertion({
  email = OWNER,
  audience = AUDIENCE,
  issuer = IAP_ISSUER,
  alg = 'ES256',
  kid = GOOGLE_KEY.kid,
  key = GOOGLE_KEY.privateKey,
  iat = Math.floor(Date.now() / 1000),
  exp = Math.floor(Date.now() / 1000) + 600,
  sign = true,
} = {}) {
  const header = b64({ alg, kid, typ: 'JWT' });
  const payload = b64({ iss: issuer, aud: audience, email, sub: `sub-${email}`, iat, exp });
  if (!sign) return `${header}.${payload}.`;
  const signature = crypto
    .sign('sha256', Buffer.from(`${header}.${payload}`), {
      key,
      dsaEncoding: 'ieee-p1363',
    })
    .toString('base64url');
  return `${header}.${payload}.${signature}`;
}

// --- a Firestore handle that records what it was asked to do ---------------

/**
 * Wraps a Firestore handle and appends every call to [log] as a readable chain
 * such as `db.collectionGroup(dailyLogs).count.get`.
 *
 * This is how the suite proves two things it could not otherwise observe from
 * the outside:
 *
 *  1. statistics really are `count()` aggregations and not document sweeps, and
 *  2. the audit write really does happen BEFORE the first health-record read —
 *     both handles trace into ONE shared log, so the log's own ordering is the
 *     evidence, with no injected fake standing in for the real call.
 */
export function tracing(target, log, path = 'db') {
  if (target === null || typeof target !== 'object') return target;
  return new Proxy(target, {
    get(object, property) {
      const value = Reflect.get(object, property, object);
      if (typeof value !== 'function' || typeof property !== 'string') {
        if (property === 'ref') return tracing(value, log, `${path}.ref`);
        if (property === 'docs' && Array.isArray(value)) {
          return value.map((entry, i) => tracing(entry, log, `${path}.docs[${i}]`));
        }
        return value;
      }
      return (...args) => {
        const arg = args.length && typeof args[0] === 'string' ? `(${args[0]})` : '';
        const next = `${path}.${property}${arg}`;
        log.push(next);
        const result = value.apply(object, args);
        if (result && typeof result.then === 'function') {
          return result.then((resolved) => wrap(resolved, next));
        }
        return wrap(result, next);
      };
    },
  });

  function wrap(result, next) {
    if (result === null || typeof result !== 'object') return result;
    if (Array.isArray(result)) return result;
    const interesting =
      typeof result.collection === 'function' ||
      typeof result.doc === 'function' ||
      typeof result.where === 'function' ||
      typeof result.count === 'function' ||
      typeof result.get === 'function' ||
      Array.isArray(result.docs);
    return interesting ? tracing(result, log, next) : result;
  }
}

// --- Firebase handles ------------------------------------------------------

let appSeq = 0;

/**
 * Admin SDK handles against the emulator.
 *
 * No credential is configured: with `FIRESTORE_EMULATOR_HOST` and
 * `FIREBASE_AUTH_EMULATOR_HOST` exported by `firebase emulators:exec`, the SDK
 * never asks for a token. That is also the reason this suite cannot
 * accidentally reach a real project even if the project id were changed.
 */
export function firebaseHandles() {
  const app = initializeApp({ projectId: PROJECT_ID }, `panel-test-${appSeq++}`);
  const raw = getFirestore(app, DATABASE_ID);
  return { app, auth: getAuth(app), raw, close: () => deleteApp(app) };
}

// --- panel under test ------------------------------------------------------

/**
 * Boots the real Express app on an ephemeral port.
 *
 * Everything is real except the IAP signing key: the identity middleware, the
 * read-only handle, the audit log, the routes and the views are the shipping
 * ones.
 */
export async function startPanel({
  adminEmails = OWNER,
  audit: auditOverride = null,
  devIdentity = null,
  now = () => Date.now(),
  jwks = JWKS,
} = {}) {
  const log = [];
  const { app: fbApp, auth, raw, close } = firebaseHandles();

  // Two handles, one log. The audit log gets a WRITABLE handle; everything else
  // gets one on which every mutating method throws.
  const auditDb = tracing(raw, log, 'audit');
  const db = readOnly(tracing(raw, log, 'db'), 'db');

  const expressApp = createApp({
    auth,
    db,
    audit: auditOverride ?? createAuditLog(auditDb),
    config: { maxRosterSweep: 50000, pageSize: 25 },
    now,
    identity: requireAdminIdentity({
      audience: AUDIENCE,
      adminEmails: parseAdminEmails(adminEmails),
      fetchKeys: async () => jwks,
      devIdentity,
      // Deliberately the REAL clock, even when the app is given a shifted one:
      // a test that moves the app's "now" forward to exercise an activity
      // window must not simultaneously expire its own IAP assertion.
      now: () => Date.now(),
    }),
  });

  const server = await new Promise((resolve) => {
    const s = expressApp.listen(0, '127.0.0.1', () => resolve(s));
  });
  const url = `http://127.0.0.1:${server.address().port}`;

  return {
    url,
    log,
    raw,
    auth,
    fbApp,
    async get(path, { token = mintAssertion(), headers = {} } = {}) {
      return request('GET', `${url}${path}`, { token, headers });
    },
    async post(path, form, { token = mintAssertion(), headers = {} } = {}) {
      return request('POST', `${url}${path}`, {
        token,
        headers: { 'content-type': 'application/x-www-form-urlencoded', ...headers },
        body: new URLSearchParams(form ?? {}).toString(),
      });
    },
    async stop() {
      await new Promise((resolve) => server.close(resolve));
      await close();
    },
  };
}

async function request(method, url, { token, headers, body }) {
  const all = { ...headers };
  if (token !== null) all['x-goog-iap-jwt-assertion'] = token;
  const response = await fetch(url, { method, headers: all, body });
  return { status: response.status, body: await response.text() };
}

// --- seeding ---------------------------------------------------------------

/**
 * Creates an Auth account. Note what is NOT created: a `users/{uid}` document.
 *
 * That absence is the trap the whole roster design exists around —
 * `SyncService` never writes the parent document, so a panel that enumerated
 * `collection('users')` would show an empty product forever while every metric
 * quietly read zero.
 */
export async function seedAccount(auth, { uid, email, password = 'passw0rd!' }) {
  await auth.createUser({ uid, email, password });
  return uid;
}

/** Signs a user in through the Auth emulator so `lastSignInTime` becomes real. */
export async function signIn(email, password = 'passw0rd!') {
  const response = await fetch(
    `${AUTH_HOST()}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  if (!response.ok) throw new Error(`emulator sign-in failed: ${await response.text()}`);
  return response.json();
}

/** A `dailyLogs` document shaped exactly like `dailyLogToMap` writes them. */
export const dayDoc = ({
  date,
  flow = 3,
  symptoms = {},
  mood = null,
  notes = null,
  bbt = null,
  opk = null,
  deviceId = 'device-1',
  updatedAt = Date.now(),
} = {}) => ({
  date,
  flow,
  symptoms,
  mood,
  notes,
  bbt,
  opk,
  createdAt: updatedAt,
  updatedAt,
  deviceId,
});

/** Wipes the emulated database between tests. */
export async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8099';
  const response = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/${DATABASE_ID}/documents`,
    { method: 'DELETE', headers: { Authorization: 'Bearer owner' } },
  );
  if (!response.ok) throw new Error(`could not clear firestore: ${response.status}`);
}

/** Wipes the emulated Auth project between tests. */
export async function clearAuth() {
  const response = await fetch(
    `${AUTH_HOST()}/emulator/v1/projects/${PROJECT_ID}/accounts`,
    { method: 'DELETE', headers: { Authorization: 'Bearer owner' } },
  );
  if (!response.ok) throw new Error(`could not clear auth: ${response.status}`);
}
