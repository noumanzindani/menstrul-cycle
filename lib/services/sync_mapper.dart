import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../models/enums.dart';

/// Firestore document id for a day: the local ISO-8601 date, e.g. `2026-08-04`.
///
/// Mirrors the `uniqueKeys => [{date}]` constraint on `DailyLogs`, which makes
/// remote writes idempotent — a day cannot be duplicated and a re-push simply
/// overwrites, so the sync loop can safely repeat work but never lose data.
String syncDocId(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

/// Encodes a local row for Firestore.
///
/// `symptoms` is written as a real map rather than the raw JSON string so the
/// console is readable and the field stays queryable later. `flow` travels as
/// the enum INDEX, matching `intEnum` locally: storing the name would break
/// silently if the enum were reordered, whereas an index breaks loudly on an
/// out-of-range value (which [dailyLogFromMap] handles).
Map<String, dynamic> dailyLogToMap(
  DailyLog log, {
  required String deviceId,
}) {
  return {
    'date': syncDocId(log.date),
    'flow': log.flow?.index,
    'symptoms': jsonDecode(log.symptoms) as Map<String, dynamic>,
    'mood': log.mood,
    'notes': log.notes,
    'bbt': log.bbt,
    'opk': log.opk,
    'createdAt': log.createdAt.millisecondsSinceEpoch,
    'updatedAt': log.updatedAt.millisecondsSinceEpoch,
    'deviceId': deviceId,
  };
}

/// Decodes a Firestore document into a drift companion ready to upsert.
DailyLogsCompanion dailyLogFromMap(Map<String, dynamic> map) {
  final parts = (map['date'] as String).split('-');
  final date = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );

  final flowIndex = map['flow'] as int?;
  final flow = (flowIndex != null &&
          flowIndex >= 0 &&
          flowIndex < FlowIntensity.values.length)
      ? FlowIntensity.values[flowIndex]
      : null;

  final symptoms = (map['symptoms'] as Map?)?.cast<String, dynamic>() ?? {};

  final updatedAt = updatedAtFromMap(map) ?? DateTime.now();

  return DailyLogsCompanion(
    date: Value(date),
    flow: Value(flow),
    symptoms: Value(jsonEncode(symptoms)),
    mood: Value(map['mood'] as String?),
    notes: Value(map['notes'] as String?),
    bbt: Value((map['bbt'] as num?)?.toDouble()),
    opk: Value(map['opk'] as String?),
    createdAt: Value(createdAtFromMap(map) ?? updatedAt),
    updatedAt: Value(updatedAt),
  );
}

/// The remote row's creation time.
DateTime? createdAtFromMap(Map<String, dynamic> map) {
  final millis = map['createdAt'] as int?;
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

/// The remote row's last-modified time, used for last-write-wins merging.
DateTime? updatedAtFromMap(Map<String, dynamic> map) {
  final millis = map['updatedAt'] as int?;
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

// ---------------------------------------------------------------------------
// v12: reminders, medications and saved photo-description conversations.
//
// Added when the owner asked for every table to be backed up (2026-09-18),
// reversing two earlier local-only rulings. See `CLAUDE.md`.
// ---------------------------------------------------------------------------

final Random _syncIdRnd = Random.secure();

/// A fresh opaque sync id: 128 random bits as 32 lowercase hex characters.
///
/// Mirrors `newMediaId()`. `Reminders.id` and `Medications.id` are
/// `autoIncrement` — a LOCAL rowid, so device A's row 3 and device B's row 3
/// are different rows and syncing on it would merge unrelated records.
String newSyncId() => List<int>.generate(16, (_) => _syncIdRnd.nextInt(256))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// The reminder type whose rows must NEVER leave the device.
///
/// The in-progress product-change session rides a dormant `Reminders` row's
/// `payload`. `CLAUDE.md`'s change-timer guardrails state that session state
/// "never touches the day-tags blob, Firestore, the doctor PDF, or the
/// home-screen widget", and it is already filtered out of `.lunabak` so a
/// restore cannot resurrect a 71-hour timer. Restoring a tampon timer onto a
/// second device would show a stale elapsed count for a device that was never
/// involved — in the one feature this app places nearest a real emergency.
bool reminderIsSyncable(Reminder row) =>
    row.type != ReminderType.productChange;

Map<String, dynamic> reminderToMap(Reminder row, {required String deviceId}) =>
    {
      'type': row.type.index,
      'hour': row.hour,
      'minute': row.minute,
      'enabled': row.enabled,
      'recurrence': row.recurrence,
      'title': row.title,
      // `payload` is deliberately NOT sent. The only type that uses it is
      // excluded by `reminderIsSyncable`, so a payload reaching this map at all
      // would mean that guard had been bypassed.
      'updatedAt': (row.updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'deviceId': deviceId,
    };

RemindersCompanion reminderFromMap(String syncId, Map<String, dynamic> map) =>
    RemindersCompanion(
      syncId: Value(syncId),
      type: Value(ReminderType
          .values[(map['type'] as num?)?.toInt().clamp(0, ReminderType.values.length - 1) ?? 0]),
      hour: Value((map['hour'] as num?)?.toInt() ?? 0),
      minute: Value((map['minute'] as num?)?.toInt() ?? 0),
      enabled: Value(map['enabled'] as bool? ?? true),
      recurrence: Value(map['recurrence'] as String?),
      title: Value(map['title'] as String?),
      updatedAt: Value(updatedAtFromMap(map)),
    );

Map<String, dynamic> medicationToMap(Medication row,
        {required String deviceId}) =>
    {
      'name': row.name,
      'type': row.type,
      'schedule': row.schedule,
      'enabled': row.enabled,
      'updatedAt': (row.updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'deviceId': deviceId,
    };

MedicationsCompanion medicationFromMap(
        String syncId, Map<String, dynamic> map) =>
    MedicationsCompanion(
      syncId: Value(syncId),
      name: Value(map['name'] as String? ?? ''),
      type: Value(map['type'] as String?),
      schedule: Value(map['schedule'] as String?),
      enabled: Value(map['enabled'] as bool? ?? true),
      updatedAt: Value(updatedAtFromMap(map)),
    );

Map<String, dynamic> analysisSessionToMap(AnalysisSession row) => {
      'uid': row.uid,
      'mediaId': row.mediaId,
      // Stamped so a stored transcript still records what its user was actually
      // told when it started, on whatever device later reads it.
      'consentVersion': row.consentVersion,
      'createdAt': row.createdAt.millisecondsSinceEpoch,
      'updatedAt': row.updatedAt.millisecondsSinceEpoch,
    };

AnalysisSessionsCompanion analysisSessionFromMap(
        String id, Map<String, dynamic> map) =>
    AnalysisSessionsCompanion(
      id: Value(id),
      uid: Value(map['uid'] as String? ?? ''),
      mediaId: Value(map['mediaId'] as String? ?? ''),
      consentVersion: Value((map['consentVersion'] as num?)?.toInt() ?? 0),
      createdAt: Value(createdAtFromMap(map) ?? DateTime.now()),
      updatedAt: Value(updatedAtFromMap(map) ?? DateTime.now()),
    );

Map<String, dynamic> analysisMessageToMap(AnalysisMessage row) => {
      'sessionId': row.sessionId,
      'role': row.role,
      'messageText': row.messageText,
      'createdAt': row.createdAt.millisecondsSinceEpoch,
      // Messages are append-only and never edited, so `createdAt` doubles as
      // the merge field. Sent under both names so the shared
      // `updatedAtFromMap` reader works without a special case.
      'updatedAt': row.createdAt.millisecondsSinceEpoch,
    };

AnalysisMessagesCompanion analysisMessageFromMap(
        String id, Map<String, dynamic> map) =>
    AnalysisMessagesCompanion(
      id: Value(id),
      sessionId: Value(map['sessionId'] as String? ?? ''),
      role: Value(map['role'] as String? ?? 'user'),
      messageText: Value(map['messageText'] as String? ?? ''),
      createdAt: Value(createdAtFromMap(map) ?? DateTime.now()),
    );
