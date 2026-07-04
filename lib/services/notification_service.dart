import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
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
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<void> cancel(int id) => _plugin.cancel(id: id);

  /// A repeating daily reminder at [hour]:[minute].
  static Future<void> scheduleDailyLogNudge({
    required int hour,
    required int minute,
  }) async {
    await cancel(idLogNudge);
    await _plugin.zonedSchedule(
      id: idLogNudge,
      title: 'How are you today?',
      body: 'Tap to log your flow and symptoms.',
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  /// A one-shot reminder on [date] at [hour]:[minute]. No-op if in the past.
  static Future<void> scheduleOneShot({
    required int id,
    required DateTime date,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
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
