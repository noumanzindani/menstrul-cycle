import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the "keep on this device only" decision from
/// `claim_local_data_sheet.dart`, scoped to the account it was made for.
///
/// Deliberately NOT a drift/`AppSettings` column: this is on-device UI/consent
/// state, not health data, so keeping it out of the encrypted local database
/// avoids a schema migration for a single small flag. Uses the same
/// `flutter_secure_storage` backend as `DeviceId`; the app manifest already
/// sets `android:allowBackup="false"` at the whole-app level, so this is
/// excluded from Android auto-backup the same way `DeviceId` is -- a restored
/// backup must not resurrect a stale decline for an account the restore
/// target was never actually asked about.
///
/// Only ONE uid's decline is ever on record at a time (a single storage key).
/// That's sufficient because callers always compare the stored uid against
/// the CURRENTLY signed-in uid before treating it as "already answered" --
/// see `SyncTrigger.declinedUidOnRecord` and its call site in
/// `AppGate._maybePromptClaim`. A decline recorded for uid A and later
/// overwritten by a decline for uid B simply means uid A would be asked again
/// if it ever signs back in, which is the conservative (re-ask rather than
/// silently skip) direction to fail in.
class ClaimPreference {
  static const _key = 'luna_claim_declined_uid';
  static const _storage = FlutterSecureStorage();

  /// The uid that most recently declined to upload local data on this device,
  /// or null if there's no decline on record.
  static Future<String?> declinedUid() => _storage.read(key: _key);

  /// Records that [uid] chose "keep on this device only".
  static Future<void> setDeclined(String uid) =>
      _storage.write(key: _key, value: uid);

  /// Reverses a decline. This is the accessor a future Settings control
  /// (opting back into sync) calls; the UI for that lives in a later task.
  static Future<void> clear() => _storage.delete(key: _key);
}
