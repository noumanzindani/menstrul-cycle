import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// App-lock: a salted-SHA-256 PIN stored in the OS keystore, plus optional
/// biometric unlock. The PIN itself is never stored in plaintext.
class LockService {
  const LockService._();

  static const _storage = FlutterSecureStorage();
  static const _pinKey = 'app_pin_hash_v1';
  static const _saltKey = 'app_pin_salt_v1';
  static final _auth = LocalAuthentication();

  static Future<bool> hasPin() async =>
      (await _storage.read(key: _pinKey)) != null;

  static Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _pinKey, value: _hash(pin, salt));
  }

  static Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final stored = await _storage.read(key: _pinKey);
    if (salt == null || stored == null) return false;
    return _hash(pin, salt) == stored;
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinKey);
    await _storage.delete(key: _saltKey);
  }

  static Future<bool> canUseBiometrics() async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock LunaTrack',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  static String _randomSalt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  }
}
