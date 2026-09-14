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

/// The standing facts about the person: profile, contraception, diagnoses.
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

  return lines.join('\n');
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
    if (v != null && v != 0) parts.add('$key $v');
  }

  if (log.bbt != null) parts.add('temperature ${log.bbt}');
  if (log.opk != null) parts.add('ovulation test: ${log.opk}');

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

  final cutoff = asOf.subtract(Duration(days: windowDays));
  final windowed = logs.where((l) => l.date.isAfter(cutoff)).toList()
    ..sort((a, b) => a.date.compareTo(b.date));

  final medNames = <int, String>{
    for (final m in medications) m.id: m.name,
  };

  final dayLines = windowed
      .map((log) => buildDayLine(
            log: log,
            cycleDay: _cycleDayFor(log.date, cycles),
            phase: _phaseFor(log.date, cycles, prediction),
            medicationNames: medNames,
          ))
      .toList();

  if (dayLines.isNotEmpty) {
    sections.add('Daily log, last $windowDays days:\n${dayLines.join('\n')}');
  }

  if (sections.isEmpty) return '';
  return '$kHealthContextOpenDelimiter\n${sections.join('\n\n')}\n$kHealthContextCloseDelimiter';
}

/// 1-based day within whichever derived cycle contains [date], or null.
int? _cycleDayFor(DateTime date, List<Cycle> cycles) {
  for (final c in cycles) {
    final end = c.lengthDays == null
        ? c.end
        : c.start.add(Duration(days: c.lengthDays! - 1));
    if (!date.isBefore(c.start) && !date.isAfter(end)) {
      return date.difference(c.start).inDays + 1;
    }
  }
  return null;
}

/// The phase for [date]. Only the CURRENT day can borrow the live prediction;
/// every other day falls back to bleeding-or-unknown rather than being guessed.
CyclePhase _phaseFor(
  DateTime date,
  List<Cycle> cycles,
  PredictionResult? prediction,
) {
  for (final c in cycles) {
    if (!date.isBefore(c.start) && !date.isAfter(c.end)) {
      return CyclePhase.menstrual;
    }
  }
  if (prediction != null && _isSameDay(date, DateTime.now())) {
    return prediction.currentPhase;
  }
  return CyclePhase.unknown;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
