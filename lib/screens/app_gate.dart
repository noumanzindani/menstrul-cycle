import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'app_shell.dart';
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
