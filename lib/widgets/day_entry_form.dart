import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/catalog.dart';
import '../models/enums.dart';
import '../providers/log_provider.dart';

/// The set of selectors for one day (flow, period-ended, symptoms, mood, sex,
/// notes). Extracted so it can be hosted both by the full-screen [DayLogScreen]
/// and inline on the calendar. Call [DayEntryFormState.save]/`clear` via a
/// [GlobalKey] from the host, which owns the Save/Clear buttons.
///
/// [shrinkWrap] makes it embeddable inside another scroll view (calendar);
/// standalone it scrolls itself.
class DayEntryForm extends StatefulWidget {
  const DayEntryForm({super.key, required this.date, this.shrinkWrap = false});

  final DateTime date;
  final bool shrinkWrap;

  @override
  DayEntryFormState createState() => DayEntryFormState();
}

class DayEntryFormState extends State<DayEntryForm> {
  FlowIntensity? _flow;
  final Set<String> _symptoms = {};
  String? _mood;
  String? _sex;
  late final TextEditingController _notes;
  bool _hadExisting = false;

  bool get hasExisting => _hadExisting;

  @override
  void initState() {
    super.initState();
    final existing = context.read<LogProvider>().logForDate(widget.date);
    _hadExisting = existing != null;
    _flow = existing?.flow;
    _symptoms.addAll(decodeSymptoms(existing?.symptoms));
    _mood = existing?.mood;
    _sex = decodeSex(existing?.symptoms);
    _notes = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> save() {
    return context.read<LogProvider>().saveDay(
          date: widget.date,
          flow: _flow,
          symptomsJson: encodeSymptoms({..._symptoms, ?_sex}),
          mood: _mood,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
  }

  Future<void> clear() => context.read<LogProvider>().clearDay(widget.date);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      shrinkWrap: widget.shrinkWrap,
      physics:
          widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        _SectionLabel('Flow'),
        Wrap(
          spacing: 8,
          children: [
            for (final f in FlowIntensity.values)
              if (f != FlowIntensity.none)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _flow == f,
                  onSelected: (sel) => setState(() => _flow = sel ? f : null),
                ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Period ended today'),
          subtitle: const Text('Marks today as no bleeding'),
          value: _flow == FlowIntensity.none,
          onChanged: (on) =>
              setState(() => _flow = on ? FlowIntensity.none : null),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Symptoms'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final o in kSymptomOptions)
              FilterChip(
                label: Text(o.label),
                selected: _symptoms.contains(o.key),
                onSelected: (sel) => setState(() {
                  sel ? _symptoms.add(o.key) : _symptoms.remove(o.key);
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel('Mood'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final o in kMoodOptions)
              ChoiceChip(
                label: Text(o.label),
                selected: _mood == o.key,
                onSelected: (sel) => setState(() => _mood = sel ? o.key : null),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel('Sex'),
        Wrap(
          spacing: 8,
          children: [
            for (final o in kSexOptions)
              ChoiceChip(
                label: Text(o.label),
                selected: _sex == o.key,
                onSelected: (sel) => setState(() => _sex = sel ? o.key : null),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionLabel('Notes'),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Anything else about today…',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
