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

  /// Generation counter for [setUser], bumped at its entry (and by [suspend]).
  ///
  /// [setUser] mutates [_uid], [_service] and [_pendingClaim] across `await`
  /// boundaries — the device id, the claim record, a local database read.
  /// Setting the gate before the first `await` closes the race against an
  /// interleaving CALLER, but NOT against an interleaving CONTINUATION of an
  /// earlier [setUser]. Reproduced: uid-2 has an `uploaded` record and its
  /// `setUser` blocks on a slow first `DeviceId.get()` (secure storage +
  /// keystore); the user signs in as uid-1, which is correctly gated; uid-2's
  /// continuation then resumes, assigns `_service` (still bound to uid-2),
  /// matches its own record, clears `_pendingClaim` and syncs — putting this
  /// device's local health rows into `users/uid-2/dailyLogs` while uid-1 is
  /// signed in and has consented to nothing, and leaving `_service` bound to
  /// uid-2 so every later resume/debounce keeps writing there.
  ///
  /// So every invocation captures this counter at entry and returns at each
  /// resumption point where it no longer matches, BEFORE any assignment. Only
  /// the newest invocation may touch this object's state. [suspend] bumps it
  /// too, so an evaluation already in flight cannot re-arm sync behind a
  /// suspend that has already returned.
  int _epoch = 0;

  /// The run [syncNow] currently has in flight, and the [SyncService] it was
  /// started for. Coalescing joins the existing run ONLY when that service is
  /// still the current one — see [syncNow].
  Future<void>? _inFlight;
  SyncService? _inFlightService;

  /// EVERY run not yet complete, including ones started for a service that has
  /// since been replaced. [suspend]'s guarantee is "this device is provably not
  /// writing to Firestore any more", which has to cover all of them, not just
  /// the newest — a run started for the previous account is still a run.
  final List<Future<void>> _outstanding = [];

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
  /// The persisted record alone is not that signal either, and the state where
  /// it lies is not exotic — it is every build that has no initialized Firebase
  /// app (which is this app today, until the console setup lands). [setUser]
  /// catches and leaves `_service` null; the user is still prompted, taps "Add
  /// to my account", [resolveClaim] durably records `uploaded`, its [syncNow]
  /// no-ops, and a record-only check then reports "Cloud sync is on" when
  /// nothing has been or can be uploaded. `_service == null` is what rules that
  /// out; [_pendingClaim] rules out the mid-[setUser] window, where the record
  /// may already say `uploaded` while [syncNow] is still refusing to run.
  ///
  /// Uid-scoped and read fresh from storage for the same reason
  /// [claimOnRecord] is: it must not race [setUser]'s async continuation.
  Future<bool> isSyncEnabledFor(String uid) async {
    if (_suspended || _pendingClaim || _service == null) return false;
    final record = await _readClaim();
    return record != null && record.uid == uid && !record.declined;
  }

  /// Whether this device holds local state a first sync would upload — the
  /// question the claim prompt actually exists to ask, and the predicate BOTH
  /// gates (this class's own and `AppGate._maybePromptClaim`'s) must share.
  ///
  /// Deliberately not "are there daily logs". `SyncService` also pushes
  /// `users/{uid}/settings/current`, which carries `pregnancyStartDate` —
  /// arguably the most sensitive field in the app. Keying only on `dailyLogs`
  /// meant a device with zero logged days but real health settings (reachable:
  /// an existing local-only user in pregnancy mode who has not logged days)
  /// auto-synced with no prompt at all — and, since the per-uid claim record
  /// landed, durably recorded an `uploaded` consent that was never given.
  /// Tombstones count for the same reason: `_pushTombstones` publishes one
  /// marker per deleted date, which is itself a statement about days this
  /// person tracked.
  ///
  /// `settingsUpdatedAt != null` is the test rather than "does the row differ
  /// from the defaults": it is stamped only by `SettingsRepository.update`,
  /// i.e. by a real user edit, and it is exactly what
  /// `SyncService._pushSettings` gates on — so this is true precisely when
  /// something would leave the device, no more and no less. A brand-new user
  /// who has not edited anything is still not prompted; anyone else is, and
  /// over-prompting is the only direction that is safe here.
  Future<bool> hasLocalDataToClaim() async {
    final repository = DailyLogRepository(_db);
    if ((await repository.getAll()).isNotEmpty) return true;
    if ((await repository.getTombstones()).isNotEmpty) return true;
    return (await SettingsRepository(_db).get()).settingsUpdatedAt != null;
  }

  /// Called when the signed-in user changes. A null uid tears sync down without
  /// touching local data — signing out must never wipe the device.
  Future<void> setUser(String? uid) async {
    if (uid == _uid) return;
    // Captured before anything is mutated; re-checked after every `await`
    // below. See [_epoch] — without it an older invocation's continuation
    // overwrites `_service` and `_pendingClaim` for an account that is no
    // longer signed in.
    final epoch = ++_epoch;
    _uid = uid;
    // A different account is a new situation: whatever [suspend] was holding
    // back belonged to the previous one. (An aborted deletion, where the uid
    // does NOT change, is what [resume] is for.)
    _suspended = false;
    // Both assignments are synchronous, before any `await`, and both fail
    // closed, so no interleaving CALLER can observe the previous account's
    // service, or this account's service with the gate open. See
    // [_pendingClaim]. That is necessary but NOT sufficient on its own: an
    // interleaving continuation of an earlier `setUser` can still resume and
    // undo both, which is what the [_epoch] checks below exist for.
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
      if (epoch != _epoch) return; // a newer setUser owns this object now
      _service = SyncService(
        db: _db,
        firestore: firestore,
        uid: uid,
        deviceId: deviceId,
      );
    } catch (_) {
      if (epoch != _epoch) return;
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
    if (epoch != _epoch) return;
    if (record != null && record.uid == uid) {
      if (record.declined) return; // stays gated until AccountSection reverses it
      _pendingClaim = false;
      await syncNow();
      return;
    }

    // No decision on record for this account. A device with existing local
    // health state is exactly the upgrade scenario `claim_local_data_sheet.dart`
    // exists for: `SyncService`'s first run pushes EVERY local row
    // unconditionally (`since == null` skips the `updatedAt` gate in
    // `_pushLogs`) and pushes the settings document too, so auto-syncing here —
    // before the user has been asked anything — would silently upload months of
    // health data (and their pregnancy state) the instant they sign in. Defer
    // to the claim prompt instead; see [resolveClaim].
    final hasLocalData = await hasLocalDataToClaim();
    if (epoch != _epoch) return;
    if (hasLocalData) return; // gate stays set; `AppGate` shows the prompt

    // Nothing to claim, so there is nothing to consent to. Record the pairing
    // so this account is not asked to "claim" its OWN synced data later (e.g.
    // after signing out and back in, once rows exist locally).
    await _writeClaim(ClaimRecord(uid: uid, declined: false));
    if (epoch != _epoch) return;
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
    // The same guard [setUser] carries, for the same reason, at the one other
    // place `_pendingClaim` is mutated across an `await`. The storage write is
    // slow (keystore), and the account can change while it is in flight: the
    // continuation would then clear the gate and sync for whoever is signed in
    // NOW, pushing this device's local health rows into an account that
    // consented to nothing. Reproduced against the epoch fix, which does not
    // cover this method. The record written above is uid-scoped, so it is
    // correct either way and does not need undoing.
    if (_uid != uid) return;
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
    // Abandon any [setUser] evaluation still in flight, so its continuation
    // cannot rebuild `_service` or clear the claim gate after this returns.
    _epoch++;
    _debounce?.cancel();
    _debounce = null;
    _service = null;
    // Every outstanding run, not just the newest: since [syncNow] no longer
    // coalesces across a service change, two can genuinely be in flight at
    // once, and a run started for the previous account is writing to Firestore
    // just the same. `_syncNow` swallows its own errors, so this cannot throw.
    await Future.wait(_outstanding.toList());
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

  /// Runs one sync, or JOINS the one already running.
  ///
  /// The coalescing is not an optimisation — it is what makes [suspend]'s wait
  /// correct, and therefore what keeps an account deletion's Firestore sweep
  /// from being outlived by a push. `SyncService.syncNow()` silently DROPS an
  /// overlapping call (its own `_running` guard) and hands back an
  /// already-complete future. Recording that no-op as [_inFlight] — which an
  /// earlier version did, because it tracked only the most recent call —
  /// overwrote the real run's future and then nulled it in its own `finally`,
  /// so a later [suspend] awaited nothing and returned while a push was still
  /// on the wire. Both overlapping callers are routine, and one was made live
  /// by this same round of work: `AppGate.didChangeAppLifecycleState`'s
  /// unawaited resume hook, and the now-eager 2-second [scheduleSync] debounce.
  ///
  /// Returning the canonical future instead means [_inFlight] always refers to
  /// the run that is actually writing, and every caller's `await` waits for it.
  ///
  /// The coalescing is per-SERVICE, not per-trigger. Joining any in-flight run
  /// meant a new account's sign-in sync silently joined the PREVIOUS account's
  /// run and was dropped: [setUser] awaits its own [syncNow], so it returned
  /// believing it had synced, and `_enableSync` then reported success off a
  /// `lastSyncedAt` the other account's run had advanced. It self-heals on the
  /// next resume, which is exactly what makes it hard to see.
  Future<void> syncNow() {
    // No consent (yet) to push this device's history.
    if (_pendingClaim) return Future<void>.value();
    // Account deletion in progress — see [suspend].
    if (_suspended) return Future<void>.value();
    final existing = _inFlight;
    // `identical`, not `==`: the question is whether the run already going is
    // one THIS service started, and a `SyncService` has no value identity.
    if (existing != null && identical(_inFlightService, _service)) {
      return existing;
    }
    final run = _syncNow();
    _inFlight = run;
    _inFlightService = _service;
    _outstanding.add(run);
    return run.whenComplete(() {
      _outstanding.remove(run);
      if (identical(_inFlight, run)) {
        _inFlight = null;
        _inFlightService = null;
      }
    });
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
