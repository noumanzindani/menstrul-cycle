/// Days a single medication was logged within one cycle. [cycleLength] is the
/// bar's denominator — a scale, NOT an adherence target (we don't store dosing
/// frequency, so no percentage is implied).
class MedAdherenceEntry {
  const MedAdherenceEntry({
    required this.medId,
    required this.name,
    required this.daysLogged,
    required this.cycleLength,
  });

  final int medId;
  final String name;
  final int daysLogged;
  final int cycleLength;
}

/// Per-medication days-logged for one cycle. Descriptive only.
class MedicationAdherence {
  const MedicationAdherence(this.entries);
  final List<MedAdherenceEntry> entries;
  bool get hasData => entries.isNotEmpty;
}
