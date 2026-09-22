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
class MonthRing extends StatefulWidget {
  const MonthRing({super.key, required this.data});

  final MonthRingData data;

  /// The whole entrance: the ring sweeping in, then the marker fading on.
  static const revealDuration = Duration(milliseconds: 600);

  /// Where the marker fade begins, as a fraction of [revealDuration]. The ring
  /// finishes sweeping FIRST and "you are here" lands afterwards, so the two
  /// phases are intervals of one controller rather than one shared curve --
  /// easeOutCubic reaches 0.7 at barely a third of the wall clock, which would
  /// start the dots before the ring was a third drawn.
  static const dotFadeStart = 0.70;

  static const revealCurve = Curves.easeOutCubic;

  /// How long a day's colour takes to travel to its new role after a save.
  ///
  /// Shorter than [revealDuration] on purpose: the entrance is the component
  /// introducing itself, this is an acknowledgement. It answers "did my log
  /// land?" and then gets out of the way.
  static const settleDuration = Duration(milliseconds: 380);

  /// Symmetric, unlike the entrance. A settle has no arrival to emphasise --
  /// it is one state becoming another, and easing only the tail makes the
  /// colour appear to overshoot and correct itself.
  static const settleCurve = Curves.easeInOut;

  @override
  State<MonthRing> createState() => _MonthRingState();
}

class _MonthRingState extends State<MonthRing>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _ringReveal;
  late final CurvedAnimation _dotFade;
  bool _started = false;

  /// The entrance and the settle are SEPARATE controllers, not intervals of
  /// one: the entrance runs once and the settle runs on every save, so they
  /// have no shared timeline to be intervals of.
  late final AnimationController _settle;
  late final CurvedAnimation _settleProgress;

  /// The ring the user is still looking at while [_settle] runs, or null when
  /// nothing is settling. Only ever set to a ring of the same month.
  MonthRingData? _previous;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: MonthRing.revealDuration,
    );
    _ringReveal = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, MonthRing.dotFadeStart,
          curve: MonthRing.revealCurve),
    );
    _dotFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(MonthRing.dotFadeStart, 1.0, curve: Curves.easeIn),
    );
    _settle = AnimationController(
      vsync: this,
      duration: MonthRing.settleDuration,
      // Parked at the END, not the start: with no previous ring there is
      // nothing to travel from, and a settle at 0 would paint the ring as if
      // mid-transition on its very first frame.
      value: 1,
    );
    _settleProgress =
        CurvedAnimation(parent: _settle, curve: MonthRing.settleCurve);
  }

  @override
  void didUpdateWidget(MonthRing old) {
    super.didUpdateWidget(old);
    if (old.data == widget.data) return;

    // Only COLOURS settle, and only between two rings of the same month. Across
    // a rollover each segment changes what it MEANS, so lerping January's day 3
    // into February's day 3 would animate a relationship that does not exist.
    final sameMonth = old.data.year == widget.data.year &&
        old.data.month == widget.data.month &&
        old.data.days.length == widget.data.days.length;

    // A change arriving mid-entrance is absorbed BY the entrance: the sweep is
    // still drawing these segments for the first time, so there is no earlier
    // state the user ever saw to settle from.
    if (!sameMonth || !_controller.isCompleted) {
      _previous = null;
      _settle.value = 1;
      return;
    }

    _previous = old.data;
    if (MediaQuery.disableAnimationsOf(context)) {
      _settle.value = 1;
    } else {
      _settle.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Entrance only. The home screen rebuilds this widget on every log save, so
    // the reveal is started once and deliberately never replayed -- there is no
    // didUpdateWidget hook on purpose.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      // Reduced motion switched on mid-settle lands on the new colours too --
      // the end state, never the old one.
      _settle.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _ringReveal.dispose();
    _dotFade.dispose();
    _settleProgress.dispose();
    _controller.dispose();
    _settle.dispose();
    super.dispose();
  }

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
              data: widget.data,
              previous: _previous,
              settle: _settleProgress,
              ringReveal: _ringReveal,
              dotFade: _dotFade,
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
            child: Center(child: _RingCentre(data: widget.data, phases: phases)),
          ),
        ),
        const SizedBox(height: 16),
        _MonthRingLegend(data: widget.data, phases: phases),
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
    this.previous,
    // Defaults to "nothing is settling": a painter built without a settle --
    // as tests do to assert a static ring -- paints [data]'s colours outright.
    this.settle = kAlwaysCompleteAnimation,
    required this.ringReveal,
    required this.dotFade,
    required this.normal,
    required this.period,
    required this.predicted,
    required this.fertile,
    required this.ovulation,
    required this.pms,
    required this.todayDot,
    required this.halo,
  }) : super(repaint: Listenable.merge([ringReveal, dotFade, settle]));

  final MonthRingData data;

  /// The ring being travelled FROM, or null when nothing is settling. Always
  /// the same month and the same day count as [data] -- the widget refuses to
  /// pair rings that are not comparable, so [paint] may index both freely.
  final MonthRingData? previous;

  /// 0 -> 1 as each day's colour travels from [previous] to [data].
  final Animation<double> settle;

  /// 0 -> 1 as the day arcs sweep in clockwise from 12 o'clock.
  final Animation<double> ringReveal;

  /// 0 -> 1 as today's marker fades on, once the ring is complete.
  final Animation<double> dotFade;
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

    // The reveal draws whole arcs for the days already uncovered plus ONE
    // partial arc for the day being uncovered right now. Stepping a whole day
    // at a time would quantise the motion: 31 segments over 420ms is about one
    // per frame, so the sweep would be pinned to the frame rate instead of the
    // curve.
    final revealed = n * ringReveal.value.clamp(0.0, 1.0);
    final whole = revealed.floor();

    for (var i = 0; i <= whole && i < n; i++) {
      final visible = i < whole ? sweep : sweep * (revealed - whole);
      if (visible <= 0) break;
      final start = -math.pi / 2 + i * step + gap / 2;
      paint.color = _segmentColor(i);
      canvas.drawArc(rect, start, visible, false, paint);
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
    final fade = dotFade.value.clamp(0.0, 1.0);
    final todayIndex = data.days.indexWhere((d) => d.isToday);
    if (fade > 0 && todayIndex >= 0) {
      final dayStart = -math.pi / 2 + todayIndex * step + gap / 2;
      // The clear fades WITH the dots. Held at full opacity from the first
      // frame of the fade it would punch a hard notch into the finished ring
      // and then slowly fill it, which reads as a glitch rather than an accent.
      paint.color = halo.withValues(alpha: halo.a * fade);
      canvas.drawArc(rect, dayStart, sweep, false, paint);

      const dotFraction = 0.26; // 3 dots + 2 gaps == 1 day
      const gapFraction = 0.11;
      paint.color = todayDot.withValues(alpha: todayDot.a * fade);
      for (var k = 0; k < 3; k++) {
        final start = dayStart + sweep * k * (dotFraction + gapFraction);
        canvas.drawArc(rect, start, sweep * dotFraction, false, paint);
      }
    }
  }

  /// Day [i]'s colour, mid-settle if one is running.
  ///
  /// Lerped per SEGMENT rather than by swapping a whole palette: a save changes
  /// the role of one day or a short run of them, and travelling every segment
  /// through an interpolated palette would animate 30 days to say that one
  /// changed.
  Color _segmentColor(int i) {
    final current = _colorFor(data.days[i].role);
    final from = previous;
    if (from == null) return current;
    final t = settle.value.clamp(0.0, 1.0);
    if (t >= 1) return current;
    // Defensive: the widget only ever pairs equal-length rings, but paint must
    // never throw on a frame.
    if (i >= from.days.length) return current;
    return Color.lerp(_colorFor(from.days[i].role), current, t) ?? current;
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
      !identical(old.previous, previous) ||
      !identical(old.settle, settle) ||
      !identical(old.ringReveal, ringReveal) ||
      !identical(old.dotFade, dotFade) ||
      old.normal != normal ||
      old.period != period ||
      old.predicted != predicted ||
      old.fertile != fertile ||
      old.ovulation != ovulation ||
      old.pms != pms ||
      old.todayDot != todayDot ||
      old.halo != halo;
}
