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

    final text = Theme.of(context).textTheme;

    // An inset card, not a full-bleed strip: it sits above a form whose fields
    // are inset by the same 16dp, and a bled edge reads as a system warning
    // bar. This is a question, not an alert.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.event_note_outlined,
                    size: 20, color: scheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Chip-weight, never a filled button: `filledButtonTheme` demands
            // infinite width, and this express lane must not outrank the form's
            // own Save below it.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: () => _mark(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: scheme.onSecondaryContainer,
                  side: BorderSide(
                      color:
                          scheme.onSecondaryContainer.withValues(alpha: 0.28)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(action),
              ),
            ),
          ],
        ),
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
