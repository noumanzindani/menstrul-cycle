import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';

/// Category gating is RENDER-ONLY. initState decodes every group and save()
/// re-encodes every group, regardless of what is visible — because
/// encodeDayTags is a full replace, not a merge, so anything missing from form
/// state at save time is destroyed. The two "DISABLED … keeps its stored value"
/// tests are the ones that matter: they fail loudly if gating ever leaks into
/// the decode or encode path.
void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  late LogProvider logs;
  final date = DateTime(2026, 4, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    await logs.load();
  });
  tearDown(() => db.close());

  Widget wrap(Widget child) => ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('an enabled category renders its section', (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: {kCatUrine},
    )));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
        find.text('Urine'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Urine'), findsOneWidget);
    expect(find.text('Blood in urine'), findsOneWidget);
  });

  testWidgets('a disabled category renders nothing', (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: const {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Urine'), findsNothing);
    expect(find.text('Blood in urine'), findsNothing);
    expect(find.text('Lifestyle'), findsNothing);
  });

  testWidgets('a new group round-trips through save', (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: {kCatUrine},
    )));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
        find.text('Frequent'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frequent'));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    expect(decodeGroup(logs.logForDate(date)?.symptoms, kUrineKeyPrefix),
        {'urn_frequent'});
  });

  // THE critical test: the numeric path is where gating can silently erase
  // data, because _metricConfigs feeds BOTH initState decode and build render.
  testWidgets('a DISABLED metric keeps its stored value across a save',
      (tester) async {
    await repo.upsert(
      date: date,
      flow: null,
      symptomsJson: encodeDayTags(numbers: {kMetricSleep: 8}),
    );
    await logs.load();

    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: const {}, // wellbeing OFF -> sleep slider not rendered
    )));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    expect(decodeNumber(logs.logForDate(date)?.symptoms, kMetricSleep), 8,
        reason: 'gating must be render-only; initState must decode everything');
  });

  testWidgets('a DISABLED chip group keeps its stored values across a save',
      (tester) async {
    await repo.upsert(
      date: date,
      flow: null,
      symptomsJson: encodeDayTags(flags: {'urn_frequent', 'habit_exercise'}),
    );
    await logs.load();

    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: const {},
    )));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    final saved = logs.logForDate(date)?.symptoms;
    expect(decodeGroup(saved, kUrineKeyPrefix), {'urn_frequent'});
    expect(decodeGroup(saved, kHabitKeyPrefix), {'habit_exercise'});
  });

  testWidgets('DayLogScreen with no SettingsProvider renders every category',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<LogProvider>.value(
      value: logs,
      child: MaterialApp(home: DayLogScreen(date: date)),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
        find.text('Lifestyle'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Lifestyle'), findsOneWidget);
  });

  testWidgets('medications need BOTH the category on and a configured med',
      (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: const {},
      medications: const [MedChip(1, 'Iron')],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Iron'), findsNothing);
  });
}
