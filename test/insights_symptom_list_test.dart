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

/// Insights surfaces a ranked "Most-logged symptoms" list built from the user's
/// day logs, so every logged symptom is visible — not just the two the narrator
/// happens to pick.
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

  testWidgets('shows a ranked most-logged symptoms section', (tester) async {
    // Two period runs → one complete cycle so the dashboard renders.
    for (final d in [1, 2, 3]) {
      await repo.upsert(
          date: DateTime(2026, 1, d), flow: FlowIntensity.medium, symptomsJson: '{}');
    }
    for (final d in [1, 2, 3]) {
      await repo.upsert(
          date: DateTime(2026, 2, d), flow: FlowIntensity.medium, symptomsJson: '{}');
    }
    // Cramps logged on several days.
    for (final date in [DateTime(2026, 1, 2), DateTime(2026, 1, 10), DateTime(2026, 1, 20)]) {
      await repo.upsert(date: date, symptomsJson: encodeDayTags(flags: {'cramps'}));
    }
    await logs.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Most-logged symptoms'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Most-logged symptoms'), findsOneWidget);
    expect(find.text('Cramps'), findsOneWidget);
  });
}
