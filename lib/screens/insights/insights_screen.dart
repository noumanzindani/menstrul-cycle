import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../db/database.dart';
import '../../models/cycle.dart';
import '../../models/flow_analysis.dart';
import '../../models/insights.dart';
import '../../models/medication_adherence.dart';
import '../../models/prediction.dart';
import '../../models/symptom_analysis.dart';
import '../../providers/log_provider.dart';
import '../../providers/medication_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/bbt_service.dart';
import '../../services/cycle_overview_service.dart';
import '../../services/flow_analysis_service.dart';
import '../../services/insights_narrator.dart';
import '../../services/insights_service.dart';
import '../../services/medication_adherence_service.dart';
import '../../services/pdf_report_service.dart';
import '../../services/symptom_analysis_service.dart';
import '../../services/weight_trend_service.dart';
import '../../theme/app_theme.dart';
import 'cycle_overview_screen.dart';

/// Stats dashboard: summary tiles, a cycle-length trend, gentle red-flag
/// notices, and a "share with your doctor" PDF export.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  Future<void> _exportPdf(BuildContext context, Insights insights) async {
    // Capture everything from providers BEFORE the async gap. These reads live
    // here (not in build) so InsightsScreen stays pumpable without the
    // prediction/settings providers in ad_placement_test.
    final log = context.read<LogProvider>();
    final cycles = log.cycles;
    final logs = log.logs;
    final prediction = context.read<PredictionResult>();
    final mode = context.read<SettingsProvider>().mode;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await PdfReportService.build(
        insights: insights,
        cycles: cycles,
        logs: logs,
        prediction: prediction,
        mode: mode,
        generatedOn: DateTime.now(),
      );
      await Printing.sharePdf(bytes: bytes, filename: 'lunatrack_summary.pdf');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logProvider = context.watch<LogProvider>();
    final cycles = logProvider.cycles;
    final insights = InsightsService.analyze(cycles);
    final flow = FlowAnalysisService.analyze(cycles, logProvider.logs);
    final symptoms = SymptomAnalysisService.analyze(logProvider.logs);
    final nudges = InsightsService.patternNudges(
      cycles: cycles,
      logs: logProvider.logs,
    );
    final bbtLogs = [
      for (final l in logProvider.logs)
        if (l.bbt != null) l,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final thermalShift = BbtService.thermalShift(logProvider.logs);
    // Medication intake for the most recent *complete* cycle — a partial current
    // cycle would understate every count against a full-cycle scale.
    final meds =
        context.watch<MedicationProvider?>()?.items ?? const <Medication>[];
    final completeCycles = cycles.where((c) => c.isComplete).toList();
    final adherence = completeCycles.isEmpty
        ? const MedicationAdherence([])
        : MedicationAdherenceService.forCycle(
            completeCycles.last, logProvider.logs, meds);
    // Plain-language "Your patterns" narratives. No current-phase line here —
    // this screen is about history/patterns, not "where am I right now".
    final narratives =
        InsightsNarrator.narrate(cycles: cycles, logs: logProvider.logs);
    // Weight: descriptive series only. No BMI, no height, no classification —
    // a judgeable body label is the same class of harm as a synthesized
    // fertility percentage.
    final weightUnit =
        context.watch<SettingsProvider?>()?.weightUnit ?? kWeightUnitKg;
    final weightTrend = WeightTrendService.compute(
      logProvider.logs,
      asOf: DateTime.now(),
    );
    final stats = insights.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          if (stats.hasData)
            IconButton(
              tooltip: 'Export PDF for your doctor',
              icon: const Icon(Icons.ios_share),
              onPressed: () => _exportPdf(context, insights),
            ),
        ],
      ),
      body: !stats.hasData
          ? const _EmptyInsights()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _StatGrid(stats: stats),
                if (stats.regularity != CycleRegularity.unknown) ...[
                  const SizedBox(height: 12),
                  _RegularityCard(
                      regularity: stats.regularity,
                      variability: stats.variability),
                ],
                const SizedBox(height: 20),
                if (narratives.isNotEmpty) ...[
                  Text('Your patterns',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Plain-language notes from your own logs — descriptions, '
                    'not a diagnosis.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final n in narratives) _NarrativeCard(narrative: n),
                  const SizedBox(height: 20),
                ],
                if (insights.cycleLengthSeries.length >= 2) ...[
                  Text('Cycle length trend',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: _CycleTrendChart(
                        series: insights.cycleLengthSeries),
                  ),
                  const SizedBox(height: 20),
                ],
                if (flow.hasData) ...[
                  Text('Flow intensity trend',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Average bleeding heaviness per cycle, oldest to newest. '
                    'Self-reported — a description of your logs, not a diagnosis.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 180, child: _FlowChart(analysis: flow)),
                  const SizedBox(height: 20),
                ],
                if (symptoms.hasData) ...[
                  Text('Most-logged symptoms',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'How often each symptom appears in your logs'
                    '${symptoms.painPeak != null ? ', with your logged pain level' : ''}. '
                    'A count of what you logged — not a diagnosis.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _SymptomFrequencyList(analysis: symptoms),
                  const SizedBox(height: 20),
                ],
                if (cycles.isNotEmpty) ...[
                  Text('Cycle history',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Tap a cycle to see everything you logged in it.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _CycleHistory(
                    cycles: cycles,
                    logs: logProvider.logs,
                    medNames: {
                      for (final m
                          in context.watch<MedicationProvider?>()?.items ??
                              const [])
                        m.id: m.name,
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                if (adherence.hasData) ...[
                  Text('Medications this cycle',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Days you logged each medication in your last complete cycle.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _MedicationAdherenceList(adherence: adherence),
                  const SizedBox(height: 20),
                ],
                if (insights.flags.isNotEmpty) ...[
                  Text('Worth noting',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final f in insights.flags) _FlagCard(flag: f),
                ],
                if (nudges.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Patterns worth discussing',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'General observations from your logs — not a diagnosis. '
                    'A clinician can help you make sense of them.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final n in nudges) _NudgeCard(nudge: n),
                ],
                if (bbtLogs.length >= 2) ...[
                  const SizedBox(height: 20),
                  Text('Basal body temperature',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  SizedBox(height: 180, child: _BbtChart(readings: bbtLogs)),
                  if (thermalShift != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'A sustained temperature rise appeared around '
                          '${DateFormat.MMMd().format(thermalShift)}. This can '
                          'indicate ovulation has already happened this cycle — '
                          'it is awareness only, not a contraceptive method.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ],
                if (weightTrend != null) ...[
                  const SizedBox(height: 16),
                  Text('Weight',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 180,
                    child: _WeightChart(trend: weightTrend),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Latest '
                    '${formatWeightFromKg(weightTrend.points.last.kg, weightUnit)} '
                    '$weightUnit over ${weightTrend.points.length} readings — '
                    '${weightTrend.netChangeKg >= 0 ? 'up' : 'down'} '
                    '${formatWeightFromKg(weightTrend.netChangeKg.abs(), weightUnit)} '
                    '$weightUnit in the last 90 days.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _exportPdf(context, insights),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Export summary for your doctor'),
                ),
              ],
            ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats});
  final CycleStats stats;

  @override
  Widget build(BuildContext context) {
    String d(int? v) => v == null ? '—' : '$v';
    final tiles = <Widget>[
      _StatTile(label: 'Cycles tracked', value: '${stats.cyclesTracked}'),
      _StatTile(label: 'Avg cycle', value: '${d(stats.averageCycleLength)} d'),
      _StatTile(
          label: 'Range',
          value: '${d(stats.shortestCycle)}–${d(stats.longestCycle)} d'),
      _StatTile(
          label: 'Variability',
          value: '± ${stats.variability.toStringAsFixed(1)} d'),
      _StatTile(
          label: 'Avg period', value: '${d(stats.averagePeriodLength)} d'),
      _StatTile(
          label: 'Since last', value: '${d(stats.daysSinceLastPeriod)} d'),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.15,
      children: tiles,
    );
  }
}

/// Visualises the [CycleRegularity] category on a three-segment track, so the
/// variability number reads as a position rather than a bare figure. Gentle by
/// design — even "Irregular" uses a neutral accent, never an alarm colour.
class _RegularityCard extends StatelessWidget {
  const _RegularityCard(
      {required this.regularity, required this.variability});
  final CycleRegularity regularity;
  final double variability;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, index) = switch (regularity) {
      CycleRegularity.regular => ('Regular', 0),
      CycleRegularity.fairlyRegular => ('Fairly regular', 1),
      CycleRegularity.irregular => ('Irregular', 2),
      CycleRegularity.unknown => ('—', -1),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Regularity',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text(label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      )),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: i == index
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Based on ± ${variability.toStringAsFixed(1)} d of variation across '
            'your cycles — a description, not a diagnosis.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CycleTrendChart extends StatelessWidget {
  const _CycleTrendChart({required this.series});
  final List<int> series;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spots = [
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].toDouble()),
    ];
    final minY = (series.reduce((a, b) => a < b ? a : b) - 3).toDouble();
    final maxY = (series.reduce((a, b) => a > b ? a : b) + 3).toDouble();

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 3,
            color: scheme.primary,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bar per cycle (oldest → newest) whose height is that cycle's average
/// bleeding heaviness on the 1 (spotting) – 5 (very heavy) flow scale, tinted
/// with the menstrual token so heavier cycles read darker. Awareness only.
class _FlowChart extends StatelessWidget {
  const _FlowChart({required this.analysis});
  final FlowAnalysis analysis;

  static const _labels = {
    1: 'Spot',
    2: 'Light',
    3: 'Med',
    4: 'Heavy',
    5: 'V.heavy',
  };

  @override
  Widget build(BuildContext context) {
    // The menstrual token when the full app theme is present; a graceful
    // fallback to the scheme keeps the screen pumpable under a bare MaterialApp.
    final base = Theme.of(context).extension<PhaseColors>()?.menstrual ??
        Theme.of(context).colorScheme.primary;
    final pts = analysis.series;
    final groups = [
      for (var i = 0; i < pts.length; i++)
        BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: pts[i].avgIntensity,
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            color: base.withValues(
              alpha: (0.30 + 0.14 * pts[i].avgIntensity).clamp(0.30, 1.0),
            ),
          ),
        ]),
    ];

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 5,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(
            show: true, drawVerticalLine: false, horizontalInterval: 1),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final label = _labels[value.toInt()];
                if (label == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(label,
                      style: Theme.of(context).textTheme.labelSmall),
                );
              },
            ),
          ),
        ),
        barGroups: groups,
      ),
    );
  }
}

/// A ranked list of the most-logged symptoms as proportional bars, plus an
/// optional pain-severity summary. Uses plain bars (not a chart lib) so it reads
/// as a compact "top symptoms" leaderboard. Descriptive, never diagnostic.
/// Per-medication days-logged for the most recent complete cycle, as bars scaled
/// to the cycle length. A count, never a percentage (dosing frequency isn't
/// stored, so no adherence target is implied).
class _MedicationAdherenceList extends StatelessWidget {
  const _MedicationAdherenceList({required this.adherence});
  final MedicationAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in adherence.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(e.name,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: e.cycleLength == 0
                          ? 0
                          : (e.daysLogged / e.cycleLength).clamp(0.0, 1.0),
                      minHeight: 12,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${e.daysLogged} ${e.daysLogged == 1 ? 'day' : 'days'}',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SymptomFrequencyList extends StatelessWidget {
  const _SymptomFrequencyList({required this.analysis});
  final SymptomAnalysis analysis;

  static const _maxRows = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = analysis.ranked.take(_maxRows).toList();
    final maxCount = rows.first.dayCount; // ranked desc → first is the largest

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(s.label,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: s.dayCount / maxCount,
                      minHeight: 12,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor:
                          AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${s.dayCount} ${s.dayCount == 1 ? 'day' : 'days'}',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        if (analysis.painPeak != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Pain: averaging ${analysis.painAverage!.toStringAsFixed(1)}/10, '
              'peaking at ${analysis.painPeak}/10.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }
}

/// The user's cycles, newest first, each opening a per-cycle [CycleOverview].
/// The overview is computed lazily on tap so the list stays cheap.
class _CycleHistory extends StatelessWidget {
  const _CycleHistory({
    required this.cycles,
    required this.logs,
    this.medNames = const {},
  });
  final List<Cycle> cycles;
  final List<DailyLog> logs;

  /// Medication id → display name, so past cycles can label intake days even
  /// for medications the user has since disabled.
  final Map<int, String> medNames;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat.MMMd();
    final ordered = cycles.reversed.toList(); // newest first
    return Column(
      children: [
        for (final c in ordered)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${df.format(c.start)} – ${df.format(c.end)}'),
              subtitle: Text(c.lengthDays != null
                  ? '${c.lengthDays}-day cycle · ${c.periodLengthDays}-day period'
                  : 'Current cycle · ${c.periodLengthDays}-day period'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CycleOverviewScreen(
                    overview: CycleOverviewService.summarize(c, logs,
                        medNames: medNames),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({required this.flag});
  final RedFlag flag;

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
            Icon(Icons.lightbulb_outline, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(flag.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                              color: scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(flag.message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSecondaryContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple line chart of basal body temperature readings (oldest → newest),
/// for symptothermal awareness. Not connected to the fertility band.
class _BbtChart extends StatelessWidget {
  const _BbtChart({required this.readings});
  final List<DailyLog> readings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vals = [for (final r in readings) r.bbt!];
    final spots = [
      for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i]),
    ];
    final lo = vals.reduce((a, b) => a < b ? a : b) - 0.2;
    final hi = vals.reduce((a, b) => a > b ? a : b) + 0.2;

    return LineChart(
      LineChartData(
        minY: lo,
        maxY: hi,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2,
            color: scheme.tertiary,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}

/// The weight series. Mirrors [_BbtChart]'s fl_chart configuration so both
/// charts read the same. Plots the DISPLAY unit; the axis is bounded by the data
/// with no reference lines, because there is no "target" or "normal" band to
/// draw — that would be a body judgement, which this app does not make.
class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.trend});
  final WeightTrend trend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit =
        context.watch<SettingsProvider?>()?.weightUnit ?? kWeightUnitKg;
    final vals = [
      for (final p in trend.points)
        unit == kWeightUnitLb ? kgToLb(p.kg) : p.kg,
    ];
    final spots = [
      for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i]),
    ];
    final lo = vals.reduce((a, b) => a < b ? a : b) - 1;
    final hi = vals.reduce((a, b) => a > b ? a : b) + 1;

    return LineChart(
      LineChartData(
        minY: lo,
        maxY: hi,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2,
            color: scheme.primary,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}

/// A non-diagnostic "discuss with a clinician" prompt. Styled distinctly from
/// [_FlagCard] (a clinical/medical accent) so it reads as a gentle suggestion,
/// never an alarm or a diagnosis.
/// One "Your patterns" narrative — a calm, plain-language observation about the
/// user's own data. Never a diagnosis, never a number.
class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({required this.narrative});
  final CycleNarrative narrative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.insights_outlined,
                size: 20, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(narrative.text,
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

class _NudgeCard extends StatelessWidget {
  const _NudgeCard({required this.nudge});
  final PatternNudge nudge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.medical_services_outlined,
                color: scheme.onTertiaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nudge.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(nudge.message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onTertiaryContainer)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInsights extends StatelessWidget {
  const _EmptyInsights();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.insights_outlined,
                size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('No insights yet',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Log at least two periods and your stats, trends, and a '
              'doctor-ready summary will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
