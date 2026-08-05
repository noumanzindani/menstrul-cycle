import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The claim decision on record for ONE account on this device.
///
/// [declined] false means "this account claimed this device's data and syncs
/// from here"; true means "keep on this device only". The distinction matters
/// because BOTH are answers: a record for the signed-in uid — whichever way it
/// went — is what says "this account has already been asked", and its absence
/// is what makes the prompt appear.
class ClaimRecord {
  const ClaimRecord({required this.uid, required this.declined});

  final String uid;
  final bool declined;

  static const _declinedTag = 'declined';
  static const _uploadedTag = 'uploaded';

  String encode() => '${declined ? _declinedTag : _uploadedTag}:$uid';

  /// Parses [encode]'s output. Anything else — including the pre-fix format
  /// (a bare uid, which only ever meant "declined") — decodes to null, i.e.
  /// "no decision on record", so the user is asked again rather than having a
  /// decision guessed for them. Re-asking is the conservative direction: it
  /// can only ever delay an upload, never cause one.
  static ClaimRecord? decode(String? raw) {
    if (raw == null) return null;
    final separator = raw.indexOf(':');
    if (separator <= 0 || separator == raw.length - 1) return null;
    final tag = raw.substring(0, separator);
    final uid = raw.substring(separator + 1);
    if (tag == _declinedTag) return ClaimRecord(uid: uid, declined: true);
    if (tag == _uploadedTag) return ClaimRecord(uid: uid, declined: false);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ClaimRecord && other.uid == uid && other.declined == declined;

  @override
  int get hashCode => Object.hash(uid, declined);

  @override
  String toString() => 'ClaimRecord(${encode()})';
}

/// Persists the answer to `claim_local_data_sheet.dart`, scoped to the account
/// that gave it.
///
/// Deliberately NOT a drift/`AppSettings` column: this is on-device UI/consent
/// state, not health data, so keeping it out of the encrypted local database
/// avoids a schema migration for a single small value. Uses the same
/// `flutter_secure_storage` backend as `DeviceId`; the app manifest already
/// sets `android:allowBackup="false"` at the whole-app level, so this is
/// excluded from Android auto-backup the same way `DeviceId` is -- a restored
/// backup must not resurrect a stale decision for an account the restore
/// target was never actually asked about.
///
/// This record is the ONLY answer to "has this ACCOUNT ever resolved the claim
/// question on this device". `AppSettings.lastSyncedAt` deliberately is not:
/// it is device-global, so once ANY account synced from this device it stayed
/// non-null forever, and a second account signing in here would have skipped
/// the question entirely and auto-pushed the first account's local history
/// into its own Firestore subtree.
///
/// Only ONE uid's decision is ever on record at a time (a single storage key).
/// That's sufficient because callers always compare the stored uid against the
/// CURRENTLY signed-in uid before treating it as "already answered" -- see
/// [ClaimRecord.decode]'s note on failing toward re-asking.
class ClaimPreference {
  static const _key = 'luna_claim_decision';

  /// The pre-fix key, whose value was a bare "declined" uid. Nothing reads it
  /// any more (the format is not decodable as a [ClaimRecord]); [clear] still
  /// deletes it so a wipe leaves nothing behind.
  static const _legacyKey = 'luna_claim_declined_uid';

  static const _storage = FlutterSecureStorage();

  /// The decision on record for whichever account most recently made one, or
  /// null when no account has answered on this device.
  static Future<ClaimRecord?> read() async =>
      ClaimRecord.decode(await _storage.read(key: _key));

  /// Records [record], replacing any earlier account's decision.
  static Future<void> write(ClaimRecord record) =>
      _storage.write(key: _key, value: record.encode());

  /// Forgets the decision entirely (account deletion; see `AccountSection`).
  static Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _legacyKey);
  }
}
