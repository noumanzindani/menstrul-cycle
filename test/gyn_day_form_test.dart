import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';

/// The day-editor half of the gynaecological intake (Tier 2 + the intimate
/// group). The interesting cases are the two that concern data the user has
/// ALREADY logged: the retired libido boolean must survive its replacement,
/// and the new category must obey the render-only gating rule that every other
/// group obeys.
void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  late LogProvider logs;
  final date = DateTime(2026, 5, 4);

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

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.dragUntilVisible(
        f, find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
  }

  testWidgets('libido is a scale in the sexual-health section', (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: {kCatSexualHealth},
    )));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Low libido'));
    await tester.tap(find.text('Low libido'));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    expect(decodeLibido(logs.logForDate(date)?.symptoms), kLibidoLow);
  });

  testWidgets('a day logged under the retired boolean opens as High, and '
      'saving migrates it to the new key', (tester) async {
    await repo.upsert(
      date: date,
      flow: null,
      symptomsJson: encodeDayTags(flags: {kLegacyHighLibidoKey, 'shx_pain'}),
    );
    await logs.load();

    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: {kCatSexualHealth},
    )));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    final saved = logs.logForDate(date)?.symptoms;
    expect(decodeLibido(saved), kLibidoHigh,
        reason: 'the answer must survive the boolean being retired');
    expect(decodeGroup(saved, kSexualHealthKeyPrefix), {'shx_pain'},
        reason: 'the retired key is rewritten forward, not carried twice');
  });

  testWidgets('bleeding after sex is offered in sexual health', (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: {kCatSexualHealth},
    )));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Bleeding after sex'));
    expect(find.text('Bleeding after sex'), findsOneWidget);
  });

  testWidgets('the heavy-bleeding markers are physical symptoms',
      (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: {kCatPhysicalSymptoms},
    )));
    await tester.pumpAndSettle();

    await reveal(tester, find.text('Soaking through hourly'));
    await tester.tap(find.text('Soaking through hourly'));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    expect(decodeSymptoms(logs.logForDate(date)?.symptoms),
        contains(kSymptomSoakingHourly));
  });

  group('the intimate category', () {
    testWidgets('ships OFF, so no existing day editor grows unasked',
        (tester) async {
      expect(defaultEnabledCategoryIds(), isNot(contains(kCatIntimacy)));

      await tester.pumpWidget(wrap(DayEntryForm(
        date: date,
        categories: defaultEnabledCategoryIds(),
      )));
      await tester.pumpAndSettle();
      expect(find.text('Masturbation'), findsNothing);
    });

    testWidgets('round-trips when enabled', (tester) async {
      final key = GlobalKey<DayEntryFormState>();
      await tester.pumpWidget(wrap(DayEntryForm(
        key: key,
        date: date,
        categories: {kCatIntimacy},
      )));
      await tester.pumpAndSettle();

      await reveal(tester, find.text('Masturbation'));
      await tester.tap(find.text('Masturbation'));
      await tester.pumpAndSettle();
      await key.currentState!.save();

      expect(decodeGroup(logs.logForDate(date)?.symptoms, kIntimacyKeyPrefix),
          {'slf_masturbation'});
    });

    testWidgets('DISABLED keeps its stored values across a save',
        (tester) async {
      await repo.upsert(
        date: date,
        flow: null,
        symptomsJson:
            encodeDayTags(flags: {'slf_masturbation', kLibidoLow}),
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
      expect(decodeGroup(saved, kIntimacyKeyPrefix), {'slf_masturbation'});
      expect(decodeLibido(saved), kLibidoLow);
    });
  });
}
