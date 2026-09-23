import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v10.dart';

/// v10 → v11 must ADD the `AnalysisSessions` / `AnalysisMessages` tables and
/// `AppSettings.analysisConsentVersion` without disturbing existing rows.
/// Seeds NON-DEFAULT values on purpose: asserting defaults survive would also
/// pass against a wipe-and-recreate migration.
///
/// The new column must read NULL. That is the only correct answer — an
/// existing user's stored `analysisConsentUid` predates the sheet disclosing
/// that a whole tracked health record (not just a photo) is sent, so a
/// fabricated version number would read as consent to something they were
/// never shown.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v10 -> v11 adds session tables and consent version, preserves '
      'existing data', () async {
    final schema = await verifier.schemaAt(10);

    final oldDb = DatabaseAtV10(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, height_cm, analysis_consent_uid) '
      'VALUES (0, 31, 165.0, ?)',
      ['uid-abc'],
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms, notes) VALUES (?, ?, ?)',
      [
        DateTime(2026, 3, 3).millisecondsSinceEpoch ~/ 1000,
        '{"cramps":true}',
        'a note that must survive',
      ],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 16);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.heightCm, 165.0);
    expect(settings.analysisConsentUid, 'uid-abc');
    expect(settings.analysisConsentVersion, isNull,
        reason: 'an existing consent predates the v11 disclosure');

    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, '{"cramps":true}');
    expect(logs.single.notes, 'a note that must survive');

    // The new tables exist and are empty for an existing user.
    final sessions = await db.select(db.analysisSessions).get();
    final messages = await db.select(db.analysisMessages).get();
    expect(sessions, isEmpty);
    expect(messages, isEmpty);

    // And are actually usable post-migration, not merely present.
    await db.into(db.analysisSessions).insert(
          AnalysisSessionsCompanion.insert(
            id: 'session-1',
            uid: 'uid-abc',
            mediaId: 'media-1',
            consentVersion: 2,
          ),
        );
    await db.into(db.analysisMessages).insert(
          AnalysisMessagesCompanion.insert(
            id: 'message-1',
            sessionId: 'session-1',
            role: 'user',
            messageText: 'what is this?',
          ),
        );
    final storedSessions = await db.select(db.analysisSessions).get();
    final storedMessages = await db.select(db.analysisMessages).get();
    expect(storedSessions.single.uid, 'uid-abc');
    expect(storedSessions.single.mediaId, 'media-1');
    expect(storedSessions.single.consentVersion, 2);
    expect(storedMessages.single.sessionId, 'session-1');
    expect(storedMessages.single.role, 'user');
    expect(storedMessages.single.messageText, 'what is this?');

    await db.close();
  });
}
