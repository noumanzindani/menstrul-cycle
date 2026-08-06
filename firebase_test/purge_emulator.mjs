// Harness for the account-deletion purge suite (`purge.test.mjs`).
//
// Sibling of `emulator.mjs`, and deliberately a different shape from it:
//
// - `emulator.mjs` tests `firestore.rules`, so it must speak the wire protocol
//   a hostile CLIENT speaks and must NOT use a privileged SDK.
// - This file tests the PURGE, which runs as a Cloud Function on the Admin SDK.
//   The Admin SDK BYPASSES security rules, and that is precisely why the purge
//   has to re-derive its own preconditions server-side. Testing it through
//   anything else would test a code path that does not exist in production.
//
// So the subject-under-test is driven with the real `firebase-admin` clients
// (resolved out of `functions/node_modules`, the only two pre-authorised
// dependencies in this repo), while seeding and assertions go through the
// emulator's own REST/admin endpoints — a different mechanism from the one
// under test, so a broken SDK path cannot make its own assertions pass.
//
// Everything here talks ONLY to the local emulators. The project id is
// `demo-lunatrack`; `firebase-tools` treats any `demo-*` id as emulator-only and
// refuses to resolve it against production, and there is deliberately no
// `.firebaserc` for any command to fall back into.

import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { PROJECT_ID, DATABASE_ID, readAsAdmin } from './emulator.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const functionsDir = path.join(here, '..', 'functions');

/**
 * `firebase-admin` lives in `functions/node_modules`, not next to this file, so
 * resolution is anchored at the functions package rather than at `firebase_test`.
 */
const requireFromFunctions = createRequire(
  path.join(functionsDir, 'package.json'),
);

/**
 * The module under test.
 *
 * `LUNA_PURGE_MODULE` lets `purge_mutation_check.mjs` point the whole suite at a
 * mutated copy — the same trick `LUNA_RULES_FILE` plays for the rules suite.
 * `purge.js` deliberately requires nothing but Node built-ins, so a copy of it
 * alone in a temp directory still loads.
 */
export const PURGE_MODULE =
  process.env.LUNA_PURGE_MODULE ?? path.join(functionsDir, 'purge.js');

export const purge = requireFromFunctions(PURGE_MODULE);

const AUTH_HOST = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9114'}`;

// --- admin clients (the production wiring, pointed at the emulators) -------

const { initializeApp } = requireFromFunctions('firebase-admin/app');
const { getFirestore } = requireFromFunctions('firebase-admin/firestore');
const { getAuth } = requireFromFunctions('firebase-admin/auth');

// No credential and no service account: with `FIRESTORE_EMULATOR_HOST` /
// `FIREBASE_AUTH_EMULATOR_HOST` set by `firebase emulators:exec`, the Admin SDK
// talks to localhost and never mints a token against a real project.
const app = initializeApp({ projectId: PROJECT_ID });

/**
 * The NAMED database, exactly as `lib/services/firestore_ref.dart` requires.
 * `getFirestore(app)` alone would target `(default)`, which carries a different
 * ruleset and is not where LunaTrack's data lives.
 */
export const firestore = getFirestore(app, DATABASE_ID);

export const auth = getAuth(app);

/** The production auth deleter the scheduled function injects. */
export const deleteAuthUser = (uid) => auth.deleteUser(uid);

// --- Auth emulator state ---------------------------------------------------

/** Creates an Auth account so the purge has something real to delete. */
export const createAuthUser = (uid) => auth.createUser({ uid });

/** True when [uid] still has a Firebase Auth account. */
export async function authUserExists(uid) {
  try {
    await auth.getUser(uid);
    return true;
  } catch (error) {
    if (error.code === 'auth/user-not-found') return false;
    throw error;
  }
}

/** Wipes every emulated Auth account between tests. */
export async function clearAuth() {
  const response = await fetch(
    `${AUTH_HOST}/emulator/v1/projects/${PROJECT_ID}/accounts`,
    { method: 'DELETE', headers: { Authorization: 'Bearer owner' } },
  );
  if (!response.ok) {
    throw new Error(`could not clear auth: ${response.status}`);
  }
}

// --- test doubles ----------------------------------------------------------

/**
 * A Firestore handle that behaves normally until `shouldFail(path)` says
 * otherwise, at which point `collection()` throws.
 *
 * This is how a crash *mid-sweep* is simulated: a real timeout or a killed
 * instance stops the job at an arbitrary point, and what matters is the state it
 * leaves behind. Only the three members `purge.js` is allowed to use are
 * forwarded, so a future implementation that reaches for some other Firestore
 * API fails loudly here instead of silently escaping the fault injection.
 */
export const firestoreFailingOn = (shouldFail, real = firestore) => ({
  collection(collectionPath) {
    if (shouldFail(collectionPath)) {
      throw new Error(`simulated crash reading ${collectionPath}`);
    }
    return real.collection(collectionPath);
  },
  doc: (docPath) => real.doc(docPath),
  batch: () => real.batch(),
});

/** A logger that records instead of printing, so tests can inspect output. */
export function recordingLogger() {
  const entries = [];
  const record = (level) => (message, payload) =>
    entries.push({ level, message, payload });
  return {
    entries,
    info: record('info'),
    warn: record('warn'),
    error: record('error'),
  };
}

// --- assertions ------------------------------------------------------------
//
// Read back over the emulator's REST surface (`readAsAdmin`), NOT through the
// same Admin SDK handle the purge writes with: an assertion that shares a client
// — and therefore a cache, a retry policy and a serializer — with the code under
// test can confirm its own mistakes.

/** Every document id in a collection. */
export async function idsIn(collectionPath) {
  const result = await readAsAdmin(collectionPath);
  if (result.status !== 200) {
    throw new Error(`could not list ${collectionPath}: HTTP ${result.status}`);
  }
  const parsed = JSON.parse(result.body);
  return (parsed.documents ?? [])
    .map((document) => document.name.split('/').pop())
    .sort();
}

/** True when the document exists. */
export async function docExists(docPath) {
  const result = await readAsAdmin(docPath);
  if (result.status === 200) return true;
  if (result.status === 404) return false;
  throw new Error(`could not read ${docPath}: HTTP ${result.status}`);
}
