import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database.dart';
import '../models/enums.dart';

/// Passphrase-based authenticated encryption for a LunaTrack backup file.
///
/// AES-256-GCM with a PBKDF2-HMAC-SHA256 key. GCM is authenticated, so a wrong
/// passphrase (or any tampering) fails to decrypt instead of returning garbage.
/// Blob layout: salt(16) ‖ nonce(12) ‖ ciphertext(var) ‖ mac(16).
class BackupCrypto {
  const BackupCrypto._();

  static final _aes = AesGcm.with256bits();
  static final _pbkdf2 =
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 120000, bits: 256);
  static final _rnd = Random.secure();

  static const int _saltLen = 16;
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _rnd.nextInt(256));

  static Future<Uint8List> encrypt(String plaintext, String passphrase) async {
    final salt = _randomBytes(_saltLen);
    final key =
        await _pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList(
        [...salt, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<String> decrypt(Uint8List blob, String passphrase) async {
    if (blob.length < _saltLen + _nonceLen + _macLen) {
      throw const FormatException('Backup file is corrupt or incomplete.');
    }
    final salt = blob.sublist(0, _saltLen);
    final nonce = blob.sublist(_saltLen, _saltLen + _nonceLen);
    final mac = blob.sublist(blob.length - _macLen);
    final cipherText = blob.sublist(_saltLen + _nonceLen, blob.length - _macLen);
    final key =
        await _pbkdf2.deriveKeyFromPassword(password: passphrase, nonce: salt);
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    return utf8.decode(clear);
  }
}

/// Exports/imports ALL local data as one encrypted file the user controls.
/// There is no cloud and no server — the file is shared/saved by the user and
/// restored by them. Restore is DESTRUCTIVE (it replaces local data).
class BackupService {
  const BackupService._();

  static const String _magic = 'lunatrack';
  static const int formatVersion = 1;
  static const String fileExtension = 'lunabak';

  // --- pure JSON codec (uses drift's own toJson/fromJson) -------------------

  static String encodeJson({
    required List<DailyLog> logs,
    required List<Reminder> reminders,
    required List<Medication> medications,
    AppSetting? settings,
    DateTime? exportedAt,
  }) =>
      jsonEncode({
        'app': _magic,
        'version': formatVersion,
        if (exportedAt != null) 'exportedAt': exportedAt.toIso8601String(),
        'daily_logs': [for (final l in logs) l.toJson()],
        'reminders': [for (final r in reminders) r.toJson()],
        'medications': [for (final m in medications) m.toJson()],
        if (settings != null) 'settings': settings.toJson(),
      });

  // --- database export / import --------------------------------------------

  static Future<Uint8List> exportEncrypted(
    AppDatabase db,
    String passphrase, {
    DateTime? exportedAt,
  }) async {
    final logs = await db.select(db.dailyLogs).get();
    // The in-progress product-change session is deliberately NOT exported. It
    // is a live "something is in use right now" fact, not a preference: a
    // backup taken mid-session and restored three days later would resurrect it
    // and claim the product had been in for 71 hours.
    final reminders = await (db.select(db.reminders)
          ..where((t) => t.type.equalsValue(ReminderType.productChange).not()))
        .get();
    final medications = await db.select(db.medications).get();
    final settings = await (db.select(db.appSettings)
          ..where((t) => t.id.equals(0)))
        .getSingleOrNull();
    final json = encodeJson(
      logs: logs,
      reminders: reminders,
      medications: medications,
      settings: settings,
      exportedAt: exportedAt ?? DateTime.now(),
    );
    return BackupCrypto.encrypt(json, passphrase);
  }

  /// Decrypts [bytes], validates it, and REPLACES all local data in one
  /// transaction. Throws on a wrong passphrase or a non-LunaTrack file, leaving
  /// the existing data untouched (the decrypt/parse happen before any write).
  static Future<void> importEncrypted(
    AppDatabase db,
    Uint8List bytes,
    String passphrase,
  ) async {
    final json = await BackupCrypto.decrypt(bytes, passphrase);
    final map = jsonDecode(json) as Map<String, dynamic>;
    if (map['app'] != _magic) {
      throw const FormatException('This is not a LunaTrack backup file.');
    }
    final logs = [
      for (final j in (map['daily_logs'] as List))
        DailyLog.fromJson(j as Map<String, dynamic>),
    ];
    final reminders = [
      for (final j in (map['reminders'] as List))
        Reminder.fromJson(j as Map<String, dynamic>),
    ];
    final medications = [
      for (final j in (map['medications'] as List))
        Medication.fromJson(j as Map<String, dynamic>),
    ];
    final settings = map['settings'] == null
        ? null
        : AppSetting.fromJson(map['settings'] as Map<String, dynamic>);

    await db.transaction(() async {
      await db.delete(db.dailyLogs).go();
      await db.delete(db.reminders).go();
      await db.delete(db.medications).go();
      await db.batch((b) {
        b.insertAll(db.dailyLogs, logs);
        b.insertAll(db.reminders, reminders);
        b.insertAll(db.medications, medications);
      });
      if (settings != null) {
        await db.into(db.appSettings).insertOnConflictUpdate(settings);
      }
    });
  }

  // --- file orchestration (platform; not unit-tested) ----------------------

  /// Writes an encrypted backup to a temp file and opens the OS share sheet.
  static Future<void> exportToFile(AppDatabase db, String passphrase) async {
    final bytes = await exportEncrypted(db, passphrase);
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/lunatrack-backup.$fileExtension';
    await File(path).writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: 'LunaTrack backup'),
    );
  }

  /// Lets the user pick a backup file; returns its bytes, or null if cancelled.
  static Future<Uint8List?> pickBackupBytes() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.bytes;
  }
}
