import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/widgets/entrance.dart';

/// [EntranceGroup] runs ONE controller for a whole list and hands each row an
/// [Interval] of it. The alternative — a controller per row — is one `Ticker`
/// per row, which is what makes a long list expensive on the low-end target.
///
/// Pumped without a `MaterialApp` on purpose: its route transitions bring
/// `FadeTransition`s of their own, and every assertion here is about finding
/// the row's OWN fade.
void main() {
  Widget harness(Widget child, {bool reduceMotion = false}) => Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: child,
        ),
      );

  Widget rows(int count) => Column(
        children: [
          for (var i = 0; i < count; i++)
            EntranceItem(
              index: i,
              child: SizedBox(key: ValueKey('row-$i'), height: 10),
            ),
        ],
      );

  double opacityOf(WidgetTester tester, int i) => tester
      .widget<FadeTransition>(find
          .ancestor(
            of: find.byKey(ValueKey('row-$i')),
            matching: find.byType(FadeTransition),
          )
          .first)
      .opacity
      .value;

  testWidgets('rows arrive in order, not all at once', (tester) async {
    await tester.pumpWidget(harness(EntranceGroup(child: rows(4))));
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      expect(opacityOf(tester, i), 0.0, reason: 'row $i at rest on frame one');
    }

    // Mid-flight the earlier rows are strictly ahead of the later ones. That
    // ordering IS the stagger; asserting only "something moved" would pass for
    // four rows fading in lockstep.
    await tester.pump(const Duration(milliseconds: 150));
    final at = [for (var i = 0; i < 4; i++) opacityOf(tester, i)];
    expect(at[0], greaterThan(at[1]));
    expect(at[1], greaterThan(at[2]));
    expect(at[2], greaterThan(at[3]));

    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      expect(opacityOf(tester, i), 1.0);
    }
  });

  testWidgets('reduced motion renders the whole list at rest on frame one',
      (tester) async {
    await tester.pumpWidget(
      harness(EntranceGroup(child: rows(4)), reduceMotion: true),
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      expect(opacityOf(tester, i), 1.0);
    }
  });

  testWidgets('rows past the cap share the last interval', (tester) async {
    await tester.pumpWidget(harness(EntranceGroup(
      child: Column(
        children: [
          EntranceItem(
            index: EntranceGroup.maxStaggered - 1,
            child: const SizedBox(key: ValueKey('row-0'), height: 10),
          ),
          const EntranceItem(
            index: 200,
            child: SizedBox(key: ValueKey('row-1'), height: 10),
          ),
        ],
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A forty-entry diary must not take four seconds to arrive. Row 200 is
    // built long after the controller finished anyway; this pins that it is
    // never given an interval running past the end of the timeline, which
    // `Interval` would assert on.
    expect(opacityOf(tester, 1), opacityOf(tester, 0));
  });

  testWidgets('the last staggered row lands exactly on the end', (tester) async {
    // step, window and maxStaggered are not independently adjustable: the last
    // interval must finish at 1.0, and `Interval` asserts end <= 1.0.
    final lastStart = (EntranceGroup.maxStaggered - 1) * EntranceGroup.step;
    expect(lastStart + EntranceGroup.window, closeTo(1.0, 1e-9));
  });

  testWidgets('an item with no group above it renders its child untouched',
      (tester) async {
    await tester.pumpWidget(harness(
      const EntranceItem(
        index: 0,
        child: SizedBox(key: ValueKey('row-0'), height: 10),
      ),
    ));
    await tester.pump();

    // So a row can be pumped on its own in a widget test without dragging the
    // animation in.
    expect(find.byType(FadeTransition), findsNothing);
    expect(find.byKey(const ValueKey('row-0')), findsOneWidget);
  });

  testWidgets('the entrance never replays when the list changes',
      (tester) async {
    await tester.pumpWidget(harness(EntranceGroup(child: rows(3))));
    await tester.pumpAndSettle();
    expect(opacityOf(tester, 0), 1.0);

    // A list that re-staggered on every data change would re-animate on every
    // save -- the same rule MonthRing's entrance keeps.
    await tester.pumpWidget(harness(EntranceGroup(child: rows(5))));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      expect(opacityOf(tester, i), 1.0);
    }
  });
}
