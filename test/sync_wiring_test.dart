import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/main.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:provider/provider.dart';

/// Reports an already-signed-in user immediately (mirrors `widget_test.dart`).
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

/// Counts the debounced-sync requests `main.dart`'s write-sync provider makes.
/// Its claim storage is injected because the default is
/// `flutter_secure_storage`, whose platform channel has no handler under
/// `flutter_tester` on this host (it hangs rather than throwing).
class _CountingSyncTrigger extends SyncTrigger {
  _CountingSyncTrigger(super.db)
      : super(readClaim: () async => null, writeClaim: (_) async {});

  int scheduleSyncCalls = 0;

  @override
  void scheduleSync() {
    scheduleSyncCalls++;
    super.scheduleSync();
  }
}

void main() {
  testWidgets('local writes actually reach SyncTrigger.scheduleSync '
      '(the write-sync provider is not lazy)', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.getSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(0)))
        .write(const AppSettingsCompanion(onboardingComplete: Value(true)));

    final trigger = _CountingSyncTrigger(db);
    await tester.pumpWidget(LunaTrackApp(
      database: db,
      authService: _FakeSignedInAuthService(),
      syncTrigger: trigger,
    ));
    await tester.pumpAndSettle();

    // `ProxyProvider2<LogProvider, SyncTrigger, void>` produces a `void`, and
    // nothing anywhere reads a `void` -- so while it was lazy (the default),
    // Provider never called `update` and a local edit never scheduled a sync
    // at all. It only rode along on the next app resume or launch.
    expect(
      trigger.scheduleSyncCalls,
      greaterThan(0),
      reason: 'the write-sync ProxyProvider2 needs lazy: false',
    );

    final before = trigger.scheduleSyncCalls;
    final context = tester.element(find.byType(MaterialApp));
    await Provider.of<LogProvider>(context, listen: false).load();
    await tester.pumpAndSettle();

    expect(
      trigger.scheduleSyncCalls,
      greaterThan(before),
      reason: 'a LogProvider change must re-run the write-sync provider',
    );
  });
}
