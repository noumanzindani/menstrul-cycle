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
import '../../services/bmi_service.dart';
import '../../services/cycle_overview_service.dart';
import '../../services/flow_analysis_service.dart';
import '../../services/insights_narrator.dart';
import '../../services/insights_service.dart';
import '../../services/medication_adherence_service.dart';
import '../../services/pdf_report_service.dart';
import '../../services/symptom_analysis_service.dart';
import '../../services/weight_trend_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/disclaimer_banner.dart';
import 'cycle_overview_screen.dart';

/// Years since the user's first period: the age they have reached today minus
/// the age they gave for menarche.
///
/// DERIVED, never stored. Two independent reasons, either one sufficient: a
/// stored copy would keep disagreeing with the profile after any edit to
/// either field, and this figure changes on its own every birthday, so it
/// would be wrong within a year even if nothing were ever edited.
///
/// Null unless both fields are answered and the arithmetic is possible. A
/// menarche age the user has not lived to yet is a typo, not a negative
/// gynaecological age, so it is refused and nothing is shown - the same
/// posture the profile fields take at the input boundary.
@visibleForTesting
int? gynaecologicalAgeYears({
  required DateTime? dateOfBirth,
  required int? menarcheAge,
  required DateTime asOf,
}) {
  if (dateOfBirth == null || menarcheAge == null) return null;
  if (menarcheAge < 0) return null;
  // Whole years actually lived: a birthday later this calendar year has not
  // been reached, so the year difference alone would over-count by one.
  var age = asOf.year - dateOfBirth.year;
  final reachedBirthday = asOf.month > dateOfBirth.month ||
      (asOf.month == dateOfBirth.month && asOf.day >= dateOfBirth.day);
  if (!reachedBirthday) age -= 1;
  if (age < 0) return null;
  final years = age - menarcheAge;
  return years < 0 ? null : years;
}

/// "1 year" / "N years" - a lone "1 years" in the card reads as a bug.
String _yearsLabel(int years) => years == 1 ? '1 year' : '$years years';

/// Stats dashboard: summary tiles, a cycle-length trend, gentle red-flag
/// notices, and a "share with your doctor" PDF export.
///
/// Every section is one filled 20dp card with a phase-coloured dot beside its
/// name, so the screen reads as a stack of equal-weight observations rather
/// than a wall of headings — and nothing on it is ever styled as an alarm.
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
    final settings = context.read<SettingsProvider>();
    final mode = settings.mode;
    // The clinician profile header. Passed in canonical units — the report
    // prints cm/kg regardless of `weightUnit`, as a clinical document should.
    // These are the PROFILE fields, not the per-day `kMetricWeight` metric that
    // feeds the trend chart further down the same report.
    final dateOfBirth = settings.dateOfBirth;
    final heightCm = settings.heightCm;
    final profileWeightKg = settings.profileWeightKg;
    final menarcheAge = settings.menarcheAge;
    // The clinical context a reader needs before the cycle numbers mean
    // anything. Read here with the rest, before the async gap.
    final contraceptionMethod = settings.contraceptionMethod;
    final contraceptionStartDate = settings.contraceptionStartDate;
    final knownDiagnoses = settings.knownDiagnoses;
    final breastfeeding = settings.breastfeeding;
    final breastfeedingSince = settings.breastfeedingSince;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await PdfReportService.build(
        insights: insights,
        cycles: cycles,
        logs: logs,
        prediction: prediction,
        mode: mode,
        generatedOn: DateTime.now(),
        dateOfBirth: dateOfBirth,
        heightCm: heightCm,
        profileWeightKg: profileWeightKg,
        menarcheAge: menarcheAge,
        contraceptionMethod: contraceptionMethod,
        contraceptionStartDate: contraceptionStartDate,
        knownDiagnoses: knownDiagnoses,
        breastfeeding: breastfeeding,
        breastfeedingSince: breastfeedingSince,
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
    // The saved profile answers, read once for everything that needs them.
    // Optional, like every other provider read in this build: the screen has
    // to stay pumpable without a SettingsProvider (see ad_placement_test).
    final settings = context.watch<SettingsProvider?>();
    // Weight trend: a descriptive series only, one value and one direction,
    // never a category. The judgeable figure the owner approved on 2026-09-13
    // is a separate card below, composed entirely inside BmiService, and it
    // reads the PROFILE weight rather than this per-day metric.
    final weightUnit = settings?.weightUnit ?? kWeightUnitKg;
    final weightTrend = WeightTrendService.compute(
      logProvider.logs,
      asOf: DateTime.now(),
    );
    // Both profile figures are DERIVED at read time from the four raw answers
    // and never stored: a stored copy would silently disagree with the profile
    // after any edit, and the first one moves on its own every birthday.
    // They degrade independently - two answers feed each, and a missing pair
    // hides only its own line, never the other.
    final gynYears = gynaecologicalAgeYears(
      dateOfBirth: settings?.dateOfBirth,
      menarcheAge: settings?.menarcheAge,
      asOf: DateTime.now(),
    );
    // Read out verbatim, never re-composed here. BmiService owns every
    // user-facing word of this line, prefix and band label included, and the
    // structural scan in test/weight_trend_service_test.dart exempts that one
    // file alone; a string assembled here would fail it, correctly.
    final profileIndex = BmiService.bmiReadout(
      heightCm: settings?.heightCm,
      weightKg: settings?.profileWeightKg,
    );
    final stats = insights.stats;
    // The full app theme carries the phase tokens; a bare `ThemeData` (as used
    // by several widget-test harnesses) does not, so every read is optional and
    // falls back to the colour scheme.
    final phases = Theme.of(context).extension<PhaseColors>();
    final scheme = Theme.of(context).colorScheme;

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
                const SizedBox(height: 12),
                if (stats.regularity != CycleRegularity.unknown)
                  _RegularityCard(
                      regularity: stats.regularity,
                      variability: stats.variability),
                if (gynYears != null || profileIndex != null)
                  _SectionCard(
                    title: 'From your profile',
                    dotColor: phases?.follicular,
                    subtitle: 'Worked out from the answers you saved in your '
                        'profile, not from your logs. Descriptions, not a '
                        'diagnosis.',
                    child: Column(
                      children: [
                        if (gynYears != null)
                          _NoticeRow(
                            icon: Icons.timelapse_outlined,
                            title:
                                'Gynaecological age: ${_yearsLabel(gynYears)}',
                            message: 'The time since your first period, from '
                                'your date of birth and the age you gave for '
                                'it. Cycle length is commonly more variable in '
                                'the years soon after a first period.',
                          ),
                        if (profileIndex != null)
                          _NoticeRow(
                            icon: Icons.straighten_outlined,
                            title: profileIndex,
                            message: 'From the height and current weight you '
                                'saved on your profile, not from the weights '
                                'you log day to day.',
                          ),
                      ],
                    ),
                  ),
                if (narratives.isNotEmpty)
                  _SectionCard(
                    title: 'Your patterns',
                    dotColor: phases?.predicted,
                    subtitle: 'Plain-language notes from your own logs — '
                        'descriptions, not a diagnosis.',
                    child: Column(
                      children: [
                        for (final n in narratives)
                          _NarrativeRow(narrative: n),
                      ],
                    ),
                  ),
                if (insights.cycleLengthSeries.length >= 2)
                  _SectionCard(
                    title: 'Cycle length trend',
                    dotColor: phases?.predicted,
                    child: SizedBox(
                      height: 180,
                      child: _CycleTrendChart(
                          series: insights.cycleLengthSeries),
                    ),
                  ),
                if (flow.hasData)
                  _SectionCard(
                    title: 'Flow intensity trend',
                    dotColor: phases?.menstrual,
                    subtitle:
                        'Average bleeding heaviness per cycle, oldest to newest. '
                        'Self-reported — a description of your logs, not a diagnosis.',
                    child: SizedBox(height: 170, child: _FlowChart(analysis: flow)),
                  ),
                if (symptoms.hasData)
                  _SectionCard(
                    title: 'Most-logged symptoms',
                    dotColor: phases?.follicular,
                    subtitle: 'How often each symptom appears in your logs'
                        '${symptoms.painPeak != null ? ', with your logged pain level' : ''}. '
                        'A count of what you logged — not a diagnosis.',
                    child: _SymptomFrequencyList(analysis: symptoms),
                  ),
                if (cycles.isNotEmpty)
                  _SectionCard(
                    title: 'Cycle history',
                    dotColor: phases?.menstrual,
                    subtitle: 'Tap a cycle to see everything you logged in it.',
                    contentPadding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                    child: _CycleHistory(
                      cycles: cycles,
                      logs: logProvider.logs,
                      medNames: {
                        for (final m
                            in context.watch<MedicationProvider?>()?.items ??
                                const [])
                          m.id: m.name,
                      },
                    ),
                  ),
                if (adherence.hasData)
                  _SectionCard(
                    title: 'Medications this cycle',
                    dotColor: phases?.predicted,
                    subtitle:
                        'Days you logged each medication in your last complete cycle.',
                    child: _MedicationAdherenceList(adherence: adherence),
                  ),
                if (insights.flags.isNotEmpty)
                  _SectionCard(
                    title: 'Worth noting',
                    dotColor: phases?.luteal,
                    child: Column(
                      children: [
                        for (final f in insights.flags)
                          _NoticeRow(
                            icon: Icons.lightbulb_outline,
                            title: f.title,
                            message: f.message,
                          ),
                      ],
                    ),
                  ),
                if (nudges.isNotEmpty)
                  _SectionCard(
                    title: 'Patterns worth discussing',
                    dotColor: phases?.ovulatory,
                    subtitle:
                        'General observations from your logs — not a diagnosis. '
                        'A clinician can help you make sense of them.',
                    child: Column(
                      children: [
                        for (final n in nudges)
                          _NoticeRow(
                            icon: Icons.medical_services_outlined,
                            title: n.title,
                            message: n.message,
                          ),
                      ],
                    ),
                  ),
                if (bbtLogs.length >= 2)
                  _SectionCard(
                    title: 'Basal body temperature',
                    dotColor: phases?.ovulatory,
                    subtitle: 'An observation, not a diagnosis.',
                    child: Column(
                      children: [
                        SizedBox(height: 170, child: _BbtChart(readings: bbtLogs)),
                        if (thermalShift != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            'A sustained temperature rise appeared around '
                            '${DateFormat.MMMd().format(thermalShift)}. This can '
                            'indicate ovulation has already happened this cycle — '
                            'it is awareness only, not a contraceptive method.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (weightTrend != null)
                  _SectionCard(
                    title: 'Weight',
                    dotColor: phases?.predicted,
                    // A value and a direction, never a category. No BMI, no
                    // target, no "ideal range" band on the chart.
                    trailing: Text(
                      '${weightTrend.netChangeKg >= 0 ? 'up' : 'down'} '
                      '${formatWeightFromKg(weightTrend.netChangeKg.abs(), weightUnit)}'
                      ' $weightUnit',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 170,
                          child: _WeightChart(trend: weightTrend),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Latest '
                            '${formatWeightFromKg(weightTrend.points.last.kg, weightUnit)} '
                            '$weightUnit across ${weightTrend.points.length} '
                            'readings in the last 90 days.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _exportPdf(context, insights),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Export summary for your doctor'),
                ),
                // Required on every surface that carries estimates or any
                // fertility/ovulation observation — the thermal-shift note and
                // the exported report both do. A permanent designed element,
                // never an error state.
                const SizedBox(height: 16),
                const DisclaimerBanner(),
              ],
            ),
    );
  }
}

/// The workhorse container: one filled 20dp card per section, headed by a small
/// phase-coloured dot, the section name, and an optional trailing value.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.dotColor,
    this.subtitle,
    this.trailing,
    this.contentPadding = const EdgeInsets.all(20),
  });

  final String title;
  final Widget child;
  final Color? dotColor;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                  left: contentPadding.left < 12 ? 12 - contentPadding.left : 0,
                  right:
                      contentPadding.right < 12 ? 12 - contentPadding.right : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dotColor ?? scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      // Flexible, not fixed: a large system text scale wraps the
                      // trailing value instead of overflowing the header row.
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        Flexible(child: trailing!),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
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
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.05,
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

    return _SectionCard(
      title: 'Regularity',
      dotColor: Theme.of(context).extension<PhaseColors>()?.follicular,
      trailing: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 8,
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: i == index ? scheme.primary : scheme.surface,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
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

/// The design system's "info card": a short label line above one large value
/// line. Left-aligned so a column of them reads as a table of figures.
class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      // Both lines are Flexible so a large system text scale shrinks the tile's
      // content instead of overflowing a fixed-ratio grid cell.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  )),
            ),
          ),
        ],
      ),
    );
  }
}

/// Softer chart grid lines than fl_chart's default grey, so a chart sitting on
/// a tinted card does not read as a spreadsheet.
FlGridData _grid(ColorScheme scheme, {double? interval}) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => FlLine(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        strokeWidth: 1,
      ),
    );

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
    final average =
        series.reduce((a, b) => a + b) / series.length;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: _grid(scheme),
        borderData: FlBorderData(show: false),
        // A dashed average line, labelled — the same figure the "Avg cycle"
        // tile shows, so the trend reads against something.
        extraLinesData: ExtraLinesData(
          extraLinesOnTop: false,
          horizontalLines: [
            HorizontalLine(
              y: average,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
              strokeWidth: 1,
              dashArray: const [5, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.only(right: 4, bottom: 2),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
                labelResolver: (_) =>
                    'avg ${average.toStringAsFixed(1)} days',
              ),
            ),
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).extension<PhaseColors>()?.menstrual ??
        scheme.primary;
    final pts = analysis.series;
    final groups = [
      for (var i = 0; i < pts.length; i++)
        BarChartGroupData(x: i, barRods: [
          BarChartRodData(
            toY: pts[i].avgIntensity,
            width: 14,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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
        gridData: _grid(scheme, interval: 1),
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

/// One "label — proportional bar — figure" row, the shared shape of the
/// symptom-frequency and medication lists.
class _MeterRow extends StatelessWidget {
  const _MeterRow({
    required this.label,
    required this.fraction,
    required this.trailing,
    required this.color,
  });

  final String label;
  final double fraction;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: scheme.surface,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            child: Text(
              trailing,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Per-medication days-logged for the most recent complete cycle, as bars scaled
/// to the cycle length. A count, never a percentage (dosing frequency isn't
/// stored, so no adherence target is implied).
class _MedicationAdherenceList extends StatelessWidget {
  const _MedicationAdherenceList({required this.adherence});
  final MedicationAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        Theme.of(context).extension<PhaseColors>()?.predicted ?? scheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in adherence.entries)
          _MeterRow(
            label: e.name,
            fraction: e.cycleLength == 0 ? 0 : e.daysLogged / e.cycleLength,
            trailing: '${e.daysLogged} ${e.daysLogged == 1 ? 'day' : 'days'}',
            color: color,
          ),
      ],
    );
  }
}

/// A ranked list of the most-logged symptoms as proportional bars, plus an
/// optional pain-severity summary. Uses plain bars (not a chart lib) so it reads
/// as a compact "top symptoms" leaderboard. Descriptive, never diagnostic.
class _SymptomFrequencyList extends StatelessWidget {
  const _SymptomFrequencyList({required this.analysis});
  final SymptomAnalysis analysis;

  static const _maxRows = 8;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Theme.of(context).extension<PhaseColors>()?.follicular ??
        scheme.primary;
    final rows = analysis.ranked.take(_maxRows).toList();
    final maxCount = rows.first.dayCount; // ranked desc → first is the largest

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in rows)
          _MeterRow(
            label: s.label,
            fraction: s.dayCount / maxCount,
            trailing: '${s.dayCount} ${s.dayCount == 1 ? 'day' : 'days'}',
            color: color,
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
    final scheme = Theme.of(context).colorScheme;
    final ordered = cycles.reversed.toList(); // newest first
    return Column(
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
                color: scheme.outlineVariant.withValues(alpha: 0.6)),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            title: Text(
              '${df.format(ordered[i].start)} – ${df.format(ordered[i].end)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              ordered[i].lengthDays != null
                  ? '${ordered[i].lengthDays}-day cycle · '
                      '${ordered[i].periodLengthDays}-day period'
                  : 'Current cycle · ${ordered[i].periodLengthDays}-day period',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            trailing:
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CycleOverviewScreen(
                  overview: CycleOverviewService.summarize(ordered[i], logs,
                      medNames: medNames),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One "Worth noting" / "Patterns worth discussing" entry, as an icon + title +
/// message row inside its section card. Deliberately NOT a coloured alert box:
/// nothing on this screen is an emergency, and nothing may be styled as one.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(message,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
              ],
            ),
          ),
        ],
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
    // Periwinkle — the ovulatory token, the same colour the calendar uses for
    // this part of the cycle.
    final line = Theme.of(context).extension<PhaseColors>()?.ovulatory ??
        scheme.tertiary;
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
        gridData: _grid(scheme),
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
            color: line,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 2.5,
                color: line,
                strokeWidth: 0,
              ),
            ),
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
    final line = Theme.of(context).extension<PhaseColors>()?.predicted ??
        scheme.primary;
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
        gridData: _grid(scheme),
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
            color: line,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                radius: 2.5,
                color: line,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One "Your patterns" narrative — a calm, plain-language observation about the
/// user's own data. Never a diagnosis, never a number.
class _NarrativeRow extends StatelessWidget {
  const _NarrativeRow({required this.narrative});
  final CycleNarrative narrative;

  static IconData _iconFor(String key) => switch (key) {
        'cycle_trend' => Icons.show_chart,
        'regularity' => Icons.check_circle_outline,
        'period_trend' => Icons.water_drop_outlined,
        'symptom_phase' => Icons.psychology_outlined,
        'phase' => Icons.schedule_outlined,
        _ => Icons.insights_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(narrative.key),
              size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(narrative.text,
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
