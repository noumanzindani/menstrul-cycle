import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/notification_service.dart';
import '../../services/pregnancy_service.dart';
import '../../theme/app_theme.dart';

/// Start, view, and end pregnancy tracking. Deliberately plain and non-medical:
/// weeks + an estimated due date, and a neutral one-step exit. No celebratory
/// UI, no fetal or size-comparison content, no illustrations, no ads — this
/// screen has to be survivable by someone who has had a loss, so nothing here
/// congratulates, counts down to a birth, or treats ending tracking as a
/// failure.
class PregnancyScreen extends StatelessWidget {
  const PregnancyScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 28)),
      firstDate: now.subtract(const Duration(days: 300)),
      lastDate: now,
      helpText: 'First day of your last period',
    );
    if (picked != null) {
      await settings.startPregnancy(picked);
      // A pregnant user shouldn't get "period expected soon" — cancel the
      // one-shot period/fertility reminders that may already be scheduled.
      await NotificationService.cancel(NotificationService.idPeriodSoon);
      await NotificationService.cancel(NotificationService.idFertile);
    }
  }

  Future<void> _end(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End pregnancy tracking?'),
        content: const Text(
          'This turns off pregnancy tracking and removes its data from this '
          'device. Your cycle history is not affected.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End tracking')),
        ],
      ),
    );
    if (confirmed != true) return;
    await settings.endPregnancy();
    messenger.showSnackBar(
      const SnackBar(content: Text('Pregnancy tracking ended.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lmp = settings.pregnancyStartDate;
    final tracking = settings.isPregnant && lmp != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Pregnancy')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children:
                  tracking ? _statusView(context, lmp) : _startView(context),
            ),
          ),
          // The exit lives in a fixed footer rather than under a long scroll:
          // it must never take hunting for.
          if (tracking)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _end(context),
                child: const Text('End pregnancy tracking'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _startView(BuildContext context) {
    return [
      const SizedBox(height: 8),
      Text(
        'Switch to pregnancy tracking',
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      Text(
        'While this is on, LunarFlow pauses period and fertility predictions '
        'and shows how far along you are, with an estimated due date. You can '
        'turn it off at any time.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => _start(context),
        child: const Text('Start pregnancy tracking'),
      ),
    ];
  }

  List<Widget> _statusView(BuildContext context, DateTime lmp) {
    final ga = PregnancyService.gestationalAge(lmp);
    final due = PregnancyService.estimatedDueDate(lmp);
    final tri = PregnancyService.trimester(lmp);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final phases = Theme.of(context).extension<PhaseColors>();

    return [
      // Hero: how far along, and nothing else competing with it.
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            children: [
              Text(
                'Week ${ga.weeks}',
                style: text.displaySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                _trimesterLabel(tri),
                style: text.titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              _TrimesterBar(trimester: tri, weeks: ga.weeks),
              const SizedBox(height: 12),
              Text(
                '${ga.weeks} weeks${ga.days > 0 ? ', ${ga.days} days' : ''} '
                'since your last period',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      // Info card: one label line, one large value, one "estimate" tag.
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: phases?.predicted ?? scheme.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Estimated due date',
                    style: text.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      DateFormat.yMMMMd().format(due),
                      style: text.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _EstimateTag(),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Dates are estimates from your last period (Naegele's rule), not "
              "medical advice. Your clinician's dating takes precedence.",
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    ];
  }

  static String _trimesterLabel(int trimester) => switch (trimester) {
        1 => 'First trimester',
        2 => 'Second trimester',
        _ => 'Third trimester',
      };
}

/// Three flat segments, one per trimester, filled up to where the pregnancy
/// currently sits. Not a completion ring and not a countdown: it says where you
/// are, never how much is "left".
class _TrimesterBar extends StatelessWidget {
  const _TrimesterBar({required this.trimester, required this.weeks});

  final int trimester;
  final int weeks;

  /// Trimester boundaries in weeks, matching [PregnancyService.trimester]:
  /// 1st = weeks 0–13, 2nd = 14–27, 3rd = 28 onwards (drawn to a 40-week term).
  static const _bounds = [(0, 14), (14, 28), (28, 40)];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: _Segment(
                  fraction: _fractionFor(i),
                  first: i == 0,
                  last: i == 2,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final label in ['1ST', '2ND', '3RD'])
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  double _fractionFor(int index) {
    final (start, end) = _bounds[index];
    final progress = (weeks - start) / (end - start);
    return progress.clamp(0.0, 1.0).toDouble();
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.fraction,
    required this.first,
    required this.last,
  });

  final double fraction;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.horizontal(
      left: Radius.circular(first ? 4 : 1),
      right: Radius.circular(last ? 4 : 1),
    );
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: 8,
        color: scheme.surfaceContainerHighest,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: Container(color: scheme.primary),
        ),
      ),
    );
  }
}

/// The design system's "estimate" tag — a quiet pill, never a confidence score.
class _EstimateTag extends StatelessWidget {
  const _EstimateTag();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phases = Theme.of(context).extension<PhaseColors>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (phases?.predicted ?? scheme.outline).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'estimate',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSurface),
      ),
    );
  }
}
