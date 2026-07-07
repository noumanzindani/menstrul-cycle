import 'package:health/health.dart';

import '../common/date_utils.dart';
import '../data/daily_log_repository.dart';

/// One temperature reading pulled from the platform health store. Kept as a
/// plain record (not the plugin's `HealthDataPoint`) so all the merge logic
/// below is pure and unit-testable without the native channel.
typedef TemperatureSample = ({DateTime time, double celsius});

/// How many days the import reaches back by default.
const int _defaultLookbackDays = 90;

/// Outcome of a full import run, so the UI can distinguish "no Health Connect"
/// from "permission denied" from "imported N".
enum HealthImportStatus { ok, unavailable, permissionDenied, error }

class HealthImportResult {
  const HealthImportResult({required this.imported, required this.skipped});

  /// Days newly filled with an imported BBT.
  final int imported;

  /// Days left untouched because they already had a (hand-entered) BBT.
  final int skipped;
}

class HealthImportOutcome {
  const HealthImportOutcome(this.status, [this.result]);
  final HealthImportStatus status;
  final HealthImportResult? result;
}

/// Imports basal body temperature from Google Health Connect (Android) or Apple
/// HealthKit (iOS) into the local log. This is an ON-DEVICE OS API — reads are
/// local IPC, never network — so it upholds the app's no-backend / no-INTERNET
/// thesis. Only body temperature is imported (it feeds the symptothermal BBT
/// chart); nothing is ever written back to the health store.
class HealthImportService {
  HealthImportService({Health? health}) : _health = health ?? Health();
  final Health _health;

  static const List<HealthDataType> _types = [HealthDataType.BODY_TEMPERATURE];

  // ---- Pure, unit-tested core -------------------------------------------

  /// Collapses many readings into one BBT per calendar day, keeping the
  /// EARLIEST reading of each day — basal temperature is the waking value, so
  /// the first sample after midnight is the best proxy.
  static Map<DateTime, double> earliestPerDay(List<TemperatureSample> samples) {
    final byDay = <DateTime, TemperatureSample>{};
    for (final s in samples) {
      final day = dateOnly(s.time);
      final current = byDay[day];
      if (current == null || s.time.isBefore(current.time)) {
        byDay[day] = s;
      }
    }
    return {for (final e in byDay.entries) e.key: e.value.celsius};
  }

  /// Writes each day's earliest reading into [repo] non-destructively, never
  /// overwriting a hand-entered BBT. Returns how many days were filled vs
  /// skipped. Pure with respect to the platform channel (takes raw samples).
  static Future<HealthImportResult> applyTemperatureSamples({
    required List<TemperatureSample> samples,
    required DailyLogRepository repo,
  }) async {
    final byDay = earliestPerDay(samples);
    var imported = 0;
    var skipped = 0;
    for (final entry in byDay.entries) {
      final wrote = await repo.setBbtIfEmpty(date: entry.key, bbt: entry.value);
      if (wrote) {
        imported++;
      } else {
        skipped++;
      }
    }
    return HealthImportResult(imported: imported, skipped: skipped);
  }

  // ---- Native orchestration (device-only; not unit-tested) --------------

  /// Runs the full import: checks availability, requests read permission, fetches
  /// the last [lookbackDays] of body-temperature data, and merges it in. The
  /// platform calls here only compile/run on a real device build, mirroring how
  /// notifications/ads isolate their plugin channels.
  Future<HealthImportOutcome> importTemperatures({
    required DailyLogRepository repo,
    int lookbackDays = _defaultLookbackDays,
    DateTime? now,
  }) async {
    try {
      await _health.configure();
      if (!await _health.isHealthConnectAvailable()) {
        return const HealthImportOutcome(HealthImportStatus.unavailable);
      }
      final granted = await _health.requestAuthorization(
        _types,
        permissions: const [HealthDataAccess.READ],
      );
      if (!granted) {
        return const HealthImportOutcome(HealthImportStatus.permissionDenied);
      }

      final end = now ?? DateTime.now();
      final start = end.subtract(Duration(days: lookbackDays));
      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: start,
        endTime: end,
      );

      final result = await applyTemperatureSamples(
        samples: _toSamples(points),
        repo: repo,
      );
      return HealthImportOutcome(HealthImportStatus.ok, result);
    } catch (_) {
      return const HealthImportOutcome(HealthImportStatus.error);
    }
  }

  /// Extracts numeric °C samples from the plugin's data points, dropping any
  /// non-numeric values defensively.
  static List<TemperatureSample> _toSamples(List<HealthDataPoint> points) {
    final samples = <TemperatureSample>[];
    for (final p in points) {
      final v = p.value;
      if (v is NumericHealthValue) {
        samples.add((time: p.dateFrom, celsius: v.numericValue.toDouble()));
      }
    }
    return samples;
  }
}
