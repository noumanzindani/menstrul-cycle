import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';

import '../data/daily_log_repository.dart';
import '../data/settings_repository.dart';
import '../db/database.dart';
import '../models/enums.dart';
import 'account_deletion_service.dart';
import 'sync_mapper.dart';
import 'sync_merge.dart';

/// Mirrors the local drift database into `users/{uid}` in the `lunatrack`
/// Firestore database.
///
/// Drift remains the single source of truth: the UI never waits on this, and
/// the app is fully usable offline. Sync is a mirror bolted alongside the
/// existing read/write path, never in front of it.
class SyncService {
  SyncService({
    required AppDatabase db,
    required FirebaseFirestore firestore,
    required this.uid,
    required this.deviceId,
  })  : _db = db,
        _firestore = firestore,
        _logs = DailyLogRepository(db),
        _settings = SettingsRepository(db);

  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  final DailyLogRepository _logs;
  final SettingsRepository _settings;
  final String uid;
  final String deviceId;

  bool _running = false;

  CollectionReference<Map<String, dynamic>> get _remoteLogs =>
      _firestore.collection('users/$uid/dailyLogs');

  DocumentReference<Map<String, dynamic>> get _remoteSettings =>
      _firestore.doc('users/$uid/settings/current');

  /// Deletion markers, keyed by the same `syncDocId` scheme as `dailyLogs`.
  /// The pull side of a sync only ever iterates documents that EXIST -- a
  /// document's absence is never observed by another device. Deleting
  /// `dailyLogs/{date}` alone therefore never reaches another device: it
  /// would keep its own stale copy of that day forever, and would never
  /// re-push it back either (its `updatedAt` sits below its `since`, so
  /// `_pushLogs` skips it too). This collection makes the deletion itself an
  /// observable, positive fact another device's pull can act on.
  CollectionReference<Map<String, dynamic>> get _remoteDeletions =>
      _firestore.collection('users/$uid/deletions');

  /// This device's own pull cursors — see [_readPullCursors].
  ///
  /// Holds no health data, only two timestamps, and lives under the same
  /// `users/{uid}/…` root as everything else.
  ///
  /// **`deviceId` correctness invariant** (this class does not, and cannot,
  /// enforce it -- it is a constructor parameter; wiring it is a later
  /// task's job, so state it here for whoever writes that code):
  ///
  /// - MUST be a per-install random identifier, generated once and persisted
  ///   locally for the life of that install.
  /// - MUST NOT be a hardware or vendor id. Two installs that happen to share
  ///   one -- a device transfer, a cloned image, any id the platform reuses
  ///   across app installs -- would then share this one cursor doc. Pull
  ///   completeness depends on the doc's cursor reflecting only what THAT
  ///   install has actually observed (see [_readPullCursors]): if install A
  ///   advances the shared cursor to `t2` and install B queries
  ///   `syncedAt >= t2`, B never fetches anything stamped before `t2` -- on
  ///   ANY future run, because the cursor only advances and nothing re-pushes
  ///   a day whose `updatedAt` sits below its owner's own push gate. The skip
  ///   is silent and permanent. A reused hardware/vendor id is also simply
  ///   the wrong choice for a menstrual-health app on privacy grounds alone,
  ///   independent of this correctness failure.
  /// - MUST NOT be restored from backup -- specifically, exclude whatever
  ///   local field stores it from Android auto-backup. A backup-restored id
  ///   reintroduces the identical two-installs-one-cursor failure above
  ///   between the original device and its restore target.
  ///
  /// Violate any of these and the result is the same: permanent, silent loss
  /// of peer history on whichever device ends up holding the duplicate id.
  DocumentReference<Map<String, dynamic>> get _deviceDoc =>
      _firestore.doc('users/$uid/devices/$deviceId');

  /// Runs one full push + pull cycle.
  ///
  /// Ordering invariant — **tombstones, then pull deletions, then prune old
  /// markers, then pull logs, then push logs, then pull/push settings**.
  /// `_pushLogs`/`_pushSettings` write with a blind `.set()`, with no
  /// comparison against the remote's CURRENT value. If push ran first, a
  /// stale local copy would overwrite a document another device wrote more
  /// recently — moments before pull ever gets a chance to compare timestamps
  /// — destroying that newer remote change. Pulling first lets
  /// last-write-wins resolve locally; the push that follows re-sends the
  /// already-merged row, which is a harmless idempotent write, not a
  /// clobber. Deletion markers are pulled before logs for the same reason
  /// tombstones are pushed first: applying a deletion before the day it
  /// targets is pulled avoids briefly resurrecting it. Pruning runs AFTER
  /// pulling deletions, not before: pruning compares THIS device's own clock
  /// against markers' server-stamped `syncedAt`, and running it first would
  /// let a skewed local clock destroy a marker this device has not even
  /// pulled yet. Do not reorder any of this without re-reading the git
  /// history on this line — it has broken more than once.
  ///
  /// `lastSyncedAt` (the PUSH gate) and the pull cursors (see
  /// [_readPullCursors]) both advance ONLY on full success, so a partial
  /// failure simply re-attempts the same window next time. Re-pushing an already-pushed day is
  /// harmless because documents are keyed by date and writes are idempotent —
  /// the design tolerates duplicate work but never data loss.
  Future<void> syncNow() async {
    if (_running) return; // overlapping runs would fight over the same window
    _running = true;
    try {
      // An account with a deletion request on record is invisible to sync in
      // BOTH directions, for the whole grace window.
      //
      // Out: `AccountDeletionService.deleteFirestoreData` (the purge) sweeps
      // the subtree collection by collection with no atomicity, so anything
      // pushed after the request survives as orphaned health data under a uid
      // whose auth user is about to be deleted -- unreachable but still on the
      // server, the exact thing "delete my account" exists to prevent.
      //
      // In: the request erases the device immediately. Signing back in during
      // the window would otherwise pull the entire cloud history straight back
      // down onto a device the user just wiped.
      //
      // This is the check that does NOT depend on the requesting device's own
      // in-memory state: it holds on every other device, on this one after a
      // relaunch, and independently of `SyncTrigger.suspend()` -- which does
      // now genuinely await every outstanding run, but is per-process and
      // per-session and so can never be the durable guarantee. It
      // costs one small document read per sync run; the marker holds a uid and
      // two timestamps, no health data. `firestore.rules` will enforce the
      // same thing server-side -- see the task-11 report -- but a rule that is
      // deployed later cannot protect a build shipped now, and a denied write
      // would only surface here as a swallowed exception.
      final deletionRequested = await _firestore
          .doc(AccountDeletionService.requestPath(uid))
          .get();
      if (deletionRequested.exists) return;
      // Captured BEFORE any push/pull work, and committed as `lastSyncedAt`
      // below — NOT a fresh `DateTime.now()` taken after the run. `_pushLogs`
      // snapshots rows near the top of this run; any local write that lands
      // between that snapshot and a post-run `now()` would get
      // `updatedAt < lastSyncedAt`, so the NEXT run's `isBefore(since)` filter
      // would skip it forever — permanent, unrecoverable loss of that edit
      // (and if another device later writes the same day, the following pull
      // would destroy it outright). Stamping the start time instead means the
      // next run may re-push a day that was actually already pushed
      // (over-pushing slightly), which is merely redundant work. Over-pushing
      // is correct; under-pushing is data loss.
      final startedAt = DateTime.now();
      final since = (await _settings.get()).lastSyncedAt;
      // `since` is a LOCAL clock value and gates the PUSH side only. The pull
      // side is scoped by server-derived cursors instead -- see
      // [_readPullCursors].
      final cursors = await _readPullCursors(fullSweep: since == null);
      await _pushTombstones();
      final deletionsCursor = await _pullDeletions(cursors.deletions);
      await _pruneOldDeletionMarkers();
      final logsCursor = await _pullLogs(cursors.logs);
      await _pushLogs(since);
      await _pullSettings();
      // Re-read AFTER the pull: `_pullSettings` may just have overwritten the
      // local settings row with a newer remote one. Pushing a snapshot taken
      // before that pull would push stale pre-pull state back out, quietly
      // reverting the very row the pull just merged.
      await _pushSettings(await _settings.get(), since);
      // `updateSyncState`, NOT `update`: advancing the high-water mark is not a
      // user edit, and stamping `settingsUpdatedAt` here would make every sync
      // look like a settings change and push forever.
      await _settings.updateSyncState(
        AppSettingsCompanion(lastSyncedAt: Value(startedAt)),
      );
      // Committed LAST, and only on full success, for the same reason
      // `lastSyncedAt` is: a cursor that advanced past a document this run
      // failed to apply would never fetch it again.
      await _writePullCursors(
        logs: logsCursor,
        deletions: deletionsCursor,
        previous: cursors,
      );
    } finally {
      _running = false;
    }
  }

  /// Where the PULL side resumes from, per collection.
  ///
  /// These are deliberately NOT `lastSyncedAt`. `lastSyncedAt` is stamped from
  /// this device's own `DateTime.now()`, while `syncedAt` on every remote
  /// document is stamped by the SERVER. Comparing the two is comparing two
  /// different clocks: a device running δ ahead of the server would query
  /// `syncedAt > server_now + δ`, so every peer write landing in the next δ is
  /// never fetched -- and never will be, because the cutoff only advances. A
  /// device that syncs more often than δ pulls NOTHING, EVER, silently. Only a
  /// value the server itself produced is comparable with `syncedAt`.
  ///
  /// So each cursor is the greatest `syncedAt` this device has actually
  /// OBSERVED and applied from that collection (see [_pullLogs] /
  /// [_pullDeletions]), which is by construction ≤ the server time at which
  /// that query ran. Anything newer than the cursor is therefore either
  /// already applied or still waiting to be fetched -- never skipped.
  ///
  /// Cursors are per-collection because the two pull queries run at different
  /// moments: a single shared cursor advanced to the maximum seen across both
  /// could jump past a document written into the OTHER collection between the
  /// two queries, which is exactly the permanent-skip failure this whole
  /// mechanism exists to prevent.
  ///
  /// They live in Firestore rather than in a local column purely to avoid a
  /// drift schema migration (which needs the project owner's sign-off); the
  /// cost is one document read per sync. `lastSyncedAt == null` -- a fresh
  /// install, or a local "delete all my data" wipe -- forces a full sweep
  /// regardless of what the remote cursors say, so a device that has lost its
  /// local state re-reads everything instead of trusting a cursor that no
  /// longer describes it.
  Future<({Timestamp? logs, Timestamp? deletions})> _readPullCursors({
    required bool fullSweep,
  }) async {
    if (fullSweep) return (logs: null, deletions: null);
    final data = (await _deviceDoc.get()).data();
    if (data == null) return (logs: null, deletions: null);
    return (
      logs: _asOrNull<Timestamp>(data['logsCursor']),
      deletions: _asOrNull<Timestamp>(data['deletionsCursor']),
    );
  }

  Future<void> _writePullCursors({
    required Timestamp? logs,
    required Timestamp? deletions,
    required ({Timestamp? logs, Timestamp? deletions}) previous,
  }) async {
    final update = <String, dynamic>{};
    if (_advances(logs, previous.logs)) update['logsCursor'] = logs;
    if (_advances(deletions, previous.deletions)) {
      update['deletionsCursor'] = deletions;
    }
    if (update.isEmpty) return; // nothing new was observed -- skip the write
    await _deviceDoc.set(update, SetOptions(merge: true));
  }

  /// True when [next] is a real, different cursor value. Compared with
  /// [Timestamp.compareTo] rather than `==` so this does not depend on
  /// `Timestamp` implementing value equality.
  bool _advances(Timestamp? next, Timestamp? previous) =>
      next != null && (previous == null || next.compareTo(previous) != 0);

  /// The server-stamped `syncedAt` of [doc], backfilling it when absent.
  ///
  /// A Firestore range filter silently excludes documents that lack the
  /// ordered field, so a `dailyLogs` document or a deletion marker written
  /// before `syncedAt` existed (an older build, a console write, a partial
  /// write) would be invisible to every future cursor-scoped pull AND to the
  /// retention sweep, which also filters on `syncedAt` -- i.e. never merged
  /// and never pruned. Such a document can only ever be seen during a full
  /// sweep, so that is where it gets its stamp.
  ///
  /// Returns null in that case rather than the value just written: the
  /// backfilled stamp is "now", which says nothing about how much of the
  /// collection this run actually observed, and must not drag a cursor
  /// forward. The document is simply re-fetched once on the next run.
  Future<Timestamp?> _observedSyncedAt(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final existing = _asOrNull<Timestamp>(doc.data()['syncedAt']);
    if (existing != null) return existing;
    await doc.reference.set(
      {'syncedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    return null;
  }

  /// Deletions first: pushing a local row for a day that was just deleted
  /// elsewhere would otherwise recreate it.
  ///
  /// But a tombstone is a point-in-time intent ("delete the day as it stood
  /// when I deleted it"), not an absolute command — if another device edited
  /// this same day AFTER our deletion, that edit is the more recent
  /// whole-day state, and whole-day last-write-wins (the rule the rest of
  /// this file enforces everywhere else) says the edit wins, not the delete.
  /// Blindly deleting would let an offline device's stale tombstone destroy
  /// a genuinely newer remote edit once it reconnects.
  Future<void> _pushTombstones() async {
    for (final t in await _logs.getTombstones()) {
      final remoteDoc = await _remoteLogs.doc(syncDocId(t.date)).get();
      final remoteData = remoteDoc.data();
      final remoteUpdated =
          remoteData == null ? null : updatedAtFromMap(remoteData);

      // `!isBefore` (not `isAfter`): an EXACT tie must resolve the SAME way
      // as `_pullDeletions`' own tie-break, which gives an exact
      // `local.updatedAt == deletedAt` to the local row. Exact ties are
      // reachable in practice, not theoretical -- this file's own test suite
      // has hit same-millisecond timestamps. If the two paths disagreed, the
      // identical moment could be "kept" when observed from one device's
      // pull and "deleted" when observed from another's push, depending on
      // which side of the sync happened to run the comparison.
      if (remoteUpdated != null && !remoteUpdated.isBefore(t.deletedAt)) {
        // The remote edit is newer than (or tied with) our deletion: leave
        // the remote doc alone and clear the tombstone so we stop trying to
        // delete it. No deletion marker is written in this branch: the
        // deletion lost, so there is nothing to tell other devices to
        // delete.
        //
        // Restore the day locally HERE, from the document already in hand,
        // rather than leaving it to `_pullLogs` later in this same run. The
        // pull is scoped by a `since` window: it only fetches documents whose
        // server-stamped `syncedAt` is newer than this device's last sync, so
        // a winning remote edit that was pushed BEFORE that cutoff (or that
        // carries no `syncedAt` at all, e.g. written by an older build) is
        // never fetched -- and the deleting device would then be the ONE
        // device permanently missing a day that every peer still has, with
        // no path back: its tombstone would be cleared, so it would never ask
        // again. We already know this document won the merge, so applying it
        // directly is both cheaper and unconditional.
        //
        // The restore runs BEFORE `clearTombstone`, never after. The restore
        // writes to the encrypted drift database, which a background isolate
        // (`CheckInWriter`) can be holding past `busy_timeout` -- that write
        // CAN throw. Clearing the tombstone first and then failing would
        // leave this device with no local row, no tombstone and a remote
        // document it has stopped asking about: the day is gone here,
        // permanently, with no retry path. Restoring first means a failure
        // aborts the run with the tombstone intact, so the next run simply
        // tries again.
        await _applyRemoteLog(remoteData!);
        await _logs.clearTombstone(t.date);
        continue;
      }

      final docId = syncDocId(t.date);
      await _remoteLogs.doc(docId).delete();
      // Record the deletion itself so other devices' pulls can observe it --
      // see the doc comment on `_remoteDeletions`. `deletedAt` stays the
      // point-in-time intent used for the merge decision on the pull side;
      // `syncedAt` is the SERVER's own write-time stamp -- see the doc
      // comment on `_pullDeletions`'s query for why the two are different
      // fields with different jobs.
      await _remoteDeletions.doc(docId).set({
        'date': docId,
        'deletedAt': t.deletedAt.millisecondsSinceEpoch,
        'syncedAt': FieldValue.serverTimestamp(),
      });
      await _logs.clearTombstone(t.date);
    }
  }

  /// Deletion markers accumulate without bound otherwise. 180 days is a
  /// trade-off, not a correctness requirement: a device that stays offline
  /// for LONGER than this will not see a day another device deleted come
  /// back missing on it -- it simply keeps its own (by-then-stale) copy and
  /// re-pushes it, silently resurrecting the day remotely. That is judged an
  /// acceptable, rare edge case against the alternative of `deletions`
  /// growing forever for every active user.
  ///
  /// Pruned on the server-stamped `syncedAt`, not `deletedAt`: `deletedAt` is
  /// a FOREIGN device's own clock, and comparing this device's `now() - 180d`
  /// against it would let a skewed peer clock make a fresh marker look
  /// artificially old (or vice versa). `syncedAt` is authoritative regardless
  /// of whose device wrote it.
  static const _deletionMarkerRetention = Duration(days: 180);

  Future<void> _pruneOldDeletionMarkers() async {
    final cutoff = DateTime.now().subtract(_deletionMarkerRetention);
    final stale = await _remoteDeletions.where('syncedAt', isLessThan: cutoff).get();
    for (final doc in stale.docs) {
      await doc.reference.delete();
    }
  }

  /// Applies remote deletion markers written by another device's
  /// `_pushTombstones`. Runs BEFORE `_pullLogs` in [syncNow] so a day already
  /// known to be deleted never round-trips through the log pull first.
  ///
  /// Queried on `syncedAt` (the SERVER's write-time stamp), never on
  /// `deletedAt` (the deleting device's own point-in-time intent, which is
  /// still what decides WHO WINS below -- this is only about which documents
  /// get fetched). A device that logs or deletes something OFFLINE and only
  /// reconnects much later stamps `deletedAt` in the past; a cutoff compared
  /// against that field would never match it, silently and permanently hiding
  /// the deletion from every peer. `syncedAt` reflects when the write actually
  /// reached the server, so a late-arriving offline change is still visible to
  /// anyone whose cursor predates the RECONNECT, not the original (offline)
  /// edit.
  ///
  /// `isGreaterThanOrEqualTo`, not `isGreaterThan`: a strict cutoff drops a
  /// marker whose server stamp lands exactly ON the cursor, and because the
  /// cursor only ever advances it drops it PERMANENTLY -- the identical
  /// failure mode as the push-side tie. The cost of the inclusive bound is
  /// re-fetching the single boundary document each run and re-deciding it
  /// identically, which is idempotent.
  ///
  /// Returns the cursor this collection should resume from next run.
  Future<Timestamp?> _pullDeletions(Timestamp? cursor) async {
    final snapshot = cursor == null
        ? await _remoteDeletions.get()
        : await _remoteDeletions
            .where('syncedAt', isGreaterThanOrEqualTo: cursor)
            .get();

    var high = cursor;
    for (final doc in snapshot.docs) {
      final observed = await _observedSyncedAt(doc);
      if (observed != null && (high == null || observed.compareTo(high) > 0)) {
        high = observed;
      }

      final deletedAtMillis = _asOrNull<int>(doc.data()['deletedAt']);
      if (deletedAtMillis == null) continue; // malformed marker -- skip it
      final deletedAt = DateTime.fromMillisecondsSinceEpoch(deletedAtMillis);

      final date = _parseSyncDocId(doc.id);
      if (date == null) continue; // malformed doc id -- skip it

      final local = await _logs.getForDate(date);
      if (local == null) continue; // nothing to do

      if (local.updatedAt.isBefore(deletedAt)) {
        // The deletion wins. Delete the local row DIRECTLY against the drift
        // table -- deliberately NOT `DailyLogRepository.deleteForDate`, which
        // records a local tombstone by design. Routing through it here would
        // manufacture a fresh tombstone for every pulled deletion, which
        // `_pushTombstones` would then push right back out as a marker on
        // every device, forever: this direct delete is the loop guard.
        await (_db.delete(_db.dailyLogs)..where((t) => t.date.equals(date)))
            .go();
      } else {
        // The local edit is at least as new as (or exactly tied with -- see
        // `_pushTombstones`) the deletion, so IT wins and the day is
        // resurrected: republish it, then delete the remote marker so it
        // stops resurfacing on every future sync.
        //
        // Republish runs BEFORE the marker delete, never after -- the same
        // shape as `_pushTombstones`'s restore-before-clear, mirrored here.
        // `_restoreRemoteDay` does its own Firestore read/write, which CAN
        // throw (a dropped mobile connection mid-run; round 4 also made DB
        // errors propagate instead of being swallowed). If the marker were
        // deleted first and the republish then failed, the marker's absence
        // is itself the only reason this branch is ever re-entered -- so a
        // fault between the two leaves no marker AND no remote day, and
        // `_pushLogs`'s own since-gate (see the doc comment on
        // `_restoreRemoteDay`) will not re-send it either, because this row
        // was already pushed in an earlier run and its `updatedAt` sits below
        // this device's `since`. The day would then survive on this device
        // alone and stay deleted, permanently, on every other device, with
        // nothing left to retry. Republishing first means a failure aborts
        // the run with the marker still intact, so the next run simply tries
        // again; the republish itself is idempotent, so a harmless duplicate
        // write on retry is the worst case.
        await _restoreRemoteDay(local);
        await doc.reference.delete();
      }
    }
    return high;
  }

  /// Republishes a day whose local row beat a peer's deletion marker.
  ///
  /// The remote document was destroyed by that peer's `_pushTombstones`, and
  /// `_pushLogs`'s own since-based gate will not necessarily re-send it: if
  /// this row was already pushed in an EARLIER run its `updatedAt` sits below
  /// this device's `since`, so the ordinary push sees "nothing changed" and
  /// skips it. The day would then survive locally but stay deleted for every
  /// other device.
  ///
  /// It deliberately does NOT stamp `updatedAt = now()` to force that push.
  /// `updatedAt` is the merge-decision field for every device: inflating it
  /// makes this row look like the newest edit of the day when it is not.
  /// Concretely -- A deletes at t1, C edits the same day at t2 > t1, this
  /// device holds t3 with t1 < t3 < t2. Bumping to t4 = now > t2 makes
  /// `_pullLogs` (later in this same run) keep the STALE local content and
  /// `_pushLogs` re-push it over C's newer edit. Buying a push by falsifying
  /// the timestamp destroys real data.
  ///
  /// Instead the day is republished directly, and the choice of what to
  /// publish is routed through the SAME [decideMerge] every other path uses,
  /// so a peer document that is genuinely newer wins here exactly as it would
  /// anywhere else.
  Future<void> _restoreRemoteDay(DailyLog local) async {
    final docId = syncDocId(local.date);
    final remoteData = (await _remoteLogs.doc(docId).get()).data();
    final decision = decideMerge(
      local: local.updatedAt,
      remote: remoteData == null ? null : updatedAtFromMap(remoteData),
    );
    if (decision == MergeDecision.takeRemote) {
      // A peer recreated the day with a newer edit than ours. Apply it
      // directly rather than waiting for `_pullLogs`, whose cursor may
      // already sit past that document.
      await _applyRemoteLog(remoteData!);
    } else if (decision == MergeDecision.keepLocal) {
      // Either nothing is there (the common case: the peer's tombstone
      // deleted it) or what is there is older than our row.
      final map = dailyLogToMap(local, deviceId: deviceId);
      map['syncedAt'] = FieldValue.serverTimestamp();
      await _remoteLogs.doc(docId).set(map);
    }
    // `unchanged` -- an exact tie -- means the remote document already holds
    // this same version of the day. Nothing to publish, nothing to apply.
  }

  Future<void> _pushLogs(DateTime? since) async {
    final rows = await _db.select(_db.dailyLogs).get();
    for (final row in rows) {
      // `isBefore(since)` -- NOT `!isAfter(since)`. An exact tie must be
      // PUSHED, not skipped. Drift persists `DateTime` columns as whole unix
      // seconds (this database does not set `storeDateTimeValuesAsText`), so
      // both `since` (read back from `AppSettings.lastSyncedAt`) and
      // `row.updatedAt` come back truncated to the second: every edit made in
      // the same second the run started reads back EXACTLY EQUAL to `since`,
      // not merely close to it. Skipping those rows loses them PERMANENTLY --
      // `lastSyncedAt` only ever advances, so the row's `updatedAt` stays at
      // or below every future `since` and is never pushed again (and if a
      // peer later writes that day, the pull destroys the local edit
      // outright). The cost of the tie going the other way is re-pushing at
      // most one second's worth of already-pushed days per run, an idempotent
      // write keyed by date. Over-pushing is correct; under-pushing is data
      // loss.
      if (since != null && row.updatedAt.isBefore(since)) continue;
      // `updatedAt` (from `dailyLogToMap`) stays the merge-decision field,
      // untouched. `syncedAt` is layered on top as the SERVER's own
      // write-time stamp -- see the doc comment on `_pullLogs`'s query for
      // why pulls key off this field instead.
      final map = dailyLogToMap(row, deviceId: deviceId);
      map['syncedAt'] = FieldValue.serverTimestamp();
      await _remoteLogs.doc(syncDocId(row.date)).set(map);
    }
  }

  /// Queried on `syncedAt` (the SERVER's write-time stamp), never on
  /// `updatedAt` (the row's own last-edited time, which still decides who
  /// wins via `decideMerge` below -- this is only about which documents get
  /// fetched). A device that logs a day OFFLINE and only reconnects much
  /// later stamps `updatedAt` in the past; a cutoff compared against that
  /// field would never match it once a peer's cutoff has advanced past that
  /// (long-past) moment -- the peer would never see the day, and would never
  /// re-push its own copy either, since its own `updatedAt` sits below its own
  /// `since` too. Offline-then-reconnect is a core scenario for this app, not
  /// an edge case. `syncedAt` reflects when the write actually reached the
  /// server, so it is always fresh relative to when the OTHER device last
  /// pulled, regardless of how old the edit itself is.
  ///
  /// The cutoff is a server-derived cursor, never `lastSyncedAt` -- see
  /// [_readPullCursors] -- and is inclusive, for the same reason
  /// [_pullDeletions]'s is.
  ///
  /// Returns the cursor this collection should resume from next run.
  Future<Timestamp?> _pullLogs(Timestamp? cursor) async {
    // Read only what arrived since the last successful sync, not the whole
    // collection every run. A two-year user has ~700 days of history; this
    // project's stated thesis is $0 running cost, and Firestore bills per
    // document read. `decideMerge` below remains the correctness backstop
    // regardless -- this query is an optimisation, never a substitute for it
    // (a first sync, `cursor == null`, still reads everything, correctly).
    final snapshot = cursor == null
        ? await _remoteLogs.get()
        : await _remoteLogs
            .where('syncedAt', isGreaterThanOrEqualTo: cursor)
            .get();
    var high = cursor;
    for (final doc in snapshot.docs) {
      final observed = await _observedSyncedAt(doc);
      if (observed != null && (high == null || observed.compareTo(high) > 0)) {
        high = observed;
      }
      await _applyRemoteLog(doc.data());
    }
    return high;
  }

  /// Merges ONE remote day document into the local database, last-write-wins.
  ///
  /// Shared by [_pullLogs] and by [_pushTombstones]'s remote-edit-wins branch
  /// so both reach the identical outcome for identical inputs -- the two
  /// paths deciding differently is exactly the class of bug this file keeps
  /// having to fix.
  ///
  /// A malformed remote document -- a bad `date`/`updatedAt` shape from a
  /// future app version, a partial write, a hand-edited console value -- must
  /// not abort the whole run: `sync_mapper.dart`'s decoders
  /// (`dailyLogFromMap`'s date parsing in particular) throw rather than return
  /// null on a bad shape, and an uncaught exception would wedge every future
  /// sync exactly like the unguarded settings casts did before that fix. One
  /// bad document costs one day, not the whole sync. `sync_mapper.dart` itself
  /// is intentionally not modified; this wraps the call instead. Nothing about
  /// the document is logged -- its content is menstrual-health data.
  ///
  /// The guard covers the DECODE ONLY, never the database write, and the
  /// distinction is the difference between losing one malformed document and
  /// losing a good day forever. `CheckInWriter` opens a SECOND connection to
  /// the encrypted database from a background isolate, so a drift write here
  /// can fail on a lock held past `busy_timeout`. Swallowing that would let
  /// the run complete, advance `lastSyncedAt` and the pull cursors past a
  /// document that was never applied, and never fetch it again -- silent,
  /// permanent local data loss. Letting it propagate aborts the run with
  /// nothing committed, so the next run retries the same window: the
  /// self-healing outcome.
  Future<void> _applyRemoteLog(Map<String, dynamic> data) async {
    final ({DateTime? updatedAt, DailyLogsCompanion companion}) decoded;
    try {
      decoded = (
        updatedAt: updatedAtFromMap(data),
        companion: dailyLogFromMap(data),
      );
    } catch (_) {
      return; // malformed document -- costs this one day, not the whole run
    }

    final companion = decoded.companion;
    final local = await _logs.getForDate(companion.date.value);

    final decision = decideMerge(
      local: local?.updatedAt,
      remote: decoded.updatedAt,
    );
    if (decision != MergeDecision.takeRemote) return;

    // Not `insertOnConflictUpdate`: it resolves conflicts on the PRIMARY
    // KEY (`id`), but `DailyLogs`' real uniqueness constraint is `date`.
    // A companion built from a remote doc never carries the local `id`,
    // so an insert-on-conflict(id) attempt against an existing same-date
    // row hits the `date` UNIQUE constraint uncaught. Mirror
    // `DailyLogRepository.upsert()`'s own explicit-existence-check
    // pattern instead — but keep the remote's real `updatedAt` (rather
    // than stamping `DateTime.now()`, which is what that helper does),
    // since the merge algorithm depends on the pulled row's timestamp
    // being the remote's own.
    if (local == null) {
      await _db.into(_db.dailyLogs).insert(companion);
    } else {
      await (_db.update(_db.dailyLogs)..where((t) => t.id.equals(local.id)))
          .write(companion);
    }
  }

  /// Preference fields only.
  ///
  /// `premium` (a Play-account IAP entitlement), `appLockEnabled` (a per-device
  /// security choice), `onboardingComplete`, `lastSyncedAt` and `id` are
  /// deliberately device-local and never travel. Syncing `premium` in
  /// particular would let one purchase unlock ads on every device signed into
  /// the account, which is not what was bought.
  Future<void> _pushSettings(AppSetting row, DateTime? since) async {
    final changed = row.settingsUpdatedAt;
    if (changed == null) return; // never edited locally — nothing to push
    // `isBefore`, not `!isAfter`: an exact tie is pushed. Same reason as
    // `_pushLogs` — drift stores both timestamps at whole-second resolution,
    // so a preference changed in the same second the run started ties exactly
    // with `since` and would otherwise never be pushed again.
    if (since != null && changed.isBefore(since)) return;

    await _remoteSettings.set({
      'mode': row.mode.index,
      'defaultCycleLength': row.defaultCycleLength,
      'defaultPeriodLength': row.defaultPeriodLength,
      'themeMode': row.themeMode,
      'language': row.language,
      'genderNeutralLanguage': row.genderNeutralLanguage,
      'pregnancyStartDate': row.pregnancyStartDate?.millisecondsSinceEpoch,
      'trackingCategories': row.trackingCategories,
      'weightUnit': row.weightUnit,
      'updatedAt': changed.millisecondsSinceEpoch,
      // `syncedAt` is written here for consistency with `dailyLogs` and
      // `deletions` (every remote document carries it), even though the
      // settings pull is a single-document `get()`, not a collection query
      // -- there is no `since`-scoped query for it to make correct. See the
      // doc comment on `_pullLogs`'s query for why the two fields exist.
      'syncedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Takes no cutoff: this is a single-document `get()`, not a collection
  /// query, so there is nothing to scope. `decideMerge` decides the outcome.
  Future<void> _pullSettings() async {
    final doc = await _remoteSettings.get();
    final data = doc.data();
    if (data == null) return;

    final remoteUpdated = updatedAtFromMap(data);
    final local = (await _settings.get()).settingsUpdatedAt;
    if (decideMerge(local: local, remote: remoteUpdated) !=
        MergeDecision.takeRemote) {
      return;
    }
    // `decideMerge` only returns `takeRemote` when `remote` is non-null (see
    // its own branching), so this is never actually null here -- but a
    // second guard costs nothing and keeps this function correct even if
    // that invariant ever changes.
    if (remoteUpdated == null) return;

    final modeIndex = _asOrNull<int>(data['mode']);
    final pregnancyMillis = _asOrNull<int>(data['pregnancyStartDate']);
    final defaultCycleLength = _asOrNull<int>(data['defaultCycleLength']);
    final defaultPeriodLength = _asOrNull<int>(data['defaultPeriodLength']);
    final themeMode = _asOrNull<String>(data['themeMode']);
    final language = _asOrNull<String>(data['language']);
    final genderNeutralLanguage =
        _asOrNull<bool>(data['genderNeutralLanguage']);

    await _settings.updateSyncState(
      AppSettingsCompanion(
        // Every field below applies the SAME defensive posture: a missing or
        // wrongly-typed remote field leaves that column untouched
        // (`Value.absent()`) rather than throwing. A plain `data['x'] as T`
        // throws a `TypeError` on any malformed document -- a future app
        // version writing a field this build doesn't understand, a partial
        // write, a hand-edited console value -- which would abort
        // `syncNow()` on EVERY subsequent run: `lastSyncedAt` never
        // advances, and sync is permanently bricked. Losing one field beats
        // failing the whole sync.
        mode: (modeIndex != null &&
                modeIndex >= 0 &&
                modeIndex < TrackingMode.values.length)
            ? Value(TrackingMode.values[modeIndex])
            : const Value.absent(),
        defaultCycleLength: defaultCycleLength == null
            ? const Value.absent()
            : Value(defaultCycleLength),
        defaultPeriodLength: defaultPeriodLength == null
            ? const Value.absent()
            : Value(defaultPeriodLength),
        themeMode:
            themeMode == null ? const Value.absent() : Value(themeMode),
        language: language == null ? const Value.absent() : Value(language),
        genderNeutralLanguage: genderNeutralLanguage == null
            ? const Value.absent()
            : Value(genderNeutralLanguage),
        // These three are nullable columns where `null` is itself a
        // meaningful, legitimate value (no pregnancy, no category override,
        // unit never chosen) -- not a sync failure -- so a missing or
        // malformed field collapses to `Value(null)`, never `Value.absent()`.
        pregnancyStartDate: Value(pregnancyMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(pregnancyMillis)),
        trackingCategories: Value(_asOrNull<String>(data['trackingCategories'])),
        weightUnit: Value(_asOrNull<String>(data['weightUnit'])),
        settingsUpdatedAt: Value(remoteUpdated),
      ),
    );
  }

  /// Casts [value] to `T?`, returning `null` instead of throwing when it is
  /// missing or a different type. See the defensive-cast note in
  /// [_pullSettings].
  T? _asOrNull<T>(Object? value) => value is T ? value : null;

  /// Parses a `syncDocId`-formatted id (`YYYY-MM-DD`) back into a [DateTime],
  /// returning `null` instead of throwing on a malformed id.
  DateTime? _parseSyncDocId(String id) {
    final parts = id.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }
}
