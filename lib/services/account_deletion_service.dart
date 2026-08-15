import 'package:cloud_firestore/cloud_firestore.dart';

/// A deletion request that is on record for an account but not yet carried out.
///
/// [purgeAfter] is nullable on purpose: the ONLY thing that makes an account
/// deletion-requested is the existence of its marker document. A marker whose
/// deadline is missing or the wrong type (a partial write, a hand-edited
/// console value, a future app version) must still count as pending — the
/// alternative fails open, i.e. resumes syncing menstrual-health data into an
/// account that is queued for erasure. The UI simply loses the exact date.
class DeletionRequest {
  const DeletionRequest({this.requestedAt, this.purgeAfter});

  /// Server-stamped moment the request was made. Null while the client's own
  /// write is still pending (`FieldValue.serverTimestamp()` resolves on the
  /// server), or when the field is missing/malformed.
  final DateTime? requestedAt;

  /// The moment the purge becomes due — the date the user was promised.
  final DateTime? purgeAfter;
}

/// Owns the two halves of "delete my account": the **request** the app makes
/// today, and the **purge** contract a scheduled job will later honour.
///
/// ## Why the request is a soft delete
///
/// Tapping "Request account deletion" erases the device immediately but does
/// NOT touch `users/{uid}`. Instead it records a marker; a scheduled job
/// (not yet written — see the task-11 report) does the irreversible part after
/// the grace window. That is what makes the request cancellable, which in turn
/// is what makes an accidental tap — or a coerced one — survivable on an app
/// whose data is this sensitive.
///
/// ## The marker's shape, and why it is where it is
///
/// One tiny document per requesting account at
/// **`deletionRequests/{uid}`** — a TOP-LEVEL collection, deliberately not a
/// field inside `users/{uid}`:
///
/// - The purge has to enumerate *every expired request in the database*. From
///   a top-level collection that is one indexed query over one small
///   collection (`where('purgeAfter', <=, now)`, automatic single-field
///   index). A flag inside the user subtree would instead require a
///   collection-group scan across health data to find the same accounts.
/// - It holds `uid` + two timestamps and nothing else. No health data ever
///   leaves `users/{uid}`, including into this marker.
/// - Its existence is a single-document read, which is what makes the sync
///   gate in `SyncService.syncNow` affordable.
///
/// `purgeAfter` is stored as an absolute timestamp rather than being derived
/// by the purge from `requestedAt`: the deadline shown to the user is then the
/// deadline the job acts on, even if [graceWindow] is ever changed (already-
/// pending requests keep the window they were promised). It is computed from
/// the client clock, so `firestore.rules` must bound it — see the task-11
/// report's rules section, which Task 12 implements.
class AccountDeletionService {
  AccountDeletionService({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String uid;

  /// How long a deletion request is held before the purge may run.
  ///
  /// THE one definition of the window on the client. The purge job must use
  /// the same number; it is stated in the task-11 report so whoever writes it
  /// does not re-derive it from a literal.
  static const Duration graceWindow = Duration(days: 30);

  /// The top-level collection of pending deletion requests — the purge's work
  /// queue. See the class doc for why it is not nested under `users/{uid}`.
  static const String requestsCollection = 'deletionRequests';

  /// The marker path for [uid]. Exposed so `SyncService` can check for a
  /// pending request without duplicating the literal.
  static String requestPath(String uid) => '$requestsCollection/$uid';

  DocumentReference<Map<String, dynamic>> get _requestDoc =>
      firestore.doc(requestPath(uid));

  /// Records the deletion request. Cloud data is left completely intact.
  ///
  /// **Create-only.** An existing marker is left exactly as it is, and this
  /// returns without writing. Two reasons, and they agree:
  ///
  /// - `firestore.rules` will allow `create` and deny `update` on this
  ///   document (see the task-11 report's rules list), and a bare `set()` on an
  ///   an existing document IS an update in rules terms. That path is reachable
  ///   — `AccountSection._readPendingDeletion` fails open to `null`, so offline
  ///   or on permission-denied the pending panel is hidden and "Request account
  ///   deletion" is offered again — and it would have been denied.
  /// - Re-requesting must not slide the deadline. `purgeAfter` is the date the
  ///   user was promised; a second request writing a fresh one would silently
  ///   extend the window they are already inside.
  ///
  /// The read narrows but cannot close the race (two devices requesting at the
  /// same instant still both see "absent"). The rule is the actual guarantee;
  /// this makes the client agree with it.
  ///
  /// [now] is injectable for tests only; production passes nothing.
  Future<void> requestDeletion({DateTime? now}) async {
    if ((await _requestDoc.get()).exists) return;
    final requestedAt = now ?? DateTime.now();
    await _requestDoc.set({
      'uid': uid,
      // Server-stamped: the audit trail of WHEN must not depend on a device
      // clock, and `firestore.rules` can pin it to `request.time`.
      'requestedAt': FieldValue.serverTimestamp(),
      'purgeAfter': Timestamp.fromDate(requestedAt.add(graceWindow)),
    });
  }

  /// Withdraws a pending request. Idempotent: deleting a missing document is
  /// not an error in Firestore, so a double tap (or a retry after a partial
  /// failure) is safe.
  Future<void> cancelDeletion() => _requestDoc.delete();

  /// The pending request for this account, or null when there is none.
  Future<DeletionRequest?> pendingRequest() async {
    final snapshot = await _requestDoc.get();
    if (!snapshot.exists) return null;
    final data = snapshot.data() ?? const <String, dynamic>{};
    return DeletionRequest(
      requestedAt: _timestamp(data['requestedAt']),
      purgeAfter: _timestamp(data['purgeAfter']),
    );
  }

  static DateTime? _timestamp(Object? value) =>
      value is Timestamp ? value.toDate() : null;

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
  /// - `media` — metadata for every photo and video the user uploaded. The
  ///   documents themselves are paths, sizes and capture dates, but they are an
  ///   index of the most sensitive content in the account, and deleting them is
  ///   only HALF the job. See [storagePrefix].
  ///
  /// Public (not `_`-prefixed) so tests can enumerate this list directly
  /// rather than hand-duplicating it — a duplicated literal in a test is
  /// exactly the kind of copy that silently drifts out of sync with this one.
  static const subcollections = [
    'dailyLogs',
    'settings',
    'deletions',
    'devices',
    'media',
  ];

  /// The Cloud Storage prefix holding this account's uploaded media bytes.
  ///
  /// **This class cannot delete it, and that weakens what it claims to be.**
  /// [deleteFirestoreData] is the executable specification of the purge, and
  /// until media landed that specification was complete: every subcollection in
  /// [subcollections], root document last. Storage is a different service with
  /// its own lifecycle and its own client, so the full contract now lives in
  /// exactly one place — `functions/purge.js` — and this constant is the part
  /// of it that is expressible here.
  ///
  /// Deleting the `media` subcollection WITHOUT sweeping this prefix leaves the
  /// bytes behind: unreferenced, unreachable through any UI, unencrypted, and
  /// belonging to somebody who explicitly asked for them to be gone. That is a
  /// worse outcome than not deleting the metadata at all, because nothing is
  /// left pointing at them to find them by.
  ///
  /// Prefix-based, never driven off the metadata documents: an object whose
  /// document was already deleted (by the user, or by a partial earlier run)
  /// must still be swept, and the uid alone is enough to reconstruct where to
  /// look.
  static String storagePrefix(String uid) => 'users/$uid/media/';

  /// The irreversible sweep. **No client path calls this any more** — the app
  /// only ever requests deletion (see [requestDeletion]). It is kept, tested
  /// and public because it is the executable specification of what the purge
  /// job must delete: this exact list of subcollections, subcollections first
  /// and the root document last.
  ///
  /// Firestore does NOT delete subcollections when a parent document is
  /// deleted, so removing `users/{uid}` alone leaves the health data orphaned
  /// and unreachable — a Google Play User Data policy violation as well as a
  /// genuine privacy failure. Every known subcollection is deleted explicitly.
  ///
  /// The order matters: subcollections first, root document last. A crash
  /// mid-delete therefore leaves the root document present, so re-running finds
  /// and finishes the job. Running it twice is safe.
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
