import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/screens/lock/lock_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/claim_preference.dart';
import 'package:menstrul_track/services/lock_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:menstrul_track/widgets/cloud_sync_unavailable_banner.dart';

/// Covers the owner's 2026-08-06 ruling: with no usable Firebase app,
/// `SignInScreen` offers "Continue without syncing" so a missing/failed
/// cloud does not lock anyone out of their own local encrypted data. See
/// `AppGate._localOnly`'s doc comment for the full design.
///
/// Reports signed OUT immediately and never becomes signed in on its own —
/// these tests are about reaching (and staying inside) local-only mode, not
/// about a real sign-in succeeding.
class _FakeSignedOutAuthService implements AuthService {
  @override
  Stream<AppUser?> authStateChanges() => Stream.value(null);
  @override
  AppUser? get currentUser => null;
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

/// Starts signed out but can [emit] a real sign-in later — used by the
/// recovery test, which needs to move from local-only to a genuine account.
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

Future<AppDatabase> _dbPastOnboarding({bool appLock = false}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.getSettings();
  await (db.update(db.appSettings)..where((t) => t.id.equals(0))).write(
    AppSettingsCompanion(
      onboardingComplete: const Value(true),
      appLockEnabled: Value(appLock),
    ),
  );
  return db;
}

/// In-memory stand-in for `ClaimPreference` + `FakeFirebaseFirestore`, so
/// nothing here touches `flutter_secure_storage` (no platform-channel handler
/// under `flutter_tester`) or a real Firebase app.
class _TestSync {
  _TestSync(AppDatabase db) : firestore = FakeFirebaseFirestore() {
    trigger = SyncTrigger(
      db,
      firestore: () => firestore,
      deviceId: () async => 'device-1',
      readClaim: () async => claimStore,
      writeClaim: (record) async => claimStore = record,
    );
  }

  final FakeFirebaseFirestore firestore;
  late final SyncTrigger trigger;
  ClaimRecord? claimStore;
}

void main() {
  const pin = '9137';

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

  final hatch = find.byKey(const Key('signIn.continueWithoutSync'));
  final claimSheet = find.byKey(const Key('claim.upload'));

  testWidgets(
      'PROOF 1: with Firebase available, the hatch is absent and the '
      'unavailable copy never appears', (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: true,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(hatch, findsNothing);
    expect(find.byType(CloudSyncUnavailableBanner), findsNothing);
    expect(find.textContaining("Cloud sync isn't available"), findsNothing);
  });

  testWidgets(
      'with Firebase unavailable, the sign-in screen offers the hatch with '
      'the service-unavailable copy', (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: false,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    expect(hatch, findsOneWidget);
    expect(
      find.textContaining("Cloud sync isn't available on this device right now"),
      findsOneWidget,
    );
  });

  testWidgets(
      'tapping "Continue without syncing" reaches the app shell with no '
      'account, and the persistent banner covers it', (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: false,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    await tester.tap(hatch);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    expect(find.byType(CloudSyncUnavailableBanner), findsOneWidget);

    // Local-only really does mean signed out — nothing synthesized a uid.
    final ctx = tester.element(find.byType(NavigationBar));
    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    expect(auth.user, isNull);
    expect(auth.state, AuthState.signedOut);
  });

  testWidgets(
      'PROOF 6: a brand-new local-only user can still complete onboarding '
      'and reach the shell', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: false,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    await tester.tap(hatch);
    await tester.pumpAndSettle();

    expect(find.text('Welcome to LunaTrack'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CloudSyncUnavailableBanner), findsOneWidget);
  });

  testWidgets(
      'PROOF 2: local-only mode uploads nothing — with pre-existing local '
      'data, no Firestore write happens and the claim prompt never appears',
      (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 2, 1),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: false,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    await tester.tap(hatch);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(claimSheet, findsNothing);

    // Also exercise the app-resume sync hook (`AppGate.didChangeAppLifecycleState`
    // calls `SyncTrigger.syncNow()` on resume) — still nothing to push.
    await background(tester);
    await foreground(tester);

    expect(claimSheet, findsNothing);
    expect(sync.claimStore, isNull);
    final written = await sync.firestore.collection('users').get();
    expect(written.docs, isEmpty,
        reason: 'local-only mode must never contact Firestore');
  });

  testWidgets(
      'PROOF 3: the local-only hatch is covered by the SAME lock as the rest '
      'of the sign-in screen -- not interactable, only mounted, while locked',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await LockService.setPin(pin);

    // App lock predates any account here — it is a device setting, and
    // `AppLock`'s own doc comment is explicit that it "covers the splash and
    // the sign-in screen too", deliberately not waiting for a signed-in user.
    // This hatch lives on that same screen, so it inherits that coverage with
    // no special-casing of its own.
    final db = await _dbPastOnboarding(appLock: true);
    addTearDown(db.close);
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: false,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LockScreen), findsOneWidget);
    // Not merely invisible — genuinely un-hit-testable, so no tap can reach
    // it. `skipOffstage: false` shows it is still mounted underneath (state
    // preservation, not a rebuild), which is what makes the later reveal a
    // restore rather than a fresh screen.
    expect(hatch, findsNothing);
    expect(find.byKey(const Key('signIn.continueWithoutSync'), skipOffstage: false),
        findsOneWidget);

    await unlockWithPin(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(hatch, findsOneWidget);
  });

  testWidgets(
      'PROOF 4: once local-only mode is entered, the shell is protected by '
      'the SAME app-lock mechanism as any signed-in session — hidden behind '
      'the lock on backgrounding, state preserved, nothing decided or pushed',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    await LockService.setPin(pin);

    final db = await _dbPastOnboarding(appLock: true);
    addTearDown(db.close);
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 2, 2),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
    final sync = _TestSync(db);

    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: false,
      authService: _FakeSignedOutAuthService(),
      syncTrigger: sync.trigger,
    ));
    await tester.pumpAndSettle();

    // Reaching the hatch at all requires unlocking first — see PROOF 3 — so
    // this session has already passed the lock once by the time local-only
    // mode is entered, same as any signed-in session reached the same way.
    await unlockWithPin(tester);
    await tester.tap(hatch);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CloudSyncUnavailableBanner), findsOneWidget);

    await background(tester);
    await foreground(tester);

    expect(find.byType(LockScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(CloudSyncUnavailableBanner), findsNothing);
    // Hidden, not lost — mounted underneath, exactly like
    // `test/app_lock_route_coverage_test.dart`'s claim for `AppShell` in
    // general.
    expect(find.byType(NavigationBar, skipOffstage: false), findsOneWidget);
    // Nothing decided or pushed on the user's behalf behind the lock.
    expect(claimSheet, findsNothing);
    expect(sync.claimStore, isNull);
    final beforeUnlock = await sync.firestore.collection('users').get();
    expect(beforeUnlock.docs, isEmpty);

    await unlockWithPin(tester);

    expect(find.byType(LockScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CloudSyncUnavailableBanner), findsOneWidget);
  });

  testWidgets(
      'PROOF 5: data present from a local-only session goes through the '
      'EXISTING claim flow on a later real sign-in, and is not auto-uploaded',
      (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);
    // Stands in for logs written during an earlier local-only session — from
    // the claim flow's point of view this is indistinguishable from any
    // other pre-account local data, which is the whole point: no second
    // consent path was added for it.
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 2, 3),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
    final sync = _TestSync(db);
    final auth = _FakeAuthService();
    addTearDown(auth.dispose);

    // Firebase has recovered by this (later) launch.
    await tester.pumpWidget(LunaTrackApp(
      database: db,
      firebaseAvailable: true,
      authService: auth,
      syncTrigger: sync.trigger,
    ));
    // `_FakeAuthService`'s stream has no initial event until [emit] is
    // called, so `AuthProvider.state` starts (and would stay) `unknown` --
    // `AppGate`'s splash spinner -- without this; `pumpAndSettle` on a
    // perpetually-animating `CircularProgressIndicator` times out rather than
    // failing fast (confirmed while writing this test).
    auth.emit(null);
    await tester.pumpAndSettle();

    // Recovered: no hatch at all, ordinary sign-in wall.
    expect(hatch, findsNothing);

    auth.emit(const AppUser(uid: 'uid-1', email: 'uid-1@example.com'));
    await tester.pumpAndSettle();

    expect(claimSheet, findsOneWidget);
    expect(find.textContaining('days logged on this device'), findsOneWidget);

    // Declining must never upload — the existing guarantee, reused as-is.
    await tester.tap(find.byKey(const Key('claim.keepLocal')));
    await tester.pumpAndSettle();

    expect(sync.claimStore?.uid, 'uid-1');
    expect(sync.claimStore?.declined, isTrue);
    final written = await sync.firestore.collection('users').get();
    expect(written.docs, isEmpty);
  });
}
