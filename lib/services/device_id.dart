import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stable per-install identifier, stamped on every synced document.
///
/// Diagnostic only — it never participates in merge decisions, so a
/// regenerated id (e.g. after a reinstall) cannot cause data loss.
class DeviceId {
  static const _key = 'luna_device_id';
  static const _storage = FlutterSecureStorage();

  static Future<String> get() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _key, value: id);
    return id;
  }
}
