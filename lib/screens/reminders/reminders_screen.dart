import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/enums.dart';
import '../../models/prediction.dart';
import '../../providers/reminder_provider.dart';
import '../../services/notification_service.dart';

/// Toggle and configure the three smart reminders. Enabling one requests the
/// system notification permission, then reschedules against the current
/// prediction.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  Future<void> _setEnabled(
    BuildContext context,
    ReminderType type,
    bool enabled, {
    int? daysBefore,
  }) async {
    final provider = context.read<ReminderProvider>();
    final prediction = context.read<PredictionResult>();
    final messenger = ScaffoldMessenger.of(context);

    if (enabled) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Enable notifications in system settings to use reminders.'),
        ));
        return;
      }
    }
    await provider.setReminder(type, enabled: enabled, daysBefore: daysBefore);
    await provider.reschedule(prediction);
  }

  Future<void> _pickTime(BuildContext context, ReminderType type) async {
    final provider = context.read<ReminderProvider>();
    final prediction = context.read<PredictionResult>();
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: provider.hourOf(type), minute: provider.minuteOf(type)),
    );
    if (picked == null) return;
    await provider.setReminder(
      type,
      enabled: provider.isEnabled(type),
      hour: picked.hour,
      minute: picked.minute,
    );
    await provider.reschedule(prediction);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReminderProvider>();

    String timeLabel(ReminderType t) =>
        TimeOfDay(hour: provider.hourOf(t), minute: provider.minuteOf(t))
            .format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _ReminderCard(
            icon: Icons.water_drop_outlined,
            title: 'Period reminder',
            subtitle: 'A heads-up before your period is expected',
            enabled: provider.isEnabled(ReminderType.periodSoon),
            onChanged: (v) => _setEnabled(context, ReminderType.periodSoon, v),
            details: [
              ListTile(
                dense: true,
                title: const Text('Days before'),
                trailing: _DaysBeforeStepper(
                  value: provider.daysBefore(ReminderType.periodSoon),
                  onChanged: (d) => _setEnabled(
                    context,
                    ReminderType.periodSoon,
                    true,
                    daysBefore: d,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                title: const Text('Time'),
                trailing: Text(timeLabel(ReminderType.periodSoon)),
                onTap: () => _pickTime(context, ReminderType.periodSoon),
              ),
            ],
          ),
          _ReminderCard(
            icon: Icons.eco_outlined,
            title: 'Fertile window reminder',
            subtitle: 'When your estimated fertile window begins',
            enabled: provider.isEnabled(ReminderType.fertileWindow),
            onChanged: (v) =>
                _setEnabled(context, ReminderType.fertileWindow, v),
            details: [
              ListTile(
                dense: true,
                title: const Text('Time'),
                trailing: Text(timeLabel(ReminderType.fertileWindow)),
                onTap: () => _pickTime(context, ReminderType.fertileWindow),
              ),
            ],
          ),
          _ReminderCard(
            icon: Icons.edit_calendar_outlined,
            title: 'Daily log reminder',
            subtitle: 'A gentle daily nudge to log how you feel',
            enabled: provider.isEnabled(ReminderType.logNudge),
            onChanged: (v) => _setEnabled(context, ReminderType.logNudge, v),
            details: [
              ListTile(
                dense: true,
                title: const Text('Time'),
                trailing: Text(timeLabel(ReminderType.logNudge)),
                onTap: () => _pickTime(context, ReminderType.logNudge),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
    required this.details,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(icon),
            title: Text(title),
            subtitle: Text(subtitle),
            value: enabled,
            onChanged: onChanged,
          ),
          if (enabled) ...details,
        ],
      ),
    );
  }
}

class _DaysBeforeStepper extends StatelessWidget {
  const _DaysBeforeStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < 7 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
