import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../common/insights_text.dart';
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
    final text = Theme.of(context).textTheme;
    final monthLabel =
        DateFormat.yMMMM().format(DateTime(data.year, data.month));

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
              halo: scheme.surface,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${data.todayDay ?? ''}',
                      style: text.displaySmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(monthLabel,
                      style: text.labelMedium
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  if (data.cycleDay != null) ...[
                    const SizedBox(height: 4),
                    Text('Day ${data.cycleDay} · ${data.phase.label}',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _MonthRingLegend(data: data, phases: phases),
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
      spacing: 14,
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
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
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

    // "You are here": a filled dot on today's segment, haloed so it reads on any
    // segment colour.
    final todayIndex = data.days.indexWhere((d) => d.isToday);
    if (todayIndex >= 0) {
      final mid = -math.pi / 2 + (todayIndex + 0.5) * step;
      final dot = center + Offset(math.cos(mid), math.sin(mid)) * radius;
      final r = thickness * 0.5;
      canvas.drawCircle(dot, r + 2, Paint()..color = halo);
      canvas.drawCircle(dot, r, Paint()..color = todayDot);
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
