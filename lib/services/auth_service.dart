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

  /// This build has no usable Firebase app at all -- see
  /// [UnavailableAuthService] -- so no auth operation can ever succeed on
  /// this device, not just this attempt. Distinct from [unknown] (a
  /// transient/unexplained failure that might well succeed on retry) so a
  /// caller can tell "try again" apart from "this device can't do this",
  /// without either code being conflated with a genuine wrong-password or
  /// network failure.
  serviceUnavailable,
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

/// Used in place of [FirebaseAuthService] whenever this build has no usable
/// Firebase app -- see `main.dart`'s `initializeFirebase()`, the single place
/// that decides.
///
/// [FirebaseAuthService]'s constructor touches `FirebaseAuth.instance`, which
/// touches `Firebase.app()`, which THROWS with no default app: the entire
/// documented crash this class exists to avoid ever reaching. This class
/// never constructs a `FirebaseAuth`, so it is always safe to build.
///
/// Reports permanently signed out (there is no session to restore without
/// Firebase), and every mutating call fails with
/// [AuthErrorCode.serviceUnavailable] rather than reaching for a client that
/// cannot exist -- `_guard` in `AuthProvider` already turns that into a
/// normal, on-screen message instead of a crash, so no new UI plumbing is
/// needed for it. Deliberately its own code, not [AuthErrorCode.unknown]: a
/// user permanently signed out on this build who taps "Sign in" would
/// otherwise be told to retry an operation that can never succeed on this
/// device, indistinguishable from a genuine transient failure that might.
/// [signOut] is the one exception: it is a no-op rather than a failure,
/// because on a build with no auth at all "sign out" can only ever mean
/// "already signed out".
class UnavailableAuthService implements AuthService {
  const UnavailableAuthService();

  @override
  Stream<AppUser?> authStateChanges() => Stream.value(null);

  @override
  AppUser? get currentUser => null;

  @override
  Future<void> signUp({required String email, required String password}) =>
      _unavailable();

  @override
  Future<void> signIn({required String email, required String password}) =>
      _unavailable();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordReset(String email) => _unavailable();

  @override
  Future<void> deleteAccount() => _unavailable();

  Future<Never> _unavailable() async =>
      throw AuthFailure(AuthErrorCode.serviceUnavailable);
}
