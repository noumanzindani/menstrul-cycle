import 'dart:convert';

/// Medication / birth-control types. Stored as the string key in the
/// `Medications.type` column, so keys are STABLE — never rename one.
class MedicationType {
  const MedicationType._();
  static const pill = 'pill';
  static const patch = 'patch';
  static const ring = 'ring';
  static const injection = 'injection';
  static const iud = 'iud';
  static const implant = 'implant';
  static const supplement = 'supplement';
  static const other = 'other';
}

/// (key, label) options for the medication-type picker.
const List<({String key, String label})> kMedicationTypes = [
  (key: MedicationType.pill, label: 'Birth control pill'),
  (key: MedicationType.patch, label: 'Patch'),
  (key: MedicationType.ring, label: 'Ring'),
  (key: MedicationType.injection, label: 'Injection'),
  (key: MedicationType.iud, label: 'IUD'),
  (key: MedicationType.implant, label: 'Implant'),
  (key: MedicationType.supplement, label: 'Supplement / vitamin'),
  (key: MedicationType.other, label: 'Other medication'),
];

/// Human label for a medication [key], falling back to a neutral default.
String medicationTypeLabel(String? key) {
  for (final t in kMedicationTypes) {
    if (t.key == key) return t.label;
  }
  return 'Medication';
}

/// A daily reminder config stored as JSON in the `Medications.schedule` column.
/// [remind] lets a user keep a time but pause the notification (e.g. during a
/// pill-free week) without losing the setting.
class MedicationSchedule {
  const MedicationSchedule({
    required this.hour,
    required this.minute,
    this.remind = true,
  });

  final int hour;
  final int minute;
  final bool remind;

  String encode() =>
      jsonEncode({'hour': hour, 'minute': minute, 'remind': remind});

  /// Decodes the `schedule` column; null for a medication with no reminder.
  static MedicationSchedule? decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final m = jsonDecode(json);
      if (m is Map && m['hour'] is int && m['minute'] is int) {
        return MedicationSchedule(
          hour: m['hour'] as int,
          minute: m['minute'] as int,
          remind: m['remind'] != false, // absent → true
        );
      }
    } catch (_) {}
    return null;
  }
}
