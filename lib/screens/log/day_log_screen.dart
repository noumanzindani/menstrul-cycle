import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/log_provider.dart';
import '../../widgets/day_entry_form.dart';

/// Full-screen host for editing one day. The field selectors live in the shared
/// [DayEntryForm] (also used inline on the calendar); this screen just supplies
/// the app bar, a pinned Save button, and the "clear this day" action.
class DayLogScreen extends StatefulWidget {
  const DayLogScreen({super.key, required this.date});

  final DateTime date;

  @override
  State<DayLogScreen> createState() => _DayLogScreenState();
}

class _DayLogScreenState extends State<DayLogScreen> {
  final _formKey = GlobalKey<DayEntryFormState>();
  late final bool _hadExisting;

  @override
  void initState() {
    super.initState();
    _hadExisting = context.read<LogProvider>().logForDate(widget.date) != null;
  }

  Future<void> _save() async {
    final saved = await _formKey.currentState?.save() ?? false;
    if (!saved) return; // invalid input; the form is showing the error
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await _formKey.currentState?.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = DateFormat.yMMMMEEEEd().format(widget.date);
    return Scaffold(
      appBar: AppBar(
        // A close X, not a back arrow, and matching [DayEntrySheet]: this screen
        // is an editor over one day, so dismissing it is "close", not "go back
        // a level". Same pop either way.
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Text(
          title,
          // The date can be long in some locales; ellipsize rather than let the
          // title collide with the trailing action.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_hadExisting)
            IconButton(
              tooltip: 'Clear this day',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
            ),
        ],
      ),
      body: DayEntryForm(
        key: _formKey,
        date: widget.date,
        medications: enabledMedChips(context),
        categories: visibleCategories(context),
      ),
      // Pinned footer: a hairline separates it from the scrolling form so the
      // Save target reads as chrome rather than as the end of the content —
      // same treatment as the sheet host. One full-width FilledButton, never a
      // Row of them (`filledButtonTheme` demands infinite width).
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ),
      ),
    );
  }
}
