import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/option_art.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/widgets/flow_drop.dart';

void main() {
  const ink = Color(0xFFAA0044);

  FlowDropPainter painterAt(double fill) => FlowDropPainter(
        fill: AlwaysStoppedAnimation<double>(fill),
        color: ink,
      );

  _RecordingCanvas record(double fill) {
    final canvas = _RecordingCanvas();
    painterAt(fill).paint(canvas, const Size(24, 24));
    return canvas;
  }

  group('FlowDropPainter geometry', () {
    // The droplet is lifted from the deleted SVGs:
    //   M12 2.5 C12 2.5 5 10.5 5 15 a7 7 0 0 0 14 0 c0-4.5-7-12.5-7-12.5 z
    // The arc's sweep flag is the one thing a hand translation gets wrong, and
    // it fails SILENTLY -- an arc bulging up instead of down still closes into a
    // plausible blob. Bottom == 22 (cy 15 + r 7) is what distinguishes them.
    test('the droplet bulges downward, matching the asset outline', () {
      final b = FlowDropPainter.droplet.getBounds();
      expect(b.left, closeTo(5, 0.01));
      expect(b.top, closeTo(2.5, 0.01));
      expect(b.right, closeTo(19, 0.01));
      expect(b.bottom, closeTo(22, 0.01));
    });

    test('paints the outline but no fill at zero', () {
      final rec = record(0);
      expect(rec.paths, isNotEmpty, reason: 'the outline is always drawn');
      expect(rec.rects, isEmpty, reason: 'nothing is filled yet');
    });

    test('clips the fill to the droplet rather than painting a bare rect', () {
      final rec = record(0.6);
      expect(rec.clips, isNotEmpty);
      expect(rec.clippedBeforeFirstRect, isTrue,
          reason: 'an unclipped rect would paint a block across the icon');
    });

    // Each level must land on the exact rect top its SVG used, or the ramp
    // shifts under users who already know it by sight.
    test('reproduces the asset fill line at every level', () {
      const svgRectTop = <FlowIntensity, double>{
        FlowIntensity.spotting: 19.1,
        FlowIntensity.light: 15.2,
        FlowIntensity.medium: 10.3,
        FlowIntensity.heavy: 5.4,
        FlowIntensity.flooding: 2.5, // the tip: a solid droplet
      };
      for (final e in svgRectTop.entries) {
        final rec = record(kFlowFill[e.key]!);
        expect(rec.rects.single.top, closeTo(e.value, 0.03),
            reason: 'fill line for ${e.key}');
        expect(rec.rects.single.bottom, closeTo(22, 0.01));
      }
    });

    test('clamps out-of-range values instead of overflowing the droplet', () {
      expect(record(1.8).rects.single.top, closeTo(2.5, 0.01));
      expect(record(-0.5).rects, isEmpty);
    });
  });

  group('FlowDropStagger', () {
    Future<void> pumpStagger(WidgetTester tester,
        {bool reduceMotion = false}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FlowDropStagger(
              levels: kFlowFill.values.toList(),
              builder: (context, drops) => Row(
                children: [
                  for (final d in drops)
                    FlowDrop(fill: d, color: ink, size: 16),
                ],
              ),
            ),
          ),
        ),
      );
    }

    FlowDropStaggerState stateOf(WidgetTester tester) =>
        tester.state<FlowDropStaggerState>(find.byType(FlowDropStagger));

    /// The painted fills, which settle at DIFFERENT levels per drop.
    List<double> fillsOf(WidgetTester tester) {
      final s = stateOf(tester);
      return [for (var i = 0; i < 5; i++) s.animationAt(i).value];
    }

    /// The raw 0 -> 1 progress, which is the only comparable measure of order.
    List<double> progressOf(WidgetTester tester) {
      final s = stateOf(tester);
      return [for (var i = 0; i < 5; i++) s.progressAt(i).value];
    }

    testWidgets('fills the drops in order, the first leading the last',
        (tester) async {
      await pumpStagger(tester);
      await tester.pump(const Duration(milliseconds: 200));
      final v = progressOf(tester);
      expect(v.first, greaterThan(v.last),
          reason: 'a simultaneous fill is not a stagger');
      for (var i = 1; i < v.length; i++) {
        expect(v[i], lessThanOrEqualTo(v[i - 1]),
            reason: 'drop $i overtook drop ${i - 1}');
      }
      await tester.pumpAndSettle();
    });

    testWidgets('settles with every drop at its full level', (tester) async {
      await pumpStagger(tester);
      await tester.pumpAndSettle();
      expect(fillsOf(tester), kFlowFill.values.toList());
    });

    testWidgets('paints the drops full on frame one when motion is reduced',
        (tester) async {
      await pumpStagger(tester, reduceMotion: true);
      expect(fillsOf(tester), kFlowFill.values.toList());
    });

    // Turning reduced motion OFF mid-session is the one dependency change this
    // widget can actually observe, and it must not rewind a row the user is
    // already looking at.
    //
    // Getting here took two wrong tests, both of which passed against a
    // deliberately broken build:
    //   - re-pumping identical MediaQueryData notifies nobody, because
    //     MediaQuery compares data with `==`, so didChangeDependencies never
    //     fired at all;
    //   - changing textScaler notifies nobody EITHER, because MediaQuery is an
    //     InheritedModel and `disableAnimationsOf` subscribes to just that one
    //     aspect.
    // Only a change to disableAnimations itself reaches this State.
    testWidgets('does not replay when reduced motion is switched off',
        (tester) async {
      await pumpStagger(tester, reduceMotion: true);
      expect(fillsOf(tester), kFlowFill.values.toList());
      await pumpStagger(tester, reduceMotion: false);
      await tester.pump(const Duration(milliseconds: 120));
      expect(fillsOf(tester), kFlowFill.values.toList(),
          reason: 'a replay would drop these back toward 0');
    });
  });
}

/// A [Canvas] that records what the painter asked for instead of rasterising it,
/// so the fill maths can be asserted in viewBox units without golden files.
class _RecordingCanvas implements ui.Canvas {
  final List<ui.Rect> rects = <ui.Rect>[];
  final List<ui.Path> paths = <ui.Path>[];
  final List<ui.Path> clips = <ui.Path>[];
  bool clippedBeforeFirstRect = false;

  @override
  void drawRect(ui.Rect rect, ui.Paint paint) {
    if (rects.isEmpty && clips.isNotEmpty) clippedBeforeFirstRect = true;
    rects.add(rect);
  }

  @override
  void drawPath(ui.Path path, ui.Paint paint) => paths.add(path);

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) => clips.add(path);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
