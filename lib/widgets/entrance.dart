import 'package:flutter/material.dart';

/// A staggered entrance for a list or a column of cards: each item fades up
/// into place slightly after the one above it.
///
/// **One controller for the whole group**, per the [FlowDropStagger] idiom —
/// each item reads its own [Interval] of the shared timeline rather than owning
/// a controller of its own. A controller per row would mean one `Ticker` per
/// row, which on a long list is a real cost on the low-end target.
///
/// Items are wrapped with [EntranceItem], which is a no-op when there is no
/// [EntranceGroup] above it. That matters for testability: a widget test can
/// pump a row on its own without dragging the animation in.
class EntranceGroup extends StatefulWidget {
  const EntranceGroup({super.key, required this.child});

  final Widget child;

  /// The whole group, first item to last.
  static const duration = Duration(milliseconds: 420);

  /// How much later each item starts than the one above it.
  static const step = 0.09;

  /// How much of the timeline a single item's own fade occupies.
  ///
  /// With [maxStaggered] of 6 the last staggered item runs 0.45 -> 1.00, so it
  /// lands exactly on the end rather than being cut off — and, just as
  /// importantly, `Interval` asserts its end is <= 1.0, so these three numbers
  /// are not independently adjustable.
  static const window = 0.55;

  /// Past this many items the stagger stops and later rows simply appear.
  ///
  /// A list of forty diary entries must not take four seconds to arrive, and
  /// rows below the fold are built lazily anyway — by the time the user has
  /// scrolled to row 20 this controller finished long ago, so row 20 renders at
  /// rest whatever interval it was given.
  static const maxStaggered = 6;

  /// Deliberately small. This is a settling-into-place, not an arrival from
  /// off-screen: a large offset turns a list into a slideshow.
  static const rise = Offset(0, 0.06);

  static const curve = Curves.easeOutCubic;

  @override
  State<EntranceGroup> createState() => _EntranceGroupState();
}

class _EntranceGroupState extends State<EntranceGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: EntranceGroup.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Entrance only, and never replayed — the house contract. A list that
    // re-staggered every time its data changed would re-animate on every save.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _EntranceScope(controller: _controller, child: widget.child);
}

class _EntranceScope extends InheritedWidget {
  const _EntranceScope({required this.controller, required super.child});

  final AnimationController controller;

  static AnimationController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EntranceScope>()?.controller;

  @override
  bool updateShouldNotify(_EntranceScope old) =>
      !identical(old.controller, controller);
}

/// One row of an [EntranceGroup]. Renders [child] untouched when there is no
/// group above it.
class EntranceItem extends StatelessWidget {
  const EntranceItem({super.key, required this.index, required this.child});

  /// Position in the list. Values at or past [EntranceGroup.maxStaggered] all
  /// share the last interval.
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = _EntranceScope.maybeOf(context);
    if (controller == null) return child;

    final i = index.clamp(0, EntranceGroup.maxStaggered - 1);
    final start = i * EntranceGroup.step;

    // `drive` rather than a CurvedAnimation: the result needs no disposal, so
    // this stays a StatelessWidget and an item whose index changes (a list that
    // reorders) simply re-derives its interval on the next build.
    final progress = controller.drive(
      CurveTween(
        curve: Interval(
          start,
          start + EntranceGroup.window,
          curve: EntranceGroup.curve,
        ),
      ),
    );

    return FadeTransition(
      opacity: progress,
      child: SlideTransition(
        position: Tween(
          begin: EntranceGroup.rise,
          end: Offset.zero,
        ).animate(progress),
        child: child,
      ),
    );
  }
}
