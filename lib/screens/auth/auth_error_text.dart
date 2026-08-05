import '../../services/auth_service.dart';

/// User-facing copy for an auth failure.
///
/// `wrongCredentials` deliberately does NOT distinguish "no such account" from
/// "wrong password" — telling them apart lets anyone test whether an email is
/// registered, which for a menstrual tracker is itself sensitive.
String messageForAuthError(AuthErrorCode code) {
  switch (code) {
    case AuthErrorCode.invalidEmail:
      return 'That email address is not valid.';
    case AuthErrorCode.emailInUse:
      return 'An account already exists for that email.';
    case AuthErrorCode.weakPassword:
      return 'Choose a stronger password.';
    case AuthErrorCode.wrongCredentials:
      return 'Email or password is incorrect.';
    case AuthErrorCode.networkError:
      return 'No connection. Check your network and try again.';
    case AuthErrorCode.requiresRecentLogin:
      return 'Please sign in again to continue.';
    case AuthErrorCode.notSignedIn:
      return "You're not signed in any more. Sign in and try again.";
    case AuthErrorCode.unknown:
      return 'Something went wrong. Please try again.';
  }
}
