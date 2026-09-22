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

/// The lock LIFTS with a fade and DROPS instantly.
///
/// Only one of those two is decoration. The other is the security property:
/// a fade-IN on the way down would leave the app readable for the length of
/// the animation at exactly the moment the phone is being backgrounded or
/// handed to someone. Every test below that asserts "full opacity on the
/// first frame" is guarding that, not the look of it.
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

  tearDown(() async => db.close());

  Future<void> launchLocked(WidgetTester tester) async {
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0))).write(
      const AppSettingsCompanion(
        onboardingComplete: Value(true),
        appLockEnabled: Value(true),
      ),
    );
    await tester.pumpWidget(
      LunarFlowApp(database: db, authService: _FakeSignedInAuthService()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsOneWidget);
  }

  /// Enters the PIN and taps Unlock WITHOUT settling, so the caller owns the
  /// frames of the lift.
  Future<void> unlock(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), pin);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
  }

  /// Backgrounds the app AND brings it back, without pumping.
  ///
  /// The round trip is not optional. `SchedulerBinding` disables frames for
  /// `hidden`/`paused`/`detached`, so the `setState` inside `AppLock._lock`
  /// produces no rebuild while the app is away -- see the long comment at that
  /// call site. The lock lands on the FIRST FRAME AFTER RESUME, which is also
  /// the first frame anyone looking at the screen can see, and is therefore
  /// the exact frame these tests need to inspect.
  Future<void> backgroundAndReturn(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  /// The veil's own fade, scoped by the [LockScreen] it wraps.
  double veilOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(find
          .ancestor(
            of: find.byType(LockScreen),
            matching: find.byType(FadeTransition),
          )
          .first)
      .opacity
      .value;

  testWidgets('the veil lifts rather than vanishing', (tester) async {
    await launchLocked(tester);
    expect(veilOpacity(tester), 1.0);

    await unlock(tester);
    await tester.pump();

    // Still mounted, still opaque: the lift has not travelled yet.
    expect(find.byType(LockScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 130));
    final mid = veilOpacity(tester);
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);
  });

  testWidgets('the lock DROPS instantly: opaque on the very first frame',
      (tester) async {
    await launchLocked(tester);
    await unlock(tester);
    await tester.pumpAndSettle();
    expect(find.byType(LockScreen), findsNothing);

    await backgroundAndReturn(tester);
    await tester.pump();

    // THE ASSERTION THIS FILE EXISTS FOR. This is the first frame the returning
    // user sees; anything less than 1.0 here is a window in which the app is
    // readable by whoever is holding the phone.
    expect(find.byType(LockScreen), findsOneWidget);
    expect(veilOpacity(tester), 1.0);
  });

  testWidgets('a lock arriving mid-lift restores full opacity at once',
      (tester) async {
    await launchLocked(tester);
    await unlock(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(veilOpacity(tester), lessThan(1.0));

    // The lift is abandoned, never reversed -- the lock is going up NOW.
    await backgroundAndReturn(tester);
    await tester.pump();
    expect(veilOpacity(tester), 1.0);
    expect(find.byType(LockScreen), findsOneWidget);
  });

  testWidgets('reduced motion unlocks in one frame', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await launchLocked(tester);
    await unlock(tester);
    await tester.pump();
    expect(find.byType(LockScreen), findsNothing);
  });
}
