import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/option_art.dart';
import '../providers/premium_provider.dart';
import '../services/ad_service.dart';
import '../widgets/track_art.dart';
import 'assistant/assistant_screen.dart';
import 'calendar/calendar_screen.dart';
import 'home/home_screen.dart';
import 'insights/insights_screen.dart';
import 'settings/settings_screen.dart';

/// Root navigation shell: Home, Calendar, Assistant, Insights, Settings.
///
/// The Assistant took Forecast's slot at index 2 (owner decision, 2026-09-23).
/// Forecast is still a screen, pushed from Home's cycle card and from the
/// Calendar app bar. Index 0 is unchanged, which keeps the interstitial where
/// it was.
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

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  int _navCount = 0;
  static const _interstitialEvery = 5;

  /// Long enough to read as a change of place, short enough that it never sits
  /// between the user and a tap they have already made. The bottom bar is the
  /// most-repeated interaction in the app; anything slower becomes a tax.
  static const _tabSwitchDuration = Duration(milliseconds: 200);
  static const _tabSwitchCurve = Curves.easeOut;

  /// A HINT of travel, not a slide -- ~1% of the viewport. The screens are
  /// siblings, not a stack, so a real slide would imply a direction and a
  /// hierarchy that the bottom bar does not have.
  static const _tabSwitchOffset = Offset(0, 0.012);

  late final AnimationController _tabSwitch;
  late final CurvedAnimation _tabFade;
  late final Animation<Offset> _tabSlide;

  static const _screens = [
    HomeScreen(),
    CalendarScreen(),
    AssistantScreen(),
    InsightsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _tabSwitch = AnimationController(
      vsync: this,
      duration: _tabSwitchDuration,
      // Parked at the END: the first tab is already here on mount. Starting at
      // 0 would fade Home in at launch, which is a splash, not a tab switch.
      value: 1,
    );
    _tabFade = CurvedAnimation(parent: _tabSwitch, curve: _tabSwitchCurve);
    _tabSlide =
        Tween(begin: _tabSwitchOffset, end: Offset.zero).animate(_tabFade);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final premium = context.read<PremiumProvider>().isPremium;
      AdService.instance.preloadInterstitial(premium: premium);
      // The rewarded unit behind Describe, warmed here for the same reason the
      // interstitial is: loading it at tap time would put a spinner between
      // "Watch ad" and the ad. Cheap to preload and never shown unasked --
      // nothing plays it but an explicit opt-in (`showRewardedDescribePrompt`).
      AdService.instance.preloadRewarded(premium: premium);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion switched on mid-switch lands on the destination, never
    // back on the tab being left.
    if (MediaQuery.disableAnimationsOf(context)) _tabSwitch.value = 1;
  }

  @override
  void dispose() {
    _tabFade.dispose();
    _tabSwitch.dispose();
    super.dispose();
  }

  void _onSelect(int i) {
    // Re-tapping the tab you are already on is not an arrival, so it does not
    // replay. NavigationBar reports every tap, not only the changes.
    final arrived = i != _index;
    setState(() => _index = i);
    if (arrived) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _tabSwitch.value = 1;
      } else {
        _tabSwitch.forward(from: 0);
      }
    }
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
    'Assistant',
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
      // IndexedStack, NOT AnimatedSwitcher: all five tabs stay mounted so each
      // keeps its scroll offset and form state. The transition therefore wraps
      // the stack rather than cross-fading two children -- only the ARRIVING
      // tab is animated, which is the incoming half of a Material fade-through.
      //
      // The RepaintBoundary caches the tab content as one raster so the fade
      // does not re-record the whole screen's picture every frame. It is the
      // first in this app; the low-end target (OnePlus Nord N200) is why.
      //
      // NOT YET DEVICE-VERIFIED: the ad banner is a platform view
      // (`google_mobile_ads` -> AdWidget) living in each screen's
      // `bottomNavigationBar`, i.e. INSIDE this stack, so it is faded and
      // translated with everything else. Android composites platform views
      // through a texture layer that does not always follow opacity and
      // transforms in lockstep. Check on a free (ad-showing) build that the
      // banner does not tear, lag a frame behind, or flash during a switch.
      body: FadeTransition(
        opacity: _tabFade,
        child: SlideTransition(
          position: _tabSlide,
          child: RepaintBoundary(
            child: IndexedStack(index: _index, children: _screens),
          ),
        ),
      ),
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
