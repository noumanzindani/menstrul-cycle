import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

/// Insights renders a "Regularity" card that names the regularity category, so
/// the variability number is no longer text-only.
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

  testWidgets('shows a Regularity card naming the category', (tester) async {
    // Four period runs ~28 days apart → 3 complete, very regular cycles.
    for (final m in [1, 2, 3, 4]) {
      for (final d in [1, 2, 3]) {
        await repo.upsert(
            date: DateTime(2026, m, d),
            flow: FlowIntensity.medium,
            symptomsJson: '{}');
      }
    }
    await logs.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Regularity'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Regularity'), findsOneWidget);
    expect(find.text('Regular'), findsOneWidget);
  });
}
