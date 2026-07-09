import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/date_utils.dart';
import '../../common/insights_text.dart';
import '../../models/enums.dart';
import '../../models/insights.dart';
import '../../models/prediction.dart';
import '../../providers/settings_provider.dart';
import '../../services/prediction_service.dart';
import '../../services/pregnancy_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/disclaimer_banner.dart';
import '../log/day_log_screen.dart';
import '../pregnancy/pregnancy_screen.dart';

/// The "today" dashboard: where am I in my cycle, when is my next period, and
/// my estimated fertile window — all with supportive, non-alarmist framing.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    // Pregnancy mode replaces the whole dashboard — no period/fertility cards,
    // and no ads on this surface (council loss-safe rule).
    if (settings.isPregnant) {
      return _PregnancyHome(lmp: settings.pregnancyStartDate!);
    }

    final prediction = context.watch<PredictionResult>();
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('LunaTrack')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DayLogScreen(date: today)),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Log today'),
      ),
      body: Column(
        children: [
          Expanded(
            child: prediction.hasPrediction
                ? _PredictionBody(prediction: prediction, today: today)
                : const _EmptyState(),
          ),
          const SafeArea(top: false, child: AdBanner()),
        ],
      ),
    );
  }
}

/// The pregnancy dashboard: gestational age + an estimated due date, plainly
/// stated. No ads, no celebratory imagery, no fetal/medical content.
class _PregnancyHome extends StatelessWidget {
  const _PregnancyHome({required this.lmp});
  final DateTime lmp;

  @override
  Widget build(BuildContext context) {
    final ga = PregnancyService.gestationalAge(lmp);
    final due = PregnancyService.estimatedDueDate(lmp);
    final tri = PregnancyService.trimester(lmp);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('LunaTrack')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${ga.weeks} weeks${ga.days > 0 ? ' ${ga.days} days' : ''}',
                    style: text.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text('Trimester $tri',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  Text('Estimated due date',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  Text(DateFormat.yMMMMd().format(due),
                      style: text.titleMedium),
                  const SizedBox(height: 8),
                  Text('An estimate, not medical advice.',
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Period and fertility predictions are paused while pregnancy '
            'tracking is on.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PregnancyScreen()),
            ),
            child: const Text('Manage pregnancy tracking'),
          ),
        ],
      ),
    );
  }
}

/// A calm, single-line "Your patterns" highlight — the most notable narrative
/// about the user's own data. Descriptive, never a diagnosis or a number.
class _InsightHighlight extends StatelessWidget {
  const _InsightHighlight({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.insights_outlined,
                size: 20, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSecondaryContainer,
                      )),
            ),
          ],
        ),
      ),
    );
  }
}

class _PredictionBody extends StatelessWidget {
  const _PredictionBody({required this.prediction, required this.today});
  final PredictionResult prediction;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    // Mode-appropriate emphasis over the same data. Conceive leads with the
    // fertile window; perimenopause suppresses it entirely (the confidence cap
    // already muted the band) and shows an honest note instead.
    final mode = context.watch<SettingsProvider>().mode;
    final conceive = mode == TrackingMode.conceive;
    final peri = mode == TrackingMode.perimenopause;
    final fertile = _FertileCard(prediction: prediction, today: today);
    final nextPeriod = _NextPeriodCard(prediction: prediction, today: today);

    // The single most-notable pattern, if any. Skip the 'phase' narrative — the
    // _PhaseCard already says where the user is now — so this highlights a trend
    // or symptom correlation instead. Empty when data is still thin.
    final patterns =
        context.watch<List<CycleNarrative>>().where((n) => n.key != 'phase');
    final topInsight = patterns.isEmpty ? null : patterns.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _PhaseCard(prediction: prediction),
        const SizedBox(height: 12),
        if (topInsight != null) ...[
          _InsightHighlight(text: topInsight.text),
          const SizedBox(height: 12),
        ],
        if (peri) ...[
          nextPeriod,
          const SizedBox(height: 12),
          const _PerimenopauseNote(),
        ] else if (conceive) ...[
          fertile,
          const SizedBox(height: 12),
          nextPeriod,
        ] else ...[
          nextPeriod,
          const SizedBox(height: 12),
          fertile,
        ],
        const SizedBox(height: 16),
        const DisclaimerBanner(),
      ],
    );
  }
}

/// Perimenopause framing that replaces the fertile-window card. Two jobs: set
/// the expectation that estimates are rougher now, and — critically — state
/// that pregnancy is still possible so a hidden fertile window never reads as
/// "safe" (a core fertility guardrail).
class _PerimenopauseNote extends StatelessWidget {
  const _PerimenopauseNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.spa_outlined, color: scheme.onTertiaryContainer),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cycles may be irregular now',
                      style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onTertiaryContainer)),
                  const SizedBox(height: 4),
                  Text(
                    'In perimenopause, cycle timing becomes less predictable, so '
                    'these estimates get rougher. You can still become pregnant '
                    '— cycle timing is not a reliable guide.',
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onTertiaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({required this.prediction});
  final PredictionResult prediction;

  @override
  Widget build(BuildContext context) {
    final phases = Theme.of(context).extension<PhaseColors>()!;
    final accent = phases.forPhase(prediction.currentPhase);
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(width: 6, height: 64, color: accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (prediction.cycleDay != null)
                    Text('Day ${prediction.cycleDay}',
                        style: text.headlineMedium),
                  Text(prediction.currentPhase.label,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(prediction.currentPhase.description,
                      style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextPeriodCard extends StatelessWidget {
  const _NextPeriodCard({required this.prediction, required this.today});
  final PredictionResult prediction;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final next = prediction.nextPeriodStart!;
    final windowEnd = prediction.nextPeriodWindowEnd!;
    final days = daysBetween(today, next);
    final window = daysBetween(next, windowEnd);

    String headline;
    if (windowEnd.isBefore(today)) {
      headline = 'Your period may be late';
    } else if (days <= 0) {
      headline = 'Your period may start today';
    } else if (days == 1) {
      headline = 'Period expected tomorrow';
    } else {
      headline = 'Period in $days days';
    }

    return _InfoCard(
      icon: Icons.water_drop_outlined,
      title: headline,
      subtitle: 'Around ${DateFormat.MMMMd().format(next)} · ± $window days',
      trailing: _ConfidenceChip(confidence: prediction.confidence),
    );
  }
}

class _FertileCard extends StatelessWidget {
  const _FertileCard({required this.prediction, required this.today});
  final PredictionResult prediction;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    // Roll a passed fertile window forward one cycle so it stays "upcoming".
    var start = prediction.fertileWindowStart!;
    var end = prediction.fertileWindowEnd!;
    if (end.isBefore(today)) {
      final c = prediction.averageCycleLength;
      start = start.add(Duration(days: c));
      end = end.add(Duration(days: c));
    }
    final inWindow = !today.isBefore(start) && !today.isAfter(end);
    final range =
        '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(end)}';

    // Qualitative, confidence-gated fertility level for TODAY (never a number).
    // Uses the raw current-cycle window, so it self-suppresses once today is
    // past it — the displayed range may be the next cycle's, but the band is now.
    // Gated on fertilityConfidence, so a corroborating OPK unlocks it in-window.
    final band = PredictionService.fertilityBand(
      today: today,
      ovulation: prediction.ovulationDay,
      fertileWindowStart: prediction.fertileWindowStart,
      fertileWindowEnd: prediction.fertileWindowEnd,
      confidence: prediction.fertilityConfidence,
    );
    // The band is visible ONLY because a symptothermal signal raised confidence.
    final corroborated =
        prediction.fertilityConfidence.index > prediction.confidence.index;

    return _InfoCard(
      icon: Icons.eco_outlined,
      title: inWindow ? 'Fertile window (now)' : 'Estimated fertile window',
      subtitle: '$range · awareness only, not contraception',
      footer: band == FertilityBand.none
          ? null
          : _BandLabel(band: band, corroborated: corroborated),
    );
  }
}

/// A small qualitative fertility indicator — a coloured dot + words, never a
/// percentage. Shown only inside the fertile window at medium+ confidence.
/// [corroborated] means a positive/peak OPK unlocked the band — surfaced as a
/// quiet caption so the user knows what raised it (still awareness, not a %).
class _BandLabel extends StatelessWidget {
  const _BandLabel({required this.band, this.corroborated = false});
  final FertilityBand band;
  final bool corroborated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (band) {
      FertilityBand.peak => 'Most fertile today (estimated)',
      FertilityBand.higher => 'Higher chance today (estimated)',
      FertilityBand.lower => 'Lower chance today (estimated)',
      FertilityBand.none => '',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: scheme.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          if (corroborated)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Confirmed by your recent ovulation test',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.footer,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                  ?footer,
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});
  final PredictionConfidence confidence;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: confidence.hint,
      child: Chip(
        label: Text(confidence.label,
            style: Theme.of(context).textTheme.labelSmall),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.spa_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('Welcome to LunaTrack',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Log the days of your period and LunaTrack will start predicting '
              'your next one — all stored privately on this device.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DayLogScreen(date: today)),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Log today'),
            ),
          ],
        ),
      ),
    );
  }
}
