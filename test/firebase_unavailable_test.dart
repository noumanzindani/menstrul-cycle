import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// Covers the physical-device crash reported on DE2118 (Android 12): building
/// [LunaTrackApp] with no usable Firebase app used to construct
/// `AuthProvider(FirebaseAuthService())` directly inside a `create:` callback,
/// which touches `FirebaseAuth.instance` -> `Firebase.app()` and throws
/// `[core/no-app]` DURING BUILD, taking down the entire widget tree (see
/// `test/tmp_repro_test.dart`'s throwaway run, recorded in the task report,
/// for the exact crash this reproduced before the fix).
///
/// The owner's ruling: a missing/failed Firebase app must leave a rendering,
/// sync-disabled app, with a non-silent notice in Settings -> Account. These
/// tests exercise `LunaTrackApp.firebaseAvailable` -- the single value
/// `main()`'s `initializeFirebase()` computes and the ONLY thing that decides
/// this behaviour (see `FirebaseAvailability`'s doc comment) -- rather than
/// re-deriving "is Firebase up" from some second signal that could disagree.
///
/// A fake, already-signed-in [AuthService] is injected here (the same seam
/// `test/widget_test.dart` uses) purely to get PAST `AppGate`'s
/// account-required gate so these tests can reach Settings at all; it is
/// deliberately independent of [LunaTrackApp.firebaseAvailable] -- these tests
/// are about what `AccountSection` shows once Firebase is known to be down,
/// not about how a user actually got signed in on such a device (see the task
/// report for why that combination cannot occur on a real device with today's
/// `AppGate`, and is flagged there rather than fixed here).
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

/// Reports signed OUT immediately -- for proving the ordinary sign-in wall
/// still renders when Firebase is unavailable is irrelevant to it (a fake is
/// used either way; only [LunaTrackApp.firebaseAvailable] changes).
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

/// See `test/widget_test.dart`'s identical helper: the default [SyncTrigger]
/// persists through `flutter_secure_storage`, whose platform channel has no
/// handler under `flutter_tester` (it hangs rather than throwing).
SyncTrigger _testSyncTrigger(AppDatabase db) => SyncTrigger(
      db,
      readClaim: () async => null,
      writeClaim: (_) async {},
    );

Future<AppDatabase> _dbPastOnboarding() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.getSettings();
  await (db.update(db.appSettings)..where((t) => t.id.equals(0)))
      .write(const AppSettingsCompanion(onboardingComplete: Value(true)));
  return db;
}

Future<void> _openSettingsTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  test(
      'initializeFirebase() swallows the real [core/no-app] failure and '
      'reports false instead of throwing -- the single guard main() relies on',
      () async {
    // No Firebase app exists in this process (no widget binding sets one up
    // either) -- exactly the state of a device with no google-services.json /
    // firebase_options.dart, which is this repo at HEAD.
    final available = await initializeFirebase();
    expect(available, isFalse);
  });

  testWidgets(
      'with Firebase unavailable, the real app renders (no crash) and '
      'Settings > Account shows the distinct unavailable notice',
      (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);

    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        firebaseAvailable: false,
        authService: _FakeSignedInAuthService(),
        syncTrigger: _testSyncTrigger(db),
      ),
    );
    await tester.pumpAndSettle();

    // No red error screen, no thrown exception -- the crash this whole task
    // exists to fix.
    expect(tester.takeException(), isNull);
    // The app actually reached the main shell, not stuck on a splash.
    expect(find.byType(NavigationBar), findsOneWidget);

    await _openSettingsTab(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('account.syncUnavailable')), findsOneWidget);
    expect(
      find.textContaining('Cloud sync unavailable on this device'),
      findsOneWidget,
    );
    // Distinct from "off": neither ordinary sync state renders alongside it.
    expect(find.byKey(const Key('account.enableSync')), findsNothing);
    expect(find.byKey(const Key('account.syncStatus')), findsNothing);
  });

  testWidgets(
      'with Firebase available, the normal signed-in sync-off state renders '
      'and the unavailable notice does NOT appear', (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);

    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        firebaseAvailable: true,
        authService: _FakeSignedInAuthService(),
        syncTrigger: _testSyncTrigger(db),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await _openSettingsTab(tester);

    expect(tester.takeException(), isNull);
    // The ordinary "never claimed on this device" off state -- untouched by
    // this task.
    expect(find.byKey(const Key('account.enableSync')), findsOneWidget);
    expect(find.byKey(const Key('account.syncUnavailable')), findsNothing);
  });

  testWidgets(
      'with Firebase available, the normal signed-out sign-in wall still '
      'renders and the unavailable notice does NOT appear (never reachable, '
      'not present)', (tester) async {
    final db = await _dbPastOnboarding();
    addTearDown(db.close);

    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        firebaseAvailable: true,
        authService: _FakeSignedOutAuthService(),
        syncTrigger: _testSyncTrigger(db),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Signed out => AppGate's account-required gate shows sign-in, not the
    // shell -- Settings/AccountSection is not on screen at all.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.byKey(const Key('account.syncUnavailable')), findsNothing);
  });

  testWidgets(
      'with Firebase unavailable and NO injected auth service, the app '
      'still builds -- UnavailableAuthService, not FirebaseAuthService',
      (tester) async {
    // Every other test in this file injects `authService`, which short-
    // circuits `main.dart`'s `authService ?? (firebaseAvailable ?
    // FirebaseAuthService() : UnavailableAuthService())` before the
    // `firebaseAvailable` branch is ever reached. Omitting it here is the
    // only way to actually exercise that ternary: revert it to the pre-fix
    // `authService ?? FirebaseAuthService()` and this constructs a real
    // `FirebaseAuthService`, which touches `FirebaseAuth.instance` ->
    // `Firebase.app()` with no app registered and throws `[core/no-app]`
    // during `create:` -- the exact crash this whole task exists to fix.
    final db = await _dbPastOnboarding();
    addTearDown(db.close);

    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        firebaseAvailable: false,
        syncTrigger: _testSyncTrigger(db),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // UnavailableAuthService reports permanently signed out, so AppGate
    // shows the sign-in wall -- same observable shape as the signed-out
    // case above, but reached via the real, un-injected ternary.
    expect(find.text('Sign in'), findsWidgets);
  });
}
