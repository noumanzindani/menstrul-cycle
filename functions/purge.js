'use strict';

/**
 * The account-deletion purge — the half of "delete my account" that no client
 * can do.
 *
 * ## What this is
 *
 * The app never erases cloud data. `AccountDeletionService.requestDeletion`
 * wipes the device and writes ONE marker document at top-level
 * `deletionRequests/{uid}` (`uid`, server-stamped `requestedAt`, client-computed
 * `purgeAfter` = requestedAt + 30 days). `SyncService.syncNow` then refuses to
 * run in either direction while that marker exists, and the user can cancel
 * throughout the grace window. Nothing else happens. This job is what finally
 * makes the promise true, and until it is deployed Google Play's in-app
 * account-deletion requirement is unmet.
 *
 * ## The executable specification
 *
 * `lib/services/account_deletion_service.dart` — read it before changing
 * anything here. `deleteFirestoreData` is kept, tested and public in the Flutter
 * app for exactly one reason: to be the specification this file implements.
 * Two orderings in it are load-bearing and are reproduced here deliberately:
 *
 *   1. **Subcollections first, `users/{uid}` last.** Firestore does not cascade,
 *      so deleting the parent alone orphans the health data — unreachable but
 *      still stored, which is both a Play User Data violation and a real privacy
 *      failure. Doing the children first means a crash leaves the parent
 *      present, so the account is still findable and the job is resumable.
 *   2. **The marker last of all.** The marker IS the work queue entry. Deleting
 *      it before the work is done removes the only record that the work exists,
 *      stranding whatever had not finished — permanently and silently.
 *
 * Firebase Auth deletion sits between the two: after the data, before the
 * marker. If it fails, the account is still signed-in-able and the job is not
 * done, so the queue entry must survive.
 *
 * ## Why this file re-derives the deadline
 *
 * `firestore.rules` bounds `purgeAfter` to 29-31 days from `request.time`
 * because it is computed on a device clock. **Those bounds do not protect this
 * path.** The Admin SDK bypasses security rules entirely, so a `purgeAfter` that
 * got past the rules — through a rules regression, a console edit, another
 * server-side writer, or a future app version — would be taken at face value and
 * would trigger an immediate, irreversible purge with no grace window and no
 * reachable cancel path. Every candidate is therefore re-checked against
 * `requestedAt + graceWindow`, where `requestedAt` is server-stamped
 * (`request.time`) and is the only trustworthy value on the document.
 *
 * A marker whose `requestedAt` is missing or malformed is **not** purged. An
 * unverifiable irreversible delete fails closed: the data stays, the marker
 * stays, and the skip is logged for a human.
 *
 * ## Dependencies
 *
 * None — not even `firebase-admin`. Everything is injected. That keeps the
 * decision logic testable against fault injection (see `firestore_failingOn` in
 * `firebase_test/purge_emulator.mjs`) and keeps this file loadable from a copy
 * in a temp directory, which is how `purge_mutation_check.mjs` proves the suite
 * discriminates. The production wiring lives in `index.js`.
 */

const { createHash } = require('node:crypto');

/**
 * How long a deletion request is held before this job may run.
 *
 * The ONE definition lives on the client, at
 * `AccountDeletionService.graceWindow` (`Duration(days: 30)`), because that is
 * the value the user is shown. This is a restatement of it — JS cannot import
 * Dart — and `purge.test.mjs` parses the Dart file and fails if the two ever
 * disagree. Do not "simplify" it to a literal at the call site.
 */
const GRACE_WINDOW_DAYS = 30;

/** The top-level work queue: `AccountDeletionService.requestsCollection`. */
const REQUESTS_COLLECTION = 'deletionRequests';

/**
 * Every subcollection under `users/{uid}`, mirroring
 * `AccountDeletionService.subcollections`.
 *
 * That list is public in Dart *specifically* so tests can enumerate it rather
 * than duplicating the literal, and its doc says adding a new subcollection
 * REQUIRES adding it there or deletion silently leaves data behind. The same
 * now applies here, in a second language: `purge.test.mjs` both asserts this
 * array equals the Dart one and seeds a probe document into every entry of the
 * DART list before sweeping, so a subcollection added there and forgotten here
 * fails the suite instead of surviving an erasure request.
 */
const SUBCOLLECTIONS = ['dailyLogs', 'settings', 'deletions', 'devices', 'media'];

/**
 * The Cloud Storage prefix holding one account's uploaded photos and videos.
 *
 * Mirrors `AccountDeletionService.storagePrefix`.
 *
 * Storage is a SECOND service, so `deleteFirestoreData` cannot reach it and the
 * `media` entry above only removes the index. The bytes are unencrypted, and an
 * object left behind after an erasure request is unreferenced, unreachable
 * through any UI, and belongs to somebody who explicitly asked for it to be
 * gone — strictly worse than leaving the metadata, because nothing remains to
 * find it by.
 *
 * Prefix-based, deliberately not driven off the metadata documents: an object
 * whose document was already deleted (by the user, or by a partial earlier run)
 * must still be swept, and the uid alone reconstructs where to look.
 */
const storagePrefix = (uid) => `users/${uid}/media/`;

/**
 * Documents deleted per batch inside one subcollection. Matches the page size
 * in `deleteFirestoreData`; a long-running user has thousands of days and a
 * single unbounded read can exhaust the instance.
 */
const PAGE_SIZE = 300;

/**
 * Markers handled per invocation.
 *
 * Bounded so one run is predictable in time and cost, and ordered by
 * `purgeAfter` so the oldest deadline is always served first and nothing
 * starves behind a growing queue. `where('purgeAfter', '<=', now)` +
 * `orderBy('purgeAfter')` needs only Firestore's automatic single-field index —
 * no composite index, so there is nothing extra to deploy.
 */
const DEFAULT_LIMIT = 200;

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const GRACE_WINDOW_MS = GRACE_WINDOW_DAYS * MS_PER_DAY;

/**
 * A stable, non-reversible label for an account, for logs.
 *
 * Cloud Logging is retained, exported and readable by anyone with project log
 * access, so a plaintext uid there re-publishes part of what this job exists to
 * erase — and a uid is enough to correlate an account across every other log
 * source. Twelve hex characters is plenty to follow one account through one
 * sweep, and not a uid.
 */
const accountLabel = (uid) =>
  createHash('sha256').update(String(uid)).digest('hex').slice(0, 12);

/**
 * Strips [uid] out of a message before it is logged.
 *
 * Firestore and Auth errors routinely quote the document path or the account
 * they failed on, which puts a plaintext uid inside an error string that would
 * otherwise be safe to log verbatim.
 */
function redactUid(message, uid) {
  const text = String(message ?? 'unknown error');
  if (!uid) return text;
  return text.split(String(uid)).join(`<account:${accountLabel(uid)}>`);
}

/** A Firestore `Timestamp` (or `Date`) as a `Date`, else null. */
function toDate(value) {
  if (value instanceof Date) return value;
  if (value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
  }
  return null;
}

/**
 * Deletes every subcollection under `users/{uid}`, then the root document.
 *
 * A direct transliteration of `AccountDeletionService.deleteFirestoreData`,
 * including the order and the paging. Safe to run twice: every step is a delete
 * of something that may already be absent.
 */
async function deleteFirestoreData(firestore, uid) {
  for (const name of SUBCOLLECTIONS) {
    for (;;) {
      const page = await firestore
        .collection(`users/${uid}/${name}`)
        .limit(PAGE_SIZE)
        .get();
      if (page.empty) break;
      const writes = firestore.batch();
      for (const document of page.docs) writes.delete(document.ref);
      await writes.commit();
    }
  }
  // Deleting a document that does not exist is a no-op in Firestore, which is
  // the normal case here: `SyncService` only ever writes subcollections, so
  // `users/{uid}` usually has no document of its own.
  await firestore.doc(`users/${uid}`).delete();
}

/**
 * Deletes every uploaded object belonging to `uid`.
 *
 * Injected like everything else here, so this file still has no dependencies
 * and the fault-injection tests can make the bucket fail on demand.
 *
 * A missing deleter is treated as a HARD ERROR rather than a skip. The
 * temptation is to make it optional so the job keeps working if Storage is not
 * configured — but the failure that produces is silent retention of intimate
 * media past an erasure request, which is precisely the outcome this whole
 * subsystem exists to prevent. Failing loudly leaves the marker in place and
 * the account in the queue.
 */
async function deleteStorageData(deleteStoragePrefix, uid) {
  if (typeof deleteStoragePrefix !== 'function') {
    throw new Error('purge: no storage deleter supplied; refusing to report an '
      + 'account as purged while its media may remain');
  }
  await deleteStoragePrefix(storagePrefix(uid));
}

/**
 * Deletes the Firebase Auth account, tolerating one that is already gone.
 *
 * "Already gone" is the expected state on any re-run after a crash between the
 * Auth deletion and the marker deletion, so it must not be an error — otherwise
 * a single interrupted run wedges that account in the queue forever.
 */
async function deleteAuthAccount(deleteAuthUser, uid) {
  try {
    await deleteAuthUser(uid);
  } catch (error) {
    if (error && error.code === 'auth/user-not-found') return;
    throw error;
  }
}

/**
 * Purges every deletion request whose grace window has genuinely elapsed.
 *
 * @param {object} options
 * @param {object} options.firestore      Admin Firestore for the NAMED database.
 * @param {(uid: string) => Promise<void>} options.deleteAuthUser
 * @param {(prefix: string) => Promise<void>} options.deleteStoragePrefix
 *        Deletes every object under a prefix. Required — see
 *        [deleteStorageData] for why a missing one is an error, not a skip.
 * @param {Date}   [options.now]          Injectable clock, for tests.
 * @param {number} [options.limit]        Markers per invocation.
 * @param {object} [options.logger]       `{info, warn, error}`.
 * @returns {Promise<{found: number, purged: number,
 *                    skipped: Array<{account: string, reason: string}>,
 *                    failed: Array<{account: string, reason: string}>}>}
 */
async function purgeExpiredRequests({
  firestore,
  deleteAuthUser,
  deleteStoragePrefix,
  now,
  limit = DEFAULT_LIMIT,
  logger = console,
}) {
  const at = now ?? new Date();

  const queue = await firestore
    .collection(REQUESTS_COLLECTION)
    .where('purgeAfter', '<=', at)
    .orderBy('purgeAfter')
    .limit(limit)
    .get();

  const summary = {
    found: queue.size,
    purged: 0,
    skipped: [],
    failed: [],
  };

  for (const marker of queue.docs) {
    // The document ID is the authority on whose account this is, never the
    // `uid` FIELD: the field is client-written, and `firestore.rules` is not
    // evaluated on this path at all.
    const uid = marker.id;
    const account = accountLabel(uid);

    try {
      // --- the server-side re-derivation (see the file header) -------------
      const requestedAt = toDate(marker.get('requestedAt'));
      if (requestedAt === null) {
        summary.skipped.push({ account, reason: 'unverifiable-requestedAt' });
        continue;
      }
      const dueAt = new Date(requestedAt.getTime() + GRACE_WINDOW_MS);
      if (dueAt.getTime() > at.getTime()) {
        summary.skipped.push({ account, reason: 'not-due' });
        continue;
      }

      // --- the irreversible part, in the one order that is resumable -------
      //
      // Storage FIRST, and that ordering is deliberate. Its input is the
      // prefix, derived from the uid alone, so it survives any partial prior
      // run — unlike the metadata, which a half-finished sweep may already have
      // removed. Running it after Firestore would mean a crash in between
      // leaves bytes with nothing pointing at them and no cheap way to find
      // them again. Marker still last, so any crash re-queues the account.
      await deleteStorageData(deleteStoragePrefix, uid);
      await deleteFirestoreData(firestore, uid);
      await deleteAuthAccount(deleteAuthUser, uid);
      await marker.ref.delete();

      summary.purged += 1;
    } catch (error) {
      // One account's failure must not abandon the rest of the queue, and the
      // marker is deliberately still in place, so the next run retries it.
      summary.failed.push({
        account,
        reason: redactUid(error && error.message, uid),
      });
    }
  }

  const counts = {
    found: summary.found,
    purged: summary.purged,
    skipped: summary.skipped.length,
    failed: summary.failed.length,
  };

  if (summary.failed.length > 0) {
    logger.error('account purge finished with failures', {
      ...counts,
      failures: summary.failed,
      skips: summary.skipped,
    });
  } else if (summary.skipped.length > 0) {
    logger.warn('account purge finished with skips', {
      ...counts,
      skips: summary.skipped,
    });
  } else {
    logger.info('account purge finished', counts);
  }

  return summary;
}

module.exports = {
  GRACE_WINDOW_DAYS,
  REQUESTS_COLLECTION,
  SUBCOLLECTIONS,
  PAGE_SIZE,
  DEFAULT_LIMIT,
  accountLabel,
  deleteFirestoreData,
  deleteStorageData,
  storagePrefix,
  purgeExpiredRequests,
};
