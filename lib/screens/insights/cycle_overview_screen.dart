import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/catalog.dart';
import '../../models/cycle_overview.dart';
import '../../theme/app_theme.dart';

/// A single-cycle rollup: bleeding, symptoms, emotions, pain, lifestyle and
/// notes for one cycle in one place. Pure display over a pre-computed
/// [CycleOverview] — descriptive, never a diagnosis.
class CycleOverviewScreen extends StatelessWidget {
  const CycleOverviewScreen({super.key, required this.overview});
  final CycleOverview overview;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final df = DateFormat.MMMd();
    final range = '${df.format(o.start)} – ${df.format(o.periodEnd)}';
    // The full theme carries the phase tokens; a plain `ThemeData` (a bare test
    // harness) does not, so every read falls back to the colour scheme.
    final phases = Theme.of(context).extension<PhaseColors>();
    final scheme = Theme.of(context).colorScheme;
    Color dot(Color? phase) => phase ?? scheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Cycle overview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SummaryHeader(range: range, overview: o),
          if (o.bleedingDays > 0)
            _Section(
              title: 'Bleeding',
              color: dot(phases?.menstrual),
              child: Text(
                '${o.bleedingDays} bleeding ${o.bleedingDays == 1 ? 'day' : 'days'}'
                '${o.peakFlow != null ? ', peaking ${o.peakFlow!.label.toLowerCase()}' : ''}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (o.symptoms.isNotEmpty)
            _Section(
              title: 'Symptoms',
              color: dot(phases?.follicular),
              child: _Counts(items: o.symptoms),
            ),
          if (o.emotions.isNotEmpty)
            _Section(
              title: 'Emotions',
              color: dot(phases?.ovulatory),
              child: _Counts(items: o.emotions),
            ),
          if (o.painPeak != null)
            _Section(
              title: 'Pain',
              color: dot(phases?.luteal),
              child: Text(
                'Averaging ${o.painAverage!.toStringAsFixed(1)}/10, '
                'peaking at ${o.painPeak}/10.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (o.lifestyle.isNotEmpty)
            _Section(
              title: 'Lifestyle',
              color: dot(phases?.follicular),
              child: _Counts(items: o.lifestyle),
            ),
          if (o.medications.isNotEmpty)
            _Section(
              title: 'Medications',
              color: dot(phases?.predicted),
              child: _Counts(items: o.medications),
            ),
          if (o.notesCount > 0)
            _Section(
              title: 'Notes',
              color: dot(phases?.predicted),
              child: Text(
                '${o.notesCount} ${o.notesCount == 1 ? 'note' : 'notes'} logged '
                'this cycle.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.range, required this.overview});
  final String range;
  final CycleOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phases = theme.extension<PhaseColors>();
    final o = overview;
    final parts = <String>[
      'Period ${o.periodLength} ${o.periodLength == 1 ? 'day' : 'days'}',
      if (o.cycleLength != null) 'Cycle ${o.cycleLength} days',
    ];
    // The bleeding run against the whole cycle, drawn from the two figures
    // already printed above it. A completed cycle only — an open cycle has no
    // total to draw against, and inventing one would be a prediction.
    final total = o.cycleLength;
    final bleedFraction = total == null || total <= 0
        ? null
        : (o.periodLength / total).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(range,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                )),
            const SizedBox(height: 4),
            Text(parts.join('  ·  '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                )),
            if (bleedFraction != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Row(
                  children: [
                    Expanded(
                      flex: (bleedFraction * 1000).round().clamp(1, 999),
                      child: Container(
                        height: 10,
                        color: phases?.menstrual ?? scheme.primary,
                      ),
                    ),
                    Expanded(
                      flex: (1000 - (bleedFraction * 1000).round())
                          .clamp(1, 999),
                      child: Container(
                        height: 10,
                        color: scheme.surface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Day 1',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  Text('Day $total',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One rollup category, as a filled 20dp card headed by a phase-coloured dot
/// and the category name.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.color,
    required this.child,
  });
  final String title;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A quiet pill carrying one figure. It reads as a value, never as a status or
/// an award — there is nothing to earn on this screen.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}

/// Renders a list of labelled day-counts as "Label … N days" rows.
class _Counts extends StatelessWidget {
  const _Counts({required this.items});
  final List<LabeledCount> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(i.label,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                const SizedBox(width: 8),
                _CountPill(text: '${i.count} ${i.count == 1 ? 'day' : 'days'}'),
              ],
            ),
          ),
      ],
    );
  }
}
