import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/prediction.dart';
import '../providers/settings_provider.dart';
import '../services/home_widget_service.dart';

/// Invisible glue: watches the derived [PredictionResult] + [SettingsProvider]
/// and pushes a fresh snapshot to the home-screen widget whenever they change
/// (deduped so identical rebuilds don't spam the platform channel). Renders its
/// [child] unchanged; the push is a guarded no-op off-device.
class HomeWidgetSync extends StatefulWidget {
  const HomeWidgetSync({super.key, required this.child});
  final Widget child;

  @override
  State<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends State<HomeWidgetSync> {
  HomeWidgetData? _last;

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
