import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../models/enums.dart';
import '../../providers/log_provider.dart';
import '../../providers/settings_provider.dart';

/// First-run flow: privacy promise → set cycle basics + last period → done.
/// Writing the last-period date seeds the first cycle so predictions can start.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  DateTime? _lastPeriod;
  int _cycleLength = 28;
  bool _genderNeutral = false;
  TrackingMode _mode = TrackingMode.track;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();

    await settings.setCycleLength(_cycleLength);
    await settings.setGenderNeutralLanguage(_genderNeutral);
    await settings.setMode(_mode);

    // Seed the last period so cycle stats have a starting anchor.
    if (_lastPeriod != null) {
      await logs.saveDay(
        date: _lastPeriod!,
        flow: FlowIntensity.medium,
        symptomsJson: encodeSymptoms({}),
      );
    }
    await settings.completeOnboarding();
    // AppGate rebuilds and shows the app once onboardingComplete flips.
  }

  Future<void> _pickLastPeriod() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastPeriod ?? now,
      firstDate: now.subtract(const Duration(days: 120)),
      lastDate: now,
    );
    if (picked != null) setState(() => _lastPeriod = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(),
                  _PrivacyPage(),
                  _SetupPage(
                    lastPeriod: _lastPeriod,
                    cycleLength: _cycleLength,
                    genderNeutral: _genderNeutral,
                    mode: _mode,
                    onPickDate: _pickLastPeriod,
                    onCycleChanged: (v) => setState(() => _cycleLength = v),
                    onGenderNeutralChanged: (v) =>
                        setState(() => _genderNeutral = v),
                    onModeChanged: (v) => setState(() => _mode = v),
                  ),
                ],
              ),
            ),
            _Dots(count: 3, index: _page),
            Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                onPressed: _next,
                child: Text(_page < 2 ? 'Continue' : 'Get started'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.spa_outlined,
      title: 'Welcome to LunaTrack',
      body: 'A calm, simple way to track your cycle, understand your body, and '
          'plan ahead — with predictions, symptom logging, and a summary you '
          'can share with your doctor.',
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Page(
      icon: Icons.lock_outline,
      title: 'Your data, on your terms',
      body: 'Your logs are stored in an encrypted database on this device, and '
          'synced to your account so you can move between devices. The synced '
          'copy is not end-to-end encrypted. You can add a PIN or biometric '
          'lock any time in Settings.',
    );
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.lastPeriod,
    required this.cycleLength,
    required this.genderNeutral,
    required this.mode,
    required this.onPickDate,
    required this.onCycleChanged,
    required this.onGenderNeutralChanged,
    required this.onModeChanged,
  });

  final DateTime? lastPeriod;
  final int cycleLength;
  final bool genderNeutral;
  final TrackingMode mode;
  final VoidCallback onPickDate;
  final ValueChanged<int> onCycleChanged;
  final ValueChanged<bool> onGenderNeutralChanged;
  final ValueChanged<TrackingMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('A few basics',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('These help predictions start right away. You can change them '
            'later, and they get more accurate as you log.'),
        const SizedBox(height: 24),
        Text('What are you here for?',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<TrackingMode>(
          segments: const [
            ButtonSegment(
              value: TrackingMode.track,
              label: Text('My cycle'),
              icon: Icon(Icons.favorite_outline),
            ),
            ButtonSegment(
              value: TrackingMode.conceive,
              label: Text('Conceiving'),
              icon: Icon(Icons.child_friendly_outlined),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onModeChanged(s.first),
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('First day of your last period'),
          subtitle: Text(lastPeriod == null
              ? 'Tap to choose (optional)'
              : DateFormat.yMMMMd().format(lastPeriod!)),
          trailing: const Icon(Icons.edit_outlined),
          onTap: onPickDate,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.repeat),
          title: const Text('Average cycle length'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed:
                    cycleLength > 21 ? () => onCycleChanged(cycleLength - 1) : null,
              ),
              Text('$cycleLength days'),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed:
                    cycleLength < 35 ? () => onCycleChanged(cycleLength + 1) : null,
              ),
            ],
          ),
        ),
        const Divider(),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.diversity_3_outlined),
          title: const Text('Gender-neutral language'),
          subtitle: const Text('Use inclusive wording throughout the app'),
          value: genderNeutral,
          onChanged: onGenderNeutralChanged,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'LunaTrack provides estimates for general wellness. It is not a '
            'contraceptive method and does not provide medical diagnosis.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text(body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == index ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index
                  ? scheme.primary
                  : scheme.primary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
