// The user list.
//
// Sourced from Firebase Auth, because `users/{uid}` documents do not exist —
// see the long note at the top of `stats.js`. `listUsers` gives uid, email,
// `metadata.creationTime`, `metadata.lastSignInTime` and
// `metadata.lastRefreshTime` for free, in Auth-native pagination, without
// reading a single Firestore document and without touching a single health
// record.
//
// This view carries NO health data at all. Not a count, not a date range,
// nothing. It exists so the operator can find an account; everything about that
// account lives one click away in the metadata view, and the health content two
// clicks away behind an audited, reason-gated read.

import { AccountDeletionService } from './paths.js';
import { createdAt, lastSeenAt } from './stats.js';

/**
 * Marks which of [uids] are inside the 30-day account-deletion grace window.
 *
 * These users wiped their device, were told their account is scheduled for
 * deletion, and can still cancel. They are NOT ordinary users, and a panel that
 * showed them identically would invite the operator to treat a departing user's
 * records as routine. One small document read per row on the page; the marker
 * holds a uid and two timestamps and no health data.
 *
 * A read failure marks the row `unknown`, never `false`. Failing open here
 * would silently drop the flag exactly when Firestore is unhealthy.
 */
export async function pendingDeletionFlags(db, uids) {
  const entries = await Promise.all(
    uids.map(async (uid) => {
      try {
        const snapshot = await db.doc(AccountDeletionService.requestPath(uid)).get();
        return [uid, snapshot.exists ? 'pending' : 'no'];
      } catch {
        return [uid, 'unknown'];
      }
    }),
  );
  return new Map(entries);
}

const toRow = (record, pending) => ({
  uid: record.uid,
  email: record.email ?? null,
  disabled: Boolean(record.disabled),
  created: createdAt(record),
  lastSeen: lastSeenAt(record),
  pendingDeletion: pending ?? 'unknown',
});

/** One page of the roster, in Auth's own pagination. */
export async function listRoster({ auth, db, pageToken = undefined, pageSize = 25 }) {
  const page = await auth.listUsers(Math.min(Math.max(pageSize, 1), 1000), pageToken);
  const flags = await pendingDeletionFlags(
    db,
    page.users.map((record) => record.uid),
  );
  return {
    rows: page.users.map((record) => toRow(record, flags.get(record.uid))),
    nextPageToken: page.pageToken ?? null,
  };
}

/**
 * Finds one account by email or uid.
 *
 * Exact lookups only, on identity fields only. There is deliberately no
 * substring search and no search over anything a user logged — see the header
 * of `records.js`.
 */
export async function findAccount({ auth, db, query }) {
  const term = String(query ?? '').trim();
  if (!term) return { rows: [], nextPageToken: null };

  const lookups = term.includes('@')
    ? [() => auth.getUserByEmail(term)]
    : [() => auth.getUser(term), () => auth.getUserByEmail(term)];

  for (const lookup of lookups) {
    try {
      const record = await lookup();
      const flags = await pendingDeletionFlags(db, [record.uid]);
      return { rows: [toRow(record, flags.get(record.uid))], nextPageToken: null };
    } catch {
      // `auth/user-not-found` for this shape of term — try the next shape.
    }
  }
  return { rows: [], nextPageToken: null };
}
