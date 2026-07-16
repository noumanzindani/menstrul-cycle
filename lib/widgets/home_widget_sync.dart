import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/prediction.dart';
import '../providers/log_provider.dart';
import '../providers/reminder_provider.dart';
import '../providers/settings_provider.dart';
import '../services/home_widget_service.dart';
import '../services/prediction_service.dart';

/// Invisible glue with two jobs:
///
/// 1. **Widget push** — watches the derived [PredictionResult] + [SettingsProvider]
///    and pushes a fresh snapshot to the home-screen widget whenever they change
///    (deduped so identical rebuilds don't spam the platform channel).
///
/// 2. **Horizon upkeep + background-write reconciliation** — the check-in
///    notification horizon only extends when the app opens, and a background
///    action writes to the DB on a *second* connection the foreground
///    [LogProvider] can't observe. So on first build and on every resume this
///    reloads the logs (picking up any background write) and reschedules the
///    horizon from the freshly-loaded state.
///
/// Renders its [child] unchanged; every side effect is a guarded no-op off-device.
class HomeWidgetSync extends StatefulWidget {
  const HomeWidgetSync({super.key, required this.child});
  final Widget child;

  @override
  State<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends State<HomeWidgetSync>
    with WidgetsBindingObserver {
  HomeWidgetData? _last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Extend the horizon once on launch (it doesn't self-extend while idle).
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAndReschedule());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A background action may have written behind the app's back; reload so
      // the UI reflects it, and reschedule the horizon from the new state.
      _reloadAndReschedule();
    }
  }

  Future<void> _reloadAndReschedule() async {
    if (!mounted) return;
    final log = context.read<LogProvider>();
    final settings = context.read<SettingsProvider>();
    final reminders = context.read<ReminderProvider>();

    await log.load();
    if (!mounted) return;
    // Recompute from the just-loaded logs (the ProxyProvider's value only
    // refreshes next frame) so the horizon is self-consistent with the reload.
    final prediction = PredictionService.predictFromLogs(
      logs: log.logs,
      mode: settings.mode,
      cycleLength: settings.cycleLength,
      periodLength: settings.periodLength,
    );
    await reminders.reschedule(prediction, log.logs);
  }

  @override
  Widget build(BuildContext context) {
    final prediction = context.watch<PredictionResult>();
    final settings = context.watch<SettingsProvider>();
    final data = buildHomeWidgetData(
      prediction: prediction,
      mode: settings.mode,
      pregnancyStartDate: settings.pregnancyStartDate,
    );
    if (data != _last) {
      _last = data;
      // Defer off the build frame — the push is a side effect, not layout.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(HomeWidgetService.push(data)),
      );
    }
    return widget.child;
  }
}
