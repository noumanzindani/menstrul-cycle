import 'package:flutter/foundation.dart';

import '../common/date_utils.dart';
import '../data/daily_log_repository.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/enums.dart';
import '../services/cycle_calculator.dart';

/// Holds all daily logs in memory (a few years of one-per-day rows is tiny) and
/// the cycles derived from them. Recomputes cycles after every mutation so the
/// calendar, Home, and stats stay in sync from a single source of truth.
class LogProvider extends ChangeNotifier {
  LogProvider(this._repo);
  final DailyLogRepository _repo;

  bool _loading = true;
  bool get loading => _loading;

  Map<DateTime, DailyLog> _byDate = {};
  List<Cycle> _cycles = const [];

  List<DailyLog> get logs => _byDate.values.toList();
  List<Cycle> get cycles => _cycles;

  DailyLog? logForDate(DateTime date) => _byDate[dateOnly(date)];

  Future<void> load() async {
    final all = await _repo.getAll();
    _byDate = {for (final l in all) dateOnly(l.date): l};
    _cycles = CycleCalculator.computeCycles(all);
    _loading = false;
    notifyListeners();
  }

  Future<void> saveDay({
    required DateTime date,
    required FlowIntensity? flow,
    required String symptomsJson,
    String? mood,
    String? notes,
    double? bbt,
    String? opk,
  }) async {
    await _repo.upsert(
      date: date,
      flow: flow,
      symptomsJson: symptomsJson,
      mood: mood,
      notes: notes,
      bbt: bbt,
      opk: opk,
    );
    await load();
  }

  Future<void> clearDay(DateTime date) async {
    await _repo.deleteForDate(date);
    await load();
  }
}
