import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/prediction.dart';
import 'cycle_check_in.dart';

/// The action id delivered to the background handler when the user taps a
/// one-tap check-in button. Both answers ("Didn't start" / "Mark ended here")
/// write the SAME primitive — a confirmed no-bleeding day (`flow = none`) — so a
/// single action id suffices; the day being answered rides in the payload.
const String kCheckInNoBleedingAction = 'checkin_no_bleeding';

/// Encodes the day a check-in notification answers into its `payload` string.
/// Date-only (local midnight): the notification confirms a whole day, and the
/// background handler must read back exactly the same key `DailyLogRepository`
/// stores under. Format is a plain `yyyy-MM-dd` so it survives the platform
/// round-trip through a String channel with no dependencies.
String encodeCheckInPayload(DateTime date) {
  final d = dateOnly(date);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// Decodes [encodeCheckInPayload]. Returns null for a null, empty, or malformed
/// payload rather than throwing — a bare background isolate that throws is
/// invisible, so a garbage payload must fail quietly, not crash the handler.
DateTime? decodeCheckInPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  final parts = payload.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  return DateTime(y, m, d);
}

/// One day's fully-resolved notification in the precomputed horizon: id, the day
/// it belongs to, the decided [prompt], and the copy/action baked in at schedule
/// time. This is a value object — no plugins — so the planner stays unit-testable.
class CheckInNotification {
  const CheckInNotification({
    required this.id,
    required this.date,
    required this.prompt,
    required this.title,
    required this.body,
    this.actionLabel,
    this.actionId,
  });

  final int id;
  final DateTime date;
  final CheckInPrompt prompt;
  final String title;
  final String body;

  /// The one-tap button label, or null for the generic fallback (body-tap only).
  final String? actionLabel;

  /// The vm:entry-point action id, or null when there is no one-tap answer.
  final String? actionId;

  bool get hasAction => actionId != null;
}

/// Precomputes the daily notification horizon. `scheduleDailyLogNudge` schedules
/// ONE repeating notification whose text is frozen at schedule time, but the
/// check-in question — "Did it start?" vs "Has it ended?" vs *nothing* — depends
/// on (logs, prediction, today), which a repeating notification can't evaluate
/// at fire time. Since [CycleCheckInService.evaluate] is pure and logs can't
/// change while the app is closed (except via our own action, which reschedules),
/// we compute the prompt for each of the next [horizonDays] days and schedule one
/// one-shot per day. Exactly one notification per day: the check-in question if
/// there is one, otherwise the generic nudge — never two.
///
/// This class is the pure half (planning). The impure half (handing the plan to
/// `flutter_local_notifications`) lives in `NotificationService`.
class CheckInHorizon {
  const CheckInHorizon._();

  /// The horizon only extends when the app is opened or an action is tapped, so
  /// a user idle longer than this stops getting nudges — accepted: someone
  /// silent for two weeks has churned for reasons a notification won't fix. 14
  /// keeps the scheduled-alarm count trivial.
  static const int horizonDays = 14;

  /// Base id for the daily slot; day `i` uses `idCheckInBase + i` (4000..4013).
  /// Above medications (2000+) and custom reminders (3000+); never collides.
  static const int idCheckInBase = 4000;

  static List<CheckInNotification> plan({
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required DateTime today,
  }) {
    final start = dateOnly(today);
    return [
      for (var i = 0; i < horizonDays; i++)
        _notificationFor(
          id: idCheckInBase + i,
          day: start.add(Duration(days: i)),
          prompt: CycleCheckInService.evaluate(
            logs: logs,
            prediction: prediction,
            today: start.add(Duration(days: i)),
          ),
        ),
    ];
  }

  /// The horizon to actually schedule, gated on the existing `logNudge` toggle.
  /// Returns [] when the daily nudge is off, so a caller cancels the whole slot
  /// and schedules nothing — the horizon never resurrects notifications the user
  /// explicitly disabled. Otherwise identical to [plan].
  static List<CheckInNotification> planIfEnabled({
    required bool logNudgeEnabled,
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required DateTime today,
  }) {
    if (!logNudgeEnabled) return const [];
    return plan(logs: logs, prediction: prediction, today: today);
  }

  // Strings are taken verbatim from PeriodCheckInBanner so the notification is a
  // remote control for the existing card, not a second source of truth.
  static CheckInNotification _notificationFor({
    required int id,
    required DateTime day,
    required CheckInPrompt prompt,
  }) {
    switch (prompt) {
      case CheckInPrompt.didItStart:
        return CheckInNotification(
          id: id,
          date: day,
          prompt: prompt,
          title: 'Period check-in',
          body: 'Your period was expected around now.',
          actionLabel: "Didn't start",
          actionId: kCheckInNoBleedingAction,
        );
      case CheckInPrompt.hasItEnded:
        return CheckInNotification(
          id: id,
          date: day,
          prompt: prompt,
          title: 'Period check-in',
          body: 'This period has run to its usual length.',
          actionLabel: 'Mark ended here',
          actionId: kCheckInNoBleedingAction,
        );
      case CheckInPrompt.none:
        // The generic daily nudge this horizon replaces (same copy as the old
        // repeating scheduleDailyLogNudge). Body-tap opens the app; no action.
        return CheckInNotification(
          id: id,
          date: day,
          prompt: prompt,
          title: 'How are you today?',
          body: 'Tap to log your flow and symptoms.',
        );
    }
  }
}
