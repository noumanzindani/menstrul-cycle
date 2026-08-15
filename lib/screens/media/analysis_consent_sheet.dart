import 'package:flutter/material.dart';

/// Asks once, before any photo is sent out for description.
///
/// ## The copy is the disclosure
///
/// This sheet is the only place a user is told that a photo leaves both their
/// device AND their own account, to a company that is not the app. Everything
/// here is what the code does today: it names Google, says the photo is sent
/// rather than "processed", says LunaTrack does not keep the answer, and does
/// not promise anything about what Google does with it — because the app has no
/// authority over that and cannot honestly speak for it.
///
/// GUARDRAIL: no "safe", "private", "secure", "encrypted" or "protected"
/// anywhere in this file. The bytes are unencrypted in Cloud Storage already,
/// and this feature sends them somewhere further. `media_guardrails_test.dart`
/// scans for those words across `lib/screens/media/`.
///
/// Returns `true` only on an explicit Allow. A dismissal, a back gesture and
/// "Not now" all return null/false and persist NOTHING — an unanswered question
/// is not a "no" that needs recording, it is simply unanswered, and the sheet
/// asks again next time.
Future<bool?> showAnalysisConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _AnalysisConsentSheet(),
  );
}

class _AnalysisConsentSheet extends StatelessWidget {
  const _AnalysisConsentSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Describe photos?', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(
              'To describe a photo, LunaTrack sends it to Google, an automatic '
              'image-recognition service outside LunaTrack. This happens only '
              'when you tap Describe on a photo — never on its own, and never '
              'to your other photos.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'LunaTrack does not keep the description. It is shown to you and '
              'discarded when you close the photo.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'It describes what is in a picture. It is not a medical opinion '
              'and cannot tell you what something is or what to do about it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'You can turn this off again in Settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Both buttons are Expanded, and that is load-bearing rather than
            // cosmetic. `filledButtonTheme` sets `minimumSize:
            // Size.fromHeight(52)`, which is `Size(double.infinity, 52)` — the
            // app's full-width CTA convention. Inside a Row an infinite minimum
            // width overflows the line, at which point MainAxisAlignment stops
            // applying and the trailing child is laid out past the right edge
            // and clipped. Device-found 2026-08-13 in a release build: Allow
            // was not on screen at all, so consent could not be granted from
            // this sheet. Expanded supplies a tight width and is what the other
            // two Row+FilledButton sites in this app already do.
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('analysis-consent-allow'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
