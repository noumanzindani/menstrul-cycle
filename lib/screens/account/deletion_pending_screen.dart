import 'package:flutter/material.dart';

import '../../services/account_deletion_service.dart';

/// Told, at sign-in, that this account is scheduled for deletion — with the
/// way out on the same screen.
///
/// `AppGate` shows this AHEAD of onboarding. That placement is the whole point:
/// `deleteAllData()` resets `onboardingComplete`, so a user who requested
/// deletion and later signs back in otherwise walks the full first-run flow for
/// an account that is queued for erasure, and learns nothing about it unless
/// they happen to open Settings → Account.
///
/// All three actions are non-destructive. "Cancel deletion" withdraws the
/// request and nothing is deleted; "Sign out" leaves the request standing and,
/// per the local-first rule, never touches local data; "Continue to LunaTrack"
/// dismisses the notice for this session only.
///
/// That third action is not optional politeness. Without it this screen is a
/// wall for the whole 30-day grace window whose only ways past are cancelling
/// the deletion or signing out of an app that requires an account — and on a
/// SECOND device, which was never wiped and still holds the full history, that
/// is a month-long outage of a health tracker nobody asked for. The request is
/// about the server copy.
class DeletionPendingScreen extends StatefulWidget {
  const DeletionPendingScreen({
    super.key,
    required this.request,
    required this.onCancel,
    required this.onSignOut,
    required this.onDismiss,
  });

  final DeletionRequest request;

  /// Withdraws the request. Throwing is the failure signal — this screen turns
  /// it into a retryable message rather than dismissing itself, because
  /// dismissing on a failed cancel would leave the user believing the deletion
  /// is off when it is still scheduled.
  final Future<void> Function() onCancel;

  final VoidCallback onSignOut;

  /// Dismisses the notice and lets the user into the app. Session-only — the
  /// notice is shown again on the next launch.
  final VoidCallback onDismiss;

  @override
  State<DeletionPendingScreen> createState() => _DeletionPendingScreenState();
}

class _DeletionPendingScreenState extends State<DeletionPendingScreen> {
  bool _busy = false;
  bool _failed = false;

  static String get _windowLabel =>
      '${AccountDeletionService.graceWindow.inDays} days';

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onCancel();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final purgeAfter = widget.request.purgeAfter;
    // A marker with no readable deadline still counts as pending (see
    // `DeletionRequest`). Say what is certainly true rather than invent a date.
    final when = purgeAfter == null
        ? 'within $_windowLabel of your request'
        : 'on ${MaterialLocalizations.of(context).formatFullDate(purgeAfter)}';

    return Scaffold(
      key: const Key('gate.deletionPending'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule, size: 40, color: scheme.error),
                const SizedBox(height: 16),
                Text(
                  'Account deletion pending',
                  style: text.headlineSmall?.copyWith(color: scheme.error),
                ),
                const SizedBox(height: 16),
                Text(
                  'You asked us to delete this account. Your account and the '
                  'copy of your logs on our server are scheduled to be '
                  'permanently deleted $when.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Cloud sync stays off until then, so nothing on this device '
                  'is being backed up.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Cancel the request and nothing is deleted — your account is '
                  'restored and your logs sync back to this device.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'The logs already on this device are untouched, and you can '
                  'keep using LunaTrack while the request stands.',
                  style: text.bodyMedium,
                ),
                if (_failed) ...[
                  const SizedBox(height: 16),
                  Text(
                    "Couldn't cancel the deletion. Check your connection and "
                    'try again.',
                    key: const Key('gate.deletionCancelFailed'),
                    style: text.bodyMedium?.copyWith(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('gate.cancelDeletion'),
                  onPressed: _busy ? null : _cancel,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cancel deletion'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('gate.dismissDeletionNotice'),
                  onPressed: _busy ? null : widget.onDismiss,
                  child: const Text('Continue to LunaTrack'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('gate.signOut'),
                  onPressed: _busy ? null : widget.onSignOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
