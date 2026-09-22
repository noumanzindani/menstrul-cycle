import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  final day = DateTime(2026, 5, 7);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });
  tearDown(() => db.close());

  test('creates a notes-only row for a day with no log', () async {
    await repo.setNotes(date: day, notes: 'first note');
    final log = await repo.getForDate(day);
    expect(log?.notes, 'first note');
    expect(log?.flow, isNull);
  });

  test('touches ONLY the note: flow, tags, bbt and opk survive', () async {
    final tags = encodeDayTags(flags: {'cramps'});
    await repo.upsert(
      date: day,
      flow: FlowIntensity.medium,
      symptomsJson: tags,
      mood: 'calm',
      notes: 'old',
      bbt: 36.6,
      opk: 'positive',
    );
    await repo.setNotes(date: day, notes: 'new');

    final log = (await repo.getForDate(day))!;
    expect(log.notes, 'new');
    expect(log.flow, FlowIntensity.medium);
    expect(log.symptoms, tags);
    expect(log.mood, 'calm');
    expect(log.bbt, 36.6);
    expect(log.opk, 'positive');
  });

  test('stamps updatedAt so the edit syncs', () async {
    await repo.upsert(date: day, symptomsJson: encodeDayTags(), notes: 'a');
    final before = (await repo.getForDate(day))!.updatedAt;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await repo.setNotes(date: day, notes: 'b');
    final after = (await repo.getForDate(day))!.updatedAt;
    expect(after.isAfter(before), isTrue);
  });

  test('a blank note clears an existing note but keeps the day', () async {
    await repo.upsert(
        date: day, flow: FlowIntensity.light,
        symptomsJson: encodeDayTags(), notes: 'x');
    await repo.setNotes(date: day, notes: '   ');
    final log = (await repo.getForDate(day))!;
    expect(log.notes, isNull);
    expect(log.flow, FlowIntensity.light);
  });

  test('a blank note on an empty day writes no row', () async {
    await repo.setNotes(date: day, notes: '');
    expect(await repo.getForDate(day), isNull);
  });
}
