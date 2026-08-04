import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/daily_log_repository.dart';
import '../data/settings_repository.dart';
import '../db/database.dart';
import 'claim_preference.dart';
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
    Future<String?> Function()? readDeclinedUid,
    Future<void> Function(String uid)? writeDeclinedUid,
    Future<void> Function()? clearDeclinedUid,
  })  : _firestore = firestore ?? lunaFirestore,
        _deviceId = deviceId ?? DeviceId.get,
        _readDeclinedUid = readDeclinedUid ?? ClaimPreference.declinedUid,
        _writeDeclinedUid = writeDeclinedUid ?? ClaimPreference.setDeclined,
        _clearDeclinedUid = clearDeclinedUid ?? ClaimPreference.clear;

  final AppDatabase _db;

  /// Overridable so tests can inject a fake Firestore instead of touching the
  /// real `Firebase.app()` singleton (which throws with no Firebase app
  /// configured — see `firestore_ref.dart`).
  final FirebaseFirestore Function() _firestore;

  /// Overridable so tests can avoid `flutter_secure_storage`'s platform
  /// channel, which has no handler registered outside a full app.
  final Future<String> Function() _deviceId;

  /// These three are overridable for the same reason as [_deviceId]:
  /// `ClaimPreference`'s default is backed by `flutter_secure_storage`, whose
  /// platform channel has no handler in a test harness.
  final Future<String?> Function() _readDeclinedUid;
  final Future<void> Function(String uid) _writeDeclinedUid;
  final Future<void> Function() _clearDeclinedUid;

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
  ///
  /// This stays true across an entire declined session even though the claim
  /// prompt itself is shown at most once (see [declinedUidOnRecord]) --
  /// there is deliberately no separate "the user said no" flag distinct from
  /// "still pending": both mean the same thing to [syncNow], which is "do not
  /// push this device's history".
  bool _pendingClaim = false;

  /// State for a future Settings control (a later task) to reflect "sync is
  /// currently held back pending/declined for this account" and offer to
  /// reverse it via `resolveClaim(upload: true)`.
  ///
  /// Deliberately a plain getter, not backed by `notifyListeners()`: this
  /// class's own [setUser] runs synchronously up to its first `await` when
  /// called from `main.dart`'s `Consumer2` DURING that widget's build, and
  /// `notifyListeners()` on that same synchronous path throws
  /// ("setState() ... called during build") -- confirmed by running the full
  /// suite with a trial `notifyListeners()` added to every state transition
  /// here, which broke `test/widget_test.dart` with exactly that assertion.
  /// Whatever reactivity a Settings control needs is that task's call to make
  /// (e.g. its own polling, or a wrapper that defers notification to a
  /// microtask) — this getter only needs to be readable on demand.
  bool get isPendingClaim => _pendingClaim;

  /// The uid on record as having chosen "keep on this device only", or null.
  ///
  /// Exposed so `AppGate` can decide independently of [setUser]'s own async
  /// timing whether to re-show the claim prompt: `setUser`'s continuation and
  /// the prompt's post-frame callback are scheduled separately, so a caller
  /// that instead read a flag [setUser] computes internally would race it.
  /// This performs its own fresh read via the same injected function, with no
  /// dependency on [setUser] having run (or finished) at all.
  Future<String?> declinedUidOnRecord() => _readDeclinedUid();

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
    //
    // Deliberately does NOT consult `declinedUidOnRecord()` here: whether this
    // uid already declined only changes whether `AppGate` re-shows the
    // prompt, never whether sync itself should be held back. Keeping that
    // single "held back" condition here means an already-declined account
    // stays correctly blocked (this just never gets released by a prompt
    // answer, only by `resolveClaim(upload: true)`) without this class having
    // to track two separate reasons for the same outcome.
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
  /// `upload: true` clears the pending gate, clears any earlier decline on
  /// record for this uid (an opt-in supersedes it), and runs the deferred
  /// sync — a genuine, consented push of the local history plus the normal
  /// pull.
  ///
  /// `upload: false` persists the decline (scoped to this uid, via
  /// [ClaimPreference]) and deliberately leaves the pending gate SET for the
  /// rest of this app session: [syncNow] keeps refusing to run, so neither the
  /// app-resume hook nor a later debounced write can push the declined
  /// history. The persisted record is what makes the decline survive an app
  /// restart (`AppGate` checks [declinedUidOnRecord] before showing the
  /// prompt again), not this in-memory flag.
  Future<void> resolveClaim({required bool upload}) async {
    if (!upload) {
      if (_uid != null) await _writeDeclinedUid(_uid!);
      return;
    }
    _pendingClaim = false;
    if (_uid != null) await _clearDeclinedUid();
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
