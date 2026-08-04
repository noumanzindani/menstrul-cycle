import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/app_gate.dart';
import 'package:menstrul_track/screens/auth/sign_in_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:menstrul_track/services/sync_trigger.dart';
import 'package:provider/provider.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => null;
  void emit(AppUser? u) => _controller.add(u);
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
  void dispose() => _controller.close();
}

void main() {
  late AppDatabase db;
  late FakeAuthService fake;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fake = FakeAuthService();
  });

  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  Widget wrap() => MultiProvider(
        providers: [
          Provider<AppDatabase>.value(value: db),
          ChangeNotifierProvider(create: (_) => AuthProvider(fake)),
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(SettingsRepository(db))..load(),
          ),
          ChangeNotifierProvider(create: (_) => SyncTrigger(db)),
        ],
        child: const MaterialApp(home: AppGate()),
      );

  testWidgets('shows a splash, not the sign-in form, before auth is known',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows sign-in once the user is known to be signed out',
      (tester) async {
    await tester.pumpWidget(wrap());
    fake.emit(null);
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a signed-in user reaches the normal app chain, not sign-in',
      (tester) async {
    await tester.pumpWidget(wrap());
    fake.emit(const AppUser(uid: 'uid-1', email: 'a@b.com'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsNothing);
  });
}
