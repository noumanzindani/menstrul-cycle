import 'dart:math' as math;

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
import '../forecast/forecast_screen.dart';
import '../media/media_route.dart';
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
          // Forecast left the bottom nav when the Assistant took its tab; the
          // calendar is the other surface showing predicted periods, so the
          // next twelve are reachable from here as well as from Home.
          IconButton(
            key: const Key('calendar-forecast-action'),
            tooltip: 'Forecast',
            icon: const Icon(Icons.date_range_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ForecastScreen()),
            ),
          ),
          // Same reasoning as the Diary action above. Hides itself when there
          // is no Firebase — media is cloud-only.
          const MediaAppBarAction(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // See `home_screen.dart`: both FABs live in the same route subtree via
        // `AppShell`'s `IndexedStack`, so neither may use the default tag.
        heroTag: 'calendar.logToday',
        onPressed: () => _selectDay(today),
        icon: const Icon(Icons.add),
        label: const Text('Log today'),
      ),
      // The disclaimer and the ad live in the Scaffold's bottom slot rather
      // than at the foot of the body: that is what makes the Scaffold lift the
      // extended FAB clear of them. Floating over the body, the FAB sat on top
      // of the right-hand half of the guardrail banner and of the ad.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Persistent non-contraception notice — always visible on the
          // calendar because it overlays a fertile-window / ovulation estimate
          // (council guardrail; matches Home and Forecast). Kept OUT of the
          // scrolling list so it can't be lazy-culled below the
          // viewport-filling month grid.
          const Padding(
            padding: EdgeInsets.fromLTRB(_kGridGutter, 0, _kGridGutter, 8),
            child: DisclaimerBanner(compact: true),
          ),
          // Ads must never co-render with the entry sheet (council rule).
          if (_selectedDay == null)
            const SafeArea(top: false, child: AdBanner()),
        ],
      ),
      body: Consumer<LogProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            // Room at the foot of the scroll for the extended FAB, which
            // otherwise floats over the legend's last row.
            padding: const EdgeInsets.only(top: 8, bottom: 72),
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
      // 8 rather than 16 so the icon buttons' own 48dp touch targets end up
      // optically flush with the 16dp grid gutter.
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          // Flexible: a long localized month name at a large text scale must
          // shrink the label, never push a chevron off the row.
          Expanded(
            child: Text(
              DateFormat.yMMMM().format(month),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
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
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
        );
    return Padding(
      // Same gutter as _MonthGrid so the initials sit over their columns.
      padding: const EdgeInsets.fromLTRB(_kGridGutter, 0, _kGridGutter, 8),
      child: Row(
        children: [
          for (final l in labels)
            Expanded(child: Center(child: Text(l, style: style))),
        ],
      ),
    );
  }
}

/// Horizontal inset shared by the weekday initials, the day grid and the
/// legend, so all three line up on the same columns.
const double _kGridGutter = 16;

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
      // No cross-axis spacing: each cell insets itself instead, so a column is
      // exactly 1/7 of the gutter-inset width and the weekday initials above
      // land on the same centres.
      padding: const EdgeInsets.symmetric(horizontal: _kGridGutter),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
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
    // A dashed lavender ring is the app-wide "this is an estimate" mark: the
    // design system reserves `predicted` for every estimated state, so a
    // forecast period must not borrow the rose a LOGGED period owns.
    bool dashedRing = false;
    if (bleeding) {
      fill = flow.color(phases);
    } else if (predictedPeriod) {
      borderColor = phases.predicted;
      dashedRing = true;
    } else if (fertile) {
      // A single flat wash for the whole window; the estimated ovulation day is
      // distinguished by its own marker dot below, not by a deeper fill — the
      // band must never read as a scale.
      fill = phases.fertile;
    } else if (pms) {
      fill = phases.luteal.withValues(alpha: 0.22);
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
            // Contrast against a saturated fill, not a theme surface — the same
            // in light and dark.
            ? Colors.white
            : scheme.onSurface;

    Widget cell = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: scheme.primary, width: 2)
            : (borderColor != null && !dashedRing)
                ? Border.all(color: borderColor, width: 1.4)
                : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            '${date.day}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                ),
          ),
          if (ovulation || hasOtherData)
            Positioned(
              bottom: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Estimated ovulation: a marker, never a number or a score.
                  if (ovulation) _marker(phases.ovulatory, 6),
                  if (ovulation && hasOtherData) const SizedBox(width: 3),
                  if (hasOtherData)
                    _marker(
                      onDark
                          ? Colors.white.withValues(alpha: 0.85)
                          : scheme.onSurface.withValues(alpha: 0.45),
                      4,
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    if (dashedRing && !isToday) {
      cell = CustomPaint(
        foregroundPainter: _DashedCirclePainter(color: borderColor!),
        child: cell,
      );
    }

    return GestureDetector(
      onTap: onTap,
      // Transparent cells still need to swallow the tap.
      behavior: HitTestBehavior.opaque,
      child: Padding(padding: const EdgeInsets.all(3), child: cell),
    );
  }

  static Widget _marker(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Draws the dashed "estimate" ring used by predicted-period days and by the
/// legend swatch that explains them.
class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color, this.strokeWidth = 1.4});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );
    // ~3dp dash + ~3dp gap, rounded to a whole number of repeats so the
    // pattern closes cleanly instead of leaving a seam.
    final dashes = math.max(8, (math.pi * radius / 3).round());
    final step = 2 * math.pi / dashes;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showOvulation});
  final bool showOvulation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phases = Theme.of(context).extension<PhaseColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(_kGridGutter, 20, _kGridGutter, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 10,
        children: [
          _LegendItem(color: phases.menstrual, label: 'Period'),
          // Dashed lavender: the mark every estimated day on the grid carries.
          _LegendItem(
            color: Colors.transparent,
            dashedBorder: phases.predicted,
            label: 'Predicted',
          ),
          _LegendItem(color: phases.fertile, label: 'Fertile'),
          if (showOvulation)
            _LegendItem(
              color: phases.ovulatory,
              size: 6,
              label: 'Ovulation (est.)',
            ),
          _LegendItem(
            color: phases.luteal.withValues(alpha: 0.22),
            label: 'PMS (est.)',
          ),
          _LegendItem(
            color: scheme.onSurface.withValues(alpha: 0.45),
            size: 4,
            label: 'Logged',
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    this.dashedBorder,
    this.size = 12,
  });

  final Color color;
  final Color? dashedBorder;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    Widget swatch = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (dashedBorder != null) {
      swatch = CustomPaint(
        foregroundPainter:
            _DashedCirclePainter(color: dashedBorder!, strokeWidth: 1.2),
        child: swatch,
      );
    }
    // Keep every swatch on the same 12dp optical column, whatever its size.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 12, height: 12, child: Center(child: swatch)),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
