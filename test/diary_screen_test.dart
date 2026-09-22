import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
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

  testWidgets('while the logs are still being read, does not claim the diary '
      'is empty', (tester) async {
    // A fresh LogProvider has `loading == true` and an empty `logs` list --
    // empty because nothing has been READ yet, not because nothing was
    // WRITTEN. The two are different answers and only one of them is honest
    // here: this user has a note, it just has not arrived.
    await seed(DateTime(2026, 5, 1), 'a real note');
    await tester.pumpWidget(
      ChangeNotifierProvider<LogProvider>.value(
        value: logs, // load() deliberately NOT awaited
        child: const MaterialApp(home: DiaryScreen()),
      ),
    );
    // pump, never pumpAndSettle: a progress indicator animates forever.
    await tester.pump();

    expect(logs.loading, isTrue, reason: 'the fixture stopped being a loading '
        'provider, so this test no longer covers what it claims to');
    expect(find.textContaining('Notes you add'), findsNothing,
        reason: 'the diary told a user with a note that they had none');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

  group('Write a note', () {
    Future<void> openPickerAndConfirm(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('diary-write-note')));
      await tester.pumpAndSettle();
      // Material date picker: the default selection is today, so OK takes it.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('is offered on an empty diary', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('diary-write-note')), findsOneWidget);
    });

    testWidgets('is offered on a diary with notes too', (tester) async {
      await seed(DateTime(2026, 5, 1), 'a note');
      await pump(tester);
      expect(find.byKey(const Key('diary-write-note')), findsOneWidget);
    });

    testWidgets('asks for a date, then saves a note for it', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('diary-write-note')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('note-sheet.text')), 'wrote this today');
      await tester.tap(find.byKey(const Key('note-sheet.save')));
      await tester.pumpAndSettle();

      final today = DateTime.now();
      final log = logs.logForDate(today);
      expect(log?.notes, 'wrote this today');
      expect(find.text('wrote this today'), findsOneWidget,
          reason: 'the new note should appear in the diary list');
    });

    testWidgets('prefills the note already written for that day',
        (tester) async {
      await seed(DateTime.now(), 'already here');
      await pump(tester);
      await openPickerAndConfirm(tester);

      final field =
          tester.widget<TextField>(find.byKey(const Key('note-sheet.text')));
      expect(field.controller?.text, 'already here');
    });

    testWidgets('does not offer future dates', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('diary-write-note')));
      await tester.pumpAndSettle();
      final picker =
          tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      final now = DateTime.now();
      expect(picker.lastDate.isAfter(DateTime(now.year, now.month, now.day)),
          isFalse);
    });

    testWidgets('cancelling the picker opens nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('diary-write-note')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-sheet.text')), findsNothing);
    });

    testWidgets('keeps the rest of the day intact', (tester) async {
      await DailyLogRepository(db).upsert(
        date: DateTime.now(),
        flow: FlowIntensity.heavy,
        symptomsJson: encodeDayTags(flags: {'cramps'}),
      );
      await pump(tester);
      await openPickerAndConfirm(tester);
      await tester.enterText(
          find.byKey(const Key('note-sheet.text')), 'heavy day');
      await tester.tap(find.byKey(const Key('note-sheet.save')));
      await tester.pumpAndSettle();

      final log = logs.logForDate(DateTime.now())!;
      expect(log.flow, FlowIntensity.heavy);
      expect(log.symptoms, contains('cramps'));
      expect(log.notes, 'heavy day');
    });
  });
}
