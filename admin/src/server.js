// Entry point.
//
// This process is UNSAFE if it is reachable without Google Cloud IAP in front
// of it. See `admin/README.md`. Nothing in this file can enforce that; what it
// can do is refuse to start without the configuration that makes the identity
// check meaningful, which `readConfig` does.

import { createApp } from './app.js';
import { createAuditLog } from './audit.js';
import { createFirebase } from './firebase.js';
import { createIapKeyFetcher, requireAdminIdentity } from './iap.js';
import { readConfig } from './env.js';

const config = readConfig();
const { auth, db, auditDb } = createFirebase(config);

const app = createApp({
  auth,
  db,
  audit: createAuditLog(auditDb),
  config,
  identity: requireAdminIdentity({
    audience: config.iapAudience,
    adminEmails: config.adminEmails,
    fetchKeys: createIapKeyFetcher(),
    devIdentity: config.devIdentity,
  }),
});

app.listen(config.port, () => {
  if (config.devIdentity) {
    console.warn(
      '*** IAP verification is BYPASSED (ADMIN_DEV_UNSAFE_IDENTITY). This is ' +
        'only reachable because FIRESTORE_EMULATOR_HOST is set. Never run this ' +
        'configuration against a real project. ***',
    );
  }
  console.log(
    `LunaTrack operator panel on :${config.port} — project ${config.projectId}, ` +
      `database ${config.databaseId}. MUST be behind IAP.`,
  );
});
