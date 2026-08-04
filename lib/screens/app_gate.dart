import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/daily_log_repository.dart';
import '../db/database.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
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
  bool _claimPromptShown = false;

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
    if (_claimPromptShown) return;
    _claimPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final settings = context.read<SettingsProvider>();
      final trigger = context.read<SyncTrigger>();
      // Only ask when there is local data that predates this account.
      if (settings.lastSyncedAt != null) return;
      final count = (await DailyLogRepository(db).getAll()).length;
      if (count == 0 || !context.mounted) return;
      // Scoped to the signed-in account: a decline recorded for a DIFFERENT
      // uid must not suppress this genuinely new question for `uid` — that
      // account has never been offered this device's data. Checked AFTER
      // `count`, not before: this touches `ClaimPreference`'s secure-storage
      // read, and most signed-in rebuilds have nothing to claim at all (a
      // fresh account, or one already synced) — no reason to touch storage
      // on every one of those when a fast, already-in-hand local read already
      // rules the prompt out.
      if (uid != null && await trigger.declinedUidOnRecord() == uid) return;
      if (!context.mounted) return;
      final upload = await showClaimLocalDataSheet(context, dayCount: count);
      if (!context.mounted) return;
      // `resolveClaim` (not a bare `syncNow`) either way: `upload == true`
      // clears SyncTrigger's pending-claim gate and runs the deferred sync;
      // `upload == false` (or a dismissal, though the sheet itself is
      // non-dismissible) persists the decline for this uid and leaves the
      // gate set so nothing pushes this session's declined history later.
      await trigger.resolveClaim(upload: upload == true);
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
