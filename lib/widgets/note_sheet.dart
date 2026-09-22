import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/log_provider.dart';

/// Opens a notes-only editor for [date]: the Diary's "Write a note" path.
///
/// A separate sheet rather than [showDayEntrySheet], because Notes is the last
/// section of a long day form, and "write a note" should not start with a
/// scroll past flow, symptoms and metrics. Saving writes ONLY the note
/// ([LogProvider.saveNote]), so the day's other data is never touched.
Future<void> showNoteSheet(BuildContext context, {required DateTime date}) {
  final logProvider = context.read<LogProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    // Routes build from the navigator's context, so the provider is handed in
    // again — the same reason `showDayEntrySheet` re-provides it.
    builder: (_) => ChangeNotifierProvider<LogProvider>.value(
      value: logProvider,
      child: NoteSheet(date: date),
    ),
  );
}

class NoteSheet extends StatefulWidget {
  const NoteSheet({super.key, required this.date});

  final DateTime date;

  @override
  State<NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<NoteSheet> {
  late final TextEditingController _text;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = context.read<LogProvider>().logForDate(widget.date);
    _text = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context
        .read<LogProvider>()
        .saveNote(date: widget.date, notes: _text.text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Lift the sheet above the keyboard, which opens with it (autofocus).
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            DateFormat.yMMMMEEEEd().format(widget.date),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('note-sheet.text'),
            controller: _text,
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Anything you want to remember…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('note-sheet.save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
