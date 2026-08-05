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

  /// The same three-state transition as [foreground], but with NO `pump`
  /// afterwards.
  ///
  /// `SchedulerBinding.handleAppLifecycleStateChanged`
  /// (scheduler/binding.dart:414-428) calls `_setFramesEnabledState(false)`
  /// for `hidden`/`paused`/`detached` and `_setFramesEnabledState(true)` for
  /// `resumed`/`inactive`; the latter, on a true->false->true edge, calls
  /// `scheduleFrame()` (:947), which only sets `_hasScheduledFrame = true` —
  /// it does not draw one. `AutomatedTestWidgetsFlutterBinding.pump` (the
  /// binding `flutter test` uses) only actually runs `handleBeginFrame` /
  /// `handleDrawFrame` — and therefore `AppLock.build` — when `pump` is next
  /// called AND `hasScheduledFrame` is true (flutter_test/binding.dart:1948
  /// -1965). So immediately after this returns, exactly one frame is
  /// scheduled-but-undrawn: the state on screen (and everything `build`
  /// would have written, including the pre-fix `lockNotifier`) is still
  /// whatever the LAST drawn frame left it as. That is the real-device race
  /// this closes: the OS can deliver a back press in that same undrawn-frame
  /// gap, before Flutter has rendered anything reflecting the resume.
  Future<void> foregroundBeforeFirstFrame(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
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

  testWidgets(
      'a back press that lands before the first post-resume frame is still '
      'swallowed — the pushed route survives AFTER unlock',
      (tester) async {
    await seedSettings(appLock: true);
    await launch(tester);
    await unlockWithPin(tester);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Log today'));
    await tester.pumpAndSettle();
    expect(find.byType(DayLogScreen), findsOneWidget);

    await background(tester);
    // Deliberately `foregroundBeforeFirstFrame`, NOT `foreground`: no frame
    // has been drawn since the app paused, so nothing below has rebuilt yet
    // — `find.byType(LockScreen)` would find nothing here, not because the
    // lock failed to engage, but because the tree hasn't caught up. That is
    // exactly the window under test, so there is deliberately no "is the
    // lock visible yet" sanity check here the way the sibling test has one.
    await foregroundBeforeFirstFrame(tester);

    // The Android back button, landing in the undrawn-frame gap.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await unlockWithPin(tester);

    // THE REGRESSION. Pre-fix, `AppLock.lockNotifier` is only written from
    // `build`, which has not run since the app paused — so the guard above
    // `MaterialApp` reads a stale `false`, declines, and `_WidgetsAppState`
    // pops the hidden route instead. The pop is invisible while offstage and
    // only shows up here, after unlock.
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(DayLogScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
