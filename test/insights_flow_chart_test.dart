import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

/// With two+ cycles of flow logged, Insights shows a "Flow intensity trend"
/// section (the heavy-vs-light-over-time view). Gated the same way as the
/// cycle-length trend — needs at least two cycles of data.
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

  testWidgets('shows the flow-intensity trend for 2+ cycles with flow',
      (tester) async {
    // Cycle 1 (light), then cycle 2 (heavy) → a real two-point trend.
    for (final d in [1, 2, 3]) {
      await repo.upsert(
          date: DateTime(2026, 1, d), flow: FlowIntensity.light, symptomsJson: '{}');
    }
    for (final d in [1, 2, 3]) {
      await repo.upsert(
          date: DateTime(2026, 2, d), flow: FlowIntensity.heavy, symptomsJson: '{}');
    }
    await logs.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Flow intensity trend'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flow intensity trend'), findsOneWidget);
  });
}
