import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily_log_repository.dart';
import '../db/database.dart';
import '../providers/auth_provider.dart';
import '../providers/log_provider.dart';
import '../providers/settings_provider.dart';
import '../services/account_deletion_service.dart';
import '../services/claim_preference.dart';
import '../services/firestore_ref.dart';
import '../services/sync_trigger.dart';
import 'account/deletion_pending_screen.dart';
import 'app_shell.dart';
import 'auth/claim_local_data_sheet.dart';
import 'auth/sign_in_screen.dart';
import 'lock/lock_screen.dart';
import 'onboarding/onboarding_screen.dart';

/// Wraps the app in the lock gate. When app lock is enabled, shows [LockScreen]
/// on cold start and again whenever the app returns from the background.
class AppGate extends StatefulWidget {
  const AppGate({
    super.key,
    this.pendingDeletion = _livePendingDeletion,
    this.cancelDeletion = _liveCancelDeletion,
  });

  /// The deletion-request marker read, and its withdrawal.
  ///
  /// Injected for the reason `AccountSection`'s identical seam is: the live
  /// implementations go through `lunaFirestore()`, which throws with no
  /// initialized Firebase app — the state of every test harness, and of this
  /// build until the console setup lands.
  final Future<DeletionRequest?> Function(String uid) pendingDeletion;
  final Future<void> Function(String uid) cancelDeletion;

  static Future<DeletionRequest?> _livePendingDeletion(String uid) =>
      AccountDeletionService(firestore: lunaFirestore(), uid: uid)
          .pendingRequest();

  static Future<void> _liveCancelDeletion(String uid) =>
      AccountDeletionService(firestore: lunaFirestore(), uid: uid)
          .cancelDeletion();

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  bool _locked = false;
  bool _initialLockApplied = false;

  /// The uid the claim prompt has already been raised for this session, NOT a
  /// bare "shown once" bool: a bool latched forever, so after uid-1 answered,
  /// uid-2 signing in on the same device (Settings now has a sign-out button)
  /// was never asked — and, because `SyncTrigger.setUser` leaves the gate set
  /// for an unanswered account, uid-2 then got no sync at all, silently.
  String? _claimPromptShownFor;

  /// The uid the deletion-marker read has already been issued for, and its
  /// result. Same per-uid keying as [_claimPromptShownFor], for the same
  /// reason: a bare bool would latch across a sign-out and sign-in.
  String? _deletionCheckedFor;
  DeletionRequest? _pendingDeletion;

  /// The marker read is a network round-trip, and it must not become one the
  /// user waits on. Nothing here blocks a build: the read is issued from a
  /// post-frame callback and the app renders normally until it lands, so the
  /// common path (no request on record — nearly everyone) costs one small
  /// document read off the critical path and no added latency at all. If it
  /// errors, times out, or the build has no Firebase app, the result is "no
  /// request", i.e. show the app: this notice must never be able to lock
  /// someone out of their own tracker.
  static const _deletionCheckTimeout = Duration(seconds: 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (!mounted) return;
      if (context.read<SettingsProvider>().appLockEnabled) {
        setState(() => _locked = true);
      }
    }
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      // Pull anything logged on another device while we were away.
      context.read<SyncTrigger>().syncNow();
    }
  }

  /// Offers to upload pre-existing local logs the first time an account signs
  /// in on this device. Runs after the frame so it can show a modal sheet.
  void _maybePromptClaim(BuildContext context, String? uid) {
    if (uid == null || _claimPromptShownFor == uid) return;
    _claimPromptShownFor = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final trigger = context.read<SyncTrigger>();
      // Only ask when there is local data to ask about. Checked first because
      // it is a fast local read and it rules the prompt out for most signed-in
      // rebuilds (a fresh account with an empty device), which then never
      // reach `ClaimPreference`'s secure-storage read below.
      //
      // Deliberately `SyncTrigger.hasLocalDataToClaim()` and NOT a daily-log
      // count: `SyncService` pushes the settings document too, so a device
      // with no logged days but real health settings (pregnancy state among
      // them) has something to consent to. This MUST stay the same predicate
      // `SyncTrigger.setUser` gates on — if the two disagree, the account is
      // either gated and never prompted (sync silently off forever) or
      // prompted about nothing. The count below is only for the sheet's copy.
      if (!await trigger.hasLocalDataToClaim() || !context.mounted) return;
      final count = (await DailyLogRepository(db).getAll()).length;
      if (!context.mounted) return;
      // "Already answered" is per-ACCOUNT, not per-device: a record belonging
      // to a DIFFERENT uid must not suppress this genuinely new question, and
      // `AppSettings.lastSyncedAt` (device-global — it stays non-null once ANY
      // account has synced here) must not be consulted at all.
      //
      // Wrapped because this is the one secure-storage call on this path that
      // isn't already inside `SyncTrigger.setUser`'s try/catch, and an
      // exception escaping an `addPostFrameCallback` closure is an unhandled
      // async error: the prompt would never appear while the sync gate stayed
      // set, i.e. sync silently off with no way to turn it on. Failing toward
      // SHOWING the prompt costs at most a repeated question.
      ClaimRecord? record;
      try {
        record = await trigger.claimOnRecord();
      } catch (_) {
        record = null;
      }
      if (record?.uid == uid) return;
      if (!context.mounted) return;
      final upload = await showClaimLocalDataSheet(context, dayCount: count);
      // null is NOT "declined". The sheet returns null only when it was
      // dismissed without an answer (the Android system back button is not
      // blocked by `isDismissible: false`; `PopScope` now blocks it, but a
      // dismissal must still be safe). Collapsing that to `false` wrote a
      // durable, uid-scoped decline the user never made, and they would never
      // be asked again. Persist nothing and leave the sync gate set: the
      // question comes back next launch.
      if (upload == null || !context.mounted) return;
      // `resolveClaim` (not a bare `syncNow`): `true` records the claim,
      // clears SyncTrigger's pending-claim gate and runs the deferred sync;
      // `false` records the decline for this uid and leaves the gate set so
      // nothing pushes the declined history later.
      await trigger.resolveClaim(upload: upload);
    });
  }

  /// Looks for a deletion request on record for the signed-in account.
  ///
  /// Deliberately registered AFTER [_maybePromptClaim] in `build`, and it does
  /// not touch that flow: the claim prompt's sequencing (post-frame callback,
  /// `hasLocalDataToClaim()` first, per-uid record check, null ≠ declined) is
  /// load-bearing against the pre-consent upload race and is left exactly as
  /// it was. The two can overlap only for an account that requested deletion
  /// from ANOTHER device and still has local data here, and that overlap is
  /// harmless: `SyncService.syncNow` refuses to run for an account with a
  /// marker on record, so answering the claim prompt pushes nothing.
  void _maybeCheckDeletion(String? uid) {
    if (uid == null || _deletionCheckedFor == uid) return;
    _deletionCheckedFor = uid;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      DeletionRequest? request;
      try {
        request =
            await widget.pendingDeletion(uid).timeout(_deletionCheckTimeout);
      } catch (_) {
        // Fail toward showing the app. Offline this is also the reachable
        // false negative: a user inside the grace window sees no notice at all
        // until they have a connection. Under-warning is the only direction
        // that is safe here — the binding gate is the marker itself, which
        // `SyncService` re-reads on every run.
        request = null;
      }
      if (!mounted || request == null || _deletionCheckedFor != uid) return;
      setState(() => _pendingDeletion = request);
    });
  }

  /// Withdraws the request, then pulls the account's data back down.
  ///
  /// The sync is not incidental. `SyncTrigger.resume()` returns immediately
  /// unless this session is the one that suspended — which it is not, in a
  /// fresh session after signing back in — so without an explicit [syncNow]
  /// the user would sit on the device they wiped, reading "Not synced yet",
  /// until they background and foreground the app. The provider reloads follow
  /// for the same reason: `SyncService` writes straight to drift and nothing
  /// tells the in-memory providers to re-read.
  Future<void> _cancelPendingDeletion(BuildContext context, String uid) async {
    final trigger = context.read<SyncTrigger>();
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();
    await widget.cancelDeletion(uid); // throws → the screen reports it
    if (!mounted) return;
    setState(() => _pendingDeletion = null);
    await trigger.syncNow();
    if (!mounted) return;
    await settings.load();
    await logs.load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // Cold start: Firebase restores the session asynchronously. Showing a
    // splash here avoids a flash of the sign-in form for an already-signed-in
    // user.
    if (auth.state == AuthState.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // An account is required (design spec §7.1).
    if (auth.state == AuthState.signedOut) {
      // Forget which account was asked: whoever signs in next — including the
      // same account, if it never answered — gets the question again.
      _claimPromptShownFor = null;
      // Same reasoning for the marker: the next account to sign in here is a
      // different question, and a stale answer must not carry over.
      _deletionCheckedFor = null;
      _pendingDeletion = null;
      return const SignInScreen();
    }
    _maybePromptClaim(context, auth.user?.uid);
    _maybeCheckDeletion(auth.user?.uid);

    final settings = context.watch<SettingsProvider>();

    // Wait for settings to load to avoid a flash of the wrong screen.
    if (!settings.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // A pending deletion outranks onboarding, and that ordering IS the fix:
    // `deleteAllData()` resets `onboardingComplete`, so a user who requested
    // deletion and signs back in inside the grace window would otherwise walk
    // the whole first-run flow for an account scheduled for erasure and never
    // be told — Settings → Account, the only other disclosure, is somewhere
    // they have no reason to go.
    //
    // It sits ahead of the lock branch below as a consequence, which is
    // consistent with what this gate already does (the sign-in screen and the
    // claim sheet both precede the lock too) and cannot expose anything: both
    // actions on that screen are non-destructive, and after a deletion request
    // the app-lock PIN is cleared and settings are reset to defaults, so app
    // lock is off in the state this branch exists for.
    final pendingDeletion = _pendingDeletion;
    final uid = auth.user?.uid;
    if (pendingDeletion != null && uid != null) {
      return DeletionPendingScreen(
        request: pendingDeletion,
        onCancel: () => _cancelPendingDeletion(context, uid),
        onSignOut: () => context.read<AuthProvider>().signOut(),
      );
    }

    // First run: onboarding before anything else.
    if (!settings.onboardingComplete) {
      return const OnboardingScreen();
    }

    final enabled = settings.appLockEnabled;

    // Lock once on the first build where app lock is known to be enabled.
    if (enabled && !_initialLockApplied) {
      _initialLockApplied = true;
      _locked = true;
    }

    if (enabled && _locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
    }
    return const AppShell();
  }
}
