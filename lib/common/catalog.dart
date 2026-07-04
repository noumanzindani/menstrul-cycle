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

/// Namespace prefix for sexual-activity keys stored inside the day-tags JSON.
const String kSexKeyPrefix = 'sex_';

/// Sexual-activity options (single-select). Keys share the same day-tags JSON as
/// symptoms but are namespaced with [kSexKeyPrefix] so they never surface in the
/// symptom chips. Stored on-device only, never transmitted.
const List<TrackOption> kSexOptions = [
  TrackOption('sex_none', 'None'),
  TrackOption('sex_protected', 'Protected'),
  TrackOption('sex_unprotected', 'Unprotected'),
];

/// Encodes selected symptom keys as a JSON object `{key: true}` — an object (not
/// a list) so we can later attach per-symptom intensity without a migration.
String encodeSymptoms(Set<String> keys) =>
    jsonEncode({for (final k in keys) k: true});

/// Tolerant decode of the symptoms JSON. Accepts the object form and, defensively,
/// a legacy list form; returns an empty set on anything unexpected.
Set<String> decodeSymptoms(String? json) {
  if (json == null || json.isEmpty) return {};
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.entries
          .where((e) => e.value == true)
          .map((e) => e.key.toString())
          .where((k) => !k.startsWith(kSexKeyPrefix)) // sex is read separately
          .toSet();
    }
    if (decoded is List) {
      return decoded
          .map((e) => e.toString())
          .where((k) => !k.startsWith(kSexKeyPrefix))
          .toSet();
    }
  } catch (_) {}
  return {};
}

/// The single selected sexual-activity key in the day-tags JSON, or null.
/// Sex shares the [encodeSymptoms] blob but is namespaced with [kSexKeyPrefix]
/// so it round-trips independently of symptoms.
String? decodeSex(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      for (final e in decoded.entries) {
        if (e.value == true && e.key.toString().startsWith(kSexKeyPrefix)) {
          return e.key.toString();
        }
      }
    }
  } catch (_) {}
  return null;
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
