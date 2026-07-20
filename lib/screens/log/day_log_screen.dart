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
    await _formKey.currentState?.save();
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
        title: Text(title, style: const TextStyle(fontSize: 18)),
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
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: FilledButton(onPressed: _save, child: const Text('Save')),
      ),
    );
  }
}
