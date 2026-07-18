import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

/// The Insights screen shows a "Your patterns" section of plain-language
/// narratives computed from the user's own logs, clearly framed as descriptions
/// rather than a diagnosis.
void main() {
  late AppDatabase db;
  late LogProvider logs;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
  });
  tearDown(() => db.close());

  Widget wrap() => ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: const MaterialApp(home: InsightsScreen()),
      );

  testWidgets('renders "Your patterns" with a regularity narrative',
      (tester) async {
    // Four period runs exactly 28 days apart → three complete 28-day cycles →
    // zero variability → the "very regular" narrative.
    for (final start in [
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 29),
      DateTime(2026, 2, 26),
      DateTime(2026, 3, 26),
    ]) {
      for (var i = 0; i < 3; i++) {
        await repo.upsert(
            date: start.add(Duration(days: i)),
            flow: FlowIntensity.medium,
            symptomsJson: '{}');
      }
    }
    await logs.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // The section now sits below the stat grid + regularity card, so scroll it
    // into view first.
    await tester.dragUntilVisible(
      find.text('Your patterns'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your patterns'), findsOneWidget);
    expect(find.textContaining('very regular'), findsOneWidget);
    // Must read as description, never diagnosis. Assert the section's own
    // subtitle specifically (several sections now carry a "not a diagnosis"
    // caveat, which is exactly the intent — this pins the Your-patterns one).
    expect(find.textContaining('descriptions, not a diagnosis'), findsOneWidget);
  });
}
