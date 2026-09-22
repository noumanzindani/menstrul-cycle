import 'dart:convert';

import '../common/catalog.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../models/prediction.dart';
import 'bmi_service.dart';

/// How much daily history travels with a photo.
///
/// `generateContent` holds no session, so the whole context is re-sent on every
/// turn of a conversation. Ninety days is about three cycles — the minimum for a
/// before-and-after-period comparison to have more than one instance in it —
/// and is a single edit if it should be longer.
const int kContextWindowDays = 90;

/// The label for [key] in [options], or null when the key is unknown.
///
/// Unknown keys are DROPPED rather than printed. A key that outlives a catalog
/// rename would otherwise leak into the request as a raw slug.
String? _labelFor(List<TrackOption> options, String key) {
  for (final o in options) {
    if (o.key == key) return o.label;
  }
  return null;
}

List<String> _labelsFor(List<TrackOption> options, Iterable<String> keys) =>
    keys.map((k) => _labelFor(options, k)).whereType<String>().toList();

int? _ageInYears(DateTime? dob, DateTime asOf) {
  if (dob == null) return null;
  var years = asOf.year - dob.year;
  final hadBirthday =
      asOf.month > dob.month || (asOf.month == dob.month && asOf.day >= dob.day);
  if (!hadBirthday) years -= 1;
  return years < 0 ? null : years;
}

/// The standing facts about the person: profile, contraception, diagnoses,
/// goal and the signup sexual-health baseline.
///
/// Every line is omitted when its field is unanswered — never sent as null or
/// "unknown", because an absent answer and a negative answer are different
/// clinical facts. The whole block is empty when nothing has been answered.
String buildProfileBlock({
  required AppSetting settings,
  required DateTime asOf,
}) {
  final lines = <String>[];

  final age = _ageInYears(settings.dateOfBirth, asOf);
  if (age != null) lines.add('Age: $age');

  final h = settings.heightCm;
  if (h != null) lines.add('Height: ${h.toStringAsFixed(0)} cm');

  final w = settings.profileWeightKg;
  if (w != null) lines.add('Current weight: ${w.toStringAsFixed(1)} kg');

  // Emitted whole. This file must not spell the acronym itself — see the
  // body-judgement scan in test/weight_trend_service_test.dart.
  final readout = BmiService.bmiReadout(heightCm: h, weightKg: w);
  if (readout != null) lines.add(readout);

  final menarche = settings.menarcheAge;
  if (menarche != null) lines.add('Age at first period: $menarche');

  // Labelled "(self-reported)" deliberately. Until two cycles complete the app
  // has measured NOTHING about variability, and the wording is the only thing
  // separating a claim the user made from an observation the app made. An
  // unknown key drops out through [_labelFor], like every other option here.
  final regularity = settings.cycleRegularity;
  if (regularity != null) {
    final label = _labelFor(kCycleRegularityOptions, regularity);
    if (label != null) lines.add('Cycle regularity (self-reported): $label');
  }

  final contra = settings.contraceptionMethod;
  if (contra != null) {
    final label = _labelFor(kContraceptionOptions, contra);
    if (label != null) {
      final since = settings.contraceptionStartDate;
      lines.add(since == null
          ? 'Contraception: $label'
          : 'Contraception: $label, since ${_ymd(since)}');
    }
  }

  final dx = _decodeKeyList(settings.knownDiagnoses);
  final dxLabels = _labelsFor(kDiagnosisOptions, dx);
  if (dxLabels.isNotEmpty) {
    lines.add('Diagnoses already given by a clinician: ${dxLabels.join(', ')}');
  }

  final bf = settings.breastfeeding;
  if (bf != null) {
    final since = settings.breastfeedingSince;
    lines.add(bf
        ? 'Breastfeeding: yes${since == null ? '' : ', since ${_ymd(since)}'}'
        : 'Breastfeeding: no');
  }

  final pregnancy = _pregnancyLine(
      settings.pregnancyStatus, settings.pregnancyStatusDate, asOf);
  if (pregnancy != null) lines.add(pregnancy);

  final goal = _goalLabel(settings.mode);
  if (goal != null) lines.add('Goal: $goal');

  lines.addAll(_baselineLines(settings.sexualHealthBaseline));

  return lines.join('\n');
}

/// Null for "Prefer not to say", for an unknown key, and when never asked.
///
/// A birth or a loss carries how many weeks ago it was, computed here rather
/// than left to the model: date arithmetic is exactly what a model gets wrong,
/// and "postpartum, week 5" is the fact a photo reading actually hinges on.
String? _pregnancyLine(String? status, DateTime? date, DateTime asOf) {
  String when() {
    if (date == null) return 'date not given';
    final today = DateTime(asOf.year, asOf.month, asOf.day);
    final day = DateTime(date.year, date.month, date.day);
    final weeks = today.difference(day).inDays ~/ 7;
    return '${_ymd(date)} ($weeks ${weeks == 1 ? 'week' : 'weeks'} ago)';
  }

  return switch (status) {
    kPregnancyBirth => 'Gave birth: ${when()}',
    kPregnancyLoss => 'Pregnancy ended (miscarriage or termination): ${when()}',
    kPregnancyNow =>
      date == null ? 'Pregnant: yes' : 'Pregnant: yes, as of ${_ymd(date)}',
    kPregnancyNone => date == null
        ? 'Pregnant, gave birth or had a pregnancy end in the last 3 months: no'
        : 'Pregnant, gave birth or had a pregnancy end in the 3 months before '
            '${_ymd(date)}: no',
    _ => null,
  };
}

/// Null for plain cycle tracking: it is the default every row starts with, so
/// it says nothing the model would not assume anyway.
String? _goalLabel(TrackingMode mode) => switch (mode) {
      TrackingMode.track => null,
      TrackingMode.conceive => 'trying to conceive',
      TrackingMode.pregnancy => 'tracking a pregnancy',
      TrackingMode.perimenopause => 'tracking perimenopause',
    };

/// The signup sexual-health answers, as GENERAL statements.
///
/// Labelled "generally" / "ever" so the model cannot mistake them for a logged
/// day. The solo answers (frequency, ways, the free-text "Other", time to
/// satisfaction) are left out on purpose: no gynaecological signal, and the
/// most sensitive answers the app holds.
List<String> _baselineLines(String? json) {
  final b = decodeSexualBaseline(json);
  final lines = <String>[];

  if (b.history.contains(kShxNone)) {
    final asked = kSexualHistoryOptions
        .where((o) => o.key != kShxNone)
        .map((o) => o.label.toLowerCase())
        .toList();
    final last = asked.removeLast();
    lines.add('Ever experienced: none of ${asked.join(', ')} or $last');
  } else {
    final history = _labelsFor(kSexualHistoryOptions, b.history);
    if (history.isNotEmpty) lines.add('Ever experienced: ${history.join(', ')}');
  }

  final libido = b.libido == null ? null : _labelFor(kLibidoOptions, b.libido!);
  if (libido != null) lines.add('Libido, generally: $libido');

  final sex = b.sexFrequency == null
      ? null
      : _labelFor(kFrequencyOptions, b.sexFrequency!);
  if (sex != null) lines.add('Sex, generally: $sex');

  return lines;
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> _decodeKeyList(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final decoded = jsonDecode(json);
    if (decoded is List) return decoded.map((e) => e.toString()).toList();
  } catch (_) {
    // A malformed blob is treated as absent, never as an error the user sees.
  }
  return const [];
}

/// One day, rendered as a single labelled line.
///
/// [cycleDay] and [phase] are DERIVED by the caller from CycleCalculator — they
/// are not stored. That derivation is what turns a pile of dated rows into
/// something a model can reason about cyclically: "day 19, luteal - discharge:
/// creamy" answers "is this normal for me at this point" in a way a bare date
/// cannot.
///
/// Reads the reserved-prefix groups DIRECTLY. `decodeSymptoms` strips them, and
/// that stripping is deliberate — it keeps intimate data out of a printout
/// handed to a clinician. The AI context has different inclusion rules on
/// purpose, so this must never route through the PDF helpers.
String buildDayLine({
  required DailyLog log,
  int? cycleDay,
  required CyclePhase phase,
  required Map<int, String> medicationNames,
}) {
  final head = cycleDay == null
      ? '${_ymd(log.date)} (phase unknown)'
      : '${_ymd(log.date)} (day $cycleDay, ${phase.name})';

  final parts = <String>[];

  if (log.flow != null) {
    parts.add('flow: ${log.flow!.name}');
  }
  if (log.mood != null) {
    final mood = _labelFor(kMoodOptions, log.mood!);
    if (mood != null) parts.add('mood: $mood');
  }

  final symptoms = decodeSymptoms(log.symptoms)
      .map(symptomLabel)
      .where((l) => l.isNotEmpty)
      .toList();
  if (symptoms.isNotEmpty) parts.add('symptoms: ${symptoms.join(', ')}');

  void addSingle(String prefix, List<TrackOption> options, String label) {
    final key = decodeSingle(log.symptoms, prefix);
    if (key == null) return;
    final text = _labelFor(options, key);
    if (text != null) parts.add('$label: $text');
  }

  void addGroup(String prefix, List<TrackOption> options, String label) {
    final labels = _labelsFor(options, decodeGroup(log.symptoms, prefix));
    if (labels.isNotEmpty) parts.add('$label: ${labels.join(', ')}');
  }

  addSingle(kDischargeKeyPrefix, kDischargeOptions, 'discharge');
  addSingle(kSexKeyPrefix, kSexOptions, 'sexual activity');
  // libido must use decodeLibido, not decodeSingle, to handle legacy shx_high_libido
  final libidoKey = decodeLibido(log.symptoms);
  if (libidoKey != null) {
    final libidoLabel = _labelFor(kLibidoOptions, libidoKey);
    if (libidoLabel != null) parts.add('libido: $libidoLabel');
  }
  addGroup(kIntimacyKeyPrefix, kIntimacyOptions, 'solo activity');
  addGroup(kVaginalKeyPrefix, kVaginalOptions, 'vaginal');
  addGroup(kSexualHealthKeyPrefix, kSexualHealthOptions, 'sexual health');
  addGroup(kUrineKeyPrefix, kUrineOptions, 'urinary');
  addGroup(kDigestionKeyPrefix, kDigestionOptions, 'digestion');
  addGroup(kSkinKeyPrefix, kSkinOptions, 'skin');
  addGroup(kHabitKeyPrefix, kHabitOptions, 'habits');

  // 0 is the unset sentinel for every numeric metric (catalog.dart:106-112).
  // Serialising it would hand the model a confident reading of nothing.
  //
  // `weight` is the one metric here with a real unit ambiguity (kg vs lb) —
  // the profile block already says `kg` for the SAME canonical value (see
  // `buildProfileBlock`), so this line must say so too, or a model reading
  // this block alone could read it as pounds. The others (0–10 / 1–5 scales,
  // hours, glasses) have no alternate unit system to be misread as.
  for (final key in const [
    kMetricPain,
    kMetricWater,
    kMetricSleep,
    kMetricSleepQuality,
    kMetricEnergy,
    kMetricStress,
    kMetricWeight,
  ]) {
    final v = decodeNumber(log.symptoms, key);
    if (v != null && v != 0) {
      final unit = key == kMetricWeight ? ' kg' : '';
      parts.add('$key $v$unit');
    }
  }

  // Canonical Celsius (the form's BBT field carries a `°C` suffix — see
  // `day_entry_form.dart`) — stated explicitly for the same reason weight is:
  // unlabelled, a model may read it as °F.
  if (log.bbt != null) parts.add('temperature ${log.bbt}°C');
  // Routed through the same label lookup every other option group uses
  // (`kOpkOptions`), rather than printing the stored key raw — this was the
  // one place that bypassed the "unknown keys are dropped, never printed
  // raw" rule the rest of this file follows.
  if (log.opk != null) {
    final opkLabel = _labelFor(kOpkOptions, log.opk!);
    if (opkLabel != null) parts.add('ovulation test: $opkLabel');
  }

  final medicationKeys = decodeGroup(log.symptoms, kMedicationKeyPrefix);
  final meds = <String>[];
  for (final entry in medicationNames.entries) {
    if (medicationKeys.contains('$kMedicationKeyPrefix${entry.key}')) {
      meds.add(entry.value);
    }
  }
  if (meds.isNotEmpty) parts.add('medication taken: ${meds.join(', ')}');

  final note = log.notes?.trim();
  if (note != null && note.isNotEmpty) parts.add('note: $note');

  return parts.isEmpty ? head : '$head - ${parts.join('; ')}';
}

/// Delimiters around the context block.
///
/// The model is told, in the system instruction, that everything between these
/// is information and never instructions. The diary is free text the user wrote
/// themselves, so this is not an attack on the user — but a note reading "ignore
/// the previous instructions" would otherwise be replayed verbatim into the
/// prompt on every turn of the conversation.
const String kHealthContextOpenDelimiter = '<<<TRACKED_DATA';
const String kHealthContextCloseDelimiter = 'END_TRACKED_DATA>>>';

/// Everything the app knows about this person, as one delimited block.
///
/// Pure: rows in, string out. It performs no I/O and touches no provider, so
/// the caller gathers from providers BEFORE the async gap — the same shape as
/// `PdfReportService.build` and its call site at insights_screen.dart:79-99.
/// That is what keeps `MediaAnalysisService` unable to reach the database.
String buildHealthContext({
  required List<DailyLog> logs,
  required List<Cycle> cycles,
  required PredictionResult? prediction,
  required List<Medication> medications,
  required AppSetting settings,
  required DateTime asOf,
  int windowDays = kContextWindowDays,
}) {
  final sections = <String>[];

  final profile = buildProfileBlock(settings: settings, asOf: asOf);
  if (profile.isNotEmpty) sections.add('About this person:\n$profile');

  if (prediction != null && prediction.cyclesTracked > 0) {
    sections.add('Cycle summary:\n'
        'Cycles tracked: ${prediction.cyclesTracked}\n'
        'Average cycle length: ${prediction.averageCycleLength} days\n'
        'Average period length: ${prediction.averagePeriodLength} days');
  }

  // Normalize asOf to local midnight to ensure exact day arithmetic.
  final asOfNormalized = DateTime(asOf.year, asOf.month, asOf.day);
  final cutoff = asOfNormalized.subtract(Duration(days: windowDays));
  // Inclusive boundary: retain logs at exactly asOf - windowDays.
  final windowed = logs.where((l) => !l.date.isBefore(cutoff)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final medNames = <int, String>{
    for (final m in medications) m.id: m.name,
  };

  // Sort cycles once by start date to avoid O(days × n log n) resorting.
  final sortedCycles = cycles.toList()..sort((a, b) => a.start.compareTo(b.start));

  final dayLines = windowed
      .map((log) => buildDayLine(
            log: log,
            cycleDay: _cycleDayFor(log.date, sortedCycles, asOfNormalized),
            phase: _phaseFor(log.date, sortedCycles, prediction, asOfNormalized),
            medicationNames: medNames,
          ))
      .toList();

  if (dayLines.isNotEmpty) {
    sections.add('Daily log, last $windowDays days:\n${dayLines.join('\n')}');
  }

  if (sections.isEmpty) return '';
  return '$kHealthContextOpenDelimiter\n${sections.join('\n\n')}\n$kHealthContextCloseDelimiter';
}

/// How many days an OPEN (still-ongoing, `lengthDays == null`) cycle may run
/// before a date stops being attributed to it.
///
/// Without this, a user who stops logging for months has every day between
/// their last period and [asOf] folded into one ever-climbing cycle
/// ("day 137") — a number no real cycle produces. 90 mirrors the amenorrhea
/// threshold `InsightsService._flags` already flags on ("no period logged in
/// a while" at 90+ days, ACOG/FIGO-derived) — the same point at which this
/// app itself stops treating a gap as a normal continuation of a cycle rather
/// than a new, unstarted one.
const int kMaxOpenCycleDays = 90;

/// 1-based day within whichever derived cycle contains [date], or null.
///
/// A cycle runs from its start up to the day before the next cycle starts.
/// The last (open) cycle with no lengthDays runs to [asOf] — but never
/// further than [kMaxOpenCycleDays] past its own start; a date beyond that
/// ceiling is outside any cycle rather than an implausibly high day count.
/// Days before the first cycle or between cycles also return null.
///
/// Expects [cycles] to be pre-sorted by start date (caller guarantees this).
int? _cycleDayFor(DateTime date, List<Cycle> cycles, DateTime asOf) {
  for (int i = 0; i < cycles.length; i++) {
    final c = cycles[i];
    // Cycle end is the day before the next cycle starts; for the last
    // (open) cycle it's asOf, capped at the plausibility ceiling above.
    DateTime cycleEnd;
    if (i + 1 < cycles.length) {
      cycleEnd = cycles[i + 1].start.subtract(const Duration(days: 1));
    } else {
      final ceiling =
          c.start.add(const Duration(days: kMaxOpenCycleDays - 1));
      cycleEnd = asOf.isBefore(ceiling) ? asOf : ceiling;
    }
    if (!date.isBefore(c.start) && !date.isAfter(cycleEnd)) {
      return date.difference(c.start).inDays + 1;
    }
  }
  return null;
}

/// The phase for [date]. Only asOf itself can borrow the live prediction;
/// every other day falls back to bleeding-or-unknown rather than being guessed.
/// Days within a cycle's bleeding window are marked menstrual; all others unknown.
CyclePhase _phaseFor(
  DateTime date,
  List<Cycle> cycles,
  PredictionResult? prediction,
  DateTime asOf,
) {
  // Check if date falls within any cycle's bleeding window (period days).
  for (final c in cycles) {
    if (!date.isBefore(c.start) && !date.isAfter(c.end)) {
      return CyclePhase.menstrual;
    }
  }
  // Only use live prediction for asOf itself; never guess historical phases.
  if (prediction != null && _isSameDay(date, asOf)) {
    return prediction.currentPhase;
  }
  return CyclePhase.unknown;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
