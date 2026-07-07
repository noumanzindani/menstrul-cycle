import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../models/medication.dart';
import '../../providers/medication_provider.dart';
import '../../services/notification_service.dart';

/// Track medications and birth control, each with an optional daily reminder.
/// Pure tracking + reminders — no dosing advice and no drug-interaction checks.
class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

  Future<void> _openEditor(BuildContext context, Medication? existing) async {
    final provider = context.read<MedicationProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MedicationEditor(provider: provider, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MedicationProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Medications & birth control')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : provider.items.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    for (final med in provider.items)
                      _MedicationCard(
                        med: med,
                        onTap: () => _openEditor(context, med),
                        onToggle: (on) => provider.update(
                          med,
                          name: med.name,
                          type: med.type,
                          schedule: MedicationSchedule.decode(med.schedule),
                          enabled: on,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medication_outlined,
                size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No medications yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Track a pill, patch, injection, or supplement — and set a daily '
              'reminder so you never miss one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.med,
    required this.onTap,
    required this.onToggle,
  });

  final Medication med;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final schedule = MedicationSchedule.decode(med.schedule);
    final parts = <String>[medicationTypeLabel(med.type)];
    if (schedule != null && schedule.remind) {
      parts.add(
        'Reminder ${TimeOfDay(hour: schedule.hour, minute: schedule.minute).format(context)}',
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.medication_outlined),
        title: Text(med.name),
        subtitle: Text(parts.join(' · ')),
        onTap: onTap,
        trailing: Switch(value: med.enabled, onChanged: onToggle),
      ),
    );
  }
}

/// Add/edit sheet. Owns its Save button; deletes (when editing) from the app bar.
class _MedicationEditor extends StatefulWidget {
  const _MedicationEditor({required this.provider, this.existing});

  final MedicationProvider provider;
  final Medication? existing;

  @override
  State<_MedicationEditor> createState() => _MedicationEditorState();
}

class _MedicationEditorState extends State<_MedicationEditor> {
  late final TextEditingController _name;
  String? _type;
  bool _remind = false;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _type = e?.type;
    final sched = MedicationSchedule.decode(e?.schedule);
    if (sched != null) {
      _remind = sched.remind;
      _time = TimeOfDay(hour: sched.hour, minute: sched.minute);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give the medication a name.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    var schedule = _remind
        ? MedicationSchedule(hour: _time.hour, minute: _time.minute)
        : null;

    // Only touch the OS when a reminder is requested; if it's denied, still
    // save the medication but without the (non-functional) reminder.
    if (schedule != null) {
      final granted = await NotificationService.requestPermission();
      if (!granted) {
        schedule = null;
        messenger.showSnackBar(const SnackBar(
          content: Text('Saved without a reminder — enable notifications to use one.'),
        ));
      }
    }

    if (_isEdit) {
      await widget.provider.update(
        widget.existing!,
        name: name,
        type: _type,
        schedule: schedule,
        enabled: widget.existing!.enabled,
      );
    } else {
      await widget.provider.add(name: name, type: _type, schedule: schedule);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this medication?'),
        content: Text('“${widget.existing!.name}” and its reminder will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.provider.remove(widget.existing!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.9;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_isEdit ? 'Edit medication' : 'Add medication'),
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
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Combined pill, Iron, Vitamin D',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Type', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in kMedicationTypes)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t.key,
                    onSelected: (sel) =>
                        setState(() => _type = sel ? t.key : null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Daily reminder'),
              subtitle: const Text('A notification at the same time each day'),
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind)
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
