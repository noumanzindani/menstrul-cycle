import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../providers/auth_provider.dart';
import '../../providers/log_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/account_deletion_service.dart';
import '../../services/claim_preference.dart';
import '../../services/firebase_availability.dart';
import '../../services/firestore_ref.dart';
import '../../services/lock_service.dart';
import '../../services/media_cache.dart';
import '../../services/notification_service.dart';
import '../../services/sync_trigger.dart';
import '../auth/auth_error_text.dart';

/// Signed-in identity, cloud-sync status (reversible if the user declined to
/// upload their pre-existing local data at sign-in — see
/// `claim_local_data_sheet.dart` / `SyncTrigger.resolveClaim`), sign-out, and
/// account deletion.
///
/// ## Deletion is a REQUEST, not an erasure
///
/// "Request account deletion" wipes this device immediately and records a
/// server-side marker (`AccountDeletionService.requestDeletion`). The cloud
/// copy is left intact and is purged by a scheduled job after
/// [AccountDeletionService.graceWindow]; until then the request can be
/// withdrawn from this same section by signing back in. Nothing here calls
/// `User.delete()` — the auth user is deleted by that purge, not by the
/// request. That is deliberate: `User.delete()` requires a recent sign-in, so
/// for a restored session (nearly everyone) it failed with
/// `requires-recent-login` AFTER the local wipe had already run, leaving a user
/// who believed their account was gone still signed into a live one.
class AccountSection extends StatefulWidget {
  const AccountSection({
    super.key,
    AccountDeletionService Function(String uid)? deletionService,
    Future<void> Function()? clearDeclinedPreference,
    Future<void> Function()? clearPin,
    Future<void> Function()? cancelNotifications,
    Future<void> Function()? clearFirestoreCache,
    Future<void> Function()? clearMediaCache,
    this.requestTimeout = const Duration(seconds: 20),
  })  : deletionService = deletionService ?? _liveDeletionService,
        clearMediaCache = clearMediaCache ?? _clearMediaCache,
        clearDeclinedPreference =
            clearDeclinedPreference ?? ClaimPreference.clear,
        clearPin = clearPin ?? LockService.clearPin,
        cancelNotifications =
            cancelNotifications ?? NotificationService.cancelAll,
        clearFirestoreCache = clearFirestoreCache ?? clearLunaFirestoreCache;

  static AccountDeletionService _liveDeletionService(String uid) =>
      AccountDeletionService(firestore: lunaFirestore(), uid: uid);

  static Future<void> _clearMediaCache() => MediaCache().clear();

  /// Deletes downloaded photos and videos from the on-disk cache.
  ///
  /// Injectable for the same reason [clearPin] is — `path_provider` has no
  /// platform-channel handler under `flutter_tester`. Cannot live inside
  /// `AppDatabase.deleteAllData()`, which is a pure drift transaction.
  final Future<void> Function() clearMediaCache;

  /// Overridable so tests can inject a fake instead of touching the real
  /// `Firebase.app()` singleton — mirrors `SyncTrigger`'s identical seam (see
  /// its doc comment) for the same reason: `lunaFirestore()` throws with no
  /// Firebase app configured, which is the current state of this app (Firebase
  /// console setup is a separate, still-pending task).
  final AccountDeletionService Function(String uid) deletionService;

  /// These three are overridable for the same reason: their real
  /// implementations are backed by `flutter_secure_storage` and the local
  /// notifications plugin, whose platform channels have no handler in
  /// `flutter_tester` on this host — `flutter_secure_storage` in particular
  /// HANGS rather than throwing, and `pumpAndSettle` does not wait on a stuck
  /// platform-channel call (it only waits on scheduled frames), so an
  /// uninjected call does not time the test out: it silently leaves the
  /// awaited pipeline stalled, which is far easier to miss than a hang.
  final Future<void> Function() clearDeclinedPreference;
  final Future<void> Function() clearPin;
  final Future<void> Function() cancelNotifications;

  /// Wipes Firestore's unencrypted on-device cache — see
  /// [clearLunaFirestoreCache], which also explains why it can only run at the
  /// very end of the deletion flow.
  ///
  /// Overridable for a reason beyond the usual platform-channel one:
  /// `FakeFirebaseFirestore.clearPersistence()` wipes the whole fake database,
  /// server side included, so a test that let the real call through could not
  /// then assert that the cloud copy survived the request.
  final Future<void> Function() clearFirestoreCache;

  /// How long to wait for the deletion marker to reach the server before
  /// reporting failure.
  ///
  /// Offline, a Firestore write is accepted into the local queue and its
  /// future simply never completes — no exception, ever. Without this the
  /// deletion flow would sit behind its progress dialog indefinitely and the
  /// catch would never fire.
  final Duration requestTimeout;

  @override
  State<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<AccountSection> {
  /// Both of these are per-uid cached Futures rather than watched state.
  /// `SyncTrigger.isPendingClaim` is deliberately non-reactive (its own doc
  /// comment explains why `notifyListeners()` isn't an option: it broke
  /// `widget_test.dart` with a setState-during-build error), and the pending
  /// deletion request is a network read. Both are refreshed when the signed-in
  /// uid changes and manually after this widget itself changes them.
  Future<bool>? _syncEnabled;
  Future<DeletionRequest?>? _pendingDeletion;
  String? _futuresUid;

  /// Part of the sync-status cache key, not just the uid. `SyncTrigger.setUser`
  /// resolves asynchronously, so the first `isSyncEnabledFor` read after a
  /// sign-in can observe a transient value and then latch it forever. The
  /// pending-claim flag flips as that evaluation settles, so folding it into
  /// the key makes the next rebuild re-read instead.
  bool? _futuresPendingClaim;

  /// Re-entrancy guard for the destructive flow. The modal progress dialog is
  /// the primary block; this closes the gap between the tap and the dialog's
  /// first frame.
  bool _busy = false;

  void _ensureFutures(SyncTrigger trigger, String? uid) {
    if (uid == null) {
      _syncEnabled = null;
      _pendingDeletion = null;
      _futuresUid = null;
      _futuresPendingClaim = null;
      return;
    }
    final pendingClaim = trigger.isPendingClaim;
    if (_futuresUid == uid && _futuresPendingClaim == pendingClaim) return;
    final uidChanged = _futuresUid != uid;
    _futuresUid = uid;
    _futuresPendingClaim = pendingClaim;
    _syncEnabled = trigger.isSyncEnabledFor(uid);
    // The network read is keyed on the uid alone: a claim-gate flip says
    // nothing about whether a deletion request exists.
    if (uidChanged) _pendingDeletion = _readPendingDeletion(uid);
  }

  /// Fails toward "no request on record": this tile is informational, and the
  /// binding gate is `SyncService`'s own check plus `firestore.rules` — not
  /// this read, which is unavailable on a build with no Firebase app at all.
  Future<DeletionRequest?> _readPendingDeletion(String uid) async {
    try {
      return await widget.deletionService(uid).pendingRequest();
    } catch (_) {
      return null;
    }
  }

  String get _windowLabel => '${AccountDeletionService.graceWindow.inDays} days';

  /// Reverses an earlier "keep on this device only" decision — or answers the
  /// claim question for an account that never did. This is the only place in
  /// the app that calls `resolveClaim(upload: true)` outside the claim sheet
  /// itself (which a recorded answer, by definition, suppresses from ever
  /// showing again); without it a decline is permanent.
  Future<void> _enableSync(String uid) async {
    final trigger = context.read<SyncTrigger>();
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final before = settings.lastSyncedAt;

    await trigger.resolveClaim(upload: true);
    await settings.load(); // pick up the fresh lastSyncedAt after syncing
    final enabled = await trigger.isSyncEnabledFor(uid);
    // `lastSyncedAt` only advances on a FULLY successful run, so it is the one
    // honest signal that something actually reached the server. Reporting
    // success off the back of the button press alone told an offline user
    // their logs were backed up when nothing had left the device.
    final synced =
        settings.lastSyncedAt != null && settings.lastSyncedAt != before;
    if (!mounted) return;
    setState(() {
      _futuresUid = uid;
      _syncEnabled = Future.value(enabled);
    });
    messenger.showSnackBar(SnackBar(
      content: Text(enabled && synced
          ? 'Cloud sync is on — your logs are backed up.'
          : "Cloud sync is on, but this device hasn't synced yet. Check "
              'your connection.'),
    ));
  }

  Future<bool> _confirmRequest(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: Text(
          'Everything on this device is erased straight away.\n\n'
          'Your account and the copy stored on our server are kept for '
          '$_windowLabel and then permanently deleted. Sign in again within '
          '$_windowLabel to cancel the request and get that copy back.\n\n'
          "You'll be signed out.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('account.confirmDelete'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _requestDeletion(BuildContext context) async {
    if (_busy) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    if (!await _confirmRequest(context) || !context.mounted) return;

    // Captured before the async gaps. All of these are needed on the success
    // path; the abort path simply doesn't use them.
    final trigger = context.read<SyncTrigger>();
    final db = context.read<AppDatabase>();
    final logs = context.read<LogProvider>();
    final meds = context.read<MedicationProvider>();
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    setState(() => _busy = true);
    var progressOpen = true;
    void closeProgress() {
      if (!progressOpen) return;
      progressOpen = false;
      navigator.pop();
    }

    // Not awaited: this dialog is dismissed by `closeProgress` below, not by
    // the user. It blocks the whole UI for the duration of a destructive
    // network operation that used to run behind a fully interactive screen —
    // where a second tap stacked a second concurrent run.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          key: Key('account.deleteProgress'),
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Expanded(child: Text('Sending your request…')),
            ],
          ),
        ),
      ),
    ));

    try {
      // BEFORE anything else: cancels the debounce, drops the SyncService and
      // no-ops scheduleSync/syncNow. The local wipe below is itself a sync
      // trigger (`logs.load()` notifies LogProvider, which main.dart turns
      // into a scheduleSync), so this has to come first.
      //
      // It DOES await the runs already in flight — `suspend()` waits on every
      // outstanding one, so when this returns the device is provably not
      // writing to Firestore. (That was not true when this flow was written;
      // Task 10 fixed it, and the reviewer verified it by execution.) The
      // durable guard is still the marker itself — `SyncService.syncNow`
      // refuses to run for an account with a request on record, from any
      // device, in any session, including after a relaunch.
      await trigger.suspend();

      try {
        await widget
            .deletionService(uid)
            .requestDeletion()
            .timeout(widget.requestTimeout);
      } on TimeoutException {
        await trigger.resume();
        closeProgress();
        _showError(
          messenger,
          "Couldn't reach the server — check your connection and try again. "
          'Nothing has been deleted.',
        );
        return;
      } catch (_) {
        await trigger.resume();
        closeProgress();
        _showError(
          messenger,
          "Couldn't record your deletion request. Check your connection and "
          'try again. Nothing has been deleted.',
        );
        return;
      }

      // The device, now. `deleteAllData` removes every local row and reseeds
      // default settings (which resets `lastSyncedAt`/`settingsUpdatedAt`).
      await db.deleteAllData();
      // It does NOT clear the app-lock PIN or cancel OS-level schedules —
      // both live outside the database. The notifications matter beyond
      // tidiness: `CheckInHorizon.plan` precomputes up to 14 days of one-shot
      // check-ins whose action handler runs `CheckInWriter.answerNoBleeding`
      // in a BACKGROUND ISOLATE, opening a second connection to the encrypted
      // database and writing a daily log with the app killed. A surviving
      // schedule can therefore resurrect health data days after the user
      // erased everything.
      await widget.clearPin();
      // Full-size media downloaded for viewing lives in the cache directory,
      // outside both the drift database and Firestore's SDK store — so neither
      // `deleteAllData` above nor `clearFirestoreCache` below touches it.
      // Swallowed: an unreadable cache is a cache with nothing to lose, and
      // this must not be what stops a deletion request from completing.
      try {
        await widget.clearMediaCache();
      } catch (_) {}
      await widget.cancelNotifications();
      // The providers cache what they last loaded and are not refreshed by a
      // direct database write, so without this the just-erased data would
      // still render for whoever signs in next on this device (there is one
      // shared local database regardless of account).
      await settings.load();
      await logs.load();
      await meds.load();
      // uid-scoped and about to be meaningless.
      await widget.clearDeclinedPreference();

      // Signing out (not deleting) ends the session. The uid change also
      // lifts the suspend, which is safe only because it happens last: by
      // now there is no local data left to push and the marker is on record,
      // so `SyncService` refuses to sync this account from any device.
      await auth.signOut();

      // LAST, and it has to be last: `terminate()` leaves the client accepting
      // nothing but `clearPersistence()`, so the marker write above — and the
      // sign-out — must already have landed. See [clearLunaFirestoreCache].
      //
      // Until this ran, "Everything on this device is erased straight away"
      // was false: drift was wiped but Firestore's own on-device persistence
      // still physically held `users/{uid}/dailyLogs` and the settings
      // document, UNENCRYPTED (drift is encrypted at rest; the Firestore SDK
      // cache is not). It also discards any push still queued offline, which
      // `suspend()` cannot do — that queue lives inside the SDK, not here.
      //
      // Swallowed rather than surfaced: by this point the request is on record
      // and the database is already empty, so there is nothing to roll back
      // and nothing actionable to tell the user. It throws on a build with no
      // Firebase app, which is this build today — there is no cache to clear
      // there either.
      try {
        await widget.clearFirestoreCache();
      } catch (_) {}

      closeProgress();
      final error = auth.lastError;
      if (error != null) {
        // A failure ANYWHERE in this flow has to be observable. The previous
        // version caught auth errors into `lastError` and never read it, so
        // the whole thing could fail with no SnackBar at all.
        _showError(
          messenger,
          '${messageForAuthError(error)} Your deletion request is saved and '
          'this device is already erased.',
        );
        return;
      }
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Deletion requested. This device is erased. Sign in again within '
          '$_windowLabel if you change your mind.',
        ),
      ));
    } finally {
      closeProgress();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Retry',
        onPressed: () {
          if (mounted) _requestDeletion(context);
        },
      ),
    ));
  }

  Future<void> _cancelDeletion(String uid) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final trigger = context.read<SyncTrigger>();
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();
    final meds = context.read<MedicationProvider>();
    setState(() => _busy = true);
    try {
      await widget
          .deletionService(uid)
          .cancelDeletion()
          .timeout(widget.requestTimeout);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
          "Couldn't cancel the deletion. Check your connection and try again.",
        ),
      ));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // A no-op unless this session is the one that suspended (it re-evaluates
    // the claim gate from scratch, so a resumed trigger is never less gated
    // than a freshly signed-in one).
    await trigger.resume();
    // And `resume()` IS a no-op in the common case — the user cancels after
    // signing back in, in a session that never suspended, so it returns at its
    // first line. Nothing else would then trigger a sync, leaving the user on
    // the device the request wiped, reading "Not synced yet", until they
    // background and foreground the app. The provider reloads follow because
    // `SyncService` writes straight to drift; nothing tells the in-memory
    // providers to re-read what the pull just landed.
    await trigger.syncNow();
    if (!mounted) return;
    await settings.load();
    await logs.load();
    await meds.load();
    if (!mounted) return;
    setState(() {
      _futuresUid = uid;
      _pendingDeletion = Future.value(null);
      _syncEnabled = trigger.isSyncEnabledFor(uid);
    });
    messenger.showSnackBar(const SnackBar(
      content: Text('Deletion cancelled. Your account and cloud data are safe.'),
    ));
  }

  Widget _pendingTile(BuildContext context, String uid, DeletionRequest request) {
    final scheme = Theme.of(context).colorScheme;
    final purgeAfter = request.purgeAfter;
    final when = purgeAfter == null
        // The marker exists but carries no readable deadline. Say what is
        // certainly true rather than inventing a date.
        ? 'within $_windowLabel of your request'
        : 'on ${MaterialLocalizations.of(context).formatFullDate(purgeAfter)}';
    return Container(
      key: const Key('account.deletionPending'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Account deletion pending',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Your account and the copy of your logs on our server are '
            'scheduled to be permanently deleted $when. Cloud sync stays off '
            'until then. Cancel now and nothing is deleted.',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('account.cancelDeletion'),
              onPressed: _busy ? null : () => _cancelDeletion(uid),
              child: const Text('Cancel deletion'),
            ),
          ),
        ],
      ),
    );
  }

  /// Distinct from the normal sync-off state below: this is a DEVICE fact
  /// (`Firebase.initializeApp()` failed in `main()` -- see
  /// `FirebaseAvailability`'s doc comment), not a user choice, so it must not
  /// read as "you turned this off". A user staring at "Cloud sync is off" with
  /// no way to ever turn it on would reasonably assume they missed a step;
  /// this tells them the device itself cannot reach sync at all. No trailing
  /// action -- there is nothing this tap could do that main()'s own
  /// `Firebase.initializeApp()` didn't already try.
  Widget _syncUnavailableTile(BuildContext context) => ListTile(
        key: const Key('account.syncUnavailable'),
        leading: Icon(
          Icons.cloud_off,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Cloud sync unavailable on this device'),
        subtitle: const Text(
          "This device can't reach cloud sync right now. Your logs stay "
          'private and safe on this device either way.',
        ),
      );

  Widget _syncTile(BuildContext context, String uid) {
    final firebaseAvailable =
        context.watch<FirebaseAvailability?>()?.available ?? true;
    if (!firebaseAvailable) return _syncUnavailableTile(context);

    final settings = context.watch<SettingsProvider>();
    return FutureBuilder<bool>(
      future: _syncEnabled,
      builder: (context, snapshot) {
        // Null (still loading) reads as OFF on purpose: briefly understating
        // sync is safe, while briefly claiming "your logs stay on this device
        // only" while they are uploading is a false privacy statement.
        final enabled = snapshot.data ?? false;
        if (!enabled) {
          return ListTile(
            key: const Key('account.enableSync'),
            leading: const Icon(Icons.cloud_off_outlined),
            title: const Text('Cloud sync is off'),
            subtitle: const Text(
              'Your logs stay on this device only. You can turn sync on any '
              'time.',
            ),
            trailing: TextButton(
              onPressed: _busy ? null : () => _enableSync(uid),
              child: const Text('Turn on'),
            ),
          );
        }
        return ListTile(
          key: const Key('account.syncStatus'),
          leading: const Icon(Icons.cloud_done_outlined),
          title: const Text('Cloud sync is on'),
          subtitle: Text(
            settings.lastSyncedAt != null
                ? 'Your logs are backed up and synced across devices.'
                : 'Not synced yet — this happens automatically.',
          ),
        );
      },
    );
  }

  Widget _signOutTile(BuildContext context) => ListTile(
        key: const Key('account.signOut'),
        leading: const Icon(Icons.logout),
        title: const Text('Sign out'),
        subtitle: const Text('Your logs stay on this device'),
        onTap: _busy ? null : () => context.read<AuthProvider>().signOut(),
      );

  Widget _deleteTile(BuildContext context) => ListTile(
        key: const Key('account.delete'),
        leading: Icon(
          Icons.delete_forever,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Request account deletion'),
        subtitle: Text(
          'Erases this device now; the server copy is deleted after '
          '$_windowLabel',
        ),
        onTap: _busy ? null : () => _requestDeletion(context),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final trigger = context.read<SyncTrigger>();
    final uid = auth.user?.uid;
    _ensureFutures(trigger, uid);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Account'),
          subtitle: Text(auth.user?.email ?? 'Not signed in'),
        ),
        if (uid == null)
          _signOutTile(context)
        else
          FutureBuilder<DeletionRequest?>(
            future: _pendingDeletion,
            builder: (context, snapshot) {
              final pending = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pending != null)
                    _pendingTile(context, uid, pending)
                  else
                    _syncTile(context, uid),
                  _signOutTile(context),
                  // Hidden while a request is pending: the way out of that
                  // state is "Cancel deletion", not requesting it again.
                  if (pending == null) _deleteTile(context),
                ],
              );
            },
          ),
      ],
    );
  }
}
