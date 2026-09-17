import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/date_utils.dart';
import '../../models/prediction.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/disclaimer_banner.dart';

/// Lists the next 12 predicted periods (start–end) computed from the user's
/// entered cycle length. Estimates only — never contraception.
class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final periods = context.watch<List<PredictedPeriod>>();
    final settings = context.watch<SettingsProvider>();
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Forecast')),
      bottomNavigationBar: const SafeArea(child: AdBanner()),
      body: periods.isEmpty
          ? const _EmptyForecast()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _ExplainerCard(
                  cycleLength: settings.cycleLength,
                  periodLength: settings.periodLength,
                ),
                const SizedBox(height: 16),
                for (final p in periods)
                  _PeriodCard(period: p, today: today),
                const SizedBox(height: 8),
                const DisclaimerBanner(),
              ],
            ),
    );
  }
}

/// A leading, plain-language note on where the forecast comes from. Framed as
/// an estimate that improves with logging — never as a promise.
class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard({
    required this.cycleLength,
    required this.periodLength,
  });

  final int cycleLength;
  final int periodLength;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These are estimates from the days you log, based on a '
              '$cycleLength-day cycle and a $periodLength-day period. They get '
              'better the more you log.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small phase-coloured dot + an uppercase eyebrow label, the design system's
/// way of naming what a value line is about.
class _DotLabel extends StatelessWidget {
  const _DotLabel({required this.color, required this.label, this.trailing});

  final Color color;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
          ),
        ),
        // Flexible, not fixed: a large system text scale shrinks the tag rather
        // than overflowing the row and clipping it off-screen.
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Flexible(child: trailing!),
        ],
      ],
    );
  }
}

/// The "ESTIMATE" tag every forecast card carries. Estimates are always
/// labelled as estimates — a forecast card must never read as a fact.
class _EstimateTag extends StatelessWidget {
  const _EstimateTag();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'ESTIMATE',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              fontSize: 10,
            ),
      ),
    );
  }
}

/// Formats a date range compactly: "16 – 21 Sep" inside one month, otherwise
/// "28 Jan – 2 Feb".
String _range(DateTime start, DateTime end) {
  if (start.month == end.month && start.year == end.year) {
    return '${DateFormat.MMMd().format(start)} – ${DateFormat.d().format(end)}';
  }
  return '${DateFormat.MMMd().format(start)} – ${DateFormat.MMMd().format(end)}';
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.today});
  final PredictedPeriod period;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phases = theme.extension<PhaseColors>()!;
    final scheme = theme.colorScheme;
    final ongoing =
        !today.isBefore(period.start) && !today.isAfter(period.end);
    final daysAway = daysBetween(today, period.start);

    String when;
    if (ongoing) {
      when = 'Predicted now';
    } else if (daysAway == 0) {
      when = 'Starts today';
    } else if (daysAway == 1) {
      when = 'In 1 day';
    } else {
      when = 'In $daysAway days';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      // The nearest predicted period is the one the user came here for: it is
      // outlined in the menstrual token rather than filled with it, so it reads
      // as "this one" without reading as an alert.
      shape: ongoing
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                  color: phases.menstrual.withValues(alpha: 0.55)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DotLabel(
              color: phases.menstrual,
              label: 'PERIOD',
              trailing: const _EstimateTag(),
            ),
            const SizedBox(height: 6),
            Text(
              _range(period.start, period.end),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${period.lengthDays} days · $when',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Divider(
                height: 1, thickness: 1, color: scheme.outlineVariant),
            const SizedBox(height: 14),
            _DotLabel(color: phases.fertile, label: 'FERTILE WINDOW'),
            const SizedBox(height: 4),
            Text(
              _range(period.fertileStart, period.fertileEnd),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            _DotLabel(color: phases.luteal, label: 'PMS'),
            const SizedBox(height: 4),
            Text(
              _range(period.pmsStart, period.pmsEnd),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyForecast extends StatelessWidget {
  const _EmptyForecast();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_note_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No forecast yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Log your last period (or set it in onboarding) and LunarFlow '
              'will map out your upcoming cycles here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
