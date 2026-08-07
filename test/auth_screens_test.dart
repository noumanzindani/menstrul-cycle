import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/screens/auth/forgot_password_screen.dart';
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

  // `SignUpScreen` is PUSHED (`sign_in_screen.dart`), unlike `SignInScreen`,
  // which `AppGate` returns from `build`. That difference is the whole reason
  // these two tests exist: swapping the auth state re-renders what `home:`
  // holds, but has no authority over a route sitting on top of it. So the
  // screen has to get out of the way itself.
  Widget pushedSignUp(FakeAuthService fake) => ChangeNotifierProvider(
        create: (_) => AuthProvider(fake),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
                ),
                // Stands in for the app AppGate renders underneath. Asserting
                // it is visible again is what proves the route actually left,
                // rather than merely that some SignUpScreen finder missed.
                child: const Text('the app below'),
              ),
            ),
          ),
        ),
      );

  Future<void> fillAndSubmitSignUp(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('signUp.email')), 'a@b.com');
    await tester.enterText(
        find.byKey(const Key('signUp.password')), 'secret123');
    await tester.enterText(
        find.byKey(const Key('signUp.confirm')), 'secret123');
    await tester.tap(find.byKey(const Key('signUp.submit')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'REGRESSION: a successful sign-up pops its pushed route so the app is '
      'revealed instead of staying hidden behind the form', (tester) async {
    await tester.pumpWidget(pushedSignUp(fake));
    await tester.tap(find.text('the app below'));
    await tester.pumpAndSettle();
    expect(find.byType(SignUpScreen), findsOneWidget);

    await fillAndSubmitSignUp(tester);

    // The account really was created — otherwise "the form went away" would
    // pass for a sign-up that silently did nothing.
    expect(fake.lastEmail, 'a@b.com');
    expect(find.byType(SignUpScreen), findsNothing);
    expect(find.text('the app below'), findsOneWidget);
  });

  testWidgets(
      'a FAILED sign-up stays put, so the error is not popped away unread',
      (tester) async {
    fake.nextFailure = AuthFailure(AuthErrorCode.emailInUse);
    await tester.pumpWidget(pushedSignUp(fake));
    await tester.tap(find.text('the app below'));
    await tester.pumpAndSettle();

    await fillAndSubmitSignUp(tester);

    expect(find.byType(SignUpScreen), findsOneWidget);
    expect(find.text('An account already exists for that email.'),
        findsOneWidget);
  });

  testWidgets(
      'forgot-password treats wrongCredentials as success so an '
      'unregistered address cannot be distinguished from a registered one',
      (tester) async {
    fake.nextFailure = AuthFailure(AuthErrorCode.wrongCredentials);
    await tester.pumpWidget(_wrap(const ForgotPasswordScreen(), fake));

    await tester.enterText(find.byKey(const Key('forgot.email')), 'a@b.com');
    await tester.tap(find.byKey(const Key('forgot.submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot.sent')), findsOneWidget);
    expect(find.text('Email or password is incorrect.'), findsNothing);
  });

  testWidgets('forgot-password still surfaces a network error',
      (tester) async {
    fake.nextFailure = AuthFailure(AuthErrorCode.networkError);
    await tester.pumpWidget(_wrap(const ForgotPasswordScreen(), fake));

    await tester.enterText(find.byKey(const Key('forgot.email')), 'a@b.com');
    await tester.tap(find.byKey(const Key('forgot.submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forgot.sent')), findsNothing);
    expect(
      find.text('No connection. Check your network and try again.'),
      findsOneWidget,
    );
  });
}
