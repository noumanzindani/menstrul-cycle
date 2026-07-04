import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/premium_provider.dart';
import '../services/ad_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onSelect,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: 'Forecast',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
