import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/data/product_session_repository.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/reminder_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/product_session.dart';
import 'package:menstrul_track/models/product_type.dart';
import 'package:menstrul_track/services/backup_service.dart';

/// Local backup is encrypted with a user passphrase (AES-GCM + PBKDF2) so a file
/// that leaves the device (Drive/Downloads) never exposes health data. There is
/// NO cloud and no server — the user owns the file.
void main() {
  group('BackupCrypto', () {
    test('round-trips text with the correct passphrase', () async {
      final blob = await BackupCrypto.encrypt('my private cycle data', 'hunter2');
      expect(await BackupCrypto.decrypt(blob, 'hunter2'), 'my private cycle data');
    });

    test('the wrong passphrase fails (authenticated encryption)', () async {
      final blob = await BackupCrypto.encrypt('my private cycle data', 'hunter2');
      expect(BackupCrypto.decrypt(blob, 'wrong-pass'), throwsA(anything));
    });

    test('the ciphertext does not contain the plaintext', () async {
      final blob = await BackupCrypto.encrypt('cramps luteal headache', 'pw');
      expect(utf8.decode(blob, allowMalformed: true),
          isNot(contains('cramps')));
    });

    test('a truncated/garbage blob is rejected, not silently accepted', () async {
      expect(BackupCrypto.decrypt(Uint8List.fromList([1, 2, 3]), 'pw'),
          throwsA(anything));
    });
  });

  group('BackupService export/import round-trip', () {
    late AppDatabase src;

    Future<void> seed(AppDatabase db) async {
      final repo = DailyLogRepository(db);
      await repo.upsert(
          date: DateTime(2026, 5, 1),
          flow: FlowIntensity.medium,
          symptomsJson: '{"cramps":true}',
          bbt: 36.55,
          opk: 'positive');
      await repo.upsert(
          date: DateTime(2026, 5, 2), flow: FlowIntensity.light, symptomsJson: '{}');
      await db.into(db.reminders).insert(RemindersCompanion.insert(
          type: ReminderType.periodSoon, hour: 8, minute: 30));
      await db
          .into(db.medications)
          .insert(MedicationsCompanion.insert(name: 'Vitamin D'));
      await db.into(db.appSettings).insertOnConflictUpdate(AppSettingsCompanion(
          id: const Value(0),
          mode: const Value(TrackingMode.conceive),
          defaultCycleLength: const Value(30)));
    }

    setUp(() async {
      src = AppDatabase.forTesting(NativeDatabase.memory());
      await seed(src);
    });
    tearDown(() => src.close());

    test('restores every table into a fresh, empty database', () async {
      final bytes = await BackupService.exportEncrypted(src, 'pass123');

      final dst = AppDatabase.forTesting(NativeDatabase.memory());
      await BackupService.importEncrypted(dst, bytes, 'pass123');

      final logs = await dst.select(dst.dailyLogs).get()
        ..sort((a, b) => a.date.compareTo(b.date));
      expect(logs.length, 2);
      expect(logs.first.bbt, 36.55);
      expect(logs.first.opk, 'positive');
      expect(logs.first.symptoms, '{"cramps":true}');

      expect((await dst.select(dst.reminders).get()).single.hour, 8);
      expect((await dst.select(dst.medications).get()).single.name, 'Vitamin D');
      final settings =
          await (dst.select(dst.appSettings)..where((t) => t.id.equals(0)))
              .getSingle();
      expect(settings.mode, TrackingMode.conceive);
      expect(settings.defaultCycleLength, 30);
      await dst.close();
    });

    test('a wrong passphrase throws and leaves existing data untouched',
        () async {
      final bytes = await BackupService.exportEncrypted(src, 'correct');

      // A DIFFERENT db that already has data the user would not want wiped.
      final dst = AppDatabase.forTesting(NativeDatabase.memory());
      await DailyLogRepository(dst).upsert(
          date: DateTime(2026, 9, 9),
          flow: FlowIntensity.heavy,
          symptomsJson: '{}');

      await expectLater(
        BackupService.importEncrypted(dst, bytes, 'WRONG'),
        throwsA(anything),
      );
      // The decrypt fails before any write, so the pre-existing day survives.
      final logs = await dst.select(dst.dailyLogs).get();
      expect(logs.single.date, DateTime(2026, 9, 9));
      await dst.close();
    });
  });

  group('in-progress product session', () {
    test('an exported in-progress session does not restore as a running timer',
        () async {
      final src = AppDatabase.forTesting(NativeDatabase.memory());
      final reminders = ReminderRepository(src);
      // A real reminder that SHOULD survive the round-trip, so this proves the
      // filter is selective rather than just dropping the table.
      await reminders.addCustom(title: 'Water', hour: 9, minute: 0);
      await ProductSessionRepository(reminders).start(ProductSession(
        insertedAt: DateTime(2026, 8, 8, 9, 14),
        product: ProductType.tampon,
        interval: const Duration(hours: 4),
      ));

      final bytes = await BackupService.exportEncrypted(src, 'pw');
      await src.close();

      final dst = AppDatabase.forTesting(NativeDatabase.memory());
      await BackupService.importEncrypted(dst, bytes, 'pw');

      // Restoring a backup taken mid-session must not claim something has been
      // in use since whenever the export happened to be taken.
      // `isNull` is ambiguous here — drift exports one too.
      final restoredSession =
          await ProductSessionRepository(ReminderRepository(dst)).get();
      expect(restoredSession, null);
      final restored = await dst.select(dst.reminders).get();
      expect(restored.map((r) => r.type),
          isNot(contains(ReminderType.productChange)));
      expect(restored.single.title, 'Water');
      await dst.close();
    });
  });
}
