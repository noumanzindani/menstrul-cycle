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

/// `WidgetsBinding.handlePopRoute` consults its observers in REGISTRATION
/// order (not newest-first — see the doc comment at
/// `widgets/binding.dart:949`) and stops at the first one that returns `true`.
/// `_WidgetsAppState` registers itself in `initState`, which runs before any
/// widget below `MaterialApp` — `AppLock` included — ever mounts. So a
/// `didPopRoute` override living on `AppLock` is never consulted while there
/// is a route to pop: `_WidgetsAppState`'s own `didPopRoute` (which calls
/// `navigator.maybePop()`) wins first and pops the hidden route stack behind
/// the lock. The pop is only DEFERRED by the muted `TickerMode` — it completes
/// silently the moment the lock lifts.
///
/// These tests pump the REAL [LunaTrackApp] for the same reason
/// `app_lock_route_coverage_test.dart` does: the fix has to live in
/// `main.dart`, where the app actually installs an observer above
/// `MaterialApp`.
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

  testWidgets(
      'the Android back button does not pop a route hidden behind the lock — '
      'the route survives AFTER unlock, not just while still hidden',
      (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    await unlockWithPin(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Log today'));
    await tester.pumpAndSettle();
    expect(find.byType(DayLogScreen), findsOneWidget);

    await background(tester);
    await foreground(tester);
    expect(find.byType(LockScreen), findsOneWidget);

    // The Android back button, while locked.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Deliberately NOT the real assertion — this alone is the false negative
    // the reviewer already hit once: it passes even with a broken guard,
    // because a pop that reaches the hidden Navigator is only DEFERRED by the
    // muted TickerMode, not blocked, and completes invisibly the instant the
    // lock lifts.
    expect(find.byType(LockScreen), findsOneWidget);

    await unlockWithPin(tester);

    // THE REGRESSION, asserted where it actually shows: after unlock, the
    // pushed route must still be there. If the guard didn't run, the back
    // press already popped it while hidden, and this is `NavigationBar`
    // instead.
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(DayLogScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
