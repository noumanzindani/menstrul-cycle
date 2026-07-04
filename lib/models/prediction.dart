import 'enums.dart';

/// How much to trust a prediction, based on how many cycles are tracked and how
/// regular they are. Surfaced in the UI so we never imply false precision.
enum PredictionConfidence { none, low, medium, high }

/// Qualitative fertility level for a day — deliberately NOT a number. A
/// calendar-method estimate cannot honestly support a precise conception
/// percentage, so we bucket into coarse, non-contraceptive bands. `none` means
/// "outside the fertile window, or confidence too low to say".
enum FertilityBand { none, lower, higher, peak }

/// One projected future period (start..end inclusive). Estimate only.
class PredictedPeriod {
  const PredictedPeriod({
    required this.start,
    required this.end,
    required this.ovulation,
    required this.fertileStart,
    required this.fertileEnd,
  });

  final DateTime start;
  final DateTime end;
  final DateTime ovulation; // estimated, ≈ start − 14 (luteal)
  final DateTime fertileStart;
  final DateTime fertileEnd;

  int get lengthDays => end.difference(start).inDays + 1;
}

/// The immutable result of running [PredictionService.predict] over a user's
/// cycle history. All dates are estimates — never contraception.
class PredictionResult {
  const PredictionResult({
    required this.averageCycleLength,
    required this.cycleVariabilityDays,
    required this.averagePeriodLength,
    required this.cyclesTracked,
    required this.confidence,
    required this.lastPeriodStart,
    required this.cycleDay,
    required this.currentPhase,
    required this.nextPeriodStart,
    required this.nextPeriodWindowStart,
    required this.nextPeriodWindowEnd,
    required this.ovulationDay,
    required this.fertileWindowStart,
    required this.fertileWindowEnd,
  });

  final int averageCycleLength;
  final double cycleVariabilityDays;
  final int averagePeriodLength;

  /// Number of COMPLETE cycles (with a known length) behind the estimate.
  final int cyclesTracked;
  final PredictionConfidence confidence;

  final DateTime? lastPeriodStart;

  /// 1-based day within the current cycle (day 1 = first day of last period).
  final int? cycleDay;
  final CyclePhase currentPhase;

  final DateTime? nextPeriodStart;
  final DateTime? nextPeriodWindowStart; // start − uncertainty
  final DateTime? nextPeriodWindowEnd; // start + uncertainty

  final DateTime? ovulationDay; // current cycle estimate
  final DateTime? fertileWindowStart;
  final DateTime? fertileWindowEnd;

  bool get hasPrediction => nextPeriodStart != null;
}
