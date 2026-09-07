import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../common/insights_text.dart';
import '../models/enums.dart';
import '../models/month_ring.dart';
import '../theme/app_theme.dart';

/// A circular "month at a glance": one arc segment per day of the current month,
/// coloured by the day's role, with today's date + cycle day + phase in the
/// centre and today's segment marked. Purely a view over [MonthRingData]; all
/// colouring decisions (including the confidence-gated fertility) were already
/// made by MonthRingBuilder, so this widget never re-derives fertility and can
/// never imply a "safe" day. Colours resolve from the theme so light/dark adapt.
class MonthRing extends StatelessWidget {
  const MonthRing({super.key, required this.data});

  final MonthRingData data;

  @override
  Widget build(BuildContext context) {
    final phases = Theme.of(context).extension<PhaseColors>()!;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 240,
          height: 240,
          child: CustomPaint(
            painter: MonthRingPainter(
              data: data,
              normal: scheme.onSurface.withValues(alpha: 0.10),
              period: phases.menstrual,
              predicted: phases.menstrual.withValues(alpha: 0.32),
              fertile: phases.fertile.withValues(alpha: 0.70),
              ovulation: phases.fertile,
              pms: phases.luteal.withValues(alpha: 0.32),
              todayDot: scheme.primary,
              // What sits BEHIND the ring: the card, not the scaffold. It is
              // painted between today's dots, so it has to be the card's own
              // fill or the gaps read as a white notch on a tinted card.
              halo: scheme.surfaceContainerLow,
            ),
            child: Center(child: _RingCentre(data: data, phases: phases)),
          ),
        ),
        const SizedBox(height: 16),
        _MonthRingLegend(data: data, phases: phases),
      ],
    );
  }
}

/// The readout inside the ring: the calendar date, the CYCLE day, the phase.
///
/// Two different numbers live here and they are easy to conflate — the ring is
/// indexed by DAY OF MONTH, while "Day 19" is the cycle day. So the date is a
/// quiet label line and the cycle day is the value line, rather than two
/// competing figures. With no cycle day yet (no prediction) the date becomes the
/// value, because there is nothing else true to show.
class _RingCentre extends StatelessWidget {
  const _RingCentre({required this.data, required this.phases});

  final MonthRingData data;
  final PhaseColors phases;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final month = DateTime(data.year, data.month);

    if (data.cycleDay == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${data.todayDay ?? ''}',
              style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
          Text(DateFormat.yMMMM().format(month),
              style:
                  text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      );
    }

    final today = data.todayDay == null
        ? null
        : DateTime(data.year, data.month, data.todayDay!);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (today != null)
          Text(
            DateFormat.MMMMd().format(today),
            style: text.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        const SizedBox(height: 2),
        Text('Day ${data.cycleDay}',
            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        if (data.phase != CyclePhase.unknown) ...[
          const SizedBox(height: 2),
          Text(
            data.phase.label,
            style: text.labelLarge?.copyWith(
              color: phases.forPhase(data.phase),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// The colour key beneath the ring. Period is always shown; Predicted only when
/// there's a predicted run this month; Fertile/Ovulation only when fertility was
/// actually coloured (i.e. confidence was high enough) — so the legend never
/// implies fertility data exists when it's been suppressed.
class _MonthRingLegend extends StatelessWidget {
  const _MonthRingLegend({required this.data, required this.phases});

  final MonthRingData data;
  final PhaseColors phases;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        _swatch(context, phases.menstrual, 'Period'),
        if (data.hasPredictedPeriod)
          _swatch(context, phases.menstrual.withValues(alpha: 0.32),
              'Predicted'),
        if (data.hasFertile)
          _swatch(context, phases.fertile.withValues(alpha: 0.70), 'Fertile'),
        if (data.hasOvulation)
          _swatch(context, phases.fertile, 'Ovulation (est.)'),
        if (data.hasPms)
          _swatch(context, phases.luteal.withValues(alpha: 0.32), 'PMS (est.)'),
      ],
    );
  }

  Widget _swatch(BuildContext context, Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
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

/// Draws the day-segment ring and the "today" marker. Holds [data] so tests can
/// read the resolved roles back off the element tree without pixel goldens.
class MonthRingPainter extends CustomPainter {
  MonthRingPainter({
    required this.data,
    required this.normal,
    required this.period,
    required this.predicted,
    required this.fertile,
    required this.ovulation,
    required this.pms,
    required this.todayDot,
    required this.halo,
  });

  final MonthRingData data;
  final Color normal;
  final Color period;
  final Color predicted;
  final Color fertile;
  final Color ovulation;
  final Color pms;
  final Color todayDot;
  final Color halo;

  @override
  void paint(Canvas canvas, Size size) {
    final n = data.days.length;
    if (n == 0) return;
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final thickness = outer * 0.16;
    final radius = outer - thickness / 2 - 2;
    final step = 2 * math.pi / n;
    const gap = 0.02; // radians of gap between adjacent day segments
    final sweep = step - gap;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    final rect = Rect.fromCircle(center: center, radius: radius);

    for (var i = 0; i < n; i++) {
      final start = -math.pi / 2 + i * step + gap / 2;
      paint.color = _colorFor(data.days[i].role);
      canvas.drawArc(rect, start, sweep, false, paint);
    }

    // "You are here": today's own segment is drawn DOTTED — three short arcs in
    // the accent colour, clearing the day's span first so the gaps show the
    // card behind the ring rather than whatever role colour it happens to sit
    // on. Dotting the day (rather than beading over it) is the design-system
    // spec for this component, and it keeps the marker legible on every role
    // colour without depending on the contrast between two of them.
    //
    // The dots are sized so three of them plus two gaps fill exactly one day.
    // Caps stay BUTT: a round cap adds half the stroke width to each end of
    // every dot, which at this thickness is far wider than a dot and fuses the
    // three into one blob wider than a whole day — the defect the mock's SVG
    // ring hit and recorded in docs/design/stitch/README.md.
    final todayIndex = data.days.indexWhere((d) => d.isToday);
    if (todayIndex >= 0) {
      final dayStart = -math.pi / 2 + todayIndex * step + gap / 2;
      paint.color = halo;
      canvas.drawArc(rect, dayStart, sweep, false, paint);

      const dotFraction = 0.26; // 3 dots + 2 gaps == 1 day
      const gapFraction = 0.11;
      paint.color = todayDot;
      for (var k = 0; k < 3; k++) {
        final start = dayStart + sweep * k * (dotFraction + gapFraction);
        canvas.drawArc(rect, start, sweep * dotFraction, false, paint);
      }
    }
  }

  Color _colorFor(RingDayRole role) => switch (role) {
        RingDayRole.normal => normal,
        RingDayRole.period => period,
        RingDayRole.predictedPeriod => predicted,
        RingDayRole.fertile => fertile,
        RingDayRole.ovulation => ovulation,
        RingDayRole.pms => pms,
      };

  @override
  bool shouldRepaint(MonthRingPainter old) =>
      !identical(old.data, data) ||
      old.normal != normal ||
      old.period != period ||
      old.predicted != predicted ||
      old.fertile != fertile ||
      old.ovulation != ovulation ||
      old.pms != pms ||
      old.todayDot != todayDot ||
      old.halo != halo;
}
