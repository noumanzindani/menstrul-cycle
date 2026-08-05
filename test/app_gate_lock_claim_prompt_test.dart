import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/app_gate.dart';
import 'package:menstrul_track/screens/lock/lock_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/lock_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// The claim prompt ("You have N days logged — add them to your account?") is a
/// Navigator ROUTE, pushed from a post-frame callback. A route renders above
/// whatever `AppGate.build` returned, `LockScreen` included — so while the
/// prompt was registered at the top of `build`, it appeared over the lock, and
/// handed whoever held the locked phone, with no PIN: the disclosure that this
/// device holds N days of menstrual-health logs, and a one-tap "Add to my
/// account" that uploads them into the signed-in account.
///
/// App lock is an explicit privacy feature of this app. Anything that renders
/// above it defeats it.
///
/// Every unlock here is a REAL one. `FlutterSecureStorage.setMockInitialValues`
/// (the package's own testing hook) gives `LockService` a working keystore, so
/// the PIN is genuinely hashed, stored and verified; the biometric case drives
/// `local_auth`'s platform channel. Without that the suite's only "app lock
/// enabled" coverage renders `LockScreen` merely because `canUseBiometrics()`
/// swallows the missing plugin, and no test can express "…and then the user
/// unlocks", which is exactly the half of this fix that must not silently drop
/// the question.
/// A [SettingsProvider] whose one load is held open by [gate].
///
/// Not a contrivance, and the reason one test needs it: on a real device this
/// load is a documents-dir lookup, a keystore read and an encrypted-sqlite open,
/// while the claim prompt's own awaits are three ordinary local queries. So the
/// window where `AppGate` has been asked to render but does not yet KNOW app
/// lock is on is wide, and it is exactly the window in which a prompt scheduled
/// from the top of `build` decides — on a race — whether it lands on top of the
/// lock. An in-memory drift database closes that window in microseconds and
/// hides the bug; this reopens it deterministically.
class _GatedSettingsProvider extends SettingsProvider {
  _GatedSettingsProvider(super.repo, this.gate);

  final Future<void> gate;

  @override
  Future<void> load() async {
    await gate;
    return super.load();
  }
}

class _FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => _user;

  void emit(AppUser? u) {
    _user = u;
    _controller.add(u);
  }

  void dispose() => _controller.close();

  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async => emit(null);
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
}

void main() {
  const pin = '2468';
  const localAuthChannel = MethodChannel('plugins.flutter.io/local_auth');

  late AppDatabase db;
  late _FakeAuthService auth;

  /// The persisted claim decision. Stays null unless something WRITES one —
  /// which is the assertion that a suppressed prompt recorded no decision.
  ClaimRecord? claimStore;

  /// One-shot suspension point for the claim-record read, so a test can hold
  /// the prompt's post-frame callback mid-flight and change the lock state
  /// underneath it. This is the only `await` on that path a test can control.
  Completer<void>? claimReadGate;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    auth = _FakeAuthService();
    claimStore = null;
    claimReadGate = null;
    // A real keystore for `LockService`, so `setPin`/`verifyPin` are the
    // production code paths and a wrong PIN really does fail.
    FlutterSecureStorage.setMockInitialValues({});
    await LockService.setPin(pin);
    // Local data that predates the account — the upgrade scenario the claim
    // prompt exists for, and the data the lock exists to keep private.
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 5),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, null);
    auth.dispose();
    await db.close();
  });

  /// Makes the device report enrolled biometrics, and `authenticate` return
  /// [succeeds]. Unmocked (the default) the channel throws
  /// `MissingPluginException`, which `LockService` swallows — i.e. "no
  /// biometrics", the PIN-only device.
  void mockBiometrics({bool succeeds = true}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localAuthChannel, (call) async {
      switch (call.method) {
        case 'isDeviceSupported':
          return true;
        case 'getAvailableBiometrics':
          return <String>['fingerprint'];
        case 'authenticate':
          return succeeds;
      }
      return null;
    });
  }

  Future<void> enableAppLock() => SettingsRepository(db)
      .update(const AppSettingsCompanion(appLockEnabled: Value(true)));

  SyncTrigger buildTrigger() => SyncTrigger(
        db,
        readClaim: () async {
          final gate = claimReadGate;
          if (gate != null) {
            claimReadGate = null;
            await gate.future;
          }
          return claimStore;
        },
        writeClaim: (record) async => claimStore = record,
      );

  /// Mirrors `main.dart`: the trigger is told who is signed in ABOVE `AppGate`.
  Widget wrap(SyncTrigger trigger, {Future<void>? settingsGate}) => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider(create: (_) => AuthProvider(auth)),
          // `lazy: false` for the discrimination reason
          // `claim_prompt_persistence_test.dart` documents at length: a lazy
          // SettingsProvider is not created until `build` reaches its `watch`,
          // so `appLockEnabled` would still be its default when the post-frame
          // callbacks are scheduled and no lock-keyed gate could be exercised.
          ChangeNotifierProvider<SettingsProvider>(
            lazy: false,
            create: (_) => (settingsGate == null
                ? SettingsProvider(SettingsRepository(db))
                : _GatedSettingsProvider(SettingsRepository(db), settingsGate))
              ..load(),
          ),
          ChangeNotifierProvider<SyncTrigger>.value(value: trigger),
        ],
        child: MaterialApp(
          home: Consumer<AuthProvider>(
            builder: (context, a, _) {
              context.read<SyncTrigger>().setUser(a.user?.uid);
              return AppGate(pendingDeletion: (_) async => null);
            },
          ),
        ),
      );

  Future<SyncTrigger> signIn(WidgetTester tester) async {
    final trigger = buildTrigger();
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(trigger));
    auth.emit(const AppUser(uid: 'uid-1', email: 'uid-1@example.com'));
    await tester.pumpAndSettle();
    return trigger;
  }

  Future<void> unlockWithPin(WidgetTester tester, {String entered = pin}) async {
    await tester.enterText(find.byType(TextField), entered);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
  }

  /// A real backgrounding, and then a real return to the foreground.
  ///
  /// Driven through the FULL state sequence rather than jumping straight to
  /// `paused`/`resumed`: `AppLifecycleListener` asserts on invalid transitions,
  /// and the binding ignores a repeat of the state it is already in — so a
  /// shortcut here would silently never reach `AppGate`'s observer, and every
  /// assertion after it would be vacuous. Each helper ends on a state the next
  /// one can legally leave.
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

  testWidgets(
      'a locked device is not told what it holds: the claim prompt does not '
      'render over the lock screen', (tester) async {
    await enableAppLock();

    final trigger = await signIn(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(claimSheet, findsNothing);
    // The disclosure itself, not just the button: "this device has N days of
    // menstrual-health logs on it" is the leak, before any tap.
    expect(disclosure, findsNothing);
    // And nothing was decided on the user's behalf — the gate stays closed and
    // no decline was persisted.
    expect(claimStore, isNull);
    expect(trigger.isPendingClaim, isTrue);
  });

  testWidgets(
      'the question is deferred, not dropped: unlocking with the PIN raises it',
      (tester) async {
    await enableAppLock();
    await signIn(tester);
    expect(claimSheet, findsNothing);

    await unlockWithPin(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(claimSheet, findsOneWidget);
    expect(disclosure, findsOneWidget);
  });

  testWidgets('a WRONG PIN unlocks nothing and raises nothing',
      (tester) async {
    await enableAppLock();
    await signIn(tester);

    await unlockWithPin(tester, entered: '0000');

    expect(find.text('Incorrect PIN'), findsOneWidget);
    expect(find.byType(LockScreen), findsOneWidget);
    expect(claimSheet, findsNothing);
  });

  testWidgets('biometric unlock raises it too — the same deferred question',
      (tester) async {
    mockBiometrics();
    await enableAppLock();

    // `LockScreen` prompts for biometrics from `initState`, so signing in and
    // settling is the whole unlock.
    await signIn(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(claimSheet, findsOneWidget);
  });

  testWidgets(
      'a failed biometric attempt leaves the lock up and the question '
      'unasked', (tester) async {
    mockBiometrics(succeeds: false);
    await enableAppLock();

    await signIn(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(claimSheet, findsNothing);
  });

  testWidgets(
      'backgrounding a locked session without ever unlocking raises nothing '
      'and records nothing', (tester) async {
    await enableAppLock();
    final trigger = await signIn(tester);

    await background(tester);
    await foreground(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(claimSheet, findsNothing);
    expect(claimStore, isNull);
    expect(trigger.isPendingClaim, isTrue);
  });

  testWidgets(
      'the lock engaging mid-flight is caught: a prompt scheduled while '
      'unlocked cannot land on top of a lock that arrived during its awaits',
      (tester) async {
    await enableAppLock();
    await signIn(tester);

    // Hold the prompt's callback at its claim-record read, then unlock. The
    // callback is now scheduled and suspended, with no lock in the way.
    final gate = Completer<void>();
    claimReadGate = gate;
    await unlockWithPin(tester);
    expect(find.byType(LockScreen), findsNothing);
    expect(claimSheet, findsNothing, reason: 'still suspended at the read');

    // The phone goes into a pocket and comes back out. `build` re-renders the
    // lock, but `build` cannot stop a route the suspended callback is about to
    // push.
    await background(tester);
    await foreground(tester);
    expect(find.byType(LockScreen), findsOneWidget);

    // The read lands NOW, with the lock already up.
    gate.complete();
    await tester.pumpAndSettle();

    expect(claimSheet, findsNothing);
    expect(disclosure, findsNothing);
    expect(claimStore, isNull);

    // Still not dropped: unlocking again asks.
    await unlockWithPin(tester);
    expect(claimSheet, findsOneWidget);
  });

  testWidgets(
      'a prompt raised before the lock state is even KNOWN must not beat the '
      'lock to the screen', (tester) async {
    await enableAppLock();
    final settingsGate = Completer<void>();
    final trigger = buildTrigger();
    addTearDown(trigger.dispose);
    await tester.pumpWidget(wrap(trigger, settingsGate: settingsGate.future));
    auth.emit(const AppUser(uid: 'uid-1', email: 'uid-1@example.com'));
    // Pumped rather than settled: the splash is a `CircularProgressIndicator`,
    // which never settles. Ten frames is far more than the prompt's three local
    // queries need to complete and push their route.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // Signed in, settings still loading: `AppGate` is showing its splash and
    // does not yet know app lock is on. Nothing may be raised from here — the
    // answer to "is this device locked?" is not in yet, and a prompt that asks
    // anyway is deciding the question by a race.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(claimSheet, findsNothing);
    expect(disclosure, findsNothing);

    settingsGate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsOneWidget);
    expect(claimSheet, findsNothing);
    expect(disclosure, findsNothing);

    // And, again, deferred rather than dropped.
    await unlockWithPin(tester);
    expect(claimSheet, findsOneWidget);
  });

  testWidgets(
      'app lock disabled — today\'s common case — is completely unaffected',
      (tester) async {
    await signIn(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(claimSheet, findsOneWidget);
    expect(disclosure, findsOneWidget);
  });
}
