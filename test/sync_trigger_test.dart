import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/sync_trigger.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('setUser does not throw when Firebase has not been initialized',
      () async {
    // No Firebase app exists in this test binary (task 1b -- the console
    // setup -- is deliberately deferred). `lunaFirestore()` throws in that
    // state; the trigger must swallow it and leave sync disabled rather than
    // crashing the app, since `LunaTrackApp.build` calls `setUser` on every
    // signed-in rebuild, including in widget tests that sign a fake user in
    // with no Firebase app configured at all.
    final trigger = SyncTrigger(db);
    await trigger.setUser('uid-1');
    // A subsequent syncNow() must also be a safe no-op.
    await trigger.syncNow();
  });

  test(
      'setUser(null) after a signed-in user tears sync down without '
      'throwing', () async {
    final trigger = SyncTrigger(db);
    await trigger.setUser('uid-1');
    await trigger.setUser(null);
    await trigger.syncNow(); // no service left -- must be a no-op, not a crash
  });
}
