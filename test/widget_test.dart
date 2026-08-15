import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

/// A fake that reports an already-signed-in user immediately. These tests
/// pump the real [LunaTrackApp] (not just [AppGate]), so the default
/// [FirebaseAuthService] would touch `FirebaseAuth.instance` with no Firebase
/// app initialized. Signed-in-from-the-start lets these tests keep exercising
/// onboarding/home without also standing up sign-in.
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

/// The default [SyncTrigger] persists the claim decision through
/// `flutter_secure_storage`, whose platform channel has no handler under
/// `flutter_tester` (on this host it hangs rather than throwing). Injecting
/// the storage is what keeps that off this path — NOT the fact that these
/// tests happen to seed no local logs.
SyncTrigger _testSyncTrigger(AppDatabase db) => SyncTrigger(
      db,
      readClaim: () async => null,
      writeClaim: (_) async {},
    );

void main() {
  testWidgets('First run shows onboarding', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        authService: _FakeSignedInAuthService(),
        syncTrigger: _testSyncTrigger(db),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome to LunaTrack'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // Not yet in the main app.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('After onboarding, app boots to Home', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Simulate a returning user who already finished onboarding.
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0)))
        .write(const AppSettingsCompanion(onboardingComplete: Value(true)));

    await tester.pumpWidget(
      LunaTrackApp(
        database: db,
        authService: _FakeSignedInAuthService(),
        syncTrigger: _testSyncTrigger(db),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });
}
