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
    final service = AccountDeletionService(firestore: firestore, uid: 'uid-1');

    await service.deleteFirestoreData();
    await service.deleteFirestoreData(); // resumable, must not throw

    expect((await firestore.doc('users/uid-1').get()).exists, isFalse);
  });
}
