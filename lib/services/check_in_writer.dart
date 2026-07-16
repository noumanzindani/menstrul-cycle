import '../data/daily_log_repository.dart';
import '../data/reminder_repository.dart';
import '../data/settings_repository.dart';
import '../db/database.dart';
import '../models/enums.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../services/prediction_service.dart';

/// The single shared write path behind the one-tap check-in — used by the
/// notification action handler today, and (Phase B) the home-widget button.
///
/// It runs in a background isolate with the app possibly killed, so it opens the
/// encrypted DB on its OWN connection (keystore → PRAGMA key), writes, and then
/// best-effort refreshes the horizon + widget. It must NEVER throw: an escaping
/// exception in a bare background isolate is invisible, so everything is caught
/// and reported as a bool the caller uses to decide whether to dismiss the
/// notification.
class CheckInWriter {
  const CheckInWriter._();

  /// Records a confirmed no-bleeding day for [date] (both one-tap answers,
  /// "Didn't start" and "Mark ended here", collapse to `FlowIntensity.none`).
  ///
  /// Returns true iff the write path completed without throwing — whether or not
  /// a row was newly written. An already-answered day (a flow already logged) is
  /// still a success: the log IS the answer, so the notification should still be
  /// dismissed. Returns false only when the DB path itself failed, leaving the
  /// notification standing as its own retry affordance.
  static Future<bool> answerNoBleeding(DateTime date) async {
    AppDatabase? db;
    try {
      db = AppDatabase(); // opens the encrypted file on a second connection
      await DailyLogRepository(db)
          .setFlowIfEmpty(date: date, flow: FlowIntensity.none);
      await _refresh(db); // keep horizon + widget fresh; best-effort
      return true;
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  /// Recompute the horizon + widget from the just-written state. Isolated in its
  /// own try/catch: the user's answer already succeeded, and the foreground app
  /// re-runs this on its next resume, so a failure here must not fail the write.
  static Future<void> _refresh(AppDatabase db) async {
    try {
      final logs = await DailyLogRepository(db).getAll();
      final settings = await SettingsRepository(db).get();
      final prediction = PredictionService.predictFromLogs(
        logs: logs,
        mode: settings.mode,
        cycleLength: settings.defaultCycleLength,
        periodLength: settings.defaultPeriodLength,
      );

      final logNudge =
          await ReminderRepository(db).getByType(ReminderType.logNudge);
      await NotificationService.rescheduleHorizon(
        logNudgeEnabled: logNudge?.enabled ?? false,
        hour: logNudge?.hour ?? 20,
        minute: logNudge?.minute ?? 0,
        logs: logs,
        prediction: prediction,
      );

      await HomeWidgetService.push(buildHomeWidgetData(
        prediction: prediction,
        mode: settings.mode,
        pregnancyStartDate: settings.pregnancyStartDate,
      ));
    } catch (_) {
      // Best-effort refresh; the foreground app self-heals on next resume.
    }
  }
}
