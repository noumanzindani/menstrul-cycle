import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../common/catalog.dart';
import '../../models/cycle_overview.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Cycle overview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _SummaryHeader(range: range, overview: o),
          const SizedBox(height: 8),
          if (o.bleedingDays > 0)
            _Section(
              title: 'Bleeding',
              child: Text(
                '${o.bleedingDays} bleeding ${o.bleedingDays == 1 ? 'day' : 'days'}'
                '${o.peakFlow != null ? ', peaking ${o.peakFlow!.label.toLowerCase()}' : ''}.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (o.symptoms.isNotEmpty)
            _Section(title: 'Symptoms', child: _Counts(items: o.symptoms)),
          if (o.emotions.isNotEmpty)
            _Section(title: 'Emotions', child: _Counts(items: o.emotions)),
          if (o.painPeak != null)
            _Section(
              title: 'Pain',
              child: Text(
                'Averaging ${o.painAverage!.toStringAsFixed(1)}/10, '
                'peaking at ${o.painPeak}/10.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (o.lifestyle.isNotEmpty)
            _Section(title: 'Lifestyle', child: _Counts(items: o.lifestyle)),
          if (o.medications.isNotEmpty)
            _Section(title: 'Medications', child: _Counts(items: o.medications)),
          if (o.notesCount > 0)
            _Section(
              title: 'Notes',
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
    final scheme = Theme.of(context).colorScheme;
    final o = overview;
    final parts = <String>[
      'Period ${o.periodLength} ${o.periodLength == 1 ? 'day' : 'days'}',
      if (o.cycleLength != null) 'Cycle ${o.cycleLength} days',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(range,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(parts.join('  ·  '),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(i.label,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
                Text('${i.count} ${i.count == 1 ? 'day' : 'days'}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
              ],
            ),
          ),
      ],
    );
  }
}
