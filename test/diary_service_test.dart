import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/diary_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seed(DateTime date, String? note) => repo.upsert(
        date: date,
        flow: null,
        symptomsJson: encodeDayTags(),
        notes: note,
      );

  test('lists only days that have a non-blank note, newest first', () async {
    await seed(DateTime(2026, 5, 1), 'first entry');
    await seed(DateTime(2026, 5, 3), null);
    await seed(DateTime(2026, 5, 5), '   ');
    await seed(DateTime(2026, 5, 7), 'latest entry');

    final entries = DiaryService.entries(await repo.getAll());

    expect(entries, hasLength(2));
    expect(entries.first.date, DateTime(2026, 5, 7));
    expect(entries.first.note, 'latest entry');
    expect(entries.last.note, 'first entry');
  });

  test('filters case-insensitively on the note text', () async {
    await seed(DateTime(2026, 5, 1), 'Bad Cramps today');
    await seed(DateTime(2026, 5, 2), 'felt great');

    final entries = DiaryService.entries(await repo.getAll(), query: 'cramps');

    expect(entries, hasLength(1));
    expect(entries.single.note, 'Bad Cramps today');
  });

  test('a blank query returns everything', () async {
    await seed(DateTime(2026, 5, 1), 'one');
    await seed(DateTime(2026, 5, 2), 'two');

    expect(
        DiaryService.entries(await repo.getAll(), query: '   '), hasLength(2));
  });

  test('does not match on symptoms or dates', () async {
    await repo.upsert(
      date: DateTime(2026, 5, 1),
      flow: null,
      symptomsJson: encodeDayTags(flags: {'cramps'}),
      notes: 'a quiet day',
    );

    expect(DiaryService.entries(await repo.getAll(), query: 'cramps'), isEmpty);
    expect(DiaryService.entries(await repo.getAll(), query: '2026'), isEmpty);
  });
}
