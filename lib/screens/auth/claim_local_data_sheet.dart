import 'package:flutter/material.dart';

/// Asks whether the logs already on this device should be added to the account
/// that just signed in.
///
/// Declining must NEVER delete anything — the rows stay local and untouched.
/// Returns true to upload, false to keep local only, null if dismissed.
///
/// `isDismissible: false` + `enableDrag: false` only block taps on the barrier
/// and drags; neither blocks the Android system back button, which pops the
/// route and returns null. The [PopScope] does block it, so the two buttons are
/// the only ways out — but callers must still treat a null result as "no
/// answer yet", never as a decline.
///
/// No drag handle, deliberately: the sheet cannot be dragged or dismissed, and
/// a handle is the affordance that says it can. (The mock draws one; that is
/// the one place its chrome disagrees with what this sheet does.)
Future<bool?> showClaimLocalDataSheet(
  BuildContext context, {
  required int dayCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    // The sheet sizes to its content instead of the default 9/16-of-screen
    // cap, and the content scrolls inside it. Both halves matter: this is a
    // consent question whose two answers must never be the part that falls off
    // the bottom, and it has to survive a large text scale on a short screen.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      final theme = Theme.of(context);
      return PopScope(
        canPop: false,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Use the data already on this device?',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                // `dayCount == 0` is reachable and is NOT a "nothing to ask"
                // case: the settings document syncs too, and it carries the
                // pregnancy state, so a device with health settings but no
                // logged days still has something to consent to. Saying
                // "0 days logged" there would misdescribe exactly the data
                // being offered up.
                Text(
                  dayCount > 0
                      ? 'You have $dayCount days logged on this device, from '
                          'before you signed in.'
                      : 'You have health settings saved on this device, from '
                          'before you signed in.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'Adding them puts them in your account, so they reach your '
                  'other devices. If you skip, they stay on this device, '
                  'nothing is deleted, and nothing syncs.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                // Stacked, never a row: `filledButtonTheme` sets
                // `minimumSize: Size.fromHeight(52)`, i.e. infinite width.
                //
                // Filled + OUTLINED, not filled + text. This is a consent
                // decision, and the two answers are equally legitimate; a
                // borderless decline reads as the throwaway option next to a
                // solid "yes". The labels stay as they are — they describe
                // what each answer does to THIS device's data, which is the
                // thing being consented to.
                FilledButton(
                  key: const Key('claim.upload'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Add to my account'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('claim.keepLocal'),
                  // Matches `filledButtonTheme`'s 52dp height and 16dp radius
                  // by hand: the app theme styles filled buttons only, and an
                  // equal-weight choice has to be equally sized.
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Keep on this device only'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
