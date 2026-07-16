import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
import '../models/prediction.dart';
import 'check_in_notifications.dart';

/// Thin wrapper over flutter_local_notifications. Everything is local — no FCM,
/// no server. Uses INEXACT alarms (a few minutes' drift is fine for cycle
/// reminders) so no exact-alarm permission is required.
class NotificationService {
  const NotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // Stable notification IDs, one per reminder kind.
  static const int idLogNudge = 1001;
  static const int idPeriodSoon = 1002;
  static const int idFertile = 1003;

  /// Medication reminders get IDs offset from this base by the medication row id
  /// (which is > 0), so they never collide with the fixed cycle-reminder IDs.
  static const int idMedicationBase = 2000;
  static int medicationNotificationId(int medicationId) =>
      idMedicationBase + medicationId;

  /// Custom reminders get IDs offset from this base by the reminder row id.
  static const int idCustomBase = 3000;
  static int customNotificationId(int reminderId) => idCustomBase + reminderId;

  /// The iOS category that carries the one-tap check-in action. On Android the
  /// action + label ride on each notification; on iOS the category (and its
  /// single generic action title) is registered once at init.
  static const String _checkInCategory = 'checkin';

  static Future<void> init({
    void Function(NotificationResponse)? onForegroundResponse,
    void Function(NotificationResponse)? onBackgroundResponse,
  }) async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwin = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          _checkInCategory,
          actions: [
            DarwinNotificationAction.plain(kCheckInNoBleedingAction, 'Confirm'),
          ],
        ),
      ],
    );
    await _plugin.initialize(
      settings: InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: onBackgroundResponse,
    );
    _ready = true;
  }

  /// Ask for notification permission. Returns true if granted (or not required).
  static Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'cycle_reminders',
      'Cycle reminders',
      channelDescription: 'Period, fertile-window and daily-log reminders',
      importance: Importance.high,
      priority: Priority.high,
      // Cycle state must NEVER land on the lock screen — roommates, partners,
      // parents, coercive control. `secret` keeps the notification out of the
      // lock screen entirely (Android's default `private` only hides it if the
      // user separately enabled "hide sensitive content", which most don't); it
      // still shows in the shade after unlock, which is where the one-tap win
      // lives. As a bonus, an only-answerable-after-unlock notification means
      // the keystore is always available when the background writer runs.
      visibility: NotificationVisibility.secret,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static const _medDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'medication_reminders',
      'Medication reminders',
      channelDescription: 'Reminders to take your medication or birth control',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  // Every plugin-touching method is a no-op until [init] has run. On device
  // main() awaits init() before runApp (and the background isolate awaits it in
  // handleCheckInResponse), so this only bites under `flutter test`, where the
  // plugin's platform instance is never initialised — the same "device-only,
  // guarded" stance HomeWidgetService takes.
  static Future<void> cancel(int id) async {
    if (!_ready) return;
    await _plugin.cancel(id: id);
  }

  /// Cancels every scheduled notification (used by "delete all my data").
  static Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  /// A repeating daily reminder at [hour]:[minute] with a custom id/title/body.
  static Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    NotificationDetails details = _details,
  }) async {
    if (!_ready) return;
    await cancel(id);
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  /// (Re)schedules the precomputed check-in horizon: one one-shot per day for
  /// the next [CheckInHorizon.horizonDays] days at [hour]:[minute], each carrying
  /// the right question (or the generic nudge) and — for the check-in days — the
  /// one-tap action. This REPLACES the old repeating `scheduleDailyLogNudge`;
  /// [idLogNudge] is retired here so a nudge left by a previous install version
  /// can't fire alongside the horizon and double-notify.
  ///
  /// The horizon owns the whole daily slot, so every slot is cancelled first and
  /// only the planned days rescheduled. Gated on [logNudgeEnabled] (the existing
  /// log-nudge toggle) — off means the slot is cleared and nothing scheduled.
  static Future<void> rescheduleHorizon({
    required bool logNudgeEnabled,
    required int hour,
    required int minute,
    required List<DailyLog> logs,
    required PredictionResult prediction,
    DateTime? today,
  }) async {
    if (!_ready) return;
    await cancel(idLogNudge); // retire the pre-horizon repeating nudge
    for (var i = 0; i < CheckInHorizon.horizonDays; i++) {
      await cancel(CheckInHorizon.idCheckInBase + i);
    }
    final horizon = CheckInHorizon.planIfEnabled(
      logNudgeEnabled: logNudgeEnabled,
      logs: logs,
      prediction: prediction,
      today: today ?? DateTime.now(),
    );
    for (final n in horizon) {
      await _scheduleCheckIn(n: n, hour: hour, minute: minute);
    }
  }

  /// Schedules ONE day's check-in one-shot. The one-tap action uses
  /// `cancelNotification: false` so the notification is dismissed by the handler
  /// only after a SUCCESSFUL write — a failed write leaves the question standing
  /// as its own retry affordance. The answered day rides in the payload.
  static Future<void> _scheduleCheckIn({
    required CheckInNotification n,
    required int hour,
    required int minute,
  }) async {
    final when = _oneShotInstance(n.date, hour, minute);
    if (when == null) return; // that day/time is already past
    final android = AndroidNotificationDetails(
      'cycle_reminders',
      'Cycle reminders',
      channelDescription: 'Period, fertile-window and daily-log reminders',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.secret,
      actions: n.hasAction
          ? [
              AndroidNotificationAction(
                n.actionId!,
                n.actionLabel!,
                cancelNotification: false,
                showsUserInterface: false,
              ),
            ]
          : null,
    );
    final darwin = DarwinNotificationDetails(
      categoryIdentifier: n.hasAction ? _checkInCategory : null,
    );
    await _plugin.zonedSchedule(
      id: n.id,
      title: n.title,
      body: n.body,
      scheduledDate: when,
      notificationDetails: NotificationDetails(android: android, iOS: darwin),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: encodeCheckInPayload(n.date),
    );
  }

  /// The [date] at [hour]:[minute] in local tz, or null if already in the past.
  static tz.TZDateTime? _oneShotInstance(DateTime date, int hour, int minute) {
    final when = tz.TZDateTime(
        tz.local, date.year, date.month, date.day, hour, minute);
    return when.isAfter(tz.TZDateTime.now(tz.local)) ? when : null;
  }

  /// A daily medication / birth-control reminder for [name].
  static Future<void> scheduleMedication({
    required int medicationId,
    required int hour,
    required int minute,
    required String name,
  }) =>
      scheduleDaily(
        id: medicationNotificationId(medicationId),
        hour: hour,
        minute: minute,
        title: 'Medication reminder',
        body: 'Time to take $name.',
        details: _medDetails,
      );

  static Future<void> cancelMedication(int medicationId) =>
      cancel(medicationNotificationId(medicationId));

  /// A daily custom reminder with a user-provided [title].
  static Future<void> scheduleCustom({
    required int reminderId,
    required int hour,
    required int minute,
    required String title,
  }) =>
      scheduleDaily(
        id: customNotificationId(reminderId),
        hour: hour,
        minute: minute,
        title: title,
        body: 'Reminder from LunaTrack',
      );

  static Future<void> cancelCustom(int reminderId) =>
      cancel(customNotificationId(reminderId));

  /// A one-shot reminder on [date] at [hour]:[minute]. No-op if in the past.
  static Future<void> scheduleOneShot({
    required int id,
    required DateTime date,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    await cancel(id);
    final when =
        tz.TZDateTime(tz.local, date.year, date.month, date.day, hour, minute);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
