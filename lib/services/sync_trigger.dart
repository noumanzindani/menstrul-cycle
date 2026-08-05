import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/daily_log_repository.dart';
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
    Future<ClaimRecord?> Function()? readClaim,
    Future<void> Function(ClaimRecord record)? writeClaim,
  })  : _firestore = firestore ?? lunaFirestore,
        _deviceId = deviceId ?? DeviceId.get,
        _readClaim = readClaim ?? ClaimPreference.read,
        _writeClaim = writeClaim ?? ClaimPreference.write;

  final AppDatabase _db;

  /// Overridable so tests can inject a fake Firestore instead of touching the
  /// real `Firebase.app()` singleton (which throws with no Firebase app
  /// configured — see `firestore_ref.dart`).
  final FirebaseFirestore Function() _firestore;

  /// Overridable so tests can avoid `flutter_secure_storage`'s platform
  /// channel, which has no handler registered outside a full app.
  final Future<String> Function() _deviceId;

  /// These two are overridable for the same reason as [_deviceId]:
  /// `ClaimPreference`'s default is backed by `flutter_secure_storage`, whose
  /// platform channel has no handler in a test harness (on this host it hangs
  /// indefinitely rather than throwing). `LunaTrackApp` accepts a whole
  /// pre-built `SyncTrigger` so widget tests that pump the real app can inject
  /// through this seam too, instead of relying on "don't seed a log in that
  /// test" to keep the storage path unreached.
  final Future<ClaimRecord?> Function() _readClaim;
  final Future<void> Function(ClaimRecord record) _writeClaim;

  String? _uid;
  SyncService? _service;
  Timer? _debounce;

  /// The run [syncNow] currently has in flight, so [suspend] can wait for it
  /// to land instead of returning while a push is still on the wire.
  Future<void>? _inFlight;

  /// Set by [suspend]: hard-stops every path into [SyncService] until [resume]
  /// or a uid change. See [suspend] for why an account deletion needs this.
  bool _suspended = false;

  /// True while nothing may be pushed for the signed-in account: either the
  /// claim question (see `claim_local_data_sheet.dart`) is still outstanding,
  /// or it was answered "keep on this device only".
  ///
  /// [setUser] sets this OPTIMISTICALLY, before its first `await`, for any
  /// non-null uid, and only clears it once it has proved no claim is needed.
  /// That ordering is the whole gate: [syncNow] refuses to run while this is
  /// set, so nothing — [setUser]'s own auto-sync, `AppGate`'s app-resume hook,
  /// or a debounced write from [scheduleSync] — can push this device's history
  /// while the decision is still being evaluated. Setting it AFTER the
  /// evaluation's awaits (as an earlier version did) left a real window in
  /// which `_service` was live and the gate was open: the database opens
  /// through a `LazyDatabase` (documents dir + keystore read + sqlite open),
  /// so the first query after sign-in takes hundreds of milliseconds on a real
  /// device, and Android delivers `resumed` — which calls [syncNow] — shortly
  /// after startup. A first sync has `since == null`, which makes
  /// `SyncService._pushLogs` upload EVERY local row.
  bool _pendingClaim = false;

  /// State for a Settings control (`AccountSection`) to reflect "sync is
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
  bool get isPendingClaim => _pendingClaim;

  /// The claim decision on record for this device, whichever account made it.
  ///
  /// Exposed so `AppGate` can decide independently of [setUser]'s own async
  /// timing whether to show the claim prompt: `setUser`'s continuation and the
  /// prompt's post-frame callback are scheduled separately, so a caller that
  /// instead read a flag [setUser] computes internally would race it. This
  /// performs its own fresh read via the same injected function, with no
  /// dependency on [setUser] having run (or finished) at all.
  Future<ClaimRecord?> claimOnRecord() => _readClaim();

  /// The uid on record as having chosen "keep on this device only", or null.
  /// An account that chose to UPLOAD is not reported here (`AccountSection`
  /// uses this to offer turning sync back on).
  Future<String?> declinedUidOnRecord() async {
    final record = await _readClaim();
    return record != null && record.declined ? record.uid : null;
  }

  /// Whether this device is actually uploading [uid]'s logs right now — the
  /// honest signal for a "Cloud sync is on/off" surface.
  ///
  /// A "declined?" check alone is NOT that signal: an account with no decision
  /// on record has not declined, yet nothing is syncing for it (the claim
  /// question is still open), and a suspended trigger is not syncing either.
  /// Reporting "your logs stay on this device only" while data is uploading —
  /// or the reverse — is a false privacy statement on a health app, so this
  /// answers the question the surface actually means.
  ///
  /// Uid-scoped and read fresh from storage for the same reason
  /// [claimOnRecord] is: it must not race [setUser]'s async continuation.
  Future<bool> isSyncEnabledFor(String uid) async {
    if (_suspended) return false;
    final record = await _readClaim();
    return record != null && record.uid == uid && !record.declined;
  }

  /// Called when the signed-in user changes. A null uid tears sync down without
  /// touching local data — signing out must never wipe the device.
  Future<void> setUser(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    // A different account is a new situation: whatever [suspend] was holding
    // back belonged to the previous one. (An aborted deletion, where the uid
    // does NOT change, is what [resume] is for.)
    _suspended = false;
    // Both assignments are synchronous, before any `await`, and both fail
    // closed: no interleaving caller can observe the previous account's
    // service, or this account's service with the gate open. See
    // [_pendingClaim].
    _service = null;
    _pendingClaim = uid != null;
    if (uid == null) return;

    try {
      // `_firestore()` (by default `lunaFirestore()`) touches `Firebase.app()`,
      // which throws whenever this build has no initialized Firebase app (e.g.
      // Firebase console setup — task 1b — hasn't landed yet, or a test
      // harness with no Firebase app). Local-first: the rest of the app must
      // keep working regardless of whether sync infrastructure is available.
      // Evaluated before `_deviceId()` on purpose, so a build with no Firebase
      // never reaches secure storage at all.
      final firestore = _firestore();
      final deviceId = await _deviceId();
      _service = SyncService(
        db: _db,
        firestore: firestore,
        uid: uid,
        deviceId: deviceId,
      );
    } catch (_) {
      _service = null;
      return; // gate stays set; with no service there is nothing to push anyway
    }

    // "Has THIS ACCOUNT ever resolved the claim question on THIS DEVICE?" is a
    // per-uid fact, so it is answered by a per-uid record — never by
    // `AppSettings.lastSyncedAt`, which is device-global. Keying on
    // `lastSyncedAt` meant that once uid A synced from here, uid B signing in
    // on the same device skipped the question and auto-pushed A's local
    // history into `users/B/dailyLogs`.
    final record = await _readClaim();
    if (record != null && record.uid == uid) {
      if (record.declined) return; // stays gated until AccountSection reverses it
      _pendingClaim = false;
      await syncNow();
      return;
    }

    // No decision on record for this account. A device with existing local
    // logs is exactly the upgrade scenario `claim_local_data_sheet.dart` exists
    // for: `SyncService`'s first run pushes EVERY local row unconditionally
    // (`since == null` skips the `updatedAt` gate in `_pushLogs`), so
    // auto-syncing here — before the user has been asked anything — would
    // silently upload months of health data the instant they sign in. Defer to
    // the claim prompt instead; see [resolveClaim].
    final hasLocalLogs = (await DailyLogRepository(_db).getAll()).isNotEmpty;
    if (hasLocalLogs) return; // gate stays set; `AppGate` shows the prompt

    // Nothing to claim, so there is nothing to consent to. Record the pairing
    // so this account is not asked to "claim" its OWN synced data later (e.g.
    // after signing out and back in, once rows exist locally).
    await _writeClaim(ClaimRecord(uid: uid, declined: false));
    _pendingClaim = false;
    await syncNow();
  }

  /// Resolves the claim prompt's decision for the signed-in account.
  ///
  /// `upload: true` records the claim, clears the pending gate and runs the
  /// deferred sync — a genuine, consented push of the local history plus the
  /// normal pull.
  ///
  /// `upload: false` records the decline (scoped to this uid, via
  /// [ClaimPreference]) and deliberately leaves the pending gate SET: [syncNow]
  /// keeps refusing to run, so neither the app-resume hook nor a later
  /// debounced write can push the declined history. The persisted record is
  /// what makes either answer survive an app restart.
  ///
  /// A dismissed prompt must NOT reach this method: "no answer" is not
  /// "declined" — see `AppGate._maybePromptClaim`.
  Future<void> resolveClaim({required bool upload}) async {
    final uid = _uid;
    // No signed-in account means there is no one to record a decision for.
    // (Returning silently rather than throwing: this is reachable from UI
    // callbacks that can outlive a sign-out.)
    if (uid == null) return;
    await _writeClaim(ClaimRecord(uid: uid, declined: !upload));
    if (!upload) return;
    _pendingClaim = false;
    await syncNow();
  }

  /// Stops all sync for this device and waits for anything in flight to land.
  ///
  /// Account deletion (`AccountDeletionService`) sweeps the user's Firestore
  /// subtree collection by collection, with no atomicity. Anything this device
  /// writes during or after that sweep survives it, and once the auth user is
  /// gone that document is unreachable but still on the server — orphaned
  /// health data, the exact thing "delete my account" exists to prevent. The
  /// delete path can even arm a sync itself: it reloads `LogProvider` after
  /// wiping local data, and `main.dart`'s write-sync provider turns that
  /// notification into a [scheduleSync].
  ///
  /// So: call this BEFORE the sweep. It cancels the debounce, drops the
  /// service, makes [scheduleSync] and [syncNow] no-ops, and awaits the
  /// in-flight run so that when it returns, this device is provably not
  /// writing to Firestore any more. It stays in force until [resume] or until
  /// the signed-in uid changes (which is what deleting the account produces).
  Future<void> suspend() async {
    _suspended = true;
    _debounce?.cancel();
    _debounce = null;
    _service = null;
    await _inFlight;
  }

  /// Lifts [suspend] for the still-signed-in account — e.g. a deletion that
  /// aborted before touching anything, where sync should simply carry on. The
  /// claim decision is re-evaluated from scratch, so a suspended-then-resumed
  /// trigger cannot end up less gated than a freshly signed-in one.
  Future<void> resume() async {
    if (!_suspended) return;
    _suspended = false;
    final uid = _uid;
    _uid = null; // force setUser to re-run its evaluation for the same uid
    await setUser(uid);
  }

  /// Coalesces bursts of local writes into one sync.
  ///
  /// The day editor saves the whole row on every field change, so syncing per
  /// write would fire a dozen times while a user fills in one day.
  void scheduleSync() {
    if (_suspended) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    if (_pendingClaim) return; // no consent (yet) to push this device's history
    if (_suspended) return; // account deletion in progress — see [suspend]
    final run = _syncNow();
    _inFlight = run;
    try {
      await run;
    } finally {
      if (identical(_inFlight, run)) _inFlight = null;
    }
  }

  Future<void> _syncNow() async {
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
