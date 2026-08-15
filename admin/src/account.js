// Account detail — METADATA ONLY.
//
// This view is the point of the whole design. Almost every support ticket
// ("did my data sync?", "my new phone is empty", "I deleted my account and it
// is still there") is answerable from document COUNTS, date RANGES, device
// cursors and sync timestamps — without reading one line of what the user
// logged. So this page exists, it is one click from the roster, and the health
// content sits behind a separate, audited, reason-gated door.
//
// Nothing here reads a `dailyLogs` document's fields. The earliest/latest dates
// come from the document IDS (`syncDocId` in `sync_mapper.dart` makes the id the
// ISO date) via `.select()` with no field list, which asks Firestore for
// references only. Two document reads, zero health content in this process.

import {
  AccountDeletionService,
  DATE_ID,
  dailyLogsPath,
  deletionsPath,
  devicesPath,
  settingsPath,
} from './paths.js';
import { countOrError } from './stats.js';
import { createdAt, lastSeenAt } from './stats.js';

const toDate = (value) => {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'number') return new Date(value);
  return null;
};

/**
 * The first or last day document id in the collection, without reading content.
 *
 * Ordered on the `date` FIELD, not on `__name__`: Firestore has no descending
 * key index, so `orderBy(documentId(), 'desc')` fails outright with
 * `FAILED_PRECONDITION: Firestore does not support descending key scans`
 * (measured on the emulator). `dailyLogToMap` writes `date` on every document,
 * and Firestore's automatic single-field index covers it in both directions, so
 * this still needs no composite index and no `firestore.indexes.json`.
 *
 * `.select()` with no field list asks for references only, so the date comes
 * from the document ID and no log content is transferred or held.
 */
async function edgeDate(db, uid, direction) {
  try {
    const snapshot = await db
      .collection(dailyLogsPath(uid))
      .orderBy('date', direction)
      .limit(1)
      .select()
      .get();
    const id = snapshot.docs[0]?.id ?? null;
    return id && DATE_ID.test(id) ? id : null;
  } catch {
    return null;
  }
}

/**
 * Per-device pull cursors (`SyncService._deviceDoc`).
 *
 * Two timestamps and a device id. No health data — but note the device id IS a
 * per-install identifier, so this is a roster of the account's installs and is
 * treated as account metadata, not as public information.
 */
async function devices(db, uid) {
  try {
    const snapshot = await db.collection(devicesPath(uid)).get();
    return snapshot.docs.map((doc) => {
      const data = doc.data() ?? {};
      return {
        deviceId: doc.id,
        logsCursor: toDate(data.logsCursor),
        deletionsCursor: toDate(data.deletionsCursor),
      };
    });
  } catch (error) {
    return { error: error?.message ?? String(error) };
  }
}

/**
 * Sync timestamps from `users/{uid}/settings/current`.
 *
 * Projected to two fields with `.select()`. The document also holds the user's
 * preferences (mode, theme, language, pregnancy start date, tracking
 * categories); the metadata view has no business with any of it, and a
 * projection means it never enters this process rather than merely not being
 * rendered. `pregnancyStartDate` in particular is health data.
 */
async function settingsMeta(db, uid) {
  try {
    const snapshot = await db
      .collection(settingsPath(uid))
      .select('updatedAt', 'syncedAt')
      .get();
    const doc = snapshot.docs.find((entry) => entry.id === 'current');
    if (!doc) return null;
    const data = doc.data() ?? {};
    return {
      updatedAt: toDate(data.updatedAt),
      syncedAt: toDate(data.syncedAt),
    };
  } catch {
    return null;
  }
}

/** The pending deletion request, if any. */
export async function deletionState(db, uid) {
  try {
    const snapshot = await db.doc(AccountDeletionService.requestPath(uid)).get();
    if (!snapshot.exists) return { pending: false };
    const data = snapshot.data() ?? {};
    return {
      pending: true,
      requestedAt: toDate(data.requestedAt),
      // Nullable on purpose, exactly as `DeletionRequest` in the Dart source
      // is: the ONLY thing that makes an account deletion-requested is the
      // marker's existence. A malformed deadline must still count as pending.
      purgeAfter: toDate(data.purgeAfter),
    };
  } catch (error) {
    // Same fail-closed posture as the Dart client's inverse case: if the state
    // cannot be read, say so loudly rather than implying "not pending".
    return { pending: 'unknown', error: error?.message ?? String(error) };
  }
}

/** Everything the metadata view shows for one account. */
export async function accountDetail({ auth, db, uid }) {
  let authRecord = null;
  let authError = null;
  try {
    authRecord = await auth.getUser(uid);
  } catch (error) {
    // An account can exist in Firestore with no Auth user: the purge job (not
    // yet written) is what removes the subtree, so a deleted Auth user leaves
    // orphaned health data behind. Saying "no Auth user, but N documents" is
    // exactly the signal the owner needs.
    authError = error?.message ?? String(error);
  }

  const [logs, deletions, deviceDocs, earliest, latest, settings, deletion, devicesList] =
    await Promise.all([
      countOrError(db.collection(dailyLogsPath(uid))),
      countOrError(db.collection(deletionsPath(uid))),
      countOrError(db.collection(devicesPath(uid))),
      edgeDate(db, uid, 'asc'),
      edgeDate(db, uid, 'desc'),
      settingsMeta(db, uid),
      deletionState(db, uid),
      devices(db, uid),
    ]);

  return {
    uid,
    auth: authRecord
      ? {
          email: authRecord.email ?? null,
          disabled: Boolean(authRecord.disabled),
          created: createdAt(authRecord),
          lastSeen: lastSeenAt(authRecord),
          emailVerified: Boolean(authRecord.emailVerified),
        }
      : null,
    authError,
    counts: {
      dailyLogs: logs,
      deletions,
      devices: deviceDocs,
    },
    earliestLogDate: earliest,
    latestLogDate: latest,
    settings,
    deletion,
    devices: devicesList,
    // Named so a reader can check it against the Dart constant of the same
    // name; if the app grows a subcollection and this list is not updated, the
    // panel under-reports what an account actually holds.
    knownSubcollections: AccountDeletionService.subcollections,
  };
}
