import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/screens/lock/lock_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/lock_service.dart';

/// `MaterialApp` installs a single app-wide `ScaffoldMessenger` AROUND the
/// output of `builder:`, so it sits ABOVE `AppLock` (see `app_lock.dart`).
/// `LockScreen` is a `Scaffold` with no ancestor `ScaffoldState` of its own, so
/// it registers as a ROOT scaffold with that SAME messenger and immediately
/// paints whatever snackbar is pending — including one raised by, or still
/// live from, a screen that is now hidden behind the lock. The action on that
/// snackbar is real: `account_section.dart`'s deletion-retry action erases the
/// device, clears the PIN and signs out, with no PIN required to press it.
///
/// These tests pump the REAL [LunaTrackApp], for the same reason
/// `app_lock_route_coverage_test.dart` does: the fix has to live where the app
/// actually wires the lock (`main.dart`'s `builder:`), and a hand-built harness
/// could pass while the shipped app does not.
class _FakeSignedInAuthService implements AuthService {
  static const _user = AppUser(uid: 'test-uid', email: 'test@example.com');

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(_user);
  @override
  AppUser? get currentUser => _user;
  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
}

void main() {
  const pin = '1379';

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    FlutterSecureStorage.setMockInitialValues({});
    await LockService.setPin(pin);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedSettings({required bool appLock}) async {
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0))).write(
      AppSettingsCompanion(
        onboardingComplete: const Value(true),
        appLockEnabled: Value(appLock),
      ),
    );
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      LunaTrackApp(database: db, authService: _FakeSignedInAuthService()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unlockWithPin(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), pin);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
  }

  // Same full-lifecycle-sequence helpers as `app_lock_route_coverage_test.dart`
  // — jumping straight to paused/resumed is a no-op if the binding is already
  // there, which would make every assertion below vacuous.
  Future<void> background(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  const liveText = 'Imported 12 temperature readings';
  const raisedText = 'Cloud sync is on — your logs are backed up.';

  testWidgets(
      'a snackbar already live when the lock engages does not render on the '
      'lock screen', (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    await unlockWithPin(tester);

    final messenger =
        ScaffoldMessenger.of(tester.element(find.byType(NavigationBar)));
    messenger.showSnackBar(const SnackBar(content: Text(liveText)));
    await tester.pump();
    // Sanity: unlocked, it really is on screen.
    expect(find.text(liveText), findsOneWidget);

    await background(tester);
    await foreground(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    // THE REGRESSION. Before the fix this text — the count of health-import
    // readings pulled from `settings_screen.dart` — renders on top of the lock
    // with no PIN.
    expect(find.text(liveText), findsNothing);
  });

  testWidgets(
      'a snackbar raised entirely while the app is locked does not render on '
      'the lock screen', (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    await unlockWithPin(tester);

    // Captured before locking, fired after — mirrors the real shape of
    // `account_section._enableSync`, which captures `ScaffoldMessenger.of`
    // before its `await`s and shows the result after they resolve, with no
    // guarantee the phone is still unlocked when that happens.
    final messenger =
        ScaffoldMessenger.of(tester.element(find.byType(NavigationBar)));

    await background(tester);
    await foreground(tester);
    expect(find.byType(LockScreen), findsOneWidget);

    messenger.showSnackBar(const SnackBar(content: Text(raisedText)));
    await tester.pump();

    // THE REGRESSION. Before the fix this "cloud sync is on" disclosure —
    // proof an account is signed in and syncing — renders on top of the lock
    // with no PIN.
    expect(find.text(raisedText), findsNothing);
  });

  testWidgets(
      'a destructive SnackBarAction does not render, and does not fire, '
      'through the lock', (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    await unlockWithPin(tester);

    var actionFired = false;
    final messenger =
        ScaffoldMessenger.of(tester.element(find.byType(NavigationBar)));
    // Mirrors `account_section._showError`'s 8-second "Retry" action, whose
    // real `onPressed` re-runs `_requestDeletion`: write the deletion marker,
    // wipe all local data, clear the PIN, cancel notifications, sign out.
    messenger.showSnackBar(SnackBar(
      content: const Text('Deletion requested. This device is erased.'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Retry',
        onPressed: () => actionFired = true,
      ),
    ));
    await tester.pump();
    // Sanity: unlocked, the action really is there and tappable.
    expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);

    await background(tester);
    await foreground(tester);
    expect(find.byType(LockScreen), findsOneWidget);

    // THE REGRESSION. Before the fix this button is hit-testable and its
    // `onPressed` genuinely fires with no PIN.
    final retry = find.widgetWithText(SnackBarAction, 'Retry');
    expect(retry, findsNothing);
    if (retry.evaluate().isNotEmpty) {
      await tester.tap(retry);
      await tester.pump();
    }
    expect(actionFired, isFalse);
  });
}
