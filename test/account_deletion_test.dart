import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/account_deletion_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  // Seeds every collection `AccountDeletionService` is supposed to sweep,
  // driven by its own public list rather than a hand-written duplicate --
  // see the doc comment on `AccountDeletionService.subcollections` for why a
  // second copy of that list is exactly the kind of thing that silently goes
  // stale.
  Future<void> seed(String uid) async {
    for (final name in AccountDeletionService.subcollections) {
      await firestore
          .collection('users/$uid/$name')
          .doc('doc-1')
          .set({'marker': name});
    }
    await firestore.doc('users/$uid').set({'email': 'a@b.com'});
  }

  group('the soft-delete request (what the app actually does now)', () {
    test('the grace window is 30 days, in one named constant', () {
      expect(AccountDeletionService.graceWindow, const Duration(days: 30));
    });

    test(
        'requestDeletion writes a top-level deletionRequests/{uid} marker -- '
        'the purge job must be able to find every expired request with one '
        'query, without scanning anybody\'s health data', () async {
      final now = DateTime(2026, 8, 5, 12);

      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .requestDeletion(now: now);

      final doc = await firestore.doc('deletionRequests/uid-1').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['uid'], 'uid-1');
      // The queryable deadline. The purge runs `where('purgeAfter', '<=',
      // now)` against this ONE small collection.
      expect(
        (doc.data()!['purgeAfter'] as Timestamp).toDate(),
        now.add(AccountDeletionService.graceWindow),
      );
      // Server-stamped, so the audit trail does not depend on a device clock.
      expect(doc.data()!['requestedAt'], isNotNull);
    });

    test(
        'requestDeletion does NOT delete any cloud data -- the purge does that '
        'later, and until then a cancel must be able to give it all back',
        () async {
      await seed('uid-1');

      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .requestDeletion(now: DateTime(2026, 8, 5));

      for (final name in AccountDeletionService.subcollections) {
        expect(
          (await firestore.collection('users/uid-1/$name').get()).docs,
          hasLength(1),
          reason: 'users/uid-1/$name must survive a deletion REQUEST',
        );
      }
      expect((await firestore.doc('users/uid-1').get()).exists, isTrue);
    });

    test('the marker holds no health data -- only the uid and two timestamps',
        () async {
      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .requestDeletion(now: DateTime(2026, 8, 5));

      final data = (await firestore.doc('deletionRequests/uid-1').get()).data()!;
      expect(data.keys.toSet(), {'uid', 'requestedAt', 'purgeAfter'});
    });

    test('the purge query finds expired requests and skips live ones',
        () async {
      // Two accounts requested deletion 40 and 5 days ago respectively.
      final now = DateTime(2026, 8, 5);
      await AccountDeletionService(firestore: firestore, uid: 'expired')
          .requestDeletion(now: now.subtract(const Duration(days: 40)));
      await AccountDeletionService(firestore: firestore, uid: 'fresh')
          .requestDeletion(now: now.subtract(const Duration(days: 5)));

      // Exactly the query the (not-yet-written) purge job will run.
      final due = await firestore
          .collection(AccountDeletionService.requestsCollection)
          .where('purgeAfter', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .get();

      expect(due.docs.map((d) => d.id), ['expired']);
    });

    test('pendingRequest reports the deadline the user was promised',
        () async {
      final now = DateTime(2026, 8, 5, 9, 30);
      final service = AccountDeletionService(firestore: firestore, uid: 'uid-1');

      expect(await service.pendingRequest(), isNull);

      await service.requestDeletion(now: now);

      expect(
        (await service.pendingRequest())!.purgeAfter,
        now.add(AccountDeletionService.graceWindow),
      );
    });

    test(
        'a marker with a malformed purgeAfter still counts as pending -- '
        'failing open would resume syncing into an account queued for erasure',
        () async {
      await firestore.doc('deletionRequests/uid-1').set({'uid': 'uid-1'});

      final pending = await AccountDeletionService(
        firestore: firestore,
        uid: 'uid-1',
      ).pendingRequest();

      expect(pending, isNotNull);
      expect(pending!.purgeAfter, isNull);
    });

    test('cancelDeletion removes the marker, and is safe to re-run', () async {
      final service = AccountDeletionService(firestore: firestore, uid: 'uid-1');
      await service.requestDeletion(now: DateTime(2026, 8, 5));

      await service.cancelDeletion();
      await service.cancelDeletion();

      expect(await service.pendingRequest(), isNull);
    });

    test('one account\'s request never marks another account', () async {
      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .requestDeletion(now: DateTime(2026, 8, 5));

      expect(
        await AccountDeletionService(firestore: firestore, uid: 'uid-2')
            .pendingRequest(),
        isNull,
      );
    });
  });

  group('the hard purge (server-side contract; no client path calls it now)',
      () {
    test(
        'the sweep covers dailyLogs, settings, deletions AND devices -- the '
        'brief predates the latter two; omitting either leaves a server-side '
        'trace of the user behind after they asked for everything to be '
        'deleted', () {
      expect(
        AccountDeletionService.subcollections,
        containsAll(['dailyLogs', 'settings', 'deletions', 'devices']),
      );
    });

    test('deletes the whole user subtree, not just the root document',
        () async {
      await seed('uid-1');

      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .deleteFirestoreData();

      // Deleting only `users/{uid}` would leave these orphaned and unreachable —
      // a Play policy violation and a real privacy failure. Enumerating the
      // service's own list (not a hardcoded pair) means a future collection
      // added to `subcollections` is automatically covered here too.
      for (final name in AccountDeletionService.subcollections) {
        expect(
          (await firestore.collection('users/uid-1/$name').get()).docs,
          isEmpty,
          reason: 'users/uid-1/$name should be empty after deletion',
        );
      }
      expect((await firestore.doc('users/uid-1').get()).exists, isFalse);
    });

    test('never touches another user\'s data', () async {
      await seed('uid-1');
      await seed('uid-2');

      await AccountDeletionService(firestore: firestore, uid: 'uid-1')
          .deleteFirestoreData();

      for (final name in AccountDeletionService.subcollections) {
        expect(
          (await firestore.collection('users/uid-2/$name').get()).docs,
          hasLength(1),
          reason: 'users/uid-2/$name should be untouched',
        );
      }
      expect((await firestore.doc('users/uid-2').get()).exists, isTrue);
    });

    test('re-running after a partial delete completes cleanly', () async {
      await seed('uid-1');
      final service =
          AccountDeletionService(firestore: firestore, uid: 'uid-1');

      await service.deleteFirestoreData();
      await service.deleteFirestoreData(); // resumable, must not throw

      expect((await firestore.doc('users/uid-1').get()).exists, isFalse);
    });
  });
}
