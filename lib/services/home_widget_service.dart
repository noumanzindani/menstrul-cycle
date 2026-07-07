import 'package:home_widget/home_widget.dart';

import '../common/date_utils.dart';
import '../models/enums.dart';
import '../models/prediction.dart';
import 'pregnancy_service.dart';

/// The two lines shown on the home-screen widget: a big [value] and a small
/// [caption] beneath it. Value-equality so the updater can skip redundant pushes.
class HomeWidgetData {
  const HomeWidgetData({required this.value, required this.caption});
  final String value;
  final String caption;

  @override
  bool operator ==(Object other) =>
      other is HomeWidgetData &&
      other.value == value &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(value, caption);
}

/// Pure: turns the current prediction/mode into the widget's glanceable text.
/// Pregnancy shows gestational weeks (period predictions are suppressed and a
/// "log your period" prompt would be wrong there); otherwise it counts down to
/// the next period, mirroring the Home card's phrasing.
HomeWidgetData buildHomeWidgetData({
  required PredictionResult prediction,
  required TrackingMode mode,
  DateTime? pregnancyStartDate,
  DateTime? now,
}) {
  final today = dateOnly(now ?? DateTime.now());

  if (mode == TrackingMode.pregnancy && pregnancyStartDate != null) {
    final ga = PregnancyService.gestationalAge(pregnancyStartDate, asOf: today);
    return HomeWidgetData(value: 'Week ${ga.weeks}', caption: 'of pregnancy');
  }

  final next = prediction.nextPeriodStart;
  if (!prediction.hasPrediction || next == null) {
    return const HomeWidgetData(value: '—', caption: 'Tap to log your period');
  }

  final start = dateOnly(next);
  final windowEnd =
      dateOnly(prediction.nextPeriodWindowEnd ?? next);
  final days = daysBetween(today, start);

  if (windowEnd.isBefore(today)) {
    return const HomeWidgetData(value: 'Late', caption: 'Period may be late');
  }
  if (days <= 0) {
    return const HomeWidgetData(
        value: 'Today', caption: 'Period may start today');
  }
  if (days == 1) {
    return const HomeWidgetData(value: '1', caption: 'day to your period');
  }
  return HomeWidgetData(value: '$days', caption: 'days to your period');
}

/// Pushes [HomeWidgetData] to the native home-screen widget. Device-only: the
/// method-channel calls throw on the host test VM / unsupported platforms, so
/// everything is swallowed (mirrors how notifications isolate their plugin).
class HomeWidgetService {
  const HomeWidgetService._();

  /// Must match the Android provider class + the iOS widget `kind`.
  static const String _androidProvider =
      'com.example.menstrul_track.LunaWidgetProvider';
  static const String _iosWidgetName = 'LunaWidget';

  static Future<void> push(HomeWidgetData data) async {
    try {
      await HomeWidget.saveWidgetData<String>('value', data.value);
      await HomeWidget.saveWidgetData<String>('caption', data.caption);
      await HomeWidget.updateWidget(
        qualifiedAndroidName: _androidProvider,
        iOSName: _iosWidgetName,
      );
    } catch (_) {
      // No widget host (tests, desktop, permission off) — nothing to update.
    }
  }
}
