import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../common/date_utils.dart';
import '../../common/l10n.dart';
import '../../models/enums.dart';
import '../../providers/log_provider.dart';
import '../../providers/settings_provider.dart';

/// First-run flow: privacy promise → cycle basics + last period → the profile
/// → done. Writing the last-period date seeds the first cycle so predictions
/// can start.
///
/// One question per step, in the design-system's stepper shape: a slim linear
/// progress line at the top, a left-aligned question, the answer control given
/// the whole middle of the screen, and a single full-width "Continue" pinned to
/// the bottom. Step 3 keeps an explicit **"I'm not sure"** escape — taking it
/// seeds no log, which lands the user on a genuinely different first Today
/// screen (no estimate at all, rather than a low-confidence one).
///
/// Steps 5 and 6 collect the profile — date of birth, height, current weight,
/// and the age at the first period. This wizard is where they are asked
/// because `AppGate` routes EVERY user through it, account holders and
/// local-only-hatch users alike; the sign-up form reaches only half of them.
/// **Every profile answer is skippable**, in exactly the sense step 3's date
/// already is: a skip is a first-class answer that stores NULL, invents no
/// default, and leaves the app behaving as it did before.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Matches the day editor's text fields, so the two numeric entry surfaces in
/// the app look like one another.
final OutlineInputBorder _kOnboardingFieldBorder = OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
);

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 11;

  /// Index of the height / weight / first-period page. Its two typed
  /// measurements are the only answers in the wizard that can be WRONG rather
  /// than merely absent, so leaving it runs [_readProfile]'s refusal check.
  static const _profilePage = 5;

  /// Birth-date window, in years before today. The picker's range IS the
  /// refusal here: a date outside it cannot be tapped at all, so no
  /// implausible birth date ever reaches the column — nothing is clamped.
  static const _minAgeYears = 8;
  static const _maxAgeYears = 100;

  /// Where the first-period stepper starts once the user touches it. It is NOT
  /// a default answer: until then the control reads "—" and saves null.
  static const _menarcheSeed = 12;

  final _controller = PageController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  int _page = 0;

  DateTime? _lastPeriod;
  int _cycleLength = 28;
  bool _genderNeutral = false;
  TrackingMode _mode = TrackingMode.track;

  // Profile answers. Each starts null and STAYS null when skipped.
  // [_profileWeightKg] is the "what do you weigh" profile fact behind the
  // doctor summary — deliberately NOT the per-day weight metric that drives
  // the 90-day trend chart, and neither ever reads from the other.
  DateTime? _dateOfBirth;
  double? _heightCm;
  double? _profileWeightKg;
  int? _menarcheAge;
  // Contraception. The only Tier 1 clinical question the wizard asks, because
  // it is the only one that changes what the app PREDICTS from day one: a
  // method that suppresses ovulation removes the fertile window. Diagnoses and
  // breastfeeding colour how results READ, so they live in Settings rather
  // than lengthening a first-run wizard.
  String? _contraception;
  // The signup sexual-health baseline: what is TYPICALLY true. Stored in one
  // JSON column, and deliberately NOT the same data as the `_today*` fields
  // below — those record what happened today and become a real log entry.
  String? _sexFrequency;
  String? _soloFrequency;
  String? _baselineLibido;
  final Set<String> _sexualHistory = {};
  // Today's answers, seeded into today's log on finish.
  String? _todaySex;
  final Set<String> _todaySexualHealth = {};
  String? _todayLibido;
  final Set<String> _todayIntimacy = {};
  String? _heightError;
  String? _weightError;

  @override
  void dispose() {
    _controller.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _next() {
    // Leaving the profile page re-reads the two typed measurements. An
    // unusable one is REFUSED: the wizard stays put showing an inline error
    // rather than advancing with a silently clamped value.
    if (_page == _profilePage && !_readProfile()) return;
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
    // A swipe reaches the last page without passing through [_next], so the
    // refusal is applied here too — an unusable measurement sends the user
    // back to the question instead of being dropped on the floor.
    if (!_readProfile()) {
      await _controller.animateToPage(
        _profilePage,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    final settings = context.read<SettingsProvider>();
    final logs = context.read<LogProvider>();

    await settings.setCycleLength(_cycleLength);
    await settings.setGenderNeutralLanguage(_genderNeutral);
    await settings.setMode(_mode);

    // The profile, in canonical units — CENTIMETRES and KILOGRAMS, converted
    // at the display boundary above. Written unconditionally, nulls included:
    // "skipped" is an answer, and writing it is what keeps these four setters
    // the single entry point for both setting and clearing.
    await settings.setDateOfBirth(_dateOfBirth);
    await settings.setHeightCm(_heightCm);
    await settings.setProfileWeightKg(_profileWeightKg);
    await settings.setMenarcheAge(_menarcheAge);
    // Null when skipped, which is not the same as `kContraceptionNone`: one
    // says nobody asked, the other says the user uses nothing. Only the second
    // belongs in a doctor report.
    await settings.setContraception(_contraception);
    await settings.setSexualBaseline(
      sexFrequency: _sexFrequency,
      soloFrequency: _soloFrequency,
      libido: _baselineLibido,
      history: _sexualHistory,
    );

    // Seed the last period so cycle stats have a starting anchor, and seed
    // today's day tags from the three sexual-health pages.
    //
    // These are ONE write when they fall on the same date. `saveDay` REPLACES a
    // day rather than merging into it, so two writes for one date would mean
    // the second silently erased the first — and the period the user had just
    // entered would vanish behind a day tag.
    final today = dateOnly(DateTime.now());
    final todayFlags = <String>{
      ..._todaySexualHealth,
      ..._todayIntimacy,
      ?_todaySex,
      ?_todayLibido,
    };
    final lastPeriodIsToday =
        _lastPeriod != null && dateOnly(_lastPeriod!) == today;

    if (_lastPeriod != null && !lastPeriodIsToday) {
      await logs.saveDay(
        date: _lastPeriod!,
        flow: FlowIntensity.medium,
        symptomsJson: encodeSymptoms({}),
      );
    }
    // An empty day is NOT written: a row with no flow and no tags reads as a
    // logged day forever after, and nothing would ever distinguish it from one
    // the user really did open and leave blank.
    if (lastPeriodIsToday || todayFlags.isNotEmpty) {
      await logs.saveDay(
        date: today,
        flow: lastPeriodIsToday ? FlowIntensity.medium : null,
        symptomsJson: encodeDayTags(flags: todayFlags),
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

  /// Same posture as [_skipDate] for the birth date. Clearing on the way out
  /// keeps "I'd rather not say" honest if a date was tapped first.
  void _skipBirthDate() {
    setState(() => _dateOfBirth = null);
    _next();
  }

  /// Reads the two typed measurements into canonical centimetres and
  /// kilograms, returning false when either is unusable.
  ///
  /// Blank is a first-class answer and reads as null. Anything unparseable or
  /// out of range is a REFUSAL — an inline error appears, nothing is stored,
  /// and the caller must not advance. [parseHeightToCm] / [parseWeightToKg]
  /// apply their range AFTER unit conversion, so the same rule holds whether
  /// the user typed centimetres or feet and inches.
  bool _readProfile() {
    final unit = context.read<SettingsProvider>().weightUnit;
    final rawHeight = _height.text.trim();
    final rawWeight = _weight.text.trim();

    double? cm;
    double? kg;
    String? heightError;
    String? weightError;

    if (rawHeight.isNotEmpty) {
      cm = parseHeightToCm(rawHeight, unit);
      if (cm == null) {
        final lo = formatHeightFromCm(kMinHeightCm, unit);
        final hi = formatHeightFromCm(kMaxHeightCm, unit);
        // Feet-and-inches already carries its own marks, so the unit word is
        // added for centimetres only rather than appended to both.
        heightError = unit == kWeightUnitLb
            ? 'Enter a height between $lo and $hi'
            : 'Enter a height between $lo and $hi cm';
      }
    }
    if (rawWeight.isNotEmpty) {
      kg = parseWeightToKg(rawWeight, unit);
      if (kg == null) {
        final lo = formatWeightFromKg(kMinWeightKg, unit);
        final hi = formatWeightFromKg(kMaxWeightKg, unit);
        weightError = 'Enter a weight between $lo and $hi $unit';
      }
    }

    setState(() {
      _heightCm = cm;
      _profileWeightKg = kg;
      _heightError = heightError;
      _weightError = weightError;
    });
    return heightError == null && weightError == null;
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
                  _BirthDatePage(
                    dateOfBirth: _dateOfBirth,
                    minAgeYears: _minAgeYears,
                    maxAgeYears: _maxAgeYears,
                    onDateChanged: (d) => setState(() => _dateOfBirth = d),
                    onSkip: _skipBirthDate,
                  ),
                  _ProfilePage(
                    height: _height,
                    weight: _weight,
                    heightError: _heightError,
                    weightError: _weightError,
                    menarcheAge: _menarcheAge,
                    menarcheSeed: _menarcheSeed,
                    onMenarcheChanged: (v) => setState(() => _menarcheAge = v),
                  ),
                  _ContraceptionPage(
                    method: _contraception,
                    onChanged: (m) => setState(() => _contraception = m),
                  ),
                  _SexBaselinePage(
                    frequency: _sexFrequency,
                    onFrequency: (v) => setState(() => _sexFrequency = v),
                    today: _todaySex,
                    onToday: (v) => setState(() => _todaySex = v),
                  ),
                  _SexualHealthBaselinePage(
                    history: _sexualHistory,
                    onHistory: (key, on) => setState(() =>
                        on ? _sexualHistory.add(key) : _sexualHistory.remove(key)),
                    libido: _baselineLibido,
                    onLibido: (v) => setState(() => _baselineLibido = v),
                    today: _todaySexualHealth,
                    onToday: (key, on) => setState(() => on
                        ? _todaySexualHealth.add(key)
                        : _todaySexualHealth.remove(key)),
                    todayLibido: _todayLibido,
                    onTodayLibido: (v) => setState(() => _todayLibido = v),
                  ),
                  _IntimacyBaselinePage(
                    frequency: _soloFrequency,
                    onFrequency: (v) => setState(() => _soloFrequency = v),
                    today: _todayIntimacy,
                    onToday: (key, on) => setState(() =>
                        on ? _todayIntimacy.add(key) : _todayIntimacy.remove(key)),
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

/// Step 5 — date of birth. Same shape as [_LastPeriodPage] (an inline picker
/// plus an explicit skip), with two differences that matter: the window is a
/// lifetime rather than the last four months, and the picker opens on the YEAR
/// grid because nobody pages back through thirty years of months.
///
/// The window IS the refusal: a date outside [minAgeYears]..[maxAgeYears]
/// cannot be tapped, so an implausible birth date never reaches the column and
/// nothing has to be clamped after the fact.
class _BirthDatePage extends StatelessWidget {
  const _BirthDatePage({
    required this.dateOfBirth,
    required this.minAgeYears,
    required this.maxAgeYears,
    required this.onDateChanged,
    required this.onSkip,
  });

  final DateTime? dateOfBirth;
  final int minAgeYears;
  final int maxAgeYears;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final youngest = DateTime(now.year - minAgeYears, now.month, now.day);
    final oldest = DateTime(now.year - maxAgeYears, now.month, now.day);
    return _QuestionPage(
      question: 'When were you born?',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          CalendarDatePicker(
            initialDate: dateOfBirth,
            // "Today" for this picker is the youngest selectable day, NOT the
            // real today: with no answer yet the grid opens on `currentDate`,
            // and the real today sits years outside the window.
            currentDate: youngest,
            firstDate: oldest,
            lastDate: youngest,
            initialCalendarMode: DatePickerMode.year,
            onDateChanged: onDateChanged,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: const Text("I'd rather not say"),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your age gives your own numbers some context in the summary you '
            'can share with your doctor. Skipping is fine — nothing else in '
            'LunaTrack depends on it.',
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

/// Step 6 — height, current weight, and the age at the first period. Three
/// answers on one page because they are one question in the user's head ("a
/// bit about my body"), and because each is individually skippable: a blank
/// field and an untouched stepper both store NULL.
///
/// **"Current weight" is a profile fact, and deliberately separate from the
/// daily weight metric** behind the 90-day trend chart. They are labelled
/// differently on purpose ("Current weight" here, "Weight" in the day editor)
/// and neither may ever be made to read from the other.
///
/// Both measurements ride the EXISTING weight-unit preference: kg means
/// centimetres and kilograms, lb means feet/inches and pounds. There is no
/// separate height unit.
class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.height,
    required this.weight,
    required this.heightError,
    required this.weightError,
    required this.menarcheAge,
    required this.menarcheSeed,
    required this.onMenarcheChanged,
  });

  final TextEditingController height;
  final TextEditingController weight;
  final String? heightError;
  final String? weightError;
  final int? menarcheAge;
  final int menarcheSeed;
  final ValueChanged<int?> onMenarcheChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Nullable read, like the day editor's: the page stays pumpable without a
    // SettingsProvider, and kg is what an unanswered preference means.
    final unit =
        context.watch<SettingsProvider?>()?.weightUnit ?? kWeightUnitKg;
    final imperial = unit == kWeightUnitLb;
    return _QuestionPage(
      question: 'A few more details about you',
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Text(
            'All optional. These appear in the summary you can share with your '
            'doctor — leave any of them blank and LunaTrack leaves them out.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          TextField(
            key: const Key('onboarding-height-field'),
            controller: height,
            keyboardType: imperial
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Height',
              hintText: imperial ? "5'5\"" : null,
              suffixText: imperial ? 'ft, in' : 'cm',
              errorText: heightError,
              border: _kOnboardingFieldBorder,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('onboarding-weight-field'),
            controller: weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Current weight',
              suffixText: unit,
              errorText: weightError,
              border: _kOnboardingFieldBorder,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Age at your first period',
            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: const Key('menarche-stepper'),
            child: _HeroStepper(
              value: menarcheAge,
              min: 8,
              max: 20,
              unsetValue: menarcheSeed,
              unit: 'years',
              caption: 'how old you were when your first period started',
              onChanged: (v) => onMenarcheChanged(v),
            ),
          ),
          if (menarcheAge != null)
            Center(
              child: TextButton(
                onPressed: () => onMenarcheChanged(null),
                child: const Text("I'm not sure"),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Step 7 — what the app is for, plus the wording preference. Two equal cards,
/// neither styled as the recommended answer.
/// Contraception method. Scrolls, because thirteen methods do not fit a phone
/// page — and the list is deliberately long rather than collapsed into
/// "hormonal / non-hormonal": the distinction the app acts on is which specific
/// methods suppress ovulation, and asking the user to make that call for us
/// would be asking them a clinical question instead of a factual one.
///
/// Skippable like every other wizard answer: walking past leaves the column
/// null, and the app behaves exactly as it did before the question existed.
class _ContraceptionPage extends StatelessWidget {
  const _ContraceptionPage({required this.method, required this.onChanged});

  final String? method;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return _QuestionPage(
      question: l10n.onboardingContraceptionTitle,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              l10n.onboardingContraceptionBody,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final o in kContraceptionOptions) ...[
            _ChoiceCard(
              title: o.label,
              description: o.key == kContraceptionNone
                  ? 'Not using contraception right now'
                  : '',
              selected: method == o.key,
              // Tapping the selected card again clears it, so a mis-tap is
              // recoverable without a separate Skip control.
              onTap: () => onChanged(method == o.key ? null : o.key),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Shared scaffolding for the three sexual-health signup pages.
///
/// Each asks TWO questions that look similar and are not: a BASELINE ("how
/// often, generally") that is stored once in settings, and a TODAY answer that
/// becomes a real day-tag entry. Keeping them visually separated matters —
/// a user who reads the second as a rephrasing of the first will answer it
/// wrongly, and the two can never be reconciled afterwards.
class _BaselineScaffold extends StatelessWidget {
  const _BaselineScaffold({
    required this.question,
    required this.baseline,
    required this.todayLabel,
    required this.today,
  });

  final String question;
  final List<Widget> baseline;
  final String todayLabel;
  final List<Widget> today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _QuestionPage(
      question: question,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          ...baseline,
          const SizedBox(height: 28),
          Divider(color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            todayLabel,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Optional — this one is logged as today, not as a general answer.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          ...today,
        ],
      ),
    );
  }
}

/// Frequency choices, rendered as the same cards the mode page uses.
List<Widget> _frequencyCards(String? selected, ValueChanged<String?> onPick) => [
      for (final o in kFrequencyOptions) ...[
        _ChoiceCard(
          title: o.label,
          description: '',
          selected: selected == o.key,
          // Tapping the selected card clears it, so a mis-tap is recoverable
          // without a separate skip control on every page.
          onTap: () => onPick(selected == o.key ? null : o.key),
        ),
        const SizedBox(height: 8),
      ],
    ];

/// Small chips for the "today" half, matching the day editor's shape.
Widget _todayChips({
  required List<TrackOption> options,
  required bool Function(String) isSelected,
  required void Function(String, bool) onToggle,
}) =>
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o.label),
            selected: isSelected(o.key),
            onSelected: (on) => onToggle(o.key, on),
          ),
      ],
    );

class _SexBaselinePage extends StatelessWidget {
  const _SexBaselinePage({
    required this.frequency,
    required this.onFrequency,
    required this.today,
    required this.onToday,
  });

  final String? frequency;
  final ValueChanged<String?> onFrequency;
  final String? today;
  final ValueChanged<String?> onToday;

  @override
  Widget build(BuildContext context) => _BaselineScaffold(
        question: 'How often do you have sex?',
        baseline: _frequencyCards(frequency, onFrequency),
        todayLabel: 'Today',
        today: [
          _todayChips(
            options: kSexOptions,
            isSelected: (k) => today == k,
            onToggle: (k, on) => onToday(on ? k : null),
          ),
        ],
      );
}

class _SexualHealthBaselinePage extends StatelessWidget {
  const _SexualHealthBaselinePage({
    required this.history,
    required this.onHistory,
    required this.libido,
    required this.onLibido,
    required this.today,
    required this.onToday,
    required this.todayLibido,
    required this.onTodayLibido,
  });

  final Set<String> history;
  final void Function(String, bool) onHistory;
  final String? libido;
  final ValueChanged<String?> onLibido;
  final Set<String> today;
  final void Function(String, bool) onToday;
  final String? todayLibido;
  final ValueChanged<String?> onTodayLibido;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _BaselineScaffold(
      question: 'Have you ever experienced any of these?',
      baseline: [
        _todayChips(
          options: kSexualHistoryOptions,
          isSelected: history.contains,
          onToggle: onHistory,
        ),
        const SizedBox(height: 24),
        Text('Your libido, generally',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _todayChips(
          options: kLibidoOptions,
          isSelected: (k) => libido == k,
          onToggle: (k, on) => onLibido(on ? k : null),
        ),
      ],
      todayLabel: 'Today',
      today: [
        _todayChips(
          options: kSexualHealthOptions,
          isSelected: today.contains,
          onToggle: onToday,
        ),
        const SizedBox(height: 12),
        _todayChips(
          options: kLibidoOptions,
          isSelected: (k) => todayLibido == k,
          onToggle: (k, on) => onTodayLibido(on ? k : null),
        ),
      ],
    );
  }
}

class _IntimacyBaselinePage extends StatelessWidget {
  const _IntimacyBaselinePage({
    required this.frequency,
    required this.onFrequency,
    required this.today,
    required this.onToday,
  });

  final String? frequency;
  final ValueChanged<String?> onFrequency;
  final Set<String> today;
  final void Function(String, bool) onToday;

  @override
  Widget build(BuildContext context) => _BaselineScaffold(
        question: 'How often do you masturbate?',
        baseline: _frequencyCards(frequency, onFrequency),
        todayLabel: 'Today',
        today: [
          _todayChips(
            options: kIntimacyOptions,
            isSelected: today.contains,
            onToggle: onToday,
          ),
        ],
      );
}

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
///
/// [value] is nullable so the same control can hold an UNANSWERED question: it
/// then reads "—", decrement is disabled, and the first increment seeds
/// [unsetValue]. A big number showing while the column is still null would be
/// the control inventing a default the user never gave — which is exactly what
/// a skippable profile question must not do.
class _HeroStepper extends StatelessWidget {
  const _HeroStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.caption,
    required this.onChanged,
    this.unsetValue = 0,
  });

  final int? value;
  final int min;
  final int max;
  final String unit;
  final String caption;
  final ValueChanged<int> onChanged;

  /// Where an unanswered stepper starts on its first increment. Unused when
  /// [value] is never null (the cycle-length step).
  final int unsetValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final current = value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              tooltip: 'Fewer $unit',
              iconSize: 22,
              onPressed: current != null && current > min
                  ? () => onChanged(current - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 140,
              child: Text(
                current == null ? '—' : '$current',
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
              onPressed: current == null
                  ? () => onChanged(unsetValue)
                  : (current < max ? () => onChanged(current + 1) : null),
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
