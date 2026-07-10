import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/enums.dart';
import '../providers/log_provider.dart';
import '../services/cycle_check_in.dart';

/// A contextual strip shown atop the calendar day-sheet when the tapped date is
/// a predicted period start ([CheckInPrompt.didItStart]) or a period that has
/// run to its usual length ([CheckInPrompt.hasItEnded]).
///
/// The single action records a confirmed no-bleeding day (`flow = none`) for
/// that date — preserving anything already logged — then fires [onCompleted]
/// (the sheet closes). It is the express lane; the form's "Period ended today"
/// toggle remains the detailed path. Period timing only — no fertility framing.
class PeriodCheckInBanner extends StatelessWidget {
  const PeriodCheckInBanner({
    super.key,
    required this.prompt,
    required this.date,
    this.onCompleted,
  });

  final CheckInPrompt prompt;
  final DateTime date;
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context) {
    if (prompt == CheckInPrompt.none) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final started = prompt == CheckInPrompt.didItStart;
    final message = started
        ? 'Your period was expected around now.'
        : 'This period has run to its usual length.';
    final action = started ? "Didn't start" : 'Mark ended here';

    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.event_note_outlined,
              size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
            ),
          ),
          TextButton(
            onPressed: () => _mark(context),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  /// Marks [date] as a confirmed no-bleeding day, keeping any symptoms/mood/etc.
  Future<void> _mark(BuildContext context) async {
    final log = context.read<LogProvider>();
    final existing = log.logForDate(date);
    await log.saveDay(
      date: date,
      flow: FlowIntensity.none,
      symptomsJson: existing?.symptoms ?? '{}',
      mood: existing?.mood,
      notes: existing?.notes,
      bbt: existing?.bbt,
      opk: existing?.opk,
    );
    onCompleted?.call();
  }
}
