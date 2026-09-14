import 'dart:convert';

import '../common/catalog.dart';
import '../db/database.dart';
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
