import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/services/auth_service.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  AuthFailure? nextFailure;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  AppUser? get currentUser => _current;

  void emit(AppUser? user) {
    _current = user;
    _controller.add(user);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    if (nextFailure != null) throw nextFailure!;
    emit(AppUser(uid: 'uid-1', email: email));
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (nextFailure != null) throw nextFailure!;
    emit(AppUser(uid: 'uid-1', email: email));
  }

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<void> sendPasswordReset(String email) async {
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> deleteAccount() async => emit(null);

  void dispose() => _controller.close();
}

void main() {
  late FakeAuthService fake;
  late AuthProvider provider;

  setUp(() {
    fake = FakeAuthService();
    provider = AuthProvider(fake);
  });

  tearDown(() {
    provider.dispose();
    fake.dispose();
  });

  test('starts in unknown so the gate can show a splash, not a flash of login',
      () {
    expect(provider.state, AuthState.unknown);
  });

  test('signing in moves to signedIn and exposes the user', () async {
    await provider.signIn(email: 'a@b.com', password: 'secret123');
    await Future<void>.delayed(Duration.zero);

    expect(provider.state, AuthState.signedIn);
    expect(provider.user?.uid, 'uid-1');
    expect(provider.user?.email, 'a@b.com');
  });

  test('signing out moves to signedOut', () async {
    await provider.signIn(email: 'a@b.com', password: 'secret123');
    await Future<void>.delayed(Duration.zero);

    await provider.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(provider.state, AuthState.signedOut);
    expect(provider.user, isNull);
  });

  test('a failure surfaces as lastError and leaves the user signed out',
      () async {
    fake.nextFailure = AuthFailure(AuthErrorCode.wrongCredentials);

    await provider.signIn(email: 'a@b.com', password: 'nope');

    expect(provider.lastError, AuthErrorCode.wrongCredentials);
    expect(provider.state, AuthState.unknown);
    expect(provider.busy, isFalse);
  });

  test('busy is false again after a failure so the button re-enables',
      () async {
    fake.nextFailure = AuthFailure(AuthErrorCode.networkError);

    await provider.signUp(email: 'a@b.com', password: 'secret123');

    expect(provider.busy, isFalse);
  });

  group('requireSignedIn (the guard FirebaseAuthService.deleteAccount uses)',
      () {
    test('a missing user is a failure, never a silent success', () {
      // `_auth.currentUser?.delete()` returned normally when currentUser was
      // null, so the whole delete pipeline reported success while the account
      // was still alive. Whatever the caller does next -- wipe the device,
      // tell the user "deleted" -- is then a lie.
      expect(
        () => requireSignedIn<Object>(null),
        throwsA(isA<AuthFailure>()
            .having((e) => e.code, 'code', AuthErrorCode.notSignedIn)),
      );
    });

    test('a present user passes straight through', () {
      const user = AppUser(uid: 'uid-1');
      expect(requireSignedIn(user), same(user));
    });
  });
}
