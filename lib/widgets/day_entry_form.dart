import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/catalog.dart';
import '../models/enums.dart';
import '../providers/log_provider.dart';

/// The set of selectors for one day. Extracted so it can be hosted both by the
/// full-screen [DayLogScreen] and inline on the calendar. Call
/// [DayEntryFormState.save]/`clear` via a [GlobalKey] from the host, which owns
/// the Save/Clear buttons.
///
/// All tracking lives in the one day-tags JSON blob (see `common/catalog.dart`):
/// plain boolean symptoms, namespaced single-select/flag groups (discharge,
/// vaginal & sexual health, habits — kept out of the doctor PDF by default), and
/// numeric metrics (pain, water, sleep, energy, stress). No schema/migration.
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

/// Numeric metrics rendered as 0..max sliders; 0 means "not logged".
const List<({String label, String key, int max, String suffix})> _metricConfigs = [
  (label: 'Water (glasses)', key: kMetricWater, max: 12, suffix: ''),
  (label: 'Sleep (hours)', key: kMetricSleep, max: 12, suffix: 'h'),
  (label: 'Energy', key: kMetricEnergy, max: 5, suffix: '/5'),
  (label: 'Stress', key: kMetricStress, max: 5, suffix: '/5'),
];

class DayEntryFormState extends State<DayEntryForm> {
  FlowIntensity? _flow;
  final Set<String> _symptoms = {}; // physical + emotional (plain keys)
  String? _mood;
  String? _sex;
  String? _discharge; // cervical-mucus / discharge quality (single-select)
  final Set<String> _vaginal = {};
  final Set<String> _sexualHealth = {};
  final Set<String> _habits = {};
  final Map<String, int> _metrics = {}; // includes pain + the lifestyle metrics
  late final TextEditingController _notes;
  late final TextEditingController _bbt; // basal body temperature (°C)
  String? _opk; // ovulation-test result
  bool _hadExisting = false;

  bool get hasExisting => _hadExisting;

  @override
  void initState() {
    super.initState();
    final existing = context.read<LogProvider>().logForDate(widget.date);
    final tags = existing?.symptoms;
    _hadExisting = existing != null;
    _flow = existing?.flow;
    _symptoms.addAll(decodeSymptoms(tags));
    _mood = existing?.mood;
    _sex = decodeSex(tags);
    _discharge = decodeSingle(tags, kDischargeKeyPrefix);
    _vaginal.addAll(decodeGroup(tags, kVaginalKeyPrefix));
    _sexualHealth.addAll(decodeGroup(tags, kSexualHealthKeyPrefix));
    _habits.addAll(decodeGroup(tags, kHabitKeyPrefix));
    _metrics[kMetricPain] = decodeNumber(tags, kMetricPain)?.round() ?? 0;
    for (final m in _metricConfigs) {
      _metrics[m.key] = decodeNumber(tags, m.key)?.round() ?? 0;
    }
    _notes = TextEditingController(text: existing?.notes ?? '');
    _bbt = TextEditingController(
        text: existing?.bbt != null ? '${existing!.bbt}' : '');
    _opk = existing?.opk;
  }

  @override
  void dispose() {
    _notes.dispose();
    _bbt.dispose();
    super.dispose();
  }

  Future<void> save() {
    final flags = <String>{
      ..._symptoms,
      ..._vaginal,
      ..._sexualHealth,
      ..._habits,
      ?_sex,
      ?_discharge,
    };
    final numbers = <String, num>{
      for (final e in _metrics.entries)
        if (e.value > 0) e.key: e.value,
    };
    return context.read<LogProvider>().saveDay(
          date: widget.date,
          flow: _flow,
          symptomsJson: encodeDayTags(flags: flags, numbers: numbers),
          mood: _mood,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          bbt: double.tryParse(_bbt.text.trim()),
          opk: _opk,
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
        _SectionLabel('Physical symptoms'),
        _FilterChips(
          options: kSymptomOptions,
          isSelected: _symptoms.contains,
          onToggle: (key, sel) => setState(
              () => sel ? _symptoms.add(key) : _symptoms.remove(key)),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Emotional symptoms'),
        _FilterChips(
          options: kEmotionalOptions,
          isSelected: _symptoms.contains,
          onToggle: (key, sel) => setState(
              () => sel ? _symptoms.add(key) : _symptoms.remove(key)),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Mood'),
        _SingleChips(
          options: kMoodOptions,
          selected: _mood,
          onSelect: (key) => setState(() => _mood = key),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Pain'),
        _MetricSlider(
          label: 'Pain level',
          value: _metrics[kMetricPain] ?? 0,
          max: 10,
          suffix: '/10',
          onChanged: (v) => setState(() => _metrics[kMetricPain] = v),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Discharge'),
        _SingleChips(
          options: kDischargeOptions,
          selected: _discharge,
          onSelect: (key) => setState(() => _discharge = key),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Temperature & ovulation tests'),
        TextField(
          controller: _bbt,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Basal body temperature',
            hintText: 'e.g. 36.55',
            suffixText: '°C',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Text('Ovulation test (LH)',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
        const SizedBox(height: 6),
        _SingleChips(
          options: kOpkOptions,
          selected: _opk,
          onSelect: (key) => setState(() => _opk = key),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Vaginal health'),
        _FilterChips(
          options: kVaginalOptions,
          isSelected: _vaginal.contains,
          onToggle: (key, sel) =>
              setState(() => sel ? _vaginal.add(key) : _vaginal.remove(key)),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Sex'),
        _SingleChips(
          options: kSexOptions,
          selected: _sex,
          onSelect: (key) => setState(() => _sex = key),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Sexual health'),
        _FilterChips(
          options: kSexualHealthOptions,
          isSelected: _sexualHealth.contains,
          onToggle: (key, sel) => setState(() =>
              sel ? _sexualHealth.add(key) : _sexualHealth.remove(key)),
        ),
        const SizedBox(height: 20),
        _SectionLabel('Lifestyle'),
        _FilterChips(
          options: kHabitOptions,
          isSelected: _habits.contains,
          onToggle: (key, sel) =>
              setState(() => sel ? _habits.add(key) : _habits.remove(key)),
        ),
        const SizedBox(height: 8),
        for (final m in _metricConfigs)
          _MetricSlider(
            label: m.label,
            value: _metrics[m.key] ?? 0,
            max: m.max,
            suffix: m.suffix,
            onChanged: (v) => setState(() => _metrics[m.key] = v),
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

/// Multi-select chip group over a list of [TrackOption]s.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.options,
    required this.isSelected,
    required this.onToggle,
  });

  final List<TrackOption> options;
  final bool Function(String key) isSelected;
  final void Function(String key, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final o in options)
          FilterChip(
            label: Text(o.label),
            selected: isSelected(o.key),
            onSelected: (sel) => onToggle(o.key, sel),
          ),
      ],
    );
  }
}

/// Single-select chip group; tapping the selected chip again clears it (null).
class _SingleChips extends StatelessWidget {
  const _SingleChips({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<TrackOption> options;
  final String? selected;
  final void Function(String? key) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.label),
            selected: selected == o.key,
            onSelected: (sel) => onSelect(sel ? o.key : null),
          ),
      ],
    );
  }
}

/// A 0..[max] slider for an optional numeric metric; 0 renders as "—" (unset).
class _MetricSlider extends StatelessWidget {
  const _MetricSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.suffix = '',
  });

  final String label;
  final int value;
  final int max;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(
                value == 0 ? '—' : '$value$suffix',
                style: TextStyle(
                  color: value == 0 ? scheme.onSurfaceVariant : scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: max.toDouble(),
            divisions: max,
            label: value == 0 ? 'Not set' : '$value$suffix',
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
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
