import 'package:firebase_auth/firebase_auth.dart';

/// The signed-in user, reduced to what the app actually needs. Keeping
/// `firebase_auth` types out of providers and widgets is what lets every screen
/// test run against a fake with no network.
class AppUser {
  const AppUser({required this.uid, this.email});
  final String uid;
  final String? email;
}

/// App-level auth error categories. Firebase's string codes are mapped here so
/// the UI can show a specific message without importing `firebase_auth`.
enum AuthErrorCode {
  invalidEmail,
  emailInUse,
  weakPassword,
  wrongCredentials,
  networkError,
  requiresRecentLogin,
  notSignedIn,
  unknown,
}

class AuthFailure implements Exception {
  AuthFailure(this.code);
  final AuthErrorCode code;

  @override
  String toString() => 'AuthFailure($code)';
}

/// Returns [value], or throws [AuthFailure] when there is no signed-in user.
///
/// Extracted from [FirebaseAuthService.deleteAccount] so the guard itself is
/// testable: constructing a `FirebaseAuth` requires a real Firebase app, and
/// this project has no auth mocking package (adding one needs the owner's
/// sign-off), so the call site cannot be unit-tested — the rule it enforces
/// can.
///
/// The rule matters because the alternative is silent: `currentUser?.delete()`
/// returns normally when `currentUser` is null, so a caller awaiting it is
/// told the account was deleted when nothing happened at all. On this app that
/// reads as "your account is gone" while the account is very much alive.
T requireSignedIn<T>(T? value) {
  if (value == null) throw AuthFailure(AuthErrorCode.notSignedIn);
  return value;
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<void> signUp({required String email, required String password});
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);

  /// Deletes the Firebase Auth user. Callers MUST delete the Firestore subtree
  /// first — deleting the auth user first orphans the health data with no
  /// signed-in identity able to reach it.
  Future<void> deleteAccount();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
      : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  AppUser? _map(User? u) =>
      u == null ? null : AppUser(uid: u.uid, email: u.email);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    await _run(() => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _run(() => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  @override
  Future<void> signOut() => _run(_auth.signOut);

  @override
  Future<void> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> deleteAccount() =>
      _run(() => requireSignedIn(_auth.currentUser).delete());

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_codeFor(e.code));
    }
  }

  AuthErrorCode _codeFor(String code) {
    switch (code) {
      case 'invalid-email':
        return AuthErrorCode.invalidEmail;
      case 'email-already-in-use':
        return AuthErrorCode.emailInUse;
      case 'weak-password':
        return AuthErrorCode.weakPassword;
      // Modern Firebase collapses wrong-password and user-not-found into
      // `invalid-credential` on purpose (it avoids account enumeration). The
      // older codes are kept for older SDK/back-end combinations.
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return AuthErrorCode.wrongCredentials;
      case 'network-request-failed':
        return AuthErrorCode.networkError;
      case 'requires-recent-login':
        return AuthErrorCode.requiresRecentLogin;
      default:
        return AuthErrorCode.unknown;
    }
  }
}
