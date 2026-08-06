// A dependency-free client for the Firestore emulator's REST API.
//
// The conventional tool for rules tests is `@firebase/rules-unit-testing` from
// npm. This project has a hard "no new dependencies without asking" rule and no
// `package.json` at all, so the same job is done here against the emulator's
// own REST surface using nothing but Node's built-ins. What the library adds on
// top of this file is convenience, not coverage: the assertions below exercise
// the identical wire protocol the Flutter app's Firestore SDK uses.
//
// Everything here talks ONLY to the local emulator. No remote Firebase project
// is contacted: the project id is `demo-*`, which `firebase-tools` treats as a
// demo project and refuses to resolve against production.

import fs from 'node:fs';

/** The emulated project. The `demo-` prefix is what guarantees "local only". */
export const PROJECT_ID = 'demo-lunatrack';

/**
 * The NAMED database LunaTrack owns — see `kLunaDatabaseId` in
 * `lib/services/firestore_ref.dart`. Tests run against the same database id the
 * app uses, so a rule scoped to the wrong database would show up here.
 */
export const DATABASE_ID = 'lunatrack';

/**
 * `firebase emulators:exec` exports `FIRESTORE_EMULATOR_HOST` for its child
 * process, so the port in `firebase.json` can change without touching tests.
 */
const HOST = `http://${process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8098'}`;

const DOCS = `${HOST}/v1/projects/${PROJECT_ID}/databases/${DATABASE_ID}/documents`;

const base64url = (value) =>
  Buffer.from(JSON.stringify(value)).toString('base64url');

/**
 * An unsigned ID token for [uid].
 *
 * The emulator decodes bearer tokens without verifying the signature, which is
 * exactly how `@firebase/rules-unit-testing` mints its own contexts. This is
 * the whole point of the "shared Auth pool" threat model: obtaining a VALID
 * token is assumed to be easy — every other app in the project can do it — so
 * the rules must not care that a token exists, only whose it is.
 */
function idToken(uid) {
  const now = Math.floor(Date.now() / 1000);
  return [
    base64url({ alg: 'none', kid: 'fakekid', type: 'JWT' }),
    base64url({
      iss: `https://securetoken.google.com/${PROJECT_ID}`,
      aud: PROJECT_ID,
      iat: now,
      exp: now + 3600,
      auth_time: now,
      sub: uid,
      user_id: uid,
      email: `${uid}@example.com`,
      email_verified: true,
      firebase: { sign_in_provider: 'password', identities: {} },
    }),
    '',
  ].join('.');
}

/**
 * A caller.
 *
 * - `user('alice')` — a signed-in user, subject to the rules.
 * - `anonymous()`   — no `Authorization` header at all.
 * - `admin()`       — the emulator's `owner` bearer, which BYPASSES rules. Used
 *                     only to seed and inspect state, never to assert with.
 */
export const user = (uid) => ({ label: uid, auth: `Bearer ${idToken(uid)}` });
export const anonymous = () => ({ label: 'unauthenticated', auth: null });
const admin = () => ({ label: 'admin', auth: 'Bearer owner' });

async function call(method, url, { as, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  const caller = as ?? anonymous();
  if (caller.auth) headers.Authorization = caller.auth;
  const response = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, body: text };
}

/** Installs [rulesPath] as the ruleset for the named database under test. */
export async function loadRules(rulesPath) {
  const result = await call(
    'PUT',
    `${HOST}/emulator/v1/projects/${PROJECT_ID}/databases/${DATABASE_ID}:securityRules`,
    {
      as: admin(),
      body: {
        rules: {
          files: [
            { name: 'firestore.rules', content: fs.readFileSync(rulesPath, 'utf8') },
          ],
        },
      },
    },
  );
  if (result.status !== 200) {
    throw new Error(`could not load ${rulesPath}: ${result.status} ${result.body}`);
  }
}

/** Wipes the database between tests (admin endpoint, bypasses rules). */
export async function clearData() {
  const result = await call(
    'DELETE',
    `${HOST}/emulator/v1/projects/${PROJECT_ID}/databases/${DATABASE_ID}/documents`,
    { as: admin() },
  );
  if (result.status !== 200) {
    throw new Error(`could not clear data: ${result.status} ${result.body}`);
  }
}

// --- value encoding -------------------------------------------------------

const encodeValue = (value) => {
  if (value === null) return { nullValue: null };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeValue) } };
  }
  return { mapValue: { fields: encodeFields(value) } };
};

const encodeFields = (data) =>
  Object.fromEntries(Object.entries(data).map(([k, v]) => [k, encodeValue(v)]));

const docName = (path) =>
  `projects/${PROJECT_ID}/databases/${DATABASE_ID}/documents/${path}`;

// --- operations -----------------------------------------------------------

/** `doc.get()` — the `get` rule operation. */
export const getDoc = (as, path) => call('GET', `${DOCS}/${path}`, { as });

/** `collection.get()` — the `list` rule operation. */
export const listDocs = (as, path) => call('GET', `${DOCS}/${path}`, { as });

/**
 * `collection.where(...).get()` — also a `list`, via the query surface the
 * cursor-scoped pulls in `SyncService` actually use.
 */
export const runQuery = (as, parentPath, structuredQuery) =>
  call('POST', `${DOCS}${parentPath ? `/${parentPath}` : ''}:runQuery`, {
    as,
    body: { structuredQuery },
  });

/** `doc.set(data)` — a `create` or an `update` depending on what is there. */
export const setDoc = (as, path, data) =>
  call('POST', `${DOCS}:commit`, {
    as,
    body: {
      writes: [{ update: { name: docName(path), fields: encodeFields(data) } }],
    },
  });

/**
 * `doc.set({..., 'x': FieldValue.serverTimestamp()})`.
 *
 * [serverTimestampFields] are written as REQUEST_TIME transforms, which is how
 * `AccountDeletionService.requestDeletion` stamps `requestedAt` and the only
 * way `request.resource.data.requestedAt == request.time` can hold.
 */
export const setDocWithServerTime = (as, path, data, serverTimestampFields) =>
  call('POST', `${DOCS}:commit`, {
    as,
    body: {
      writes: [
        {
          update: { name: docName(path), fields: encodeFields(data) },
          updateTransforms: serverTimestampFields.map((fieldPath) => ({
            fieldPath,
            setToServerValue: 'REQUEST_TIME',
          })),
        },
      ],
    },
  });

/** `doc.delete()`. */
export const deleteDoc = (as, path) =>
  call('POST', `${DOCS}:commit`, {
    as,
    body: { writes: [{ delete: docName(path) }] },
  });

/** Seeds a document with rules bypassed, so a test can assert on READ paths. */
export const seed = (path, data) => setDoc(admin(), path, data);

/** Reads a document with rules bypassed, to prove a denied write wrote nothing. */
export const readAsAdmin = (path) => getDoc(admin(), path);

// --- assertions -----------------------------------------------------------

const describe = (result) =>
  `HTTP ${result.status} ${result.body.replace(/\s+/g, ' ').slice(0, 240)}`;

/** Asserts the operation was ALLOWED by the rules. */
export async function assertAllowed(operation, what) {
  const result = await operation;
  if (result.status !== 200) {
    throw new Error(`expected ${what} to be ALLOWED, got ${describe(result)}`);
  }
  return result;
}

/**
 * Asserts the operation was DENIED by the RULES specifically.
 *
 * The status check alone is not enough: the emulator answers a failed
 * `currentDocument` precondition with 409 ALREADY_EXISTS and a malformed
 * request with 400, and either would let a test pass while the rules were wide
 * open. Only PERMISSION_DENIED counts.
 */
export async function assertDenied(operation, what) {
  const result = await operation;
  if (result.status === 200) {
    throw new Error(`expected ${what} to be DENIED, but it SUCCEEDED`);
  }
  if (!result.body.includes('PERMISSION_DENIED')) {
    throw new Error(
      `expected ${what} to be denied BY THE RULES, but failed for another ` +
        `reason: ${describe(result)}`,
    );
  }
  return result;
}
