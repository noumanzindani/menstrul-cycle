import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/check_in_notifications.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';

/// The precomputed notification horizon. A repeating notification can't decide
/// "Did it start? / Has it ended? / nothing" at fire time, because the answer
/// depends on (logs, prediction, day). So we precompute one notification per day
/// for the next N days — the check-in question if there is one, otherwise the
/// generic daily nudge — and reschedule the whole horizon when the app opens or
/// a background action writes. This is the PURE half: no plugins.
void main() {
  DailyLog log(DateTime date, {FlowIntensity? flow}) => DailyLog(
        id: 0,
        date: date,
        flow: flow,
        symptoms: '{}',
        mood: null,
        notes: null,
        bbt: null,
        opk: null,
        createdAt: date,
        updatedAt: date,
      );

  PredictionResult pred({DateTime? next, int avgPeriod = 5}) => PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1,
        averagePeriodLength: avgPeriod,
        cyclesTracked: 3,
        confidence: PredictionConfidence.high,
        lastPeriodStart: DateTime(2026, 1, 1),
        cycleDay: 1,
        currentPhase: CyclePhase.luteal,
        nextPeriodStart: next,
        nextPeriodWindowStart: next,
        nextPeriodWindowEnd: next,
        ovulationDay: null,
        fertileWindowStart: null,
        fertileWindowEnd: null,
      );

  group('check-in payload codec', () {
    test('round-trips the answered date (date-only, no time)', () {
      final date = DateTime(2026, 7, 16);
      final decoded = decodeCheckInPayload(encodeCheckInPayload(date));
      expect(decoded, DateTime(2026, 7, 16));
    });

    test('normalises a datetime to local midnight on encode', () {
      final decoded = decodeCheckInPayload(
          encodeCheckInPayload(DateTime(2026, 7, 16, 22, 45)));
      expect(decoded, DateTime(2026, 7, 16));
    });

    test('returns null for a null/garbage payload (never crashes the isolate)',
        () {
      expect(decodeCheckInPayload(null), isNull);
      expect(decodeCheckInPayload(''), isNull);
      expect(decodeCheckInPayload('not-a-date'), isNull);
    });
  });

  group('CheckInHorizon.plan', () {
    test('emits exactly one notification per day across the horizon', () {
      final today = DateTime(2026, 1, 15);
      final horizon = CheckInHorizon.plan(
        logs: const [],
        prediction: pred(next: null),
        today: today,
      );

      expect(horizon, hasLength(CheckInHorizon.horizonDays));
      // Consecutive days from today, and stable per-day ids offset from the base.
      for (var i = 0; i < horizon.length; i++) {
        expect(horizon[i].date, today.add(Duration(days: i)));
        expect(horizon[i].id, CheckInHorizon.idCheckInBase + i);
      }
      // Every id distinct → never two notifications collide on the same slot.
      final ids = horizon.map((n) => n.id).toSet();
      expect(ids, hasLength(CheckInHorizon.horizonDays));
    });

    test('a due/overdue period day carries the "Did it start?" check-in', () {
      final today = DateTime(2026, 1, 28);
      final horizon = CheckInHorizon.plan(
        logs: const [],
        prediction: pred(next: today), // due today, unlogged
        today: today,
      );

      final entry = horizon.first;
      expect(entry.prompt, CheckInPrompt.didItStart);
      // Body + action label are verbatim from PeriodCheckInBanner (one source
      // of truth) — the notification is a remote control for that card.
      expect(entry.body, 'Your period was expected around now.');
      expect(entry.actionLabel, "Didn't start");
      // Both one-tap answers write the same primitive, so one action id suffices.
      expect(entry.actionId, kCheckInNoBleedingAction);
    });

    test('an on-period-past-usual-length day carries "Has it ended?"', () {
      // Period Jan 1..5 (avg 5); Jan 6 unlogged -> hasItEnded on day 0.
      final horizon = CheckInHorizon.plan(
        logs: [
          for (var i = 0; i < 5; i++)
            log(DateTime(2026, 1, 1).add(Duration(days: i)),
                flow: FlowIntensity.medium),
        ],
        prediction: pred(next: DateTime(2026, 1, 28), avgPeriod: 5),
        today: DateTime(2026, 1, 6),
      );

      final entry = horizon.first;
      expect(entry.prompt, CheckInPrompt.hasItEnded);
      expect(entry.body, 'This period has run to its usual length.');
      expect(entry.actionLabel, 'Mark ended here');
      expect(entry.actionId, kCheckInNoBleedingAction);
    });

    test('days with no question fall back to the generic nudge (no action)', () {
      final horizon = CheckInHorizon.plan(
        logs: const [],
        prediction: pred(next: null), // nothing to ask
        today: DateTime(2026, 1, 15),
      );

      for (final entry in horizon) {
        expect(entry.prompt, CheckInPrompt.none);
        expect(entry.title, 'How are you today?');
        expect(entry.body, 'Tap to log your flow and symptoms.');
        expect(entry.actionLabel, isNull); // body-tap only, no one-tap answer
        expect(entry.actionId, isNull);
      }
    });

    test('planIfEnabled schedules the full horizon when the nudge is on', () {
      final horizon = CheckInHorizon.planIfEnabled(
        logNudgeEnabled: true,
        logs: const [],
        prediction: pred(next: null),
        today: DateTime(2026, 1, 15),
      );
      expect(horizon, hasLength(CheckInHorizon.horizonDays));
    });

    test(
        'REGRESSION GUARD: planIfEnabled schedules NOTHING when the nudge is off',
        () {
      // The horizon is gated on the existing logNudge toggle. Resurrecting
      // notifications the user explicitly disabled would be a bug, not a feature.
      final horizon = CheckInHorizon.planIfEnabled(
        logNudgeEnabled: false,
        logs: [
          for (var i = 0; i < 5; i++)
            log(DateTime(2026, 1, 28).add(Duration(days: i)),
                flow: FlowIntensity.medium),
        ],
        prediction: pred(next: DateTime(2026, 1, 28)), // would otherwise prompt
        today: DateTime(2026, 1, 28),
      );
      expect(horizon, isEmpty);
    });

    test('GUARDRAIL: no copy anywhere says "safe" or frames fertility', () {
      // Exercise both check-in kinds and the fallback in one horizon sweep.
      final horizons = [
        CheckInHorizon.plan(
            logs: const [],
            prediction: pred(next: DateTime(2026, 1, 28)),
            today: DateTime(2026, 1, 28)),
        CheckInHorizon.plan(
            logs: [
              for (var i = 0; i < 5; i++)
                log(DateTime(2026, 1, 1).add(Duration(days: i)),
                    flow: FlowIntensity.medium),
            ],
            prediction: pred(next: DateTime(2026, 1, 28), avgPeriod: 5),
            today: DateTime(2026, 1, 6)),
      ];
      const banned = ['safe', 'fertile', 'fertility', 'ovulat', 'conceiv'];
      for (final horizon in horizons) {
        for (final entry in horizon) {
          final copy =
              '${entry.title} ${entry.body} ${entry.actionLabel ?? ''}'
                  .toLowerCase();
          for (final word in banned) {
            expect(copy.contains(word), isFalse,
                reason: 'check-in copy must be period-timing only: "$copy"');
          }
        }
      }
    });
  });
}
