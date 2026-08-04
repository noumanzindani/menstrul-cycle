import 'dart:async';

import 'package:flutter/foundation.dart';

import '../db/database.dart';
import 'device_id.dart';
import 'firestore_ref.dart';
import 'sync_service.dart';

/// Owns the current user's [SyncService] and exposes a single entry point the
/// UI can call. Rebuilt whenever the signed-in uid changes.
class SyncTrigger extends ChangeNotifier {
  SyncTrigger(this._db);
  final AppDatabase _db;

  String? _uid;
  SyncService? _service;
  Timer? _debounce;

  /// Called when the signed-in user changes. A null uid tears sync down without
  /// touching local data — signing out must never wipe the device.
  Future<void> setUser(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    if (uid == null) {
      _service = null;
      return;
    }
    try {
      _service = SyncService(
        db: _db,
        firestore: lunaFirestore(),
        uid: uid,
        deviceId: await DeviceId.get(),
      );
    } catch (_) {
      // `lunaFirestore()` touches `Firebase.app()`, which throws whenever this
      // build has no initialized Firebase app (e.g. Firebase console setup —
      // task 1b — hasn't landed yet, or a test harness with no Firebase app).
      // Local-first: the rest of the app must keep working regardless of
      // whether sync infrastructure is available.
      _service = null;
      return;
    }
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
