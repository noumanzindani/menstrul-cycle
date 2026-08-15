import '../data/product_session_repository.dart';
import '../data/reminder_repository.dart';
import '../db/database.dart';
import 'notification_service.dart';
import 'product_timer_payload.dart';
import 'product_timer_plan.dart';

/// The write path behind the "Changed" action on a product-change notification.
///
/// Runs in a background isolate with the app possibly killed, so it opens the
/// encrypted database on its own connection (keystore → PRAGMA key) and must
/// NEVER throw: an escaping exception in a bare isolate is invisible. Failures
/// come back as `false`, and the caller leaves the notification standing as its
/// own retry affordance.
///
/// The keystore is reliably available here for a non-obvious reason: the
/// notification is posted with `visibility: secret`, so it cannot be actioned
/// before the device is unlocked.
class ProductChangeWriter {
  const ProductChangeWriter._();

  /// Swaps in a fresh product of the same kind, carrying the user's chosen
  /// duration forward, and re-arms the notification slots.
  ///
  /// Returns whether the tap was *handled* — which is not the same as "wrote
  /// something". A stale payload, or a session already ended in the foreground,
  /// is handled by doing nothing: the notification is obsolete and should be
  /// dismissed rather than left on screen inviting another tap. Only a genuine
  /// database failure returns false.
  ///
  /// [db] and [now] are injectable for tests; production passes neither.
  static Future<bool> markChanged(
    String? payload, {
    AppDatabase? db,
    DateTime? now,
  }) async {
    AppDatabase? owned;
    try {
      final database = db ?? (owned = AppDatabase());
      final repo = ProductSessionRepository(ReminderRepository(database));

      final current = await repo.get();
      // Nothing running, or this notification belongs to an earlier session:
      // handled, but deliberately inert.
      if (current == null) return true;
      if (!isStampFor(payload, current.insertedAt)) return true;

      final at = now ?? DateTime.now();
      final restarted = current.copyWith(insertedAt: at);
      await repo.start(restarted);

      // Best-effort re-arm. The write already succeeded, and the foreground app
      // reschedules on its next resume, so a failure here must not fail the tap.
      try {
        await NotificationService.applyProductTimerPlan(
          ProductTimerPlan.plan(session: restarted, now: at),
          payload: encodeSessionStamp(restarted.insertedAt),
        );
      } catch (_) {
        // Self-heals on resume.
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      await owned?.close();
    }
  }
}
