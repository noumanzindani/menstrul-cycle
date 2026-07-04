import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../common/date_utils.dart';
import '../data/reminder_repository.dart';
import '../db/database.dart';
import '../models/enums.dart';
import '../models/prediction.dart';
import '../services/notification_service.dart';

/// Manages the three smart reminders and (re)schedules the underlying local
/// notifications. Rescheduling needs the current [PredictionResult] because the
/// period/fertile reminders are anchored to predicted dates.
class ReminderProvider extends ChangeNotifier {
  ReminderProvider(this._repo);
  final ReminderRepository _repo;

  final Map<ReminderType, Reminder> _byType = {};

  Reminder? forType(ReminderType type) => _byType[type];
  bool isEnabled(ReminderType type) => _byType[type]?.enabled ?? false;

  int hourOf(ReminderType type) => _byType[type]?.hour ?? _defaultHour(type);
  int minuteOf(ReminderType type) => _byType[type]?.minute ?? 0;

  int daysBefore(ReminderType type) {
    final payload = _byType[type]?.payload;
    if (payload == null) return 2;
    try {
      final v = (jsonDecode(payload) as Map)['daysBefore'];
      if (v is int) return v;
    } catch (_) {}
    return 2;
  }

  Future<void> load() async {
    final all = await _repo.getAll();
    _byType
      ..clear()
      ..addEntries(all.map((r) => MapEntry(r.type, r)));
    notifyListeners();
  }

  Future<void> setReminder(
    ReminderType type, {
    required bool enabled,
    int? hour,
    int? minute,
    int? daysBefore,
  }) async {
    await _repo.upsert(
      type: type,
      enabled: enabled,
      hour: hour ?? hourOf(type),
      minute: minute ?? minuteOf(type),
      payload: type == ReminderType.periodSoon
          ? jsonEncode({'daysBefore': daysBefore ?? this.daysBefore(type)})
          : _byType[type]?.payload,
    );
    await load();
  }

  /// (Re)schedules all enabled reminders against [prediction]. Safe to call on
  /// startup and after any change; cancels the ones that are off.
  Future<void> reschedule(PredictionResult prediction) async {
    // Daily log nudge.
    if (isEnabled(ReminderType.logNudge)) {
      await NotificationService.scheduleDailyLogNudge(
        hour: hourOf(ReminderType.logNudge),
        minute: minuteOf(ReminderType.logNudge),
      );
    } else {
      await NotificationService.cancel(NotificationService.idLogNudge);
    }

    // Period-soon (one-shot before the predicted start).
    final nextStart = prediction.nextPeriodStart;
    if (isEnabled(ReminderType.periodSoon) && nextStart != null) {
      final d = daysBefore(ReminderType.periodSoon);
      await NotificationService.scheduleOneShot(
        id: NotificationService.idPeriodSoon,
        date: nextStart.subtract(Duration(days: d)),
        hour: hourOf(ReminderType.periodSoon),
        minute: minuteOf(ReminderType.periodSoon),
        title: 'Period expected soon',
        body: d <= 1 ? 'Your period may start tomorrow.' : 'Your period is expected in $d days.',
      );
    } else {
      await NotificationService.cancel(NotificationService.idPeriodSoon);
    }

    // Fertile-window start (rolled forward if already passed).
    var fertileStart = prediction.fertileWindowStart;
    if (isEnabled(ReminderType.fertileWindow) && fertileStart != null) {
      final today = dateOnly(DateTime.now());
      if (fertileStart.isBefore(today)) {
        fertileStart =
            fertileStart.add(Duration(days: prediction.averageCycleLength));
      }
      await NotificationService.scheduleOneShot(
        id: NotificationService.idFertile,
        date: fertileStart,
        hour: hourOf(ReminderType.fertileWindow),
        minute: minuteOf(ReminderType.fertileWindow),
        title: 'Fertile window starting',
        body: 'Your estimated fertile window begins around today.',
      );
    } else {
      await NotificationService.cancel(NotificationService.idFertile);
    }
  }

  int _defaultHour(ReminderType type) =>
      type == ReminderType.logNudge ? 20 : 9;
}
