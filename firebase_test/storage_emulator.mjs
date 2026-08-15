// A dependency-free REST client for the Cloud STORAGE emulator.
//
// `emulator.mjs` is the equivalent for Firestore, and this is deliberately a
// sibling rather than an extension of it: the two emulators speak entirely
// different APIs. Firestore is `/v1/projects/.../documents` with a JSON
// document encoding; Storage is the GCS-shaped `/v0/b/{bucket}/o` with raw
// bodies, query-string object names, and a separate `?alt=media` for content.
//
// No npm packages, for the same reason the Firestore harness has none: the test
// suite must run on a fresh clone with nothing but Node and a JDK, and a rules
// suite whose own dependencies could change behaviour is not evidence.
//
// Auth is the same trick — an UNSIGNED bearer token the emulator decodes
// without verifying. That is the threat model, not a shortcut: in a Firebase
// project shared with unrelated apps, obtaining a valid token is assumed to be
// trivial, so the rules must never care that a token exists, only whose it is.

import fs from 'node:fs';

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? 'demo-lunatrack';
const HOST = `http://${process.env.FIREBASE_STORAGE_EMULATOR_HOST ?? '127.0.0.1:9599'}`;

/** The bucket under test. Any name works against the emulator. */
export const BUCKET = `${PROJECT_ID}.firebasestorage.app`;

const base64url = (value) =>
  Buffer.from(JSON.stringify(value)).toString('base64url');

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

export const user = (uid) => ({ label: uid, auth: `Bearer ${idToken(uid)}` });
export const anonymous = () => ({ label: 'unauthenticated', auth: null });
const admin = () => ({ label: 'admin', auth: 'Bearer owner' });

const encode = (objectPath) => encodeURIComponent(objectPath);

async function call(
  method,
  url,
  { as, body, contentType, extraHeaders, rawResponse } = {},
) {
  const headers = { ...(extraHeaders ?? {}) };
  const caller = as ?? anonymous();
  if (caller.auth) headers.Authorization = caller.auth;
  if (contentType) headers['Content-Type'] = contentType;
  const response = await fetch(url, { method, headers, body });
  const text = await response.text();
  return rawResponse
      ? { status: response.status, body: text, headers: response.headers }
      : { status: response.status, body: text };
}

/** Installs [rulesPath] as the bucket's ruleset. */
export async function loadRules(rulesPath) {
  const result = await call(
    'PUT',
    `${HOST}/internal/setRules`,
    {
      as: admin(),
      contentType: 'application/json',
      body: JSON.stringify({
        rules: {
          files: [
            { name: 'storage.rules', content: fs.readFileSync(rulesPath, 'utf8') },
          ],
        },
      }),
    },
  );
  if (result.status !== 200) {
    throw new Error(`could not load ${rulesPath}: ${result.status} ${result.body}`);
  }
}

/** Removes every object (admin endpoint, bypasses rules). */
export async function clearStorage() {
  await call('DELETE', `${HOST}/internal/reset`, { as: admin() });
}

/**
 * Uploads bytes AS a caller, so rules apply.
 *
 * Uses the RESUMABLE protocol, which is what `putFile` does in production —
 * and here it is not a stylistic choice. The simple `uploadType=media`
 * endpoint stores every object as `application/octet-stream` no matter what
 * `Content-Type` is sent (verified against the emulator four different ways),
 * so `request.resource.contentType` in the rules would be a constant and the
 * whole content-type allowlist would be untestable — worse, it would appear
 * tested. The resumable start request carries the real metadata.
 *
 * Rules are evaluated at the START step, where the size and content type are
 * declared, so a refusal surfaces there rather than after the bytes move.
 */
export async function upload(
  as,
  objectPath,
  { bytes = 16, contentType = 'image/jpeg', metadata } = {},
) {
  const start = await call(
    'POST',
    `${HOST}/v0/b/${BUCKET}/o?${new URLSearchParams({ name: objectPath })}`,
    {
      as,
      contentType: 'application/json',
      body: JSON.stringify({
        name: objectPath,
        contentType,
        // Declared up front so `underSizeCap()` sees the real size at the
        // moment the rules run, exactly as a real client declares it.
        size: bytes,
        ...(metadata ?? {}),
      }),
      extraHeaders: {
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Type': contentType,
      },
      rawResponse: true,
    },
  );
  if (start.status < 200 || start.status >= 300) return start;

  const uploadUrl = start.headers.get('x-goog-upload-url');
  if (!uploadUrl) {
    throw new Error(`resumable start gave no upload URL: ${start.body}`);
  }
  return call('POST', uploadUrl, {
    as,
    body: Buffer.alloc(bytes, 1),
    extraHeaders: {
      'X-Goog-Upload-Command': 'upload, finalize',
      'X-Goog-Upload-Offset': '0',
    },
  });
}

/** Seeds an object bypassing rules, so a test can assert on READING it. */
export const seed = (objectPath, options) => upload(admin(), objectPath, options);

export const download = (as, objectPath) =>
  call('GET', `${HOST}/v0/b/${BUCKET}/o/${encode(objectPath)}?alt=media`, { as });

export const getMetadata = (as, objectPath) =>
  call('GET', `${HOST}/v0/b/${BUCKET}/o/${encode(objectPath)}`, { as });

export const list = (as, prefix) =>
  call(
    'GET',
    `${HOST}/v0/b/${BUCKET}/o?${new URLSearchParams({ prefix, delimiter: '/' })}`,
    { as },
  );

export const remove = (as, objectPath) =>
  call('DELETE', `${HOST}/v0/b/${BUCKET}/o/${encode(objectPath)}`, { as });

/**
 * Asserts an operation was PERMITTED.
 *
 * Anything 2xx counts. A 404 does not: "the object is not there" is not "you
 * were allowed".
 */
export async function assertAllowed(promise, what) {
  const { status, body } = await promise;
  if (status < 200 || status >= 300) {
    throw new Error(`expected ${what} to be ALLOWED, got ${status}: ${body}`);
  }
}

/**
 * Asserts an operation was DENIED BY THE RULES.
 *
 * Deliberately strict about which failures count, mirroring the Firestore
 * harness. A 400 (malformed request) or a 404 (wrong path) would let a test
 * pass for a reason that has nothing to do with authorisation — which is how a
 * rules suite silently stops testing rules. Only 401/403 are evidence.
 */
export async function assertDenied(promise, what) {
  const { status, body } = await promise;
  if (status !== 401 && status !== 403) {
    throw new Error(
      `expected ${what} to be DENIED by the rules, got ${status}: ${body}`,
    );
  }
}
