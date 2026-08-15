import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/media_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/media_provider.dart';
import 'package:menstrul_track/services/media_limits.dart';

void main() {
  late AppDatabase db;
  late MediaRepository repo;
  late MediaProvider provider;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = MediaRepository(db);
    provider = MediaProvider(repo);
  });
  tearDown(() => db.close());

  Future<void> seed(String id, String uid, {DateTime? capturedAt}) => repo.upsert(
        id: id,
        uid: uid,
        kind: MediaKind.image,
        storagePath: 'users/$uid/media/$id/original.jpg',
        capturedAt: capturedAt ?? DateTime(2026, 6, 1),
      );

  test('starts empty and loading, with no account', () {
    expect(provider.items, isEmpty);
    expect(provider.loading, isTrue);
    expect(provider.uid, isNull);
  });

  test('signing in loads that account\'s items and clears the loading flag',
      () async {
    await seed('a' * 32, 'uid-1');
    await seed('b' * 32, 'uid-1', capturedAt: DateTime(2026, 7, 1));

    await provider.setUid('uid-1');

    expect(provider.loading, isFalse);
    expect(provider.items.map((m) => m.id), ['b' * 32, 'a' * 32]);
  });

  test('notifies listeners when the set changes', () async {
    var notifications = 0;
    provider.addListener(() => notifications++);

    await seed('a' * 32, 'uid-1');
    await provider.setUid('uid-1');

    expect(notifications, greaterThan(0));
  });

  test('switching accounts ERASES the old rows and starts the new one empty',
      () async {
    await seed('a' * 32, 'uid-A');
    await provider.setUid('uid-A');
    expect(provider.items.single.id, 'a' * 32);

    await provider.setUid('uid-B');

    // A's rows are not merely filtered out of the view — they are gone from
    // disk. A's thumbnails are photographs, and nothing else in this flow would
    // ever remove them.
    expect(await repo.allFor('uid-A'), isEmpty);
    // B starts empty: media is cloud-required, so B's timeline is whatever the
    // next pull brings down, never whatever happened to be on this device.
    expect(provider.items, isEmpty);

    await seed('b' * 32, 'uid-B'); // as the pull would
    await provider.reload();
    expect(provider.items.single.id, 'b' * 32);
  });

  test('signing out empties the timeline and the table', () async {
    await seed('a' * 32, 'uid-A');
    await provider.setUid('uid-A');

    await provider.setUid(null);

    expect(provider.items, isEmpty);
    expect(provider.uid, isNull);
    expect(await db.select(db.mediaItems).get(), isEmpty);
  });

  test('setting the SAME uid again does not wipe anything', () async {
    // A resumed session or a rebuilt provider re-announces the same account.
    // Treating that as a switch would delete the user's own timeline.
    await seed('a' * 32, 'uid-A');
    await provider.setUid('uid-A');
    await provider.setUid('uid-A');

    expect(provider.items, hasLength(1));
  });

  test('reload picks up rows written by the sync layer', () async {
    await provider.setUid('uid-1');
    expect(provider.items, isEmpty);

    await seed('a' * 32, 'uid-1'); // as a pull would
    await provider.reload();

    expect(provider.items, hasLength(1));
  });

  test('reload with no account is a no-op rather than a crash', () async {
    await provider.reload();
    expect(provider.items, isEmpty);
  });
}
