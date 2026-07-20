import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/medication_adherence.dart';

/// Counts, per enabled medication, how many days it was logged within a cycle.
/// Pure function of (cycle, logs, meds). No percentage — just a day-count and
/// the cycle length as a bar scale.
class MedicationAdherenceService {
  const MedicationAdherenceService._();

  static MedicationAdherence forCycle(
    Cycle cycle,
    List<DailyLog> logs,
    List<Medication> meds,
  ) {
    final start = dateOnly(cycle.start);
    final nextStart = cycle.lengthDays == null
        ? null
        : start.add(Duration(days: cycle.lengthDays!));
    final cycleLength = cycle.lengthDays ?? cycle.periodLengthDays;

    bool inCycle(DateTime raw) {
      final d = dateOnly(raw);
      return !d.isBefore(start) && (nextStart == null || d.isBefore(nextStart));
    }

    // Pre-count med_<id> day tallies across the cycle.
    final tally = <int, int>{};
    for (final l in logs) {
      if (!inCycle(l.date)) continue;
      for (final key in decodeGroup(l.symptoms, kMedicationKeyPrefix)) {
        final id = int.tryParse(key.substring(kMedicationKeyPrefix.length));
        if (id != null) tally[id] = (tally[id] ?? 0) + 1;
      }
    }

    final entries = <MedAdherenceEntry>[
      for (final m in meds)
        if (m.enabled && (tally[m.id] ?? 0) > 0)
          MedAdherenceEntry(
            medId: m.id,
            name: m.name,
            daysLogged: tally[m.id]!,
            cycleLength: cycleLength,
          ),
    ]..sort((a, b) {
        final byCount = b.daysLogged.compareTo(a.daysLogged);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });

    return MedicationAdherence(entries);
  }
}
