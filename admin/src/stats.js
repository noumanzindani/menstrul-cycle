// Business metrics.
//
// ## Two rules this file exists to enforce
//
// 1. **The roster comes from Firebase Auth, not Firestore.** `users/{uid}`
//    DOCUMENTS DO NOT EXIST. `SyncService` only ever writes SUBcollections
//    (`users/{uid}/dailyLogs`, `/settings`, `/deletions`, `/devices`); the only
//    operation it performs on the parent document is `delete()`, in
//    `AccountDeletionService.deleteFirestoreData`. So
//    `db.collection('users').get()` returns ZERO documents, forever, no matter
//    how many accounts exist. `auth.listUsers()` is the only true roster — and
//    it costs no Firestore reads and touches no health record. Do NOT "fix" an
//    empty user list by making the app write profile documents: that would put
//    a new document per user in front of the sync path for the panel's
//    convenience.
//
// 2. **Statistics use `count()` aggregation, never document reads.** A sweep
//    that reads every document to count them costs, at 100k users with ~400
//    days each, roughly 40M reads — about $24 EVERY TIME the dashboard is
//    refreshed. The same numbers via `count()` bill roughly one read per 1000
//    documents counted: ~40k reads, about $0.024. Three orders of magnitude,
//    for identical output. Any future metric added here must be expressible as
//    an aggregation or it does not belong on this page.

import { AccountDeletionService } from './paths.js';

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * Reads a metadata timestamp off an Auth user record.
 *
 * `lastRefreshTime` is the truest liveness signal — it advances whenever the
 * SDK refreshes an ID token, which a running app does — and falls back to
 * `lastSignInTime` for accounts old enough to predate it.
 */
export function lastSeenAt(record) {
  const meta = record?.metadata ?? {};
  const raw = meta.lastRefreshTime || meta.lastSignInTime || null;
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function createdAt(record) {
  const raw = record?.metadata?.creationTime ?? null;
  if (!raw) return null;
  const parsed = new Date(raw);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * Pages through the whole Auth roster, accumulating counters only.
 *
 * Deliberately does not retain the user records: at 100k accounts that is a lot
 * of memory for numbers we already have, and holding a full roster in a request
 * handler invites someone to render it.
 */
export async function sweepAuthRoster(auth, { now = Date.now(), max = 50000 } = {}) {
  let pageToken;
  let total = 0;
  let truncated = false;
  const newWithin = { 1: 0, 7: 0, 28: 0 };
  const activeWithin = { 7: 0, 28: 0 };

  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const record of page.users) {
      total += 1;
      const created = createdAt(record);
      if (created) {
        const ageDays = (now - created.getTime()) / DAY_MS;
        if (ageDays <= 1) newWithin[1] += 1;
        if (ageDays <= 7) newWithin[7] += 1;
        if (ageDays <= 28) newWithin[28] += 1;
      }
      const seen = lastSeenAt(record);
      if (seen) {
        const idleDays = (now - seen.getTime()) / DAY_MS;
        if (idleDays <= 7) activeWithin[7] += 1;
        if (idleDays <= 28) activeWithin[28] += 1;
      }
    }
    pageToken = page.pageToken;
    if (total >= max && pageToken) {
      truncated = true;
      break;
    }
  } while (pageToken);

  return { total, truncated, newWithin, activeWithin };
}

/**
 * Runs one `count()` aggregation, degrading to a reported error rather than a
 * misleading zero.
 *
 * The failure that matters is `FAILED_PRECONDITION` — Firestore's "this query
 * needs an index". A collection-group aggregation can hit it, and an operator
 * who sees `0 logged days` when the true answer is 4 million has been actively
 * misinformed. So the number is either real or absent; it is never faked.
 */
export async function countOrError(query) {
  try {
    const snapshot = await query.count().get();
    return { count: snapshot.data().count };
  } catch (error) {
    return { error: error?.message ?? String(error) };
  }
}

/**
 * Every Firestore-side statistic, as aggregations.
 *
 * - `loggedDays` — every synced day across every account. One aggregation over
 *   the `dailyLogs` collection group. No document is read, so no log content is
 *   ever in this process's memory.
 * - `accountsWithSyncedSettings` — `users/{uid}/settings/current` is written at
 *   most once per account (the document id is the literal `current`), so this
 *   collection-group count IS an account count, not a document count. It is the
 *   cheapest honest proxy for "has this account ever completed a sync".
 * - `deviceCursorDocs` — `users/{uid}/devices/{deviceId}`. Devices, not
 *   accounts: an account with three phones contributes three. Labelled that way
 *   on the page.
 * - `deletionMarkers` — `users/{uid}/deletions/{date}` cross-device tombstones.
 * - `pendingDeletionRequests` — top-level `deletionRequests`, i.e. accounts
 *   inside the 30-day grace window who believe they have deleted their account.
 */
export async function firestoreStats(db) {
  const [
    loggedDays,
    accountsWithSyncedSettings,
    deviceCursorDocs,
    deletionMarkers,
    pendingDeletionRequests,
  ] = await Promise.all([
    countOrError(db.collectionGroup('dailyLogs')),
    countOrError(db.collectionGroup('settings')),
    countOrError(db.collectionGroup('devices')),
    countOrError(db.collectionGroup('deletions')),
    countOrError(db.collection(AccountDeletionService.requestsCollection)),
  ]);
  return {
    loggedDays,
    accountsWithSyncedSettings,
    deviceCursorDocs,
    deletionMarkers,
    pendingDeletionRequests,
  };
}

/** The whole dashboard, in one Auth sweep plus five aggregations. */
export async function collectDashboard({ auth, db, now = Date.now(), max }) {
  const [accounts, firestore] = await Promise.all([
    sweepAuthRoster(auth, { now, max }),
    firestoreStats(db),
  ]);

  const pending = firestore.pendingDeletionRequests.count ?? null;
  const synced = firestore.accountsWithSyncedSettings.count ?? null;

  return {
    generatedAt: new Date(now),
    accounts,
    firestore,
    // Derived, and deliberately clamped at zero: the two numbers come from two
    // different systems read at two different instants, so a race can make the
    // subtraction negative. A negative "accounts" figure is nonsense; a zero
    // with a documented meaning is not.
    accountsNotPendingDeletion:
      pending === null ? null : Math.max(0, accounts.total - pending),
    accountsLocalOnlyOrNeverSyncedSettings:
      synced === null ? null : Math.max(0, accounts.total - synced),
  };
}
