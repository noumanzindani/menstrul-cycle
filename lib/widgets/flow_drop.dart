import 'package:flutter/material.dart';

/// The flow droplet, drawn rather than loaded.
///
/// Replaces `assets/track/flow_[1-5]_*.svg`, which were one drawing repeated
/// five times with a single number changed: the y of a rect clipped to the
/// droplet. That number is now [FlowDropPainter.fill], so the ramp lives in
/// `option_art.dart`'s `kFlowFill` as readable fractions instead of rect offsets
/// buried in XML -- and, being a number, it can be animated between.
///
/// The fill fraction is the ONLY encoding of intensity here. `day_entry_form`
/// deliberately paints every drop the same constant red rather than a graduated
/// ramp; see the ruling in its flow chip row.
class FlowDropPainter extends CustomPainter {
  FlowDropPainter({required this.fill, required this.color})
      : super(repaint: fill);

  /// 0 -> 1 as the droplet fills from its bottom to its tip.
  final Animation<double> fill;

  final Color color;

  /// Bottom of the droplet: the bulb's centre (15) plus its radius (7).
  static const _bottom = 22.0;

  /// The tip.
  static const _tip = 2.5;

  static const _height = _bottom - _tip;

  /// The outline, in the 24-unit viewBox the SVGs used:
  ///   M12 2.5 C12 2.5 5 10.5 5 15 a7 7 0 0 0 14 0 c0-4.5-7-12.5-7-12.5 z
  ///
  /// `clockwise: false` is the SVG's sweep-flag 0, and it is the one part of
  /// this translation that fails silently -- an arc bulging up instead of down
  /// still closes into a plausible blob, just not a droplet. `flow_drop_test`
  /// pins the bounds for exactly that reason.
  static final Path droplet = Path()
    ..moveTo(12, _tip)
    ..cubicTo(12, _tip, 5, 10.5, 5, 15)
    ..arcToPoint(
      const Offset(19, 15),
      radius: const Radius.circular(7),
      clockwise: false,
    )
    ..cubicTo(19, 10.5, 12, _tip, 12, _tip)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.shortestSide / 24.0);

    // The outline is drawn at every level, including full. The old
    // `flow_5_flooding.svg` was a solid droplet with no stroke, so flooding now
    // carries a marginally heavier silhouette -- consistent with its four
    // siblings, which is the point.
    canvas.drawPath(
      droplet,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );

    final f = fill.value.clamp(0.0, 1.0);
    if (f > 0) {
      canvas.save();
      canvas.clipPath(droplet);
      canvas.drawRect(
        Rect.fromLTRB(0, _bottom - f * _height, 24, _bottom),
        Paint()..color = color,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlowDropPainter old) =>
      !identical(old.fill, fill) || old.color != color;
}

/// One droplet, sized and tinted like [TrackArt] so it sits in a chip label
/// beside marks that are still SVGs.
class FlowDrop extends StatelessWidget {
  const FlowDrop({
    super.key,
    required this.fill,
    this.color,
    this.size = 16,
  });

  final Animation<double> fill;

  /// Null inherits the surrounding label colour, exactly as `TrackArt` does.
  final Color? color;

  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = color ??
        DefaultTextStyle.of(context).style.color ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return CustomPaint(
      size: Size.square(size),
      painter: FlowDropPainter(fill: fill, color: ink),
    );
  }
}

/// Drives [count] droplets filling in sequence from one controller.
///
/// The stagger teaches the ramp: the drops fill left to right, so the row reads
/// as an ordered scale at a glance instead of five unrelated marks. It is an
/// ENTRANCE -- it runs once and never replays, because the day-entry form
/// rebuilds on every field change and a re-run would make the row twitch while
/// the user works down the page.
class FlowDropStagger extends StatefulWidget {
  const FlowDropStagger({
    super.key,
    required this.levels,
    required this.builder,
  });

  /// Each drop's resting fill, in row order -- normally `kFlowFill.values`.
  ///
  /// The stagger scales to these itself rather than handing out a bare 0 -> 1
  /// and letting the caller multiply, because the caller is a `build` method:
  /// a tween created there would be a fresh [Animation] on every rebuild, and
  /// the form rebuilds on every field change, so each painter would detach and
  /// re-attach its listener for nothing.
  final List<double> levels;

  /// Builds the whole row, so layout stays with the caller.
  final Widget Function(BuildContext, List<Animation<double>>) builder;

  static const duration = Duration(milliseconds: 600);

  /// Each drop fills over [window] of the timeline, starting [step] later than
  /// the one before it. With five drops the last runs 0.40 -> 1.00, so it lands
  /// exactly on the end rather than being cut off.
  static const step = 0.10;
  static const window = 0.60;

  @override
  FlowDropStaggerState createState() => FlowDropStaggerState();
}

class FlowDropStaggerState extends State<FlowDropStagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<CurvedAnimation> _progress;
  late final List<Animation<double>> _drops;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: FlowDropStagger.duration,
    );
    _progress = [
      for (var i = 0; i < widget.levels.length; i++)
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            i * FlowDropStagger.step,
            i * FlowDropStagger.step + FlowDropStagger.window,
            curve: Curves.easeOutCubic,
          ),
        ),
    ];
    _drops = [
      for (var i = 0; i < widget.levels.length; i++)
        Tween<double>(begin: 0, end: widget.levels[i]).animate(_progress[i]),
    ];
  }

  /// The fill driving drop [i] -- 0 up to its own level, not to 1.
  Animation<double> animationAt(int i) => _drops[i];

  /// Drop [i]'s raw 0 -> 1 progress through its interval. The fills settle at
  /// DIFFERENT values, so ordering can only be compared on this.
  Animation<double> progressAt(int i) => _progress[i];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    for (final p in _progress) {
      p.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _drops);
}
