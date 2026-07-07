import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/premium_provider.dart';

/// One-time Premium unlock: removes ads and unlocks extras. Non-consumable,
/// restorable. Safety features are NEVER behind this paywall.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  // Only advertise what Premium actually delivers today. Ad removal is the one
  // gated benefit; the doctor PDF is (and must stay) free — it is a health
  // feature and "never paywall a safety feature" is a guardrail. Themes and
  // backup/restore are not built yet, so listing them would be misleading.
  static const _benefits = [
    ('block', 'Remove all ads'),
    ('favorite', 'Support a private, indie app'),
  ];

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('LunaTrack Premium')),
      body: premium.isPremium
          ? _AlreadyPremium()
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(Icons.workspace_premium,
                    size: 64, color: scheme.primary),
                const SizedBox(height: 12),
                Text('Unlock Premium',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text('One-time purchase. No subscription.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 24),
                for (final (icon, label) in _benefits)
                  ListTile(
                    leading: Icon(_iconFor(icon), color: scheme.primary),
                    title: Text(label),
                    dense: true,
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: premium.storeAvailable
                      ? () => premium.buy()
                      : null,
                  child: Text(premium.storeAvailable
                      ? 'Unlock${premium.price != null ? ' — ${premium.price}' : ''}'
                      : 'Store unavailable'),
                ),
                TextButton(
                  onPressed: () => premium.restore(),
                  child: const Text('Restore purchase'),
                ),
              ],
            ),
    );
  }

  IconData _iconFor(String key) => switch (key) {
        'block' => Icons.block,
        _ => Icons.favorite_outline,
      };
}

class _AlreadyPremium extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text("You're Premium 💜",
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Thank you for supporting LunaTrack.'),
        ],
      ),
    );
  }
}
