import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../models/enums.dart';
import '../../models/prediction.dart';
import '../../providers/log_provider.dart';
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
    final logs = context.read<LogProvider>().logs;
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
    await provider.reschedule(prediction, logs);
  }

  Future<void> _pickTime(BuildContext context, ReminderType type) async {
    final provider = context.read<ReminderProvider>();
    final prediction = context.read<PredictionResult>();
    final logs = context.read<LogProvider>().logs;
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
    await provider.reschedule(prediction, logs);
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
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Custom reminders',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                TextButton.icon(
                  onPressed: () => _addCustom(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          if (provider.customReminders.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Add your own daily reminders — water, medication, '
                  'anything you want a nudge for.'),
            ),
          for (final r in provider.customReminders)
            _CustomReminderCard(
              reminder: r,
              timeLabel:
                  TimeOfDay(hour: r.hour, minute: r.minute).format(context),
              onToggle: (on) => _toggleCustom(context, r, on),
              onTap: () => _editCustom(context, r),
            ),
        ],
      ),
    );
  }

  Future<void> _addCustom(BuildContext context) async {
    final provider = context.read<ReminderProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CustomReminderEditor(provider: provider),
    );
  }

  Future<void> _editCustom(BuildContext context, Reminder reminder) async {
    final provider = context.read<ReminderProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _CustomReminderEditor(provider: provider, existing: reminder),
    );
  }

  Future<void> _toggleCustom(BuildContext context, Reminder r, bool on) async {
    final provider = context.read<ReminderProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (on) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        messenger.showSnackBar(const SnackBar(
          content:
              Text('Enable notifications in system settings to use reminders.'),
        ));
        return;
      }
    }
    await provider.updateCustom(
      r,
      title: r.title ?? 'Reminder',
      hour: r.hour,
      minute: r.minute,
      enabled: on,
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

class _CustomReminderCard extends StatelessWidget {
  const _CustomReminderCard({
    required this.reminder,
    required this.timeLabel,
    required this.onToggle,
    required this.onTap,
  });

  final Reminder reminder;
  final String timeLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.alarm_outlined),
        title: Text(reminder.title ?? 'Reminder'),
        subtitle: Text('Every day at $timeLabel'),
        onTap: onTap,
        trailing: Switch(value: reminder.enabled, onChanged: onToggle),
      ),
    );
  }
}

/// Add/edit sheet for a custom reminder. Owns its Save button; deletes (when
/// editing) from the app bar.
class _CustomReminderEditor extends StatefulWidget {
  const _CustomReminderEditor({required this.provider, this.existing});

  final ReminderProvider provider;
  final Reminder? existing;

  @override
  State<_CustomReminderEditor> createState() => _CustomReminderEditorState();
}

class _CustomReminderEditorState extends State<_CustomReminderEditor> {
  late final TextEditingController _title;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    if (e != null) _time = TimeOfDay(hour: e.hour, minute: e.minute);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the reminder a name.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final granted = await NotificationService.requestPermission();
    if (!granted) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Enable notifications in system settings for this to fire.'),
      ));
    }
    if (_isEdit) {
      await widget.provider.updateCustom(
        widget.existing!,
        title: title,
        hour: _time.hour,
        minute: _time.minute,
        enabled: widget.existing!.enabled,
      );
    } else {
      await widget.provider
          .addCustom(title: title, hour: _time.hour, minute: _time.minute);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.provider.removeCustom(widget.existing!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.6;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_isEdit ? 'Edit reminder' : 'Add reminder'),
          actions: [
            if (_isEdit)
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Drink water',
                border: OutlineInputBorder(),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              trailing: Text(_time.format(context)),
              onTap: _pickTime,
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
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
