import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/sync_mapper.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  test('doc id is the ISO date, zero-padded', () {
    expect(syncDocId(DateTime(2026, 8, 4)), '2026-08-04');
    expect(syncDocId(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('round-trips every field, including reserved tag prefixes', () async {
    // Reserved prefixes (med_, sex_, cm_, …) ride the same symptoms blob and
    // must survive sync exactly — a dropped prefix silently loses a whole
    // tracking category.
    const symptoms =
        '{"cramps":true,"med_pill":true,"sex_protected":true,"weight":61.5}';
    final day = DateTime(2026, 8, 4);
    await repo.upsert(
      date: day,
      flow: FlowIntensity.medium,
      symptomsJson: symptoms,
      mood: 'calm',
      notes: 'felt fine',
      bbt: 36.6,
      opk: 'positive',
    );
    final log = (await repo.getForDate(day))!;

    final map = dailyLogToMap(log, deviceId: 'device-abc');
    final companion = dailyLogFromMap(map);

    expect(companion.date.value, day);
    expect(companion.flow.value, FlowIntensity.medium);
    expect(companion.symptoms.value, symptoms);
    expect(companion.mood.value, 'calm');
    expect(companion.notes.value, 'felt fine');
    expect(companion.bbt.value, 36.6);
    expect(companion.opk.value, 'positive');
    expect(map['deviceId'], 'device-abc');
  });

  test('round-trips a sparse row with a null flow and an empty blob', () async {
    final day = DateTime(2026, 8, 5);
    await repo.upsert(date: day, symptomsJson: '{}');
    final log = (await repo.getForDate(day))!;

    final companion = dailyLogFromMap(dailyLogToMap(log, deviceId: 'd'));

    expect(companion.flow.value, isNull);
    expect(companion.symptoms.value, '{}');
    expect(companion.mood.value, isNull);
  });

  test('symptoms travel as a map, not an opaque JSON string', () async {
    final day = DateTime(2026, 8, 6);
    await repo.upsert(date: day, symptomsJson: '{"cramps":true}');
    final log = (await repo.getForDate(day))!;

    final map = dailyLogToMap(log, deviceId: 'd');

    expect(map['symptoms'], isA<Map<String, dynamic>>());
    expect(map['symptoms']['cramps'], isTrue);
  });

  test('an out-of-range flow index decodes to null instead of crashing',
      () async {
    // Defensive: a future app version could write an enum index this build
    // doesn't know. Losing one field beats failing the whole sync.
    final map = {
      'date': '2026-08-07',
      'flow': 99,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 8, 7).millisecondsSinceEpoch,
    };

    expect(dailyLogFromMap(map).flow.value, isNull);
  });

  test('updatedAtFromMap reads the epoch-millis timestamp', () {
    final t = DateTime(2026, 8, 4, 12, 30);
    expect(
      updatedAtFromMap({'updatedAt': t.millisecondsSinceEpoch}),
      t,
    );
    expect(updatedAtFromMap({}), isNull);
  });
}
