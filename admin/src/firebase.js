// Admin SDK wiring — SERVER SIDE ONLY.
//
// The browser never receives a Firebase credential, the Admin SDK, a client SDK
// or a raw Firestore handle. It receives HTML this process rendered. That is
// the whole reason a hosted panel can be built at all: an admin credential in a
// browser is an admin credential in whatever else that browser is running.
//
// Application Default Credentials only. There is deliberately no code path that
// reads a service-account JSON file: a key file that has to exist somewhere is a
// key file that gets committed, emailed or left in an image. On Cloud Run the
// runtime service account IS the credential.

import { initializeApp, applicationDefault, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

import { readOnly } from './readonly.js';

/**
 * Builds the Admin SDK handles for [config].
 *
 * Returns three things, and the split is the point:
 *
 * - `auth`     — the roster source. `users/{uid}` documents do not exist.
 * - `db`       — READ-ONLY. Every view and query gets this one.
 * - `auditDb`  — writable, and handed to nothing except `createAuditLog`.
 */
export function createFirebase(config) {
  const app =
    getApps().find((existing) => existing.name === 'lunatrack-admin') ??
    initializeApp(
      {
        credential: applicationDefault(),
        // Never hardcoded — see `env.js`. The owning project is an open
        // decision, and the untracked root `firebase.json` currently names an
        // unrelated production project.
        projectId: config.projectId,
      },
      'lunatrack-admin',
    );

  // The NAMED database `lunatrack`, never `(default)`. A `(default)` database
  // carries one ruleset for every app in the project, which is exactly why the
  // Flutter app uses a named one (`lunaFirestore()` /
  // `lib/services/firestore_ref.dart`). Reading `(default)` here would read a
  // different database and quietly report zeros.
  const auditDb = getFirestore(app, config.databaseId);

  return {
    auth: getAuth(app),
    db: readOnly(auditDb, 'db'),
    auditDb,
  };
}
