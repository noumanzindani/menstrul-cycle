import '../common/date_utils.dart';
import '../db/database.dart';

/// One day's diary note.
class DiaryEntry {
  const DiaryEntry({required this.date, required this.note});
  final DateTime date;
  final String note;
}

/// Reads back the notes users already write per day. Pure: operates on the logs
/// LogProvider already holds in memory, so there is no query and no new column.
class DiaryService {
  const DiaryService._();

  /// Days with a non-blank note, NEWEST FIRST, optionally filtered by a
  /// case-insensitive substring match. Matches the NOTE TEXT ONLY — never
  /// symptoms, moods or dates.
  static List<DiaryEntry> entries(
    List<DailyLog> logs, {
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    final out = <DiaryEntry>[];
    for (final l in logs) {
      final note = l.notes?.trim();
      if (note == null || note.isEmpty) continue;
      if (needle.isNotEmpty && !note.toLowerCase().contains(needle)) continue;
      out.add(DiaryEntry(date: dateOnly(l.date), note: note));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }
}
