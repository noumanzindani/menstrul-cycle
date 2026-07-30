import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../common/catalog.dart';
import '../../common/date_utils.dart';
import '../../db/database.dart';
import '../../models/prediction.dart';
import '../../providers/log_provider.dart';
import '../../services/cycle_check_in.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ad_banner.dart';
import '../../widgets/day_entry_sheet.dart';
import '../diary/diary_screen.dart';
import '../../widgets/disclaimer_banner.dart';

/// Month calendar. Logged bleeding days are filled (deeper = heavier); the
/// upcoming fertile window and predicted next period are overlaid on future,
/// unlogged days; days with other logs get a dot.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month; // first day of the shown month
  DateTime? _selectedDay; // day whose entry sheet is open (gates the ad)

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) =>
      setState(() => _month = DateTime(_month.year, _month.month + delta));

  /// Opens the day's log form in a bottom sheet — the "combined calendar +
  /// entry" surface. A sheet (not an inline panel under the grid) is used
  /// because an inline panel below the viewport-filling month grid never
  /// reliably lays out. [_selectedDay] tracks the open sheet so the calendar
  /// ad is hidden while logging (council rule: no ad beside entry).
  Future<void> _selectDay(DateTime date) async {
    setState(() => _selectedDay = date);
    // Decide the contextual back-fill prompt for this date here, where the
    // PredictionResult is in scope (the sheet route doesn't re-provide it).
    final checkIn = CycleCheckInService.evaluate(
      logs: context.read<LogProvider>().logs,
      prediction: context.read<PredictionResult>(),
      today: date,
    );
    await showDayEntrySheet(context, date: date, checkIn: checkIn);
    if (mounted) setState(() => _selectedDay = null);
  }

  @override
  Widget build(BuildContext context) {
    final phases = Theme.of(context).extension<PhaseColors>()!;
    final today = dateOnly(DateTime.now());
    final periods = context.watch<List<PredictedPeriod>>();
    final overlay = _PredictionOverlay(periods);
    // Only surface a confident single-day ovulation estimate; below medium
    // confidence we show the fertile window only, never a precise day. Uses
    // fertilityConfidence so a corroborating OPK unlocks the marker in step with
    // the Home band (and perimenopause's cap still suppresses it).
    final confidence = context.watch<PredictionResult>().fertilityConfidence;
    final showOvulation =
        confidence.index >= PredictionConfidence.medium.index;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          // Diary lives here rather than in the bottom nav, which is already at
          // Material's five-destination ceiling.
          IconButton(
            tooltip: 'Diary',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiaryScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _selectDay(today),
        icon: const Icon(Icons.add),
        label: const Text('Log today'),
      ),
      body: Consumer<LogProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _MonthHeader(
                      month: _month,
                      onPrev: () => _shiftMonth(-1),
                      onNext: () => _shiftMonth(1),
                    ),
                    const _WeekdayRow(),
                    _MonthGrid(
                      month: _month,
                      today: today,
                      phases: phases,
                      overlay: overlay,
                      showOvulation: showOvulation,
                      logFor: provider.logForDate,
                      onTapDay: _selectDay,
                    ),
                    _Legend(showOvulation: showOvulation),
                  ],
                ),
              ),
              // Persistent non-contraception notice — always visible on the
              // calendar because it overlays a fertile-window / ovulation
              // estimate (council guardrail; matches Home and Forecast). Kept
              // OUT of the scrolling ListView so it can't be lazy-culled below
              // the viewport-filling month grid.
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: DisclaimerBanner(compact: true),
              ),
              // Ads must never co-render with the entry sheet (council rule).
              if (_selectedDay == null)
                const SafeArea(top: false, child: AdBanner()),
            ],
          );
        },
      ),
    );
  }
}

/// Shades predicted period and fertile days across ALL future months, using
/// the multi-month forecast.
class _PredictionOverlay {
  const _PredictionOverlay(this.periods);
  final List<PredictedPeriod> periods;

  bool _inRange(DateTime d, DateTime a, DateTime b) =>
      !d.isBefore(a) && !d.isAfter(b);

  bool isPredictedPeriod(DateTime d) =>
      periods.any((p) => _inRange(d, p.start, p.end));

  bool isFertile(DateTime d) =>
      periods.any((p) => _inRange(d, p.fertileStart, p.fertileEnd));

  bool isOvulation(DateTime d) =>
      periods.any((p) => isSameDay(d, p.ovulation));

  bool isPms(DateTime d) =>
      periods.any((p) => _inRange(d, p.pmsStart, p.pmsEnd));
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Text(
            DateFormat.yMMMM().format(month),
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final l in labels)
            Expanded(child: Center(child: Text(l, style: style))),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.phases,
    required this.overlay,
    required this.showOvulation,
    required this.logFor,
    required this.onTapDay,
  });

  final DateTime month;
  final DateTime today;
  final PhaseColors phases;
  final _PredictionOverlay overlay;
  final bool showOvulation;
  final DailyLog? Function(DateTime) logFor;
  final void Function(DateTime) onTapDay;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final leadingBlanks = month.weekday % 7; // Sunday-first columns
    final cellCount = leadingBlanks + daysInMonth;

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.82,
      ),
      itemCount: cellCount,
      itemBuilder: (context, index) {
        if (index < leadingBlanks) return const SizedBox.shrink();
        final day = index - leadingBlanks + 1;
        final date = DateTime(month.year, month.month, day);
        final isFuture = date.isAfter(today);
        return _DayCell(
          date: date,
          log: logFor(date),
          isToday: isSameDay(date, today),
          isFuture: isFuture,
          predictedPeriod: overlay.isPredictedPeriod(date),
          fertile: overlay.isFertile(date),
          ovulation: showOvulation && overlay.isOvulation(date),
          pms: overlay.isPms(date),
          phases: phases,
          onTap: isFuture ? null : () => onTapDay(date),
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.log,
    required this.isToday,
    required this.isFuture,
    required this.predictedPeriod,
    required this.fertile,
    required this.ovulation,
    required this.pms,
    required this.phases,
    required this.onTap,
  });

  final DateTime date;
  final DailyLog? log;
  final bool isToday;
  final bool isFuture;
  final bool predictedPeriod;
  final bool fertile;
  final bool ovulation;
  final bool pms;
  final PhaseColors phases;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final flow = log?.flow;
    final bleeding = flow != null && flow.isBleeding;

    Color fill = Colors.transparent;
    Color? borderColor;
    if (bleeding) {
      fill = flow.color(phases);
    } else if (predictedPeriod) {
      fill = phases.menstrual.withValues(alpha: 0.16);
      borderColor = phases.menstrual.withValues(alpha: 0.6);
    } else if (fertile) {
      // The estimated ovulation day sits inside the fertile window but gets a
      // deeper fill and a solid ring so it reads as distinct (still an estimate).
      fill = phases.fertile.withValues(alpha: ovulation ? 0.8 : 0.55);
      if (ovulation) borderColor = phases.fertile;
    } else if (pms) {
      fill = phases.luteal.withValues(alpha: 0.28);
      borderColor = phases.luteal.withValues(alpha: 0.55);
    }

    final hasOtherData = log != null &&
        !bleeding &&
        (decodeSymptoms(log!.symptoms).isNotEmpty ||
            log!.mood != null ||
            (log!.notes?.isNotEmpty ?? false) ||
            flow != null);

    final onDark = bleeding && flow.index >= 3; // medium+ → light text
    final textColor = isFuture && !predictedPeriod && !fertile && !pms
        ? scheme.onSurface.withValues(alpha: 0.35)
        : onDark
            ? Colors.white
            : scheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: isToday
              ? Border.all(color: scheme.primary, width: 2)
              : borderColor != null
                  ? Border.all(color: borderColor, width: 1.4)
                  : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text('${date.day}', style: TextStyle(color: textColor)),
            if (hasOtherData)
              Positioned(
                bottom: 6,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showOvulation});
  final bool showOvulation;

  @override
  Widget build(BuildContext context) {
    final phases = Theme.of(context).extension<PhaseColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 4,
        children: [
          _LegendItem(color: phases.menstrual, label: 'Period'),
          _LegendItem(
            color: phases.menstrual.withValues(alpha: 0.16),
            border: phases.menstrual.withValues(alpha: 0.6),
            label: 'Predicted',
          ),
          _LegendItem(
            color: phases.fertile.withValues(alpha: 0.55),
            label: 'Fertile',
          ),
          if (showOvulation)
            _LegendItem(
              color: phases.fertile.withValues(alpha: 0.8),
              border: phases.fertile,
              label: 'Ovulation (est.)',
            ),
          _LegendItem(
            color: phases.luteal.withValues(alpha: 0.28),
            border: phases.luteal.withValues(alpha: 0.55),
            label: 'PMS (est.)',
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.border});
  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border != null ? Border.all(color: border!) : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
