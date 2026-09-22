import 'package:flutter/material.dart';

import '../../widgets/entrance.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/cycle.dart';
import '../../providers/log_provider.dart';
import '../../services/diary_service.dart';
import '../../widgets/day_entry_sheet.dart';
import '../../widgets/note_sheet.dart';

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

  /// Picks a day (today by default), then opens the notes-only sheet for it.
  /// Future days are not offered: a diary looks back, and a note dated
  /// tomorrow would also create a log for a day that has not happened.
  Future<void> _writeNote() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2000),
      lastDate: today,
      helpText: 'Note for which day?',
    );
    if (date == null || !mounted) return;
    await showNoteSheet(context, date: date);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    final entries = DiaryService.entries(provider.logs, query: _query);
    final df = DateFormat.yMMMEd();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Diary')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('diary-write-note'),
        onPressed: _writeNote,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write a note'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              key: const Key('diary-search'),
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              // A soft filled pill, not an outlined box: search is a quiet
              // affordance over the notes, not a form field to fill in.
              decoration: InputDecoration(
                hintText: 'Search your notes',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: scheme.primary),
                ),
              ),
            ),
          ),
          Expanded(
            // "Nothing written yet" and "not read yet" are different answers,
            // and `provider.logs` is empty in both. Without this branch the
            // diary spends the read window telling a user with a full diary
            // that notes they add "appear here" -- a confident claim it has
            // not earned, and the reason an empty diary reads as a broken one.
            child: provider.loading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? _EmptyState(searching: _query.trim().isNotEmpty)
                    : EntranceGroup(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: entries.length,
                          itemBuilder: (context, i) {
                            final e = entries[i];
                            return EntranceItem(
                              index: i,
                              child: _DiaryCard(
                                date: df.format(e.date),
                                note: e.note,
                                cycleDay: _cycleDay(provider, e.date),
                                onTap: () =>
                                    showDayEntrySheet(context, date: e.date),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// One note, as a card: the date and its cycle-day tag on one line, the note
/// itself beneath in three lines of quieter type.
class _DiaryCard extends StatelessWidget {
  const _DiaryCard({
    required this.date,
    required this.note,
    required this.cycleDay,
    required this.onTap,
  });

  final String date;
  final String note;
  final int? cycleDay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                // Top-aligned so the tag stays put if a long date wraps.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      date,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (cycleDay != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text(
                        'Day $cycleDay',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                note,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                searching ? Icons.search_off : Icons.edit_note,
                size: 32,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              searching
                  ? 'No notes match that search.'
                  : 'Notes you add to a day appear here, newest '
                      'first — so you can look back over them. Tap '
                      '"Write a note" to start.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
