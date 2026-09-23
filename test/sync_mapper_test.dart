import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/media_analysis.dart';
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
    expect(companion.createdAt.value, log.createdAt);
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

  test('createdAt falls back to updatedAt when absent', () {
    final updatedAtTime = DateTime(2026, 8, 7, 10, 30);
    final map = {
      'date': '2026-08-07',
      'symptoms': <String, dynamic>{},
      'updatedAt': updatedAtTime.millisecondsSinceEpoch,
    };

    expect(
      dailyLogFromMap(map).createdAt.value,
      updatedAtTime,
    );
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

  test('a negative flow index decodes to null instead of crashing', () {
    // Defensive: guard the lower bound as well as the upper bound.
    final map = {
      'date': '2026-08-08',
      'flow': -1,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 8, 8).millisecondsSinceEpoch,
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

  group('assistant conversations (v16 fields)', () {
    Future<AnalysisSession> storedSession(AnalysisSessionsCompanion c) async {
      await db.into(db.analysisSessions).insert(c);
      return db.select(db.analysisSessions).getSingle();
    }

    Future<AnalysisMessage> storedMessage(AnalysisMessagesCompanion c) async {
      await db.into(db.analysisMessages).insert(c);
      return db.select(db.analysisMessages).getSingle();
    }

    test('a live session carries its title and no deletedAt', () async {
      final row = await storedSession(AnalysisSessionsCompanion.insert(
        id: 's-1',
        uid: 'uid-1',
        mediaId: '',
        consentVersion: 7,
        title: const Value('why is my cycle long'),
      ));

      final map = analysisSessionToMap(row);

      expect(map['title'], 'why is my cycle long');
      expect(map.containsKey('deletedAt'), isFalse);
    });

    test('a tombstone keeps the full v15 shape, adds deletedAt, drops title',
        () async {
      // v15 clients rebuild the whole row from this document. Without
      // `mediaId`, `consentVersion` and `createdAt` they would store an empty
      // ghost row; with a title, the user's own first words would outlive
      // their delete.
      final deleted = DateTime(2026, 9, 20, 10);
      final row = await storedSession(AnalysisSessionsCompanion.insert(
        id: 's-1',
        uid: 'uid-1',
        mediaId: 'media-1',
        consentVersion: 7,
        title: const Value('left over'),
        deletedAt: Value(deleted),
      ));

      final map = analysisSessionToMap(row);

      expect(map['uid'], 'uid-1');
      expect(map['mediaId'], 'media-1');
      expect(map['consentVersion'], 7);
      expect(map['createdAt'], isA<int>());
      expect(map['updatedAt'], isA<int>());
      expect(map['deletedAt'], deleted.millisecondsSinceEpoch);
      expect(map.containsKey('title'), isFalse);
    });

    test('title and deletedAt round-trip from a document', () {
      final deleted = DateTime(2026, 9, 20, 10);
      final c = analysisSessionFromMap('s-1', {
        'uid': 'uid-1',
        'mediaId': '',
        'consentVersion': 7,
        'title': 'hello',
        'deletedAt': deleted.millisecondsSinceEpoch,
      });

      expect(c.title.value, 'hello');
      expect(c.deletedAt.value, deleted);
    });

    test('a v15 session document defaults the new fields', () {
      final c = analysisSessionFromMap('s-1', {
        'uid': 'uid-1',
        'mediaId': 'media-1',
        'consentVersion': 6,
      });

      expect(c.deletedAt.value, isNull);
      // ABSENT, not null: a v15 device re-pushing a conversation it only
      // knows the old shape of must not erase the title this device holds.
      // On insert an absent column takes its default, which is null anyway.
      expect(c.title.present, isFalse);
    });

    test('a message sends its attachments as references and includeInModel',
        () async {
      final row = await storedMessage(AnalysisMessagesCompanion.insert(
        id: 'm-1',
        sessionId: 's-1',
        role: 'model',
        messageText: 'I cannot look at videos yet',
        attachmentsJson: Value(encodeAttachments([
          AttachmentRef.image('a' * 32),
          AttachmentRef.video('b' * 32),
        ])),
        includeInModel: const Value(false),
      ));

      final map = analysisMessageToMap(row);

      expect(map['includeInModel'], isFalse);
      expect(map['attachments'], [
        {'mediaId': 'a' * 32, 'kind': 'image'},
        {'mediaId': 'b' * 32, 'kind': 'video'},
      ]);
    });

    test('a message with no attachments sends none', () async {
      final row = await storedMessage(AnalysisMessagesCompanion.insert(
        id: 'm-1',
        sessionId: 's-1',
        role: 'user',
        messageText: 'hi',
      ));

      final map = analysisMessageToMap(row);

      expect(map.containsKey('attachments'), isFalse);
      expect(map['includeInModel'], isTrue);
    });

    test('attachments round-trip from a document', () {
      final c = analysisMessageFromMap('m-1', {
        'sessionId': 's-1',
        'role': 'user',
        'messageText': 'look',
        'attachments': [
          {'mediaId': 'a' * 32, 'kind': 'image'},
        ],
        'includeInModel': false,
      });

      expect(decodeAttachments(c.attachmentsJson.value),
          [AttachmentRef.image('a' * 32)]);
      expect(c.includeInModel.value, isFalse);
    });

    test('a v15 message document defaults to no attachments, sent to model',
        () {
      final c = analysisMessageFromMap('m-1', {
        'sessionId': 's-1',
        'role': 'model',
        'messageText': 'a description',
      });

      expect(c.attachmentsJson.value, isNull);
      expect(c.includeInModel.value, isTrue);
    });

    test('malformed attachments from another client read as none', () {
      final c = analysisMessageFromMap('m-1', {
        'sessionId': 's-1',
        'role': 'user',
        'messageText': 'x',
        'attachments': 'not a list',
      });
      expect(c.attachmentsJson.value, isNull);

      final partial = analysisMessageFromMap('m-2', {
        'sessionId': 's-1',
        'role': 'user',
        'messageText': 'x',
        'attachments': [
          {'mediaId': 'a' * 32, 'kind': 'image', 'url': 'https://x'},
          {'kind': 'image'},
          42,
        ],
      });
      // Only the id and kind of a well-formed entry survive; the URL never
      // reaches the local row.
      expect(partial.attachmentsJson.value,
          encodeAttachments([AttachmentRef.image('a' * 32)]));
    });
  });
}
