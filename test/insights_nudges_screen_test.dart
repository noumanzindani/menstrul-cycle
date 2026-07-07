import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

/// The Insights screen surfaces the non-diagnostic pattern nudges. Here we seed
/// recurrent severe pain (+ a cycle so the dashboard renders) and expect the
/// endometriosis nudge to appear under a clearly-labelled, non-diagnostic
/// section.
void main() {
  late AppDatabase db;
  late LogProvider logs;
  late DailyLogRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
  });
  tearDown(() => db.close());

  Widget wrap() => ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: const MaterialApp(home: InsightsScreen()),
      );

  testWidgets('shows the endometriosis nudge for recurrent severe pain',
      (tester) async {
    // Two period runs → one complete cycle, so the dashboard renders.
    for (final d in [1, 2, 3]) {
      await repo.upsert(
          date: DateTime(2026, 1, d), flow: FlowIntensity.medium, symptomsJson: '{}');
    }
    for (final d in [5, 6, 7]) {
      await repo.upsert(
          date: DateTime(2026, 2, d), flow: FlowIntensity.medium, symptomsJson: '{}');
    }
    // Three days of severe pain (>=7/10).
    for (final date in [DateTime(2026, 1, 2), DateTime(2026, 1, 15), DateTime(2026, 2, 6)]) {
      await repo.upsert(
          date: date, symptomsJson: encodeDayTags(numbers: {kMetricPain: 8}));
    }
    await logs.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // The section sits below stats/trend/flags, so scroll it into view first.
    await tester.dragUntilVisible(
      find.text('Patterns worth discussing'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Patterns worth discussing'), findsOneWidget);
    expect(find.textContaining('severe pain'), findsOneWidget);
    // Must read as a prompt, never a diagnosis.
    expect(find.textContaining('not a diagnosis'), findsOneWidget);
  });
}
