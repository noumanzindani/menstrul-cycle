/// Puberty staging (Tanner / sexual-maturity rating), self-reported.
///
/// Two separate scales because they track two separate hormone systems:
/// - **B stage**, breast development, follows ESTROGEN from the ovaries.
/// - **P stage**, pubic hair, follows ADRENAL ANDROGENS.
///
/// Pure Dart: no Flutter import, so the AI context builder and tests can use
/// it without a widget binding.
///
/// Every key is persisted in `AppSettings` and synced, so keys are STABLE:
/// never rename one, only its label. Null in a column means NOBODY ASKED.
/// The stage questions have no opt-out: a stage must be picked. The timing
/// question keeps "Not sure", which is stored and never sent.
library;

/// One stage on the B or P scale.
class PubertyStageOption {
  const PubertyStageOption(this.key, this.stage, this.label, this.description);

  final String key;

  /// 1-5.
  final int stage;
  final String label;
  final String description;
}

const List<PubertyStageOption> kBreastStageOptions = [
  PubertyStageOption('tan_b1', 1, 'B1 · Not started',
      'No breast development yet.'),
  PubertyStageOption('tan_b2', 2, 'B2 · Breast bud',
      'A small raised bud under the nipple; the darker area around it widens.'),
  PubertyStageOption('tan_b3', 3, 'B3 · Growing',
      'Breast and the darker area grow larger as one rounded shape.'),
  PubertyStageOption('tan_b4', 4, 'B4 · Second mound',
      'The nipple and the darker area form a small mound raised above the '
          'breast.'),
  PubertyStageOption('tan_b5', 5, 'B5 · Adult',
      'Adult shape: the darker area is level with the breast again and only '
          'the nipple sticks out.'),
];

const List<PubertyStageOption> kPubicStageOptions = [
  PubertyStageOption('tan_p1', 1, 'P1 · Not started', 'No pubic hair yet.'),
  PubertyStageOption('tan_p2', 2, 'P2 · First hair',
      'A few long, fine, lightly coloured hairs, mostly along the labia.'),
  PubertyStageOption('tan_p3', 3, 'P3 · Darker',
      'Darker, coarser, curlier hair spreading thinly over the pubic bone.'),
  PubertyStageOption('tan_p4', 4, 'P4 · Nearly adult',
      'Adult-type hair covering a smaller area; none on the thighs yet.'),
  PubertyStageOption('tan_p5', 5, 'P5 · Adult',
      'Adult amount and pattern, reaching the inner thighs.'),
];

/// How the user themselves would describe the timing of their puberty.
const String kPubertyTimingEarly = 'pub_early';
const String kPubertyTimingOnTime = 'pub_on_time';
const String kPubertyTimingDelayed = 'pub_delayed';
const String kPubertyTimingDiscordant = 'pub_discordant';
const String kPubertyTimingNotSure = 'pub_not_sure';

const List<({String key, String label, String description})>
    kPubertyTimingOptions = [
  (
    key: kPubertyTimingEarly,
    label: 'Early',
    description: 'Started noticeably earlier than most people my age.',
  ),
  (
    key: kPubertyTimingOnTime,
    label: 'Around the usual time',
    description: 'About the same time as most people my age.',
  ),
  (
    key: kPubertyTimingDelayed,
    label: 'Delayed',
    description: 'Started noticeably later than most people my age.',
  ),
  (
    key: kPubertyTimingDiscordant,
    label: 'Out of step (discordant)',
    description: 'Breast growth and pubic hair started far apart, or one '
        'is well ahead of the other.',
  ),
  (key: kPubertyTimingNotSure, label: 'Not sure', description: ''),
];

/// 1-5 for a B or P key; null for an unknown key (from a newer or older
/// build) and for null.
int? pubertyStageNumber(String? key) {
  for (final o in [...kBreastStageOptions, ...kPubicStageOptions]) {
    if (o.key == key) return o.stage;
  }
  return null;
}

/// The option label for a B, P or timing key, or null when unknown.
String? pubertyLabel(String? key) {
  for (final o in [...kBreastStageOptions, ...kPubicStageOptions]) {
    if (o.key == key) return o.label;
  }
  for (final o in kPubertyTimingOptions) {
    if (o.key == key) return o.label;
  }
  return null;
}

enum PubertyFlag { early, delayed, discordant }

/// The app's OWN reading of the two stages, next to (never replacing) the
/// user's self-reported timing.
///
/// A screening label, not a diagnosis: the age cut-offs below are the
/// commonly used clinical referral points for girls, and a result outside
/// them means "worth mentioning to a doctor", nothing more.
class PubertyAssessment {
  const PubertyAssessment(this.flags);

  final Set<PubertyFlag> flags;

  bool get typical => flags.isEmpty;

  /// "Early for age", "Early for age; B and P out of step", "Typical for age".
  String get label {
    if (typical) return 'Typical for age';
    return [
      if (flags.contains(PubertyFlag.early)) 'Early for age',
      if (flags.contains(PubertyFlag.delayed)) 'Later than usual',
      if (flags.contains(PubertyFlag.discordant)) 'B and P out of step',
    ].join('; ');
  }
}

/// Youngest age (whole years) at which each stage is still within the usual
/// range. Reaching the stage YOUNGER than this is flagged early. B2 or P2
/// before 8 is the standard definition of early (precocious) puberty in
/// girls; the later stages step up a year at a time, roughly two standard
/// deviations below their average ages.
const Map<int, int> kPubertyEarliestUsualAge = {2: 8, 3: 9, 4: 10, 5: 11};

/// No breast development (B1) at 13 or older is the standard definition of
/// delayed puberty in girls. Pubic hair is allowed a year longer, because it
/// is driven by the adrenals and commonly lags a little.
const int kBreastDelayedAge = 13;
const int kPubicDelayedAge = 14;

/// Stages this many apart or more are flagged discordant.
const int kPubertyDiscordantGap = 2;

/// Null when there is nothing to assess: both stages unanswered.
///
/// Early and delayed need an age, so without [dateOfBirth] only discordance
/// can be read. [answeredOn] is when the stages were given -- the age THEN is
/// what the stages describe, not the age today.
PubertyAssessment? assessPuberty({
  required String? breastStage,
  required String? pubicStage,
  required DateTime? dateOfBirth,
  required DateTime? answeredOn,
}) {
  final b = pubertyStageNumber(breastStage);
  final p = pubertyStageNumber(pubicStage);
  if (b == null && p == null) return null;

  final flags = <PubertyFlag>{};
  final age = (dateOfBirth == null || answeredOn == null)
      ? null
      : _wholeYears(dateOfBirth, answeredOn);

  if (age != null) {
    bool early(int? stage) =>
        stage != null &&
        stage >= 2 &&
        age < kPubertyEarliestUsualAge[stage]!;
    if (early(b) || early(p)) flags.add(PubertyFlag.early);
    if ((b == 1 && age >= kBreastDelayedAge) ||
        (p == 1 && age >= kPubicDelayedAge)) {
      flags.add(PubertyFlag.delayed);
    }
  }
  if (b != null && p != null && (b - p).abs() >= kPubertyDiscordantGap) {
    flags.add(PubertyFlag.discordant);
  }
  return PubertyAssessment(flags);
}

int _wholeYears(DateTime dob, DateTime on) {
  var years = on.year - dob.year;
  if (on.month < dob.month || (on.month == dob.month && on.day < dob.day)) {
    years--;
  }
  return years;
}
