import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/app_gate.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:provider/provider.dart';

/// Reports an already-signed-in user immediately, like
/// `widget_test.dart`'s `_FakeSignedInAuthService`, so `AppGate` reaches the
/// signed-in branch (and therefore `_maybePromptClaim`) without needing a
/// separate `emit()` step.
class _FakeSignedInAuthService implements AuthService {
  _FakeSignedInAuthService(this._user);
  final AppUser _user;

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
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Local data that predates any account -- the exact upgrade scenario the
    // claim prompt exists for.
    await DailyLogRepository(db).upsert(
      date: DateTime(2026, 1, 5),
      flow: FlowIntensity.medium,
      symptomsJson: '{}',
    );
  });

  tearDown(() => db.close());

  Widget wrap({
    required AppUser user,
    required Future<String?> Function() readDeclinedUid,
  }) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>.value(value: db),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(_FakeSignedInAuthService(user)),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(SettingsRepository(db))..load(),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncTrigger(
            db,
            readDeclinedUid: readDeclinedUid,
            writeDeclinedUid: (_) async {},
            clearDeclinedUid: () async {},
          ),
        ),
      ],
      child: const MaterialApp(home: AppGate()),
    );
  }

  testWidgets('shows the prompt when this uid has never been asked',
      (tester) async {
    await tester.pumpWidget(wrap(
      user: const AppUser(uid: 'uid-1', email: 'a@b.com'),
      readDeclinedUid: () async => null,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('claim.upload')), findsOneWidget);
  });

  testWidgets(
      'does NOT re-show the prompt once this uid is on record as declined '
      '(persists across a simulated relaunch)', (tester) async {
    await tester.pumpWidget(wrap(
      user: const AppUser(uid: 'uid-1', email: 'a@b.com'),
      readDeclinedUid: () async => 'uid-1',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('claim.upload')), findsNothing);
  });

  testWidgets(
      'DOES re-show the prompt for a different uid even though another uid '
      'declined -- that account has never been asked', (tester) async {
    await tester.pumpWidget(wrap(
      user: const AppUser(uid: 'uid-2', email: 'c@d.com'),
      readDeclinedUid: () async => 'uid-1',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('claim.upload')), findsOneWidget);
  });
}
