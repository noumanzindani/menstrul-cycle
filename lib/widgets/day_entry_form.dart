import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common/catalog.dart';
import '../common/tracking_categories.dart';
import '../models/enums.dart';
import '../providers/log_provider.dart';
import '../providers/medication_provider.dart';
import '../providers/settings_provider.dart';

/// The set of selectors for one day. Extracted so it can be hosted both by the
/// full-screen [DayLogScreen] and inline on the calendar. Call
/// [DayEntryFormState.save]/`clear` via a [GlobalKey] from the host, which owns
/// the Save/Clear buttons.
///
/// All tracking lives in the one day-tags JSON blob (see `common/catalog.dart`):
/// plain boolean symptoms, namespaced single-select/flag groups (discharge,
/// vaginal & sexual health, habits — kept out of the doctor PDF by default), and
/// numeric metrics (pain, water, sleep, energy, stress, and weight in canonical
/// kilograms). No schema/migration.
///
/// [shrinkWrap] makes it embeddable inside another scroll view (calendar);
/// standalone it scrolls itself.
class DayEntryForm extends StatefulWidget {
  const DayEntryForm({
    super.key,
    required this.date,
    this.shrinkWrap = false,
    this.medications = const [],
    this.categories,
  });

  final DateTime date;
  final bool shrinkWrap;
  final List<MedChip> medications;

  /// Which sections to RENDER. NULL means "no opinion" and shows everything, so
  /// the form stays pumpable without a [SettingsProvider]; an EMPTY set means
  /// "explicitly nothing". Gating NEVER affects decode or encode — see
  /// [DayEntryFormState.save].
  final Set<String>? categories;

  @override
  DayEntryFormState createState() => DayEntryFormState();
}

/// One configured medication offered as an intake chip in the day editor.
class MedChip {
  const MedChip(this.id, this.name);
  final int id;
  final String name;
}

/// Enabled medications as intake chips, or empty when the provider is absent.
/// The nullable lookup returns null instead of throwing, which keeps the form
/// and its hosts pumpable in tests that wire no [MedicationProvider].
List<MedChip> enabledMedChips(BuildContext context) {
  final meds = context.watch<MedicationProvider?>();
  if (meds == null) return const [];
  return [
    for (final m in meds.items)
      if (m.enabled) MedChip(m.id, m.name),
  ];
}

/// Every category id — the fail-open value used when [DayEntryForm.categories]
/// is null.
final Set<String> kAllCategoryIds = {
  for (final c in kTrackingCategories) c.id,
};

/// Categories the user has switched on, or ALL of them when no
/// [SettingsProvider] is in scope. Deliberately fails OPEN: unlike
/// [enabledMedChips], an empty set here would blank every section for the
/// screens that pump this form without settings wired.
///
/// Named `visibleCategories`, not `enabledCategories`, because
/// [SettingsProvider.enabledCategories] already owns that name and the two have
/// deliberately different fallbacks.
Set<String> visibleCategories(BuildContext context) {
  final settings = context.watch<SettingsProvider?>();
  if (settings == null || !settings.loaded) return kAllCategoryIds;
  return settings.enabledCategories;
}

/// Numeric metrics rendered as 0..max sliders; 0 means "not logged". NEVER
/// filter this list — it drives the initState decode as well as the render, so
/// dropping an entry here would erase that metric on the next save.
const List<({String label, String key, int max, String suffix})> _metricConfigs = [
  (label: 'Water (glasses)', key: kMetricWater, max: 12, suffix: ''),
  (label: 'Sleep (hours)', key: kMetricSleep, max: 12, suffix: 'h'),
  (label: 'Energy', key: kMetricEnergy, max: 5, suffix: '/5'),
  (label: 'Stress', key: kMetricStress, max: 5, suffix: '/5'),
  (label: 'Sleep quality', key: kMetricSleepQuality, max: 5, suffix: '/5'),
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
  final Set<String> _medications = {}; // med_<id> keys
  final Set<String> _urine = {};
  final Set<String> _digestion = {};
  final Set<String> _skin = {};
  final Map<String, int> _metrics = {}; // includes pain + the lifestyle metrics
  late final TextEditingController _notes;
  late final TextEditingController _bbt; // basal body temperature (°C)
  late final TextEditingController _weight; // in the DISPLAY unit, not kg
  String? _weightError;
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
    _medications.addAll(decodeGroup(tags, kMedicationKeyPrefix));
    // Decoded unconditionally, even for hidden categories: save() rebuilds the
    // whole blob, so a group left un-decoded here would be erased on save.
    _urine.addAll(decodeGroup(tags, kUrineKeyPrefix));
    _digestion.addAll(decodeGroup(tags, kDigestionKeyPrefix));
    _skin.addAll(decodeGroup(tags, kSkinKeyPrefix));
    _metrics[kMetricPain] = decodeNumber(tags, kMetricPain)?.round() ?? 0;
    for (final m in _metricConfigs) {
      _metrics[m.key] = decodeNumber(tags, m.key)?.round() ?? 0;
    }
    _notes = TextEditingController(text: existing?.notes ?? '');
    _bbt = TextEditingController(
        text: existing?.bbt != null ? '${existing!.bbt}' : '');
    // Decoded unconditionally too (see the note above): the stored value is
    // canonical kg, shown in whatever unit was chosen when the editor opened.
    final unitAtOpen =
        context.read<SettingsProvider?>()?.weightUnit ?? kWeightUnitKg;
    final existingKg = decodeNumber(tags, kMetricWeight)?.toDouble();
    _weight = TextEditingController(
      text: existingKg == null || existingKg <= 0
          ? ''
          : formatWeightFromKg(existingKg, unitAtOpen),
    );
    _opk = existing?.opk;
  }

  @override
  void dispose() {
    _notes.dispose();
    _bbt.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Saves the day. Returns false WITHOUT writing when the typed weight is
  /// invalid — an inline error is then showing, so hosts must not pop.
  Future<bool> save() async {
    final unit =
        context.read<SettingsProvider?>()?.weightUnit ?? kWeightUnitKg;
    final raw = _weight.text.trim();
    double? weightKg;
    if (raw.isNotEmpty) {
      weightKg = parseWeightToKg(raw, unit);
      if (weightKg == null) {
        final lo = formatWeightFromKg(kMinWeightKg, unit);
        final hi = formatWeightFromKg(kMaxWeightKg, unit);
        setState(
            () => _weightError = 'Enter a weight between $lo and $hi $unit');
        return false;
      }
    }
    if (_weightError != null) setState(() => _weightError = null);

    final flags = <String>{
      ..._symptoms,
      ..._vaginal,
      ..._sexualHealth,
      ..._habits,
      ..._medications,
      ..._urine,
      ..._digestion,
      ..._skin,
      ?_sex,
      ?_discharge,
    };
    final numbers = <String, num>{
      for (final e in _metrics.entries)
        if (e.value > 0) e.key: e.value,
      // Written unconditionally, even when the Weight category is hidden: the
      // blob is fully REPLACED on save, so omitting it would erase the value.
      kMetricWeight: ?weightKg,
    };
    await context.read<LogProvider>().saveDay(
          date: widget.date,
          flow: _flow,
          symptomsJson: encodeDayTags(flags: flags, numbers: numbers),
          mood: _mood,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          bbt: double.tryParse(_bbt.text.trim()),
          opk: _opk,
        );
    return true;
  }

  Future<void> clear() => context.read<LogProvider>().clearDay(widget.date);

  /// Sections to render. Resolving null here (rather than in the constructor)
  /// keeps the default out of the const-expression rules while preserving the
  /// null-vs-empty distinction: null = show everything, {} = show nothing.
  Set<String> get _cats => widget.categories ?? kAllCategoryIds;

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
        if (_cats.contains(kCatPhysicalSymptoms)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Physical symptoms'),
          _FilterChips(
            options: kSymptomOptions,
            isSelected: _symptoms.contains,
            onToggle: (key, sel) => setState(
                () => sel ? _symptoms.add(key) : _symptoms.remove(key)),
          ),
        ],
        if (_cats.contains(kCatEmotional)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Emotional symptoms'),
          _FilterChips(
            options: kEmotionalOptions,
            isSelected: _symptoms.contains,
            onToggle: (key, sel) => setState(
                () => sel ? _symptoms.add(key) : _symptoms.remove(key)),
          ),
        ],
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
        if (_cats.contains(kCatDischarge)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Discharge'),
          _SingleChips(
            options: kDischargeOptions,
            selected: _discharge,
            onSelect: (key) => setState(() => _discharge = key),
          ),
        ],
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
        if (_cats.contains(kCatVaginal)) ...[
          const SizedBox(height: 20),
          // Matches the registry label so Settings and the day editor agree.
          _SectionLabel('Vulva & vagina'),
          _FilterChips(
            options: kVaginalOptions,
            isSelected: _vaginal.contains,
            onToggle: (key, sel) =>
                setState(() => sel ? _vaginal.add(key) : _vaginal.remove(key)),
          ),
        ],
        if (_cats.contains(kCatSex)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Sex'),
          _SingleChips(
            options: kSexOptions,
            selected: _sex,
            onSelect: (key) => setState(() => _sex = key),
          ),
        ],
        if (_cats.contains(kCatSexualHealth)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Sexual health'),
          _FilterChips(
            options: kSexualHealthOptions,
            isSelected: _sexualHealth.contains,
            onToggle: (key, sel) => setState(() =>
                sel ? _sexualHealth.add(key) : _sexualHealth.remove(key)),
          ),
        ],
        if (_cats.contains(kCatLifestyle)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Lifestyle'),
          _FilterChips(
            options: kHabitOptions,
            isSelected: _habits.contains,
            onToggle: (key, sel) =>
                setState(() => sel ? _habits.add(key) : _habits.remove(key)),
          ),
        ],
        if (_cats.contains(kCatMedications) &&
            widget.medications.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('Medications'),
          _FilterChips(
            options: [
              for (final m in widget.medications)
                TrackOption('$kMedicationKeyPrefix${m.id}', m.name),
            ],
            isSelected: _medications.contains,
            onToggle: (key, sel) => setState(
                () => sel ? _medications.add(key) : _medications.remove(key)),
          ),
        ],
        // Structurally identical groups, rendered from one loop rather than
        // three hand-copied blocks.
        for (final g in [
          (kCatUrine, 'Urine', kUrineOptions, _urine),
          (kCatDigestion, 'Digestion', kDigestionOptions, _digestion),
          (kCatSkin, 'Skin & hair', kSkinOptions, _skin),
        ])
          if (_cats.contains(g.$1)) ...[
            const SizedBox(height: 20),
            _SectionLabel(g.$2),
            _FilterChips(
              options: g.$3,
              isSelected: g.$4.contains,
              onToggle: (key, sel) =>
                  setState(() => sel ? g.$4.add(key) : g.$4.remove(key)),
            ),
          ],
        if (_cats.contains(kCatWellbeing) ||
            _cats.contains(kCatSleepQuality)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Wellbeing'),
        ],
        // Filtered HERE ONLY. _metricConfigs itself stays whole so initState
        // still decodes every metric — see the note on that list.
        for (final m in _metricConfigs)
          if (_cats.contains(m.key == kMetricSleepQuality
              ? kCatSleepQuality
              : kCatWellbeing))
            _MetricSlider(
              label: m.label,
              value: _metrics[m.key] ?? 0,
              max: m.max,
              suffix: m.suffix,
              onChanged: (v) => setState(() => _metrics[m.key] = v),
            ),
        if (_cats.contains(kCatWeight)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Weight'),
          TextField(
            key: const Key('weight-field'),
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Weight',
              suffixText: context.watch<SettingsProvider?>()?.weightUnit ??
                  kWeightUnitKg,
              errorText: _weightError,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
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
