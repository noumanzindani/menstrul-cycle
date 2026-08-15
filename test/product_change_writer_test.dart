import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/product_session.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/services/product_change_writer.dart';
import 'package:menstrul_track/services/product_timer_payload.dart';

/// The action handler runs in a bare background isolate with the app possibly
/// killed. These tests cover the decision logic against an injected database;
/// the isolate -> keystore -> cipher path itself is device-verified only, the
/// same standing exception the one-tap check-in carries.
void main() {
  late AppDatabase db;
  late ProductSessionRepository repo;

  final insertedAt = DateTime(2026, 8, 8, 9, 14);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ProductSessionRepository(ReminderRepository(db));
  });
  tearDown(() => db.close());

  ProductSession session({DateTime? at}) => ProductSession(
        insertedAt: at ?? insertedAt,
        product: ProductType.tampon,
        interval: const Duration(hours: 6),
      );

  test('restarts the session it was scheduled for', () async {
    await repo.start(session());
    final now = DateTime(2026, 8, 8, 15, 30);

    final handled = await ProductChangeWriter.markChanged(
      encodeSessionStamp(insertedAt),
      db: db,
      now: now,
    );

    expect(handled, isTrue);
    final after = await repo.get();
    expect(after?.insertedAt, now);
    // The duration the user chose survives the restart.
    expect(after?.interval, const Duration(hours: 6));
    expect(after?.product, ProductType.tampon);
  });

  test('a payload from a stale session is rejected', () async {
    // A notification left in the shade from an earlier session must not
    // restart — or end — the one running now.
    final currentStart = DateTime(2026, 8, 8, 14, 0);
    await repo.start(session(at: currentStart));
    final staleStamp = encodeSessionStamp(insertedAt);

    final handled = await ProductChangeWriter.markChanged(
      staleStamp,
      db: db,
      now: DateTime(2026, 8, 8, 15, 30),
    );

    // Handled — the obsolete notification should still go away — but the live
    // session is untouched.
    expect(handled, isTrue);
    expect((await repo.get())?.insertedAt, currentStart);
  });

  test('a tap after the session was ended elsewhere changes nothing', () async {
    final handled = await ProductChangeWriter.markChanged(
      encodeSessionStamp(insertedAt),
      db: db,
      now: DateTime(2026, 8, 8, 15, 30),
    );

    expect(handled, isTrue);
    expect(await repo.get(), null);
  });

  test('a malformed payload never restarts a session', () async {
    await repo.start(session());
    for (final bad in <String?>[null, '', 'abc', '{}']) {
      final handled =
          await ProductChangeWriter.markChanged(bad, db: db, now: DateTime.now());
      expect(handled, isTrue, reason: 'must not throw or retry-loop on: $bad');
      expect((await repo.get())?.insertedAt, insertedAt);
    }
  });

  test('a database failure is reported as false, never thrown', () async {
    // Stands in for the real failure mode this guard exists for: an
    // unavailable keystore, where opening the encrypted database throws. An
    // exception escaping a bare background isolate would be invisible, so the
    // contract is a bool — and false leaves the notification standing as its
    // own retry affordance.
    await db.customStatement('DROP TABLE reminders');

    final handled = await ProductChangeWriter.markChanged(
      encodeSessionStamp(insertedAt),
      db: db,
      now: DateTime.now(),
    );

    expect(handled, isFalse);
  });
}
