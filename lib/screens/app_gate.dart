import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily_log_repository.dart';
import '../db/database.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/claim_preference.dart';
import '../services/sync_trigger.dart';
import 'app_shell.dart';
import 'auth/claim_local_data_sheet.dart';
import 'auth/sign_in_screen.dart';
import 'lock/lock_screen.dart';
import 'onboarding/onboarding_screen.dart';

/// Wraps the app in the lock gate. When app lock is enabled, shows [LockScreen]
/// on cold start and again whenever the app returns from the background.
class AppGate extends StatefulWidget {
  const AppGate({super.key});

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
      return const SignInScreen();
    }
    _maybePromptClaim(context, auth.user?.uid);

    final settings = context.watch<SettingsProvider>();

    // Wait for settings to load to avoid a flash of the wrong screen.
    if (!settings.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
