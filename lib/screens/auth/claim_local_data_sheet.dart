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
Future<bool?> showClaimLocalDataSheet(
  BuildContext context, {
  required int dayCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => PopScope(
      canPop: false,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              dayCount > 0
                  ? 'Add your existing logs?'
                  : 'Add your existing data?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            // `dayCount == 0` is reachable and is NOT a "nothing to ask"
            // case: the settings document syncs too, and it carries the
            // pregnancy state, so a device with health settings but no logged
            // days still has something to consent to. Saying "0 days logged"
            // there would misdescribe exactly the data being offered up.
            Text(
              dayCount > 0
                  ? 'You have $dayCount days logged on this device. Add them '
                      'to this account so they sync to your other devices? If '
                      'you skip, they stay on this device and nothing is '
                      'deleted.'
                  : 'You have health settings saved on this device. Add them '
                      'to this account so they sync to your other devices? If '
                      'you skip, they stay on this device and nothing is '
                      'deleted.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('claim.upload'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add to my account'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('claim.keepLocal'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep on this device only'),
            ),
          ],
        ),
      ),
    ),
  );
}
