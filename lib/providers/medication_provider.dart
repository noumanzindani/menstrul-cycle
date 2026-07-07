import 'package:flutter/foundation.dart';

import '../data/medication_repository.dart';
import '../db/database.dart';
import '../models/medication.dart';
import '../services/notification_service.dart';

/// Holds the user's medications / birth control and keeps each one's daily
/// reminder in sync. Reminders are scheduled straight from here (self-contained
/// in the Medications table) rather than via the cycle-reminder Reminders table.
class MedicationProvider extends ChangeNotifier {
  MedicationProvider(this._repo);
  final MedicationRepository _repo;

  List<Medication> _items = const [];
  List<Medication> get items => _items;

  bool _loading = true;
  bool get loading => _loading;

  Future<void> load() async {
    _items = await _repo.getAll();
    _loading = false;
    notifyListeners();
  }

  Future<void> add({
    required String name,
    String? type,
    MedicationSchedule? schedule,
  }) async {
    final id = await _repo.add(
      name: name,
      type: type,
      schedule: schedule?.encode(),
    );
    // A brand-new row has nothing to cancel, so only touch the OS if we are
    // actually arming a reminder — this keeps a reminder-less add plugin-free.
    if (schedule != null && schedule.remind) {
      await NotificationService.scheduleMedication(
        medicationId: id,
        hour: schedule.hour,
        minute: schedule.minute,
        name: name,
      );
    }
    await load();
  }

  Future<void> update(
    Medication med, {
    required String name,
    String? type,
    MedicationSchedule? schedule,
    required bool enabled,
  }) async {
    await _repo.update(
      id: med.id,
      name: name,
      type: type,
      schedule: schedule?.encode(),
      enabled: enabled,
    );
    if (enabled && schedule != null && schedule.remind) {
      await NotificationService.scheduleMedication(
        medicationId: med.id,
        hour: schedule.hour,
        minute: schedule.minute,
        name: name,
      );
    } else {
      await NotificationService.cancelMedication(med.id);
    }
    await load();
  }

  Future<void> remove(Medication med) async {
    await NotificationService.cancelMedication(med.id);
    await _repo.remove(med.id);
    await load();
  }
}
