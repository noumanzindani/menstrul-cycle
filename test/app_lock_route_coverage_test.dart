import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';
import 'package:menstrul_track/screens/lock/lock_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/lock_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// The app lock has to gate the NAVIGATOR, not the widget tree.
///
/// `LockScreen` used to be returned from `AppGate.build`, so it replaced the
/// contents of the `home:` route and nothing else. Bottom sheets, dialogs,
/// pushed screens and snackbars are routes on the same root navigator, and a
/// route renders ABOVE whatever `home:` returned — the lock included. So
/// backgrounding the app with something open left that something sitting on top
/// of the lock, fully readable and fully tappable, to whoever picked the phone
/// up. Three rounds of guarding individual `show*` call sites each missed a
/// variant; the fix is `MaterialApp.builder`, which wraps the navigator.
///
/// These tests pump the REAL [LunaTrackApp] rather than a hand-built harness,
/// for one specific reason: the fix lives in `main.dart`'s `builder:` argument,
/// and a harness that built its own `MaterialApp` could pass while the app
/// shipped without it.
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

  /// The persisted claim decision. Stays null unless something WRITES one —
  /// which is how "the locked session decided nothing on the user's behalf" is
  /// asserted.
  ClaimRecord? claimStore;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    claimStore = null;
    // A real keystore for `LockService`: the PIN is genuinely hashed, stored
    // and verified, so every unlock below is a production code path.
    FlutterSecureStorage.setMockInitialValues({});
    await LockService.setPin(pin);
  });

  tearDown(() async {
    await db.close();
  });

  /// Written straight to the table rather than through `SettingsRepository`,
  /// which stamps `settingsUpdatedAt` — and that stamp is one of the things
  /// `SyncTrigger.hasLocalDataToClaim()` keys on, so going through the
  /// repository would raise the claim prompt in the tests that are not about
  /// it.
  Future<void> seedSettings({required bool appLock}) async {
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0))).write(
      AppSettingsCompanion(
        onboardingComplete: const Value(true),
        appLockEnabled: Value(appLock),
      ),
    );
  }

  SyncTrigger buildTrigger() => SyncTrigger(
        db,
        readClaim: () async => claimStore,
        writeClaim: (record) async => claimStore = record,
      );

  Future<SyncTrigger> launch(WidgetTester tester) async {
    final trigger = buildTrigger();
    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        authService: _FakeSignedInAuthService(),
        syncTrigger: trigger,
      ),
    );
    await tester.pumpAndSettle();
    return trigger;
  }

  Future<void> unlockWithPin(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), pin);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
  }

  /// A real backgrounding, and then a real return to the foreground.
  ///
  /// Driven through the FULL state sequence rather than jumping straight to
  /// `paused`/`resumed`: the binding ignores a repeat of the state it is
  /// already in, so a shortcut would silently never reach the lifecycle
  /// observer and every assertion after it would be vacuous.
  ///
  /// The assertions below always run after BOTH, never between them, and that
  /// is not laziness: `SchedulerBinding` disables frames from `hidden` onwards,
  /// so `scheduleFrame` is a no-op and `pumpAndSettle` produces no frame at all
  /// while the app is away. The lock's `setState` lands the moment frames are
  /// re-enabled, i.e. as the app comes back — which is the moment that matters,
  /// because it is the first one a person looking at the screen can see.
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

  final claimSheet = find.byKey(const Key('claim.upload'));
  final disclosure = find.textContaining('days logged on this device');

  /// The same two finders, ignoring the offstage-ness the lock imposes — i.e.
  /// "is this route still MOUNTED?". `findsNothing` above plus `findsOneWidget`
  /// here is the whole claim of this fix: hidden, not lost.
  final claimSheetMounted =
      find.byKey(const Key('claim.upload'), skipOffstage: false);

  testWidgets(
      'the claim sheet is open and the phone is backgrounded: the lock covers '
      'the sheet instead of appearing underneath it', (tester) async {
    await seedSettings(appLock: true);
    // Local data that predates the account — the upgrade the claim prompt
    // exists for, and the data the lock exists to keep private.
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 5),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );

    final trigger = await launch(tester);
    await unlockWithPin(tester);

    // The state a user is ordinarily left in: the sheet is `isDismissible:
    // false` with `PopScope(canPop: false)`, so someone who does not want to
    // answer it cannot clear it — putting the phone down is the way out.
    expect(claimSheet, findsOneWidget);
    expect(disclosure, findsOneWidget);

    await background(tester);
    await foreground(tester);

    // THE REGRESSION. Before the fix all three of these were true with the lock
    // ALSO on screen: the sheet and its disclosure rendered above `LockScreen`,
    // so whoever held the locked phone could read that this device holds N days
    // of menstrual-health logs and tap "Add to my account" to upload them into
    // the signed-in account, with no PIN.
    expect(find.byType(LockScreen), findsOneWidget);
    expect(claimSheet, findsNothing);
    expect(disclosure, findsNothing);
    // Nothing was decided on the user's behalf: no upload, no persisted
    // decline, and the sync gate is still closed.
    expect(claimStore, isNull);
    expect(trigger.isPendingClaim, isTrue);
    // Hidden, not lost — the route is still mounted behind the lock.
    expect(claimSheetMounted, findsOneWidget);

    // And unlocking puts the user back exactly where they were: the same open
    // sheet, still unanswered.
    await unlockWithPin(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(claimSheet, findsOneWidget);
    expect(disclosure, findsOneWidget);
    expect(claimStore, isNull);
    expect(trigger.isPendingClaim, isTrue);
  });

  testWidgets(
      'a screen pushed from AppShell is covered too: backgrounding inside the '
      'day log does not leave it on top of the lock', (tester) async {
    // No claim prompt in this one — it is about the hole that predates the sync
    // work entirely. Every `Navigator.push` from `AppShell` (the day log,
    // medications, reminders, the calendar day sheet) had it.
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
    expect(find.byType(DayLogScreen), findsNothing);
    // The screen's content, not just its type: a day log is a menstrual-health
    // logging form, and "Flow" on screen already says what this app is.
    expect(find.text('Flow'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    // Mounted behind the lock, so it can be restored.
    expect(find.byType(DayLogScreen, skipOffstage: false), findsOneWidget);

    await unlockWithPin(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(DayLogScreen), findsOneWidget);
  });

  testWidgets(
      'biometric unlock restores the same open route as the PIN does',
      (tester) async {
    const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');
    var biometricsSucceed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
          return true;
        case 'getAvailableBiometrics':
          return <String>['fingerprint'];
        case 'authenticate':
          return biometricsSucceed;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null));

    await seedSettings(appLock: true);
    await launch(tester);
    // The cold-start lock: biometrics are offered from `LockScreen.initState`
    // and refused, so the PIN is what gets in.
    await unlockWithPin(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Log today'));
    await tester.pumpAndSettle();
    expect(find.byType(DayLogScreen), findsOneWidget);

    // The lock comes up on resume with the fingerprint still being refused, so
    // the pushed screen is genuinely hidden before anything unlocks it.
    await background(tester);
    await foreground(tester);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(DayLogScreen), findsNothing);

    // Now the fingerprint is accepted. Both unlock paths land on the same
    // `setState`, and both must restore rather than reset.
    biometricsSucceed = true;
    await tester.tap(find.widgetWithText(TextButton, 'Use biometrics'));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(DayLogScreen), findsOneWidget);
  });

  testWidgets('app lock off leaves every route exactly as it was',
      (tester) async {
    await seedSettings(appLock: false);

    await launch(tester);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Log today'));
    await tester.pumpAndSettle();

    await background(tester);
    await foreground(tester);

    // No lock was asked for, so nothing is hidden and nothing is covered.
    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(DayLogScreen), findsOneWidget);
  });
}
