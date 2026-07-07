import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_provider.dart';
import '../../services/notification_service.dart';
import '../../services/pregnancy_service.dart';

/// Start, view, and end pregnancy tracking. Deliberately plain and non-medical:
/// weeks + an estimated due date, and a neutral one-step exit. No celebratory
/// UI, no fetal/medical content, no ads (a loss must never be re-triggered).
class PregnancyScreen extends StatelessWidget {
  const PregnancyScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 28)),
      firstDate: now.subtract(const Duration(days: 300)),
      lastDate: now,
      helpText: 'First day of your last period',
    );
    if (picked != null) {
      await settings.startPregnancy(picked);
      // A pregnant user shouldn't get "period expected soon" — cancel the
      // one-shot period/fertility reminders that may already be scheduled.
      await NotificationService.cancel(NotificationService.idPeriodSoon);
      await NotificationService.cancel(NotificationService.idFertile);
    }
  }

  Future<void> _end(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End pregnancy tracking?'),
        content: const Text(
          'This turns off pregnancy tracking and removes its data from this '
          'device. Your cycle history is not affected.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End tracking')),
        ],
      ),
    );
    if (confirmed != true) return;
    await settings.endPregnancy();
    messenger.showSnackBar(
      const SnackBar(content: Text('Pregnancy tracking ended.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final lmp = settings.pregnancyStartDate;

    return Scaffold(
      appBar: AppBar(title: const Text('Pregnancy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: settings.isPregnant && lmp != null
            ? _statusView(context, lmp)
            : _startView(context),
      ),
    );
  }

  List<Widget> _startView(BuildContext context) {
    return [
      Text(
        'Switch to pregnancy tracking',
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'While this is on, LunaTrack pauses period and fertility predictions and '
        'shows how far along you are, with an estimated due date. You can turn it '
        'off at any time.',
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () => _start(context),
        child: const Text('Start pregnancy tracking'),
      ),
    ];
  }

  List<Widget> _statusView(BuildContext context, DateTime lmp) {
    final ga = PregnancyService.gestationalAge(lmp);
    final due = PregnancyService.estimatedDueDate(lmp);
    final tri = PregnancyService.trimester(lmp);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${ga.weeks} weeks${ga.days > 0 ? ' ${ga.days} days' : ''}',
                style: text.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text('Trimester $tri',
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Text('Estimated due date',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              Text(DateFormat.yMMMMd().format(due), style: text.titleMedium),
              const SizedBox(height: 8),
              Text(
                "An estimate from your last period (Naegele's rule) — not medical "
                'advice.',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      OutlinedButton(
        onPressed: () => _end(context),
        child: const Text('End pregnancy tracking'),
      ),
    ];
  }
}
