import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

/// Insights lists the user's cycles ("Cycle history"); tapping one opens the
/// per-cycle overview screen.
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

  testWidgets('lists cycles and opens the overview on tap', (tester) async {
    // Three period runs → two complete cycles + the open one.
    for (final m in [1, 2, 3]) {
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
      find.text('Cycle history'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cycle history'), findsOneWidget);
    // Three cycles → three rows.
    expect(find.byType(ListTile), findsNWidgets(3));

    // Tap the first listed cycle row → the overview screen opens.
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('Cycle overview'), findsOneWidget);
  });
}
