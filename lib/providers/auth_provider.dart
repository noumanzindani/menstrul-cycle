import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

/// `unknown` exists so the gate can show a splash on cold start instead of a
/// flash of the sign-in screen before Firebase restores the session.
enum AuthState { unknown, signedOut, signedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service) {
    _sub = _service.authStateChanges().listen(_onUser);
  }

  final AuthService _service;
  late final StreamSubscription<AppUser?> _sub;

  AuthState _state = AuthState.unknown;
  AppUser? _user;
  bool _busy = false;
  AuthErrorCode? _lastError;

  AuthState get state => _state;
  AppUser? get user => _user;
  bool get busy => _busy;
  AuthErrorCode? get lastError => _lastError;

  void _onUser(AppUser? user) {
    _user = user;
    _state = user == null ? AuthState.signedOut : AuthState.signedIn;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _service.signIn(email: email, password: password));

  Future<void> signUp({required String email, required String password}) =>
      _guard(() => _service.signUp(email: email, password: password));

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _service.sendPasswordReset(email));

  Future<void> signOut() => _guard(_service.signOut);

  /// Runs an action with busy/error bookkeeping. `busy` is always cleared, so a
  /// failed sign-in re-enables the button instead of stranding the user.
  Future<void> _guard(Future<void> Function() action) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
    } on AuthFailure catch (e) {
      _lastError = e.code;
    } catch (_) {
      _lastError = AuthErrorCode.unknown;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
