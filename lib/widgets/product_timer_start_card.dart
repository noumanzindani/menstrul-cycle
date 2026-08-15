import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product_type.dart';
import '../providers/product_session_provider.dart';
import '../services/product_timer_plan.dart';

/// Smallest adjustable step, and the floor. Half an hour is finer than any
/// real wear decision and coarse enough that the stepper never needs a keyboard.
const Duration _step = Duration(minutes: 30);

/// What the app says instead of promising delivery. Android may delay this
/// reminder, and an OEM battery manager may drop it entirely — so the honest
/// move is to say so where the user first relies on it, not to engineer around
/// a guarantee the platform will not give.
const String kBestEffortNotice =
    'Reminders may arrive late, or not at all — phone battery settings can '
    'block them.';

/// Points clinical authority away from LunaTrack and at the box the product
/// came in. Shown on every duration picker.
const String kFollowInstructions =
    'Follow the instructions that came with your product.';

/// The idle state: start a timer in one tap.
///
/// Home only renders this on days with logged bleeding, and nothing is ever
/// scheduled until a chip is tapped — so the feature is opt-in by action rather
/// than by a setting the user would have to go looking for.
class ProductTimerStartCard extends StatelessWidget {
  const ProductTimerStartCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Change reminder',
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Start a timer when you put one in.',
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final product in ProductType.values)
                  ActionChip(
                    label: Text(product.label),
                    onPressed: () =>
                        context.read<ProductSessionProvider>().start(product),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => _openDurationSheet(context),
                child: const Text('Set a different time'),
              ),
            ),
            Text(kBestEffortNotice,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  void _openDurationSheet(BuildContext context) {
    final provider = context.read<ProductSessionProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<ProductSessionProvider>.value(
        value: provider,
        child: const _DurationSheet(),
      ),
    );
  }
}

/// Pick a product and a duration, then start.
///
/// The chosen duration lives on the session, not in settings. Persisting a
/// per-product preference would mean a schema migration, and "Changed" already
/// carries the duration forward for as long as the session chain lasts — which
/// is the span the user actually cares about.
class _DurationSheet extends StatefulWidget {
  const _DurationSheet();

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  ProductType _product = ProductType.pad;
  late Duration _interval = _product.defaultDuration;

  void _select(ProductType product) {
    setState(() {
      _product = product;
      // Snap back to the product's own default, then clamp — a 12h cup
      // duration must not survive a switch to tampons.
      _interval = product.defaultDuration;
    });
  }

  /// The cap is enforced here as a refusal to go higher rather than a silent
  /// rewrite at save time: the button simply stops, with the attributed reason
  /// already on screen next to it.
  void _adjust(Duration delta) {
    final next = _interval + delta;
    if (next < _step || next > _product.maxDuration) return;
    setState(() => _interval = next);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final capNote = _product.capNote;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change reminder',
                style:
                    text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final product in ProductType.values)
                  ChoiceChip(
                    label: Text(product.label),
                    selected: _product == product,
                    onSelected: (_) => _select(product),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: () => _adjust(-_step),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatElapsed(_interval),
                    textAlign: TextAlign.center,
                    style: text.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 20),
                IconButton.filledTonal(
                  onPressed: () => _adjust(_step),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (capNote != null) ...[
              Text(capNote,
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
            ],
            Text(kFollowInstructions,
                style:
                    text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                await context
                    .read<ProductSessionProvider>()
                    .start(_product, interval: _interval);
                navigator.pop();
              },
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }
}
