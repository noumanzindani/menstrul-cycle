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
    final scheme = Theme.of(context).colorScheme;
    final items = provider.items;
    return Scaffold(
      // Short title: the entry point in Settings carries the fuller
      // "Medications & birth control" label, and that string ellipsizes in a
      // 360dp app bar next to the back arrow.
      appBar: AppBar(title: const Text('Medications')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    // One grouped card rather than a card per row: the list is
                    // short and homogeneous, so a stack of separate cards reads
                    // as more separation than there is.
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 1,
                                indent: 68,
                                endIndent: 12,
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            _MedicationRow(
                              med: items[i],
                              onTap: () => _openEditor(context, items[i]),
                              onToggle: (on) => provider.update(
                                items[i],
                                name: items[i].name,
                                type: items[i].type,
                                schedule:
                                    MedicationSchedule.decode(items[i].schedule),
                                enabled: on,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'LunaTrack only tracks what you tell it and reminds you '
                        '— it gives no dosing advice and checks nothing.',
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

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
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.medication_outlined,
                  size: 34, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('No medications yet',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Add the ones you want to tick off each day — a pill, patch, '
              'injection or supplement. Each can carry a daily reminder.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row inside the grouped list: a soft icon tile, the name, what it is,
/// and — only when one exists — the reminder time on its own quieter line.
/// The switch pauses the reminder without deleting the medication.
class _MedicationRow extends StatelessWidget {
  const _MedicationRow({
    required this.med,
    required this.onTap,
    required this.onToggle,
  });

  final Medication med;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final schedule = MedicationSchedule.decode(med.schedule);
    final reminder = schedule != null && schedule.remind
        ? 'Reminder ${TimeOfDay(hour: schedule.hour, minute: schedule.minute).format(context)}'
        : null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.medication_outlined,
                  size: 22, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    med.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    medicationTypeLabel(med.type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (reminder != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      reminder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(value: med.enabled, onChanged: onToggle),
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
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
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Combined pill, Iron, Vitamin D',
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: scheme.primary, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Type'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kMedicationTypes)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t.key,
                    showCheckmark: false,
                    onSelected: (sel) =>
                        setState(() => _type = sel ? t.key : null),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionLabel('Reminder'),
            const SizedBox(height: 10),
            // Switch and time share one card, so the revealed time row reads as
            // part of the same setting rather than a new one.
            Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text('Daily reminder'),
                    subtitle:
                        const Text('A notification at the same time each day'),
                    value: _remind,
                    onChanged: (v) => setState(() => _remind = v),
                  ),
                  if (_remind) ...[
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Time'),
                      trailing: Text(
                        _time.format(context),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      onTap: _pickTime,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Same honesty as the Reminders screen: a notification here is
            // best-effort, and the app never implies otherwise.
            Text(
              'Reminders are best-effort. Your phone’s battery settings can '
              'delay or drop them.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
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

/// Small uppercase group header — the same section grammar the day log uses.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
