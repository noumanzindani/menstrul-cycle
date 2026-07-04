import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Whether the database file is encrypted at rest with a random 256-bit key
/// held in the OS keystore.
///
/// Encryption uses the "SQLite Multiple Ciphers" build of sqlite3, selected via
/// a build hook in pubspec.yaml:
///
/// ```yaml
/// hooks:
///   user_defines:
///     sqlite3:
///       source: sqlite3mc   # (or: sqlcipher)
/// ```
///
/// To turn encryption ON:
///   1. Add the block above to pubspec.yaml.
///   2. Set this flag to `true`.
///   3. Build & run on a REAL device (`flutter run`) and confirm the DB opens.
///      The native cipher build only compiles during an on-device/host build,
///      so it must be verified there — not via `flutter analyze` alone.
///
/// While `false`, the DB is plaintext but still lives in the app-private
/// sandbox directory (not readable by other apps on a non-rooted device).
const bool kDatabaseEncryptionEnabled = false;

// v10+ encrypts secure storage automatically; no Android options needed.
const _secureStorage = FlutterSecureStorage();
const _dbKeyName = 'lunatrack_db_key_v1';
const _dbFileName = 'lunatrack.db';

/// Fetches the DB passphrase from secure storage, generating it once on first
/// launch. SQLCipher/sqlite3mc derives the actual key from this via PBKDF2.
Future<String> _getOrCreateDbKey() async {
  var key = await _secureStorage.read(key: _dbKeyName);
  if (key == null || key.isEmpty) {
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    key = base64Url.encode(bytes); // url-safe: no quotes to escape in PRAGMA
    await _secureStorage.write(key: _dbKeyName, value: key);
  }
  return key;
}

/// Opens the on-device database. This is the ONE place DB provisioning lives —
/// swapping to encryption or a different backend is a change here only.
QueryExecutor openDatabaseConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, _dbFileName));

    String? key;
    if (kDatabaseEncryptionEnabled) {
      key = await _getOrCreateDbKey();
    }

    return NativeDatabase(
      file,
      setup: (rawDb) {
        if (kDatabaseEncryptionEnabled && key != null) {
          // Must run before any other statement to unlock the database.
          rawDb.execute("PRAGMA key = '$key';");
        }
        rawDb.execute('PRAGMA foreign_keys = ON;');
      },
    );
  });
}
