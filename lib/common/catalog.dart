import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../theme/app_theme.dart';

/// A selectable tracking option (symptom or mood). Keys are STABLE identifiers
/// persisted in the DB — never rename a key, only its [label].
class TrackOption {
  const TrackOption(this.key, this.label);
  final String key;
  final String label;
}

const List<TrackOption> kSymptomOptions = [
  TrackOption('cramps', 'Cramps'),
  TrackOption('headache', 'Headache'),
  TrackOption('bloating', 'Bloating'),
  TrackOption('tender_breasts', 'Tender breasts'),
  TrackOption('acne', 'Acne'),
  TrackOption('fatigue', 'Fatigue'),
  TrackOption('nausea', 'Nausea'),
  TrackOption('backache', 'Back pain'),
  TrackOption('cravings', 'Cravings'),
  TrackOption('insomnia', 'Trouble sleeping'),
  TrackOption('diarrhea', 'Diarrhea'),
  TrackOption('constipation', 'Constipation'),
  TrackOption('dizziness', 'Dizziness'),
  TrackOption('discharge', 'Discharge'),
  TrackOption('migraine', 'Migraine'),
  TrackOption('hot_flashes', 'Hot flashes'),
  TrackOption('night_sweats', 'Night sweats'),
  TrackOption('pelvic_pain', 'Pelvic pain'),
  TrackOption('leg_pain', 'Leg pain'),
  TrackOption('swelling', 'Swelling'),
  TrackOption('fever', 'Fever'),
  TrackOption('chills', 'Chills'),
  // Heavy-bleeding red flags. DELIBERATELY plain, un-prefixed symptom keys and
  // not a reserved group: a clinician asks about these directly, so they must
  // ride [decodeSymptoms] into the doctor report exactly like cramps do. Every
  // reserved prefix in this file is excluded from that report by default, which
  // is the opposite of what these two are for.
  //
  // `flooding` already exists as a FlowIntensity, but it describes the flow
  // LEVEL. Neither of these is a level: a single large clot can appear in an
  // otherwise ordinary day, and "soaking hourly" is a rate the intensity scale
  // has no way to say.
  TrackOption(kSymptomLargeClots, 'Large clots (2.5 cm or more)'),
  TrackOption(kSymptomSoakingHourly, 'Soaking through hourly'),
];

/// Clots at or above roughly a 10p / quarter coin, and soaking through a pad or
/// tampon every hour — the two heavy-bleeding markers clinicians screen for.
/// Named constants because both the catalog entry and the red-flag surfacing
/// read them, and a typo in one string would silently sever the two.
const String kSymptomLargeClots = 'clots_large';
const String kSymptomSoakingHourly = 'soaking_hourly';

const List<TrackOption> kMoodOptions = [
  TrackOption('calm', 'Calm'),
  TrackOption('happy', 'Happy'),
  TrackOption('energetic', 'Energetic'),
  TrackOption('sensitive', 'Sensitive'),
  TrackOption('sad', 'Low'),
  TrackOption('anxious', 'Anxious'),
  TrackOption('irritable', 'Irritable'),
  TrackOption('angry', 'Angry'),
];

/// Namespace prefixes for keys stored inside the day-tags JSON that are NOT
/// plain symptoms. Each groups a set of keys and is EXCLUDED from the doctor
/// PDF's symptom frequency by default (they are sensitive or non-symptom),
/// mirroring how sexual-activity data has always been kept separate.
const String kSexKeyPrefix = 'sex_'; // sexual activity (single-select)
const String kDischargeKeyPrefix = 'cm_'; // cervical mucus / discharge (single)
const String kVaginalKeyPrefix = 'vag_'; // vaginal-health flags
const String kSexualHealthKeyPrefix = 'shx_'; // sexual-health flags
const String kHabitKeyPrefix = 'habit_'; // lifestyle habits
const String kMedicationKeyPrefix = 'med_'; // per-day medication intake
const String kUrineKeyPrefix = 'urn_'; // urinary symptoms
const String kDigestionKeyPrefix = 'dig_'; // digestion / bowel
const String kSkinKeyPrefix = 'skin_'; // skin & hair
const String kIntimacyKeyPrefix = 'slf_'; // solo sexual activity
const String kLibidoKeyPrefix = 'lbd_'; // libido level (single-select)

/// All reserved (non-symptom) prefixes. [decodeSymptoms] skips these so grouped
/// and sensitive data never surfaces in the symptom chips or the doctor PDF.
const List<String> kReservedTagPrefixes = [
  kSexKeyPrefix,
  kDischargeKeyPrefix,
  kVaginalKeyPrefix,
  kSexualHealthKeyPrefix,
  kHabitKeyPrefix,
  kMedicationKeyPrefix,
  kUrineKeyPrefix,
  kDigestionKeyPrefix,
  kSkinKeyPrefix,
  kIntimacyKeyPrefix,
  kLibidoKeyPrefix,
];

/// Numeric day-metric keys (stored as real JSON numbers, not booleans, in the
/// same day-tags blob). They never satisfy the `== true` symptom check, so they
/// are naturally excluded from [decodeSymptoms].
const String kMetricPain = 'pain'; // 0–10
const String kMetricWater = 'water'; // glasses
const String kMetricSleep = 'sleep'; // hours
const String kMetricEnergy = 'energy'; // 1–5
const String kMetricStress = 'stress'; // 1–5
const String kMetricSleepQuality = 'sleep_quality'; // 1–5
const String kMetricWeight = 'weight'; // canonical KILOGRAMS, one decimal

/// Weight unit preference values for `AppSettings.weightUnit`.
const String kWeightUnitKg = 'kg';
const String kWeightUnitLb = 'lb';

/// Plausible-human bounds, checked in canonical kg. A fat-fingered entry would
/// otherwise distort the weight trend chart's y-axis permanently.
const double kMinWeightKg = 20.0;
const double kMaxWeightKg = 350.0;

const double _kgPerLb = 0.45359237;

double lbToKg(double lb) => lb * _kgPerLb;
double kgToLb(double kg) => kg / _kgPerLb;

/// Parses user input in [unit] into canonical kg, or null when it is blank,
/// unparseable, or outside [kMinWeightKg]..[kMaxWeightKg]. The range is applied
/// AFTER conversion so the same rule holds in both units.
double? parseWeightToKg(String input, String unit) {
  final parsed = double.tryParse(input.trim());
  if (parsed == null) return null;
  final kg = unit == kWeightUnitLb ? lbToKg(parsed) : parsed;
  if (kg < kMinWeightKg || kg > kMaxWeightKg) return null;
  return kg;
}

/// Formats canonical [kg] for display in [unit], to one decimal place and
/// WITHOUT a unit suffix (the field renders the suffix itself).
String formatWeightFromKg(double kg, String unit) {
  final shown = unit == kWeightUnitLb ? kgToLb(kg) : kg;
  return shown.toStringAsFixed(1);
}

/// Plausible-human bounds, checked in canonical cm. Height is a profile fact
/// nothing else ever corrects, so a fat-fingered entry would sit in the doctor
/// report until the user noticed it themselves.
const double kMinHeightCm = 80.0;
const double kMaxHeightCm = 250.0;

const double _cmPerInch = 2.54;

double inchToCm(double inch) => inch * _cmPerInch;
double cmToInch(double cm) => cm / _cmPerInch;

/// Feet-and-inches input, e.g. `5'5"`, `5' 5`, `5ft 5in`, or a bare `5'`. The
/// inches part and both unit marks are optional; `\x22` is the double quote,
/// spelled as an escape so the pattern itself can stay a raw string.
final RegExp _feetInchesPattern = RegExp(
  r"^(\d+(?:\.\d+)?)\s*(?:'|ft|feet)\.?\s*"
  r"(?:(\d+(?:\.\d+)?)\s*(?:\x22|''|in|inch|inches)?\.?)?$",
  caseSensitive: false,
);

/// Parses user input in [unit] into canonical cm, or null when it is blank,
/// unparseable, or outside [kMinHeightCm]..[kMaxHeightCm]. The range is applied
/// AFTER conversion so the same rule holds in both units.
///
/// Height rides the EXISTING weight-unit preference rather than a column of its
/// own: [kWeightUnitKg] means the input is centimetres, [kWeightUnitLb] means
/// feet and inches (or a bare number of inches).
double? parseHeightToCm(String input, String unit) {
  final text = input.trim();
  final double cm;
  if (unit == kWeightUnitLb) {
    final match = _feetInchesPattern.firstMatch(text);
    if (match != null) {
      final feet = double.parse(match.group(1)!);
      final inches = double.tryParse(match.group(2) ?? '') ?? 0.0;
      cm = inchToCm(feet * 12 + inches);
    } else {
      // No feet mark: a bare number is inches. Someone who types a centimetre
      // value here lands far above the maximum and is REFUSED, not reinterpreted.
      final bareInches = double.tryParse(text);
      if (bareInches == null) return null;
      cm = inchToCm(bareInches);
    }
  } else {
    final parsed = double.tryParse(text);
    if (parsed == null) return null;
    cm = parsed;
  }
  if (cm < kMinHeightCm || cm > kMaxHeightCm) return null;
  return cm;
}

/// Formats canonical [cm] for display in [unit] WITHOUT a unit suffix (the field
/// renders it). Centimetres get one decimal, like weight; feet and inches are
/// one readable combined string (`5'5"`), rounded to the nearest whole inch —
/// the total is rounded BEFORE the split, so 59.96in reads 5'0", never 4'12".
String formatHeightFromCm(double cm, String unit) {
  if (unit != kWeightUnitLb) return cm.toStringAsFixed(1);
  final totalInches = cmToInch(cm).round();
  return "${totalInches ~/ 12}'${totalInches % 12}\"";
}

/// Sexual-activity options (single-select). Keys share the same day-tags JSON as
/// symptoms but are namespaced with [kSexKeyPrefix] so they never surface in the
/// symptom chips. Stored on-device only, never transmitted.
const List<TrackOption> kSexOptions = [
  TrackOption('sex_none', 'None'),
  TrackOption('sex_protected', 'Protected'),
  TrackOption('sex_unprotected', 'Unprotected'),
];

/// Emotional symptoms (boolean multi-select). Plain (un-prefixed) keys — they
/// are symptoms, so they DO appear in the doctor PDF alongside physical ones.
const List<TrackOption> kEmotionalOptions = [
  TrackOption('mood_swings', 'Mood swings'),
  TrackOption('anxiety', 'Anxiety'),
  TrackOption('low_mood', 'Low mood'),
  TrackOption('irritability', 'Irritability'),
  TrackOption('sensitive_emotional', 'Emotional sensitivity'),
  TrackOption('tearful', 'Tearful'),
  TrackOption('low_motivation', 'Low motivation'),
  TrackOption('brain_fog', 'Brain fog'),
];

/// Discharge / cervical-mucus quality (single-select, [kDischargeKeyPrefix]).
/// Sensitive + fertility-relevant → excluded from the doctor PDF by default.
const List<TrackOption> kDischargeOptions = [
  TrackOption('cm_dry', 'Dry'),
  TrackOption('cm_sticky', 'Sticky'),
  TrackOption('cm_creamy', 'Creamy'),
  TrackOption('cm_watery', 'Watery'),
  TrackOption('cm_eggwhite', 'Egg white'),
];

/// Vaginal-health flags (boolean multi-select, [kVaginalKeyPrefix]). Sensitive
/// → excluded from the doctor PDF by default.
const List<TrackOption> kVaginalOptions = [
  TrackOption('vag_itching', 'Itching'),
  TrackOption('vag_burning', 'Burning'),
  TrackOption('vag_dryness', 'Dryness'),
  TrackOption('vag_odor', 'Unusual odor'),
  // "Vulval swelling", not "Swelling" — plain `swelling` already exists in
  // [kSymptomOptions] and an exact label clash breaks find.text in widget tests.
  TrackOption('vag_swelling', 'Vulval swelling'),
  TrackOption('vag_lumps', 'Lumps or bumps'),
  TrackOption('vag_discomfort', 'Discomfort'),
];

/// Sexual-health flags (boolean multi-select, [kSexualHealthKeyPrefix]).
/// Sensitive → excluded from the doctor PDF by default.
const List<TrackOption> kSexualHealthOptions = [
  TrackOption('shx_condom', 'Condom used'),
  TrackOption('shx_emergency', 'Emergency contraception'),
  TrackOption('shx_pain', 'Pain during sex'),
  // Bleeding after sex. The single most significant red flag this app can
  // collect, and the one thing in Tier 2 that is NOT derivable from anything
  // already logged. It sits under `shx_` — and therefore out of the doctor
  // report by default — because the owner chose sensitivity over automatic
  // disclosure: it reaches a clinician when the user decides it does.
  TrackOption('shx_post_coital', 'Bleeding after sex'),
  // `shx_high_libido` USED to live here as a boolean. It was replaced by the
  // three-point [kLibidoOptions] scale, but the key is NOT dead: days already
  // logged still carry it and [decodeLibido] still reads it as high. Never
  // reuse this key for anything else.
];

/// Ovulation-test (LH) result — stored directly in the `DailyLogs.opk` column
/// (not the day-tags JSON). Single-select.
const List<TrackOption> kOpkOptions = [
  TrackOption('negative', 'Negative'),
  TrackOption('positive', 'Positive'),
  TrackOption('peak', 'Peak'),
];

/// Lifestyle habits (boolean multi-select, [kHabitKeyPrefix]).
const List<TrackOption> kHabitOptions = [
  TrackOption('habit_exercise', 'Exercise'),
  TrackOption('habit_caffeine', 'Caffeine'),
  TrackOption('habit_alcohol', 'Alcohol'),
  TrackOption('habit_smoking', 'Smoking'),
  TrackOption('habit_meditation', 'Meditation'),
];

/// Urinary symptoms (boolean multi-select, [kUrineKeyPrefix]).
const List<TrackOption> kUrineOptions = [
  TrackOption('urn_frequent', 'Frequent'),
  TrackOption('urn_urgency', 'Urgency'),
  TrackOption('urn_burning', 'Burning or pain'),
  TrackOption('urn_dark', 'Dark colour'),
  TrackOption('urn_cloudy', 'Cloudy'),
  TrackOption('urn_blood', 'Blood in urine'),
  TrackOption('urn_leaking', 'Leaking'),
];

/// Digestion / bowel (boolean multi-select, [kDigestionKeyPrefix]). Deliberately
/// excludes diarrhea/constipation/bloating/nausea — those are already plain
/// symptoms in [kSymptomOptions] and must not be restated under a second key.
const List<TrackOption> kDigestionOptions = [
  TrackOption('dig_gas', 'Gas'),
  TrackOption('dig_heartburn', 'Heartburn'),
  TrackOption('dig_no_bm', 'No bowel movement'),
  TrackOption('dig_loose_stool', 'Loose stool'),
  TrackOption('dig_hard_stool', 'Hard stool'),
];

/// Skin & hair (boolean multi-select, [kSkinKeyPrefix]). Excludes `acne`, which
/// is already a plain symptom.
const List<TrackOption> kSkinOptions = [
  TrackOption('skin_dry', 'Dry skin'),
  TrackOption('skin_oily', 'Oily skin'),
  TrackOption('skin_itchy', 'Itchy skin'),
  TrackOption('skin_rash', 'Rash'),
  TrackOption('skin_hair_loss', 'Hair loss'),
  TrackOption('skin_hair_oily', 'Oily hair'),
];

/// Solo sexual activity (boolean multi-select, [kIntimacyKeyPrefix]).
///
/// Rides the day-tags blob like every other group, which means it SYNCS. That
/// was a deliberate owner decision — the alternative considered was a
/// local-only table, and it was rejected because a local-only row cannot
/// survive a lost phone. The trade-off accepted with it: this reaches Firestore
/// in plaintext, where an audited operator route can display it. Being reserved
/// keeps it out of the symptom chips, Insights counts and the doctor report;
/// it does not keep it off the network.
///
/// Deliberately just the fact of it. Frequency is DERIVED from how many days
/// carry the tag, the same way discharge frequency is — asking a user to
/// summarise data the app already holds produces an answer that is stale the
/// moment it is given and disagrees with the logs. Preferred methods and time
/// to orgasm are deliberately absent: they carry no gynaecological signal while
/// being among the most sensitive things this app could store.
const List<TrackOption> kIntimacyOptions = [
  TrackOption('slf_masturbation', 'Masturbation'),
];

/// Libido level (single-select, [kLibidoKeyPrefix]).
///
/// Replaces the old `shx_high_libido` boolean, which could only ever say
/// "high" — and therefore could not record the clinically interesting half,
/// which is a DROP. Read through [decodeLibido], never [decodeSingle], so the
/// old boolean keeps reading as [kLibidoHigh].
const List<TrackOption> kLibidoOptions = [
  TrackOption(kLibidoLow, 'Low libido'),
  TrackOption('lbd_medium', 'Medium libido'),
  TrackOption(kLibidoHigh, 'High libido'),
];

const String kLibidoLow = 'lbd_low';
const String kLibidoHigh = 'lbd_high';

/// The legacy boolean libido key. Kept as a named constant precisely because it
/// must never be typed by hand again: it is read-only history now.
const String kLegacyHighLibidoKey = 'shx_high_libido';

/// Contraception method (single-select), stored in `AppSettings`, not the
/// day-tags blob — it is ongoing state, not something that happens on a day.
///
/// [kContraceptionNone] is a real answer and not the same as null: null means
/// "never asked", which must not be read as "not using contraception".
const List<TrackOption> kContraceptionOptions = [
  TrackOption(kContraceptionNone, 'None'),
  TrackOption('contra_combined_pill', 'Combined pill'),
  TrackOption('contra_mini_pill', 'Progestogen-only pill'),
  TrackOption('contra_hormonal_iud', 'Hormonal IUD'),
  TrackOption('contra_copper_iud', 'Copper IUD'),
  TrackOption('contra_implant', 'Implant'),
  TrackOption('contra_injection', 'Injection'),
  TrackOption('contra_patch', 'Patch'),
  TrackOption('contra_ring', 'Vaginal ring'),
  TrackOption('contra_barrier', 'Condoms or another barrier'),
  TrackOption('contra_awareness', 'Fertility awareness'),
  TrackOption('contra_sterilisation', 'Sterilisation'),
  TrackOption('contra_other', 'Another method'),
];

const String kContraceptionNone = 'contra_none';

/// Methods that suppress ovulation, and therefore make a predicted fertile
/// window meaningless. Consumed by `PredictionService.predictFromLogs`, which
/// caps confidence to low — the same suppression perimenopause already gets.
///
/// The copper IUD is DELIBERATELY absent: it is non-hormonal, ovulation
/// continues, and blanking the fertile window for those users would remove a
/// real signal. Sterilisation is absent for the same structural reason — the
/// cycle itself is unchanged.
///
/// The hormonal IUD IS included even though many users keep ovulating on it,
/// because the two errors are not symmetric: suppressing a window that was real
/// costs a user information they can get elsewhere, while showing a fertile
/// window to somebody who does not ovulate is the app asserting something false
/// about their body.
const Set<String> kOvulationSuppressingContraception = {
  'contra_combined_pill',
  'contra_mini_pill',
  'contra_hormonal_iud',
  'contra_implant',
  'contra_injection',
  'contra_patch',
  'contra_ring',
};

/// Whether [method] suppresses ovulation, and therefore whether a predicted
/// fertile window would be meaningless. Null (never asked),
/// [kContraceptionNone] and any key this build does not recognise all read as
/// FALSE — an unknown answer must never silently blank the fertile window,
/// because nobody could then explain why it went.
///
/// The single mapping from an answer to the suppression, so the prediction
/// service (pure Dart, deliberately Flutter-free) never has to import this
/// file and the three call sites cannot drift apart.
bool contraceptionSuppressesOvulation(String? method) =>
    kOvulationSuppressingContraception.contains(method);

/// Diagnoses a clinician has already given the user (multi-select), stored in
/// `AppSettings` as a JSON array. Every one of these changes how a cycle should
/// be read, which is why they are profile state rather than a day tag.
///
/// This list is what the user has BEEN TOLD, never what the app concluded. The
/// app does not infer, suggest or score any of them.
const List<TrackOption> kDiagnosisOptions = [
  TrackOption('dx_pcos', 'PCOS'),
  TrackOption('dx_endometriosis', 'Endometriosis'),
  TrackOption('dx_fibroids', 'Fibroids'),
  TrackOption('dx_adenomyosis', 'Adenomyosis'),
  TrackOption('dx_thyroid', 'Thyroid condition'),
];

/// How often something typically happens. Asked ONCE, at signup, for the
/// questions where a per-day chip cannot answer on day one.
const List<TrackOption> kFrequencyOptions = [
  TrackOption('freq_never', 'Never'),
  TrackOption('freq_rarely', 'Rarely'),
  TrackOption('freq_weekly', 'Weekly'),
  TrackOption('freq_often', 'Several times a week'),
];

/// Things the user has EVER experienced, asked once at signup.
///
/// Reuses the day-tag keys deliberately. "Ever had pain during sex" and the
/// `shx_pain` chip are the same fact at two time scales; a separate vocabulary
/// for the baseline would let the two drift into meaning different things, and
/// nothing could then reconcile them.
const List<TrackOption> kSexualHistoryOptions = [
  TrackOption('shx_pain', 'Pain during sex'),
  TrackOption('shx_post_coital', 'Bleeding after sex'),
  TrackOption('vag_dryness', 'Dryness'),
];

/// The signup answers to the questions a first-run wizard can meaningfully ask:
/// what is TYPICALLY true, rather than what happened today.
///
/// Deliberately never merged with logged days. The baseline answers "how often,
/// generally"; the logs answer "what happened on the 3rd". A field that tries
/// to be both ends up disagreeing with itself — which is exactly why frequency
/// questions do not belong in the day-tags blob.
class SexualBaseline {
  const SexualBaseline({
    this.sexFrequency,
    this.soloFrequency,
    this.libido,
    this.history = const {},
  });

  /// A `freq_` key from [kFrequencyOptions], or null when skipped.
  final String? sexFrequency;
  final String? soloFrequency;

  /// An `lbd_` key from [kLibidoOptions] — the user's GENERAL level, not a
  /// day's. Null when skipped.
  final String? libido;

  /// Keys from [kSexualHistoryOptions] the user has ever experienced.
  final Set<String> history;

  bool get isEmpty =>
      sexFrequency == null &&
      soloFrequency == null &&
      libido == null &&
      history.isEmpty;
}

String? _validKey(List<TrackOption> options, Object? raw) {
  if (raw is! String) return null;
  for (final o in options) {
    if (o.key == raw) return raw;
  }
  return null;
}

/// Encodes the signup baseline, or NULL when nothing was answered.
///
/// Null is what "never asked" looks like in the column. An empty `{}` would
/// read as "asked, and answered nothing" — a different claim, and one that
/// would print an empty section in the doctor report.
String? encodeSexualBaseline({
  String? sexFrequency,
  String? soloFrequency,
  String? libido,
  Set<String> history = const {},
}) {
  if (sexFrequency == null &&
      soloFrequency == null &&
      libido == null &&
      history.isEmpty) {
    return null;
  }
  return jsonEncode({
    'sexFrequency': ?sexFrequency,
    'soloFrequency': ?soloFrequency,
    'libido': ?libido,
    if (history.isNotEmpty) 'history': history.toList(),
  });
}

/// Tolerant decode. Malformed JSON, the wrong shape, and keys written by a
/// NEWER build all read as "not answered" rather than throwing or surfacing a
/// raw key — a settings getter that throws takes the whole screen down, and a
/// raw `freq_from_the_future` in a clinical summary is worse than an omission.
SexualBaseline decodeSexualBaseline(String? json) {
  if (json == null || json.isEmpty) return const SexualBaseline();
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return const SexualBaseline();
    final rawHistory = decoded['history'];
    return SexualBaseline(
      sexFrequency: _validKey(kFrequencyOptions, decoded['sexFrequency']),
      soloFrequency: _validKey(kFrequencyOptions, decoded['soloFrequency']),
      libido: _validKey(kLibidoOptions, decoded['libido']),
      history: rawHistory is! List
          ? const {}
          : {
              for (final e in rawHistory)
                if (_validKey(kSexualHistoryOptions, e) != null) e as String,
            },
    );
  } catch (_) {
    return const SexualBaseline();
  }
}

bool _isReserved(String key) => kReservedTagPrefixes.any(key.startsWith);

/// Encodes a full day's tags into the JSON blob: boolean [flags] (symptoms plus
/// any selected namespaced keys) as `{key: true}`, and numeric [numbers] as real
/// JSON numbers. An object (not a list) so per-key detail can be added later
/// without a migration.
String encodeDayTags({
  Set<String> flags = const {},
  Map<String, num> numbers = const {},
}) =>
    jsonEncode({
      for (final k in flags) k: true,
      for (final e in numbers.entries) e.key: e.value,
    });

/// Backward-compatible alias: encode only boolean symptom/flag keys.
String encodeSymptoms(Set<String> keys) => encodeDayTags(flags: keys);

/// Tolerant decode of the day-tags JSON, returning only PLAIN symptom keys —
/// boolean-true keys not under any reserved prefix. Numeric metrics are excluded
/// automatically (they are not `== true`). Defensively accepts a legacy list.
Set<String> decodeSymptoms(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .where((k) => !_isReserved(k))
          .toSet();
    }
    if (decoded is List) {
      return decoded
          .map((e) => e.toString())
          .where((k) => !_isReserved(k))
          .toSet();
    }
  } catch (_) {}
  return {};
}

/// The single selected key under [prefix] in the day-tags JSON, or null. Used
/// for single-select groups (sexual activity, discharge quality) that share the
/// symptoms blob but round-trip independently.
String? decodeSingle(String? json, String prefix) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      for (final e in decoded.entries) {
        if (e.value == true && e.key.toString().startsWith(prefix)) {
          return e.key.toString();
        }
      }
    }
  } catch (_) {}
  return null;
}

/// The selected sexual-activity key, or null. Thin wrapper over [decodeSingle].
String? decodeSex(String? json) => decodeSingle(json, kSexKeyPrefix);

/// All selected keys under [prefix] in the day-tags JSON — for multi-select
/// groups such as vaginal-health or lifestyle habits.
Set<String> decodeGroup(String? json, String prefix) {
  if (json == null || json.isEmpty) return {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.entries
          .where((e) => e.value == true && e.key.toString().startsWith(prefix))
          .map((e) => e.key.toString())
          .toSet();
    }
  } catch (_) {}
  return {};
}

/// The selected libido level, or null when the day carries none.
///
/// Falls back to the retired `shx_high_libido` boolean, which is the whole
/// reason this wrapper exists. The day-tags blob has no migration path — days
/// are only ever rewritten when the user re-saves them — so a decoder that
/// only understood [kLibidoKeyPrefix] would blank every libido answer already
/// on the device. The new key wins when a day somehow carries both.
String? decodeLibido(String? json) =>
    decodeSingle(json, kLibidoKeyPrefix) ??
    (decodeGroup(json, kSexualHealthKeyPrefix).contains(kLegacyHighLibidoKey)
        ? kLibidoHigh
        : null);

/// A numeric day-metric (e.g. [kMetricPain], [kMetricWater]) from the day-tags
/// JSON, or null if absent/invalid.
num? decodeNumber(String? json, String key) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      final v = decoded[key];
      if (v is num) return v;
    }
  } catch (_) {}
  return null;
}

/// Human label for a plain-symptom [key] (physical or emotional), falling back
/// to the raw key. Used by the doctor PDF so every symptom group renders a
/// readable name rather than a storage key.
String symptomLabel(String key) {
  for (final o in [...kSymptomOptions, ...kEmotionalOptions]) {
    if (o.key == key) return o.label;
  }
  return key;
}

extension FlowIntensityUi on FlowIntensity {
  String get label => switch (this) {
        FlowIntensity.none => 'None',
        FlowIntensity.spotting => 'Spotting',
        FlowIntensity.light => 'Light',
        FlowIntensity.medium => 'Medium',
        FlowIntensity.heavy => 'Heavy',
        FlowIntensity.flooding => 'Very heavy',
      };

  /// Any bleeding at all counts toward a period run.
  bool get isBleeding => this != FlowIntensity.none;

  /// Fill color for a day: rose that deepens with intensity.
  Color color(PhaseColors phases) {
    final base = phases.menstrual;
    return switch (this) {
      FlowIntensity.none => Colors.transparent,
      FlowIntensity.spotting => base.withValues(alpha: 0.28),
      FlowIntensity.light => base.withValues(alpha: 0.48),
      FlowIntensity.medium => base.withValues(alpha: 0.68),
      FlowIntensity.heavy => base.withValues(alpha: 0.86),
      FlowIntensity.flooding => base,
    };
  }
}
