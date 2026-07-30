import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/diary/diary_screen.dart';
import 'package:menstrul_track/widgets/ad_banner.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late LogProvider logs;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = LogProvider(DailyLogRepository(db));
  });

  tearDown(() => db.close());

  Future<void> seed(DateTime date, String note) =>
      DailyLogRepository(db).upsert(
        date: date,
        flow: null,
        symptomsJson: encodeDayTags(),
        notes: note,
      );

  Future<void> pump(WidgetTester tester) async {
    await logs.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: const MaterialApp(home: DiaryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists notes newest first', (tester) async {
    await seed(DateTime(2026, 5, 1), 'older note');
    await seed(DateTime(2026, 5, 7), 'newer note');
    await pump(tester);

    expect(find.text('newer note'), findsOneWidget);
    expect(find.text('older note'), findsOneWidget);

    final newer = tester.getTopLeft(find.text('newer note'));
    final older = tester.getTopLeft(find.text('older note'));
    expect(newer.dy, lessThan(older.dy));
  });

  testWidgets('search narrows the list', (tester) async {
    await seed(DateTime(2026, 5, 1), 'bad cramps');
    await seed(DateTime(2026, 5, 2), 'felt great');
    await pump(tester);

    await tester.enterText(find.byKey(const Key('diary-search')), 'cramps');
    await tester.pumpAndSettle();

    expect(find.text('bad cramps'), findsOneWidget);
    expect(find.text('felt great'), findsNothing);
  });

  testWidgets('shows an empty state when nothing is written', (tester) async {
    await pump(tester);
    expect(find.textContaining('Notes you add'), findsOneWidget);
  });

  testWidgets('GUARDRAIL: never renders an ad banner', (tester) async {
    await seed(DateTime(2026, 5, 1), 'a note');
    await pump(tester);
    expect(find.byType(AdBanner), findsNothing);
  });

  testWidgets('tapping a row opens that day\'s entry sheet', (tester) async {
    await seed(DateTime(2026, 5, 7), 'a note worth revisiting');
    await pump(tester);

    await tester.tap(find.text('a note worth revisiting'));
    await tester.pumpAndSettle();

    // The sheet hosts the day's form with its own Save button.
    expect(find.text('Save'), findsOneWidget);
  });
}
