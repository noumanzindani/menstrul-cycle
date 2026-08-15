import 'package:flutter/material.dart';

/// Ambient notice that this build has no usable Firebase app right now — see
/// `services/firebase_availability.dart`'s doc comment for the single fact
/// this is downstream of.
///
/// Shown in exactly two places, both gated on that same [FirebaseAvailability]
/// fact and never on anything re-derived from it:
///
///  * [SignInScreen]'s "Continue without syncing" hatch — the copy explaining
///    why the hatch exists.
///  * The persistent banner `AppGate` renders over the shell (and onboarding)
///    for the length of a local-only session, so the reduced-functionality
///    state is never silent. See `AppGate`'s `_localOnly` doc comment for why
///    that session cannot outlive the current process.
///
/// Modelled directly on `widgets/disclaimer_banner.dart`'s shape (a rounded
/// `surfaceContainerHighest` strip with a leading icon) rather than inventing
/// a second visual language for a banner.
class CloudSyncUnavailableBanner extends StatelessWidget {
  const CloudSyncUnavailableBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('cloudSyncUnavailable.banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Cloud sync isn't available on this device right now. Your "
              'logs stay private and saved on this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
