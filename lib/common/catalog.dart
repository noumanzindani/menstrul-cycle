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
];

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
  TrackOption('cm_eggwhite', 'Egg-white'),
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
  TrackOption('shx_high_libido', 'High libido'),
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
