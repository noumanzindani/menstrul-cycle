import '../models/product_session.dart';

/// The action id delivered to the handler when the user taps "Changed" on a
/// product-change notification. The session it answers rides in the payload, so
/// a notification left over from an earlier session can be recognised and
/// ignored rather than ending the one running now.
const String kProductChangedAction = 'product_changed';

/// The button label. Deliberately says nothing about what was changed.
const String kProductChangedLabel = 'Changed';

/// Elapsed time as "4h 20m" / "45m" / "12h". Floors to the minute so the
/// display never runs ahead of reality, and clamps negatives so a clock skew
/// cannot render "-3m".
String formatElapsed(Duration d) {
  final total = d.inMinutes < 0 ? 0 : d.inMinutes;
  final hours = total ~/ 60;
  final minutes = total % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// Zero-padded 24-hour wall clock, e.g. "09:14".
String formatClock(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// One fully-resolved slot in the plan: id, fire time, and the copy baked in at
/// schedule time. A value object with no plugin dependency, so the planner
/// stays unit-testable.
class ProductTimerNotification {
  const ProductTimerNotification({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime when;
  final String title;
  final String body;
}

/// Precomputes the notification slots for an in-progress [ProductSession].
///
/// This is the pure half; handing the plan to `flutter_local_notifications`
/// lives in `NotificationService`. Same split as [CheckInHorizon], and for the
/// same reason: the impure half is untestable off-device, so everything worth
/// asserting has to live on this side of the line.
///
/// Two slots, never more. The second is **delivery redundancy, not a nag** —
/// every alarm in this app is deliberately inexact, so a single dropped
/// notification would mean the feature silently did nothing on the one night it
/// mattered. Repeat-nagging a user (many of whom are teenagers) about intimate
/// hygiene is a separate thing, and it is not what this is.
class ProductTimerPlan {
  const ProductTimerPlan._();

  /// Fires at `insertedAt + interval`.
  static const int idDue = 5000;

  /// Fires [followUpDelay] later. 1001-1003 are the fixed cycle reminders,
  /// 2000+ medications, 3000+ custom reminders and 4000-4013 the check-in
  /// horizon, so 5000+ is the first free base.
  static const int idFollowUp = 5001;

  static const List<int> allIds = [idDue, idFollowUp];

  /// Android rate-limits `setAndAllowWhileIdle` — what
  /// `AndroidScheduleMode.inexactAllowWhileIdle` resolves to — to roughly one
  /// wakeup per 9-15 minutes per app. Slots closer than this are silently
  /// deferred into the previous one's shadow, so the follow-up would never
  /// arrive. Any future change to [followUpDelay] must keep clearing this.
  static const Duration minSlotSpacing = Duration(minutes: 15);

  static const Duration followUpDelay = Duration(minutes: 30);

  /// Fixed and deliberately uninformative. The notification is `secret`, but
  /// that is not guaranteed across Wear OS bridging, Phone Link mirroring or
  /// Notification History — so the title must be harmless wherever it surfaces.
  static const String title = 'LunaTrack';

  static List<ProductTimerNotification> plan({
    required ProductSession session,
    required DateTime now,
  }) {
    final due = session.dueAt;
    final followUp = due.add(followUpDelay);
    return [
      if (due.isAfter(now)) _slot(idDue, due, session, session.interval),
      if (followUp.isAfter(now))
        _slot(idFollowUp, followUp, session, session.interval + followUpDelay),
    ];
  }

  /// The plan to actually schedule. Returns [] when the timer is off or no
  /// session is running, so a caller cancels every slot and schedules nothing —
  /// the plan never resurrects a reminder the user ended.
  static List<ProductTimerNotification> planIfEnabled({
    required bool enabled,
    required ProductSession? session,
    required DateTime now,
  }) {
    if (!enabled || session == null) return const [];
    return plan(session: session, now: now);
  }

  /// Copy is elapsed-since-start only. It counts **up**, names no product, and
  /// states no deadline: a countdown would manufacture a danger moment the app
  /// cannot locate, on a value it does not know (absorbency, flow, individual
  /// risk). The product word is opt-in and lives elsewhere.
  static ProductTimerNotification _slot(
    int id,
    DateTime when,
    ProductSession session,
    Duration elapsedAtFire,
  ) =>
      ProductTimerNotification(
        id: id,
        when: when,
        title: title,
        body: "It's been ${formatElapsed(elapsedAtFire)} "
            "since ${formatClock(session.insertedAt)}.",
      );
}
