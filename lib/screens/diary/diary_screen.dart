import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/cycle.dart';
import '../../providers/log_provider.dart';
import '../../services/diary_service.dart';
import '../../widgets/day_entry_sheet.dart';

/// Reads back the notes the user has written, newest first, with search.
///
/// Deliberately carries NO ad banner: personal free-text belongs to the same
/// family as the logging and insights screens, where ads are banned.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The 1-based day within the cycle containing [date], or null if unknown.
  ///
  /// `Cycle.end` is the last BLEEDING day, not the cycle boundary, so a date can
  /// legitimately sit after `end` and still belong to that cycle. Hence: take the
  /// most recent cycle that started on or before [date]. The 60-day ceiling stops
  /// a note written long after the last logged cycle reading as "cycle day 400".
  int? _cycleDay(LogProvider provider, DateTime date) {
    Cycle? containing;
    for (final c in provider.cycles) {
      if (c.start.isAfter(date)) continue;
      if (containing == null || c.start.isAfter(containing.start)) {
        containing = c;
      }
    }
    if (containing == null) return null;
    final day = date.difference(containing.start).inDays + 1;
    return day >= 1 && day <= 60 ? day : null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    final entries = DiaryService.entries(provider.logs, query: _query);
    final df = DateFormat.yMMMEd();

    return Scaffold(
      appBar: AppBar(title: const Text('Diary')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('diary-search'),
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search your notes',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.trim().isEmpty
                            ? 'Notes you add to a day appear here, newest '
                                'first — so you can look back over them.'
                            : 'No notes match that search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final day = _cycleDay(provider, e.date);
                      return ListTile(
                        title: Text(df.format(e.date)),
                        subtitle: Text(
                          e.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: day == null
                            ? null
                            : Text(
                                'Cycle day $day',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                        onTap: () => showDayEntrySheet(context, date: e.date),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
