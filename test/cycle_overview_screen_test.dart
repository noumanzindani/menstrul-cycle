import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/cycle_overview.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/screens/insights/cycle_overview_screen.dart';

/// The per-cycle overview screen renders every category it has data for, in one
/// place, from a pre-computed [CycleOverview].
void main() {
  testWidgets('shows each category section for a cycle', (tester) async {
    // Phone-width but tall enough that the whole list is laid out. The screen
    // is a lazy `ListView`: at the default 800x600 harness surface the sections
    // below the fold are never BUILT, so `find.text` reports them missing even
    // though the widget renders them — which is not what this test is about.
    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final overview = CycleOverview(
      start: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 4),
      cycleLength: 28,
      periodLength: 4,
      peakFlow: FlowIntensity.heavy,
      bleedingDays: 4,
      symptoms: const [LabeledCount('Cramps', 3), LabeledCount('Headache', 1)],
      emotions: const [LabeledCount('Low', 2)],
      painAverage: 5.0,
      painPeak: 7,
      lifestyle: const [LabeledCount('Exercise', 2)],
      medications: const [LabeledCount('Vitamin D', 3)],
      notesCount: 1,
    );

    await tester.pumpWidget(MaterialApp(
      home: CycleOverviewScreen(overview: overview),
    ));
    await tester.pumpAndSettle();

    for (final header in [
      'Bleeding',
      'Symptoms',
      'Emotions',
      'Pain',
      'Lifestyle',
      'Medications',
    ]) {
      expect(find.text(header), findsOneWidget, reason: 'missing $header');
    }
    expect(find.text('Cramps'), findsOneWidget);
    expect(find.text('Exercise'), findsOneWidget);
    expect(find.text('Vitamin D'), findsOneWidget);
  });
}
