import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/screens/auth/auth_error_text.dart';
import 'package:menstrul_track/services/auth_service.dart';

/// Covers `AuthErrorCode.serviceUnavailable` -- added because
/// [UnavailableAuthService] previously threw [AuthErrorCode.unknown], which
/// renders as "Something went wrong. Please try again." A user permanently
/// signed out on a build with no usable Firebase app would be told to retry
/// an operation that can never succeed, forever, with no way to tell that
/// apart from a genuine transient failure. `UnavailableAuthService` needs no
/// Firebase app to construct (that is the whole point of the class), so its
/// mutating calls are directly unit-testable with no fake/widget needed.
void main() {
  group('UnavailableAuthService', () {
    const service = UnavailableAuthService();

    test('signUp fails with serviceUnavailable, not unknown', () async {
      await expectLater(
        service.signUp(email: 'a@b.com', password: 'password1'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.code, 'code', AuthErrorCode.serviceUnavailable)),
      );
    });

    test('signIn fails with serviceUnavailable, not unknown', () async {
      await expectLater(
        service.signIn(email: 'a@b.com', password: 'password1'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.code, 'code', AuthErrorCode.serviceUnavailable)),
      );
    });

    test('sendPasswordReset fails with serviceUnavailable', () async {
      await expectLater(
        service.sendPasswordReset('a@b.com'),
        throwsA(isA<AuthFailure>()
            .having((e) => e.code, 'code', AuthErrorCode.serviceUnavailable)),
      );
    });

    test('deleteAccount fails with serviceUnavailable', () async {
      await expectLater(
        service.deleteAccount(),
        throwsA(isA<AuthFailure>()
            .having((e) => e.code, 'code', AuthErrorCode.serviceUnavailable)),
      );
    });

    test('signOut stays a no-op (already signed out)', () async {
      await expectLater(service.signOut(), completes);
    });
  });

  test(
      'messageForAuthError(serviceUnavailable) gives a distinct, non-retry '
      'message', () {
    final message = messageForAuthError(AuthErrorCode.serviceUnavailable);
    expect(message, isNot(messageForAuthError(AuthErrorCode.unknown)));
    expect(message, contains("isn't available on this device"));
  });
}
