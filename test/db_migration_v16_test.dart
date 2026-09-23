import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v15.dart';

/// v15 → v16 adds the assistant columns to `AnalysisSessions` (`title`,
/// `deleted_at`) and `AnalysisMessages` (`attachments_json`,
/// `include_in_model`) without disturbing a row. Seeds a real v15
/// conversation so a wipe-and-recreate migration would fail, and checks
/// `PRAGMA table_info` because three of the four columns are nullable and a
/// missing `addColumn` would read quietly as null.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  Future<void> seedV15(DatabaseAtV15 oldDb) async {
    await oldDb.customStatement(
      'INSERT INTO analysis_sessions '
      '(id, uid, media_id, consent_version, created_at, updated_at) '
      'VALUES (?, ?, ?, 6, 1767225600, 1767225600)',
      ['s1', 'u1', 'a' * 32],
    );
    await oldDb.customStatement(
      'INSERT INTO analysis_messages '
      '(id, session_id, role, message_text, created_at) '
      'VALUES (?, ?, ?, ?, 1767225600)',
      ['m1', 's1', 'user', 'What do you see?'],
    );
    await oldDb.customStatement(
      'INSERT INTO analysis_messages '
      '(id, session_id, role, message_text, created_at) '
      'VALUES (?, ?, ?, ?, 1767225601)',
      ['m2', 's1', 'model', 'A description.'],
    );
  }

  test(
    'v15 -> v16 adds the assistant columns, preserving the conversation',
    () async {
      final schema = await verifier.schemaAt(15);

      final oldDb = DatabaseAtV15(schema.newConnection());
      await seedV15(oldDb);
      await oldDb.close();

      final db = AppDatabase.forTesting(schema.newConnection());
      await verifier.migrateAndValidate(db, 16);

      Future<List<String>> columnsOf(String table) => db
          .customSelect('PRAGMA table_info($table)')
          .map((r) => r.read<String>('name'))
          .get();
      expect(
        await columnsOf('analysis_sessions'),
        containsAll(['title', 'deleted_at']),
      );
      expect(
        await columnsOf('analysis_messages'),
        containsAll(['attachments_json', 'include_in_model']),
      );

      final session = await db.select(db.analysisSessions).getSingle();
      expect(session.id, 's1');
      expect(session.mediaId, 'a' * 32);
      expect(session.consentVersion, 6);
      expect(session.title, isNull, reason: 'no row is backfilled');
      expect(
        session.deletedAt,
        isNull,
        reason: 'an upgraded conversation must not read as deleted',
      );

      final messages = await (db.select(
        db.analysisMessages,
      )..orderBy([(t) => OrderingTerm(expression: t.createdAt)])).get();
      expect(messages.map((m) => m.messageText), [
        'What do you see?',
        'A description.',
      ]);
      expect(messages.map((m) => m.attachmentsJson), [null, null]);
      expect(
        messages.map((m) => m.includeInModel),
        [true, true],
        reason: 'every v15 turn was sent to the model, so it must replay',
      );

      await db.close();
    },
  );

  test('v15 -> v16 survives columns a newer install already added', () async {
    // A v16 build, then a v15 build installed over it, leaves user_version at
    // 15 with the v16 columns physically present. Re-running the branch must
    // skip them rather than throw "duplicate column name" on every open.
    final schema = await verifier.schemaAt(15);

    final oldDb = DatabaseAtV15(schema.newConnection());
    await seedV15(oldDb);
    await oldDb.customStatement(
      'ALTER TABLE analysis_sessions ADD COLUMN title TEXT NULL',
    );
    await oldDb.customStatement(
      'ALTER TABLE analysis_messages ADD COLUMN attachments_json TEXT NULL',
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 16);

    final messages = await db.select(db.analysisMessages).get();
    expect(messages, hasLength(2));
    expect(messages.every((m) => m.includeInModel), isTrue);

    await db.close();
  });
}
