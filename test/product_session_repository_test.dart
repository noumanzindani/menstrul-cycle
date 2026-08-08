import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/product_session.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/providers/product_session_provider.dart';
import 'package:menstrul_track/providers/reminder_provider.dart';

void main() {
  late AppDatabase db;
  late ProductSessionRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ProductSessionRepository(ReminderRepository(db));
  });
  tearDown(() => db.close());

  ProductSession session({
    ProductType product = ProductType.tampon,
    int hour = 9,
    Duration interval = const Duration(hours: 4),
  }) =>
      ProductSession(
        insertedAt: DateTime(2026, 8, 8, hour, 14),
        product: product,
        interval: interval,
      );

  group('ProductSessionRepository', () {
    test('round-trips a session through the database', () async {
      await repo.start(session());
      expect(await repo.get(), session());
    });

    test('starting a session twice replaces the row rather than creating a '
        'second', () async {
      // getByType uses getSingleOrNull, which THROWS on two rows — so the
      // failure mode of an accidental insert is an exception, not a wrong
      // value. That is why this is asserted explicitly.
      await repo.start(session(hour: 9));
      await repo.start(session(hour: 11, product: ProductType.cupOrDisc));

      final rows = await db.select(db.reminders).get();
      expect(rows, hasLength(1));
      expect(await repo.get(), session(hour: 11, product: ProductType.cupOrDisc));
    });

    test('no session before one is started', () async {
      expect(await repo.get(), isNull);
    });

    test('ending a session removes the row entirely', () async {
      await repo.start(session());
      await repo.end();

      expect(await repo.get(), isNull);
      expect(await db.select(db.reminders).get(), isEmpty);
    });

    test('ending when nothing is running is a no-op, not an error', () async {
      await repo.end();
      expect(await repo.get(), isNull);
    });

    test('a corrupt payload reads as no session rather than throwing',
        () async {
      await ReminderRepository(db).upsert(
        type: ReminderType.productChange,
        enabled: true,
        hour: 0,
        minute: 0,
        payload: 'not json',
      );
      expect(await repo.get(), isNull);
    });

    test('deleteAllData clears the session with everything else', () async {
      await repo.start(session());
      await db.deleteAllData();
      expect(await repo.get(), isNull);
    });
  });

  group('coexistence with the existing reminder rows', () {
    test('a session does not surface as a custom reminder', () async {
      final reminders = ReminderRepository(db);
      await reminders.addCustom(title: 'Water', hour: 9, minute: 0);
      await repo.start(session());

      final provider = ReminderProvider(reminders);
      await provider.load();

      expect(provider.customReminders, hasLength(1));
      expect(provider.customReminders.single.title, 'Water');
    });

    test('the daysBefore reader still defaults when a session payload exists',
        () async {
      // ReminderProvider.daysBefore() reads `payload` for ANY type. A session
      // blob has no daysBefore key and must not disturb it.
      await repo.start(session());
      final provider = ReminderProvider(ReminderRepository(db));
      await provider.load();

      expect(provider.daysBefore(ReminderType.productChange), 2);
      expect(provider.daysBefore(ReminderType.periodSoon), 2);
    });

    test('smart reminders are unaffected by a live session', () async {
      final reminders = ReminderRepository(db);
      await reminders.upsert(
          type: ReminderType.periodSoon, enabled: true, hour: 9, minute: 0);
      await repo.start(session());

      final provider = ReminderProvider(reminders);
      await provider.load();

      expect(provider.isEnabled(ReminderType.periodSoon), isTrue);
      expect(provider.hourOf(ReminderType.periodSoon), 9);
    });
  });

  group('ProductSessionProvider', () {
    late ProductSessionProvider provider;
    setUp(() => provider = ProductSessionProvider(repo));

    test('starts a session at the product default duration', () async {
      final now = DateTime(2026, 8, 8, 9, 14);
      final ok = await provider.start(ProductType.cupOrDisc, now: now);

      expect(ok, isTrue);
      expect(provider.session?.product, ProductType.cupOrDisc);
      expect(provider.session?.interval, ProductType.cupOrDisc.defaultDuration);
      expect(provider.session?.insertedAt, now);
    });

    test('refuses a duration past a manufacturer cap and starts nothing',
        () async {
      // A refusal, not a silent clamp: rewriting the user's number would hide
      // that the app declined.
      final ok = await provider.start(
        ProductType.tampon,
        interval: const Duration(hours: 10),
        now: DateTime(2026, 8, 8, 9, 14),
      );

      expect(ok, isFalse);
      expect(provider.session, isNull);
    });

    test('accepts a duration exactly at the cap', () async {
      final ok = await provider.start(ProductType.tampon,
          interval: const Duration(hours: 8), now: DateTime(2026, 8, 8, 9, 14));
      expect(ok, isTrue);
    });

    test('refuses a zero or negative duration', () async {
      expect(await provider.start(ProductType.pad, interval: Duration.zero),
          isFalse);
      expect(
          await provider.start(ProductType.pad,
              interval: const Duration(minutes: -5)),
          isFalse);
    });

    test('"changed" restarts the same product from now', () async {
      await provider.start(ProductType.tampon,
          interval: const Duration(hours: 6), now: DateTime(2026, 8, 8, 9, 14));

      final later = DateTime(2026, 8, 8, 15, 20);
      await provider.changed(now: later);

      expect(provider.session?.product, ProductType.tampon);
      expect(provider.session?.insertedAt, later);
      // The duration the user chose is carried over, not reset to the default.
      expect(provider.session?.interval, const Duration(hours: 6));
    });

    test('"changed" with nothing running does not invent a session', () async {
      await provider.changed(now: DateTime(2026, 8, 8, 15, 20));
      expect(provider.session, isNull);
    });

    test('"removed" ends the session outright', () async {
      await provider.start(ProductType.pad, now: DateTime(2026, 8, 8, 9, 14));
      await provider.removed();
      expect(provider.session, isNull);
    });

    test('load picks up a session written by another isolate', () async {
      await repo.start(session());
      await provider.load();
      expect(provider.session, session());
    });

    test('notifies listeners when the session changes', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.start(ProductType.pad, now: DateTime(2026, 8, 8, 9, 14));
      expect(notifications, greaterThan(0));

      final before = notifications;
      await provider.removed();
      expect(notifications, greaterThan(before));
    });
  });
}
