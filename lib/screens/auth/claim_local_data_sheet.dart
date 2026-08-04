import 'package:flutter/material.dart';

/// Asks whether the logs already on this device should be added to the account
/// that just signed in.
///
/// Declining must NEVER delete anything — the rows stay local and untouched.
/// Returns true to upload, false to keep local only, null if dismissed.
Future<bool?> showClaimLocalDataSheet(
  BuildContext context, {
  required int dayCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add your existing logs?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'You have $dayCount days logged on this device. Add them to this '
            'account so they sync to your other devices? If you skip, they '
            'stay on this device and nothing is deleted.',
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
  );
}
