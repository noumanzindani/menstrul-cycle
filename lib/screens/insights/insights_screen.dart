import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../models/insights.dart';
import '../../models/prediction.dart';
import '../../providers/log_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/insights_service.dart';
import '../../services/pdf_report_service.dart';

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
    final cycles = context.watch<LogProvider>().cycles;
    final insights = InsightsService.analyze(cycles);
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
                const SizedBox(height: 20),
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
                if (insights.flags.isNotEmpty) ...[
                  Text('Worth noting',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (final f in insights.flags) _FlagCard(flag: f),
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
