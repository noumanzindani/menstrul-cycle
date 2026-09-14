import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/option_art.dart';
import '../providers/premium_provider.dart';
import '../services/ad_service.dart';
import '../widgets/track_art.dart';
import 'calendar/calendar_screen.dart';
import 'forecast/forecast_screen.dart';
import 'home/home_screen.dart';
import 'insights/insights_screen.dart';
import 'settings/settings_screen.dart';

/// Root navigation shell: Home, Calendar, Forecast, Insights, Settings.
///
/// Also hosts the RARE interstitial. Council rule: never during a logging flow.
/// Calendar now hosts inline logging, so the ONLY eligible ad moment is a switch
/// into Home (never Calendar, Insights, or a log screen), and only once every
/// [_interstitialEvery] such switches.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _navCount = 0;
  static const _interstitialEvery = 5;

  static const _screens = [
    HomeScreen(),
    CalendarScreen(),
    ForecastScreen(),
    InsightsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final premium = context.read<PremiumProvider>().isPremium;
      AdService.instance.preloadInterstitial(premium: premium);
    });
  }

  void _onSelect(int i) {
    setState(() => _index = i);
    // Only Home (0) is an eligible ad moment — Calendar now hosts logging.
    if (i == 0) {
      _navCount++;
      if (_navCount % _interstitialEvery == 0) {
        final premium = context.read<PremiumProvider>().isPremium;
        AdService.instance.showInterstitial(premium: premium);
      }
    }
  }

  static const _labels = [
    'Today',
    'Calendar',
    'Forecast',
    'Insights',
    'Settings',
  ];

  /// Material sizes a navigation icon at 24. [TrackArt] takes a GLYPH size and
  /// multiplies raster art by [TrackArt.rasterScale], so the target is divided
  /// back out rather than hardcoded — hardcoding 13.7 here would silently
  /// resize the whole bar the day that scale changes.
  static const double _navIconPx = 26;

  /// The unselected mark is dimmed because one raster cannot supply the
  /// outlined/filled pair `NavigationDestination` expects; see `kNavArt`.
  static Widget _navMark(int i, {required bool selected}) {
    final mark = TrackArt(
      path: kNavArt[i],
      size: _navIconPx / TrackArt.rasterScale,
    );
    return selected
        ? mark
        : Opacity(opacity: kNavUnselectedOpacity, child: mark);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        destinations: [
          for (final (i, label) in _labels.indexed)
            NavigationDestination(
              icon: _navMark(i, selected: false),
              selectedIcon: _navMark(i, selected: true),
              label: label,
            ),
        ],
      ),
    );
  }
}
