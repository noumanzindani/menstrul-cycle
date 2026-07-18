import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/models/cycle_overview.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/screens/insights/cycle_overview_screen.dart';

/// The per-cycle overview screen renders every category it has data for, in one
/// place, from a pre-computed [CycleOverview].
void main() {
  testWidgets('shows each category section for a cycle', (tester) async {
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
      medications: const [],
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
    ]) {
      expect(find.text(header), findsOneWidget, reason: 'missing $header');
    }
    expect(find.text('Cramps'), findsOneWidget);
    expect(find.text('Exercise'), findsOneWidget);
  });
}
