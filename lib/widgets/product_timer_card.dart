import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product_session.dart';
import '../models/product_type.dart';
import '../providers/product_session_provider.dart';
import '../services/product_timer_plan.dart';

/// How far past the target the card starts admitting the reminder may never
/// have arrived. Comfortably clear of the inexact-alarm drift we expect, so the
/// disclosure means "something went wrong", not "alarms are approximate".
const Duration _delayDisclosureAfter = Duration(minutes: 30);

/// The live card for an in-progress product-change session.
///
/// This card — not the notification — is the feature's primary surface. Every
/// alarm in this app is deliberately inexact, and an OEM battery manager can
/// drop one entirely, so the app cannot promise delivery. What it can promise
/// is that the truth is here whenever the user opens it.
///
/// [clock] exists because `tester.pump(Duration)` advances fake timers but not
/// `DateTime.now()`, so a real-clock ticker would be untestable.
class ProductTimerCard extends StatelessWidget {
  const ProductTimerCard({super.key, required this.session, this.clock});

  final ProductSession session;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _TickingBody(session: session, clock: clock ?? DateTime.now),
      ),
    );
  }
}

/// Owns the only repeating timer in the app.
///
/// Kept as a private child rather than folded into [ProductTimerCard] so a tick
/// dirties this element alone — Home's ListView and every sibling card are
/// untouched.
class _TickingBody extends StatefulWidget {
  const _TickingBody({required this.session, required this.clock});

  final ProductSession session;
  final DateTime Function() clock;

  @override
  State<_TickingBody> createState() => _TickingBodyState();
}

class _TickingBodyState extends State<_TickingBody>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleTick();
  }

  @override
  void didUpdateWidget(covariant _TickingBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A restart resets the minute boundary; without this the display would be
    // stale by up to 59 seconds after every "Changed".
    if (oldWidget.session.insertedAt != widget.session.insertedAt) {
      _scheduleTick();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Elapsed time is recomputed from the stored timestamp, so returning from
    // the background (or from behind the app lock, where TickerMode freezes
    // animations) needs a rebuild, not a reconciliation.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Ticks once a minute, aligned to the elapsed-minute boundary.
  ///
  /// A plain `Timer.periodic(60s)` would fire 60 seconds after mount rather
  /// than when the displayed minute actually changes, leaving the number stale
  /// by up to 59 seconds. One second would be 60x the wakeups — including
  /// behind the app lock, where a `Timer` (unlike a `Ticker`) keeps firing and
  /// an offstage subtree still lays out — for a display that only ever shows
  /// minutes.
  void _scheduleTick() {
    _timer?.cancel();
    final elapsed = widget.session.elapsedAt(widget.clock());
    final toBoundary = 60 - (elapsed.inSeconds % 60);
    _timer = Timer(Duration(seconds: toBoundary), () {
      if (!mounted) return;
      setState(() {});
      _scheduleTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final onCard = scheme.onTertiaryContainer;

    final now = widget.clock();
    final session = widget.session;
    final elapsed = session.elapsedAt(now);
    final pastTarget = session.isPastTargetAt(now);
    final mayHaveMissed = session.overrunAt(now) > _delayDisclosureAfter;
    final capNote = session.product.capNote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 20, color: onCard),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session.product.label,
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: onCard),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Counts UP from the logged time. Never time remaining, and never a
        // progress bar — both would draw a deadline the app cannot locate, on
        // a value it does not know (absorbency, flow, individual risk).
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: 'Logged at ${formatClock(session.insertedAt)} · '),
              TextSpan(
                text: '${formatElapsed(elapsed)} ago',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: pastTarget ? scheme.error : onCard,
                ),
              ),
              // "past the Nh you set" — the target is the user's, not the
              // app's, so the app is never the one calling it late.
              if (pastTarget)
                TextSpan(
                    text: ' — past the ${formatElapsed(session.interval)} '
                        'you set.'),
            ],
          ),
          style: text.bodyMedium?.copyWith(color: onCard),
        ),
        if (mayHaveMissed) ...[
          const SizedBox(height: 6),
          Text(
            'This reminder may not have arrived on time.',
            style: text.bodySmall?.copyWith(color: onCard),
          ),
        ],
        if (pastTarget && capNote != null) ...[
          const SizedBox(height: 6),
          Text(capNote, style: text.bodySmall?.copyWith(color: onCard)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    context.read<ProductSessionProvider>().changed(),
                child: const Text('Changed'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    context.read<ProductSessionProvider>().removed(),
                child: const Text('Removed'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
