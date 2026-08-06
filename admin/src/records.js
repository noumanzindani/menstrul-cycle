// Record browse — the operator reading a user's actual menstrual-health days.
//
// This is what the owner explicitly asked for and it is built. The constraints
// around it are not decoration:
//
// - **Every read is audited BEFORE the content is fetched, and a failed audit
//   write fails the read.** See `audit.js`. The routes call `auditedRead`; this
//   module exposes only the fetchers, so no route can "just query directly"
//   without it being visible in a diff.
// - **Per-uid only. No cross-user search on any health field.** There is no
//   function here that takes a symptom, a flow value, a mood or a note
//   fragment. "Find everyone who logged X" is not a support tool; it is a
//   cohort-building tool, and for a menstrual tracker the cohorts it builds
//   (pregnant, trying to conceive, sexually active on a date) are the exact
//   categories this app must never make queryable. The absence of that function
//   is a design decision, not an omission.
// - **Read-only.** The handle reaching this module is wrapped by
//   `readOnly()`; a write throws before it reaches the network. An operator
//   write to somebody's menstrual log is unfalsifiable from the user's side.
//
// Document shape is transcribed from `dailyLogToMap` in
// `lib/services/sync_mapper.dart` — `date`, `flow` (enum INDEX), `symptoms` (a
// map), `mood`, `notes`, `bbt`, `opk`, `createdAt`/`updatedAt` (epoch millis),
// `deviceId` — plus the server-stamped `syncedAt` that `SyncService._pushLogs`
// layers on top.

import {
  DATE_ID,
  NUMERIC_METRICS,
  TAG_PREFIXES,
  dailyLogsPath,
  deletionsPath,
  flowLabel,
  isBleeding,
} from './paths.js';

const millis = (value) =>
  typeof value === 'number' && Number.isFinite(value) ? new Date(value) : null;

const stamp = (value) =>
  value && typeof value.toDate === 'function' ? value.toDate() : millis(value);

/**
 * Splits the one `symptoms` JSON blob back into the groups the app encodes into
 * it.
 *
 * `encodeDayTags` is a full REPLACE that rebuilds the whole blob from form
 * state, and MANY groups ride it under reserved key prefixes (`sex_`, `med_`,
 * `cm_`, `vag_`, `shx_`, `habit_`, `urn_`, `dig_`, `skin_`). Numeric metrics
 * ride the same object as real JSON numbers and carry no prefix.
 *
 * **`0` means "unset" for every numeric metric, weight included** — a 0 is
 * dropped rather than rendered, because showing "Pain: 0" as a reading invents
 * a measurement the user never made.
 */
export function decodeDayTags(symptoms) {
  const blob = symptoms && typeof symptoms === 'object' ? symptoms : {};
  const groups = new Map();
  const metrics = [];
  const plainSymptoms = [];
  const unrecognised = [];

  for (const [key, value] of Object.entries(blob)) {
    if (Object.prototype.hasOwnProperty.call(NUMERIC_METRICS, key)) {
      if (typeof value === 'number' && value !== 0) {
        metrics.push({ key, label: NUMERIC_METRICS[key], value });
      }
      continue;
    }

    const prefix = Object.keys(TAG_PREFIXES).find((candidate) =>
      key.startsWith(candidate),
    );
    if (prefix) {
      if (value === true) {
        if (!groups.has(prefix)) groups.set(prefix, []);
        groups.get(prefix).push(key.slice(prefix.length));
      }
      continue;
    }

    if (value === true) plainSymptoms.push(key);
    else unrecognised.push({ key, value });
  }

  return {
    symptoms: plainSymptoms.sort(),
    // Rendered under the app's own group names so the operator sees the same
    // taxonomy the user filled in, not a wall of raw keys.
    groups: [...groups.entries()]
      .map(([prefix, values]) => ({
        prefix,
        label: TAG_PREFIXES[prefix],
        values: values.sort(),
      }))
      .sort((a, b) => a.label.localeCompare(b.label)),
    metrics: metrics.sort((a, b) => a.label.localeCompare(b.label)),
    // Anything a newer app version writes that this panel does not know about.
    // Shown verbatim rather than dropped: silently hiding a field would make
    // the panel quietly wrong the first time the app adds a group.
    unrecognised,
  };
}

/** One `dailyLogs` document, fully decoded. */
export function decodeDay(id, data) {
  const raw = data ?? {};
  const flow = typeof raw.flow === 'number' ? raw.flow : null;
  return {
    date: raw.date ?? id,
    flow,
    flowLabel: flowLabel(flow),
    bleeding: isBleeding(flow),
    mood: raw.mood ?? null,
    notes: raw.notes ?? null,
    bbt: typeof raw.bbt === 'number' ? raw.bbt : null,
    opk: raw.opk ?? null,
    createdAt: millis(raw.createdAt),
    updatedAt: millis(raw.updatedAt),
    syncedAt: stamp(raw.syncedAt),
    deviceId: raw.deviceId ?? null,
    tags: decodeDayTags(raw.symptoms),
  };
}

/**
 * One page of a single account's days, newest first.
 *
 * ## Why this orders on the `date` FIELD and not on the document id
 *
 * The document id already IS the ISO date (`syncDocId`), so ordering on
 * `__name__` would be the obvious choice — and it does not work.
 * **Firestore has no descending key index:** any query that scans `__name__`
 * in reverse (`orderBy(documentId(), 'desc')`, and also `limitToLast()` with an
 * ascending key order, which the client implements as a reversed scan) fails
 * with `FAILED_PRECONDITION: Firestore does not support descending key scans`.
 * Measured against the emulator, not assumed. Newest-first therefore has to
 * order on a real field.
 *
 * `dailyLogToMap` writes `date` on every document, and Firestore's AUTOMATIC
 * single-field indexes cover a field ascending and descending, so this needs no
 * composite index and no `firestore.indexes.json`.
 *
 * The caveat, stated because it is the same trap `sync_service.dart` documents
 * for `syncedAt`: a range/order filter silently EXCLUDES documents that lack
 * the ordered field. A `dailyLogs` document written without `date` — a partial
 * write, a hand-edited console value — would be invisible here. That is why the
 * caller also reports the collection's `count()`: a page total that does not
 * reconcile with the document count is the signal.
 *
 * The cursor is a plain date string rather than a snapshot so the page link is
 * stateless and nothing in the query path holds a live reference.
 */
export async function browseDays(db, uid, { limit = 40, before = null } = {}) {
  let query = db.collection(dailyLogsPath(uid)).orderBy('date', 'desc');
  if (before && DATE_ID.test(before)) {
    query = query.where('date', '<', before);
  }
  const snapshot = await query.limit(limit).get();
  const days = snapshot.docs.map((doc) => decodeDay(doc.id, doc.data()));
  return {
    days,
    nextBefore: days.length === limit ? days[days.length - 1].date : null,
  };
}

/**
 * How many day documents this account actually has, as a `count()`.
 *
 * Shown next to the page so a shortfall is visible: [browseDays] orders on the
 * `date` field, and a Firestore order filter silently drops documents that lack
 * it. Reconciling the page against the true count is what turns that silent
 * exclusion into something an operator can see.
 */
export async function dayCount(db, uid) {
  try {
    const snapshot = await db.collection(dailyLogsPath(uid)).count().get();
    return snapshot.data().count;
  } catch {
    return null;
  }
}

/** A single day. */
export async function getDay(db, uid, date) {
  if (!DATE_ID.test(String(date ?? ''))) return null;
  const snapshot = await db.collection(dailyLogsPath(uid)).doc(date).get();
  if (!snapshot.exists) return null;
  return decodeDay(snapshot.id, snapshot.data());
}

/**
 * Cross-device deletion markers — dates only, no content.
 *
 * Ordered on the `date` field for the same reason as [browseDays]:
 * `SyncService._pushTombstones` writes `date` on every marker, and there is no
 * descending key index to order on the id instead.
 */
export async function recentDeletions(db, uid, { limit = 40 } = {}) {
  const snapshot = await db
    .collection(deletionsPath(uid))
    .orderBy('date', 'desc')
    .limit(limit)
    .get();
  return snapshot.docs.map((doc) => ({
    date: doc.id,
    deletedAt: millis(doc.data()?.deletedAt),
    syncedAt: stamp(doc.data()?.syncedAt),
  }));
}

/**
 * "Current status", derived from the page of days already in hand.
 *
 * Deliberately NOT a re-implementation of `CycleCalculator` /
 * `PredictionService`. Those live in Dart, are the app's source of truth, and a
 * second implementation here would drift and start telling the operator a
 * different cycle day than the user's own screen shows. What this reports is
 * only what is directly observable in the documents: the most recent logged
 * day, the most recent BLEEDING day (`none.isBleeding == false`, per the app's
 * "period ended" primitive) and the gap in days.
 *
 * No prediction, no fertile window, no phase. Those are estimates the app
 * frames carefully for its user, and an operator panel restating them as fact
 * would be false precision at one remove.
 */
export function currentStatus(days, { now = Date.now() } = {}) {
  if (!days || days.length === 0) return null;
  const sorted = [...days].sort((a, b) => (a.date < b.date ? 1 : -1));
  const lastLogged = sorted[0] ?? null;
  const lastBleeding = sorted.find((day) => day.bleeding) ?? null;
  const dayMs = 24 * 60 * 60 * 1000;
  const since = (date) => {
    if (!date) return null;
    const parsed = Date.parse(`${date}T00:00:00Z`);
    if (Number.isNaN(parsed)) return null;
    return Math.floor((now - parsed) / dayMs);
  };
  return {
    lastLoggedDate: lastLogged?.date ?? null,
    lastLoggedDaysAgo: since(lastLogged?.date),
    lastBleedingDate: lastBleeding?.date ?? null,
    lastBleedingDaysAgo: since(lastBleeding?.date),
    // Stated so the operator cannot mistake a page boundary for a data gap.
    windowCoversDays: sorted.length,
    oldestDateInWindow: sorted[sorted.length - 1]?.date ?? null,
  };
}
