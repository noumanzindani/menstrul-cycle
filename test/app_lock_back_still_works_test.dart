import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';
import 'package:menstrul_track/screens/lock/lock_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/lock_service.dart';

/// The positive complement to `test/app_lock_back_button_test.dart`.
///
/// Every test added for the guard so far asserts that it SWALLOWS the back
/// button. Nothing before this file asserted the opposite — that the guard
/// gets OUT OF THE WAY when there is no lock to protect — so a refactor that
/// made `_LockRouteGuard.didPopRoute` return `true` unconditionally would
/// brick the back button app-wide with every other test in the suite still
/// green (none of them press back while unlocked). These tests close that
/// hole, plus the mirror image of the swallow tests: a locked app at the
/// ROOT route (nothing pushed) must not be closeable via back either.
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

  testWidgets(
      'app lock enabled but currently UNLOCKED, with a route pushed: the '
      'back button pops it normally', (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    await unlockWithPin(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Log today'));
    await tester.pumpAndSettle();
    expect(find.byType(DayLogScreen), findsOneWidget);

    // THE ASSERTION THIS FILE EXISTS FOR: the guard must not be swallowing
    // back presses just because a lock EXISTS somewhere above the tree —
    // only while one is actually up. `handlePopRoute` returning `true` here
    // is `_WidgetsAppState.didPopRoute` (via `Navigator.maybePop()`)
    // reporting that it handled the pop, not the guard declining to.
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();

    expect(find.byType(DayLogScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets(
      'app lock disabled entirely, with a route pushed: the back button '
      'pops it normally', (tester) async {
    await seedSettings(appLock: false);
    await launch(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Log today'));
    await tester.pumpAndSettle();
    expect(find.byType(DayLogScreen), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();

    expect(find.byType(DayLogScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets(
      'a locked app at the ROOT route (nothing pushed) cannot be closed via '
      'the back button', (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    // Still locked: never unlocked. Only the lock screen is on the root
    // route, nothing pushed above it.
    expect(find.byType(LockScreen), findsOneWidget);

    // `WidgetsBinding.handlePopRoute` (widgets/binding.dart:983-991) calls
    // `SystemNavigator.pop()` — a platform-channel call with no mock handler
    // registered in this test — the moment every observer's `didPopRoute`
    // returns `false`. There is no `MissingPluginException` here, which is
    // itself part of the proof: if the guard had failed to swallow this, the
    // call below would have thrown instead of resolving.
    final handled = await tester.binding.handlePopRoute();
    expect(handled, isTrue);
    await tester.pumpAndSettle();

    // Still locked — the press did not fall through to anything that could
    // have unlocked or dismissed it.
    expect(find.byType(LockScreen), findsOneWidget);
  });
}
