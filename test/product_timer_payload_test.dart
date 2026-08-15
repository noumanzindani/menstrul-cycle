import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/models/product_session.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/services/product_timer_payload.dart';

void main() {
  final session = ProductSession(
    insertedAt: DateTime(2026, 8, 8, 9, 14),
    product: ProductType.tampon,
    interval: const Duration(hours: 4),
  );

  group('session payload (Reminders.payload column)', () {
    test('round-trips insertedAt, product and interval', () {
      final decoded = decodeProductSession(encodeProductSession(session));
      expect(decoded, session);
    });

    test('round-trips every product type', () {
      for (final t in ProductType.values) {
        final s = session.copyWith(product: t);
        expect(decodeProductSession(encodeProductSession(s))?.product, t);
      }
    });

    test('preserves the instant across time zones, not the wall clock', () {
      // The payload stores epoch millis, so a device that changes zone (or
      // crosses a DST boundary) still reads back the same moment. An elapsed
      // timer cares about the instant; reconstructing a wall clock would drift.
      final utc = DateTime.utc(2026, 8, 8, 9, 14);
      final decoded =
          decodeProductSession(encodeProductSession(session.copyWith(insertedAt: utc)));
      expect(decoded!.insertedAt.isAtSameMomentAs(utc), isTrue);
    });

    test('returns null for a malformed payload instead of throwing', () {
      // This is read from a bare background isolate, where an exception is
      // invisible — a garbage payload must fail quietly, not kill the handler.
      const bad = <String?>[
        null,
        '',
        '   ',
        'not json at all',
        '{',
        '[]',
        '"a string"',
        '42',
        '{}',
        '{"product":"tampon","intervalMinutes":240}', // no insertedAt
        '{"insertedAt":1,"intervalMinutes":240}', // no product
        '{"insertedAt":1,"product":"tampon"}', // no interval
        '{"insertedAt":"nope","product":"tampon","intervalMinutes":240}',
        '{"insertedAt":1,"product":"sponge","intervalMinutes":240}',
        '{"insertedAt":1,"product":"tampon","intervalMinutes":"240"}',
        '{"insertedAt":1,"product":"tampon","intervalMinutes":0}',
        '{"insertedAt":1,"product":"tampon","intervalMinutes":-30}',
        '{"insertedAt":1,"product":"tampon","intervalMinutes":100000}',
      ];
      for (final payload in bad) {
        expect(() => decodeProductSession(payload), returnsNormally,
            reason: 'must not throw on: $payload');
        expect(decodeProductSession(payload), isNull,
            reason: 'must not decode: $payload');
      }
    });

    test('the daysBefore reader on other reminder types is unaffected', () {
      // ReminderProvider.daysBefore() reads `payload` for ANY reminder type and
      // must keep defaulting rather than choking on a session blob.
      final encoded = encodeProductSession(session);
      expect(encoded.contains('daysBefore'), isFalse);
    });
  });

  group('notification payload (session identity)', () {
    test('round-trips the session stamp', () {
      final stamp = encodeSessionStamp(session.insertedAt);
      expect(decodeSessionStamp(stamp), session.insertedAt);
    });

    test('a payload from a stale session is rejected', () {
      // A notification left in the shade from a previous session must not end
      // the current one when tapped.
      final current = session.insertedAt;
      final stale = current.subtract(const Duration(hours: 9));
      final stamp = encodeSessionStamp(stale);

      expect(decodeSessionStamp(stamp), isNot(current));
      expect(isStampFor(stamp, current), isFalse);
      expect(isStampFor(encodeSessionStamp(current), current), isTrue);
    });

    test('a malformed stamp is not treated as a match', () {
      for (final bad in <String?>[null, '', 'abc', '1.5', '{}', ' ']) {
        expect(() => decodeSessionStamp(bad), returnsNormally);
        expect(decodeSessionStamp(bad), isNull);
        expect(isStampFor(bad, session.insertedAt), isFalse);
      }
    });

    test('never matches when there is no current session', () {
      expect(isStampFor(encodeSessionStamp(session.insertedAt), null), isFalse);
    });
  });
}
