import 'dart:convert';

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
