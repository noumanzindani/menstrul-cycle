import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../models/enums.dart';
import '../../providers/log_provider.dart';
import '../../providers/settings_provider.dart';

/// First-run flow: privacy promise → set cycle basics + last period → done.
/// Writing the last-period date seeds the first cycle so predictions can start.
///
/// One question per step, in the design-system's stepper shape: a slim linear
/// progress line at the top, a left-aligned question, the answer control given
/// the whole middle of the screen, and a single full-width "Continue" pinned to
/// the bottom. Step 3 keeps an explicit **"I'm not sure"** escape — taking it
/// seeds no log, which lands the user on a genuinely different first Today
/// screen (no estimate at all, rather than a low-confidence one).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 5;

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
    if (_page < _pageCount - 1) {
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

  /// The date is optional by design; skipping it is a first-class answer, not a
  /// failure to answer. Clearing it here keeps "I'm not sure" honest if the
  /// user tapped a day first and changed their mind.
  void _skipDate() {
    setState(() => _lastPeriod = null);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _StepProgress(step: _page, count: _pageCount),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  const _WelcomePage(),
                  const _PrivacyPage(),
                  _LastPeriodPage(
                    lastPeriod: _lastPeriod,
                    onDateChanged: (d) => setState(() => _lastPeriod = d),
                    onSkip: _skipDate,
                  ),
                  _CycleLengthPage(
                    cycleLength: _cycleLength,
                    onChanged: (v) => setState(() => _cycleLength = v),
                  ),
                  _ModePage(
                    mode: _mode,
                    genderNeutral: _genderNeutral,
                    onModeChanged: (v) => setState(() => _mode = v),
                    onGenderNeutralChanged: (v) =>
                        setState(() => _genderNeutral = v),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: FilledButton(
                onPressed: _next,
                child: Text(_page < _pageCount - 1 ? 'Continue' : 'Get started'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slim determinate line under the (absent) app bar — the stepper's only
/// chrome. Deliberately not a percentage or a "x of y complete" badge.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step, required this.count});
  final int step;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: (step + 1) / count),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, value, _) => LinearProgressIndicator(
        value: value,
        minHeight: 3,
        backgroundColor: scheme.surfaceContainerHighest,
        color: scheme.primary,
      ),
    );
  }
}

/// Shared shell for a question step: the question at the top left, the answer
/// control filling the space beneath it.
class _QuestionPage extends StatelessWidget {
  const _QuestionPage({required this.question, required this.child});
  final String question;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 24),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _IntroPage(
      icon: Icons.spa_outlined,
      title: 'Welcome to LunaTrack',
      body: 'A calm, simple way to track your cycle, understand your body, and '
          'plan ahead — with predictions, symptom logging, and a summary you '
          'can share with your doctor.',
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    return const _IntroPage(
      icon: Icons.lock_outline,
      title: 'Your data, on your terms',
      body: 'Your logs are stored in an encrypted database on this device, and '
          'synced to your account so you can move between devices. The synced '
          'copy is not end-to-end encrypted. You can add a PIN or biometric '
          'lock any time in Settings.',
    );
  }
}

/// Step 3 — the date. Inline month grid rather than a modal picker: this is the
/// whole question of the step, so it should not be hidden behind a dialog.
class _LastPeriodPage extends StatelessWidget {
  const _LastPeriodPage({
    required this.lastPeriod,
    required this.onDateChanged,
    required this.onSkip,
  });

  final DateTime? lastPeriod;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    return _QuestionPage(
      question: 'When did your last period start?',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          CalendarDatePicker(
            initialDate: lastPeriod,
            currentDate: now,
            firstDate: now.subtract(const Duration(days: 120)),
            lastDate: now,
            onDateChanged: onDateChanged,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: const Text("I'm not sure"),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Skipping is fine — LunaTrack simply waits until you log a period '
            'before it estimates anything.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Step 4 — cycle length. The value is the hero of the screen.
class _CycleLengthPage extends StatelessWidget {
  const _CycleLengthPage({required this.cycleLength, required this.onChanged});

  final int cycleLength;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return _QuestionPage(
      question: 'How long is your cycle, usually?',
      child: Center(
        child: SingleChildScrollView(
          child: _HeroStepper(
            value: cycleLength,
            min: 21,
            max: 35,
            unit: 'days',
            caption: 'days from the first day of one period to the next',
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

/// Step 5 — what the app is for, plus the wording preference. Two equal cards,
/// neither styled as the recommended answer.
class _ModePage extends StatelessWidget {
  const _ModePage({
    required this.mode,
    required this.genderNeutral,
    required this.onModeChanged,
    required this.onGenderNeutralChanged,
  });

  final TrackingMode mode;
  final bool genderNeutral;
  final ValueChanged<TrackingMode> onModeChanged;
  final ValueChanged<bool> onGenderNeutralChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _QuestionPage(
      question: 'What are you using LunaTrack for?',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ChoiceCard(
            title: 'Track my cycle',
            description: 'Predictions, symptoms and patterns',
            selected: mode == TrackingMode.track,
            onTap: () => onModeChanged(TrackingMode.track),
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            title: 'Trying to conceive',
            description: 'Adds fertility signals and ovulation tracking',
            selected: mode == TrackingMode.conceive,
            onTap: () => onModeChanged(TrackingMode.conceive),
          ),
          const SizedBox(height: 24),
          Material(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              secondary: const Icon(Icons.diversity_3_outlined),
              title: const Text('Gender-neutral language'),
              subtitle: const Text('Inclusive wording throughout the app'),
              value: genderNeutral,
              onChanged: onGenderNeutralChanged,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LunaTrack provides estimates for general wellness. It is not '
                  'a contraceptive method and does not provide medical '
                  'diagnosis.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// A large number with a circular decrement/increment on either side. The
/// buttons are [IconButton.outlined], never `FilledButton`s — a filled button
/// in a `Row` demands infinite width and silently clips its neighbours.
class _HeroStepper extends StatelessWidget {
  const _HeroStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.caption,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final String unit;
  final String caption;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              tooltip: 'Fewer $unit',
              iconSize: 22,
              onPressed: value > min ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 140,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: text.displayLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  color: scheme.onSurface,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'More $unit',
              iconSize: 22,
              onPressed: value < max ? () => onChanged(value + 1) : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 220,
          child: Text(
            caption,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Full-width selectable card. Both options carry the same size and weight —
/// only the fill and the trailing tick differ, so neither reads as "the right
/// answer".
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.icon, required this.title, required this.body});
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
