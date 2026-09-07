import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/premium_provider.dart';

/// One-time Premium unlock: removes ads. Non-consumable, restorable. Tracking
/// features are NEVER behind this paywall.
///
/// Deliberately styled as a calm statement rather than a sales page: a close
/// affordance instead of an app bar, one honest sentence, a plain price row,
/// and one action. **No urgency, no countdown, no crossed-out price, no
/// feature-comparison table** implying tracking is gated — those are the things
/// this screen must never grow.
class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final premium = context.watch<PremiumProvider>();

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Expanded(
              child: premium.isPremium
                  ? const _AlreadyPremium()
                  : _Offer(premium: premium),
            ),
          ],
        ),
      ),
    );
  }
}

class _Offer extends StatelessWidget {
  const _Offer({required this.premium});

  final PremiumProvider premium;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final price = premium.price;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(
              children: [
                const SizedBox(height: 16),
                const _RingMark(),
                const SizedBox(height: 28),
                Text(
                  'LunaTrack Premium',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    "Removes ads. That's it. Every tracking feature is free and "
                    'always will be.',
                    textAlign: TextAlign.center,
                    style: text.bodyLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 28),
                // Price row: a plain statement of what is charged, once.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'One-time purchase',
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (price != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.outline,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        price,
                        style: text.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            children: [
              FilledButton(
                onPressed: premium.storeAvailable ? () => premium.buy() : null,
                child: Text(
                  premium.storeAvailable
                      ? (price != null ? 'Buy once — $price' : 'Buy once')
                      : 'Store unavailable',
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => premium.restore(),
                child: const Text('Restore purchase'),
              ),
              const SizedBox(height: 8),
              Text(
                'No subscription. No recurring charge.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }
}

/// The app's ring mark, drawn as a dashed circle of soft-pink ticks around a
/// heart. Purely decorative — it is not the month ring and carries no data.
class _RingMark extends StatelessWidget {
  const _RingMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(112),
            painter: _DashedRingPainter(color: scheme.primary),
          ),
          Icon(Icons.favorite_outline, size: 40, color: scheme.primary),
        ],
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 4,
    );
    const segments = 24;
    const sweep = 6.283185307179586 / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _AlreadyPremium extends StatelessWidget {
  const _AlreadyPremium();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              "You're Premium",
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Ads are off. Thank you for supporting LunaTrack.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
