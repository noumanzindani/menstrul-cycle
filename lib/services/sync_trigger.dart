import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/daily_log_repository.dart';
import '../data/settings_repository.dart';
import '../db/database.dart';
import 'device_id.dart';
import 'firestore_ref.dart';
import 'sync_service.dart';

/// Owns the current user's [SyncService] and exposes a single entry point the
/// UI can call. Rebuilt whenever the signed-in uid changes.
class SyncTrigger extends ChangeNotifier {
  SyncTrigger(
    this._db, {
    FirebaseFirestore Function()? firestore,
    Future<String> Function()? deviceId,
  })  : _firestore = firestore ?? lunaFirestore,
        _deviceId = deviceId ?? DeviceId.get;

  final AppDatabase _db;

  /// Overridable so tests can inject a fake Firestore instead of touching the
  /// real `Firebase.app()` singleton (which throws with no Firebase app
  /// configured — see `firestore_ref.dart`).
  final FirebaseFirestore Function() _firestore;

  /// Overridable so tests can avoid `flutter_secure_storage`'s platform
  /// channel, which has no handler registered outside a full app.
  final Future<String> Function() _deviceId;

  String? _uid;
  SyncService? _service;
  Timer? _debounce;

  /// True while this device holds local logs that predate the signed-in
  /// account and have not yet been claimed (see `claim_local_data_sheet.dart`).
  ///
  /// Set by [setUser] whenever a fresh device/account pairing has existing
  /// local rows: [syncNow] refuses to run while this is set, so nothing about
  /// [setUser]'s own auto-sync, the app-resume hook in `AppGate`, or a
  /// debounced write from [scheduleSync] can push that history before the
  /// user has actually been asked. Only [resolveClaim] can clear it.
  bool _pendingClaim = false;

  /// Called when the signed-in user changes. A null uid tears sync down without
  /// touching local data — signing out must never wipe the device.
  Future<void> setUser(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    _pendingClaim = false;
    if (uid == null) {
      _service = null;
      return;
    }
    try {
      _service = SyncService(
        db: _db,
        firestore: _firestore(),
        uid: uid,
        deviceId: await _deviceId(),
      );
    } catch (_) {
      // `_firestore()` (by default `lunaFirestore()`) touches `Firebase.app()`,
      // which throws whenever this build has no initialized Firebase app (e.g.
      // Firebase console setup — task 1b — hasn't landed yet, or a test
      // harness with no Firebase app). Local-first: the rest of the app must
      // keep working regardless of whether sync infrastructure is available.
      _service = null;
      return;
    }

    // A fresh pairing of this device with this account (never synced from
    // here before) that ALSO already has local logs is exactly the upgrade
    // scenario `claim_local_data_sheet.dart` exists for: `SyncService`'s first
    // run pushes EVERY local row unconditionally (`since == null` skips the
    // `updatedAt` gate in `_pushLogs`), so auto-syncing here — before the user
    // has been asked anything — would silently upload months of health data
    // the instant they sign in. Defer to the claim prompt instead; see
    // [resolveClaim].
    final settings = await SettingsRepository(_db).get();
    if (settings.lastSyncedAt == null) {
      final hasLocalLogs =
          (await DailyLogRepository(_db).getAll()).isNotEmpty;
      if (hasLocalLogs) {
        _pendingClaim = true;
        return;
      }
    }
    await syncNow();
  }

  /// Resolves the claim prompt's decision.
  ///
  /// `upload: true` clears the pending gate and runs the deferred sync — a
  /// genuine, consented push of the local history plus the normal pull.
  ///
  /// `upload: false` deliberately leaves the gate SET for the rest of this
  /// app session: [syncNow] keeps refusing to run, so neither the app-resume
  /// hook nor a later debounced write can push the declined history. This
  /// flag lives only in memory, so the next app launch re-evaluates from
  /// scratch and asks again rather than silently opting the account in.
  Future<void> resolveClaim({required bool upload}) async {
    if (!upload) return;
    _pendingClaim = false;
    await syncNow();
  }

  /// Coalesces bursts of local writes into one sync.
  ///
  /// The day editor saves the whole row on every field change, so syncing per
  /// write would fire a dozen times while a user fills in one day.
  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    if (_pendingClaim) return; // still waiting on the claim decision
    // Network failures must never surface as a crash in the UI; the next
    // trigger retries the same window because lastSyncedAt did not advance.
    try {
      await _service?.syncNow();
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
