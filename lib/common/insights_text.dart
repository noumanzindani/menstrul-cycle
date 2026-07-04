import '../models/enums.dart';
import '../models/prediction.dart';

/// Human, supportive, non-diagnostic copy for phases and confidence. Tone is
/// deliberately calm — this app must never alarm.
extension CyclePhaseText on CyclePhase {
  String get label => switch (this) {
        CyclePhase.menstrual => 'Menstrual phase',
        CyclePhase.follicular => 'Follicular phase',
        CyclePhase.ovulatory => 'Fertile phase',
        CyclePhase.luteal => 'Luteal phase',
        CyclePhase.unknown => 'Getting started',
      };

  String get description => switch (this) {
        CyclePhase.menstrual =>
          'Your period. Hormones are at their lowest — rest and iron-rich '
              'food can help.',
        CyclePhase.follicular =>
          'After your period. Estrogen rises and energy often climbs.',
        CyclePhase.ovulatory =>
          'Around ovulation — the most fertile days of your cycle.',
        CyclePhase.luteal =>
          'After ovulation. PMS symptoms can show up in the days before your '
              'period.',
        CyclePhase.unknown =>
          'Log a few periods and personalized insights will appear here.',
      };
}

extension ConfidenceText on PredictionConfidence {
  String get label => switch (this) {
        PredictionConfidence.none => 'Not enough data yet',
        PredictionConfidence.low => 'Low confidence',
        PredictionConfidence.medium => 'Medium confidence',
        PredictionConfidence.high => 'High confidence',
      };

  String get hint => switch (this) {
        PredictionConfidence.none =>
          'Based on a typical 28-day cycle — log a period to personalize.',
        PredictionConfidence.low =>
          'Your cycles vary, so this is a rough estimate.',
        PredictionConfidence.medium => 'Getting more accurate as you log.',
        PredictionConfidence.high => 'Based on your regular cycle history.',
      };
}
