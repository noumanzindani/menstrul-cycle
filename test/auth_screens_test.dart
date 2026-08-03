import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/screens/auth/sign_in_screen.dart';
import 'package:menstrul_track/screens/auth/sign_up_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:provider/provider.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AuthFailure? nextFailure;
  String? lastEmail;
  String? lastPassword;
  int signInCalls = 0;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => null;
  @override
  Future<void> signUp({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {
    lastEmail = email;
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> deleteAccount() async {}
  void dispose() => _controller.close();
}

Widget _wrap(Widget child, FakeAuthService fake) {
  return ChangeNotifierProvider(
    create: (_) => AuthProvider(fake),
    child: MaterialApp(home: child),
  );
}

void main() {
  late FakeAuthService fake;

  setUp(() => fake = FakeAuthService());
  tearDown(() => fake.dispose());

  testWidgets('sign-in submits the entered credentials', (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));

    await tester.enterText(find.byKey(const Key('signIn.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signIn.password')), 'secret123');
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(fake.lastEmail, 'a@b.com');
    expect(fake.lastPassword, 'secret123');
  });

  testWidgets('sign-in blocks an empty email without calling the service',
      (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));

    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(fake.signInCalls, 0);
    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('a wrong-credentials failure is shown to the user',
      (tester) async {
    fake.nextFailure = AuthFailure(AuthErrorCode.wrongCredentials);
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));

    await tester.enterText(find.byKey(const Key('signIn.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signIn.password')), 'nope1234');
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('sign-up rejects a password shorter than 8 characters',
      (tester) async {
    await tester.pumpWidget(_wrap(const SignUpScreen(), fake));

    await tester.enterText(find.byKey(const Key('signUp.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signUp.password')), 'short');
    await tester.enterText(find.byKey(const Key('signUp.confirm')), 'short');
    await tester.tap(find.byKey(const Key('signUp.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(fake.lastPassword, isNull);
  });

  testWidgets('sign-up rejects mismatched confirmation', (tester) async {
    await tester.pumpWidget(_wrap(const SignUpScreen(), fake));

    await tester.enterText(find.byKey(const Key('signUp.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signUp.password')), 'secret123');
    await tester.enterText(find.byKey(const Key('signUp.confirm')), 'secret124');
    await tester.tap(find.byKey(const Key('signUp.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(fake.lastPassword, isNull);
  });
}
