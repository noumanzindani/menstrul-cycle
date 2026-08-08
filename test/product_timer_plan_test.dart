import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/models/product_session.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/services/product_timer_plan.dart';

/// A session started at 09:14 with a 4-hour target: due 13:14, follow-up 13:44.
ProductSession _session({
  ProductType product = ProductType.tampon,
  Duration interval = const Duration(hours: 4),
}) =>
    ProductSession(
      insertedAt: DateTime(2026, 8, 8, 9, 14),
      product: product,
      interval: interval,
    );

void main() {
  group('ProductType wear limits', () {
    test('a ProductType knows whether it carries a wear-time cap', () {
      // Tampons and cups/discs have a manufacturer-stated maximum. Pads and
      // period underwear do not — their caps are UI sanity bounds, so the app
      // must not present them as safety guidance.
      expect(ProductType.tampon.hasWearLimit, isTrue);
      expect(ProductType.cupOrDisc.hasWearLimit, isTrue);
      expect(ProductType.pad.hasWearLimit, isFalse);
      expect(ProductType.periodUnderwear.hasWearLimit, isFalse);
    });

    test('caps match the manufacturer guidance the copy attributes', () {
      expect(ProductType.tampon.maxDuration, const Duration(hours: 8));
      expect(ProductType.cupOrDisc.maxDuration, const Duration(hours: 12));
    });

    test('defaults fire before the cap, never at it', () {
      for (final t in ProductType.values) {
        expect(t.defaultDuration, lessThan(t.maxDuration),
            reason: '${t.name} default must leave room to act');
      }
    });

    test('only capped products carry an attributed cap note', () {
      // The note is what keeps a duration from reading as LunaTrack's own
      // medical advice, so it must cite the source and never say "we".
      for (final t in ProductType.values) {
        if (t.hasWearLimit) {
          expect(t.capNote, isNotNull, reason: '${t.name} needs attribution');
          expect(t.capNote!.toLowerCase(),
              anyOf(contains('packaging'), contains('manufacturer')));
          expect(t.capNote!.toLowerCase(), isNot(contains('we recommend')));
          expect(t.capNote!.toLowerCase(), isNot(contains('safe')));
        } else {
          expect(t.capNote, isNull, reason: '${t.name} has no safety limit');
        }
      }
    });
  });

  group('ProductType persistence', () {
    test('round-trips by name, so declaration order carries no meaning', () {
      for (final t in ProductType.values) {
        expect(productTypeFromName(t.name), t);
      }
    });

    test('an unknown or malformed name decodes to null, never throws', () {
      expect(productTypeFromName('sponge'), isNull);
      expect(productTypeFromName(''), isNull);
      expect(productTypeFromName(null), isNull);
    });
  });

  group('ProductType labels', () {
    test('every product has a label and none of them say "safe"', () {
      for (final t in ProductType.values) {
        expect(t.label, isNotEmpty);
        expect(t.label.toLowerCase(), isNot(contains('safe')));
      }
    });
  });

  group('ProductTimerPlan.plan', () {
    test('plans a reminder at insertedAt + interval and a follow-up 30 '
        'minutes later', () {
      final slots = ProductTimerPlan.plan(
        session: _session(),
        now: DateTime(2026, 8, 8, 9, 15),
      );

      expect(slots, hasLength(2));
      expect(slots[0].id, ProductTimerPlan.idDue);
      expect(slots[0].when, DateTime(2026, 8, 8, 13, 14));
      expect(slots[1].id, ProductTimerPlan.idFollowUp);
      expect(slots[1].when, DateTime(2026, 8, 8, 13, 44));
    });

    test('the two slots stay outside the allow-while-idle throttle window', () {
      // `inexactAllowWhileIdle` resolves to setAndAllowWhileIdle, which Android
      // rate-limits to roughly one wakeup per 9-15 minutes per app. Slots closer
      // than that are silently swallowed, so the follow-up would never arrive.
      final slots = ProductTimerPlan.plan(
        session: _session(),
        now: DateTime(2026, 8, 8, 9, 15),
      );
      final gap = slots[1].when.difference(slots[0].when);
      expect(gap, greaterThanOrEqualTo(ProductTimerPlan.minSlotSpacing));
    });

    test('replanning mid-session omits slots that have already passed', () {
      // Resumed at 13:20: the due slot fired, the follow-up has not.
      final slots = ProductTimerPlan.plan(
        session: _session(),
        now: DateTime(2026, 8, 8, 13, 20),
      );
      expect(slots, hasLength(1));
      expect(slots.single.id, ProductTimerPlan.idFollowUp);
    });

    test('a session past both slots plans nothing', () {
      final slots = ProductTimerPlan.plan(
        session: _session(),
        now: DateTime(2026, 8, 8, 18, 0),
      );
      expect(slots, isEmpty);
    });

    test('a slot exactly at now is treated as passed, not scheduled', () {
      final slots = ProductTimerPlan.plan(
        session: _session(),
        now: DateTime(2026, 8, 8, 13, 14),
      );
      expect(slots.map((s) => s.id), isNot(contains(ProductTimerPlan.idDue)));
    });

    test('slot ids sit in the free 5000+ range', () {
      expect(ProductTimerPlan.idDue, 5000);
      expect(ProductTimerPlan.idFollowUp, 5001);
      // 1001-1003 fixed, 2000+ medications, 3000+ custom, 4000-4013 check-in.
      for (final id in ProductTimerPlan.allIds) {
        expect(id, greaterThanOrEqualTo(5000));
      }
    });
  });

  group('ProductTimerPlan.planIfEnabled', () {
    test('returns nothing when the timer is off, so a caller cancels the '
        'whole slot and never resurrects a disabled reminder', () {
      final slots = ProductTimerPlan.planIfEnabled(
        enabled: false,
        session: _session(),
        now: DateTime(2026, 8, 8, 9, 15),
      );
      expect(slots, isEmpty);
    });

    test('returns nothing when there is no session at all', () {
      final slots = ProductTimerPlan.planIfEnabled(
        enabled: true,
        session: null,
        now: DateTime(2026, 8, 8, 9, 15),
      );
      expect(slots, isEmpty);
    });

    test('is identical to plan() when enabled', () {
      final now = DateTime(2026, 8, 8, 9, 15);
      final gated =
          ProductTimerPlan.planIfEnabled(enabled: true, session: _session(), now: now);
      final direct = ProductTimerPlan.plan(session: _session(), now: now);
      expect(gated.map((s) => s.id), direct.map((s) => s.id));
      expect(gated.map((s) => s.when), direct.map((s) => s.when));
    });
  });

  group('ProductTimerPlan copy', () {
    List<ProductTimerNotification> slots() => ProductTimerPlan.plan(
          session: _session(),
          now: DateTime(2026, 8, 8, 9, 15),
        );

    test('the title is a fixed generic string that names nothing', () {
      for (final s in slots()) {
        expect(s.title, 'LunaTrack');
      }
    });

    test('the body states elapsed time and the start clock', () {
      expect(slots()[0].body, "It's been 4h since 09:14.");
      expect(slots()[1].body, "It's been 4h 30m since 09:14.");
    });

    test('no notification names a product by default', () {
      // `secret` visibility is honoured by AOSP but not guaranteed across Wear
      // OS bridging, Phone Link mirroring or Notification History, so the
      // default body must be harmless if it leaks.
      const banned = [
        'tampon',
        'cup',
        'disc',
        'pad',
        'period',
        'menstrual',
        'underwear',
      ];
      for (final s in slots()) {
        for (final word in banned) {
          expect(s.body.toLowerCase(), isNot(contains(word)),
              reason: '"$word" must not appear in a notification body');
          expect(s.title.toLowerCase(), isNot(contains(word)));
        }
      }
    });

    test('no notification counts down, warns, or reassures', () {
      const banned = [
        'remaining',
        'left',
        'until',
        "time's up",
        'safe',
        'overdue',
        'danger',
        'urgent',
        'warning',
        'tss',
        'toxic',
      ];
      for (final s in slots()) {
        final text = '${s.title} ${s.body}'.toLowerCase();
        for (final word in banned) {
          expect(text, isNot(contains(word)),
              reason: '"$word" must not appear in a notification');
        }
      }
    });
  });

  group('elapsed formatting', () {
    test('reads in hours and minutes, dropping empty units', () {
      expect(formatElapsed(const Duration(hours: 4)), '4h');
      expect(formatElapsed(const Duration(hours: 4, minutes: 20)), '4h 20m');
      expect(formatElapsed(const Duration(minutes: 45)), '45m');
      expect(formatElapsed(Duration.zero), '0m');
      expect(formatElapsed(const Duration(hours: 12, minutes: 0)), '12h');
    });

    test('never goes negative, so a clock skew cannot render "-3m"', () {
      expect(formatElapsed(const Duration(minutes: -5)), '0m');
    });

    test('seconds are floored, not rounded, so the display never runs ahead',
        () {
      expect(formatElapsed(const Duration(minutes: 3, seconds: 59)), '3m');
    });
  });

  group('clock formatting', () {
    test('is zero-padded 24-hour', () {
      expect(formatClock(DateTime(2026, 8, 8, 9, 14)), '09:14');
      expect(formatClock(DateTime(2026, 8, 8, 23, 5)), '23:05');
      expect(formatClock(DateTime(2026, 8, 8, 0, 0)), '00:00');
    });
  });
}
