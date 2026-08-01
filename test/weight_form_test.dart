import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late LogProvider logs;
  final day = DateTime(2026, 3, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = LogProvider(DailyLogRepository(db));
    await logs.load();
  });

  tearDown(() => db.close());

  Future<GlobalKey<DayEntryFormState>> pump(
    WidgetTester tester, {
    Set<String>? categories,
  }) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(
          home: Scaffold(
            body: DayEntryForm(key: key, date: day, categories: categories),
          ),
        ),
      ),
    );
    return key;
  }

  // The form is a lazy ListView, so anything below the viewport is not in the
  // element tree at all. Scroll it into existence before touching it.
  Future<void> scrollTo(WidgetTester tester, Finder target) => tester
      .dragUntilVisible(target, find.byType(ListView), const Offset(0, -300));

  final weightField = find.byKey(const Key('weight-field'));

  testWidgets('saves a typed weight as canonical kg', (tester) async {
    final key = await pump(tester, categories: {kCatWeight});

    await scrollTo(tester, weightField);
    await tester.enterText(weightField, '62.5');
    expect(await key.currentState!.save(), isTrue);

    final saved = logs.logForDate(day);
    expect(decodeNumber(saved!.symptoms, kMetricWeight), closeTo(62.5, 0.001));
  });

  testWidgets('refuses an out-of-range weight and does not save',
      (tester) async {
    final key = await pump(tester, categories: {kCatWeight});

    await scrollTo(tester, weightField);
    await tester.enterText(weightField, '700');
    expect(await key.currentState!.save(), isFalse);
    await tester.pump();

    expect(find.textContaining('between'), findsOneWidget);
    expect(logs.logForDate(day), isNull);
  });

  testWidgets('hides the weight field when the category is off',
      (tester) async {
    await pump(tester, categories: const <String>{});

    // Scroll to Notes FIRST. Weight renders immediately before it, so once
    // Notes is built, an absent weight-field means genuinely gated off rather
    // than merely below the fold — otherwise this assertion is vacuous.
    await scrollTo(tester, find.text('Notes'));
    expect(weightField, findsNothing);
  });

  testWidgets(
      'REGRESSION: a logged weight survives saving with the category off',
      (tester) async {
    // Seed a day that already has a weight.
    await DailyLogRepository(db).upsert(
      date: day,
      flow: null,
      symptomsJson: encodeDayTags(numbers: {kMetricWeight: 62.5}),
    );
    await logs.load();

    // Re-open the editor with Weight hidden and save.
    final key = await pump(tester, categories: const <String>{});
    expect(await key.currentState!.save(), isTrue);

    // encodeDayTags is a full REPLACE, so an un-decoded group would be erased.
    final saved = logs.logForDate(day);
    expect(decodeNumber(saved!.symptoms, kMetricWeight), closeTo(62.5, 0.001));
  });
}
