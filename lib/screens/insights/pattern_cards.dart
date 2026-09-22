import 'package:flutter/material.dart';

import '../../common/catalog.dart';
import '../../models/enums.dart';
import '../../services/cycle_patterns_service.dart';

/// Card BODIES for the `CyclePatternsService` sections. `InsightsScreen` wraps
/// each in its own section card, so the headings stay in one place.

/// One plain-language line with a leading icon, styled like the "Your
/// patterns" rows.
class PatternLine extends StatelessWidget {
  const PatternLine(this.text, {super.key, this.icon = Icons.insights_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Metrics down the side, phases across the top. A blank cell is "not enough
/// readings in that phase", shown as a dash rather than a zero.
class PhaseProfileTable extends StatelessWidget {
  const PhaseProfileTable({super.key, required this.profile});

  final PhaseProfile profile;

  static const _headers = {
    CyclePhase.menstrual: 'Period',
    CyclePhase.follicular: 'Before\novulation',
    CyclePhase.ovulatory: 'Fertile\nwindow',
    CyclePhase.luteal: 'After\novulation',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final head = theme.textTheme.labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.2);
    final label = theme.textTheme.bodySmall
        ?.copyWith(fontWeight: FontWeight.w600);
    final cell = theme.textTheme.bodySmall;
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: const {0: FlexColumnWidth(1.3)},
      children: [
        TableRow(children: [
          const SizedBox.shrink(),
          for (final p in CyclePatternsService.phases)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_headers[p]!, textAlign: TextAlign.center, style: head),
            ),
        ]),
        for (final row in profile.rows)
          TableRow(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(row.label, style: label),
              ),
              for (final p in CyclePatternsService.phases)
                Text(row.cells[p] ?? '–',
                    textAlign: TextAlign.center, style: cell),
            ],
          ),
      ],
    );
  }
}

/// The usual flow for each day of a period, as a row of small labelled pills.
class FlowByDayRow extends StatelessWidget {
  const FlowByDayRow({super.key, required this.flows});

  final List<FlowIntensity> flows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < flows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Day ${i + 1}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Text(flows[i].label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
