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

  /// Runs one full push + pull cycle.
  ///
  /// Ordering invariant — **tombstones, then pull, then push** — for both logs
  /// and settings. `_pushLogs`/`_pushSettings` write with a blind `.set()`,
  /// with no comparison against the remote's CURRENT value. If push ran
  /// first, a stale local copy would overwrite a document another device
  /// wrote more recently — moments before pull ever gets a chance to compare
  /// timestamps — destroying that newer remote change. Pulling first lets
  /// last-write-wins resolve locally; the push that follows re-sends the
  /// already-merged row, which is a harmless idempotent write, not a
  /// clobber. Do not reorder this without re-reading the git history on this
  /// line — it has broken twice.
  ///
  /// `lastSyncedAt` advances ONLY on full success, so a partial failure simply
  /// re-attempts the same window next time. Re-pushing an already-pushed day is
  /// harmless because documents are keyed by date and writes are idempotent —
  /// the design tolerates duplicate work but never data loss.
  Future<void> syncNow() async {
    if (_running) return; // overlapping runs would fight over the same window
    _running = true;
    try {
      final since = (await _settings.get()).lastSyncedAt;
      await _pushTombstones();
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
        AppSettingsCompanion(lastSyncedAt: Value(DateTime.now())),
      );
    } finally {
      _running = false;
    }
  }

  /// Deletions first: pushing a local row for a day that was just deleted
  /// elsewhere would otherwise recreate it.
  Future<void> _pushTombstones() async {
    for (final t in await _logs.getTombstones()) {
      await _remoteLogs.doc(syncDocId(t.date)).delete();
      await _logs.clearTombstone(t.date);
    }
  }

  Future<void> _pushLogs(DateTime? since) async {
    final rows = await _db.select(_db.dailyLogs).get();
    for (final row in rows) {
      if (since != null && !row.updatedAt.isAfter(since)) continue;
      await _remoteLogs
          .doc(syncDocId(row.date))
          .set(dailyLogToMap(row, deviceId: deviceId));
    }
  }

  Future<void> _pullLogs(DateTime? since) async {
    final snapshot = await _remoteLogs.get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final remoteUpdated = updatedAtFromMap(data);
      final companion = dailyLogFromMap(data);
      final local = await _logs.getForDate(companion.date.value);

      final decision = decideMerge(
        local: local?.updatedAt,
        remote: remoteUpdated,
      );
      if (decision != MergeDecision.takeRemote) continue;

      // Not `insertOnConflictUpdate`: it resolves conflicts on the PRIMARY KEY
      // (`id`), but `DailyLogs`' real uniqueness constraint is `date`. A
      // companion built from a remote doc never carries the local `id`, so an
      // insert-on-conflict(id) attempt against an existing same-date row hits
      // the `date` UNIQUE constraint uncaught. Mirror
      // `DailyLogRepository.upsert()`'s own explicit-existence-check pattern
      // instead — but keep the remote's real `updatedAt` (rather than
      // stamping `DateTime.now()`, which is what that helper does), since the
      // merge algorithm depends on the pulled row's timestamp being the
      // remote's own.
      if (local == null) {
        await _db.into(_db.dailyLogs).insert(companion);
      } else {
        await (_db.update(_db.dailyLogs)..where((t) => t.id.equals(local.id)))
            .write(companion);
      }
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
    if (since != null && !changed.isAfter(since)) return;

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

    final pregnancyMillis = data['pregnancyStartDate'] as int?;
    final modeIndex = data['mode'] as int?;
    await _settings.updateSyncState(
      AppSettingsCompanion(
        // Guard the enum index: a future version could write one this build
        // doesn't know, and losing one field beats failing the whole sync.
        mode: (modeIndex != null &&
                modeIndex >= 0 &&
                modeIndex < TrackingMode.values.length)
            ? Value(TrackingMode.values[modeIndex])
            : const Value.absent(),
        defaultCycleLength: Value(data['defaultCycleLength'] as int),
        defaultPeriodLength: Value(data['defaultPeriodLength'] as int),
        themeMode: Value(data['themeMode'] as String),
        language: Value(data['language'] as String),
        genderNeutralLanguage: Value(data['genderNeutralLanguage'] as bool),
        pregnancyStartDate: Value(pregnancyMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(pregnancyMillis)),
        trackingCategories: Value(data['trackingCategories'] as String?),
        weightUnit: Value(data['weightUnit'] as String?),
        settingsUpdatedAt: Value(remoteUpdated!),
      ),
    );
  }
}
