import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/prediction_service.dart';

/// The single recompute both the foreground (main.dart ProxyProvider) and the
/// background isolate (CheckInWriter) run: logs + the tracking mode -> a
/// prediction, with the mode-specific health suppressions applied in ONE place
/// so the two callers can never drift apart.
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

  // `count` regular 5-day periods, `cycleLen` apart, from `firstStart`.
  List<DailyLog> bleedingCycles(
    DateTime firstStart, {
    required int count,
    int cycleLen = 28,
    int periodLen = 5,
  }) {
    final logs = <DailyLog>[];
    var start = firstStart;
    for (var c = 0; c < count; c++) {
      for (var d = 0; d < periodLen; d++) {
        logs.add(log(start.add(Duration(days: d)), flow: FlowIntensity.medium));
      }
      start = start.add(Duration(days: cycleLen));
    }
    return logs;
  }

  final logs = bleedingCycles(DateTime(2026, 1, 1), count: 6);
  final asOf = DateTime(2026, 1, 1).add(const Duration(days: 28 * 5));

  test('track mode: derives cycles from logs and predicts a next period', () {
    final r = PredictionService.predictFromLogs(
      logs: logs,
      mode: TrackingMode.track,
      cycleLength: 28,
      periodLength: 5,
      asOf: asOf,
    );
    expect(r.hasPrediction, isTrue);
    expect(r.confidence, isNot(PredictionConfidence.none));
  });

  test('pregnancy mode: suppresses all period/fertility prediction', () {
    // Even with a rich bleeding history, pregnancy shows no next-period estimate.
    final r = PredictionService.predictFromLogs(
      logs: logs,
      mode: TrackingMode.pregnancy,
      cycleLength: 28,
      periodLength: 5,
      asOf: asOf,
    );
    expect(r.hasPrediction, isFalse);
  });

  test('perimenopause mode: caps confidence to low (suppresses fertility)', () {
    final r = PredictionService.predictFromLogs(
      logs: logs,
      mode: TrackingMode.perimenopause,
      cycleLength: 28,
      periodLength: 5,
      asOf: asOf,
    );
    expect(r.confidence, PredictionConfidence.low);
  });
}
