import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';

import '../data/daily_log_repository.dart';
import '../data/settings_repository.dart';
import '../db/database.dart';
import '../models/enums.dart';
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
  /// `lastSyncedAt` advances ONLY on full success, so a partial failure simply
  /// re-attempts the same window next time. Re-pushing an already-pushed day is
  /// harmless because documents are keyed by date and writes are idempotent —
  /// the design tolerates duplicate work but never data loss.
  Future<void> syncNow() async {
    if (_running) return; // overlapping runs would fight over the same window
    _running = true;
    try {
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
      await _pushTombstones();
      await _pullDeletions(since);
      await _pruneOldDeletionMarkers();
      await _pullLogs(since);
      await _pushLogs(since);
      await _pullSettings(since);
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
    } finally {
      _running = false;
    }
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
        await _logs.clearTombstone(t.date);
        // Restore the day locally HERE, from the document already in hand,
        // rather than leaving it to `_pullLogs` later in this same run. The
        // pull is scoped by a `since` window: it only fetches documents whose
        // server-stamped `syncedAt` is newer than this device's last sync, so
        // a winning remote edit that was pushed BEFORE that cutoff (or that
        // carries no `syncedAt` at all, e.g. written by an older build) is
        // never fetched -- and the deleting device would then be the ONE
        // device permanently missing a day that every peer still has, with
        // no path back: its tombstone is now cleared, so it will never ask
        // again. We already know this document won the merge, so applying it
        // directly is both cheaper and unconditional.
        await _applyRemoteLog(remoteData!);
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
  /// reconnects much later stamps `deletedAt` in the past; a `since` cutoff
  /// compared against that field would never match it, silently and
  /// permanently hiding the deletion from every peer. `syncedAt` reflects
  /// when the write actually reached the server, so a late-arriving offline
  /// change is still visible to anyone whose `since` predates the RECONNECT,
  /// not the original (offline) edit.
  Future<void> _pullDeletions(DateTime? since) async {
    final snapshot = since == null
        ? await _remoteDeletions.get()
        : await _remoteDeletions.where('syncedAt', isGreaterThan: since).get();

    for (final doc in snapshot.docs) {
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
        // resurrected. Delete the remote marker so it stops resurfacing on
        // every future sync.
        await doc.reference.delete();
        // Then stamp `updatedAt` to `now()` so `_pushLogs`'s OWN since-based
        // gate (below, later in this same run) treats this row as freshly
        // changed. Without this, if this exact row was already pushed in an
        // EARLIER sync, its `updatedAt` already sits below THIS device's own
        // `since` -- `_pushLogs` would see "nothing changed since my last
        // push" and skip it, even though the remote copy was just destroyed
        // by the peer's tombstone and must be recreated. The deleting
        // device's own `lastSyncedAt` has already advanced past the moment
        // of its delete, so only a push stamped newer than that will ever
        // reach it again -- clock skew only widens this gap, it never closes
        // it on its own.
        await (_db.update(_db.dailyLogs)..where((t) => t.date.equals(date)))
            .write(DailyLogsCompanion(updatedAt: Value(DateTime.now())));
      }
    }
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
  /// later stamps `updatedAt` in the past; a `since` cutoff compared against
  /// that field would never match it once a peer's `since` has advanced past
  /// that (long-past) moment -- the peer would never see the day, and would
  /// never re-push its own copy either, since its own `updatedAt` sits below
  /// its own `since` too. Offline-then-reconnect is a core scenario for this
  /// app, not an edge case. `syncedAt` reflects when the write actually
  /// reached the server, so it is always fresh relative to when the OTHER
  /// device's `since` was captured, regardless of how old the edit itself is.
  Future<void> _pullLogs(DateTime? since) async {
    // Read only what changed since the last successful sync, not the whole
    // collection every run. A two-year user has ~700 days of history; this
    // project's stated thesis is $0 running cost, and Firestore bills per
    // document read. `decideMerge` below remains the correctness backstop
    // regardless -- this query is an optimisation, never a substitute for it
    // (a first sync, `since == null`, still reads everything, correctly).
    final snapshot = since == null
        ? await _remoteLogs.get()
        : await _remoteLogs.where('syncedAt', isGreaterThan: since).get();
    for (final doc in snapshot.docs) {
      await _applyRemoteLog(doc.data());
    }
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
  Future<void> _applyRemoteLog(Map<String, dynamic> data) async {
    try {
      final remoteUpdated = updatedAtFromMap(data);
      final companion = dailyLogFromMap(data);
      final local = await _logs.getForDate(companion.date.value);

      final decision = decideMerge(
        local: local?.updatedAt,
        remote: remoteUpdated,
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
    } catch (_) {
      return;
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

  Future<void> _pullSettings(DateTime? since) async {
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
