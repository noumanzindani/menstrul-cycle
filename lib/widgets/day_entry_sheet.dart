import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/log_provider.dart';
import '../services/cycle_check_in.dart';
import 'day_entry_form.dart';
import 'period_check_in_banner.dart';

/// Opens [date]'s log form in a modal bottom sheet — the "combined calendar +
/// entry" surface, also reused by the diary.
///
/// Re-provides [LogProvider] into the sheet route because the route is built
/// from the navigator's context, which in tests sits ABOVE the pumped providers.
///
/// [checkIn] is decided by the CALLER, where a `PredictionResult` is in scope;
/// this route deliberately does not re-provide one.
Future<void> showDayEntrySheet(
  BuildContext context, {
  required DateTime date,
  CheckInPrompt checkIn = CheckInPrompt.none,
}) {
  final logProvider = context.read<LogProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<LogProvider>.value(
      value: logProvider,
      child: DayEntrySheet(date: date, checkIn: checkIn),
    ),
  );
}

/// Bottom-sheet host for the selected day's log form — the "combined calendar +
/// entry" surface. Hosts the shared [DayEntryForm] and owns its Save/Clear
/// buttons; a fixed header/footer with the form scrolling between them. Save and
/// Clear pop the sheet.
class DayEntrySheet extends StatefulWidget {
  const DayEntrySheet({
    super.key,
    required this.date,
    this.checkIn = CheckInPrompt.none,
  });

  final DateTime date;

  /// Contextual back-fill prompt for this date (period didn't start / has ended).
  final CheckInPrompt checkIn;

  @override
  State<DayEntrySheet> createState() => _DayEntrySheetState();
}

class _DayEntrySheetState extends State<DayEntrySheet> {
  final _formKey = GlobalKey<DayEntryFormState>();

  Future<void> _save() async {
    final saved = await _formKey.currentState?.save() ?? false;
    if (!saved) return; // keep the sheet open so the error is visible
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clear() async {
    await _formKey.currentState?.clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = DateFormat.yMMMMEEEEd().format(widget.date);
    final hadExisting =
        context.read<LogProvider>().logForDate(widget.date) != null;
    // Cap the sheet so the calendar stays partly visible behind it. The content
    // is a Scaffold (mirroring DayLogScreen) — its layout gives the form and
    // the Save button bounded, tight constraints and absorbs the intrinsic-width
    // query that otherwise makes a bare button blow up to infinite width inside
    // a modal sheet.
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(title, style: const TextStyle(fontSize: 18)),
          actions: [
            if (hadExisting)
              IconButton(
                tooltip: 'Clear this day',
                icon: const Icon(Icons.delete_outline),
                onPressed: _clear,
              ),
          ],
        ),
        body: Column(
          children: [
            // Contextual express lane: on a predicted-start / run-to-length date,
            // one tap records a confirmed no-bleeding day and closes the sheet.
            PeriodCheckInBanner(
              prompt: widget.checkIn,
              date: widget.date,
              onCompleted: () {
                if (mounted) Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: DayEntryForm(
                key: _formKey,
                date: widget.date,
                medications: enabledMedChips(context),
                categories: visibleCategories(context),
              ),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
      ),
    );
  }
}
