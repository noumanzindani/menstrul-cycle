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
                Text(
                  'Based on a ${settings.cycleLength}-day cycle and '
                  '${settings.periodLength}-day period.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final p in periods)
                  _PeriodCard(period: p, today: today),
                const SizedBox(height: 12),
                const DisclaimerBanner(),
              ],
            ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.today});
  final PredictedPeriod period;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final phases = Theme.of(context).extension<PhaseColors>()!;
    final scheme = Theme.of(context).colorScheme;
    final ongoing =
        !today.isBefore(period.start) && !today.isAfter(period.end);
    final daysAway = daysBetween(today, period.start);

    final sameMonth = period.start.month == period.end.month;
    final range = sameMonth
        ? '${DateFormat.MMMd().format(period.start)} – ${DateFormat.d().format(period.end)}'
        : '${DateFormat.MMMd().format(period.start)} – ${DateFormat.MMMd().format(period.end)}';

    String subtitle;
    if (ongoing) {
      subtitle = 'Predicted now';
    } else if (daysAway == 0) {
      subtitle = 'Starts today';
    } else if (daysAway == 1) {
      subtitle = 'In 1 day';
    } else {
      subtitle = 'In $daysAway days';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: phases.menstrual.withValues(alpha: ongoing ? 0.9 : 0.18),
                shape: BoxShape.circle,
                border: Border.all(
                    color: phases.menstrual.withValues(alpha: 0.6)),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.water_drop,
                  size: 20,
                  color: ongoing ? Colors.white : phases.menstrual),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(range,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${period.lengthDays} days',
                    style: Theme.of(context).textTheme.labelLarge),
                Text(
                  'fertile ${DateFormat.MMMd().format(period.fertileStart)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                Text(
                  'PMS ${DateFormat.MMMd().format(period.pmsStart)}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
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
              'Log your last period (or set it in onboarding) and LunaTrack '
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
