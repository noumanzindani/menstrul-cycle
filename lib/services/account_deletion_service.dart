import 'package:cloud_firestore/cloud_firestore.dart';

/// Deletes a user's server-side data.
///
/// Firestore does NOT delete subcollections when a parent document is deleted,
/// so removing `users/{uid}` alone leaves the health data orphaned and
/// unreachable — a Google Play User Data policy violation as well as a genuine
/// privacy failure. Every known subcollection is deleted explicitly.
///
/// The order matters: subcollections first, root document last. A crash
/// mid-delete therefore leaves the root document present, so re-running finds
/// and finishes the job. Running it twice is safe.
class AccountDeletionService {
  AccountDeletionService({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String uid;

  /// Every subcollection under `users/{uid}`. Adding a new one to the sync
  /// model REQUIRES adding it here, or deletion silently leaves data behind.
  ///
  /// - `dailyLogs`, `settings` — the health/preference data itself.
  /// - `deletions` (`SyncService._remoteDeletions`) — cross-device deletion
  ///   markers keyed by the date the user logged. Each marker's document id
  ///   IS a date the user tracked, so leaving these behind after "delete my
  ///   account" is a server-side record of which days the user tracked
  ///   surviving an explicit request to erase everything — the exact thing
  ///   this feature exists to prevent.
  /// - `devices` (`SyncService._deviceDoc`) — per-device pull cursors. No
  ///   health data, but a permanent server-side roster of every device that
  ///   ever signed into the account; nothing else prunes it, so it belongs to
  ///   the erasure sweep.
  ///
  /// Public (not `_`-prefixed) so tests can enumerate this list directly
  /// rather than hand-duplicating it — a duplicated literal in a test is
  /// exactly the kind of copy that silently drifts out of sync with this one.
  static const subcollections = ['dailyLogs', 'settings', 'deletions', 'devices'];

  Future<void> deleteFirestoreData() async {
    for (final name in subcollections) {
      // Page through in batches: a long-running user could have thousands of
      // days, and a single unbounded read can exhaust memory.
      while (true) {
        final batch = await firestore
            .collection('users/$uid/$name')
            .limit(300)
            .get();
        if (batch.docs.isEmpty) break;
        final writes = firestore.batch();
        for (final doc in batch.docs) {
          writes.delete(doc.reference);
        }
        await writes.commit();
      }
    }
    await firestore.doc('users/$uid').delete();
  }
}
