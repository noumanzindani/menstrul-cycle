# Per-day Medication Intake + Adherence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user log which medications they took each day, surface those in the per-cycle Cycle Overview, and show a descriptive per-medication "days logged this cycle" adherence view on Insights — closing the last Clue "Complete Cycle Overview" gap.

**Architecture:** Per-day intake rides in the existing `DailyLogs.symptoms` JSON as `med_<id>` keys (migration-free, exactly like `habit_`/`sex_`). Pure services (`CycleOverviewService`, new `MedicationAdherenceService`) tally these against derived cycles; UI reuses existing chip/bar widgets. No schema change, no new dependency.

**Tech Stack:** Flutter, `provider` (ChangeNotifier), `drift` (SQLite, on-device), `fl_chart` (already present — not needed here). Tests use `AppDatabase.forTesting(NativeDatabase.memory())`.

## Global Constraints

- **Migration-free:** no new DB column, no `schemaVersion` bump. Intake = `med_<id>` key in `DailyLogs.symptoms` JSON.
- **Stable keys:** `med_<id>` uses the `Medications` row id; never key on name/type.
- **No false precision:** adherence is a *count of days logged*, never a percentage or an assumed-daily ratio.
- **No new dependency** (global CLAUDE.md: ask before adding one — none is needed here).
- **TDD:** every behavior gets a failing test first (RED → GREEN → REFACTOR). Keep `flutter analyze` clean and `flutter test` green.
- **Conventional Commits** (`feat:` / `test:` / `refactor:`).
- **Tolerant composition:** new Insights widgets must not hard-`!` on optional providers/theme — the Insights screen is deliberately pumpable without prediction/settings providers and without full theme.
- Run all commands from `/Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track`.

---

### Task 1: Reserve and decode the `med_` tag prefix

**Files:**
- Modify: `lib/common/catalog.dart` (add constant near line 60; add to `kReservedTagPrefixes` at line 64)
- Test: `test/medication_tag_test.dart` (create)

**Interfaces:**
- Consumes: existing `decodeSymptoms(String?)`, `decodeGroup(String?, String)`, `encodeDayTags({Set<String> flags})` from `catalog.dart`.
- Produces: `const String kMedicationKeyPrefix = 'med_';` — used by all later tasks.

- [ ] **Step 1: Write the failing test**

```dart
// test/medication_tag_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

void main() {
  test('med_ keys are reserved (excluded from symptom chips) and group-decodable',
      () {
    final json = encodeDayTags(flags: {'cramps', 'med_3', 'med_7'});

    // Not surfaced as a symptom.
    expect(decodeSymptoms(json), contains('cramps'));
    expect(decodeSymptoms(json), isNot(contains('med_3')));

    // Retrievable as its own group.
    expect(decodeGroup(json, kMedicationKeyPrefix), {'med_3', 'med_7'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/medication_tag_test.dart`
Expected: FAIL — `kMedicationKeyPrefix` is undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

In `lib/common/catalog.dart`, add the constant alongside the other prefixes (after `kHabitKeyPrefix`, ~line 60):

```dart
const String kMedicationKeyPrefix = 'med_'; // per-day medication intake
```

Add it to `kReservedTagPrefixes` (the list at ~line 64):

```dart
const List<String> kReservedTagPrefixes = [
  kSexKeyPrefix,
  kDischargeKeyPrefix,
  kVaginalKeyPrefix,
  kSexualHealthKeyPrefix,
  kHabitKeyPrefix,
  kMedicationKeyPrefix,
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/medication_tag_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/common/catalog.dart test/medication_tag_test.dart
git commit -m "feat: reserve med_ tag prefix for per-day medication intake"
```

---

### Task 2: Tally medications in `CycleOverview`

**Files:**
- Modify: `lib/models/cycle_overview.dart` (add `medications` field)
- Modify: `lib/services/cycle_overview_service.dart` (add `medNames` param + tally)
- Test: `test/cycle_overview_test.dart` (extend — add one test)

**Interfaces:**
- Consumes: `kMedicationKeyPrefix` (Task 1); `decodeGroup`; existing `_rank` in the service; `Cycle`, `DailyLog`.
- Produces:
  - `CycleOverview.medications` → `List<LabeledCount>`.
  - New signature: `CycleOverviewService.summarize(Cycle cycle, List<DailyLog> logs, {Map<int, String> medNames = const {}})`.

- [ ] **Step 1: Write the failing test**

Append to `test/cycle_overview_test.dart` (inside its existing `main()`):

```dart
  test('tallies medication days, mapping id to name with orphan fallback',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = DailyLogRepository(db);
    // A 3-day period → one cycle starting Jan 1.
    for (final d in [1, 2, 3]) {
      await repo.upsert(
        date: DateTime(2026, 1, d),
        flow: FlowIntensity.medium,
        // med 5 taken all 3 days; med 9 (deleted → no name) taken 1 day.
        symptomsJson: encodeDayTags(
            flags: d == 1 ? {'med_5', 'med_9'} : {'med_5'}),
      );
    }
    final logs = await repo.getAll();
    final cycles = CycleCalculator.computeCycles(logs);

    final overview = CycleOverviewService.summarize(
      cycles.single, logs,
      medNames: {5: 'Vitamin D'},
    );

    expect(overview.medications, hasLength(2));
    // Ranked by day-count desc: Vitamin D (3) before the orphan (1).
    expect(overview.medications.first.label, 'Vitamin D');
    expect(overview.medications.first.count, 3);
    expect(overview.medications.last.label, 'Medication'); // orphan fallback
    expect(overview.medications.last.count, 1);

    await db.close();
  });
```

Ensure the file's imports include (add any missing):
`package:drift/native.dart`, `package:menstrul_track/db/database.dart`, `package:menstrul_track/data/daily_log_repository.dart`, `package:menstrul_track/models/enums.dart`, `package:menstrul_track/common/catalog.dart`, `package:menstrul_track/services/cycle_calculator.dart`, `package:menstrul_track/services/cycle_overview_service.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cycle_overview_test.dart`
Expected: FAIL — `summarize` has no `medNames` param / `CycleOverview` has no `medications`.

- [ ] **Step 3: Write minimal implementation**

In `lib/models/cycle_overview.dart`, add to the `CycleOverview` constructor and fields (required, with a `const []` default at construction sites):

```dart
    required this.medications,
```
```dart
  /// Per-medication day-counts for this cycle (empty if none logged). Labels are
  /// resolved from the medication catalog; an orphaned id (deleted med) falls
  /// back to "Medication".
  final List<LabeledCount> medications;
```

In `lib/services/cycle_overview_service.dart`:

Change the signature:
```dart
  static CycleOverview summarize(
    Cycle cycle,
    List<DailyLog> logs, {
    Map<int, String> medNames = const {},
  }) {
```

Add a tally map next to the others (`final medications = <String, int>{};` alongside `lifestyle`), and inside the per-log loop (after the `kHabitKeyPrefix` block):

```dart
      for (final key in decodeGroup(l.symptoms, kMedicationKeyPrefix)) {
        medications[key] = (medications[key] ?? 0) + 1;
      }
```

Add to the returned `CycleOverview(...)`:

```dart
      medications: _rank(medications, (key) {
        final id = int.tryParse(key.substring(kMedicationKeyPrefix.length));
        return (id != null ? medNames[id] : null) ?? 'Medication';
      }),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/cycle_overview_test.dart`
Expected: PASS. Then `flutter analyze` — fix any `CycleOverview(...)` construction site now missing `medications:` (the screen test in Task 3 and any existing constructor call; add `medications: const []` there).

- [ ] **Step 5: Commit**

```bash
git add lib/models/cycle_overview.dart lib/services/cycle_overview_service.dart test/cycle_overview_test.dart
git commit -m "feat: tally per-cycle medication days in CycleOverview"
```

---

### Task 3: Render the "Medications" section on the Cycle Overview screen

**Files:**
- Modify: `lib/screens/insights/cycle_overview_screen.dart` (add a `_Section` before Notes)
- Test: `test/cycle_overview_screen_test.dart` (extend the existing `CycleOverview` literal + assertion)

**Interfaces:**
- Consumes: `CycleOverview.medications` (Task 2); existing `_Section`, `_Counts`, `LabeledCount`.
- Produces: a visible "Medications" section, gated on `o.medications.isNotEmpty`.

- [ ] **Step 1: Write the failing test**

In `test/cycle_overview_screen_test.dart`, add `medications:` to the existing `CycleOverview(...)` literal and assert the section renders:

```dart
      medications: const [LabeledCount('Vitamin D', 3)],
```
Add to the header loop list (`'Bleeding', 'Symptoms', ...`) the entry `'Medications'`, and after the existing chip assertions:
```dart
    expect(find.text('Vitamin D'), findsOneWidget);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/cycle_overview_screen_test.dart`
Expected: FAIL — no "Medications" text found (section not rendered yet). (If it instead fails to compile because other tests construct `CycleOverview` without `medications`, add `medications: const []` to those first.)

- [ ] **Step 3: Write minimal implementation**

In `lib/screens/insights/cycle_overview_screen.dart`, insert before the `if (o.notesCount > 0)` block:

```dart
          if (o.medications.isNotEmpty)
            _Section(title: 'Medications', child: _Counts(items: o.medications)),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/cycle_overview_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/insights/cycle_overview_screen.dart test/cycle_overview_screen_test.dart
git commit -m "feat: show Medications section on cycle overview screen"
```

---

### Task 4: Medication chip group in `DayEntryForm`

**Files:**
- Modify: `lib/widgets/day_entry_form.dart` (add `MedChip` type, `medications` param, `_medications` set, section, save/initState wiring)
- Test: `test/day_entry_form_medications_test.dart` (create)

**Interfaces:**
- Consumes: `kMedicationKeyPrefix`, `decodeGroup` (Task 1); existing `_FilterChips`, `TrackOption`, `LogProvider`, `encodeDayTags`.
- Produces:
  - `class MedChip { final int id; final String name; const MedChip(this.id, this.name); }` (top-level in `day_entry_form.dart`).
  - `DayEntryForm({..., List<MedChip> medications = const []})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/day_entry_form_medications_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  late LogProvider logs;
  final date = DateTime(2026, 3, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    await logs.load();
  });
  tearDown(() => db.close());

  Widget wrap(GlobalKey<DayEntryFormState> key) =>
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(
          home: Scaffold(
            body: DayEntryForm(
              key: key,
              date: date,
              medications: const [MedChip(5, 'Vitamin D')],
            ),
          ),
        ),
      );

  testWidgets('toggling a medication chip writes med_<id> on save',
      (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(key));
    await tester.pumpAndSettle();

    // The chip is shown by name.
    expect(find.text('Vitamin D'), findsOneWidget);

    await tester.tap(find.text('Vitamin D'));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    final saved = logs.logForDate(date);
    expect(decodeGroup(saved?.symptoms, kMedicationKeyPrefix), {'med_5'});
  });

  testWidgets('no medications configured → no Medications section',
      (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(ChangeNotifierProvider<LogProvider>.value(
      value: logs,
      child: MaterialApp(
        home: Scaffold(body: DayEntryForm(key: key, date: date)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Medications'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/day_entry_form_medications_test.dart`
Expected: FAIL — `MedChip` / `medications:` param undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

In `lib/widgets/day_entry_form.dart`:

Add the value type at top level (near the other small types):
```dart
/// One configured medication offered as an intake chip in the day editor.
class MedChip {
  const MedChip(this.id, this.name);
  final int id;
  final String name;
}
```

Add the constructor param:
```dart
  const DayEntryForm({
    super.key,
    required this.date,
    this.shrinkWrap = false,
    this.medications = const [],
  });

  final DateTime date;
  final bool shrinkWrap;
  final List<MedChip> medications;
```

Add the state field (next to `_habits`):
```dart
  final Set<String> _medications = {}; // med_<id> keys
```

Seed it in `initState` (after the `_habits` line):
```dart
    _medications.addAll(decodeGroup(tags, kMedicationKeyPrefix));
```

Fold into `save()`'s `flags` set (add to the set literal alongside `..._habits`):
```dart
      ..._medications,
```

Render the section in `build`, right after the Lifestyle `_FilterChips` block (before the metric sliders), gated on a non-empty list:
```dart
        if (widget.medications.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionLabel('Medications'),
          _FilterChips(
            options: [
              for (final m in widget.medications)
                TrackOption('${kMedicationKeyPrefix}${m.id}', m.name),
            ],
            isSelected: _medications.contains,
            onToggle: (key, sel) => setState(
                () => sel ? _medications.add(key) : _medications.remove(key)),
          ),
        ],
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/day_entry_form_medications_test.dart`
Expected: PASS (both tests). Then `flutter analyze` — clean.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/day_entry_form.dart test/day_entry_form_medications_test.dart
git commit -m "feat: log medication intake via chips in the day editor"
```

---

### Task 5: Wire callers to supply the medication list

**Files:**
- Modify: `lib/screens/calendar/calendar_screen.dart:226` (the `DayEntryForm(...)` in `_DayEntrySheet`)
- Modify: `lib/screens/log/day_log_screen.dart:55` (the `DayEntryForm(...)`)
- Modify: `lib/screens/insights/insights_screen.dart` (`_CycleHistory` → pass `medNames` into `summarize`)
- Test: `test/day_log_screen_test.dart` (extend — assert med chip appears when a med is configured)

**Interfaces:**
- Consumes: `MedChip` (Task 4); `MedicationProvider.items` (`List<Medication>`, each `.id`, `.name`, `.enabled`); new `summarize(..., medNames:)` (Task 2).
- Produces: enabled meds flow from `MedicationProvider` into the form; `medNames` flows into cycle-history overviews.

- [ ] **Step 1: Write the failing test**

Extend `test/day_log_screen_test.dart`. Its harness pumps `DayLogScreen`; add a `MedicationProvider` seeded with one enabled medication and assert the chip renders. Add near the top of the relevant `testWidgets` (adapt to the file's existing provider wrap — it already provides `LogProvider`):

```dart
  testWidgets('day log screen shows configured medication chips',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final logRepo = DailyLogRepository(db);
    final logs = LogProvider(logRepo)..load();
    final medRepo = MedicationRepository(db);
    await medRepo.add(name: 'Iron', enabled: true);
    final meds = MedicationProvider(medRepo);
    await meds.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        ChangeNotifierProvider<MedicationProvider>.value(value: meds),
      ],
      child: MaterialApp(home: DayLogScreen(date: DateTime(2026, 3, 10))),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Iron'), findsOneWidget);
    await db.close();
  });
```

Add imports as needed: `package:menstrul_track/data/medication_repository.dart`, `package:menstrul_track/providers/medication_provider.dart`, `package:provider/provider.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/day_log_screen_test.dart`
Expected: FAIL — "Iron" not found (screen doesn't pass meds to the form yet).

- [ ] **Step 3: Write minimal implementation**

Add a shared helper reading enabled meds. In `day_log_screen.dart`, change the `DayEntryForm(...)` (line ~55) to:

```dart
      body: DayEntryForm(
        key: _formKey,
        date: widget.date,
        medications: _enabledMedChips(context),
      ),
```

Add this top-level helper in `day_log_screen.dart` (and import `MedicationProvider`, `MedChip`, `provider`):

```dart
/// Enabled medications as intake chips, or empty when the provider is absent
/// (keeps the form pumpable in tests without a MedicationProvider).
List<MedChip> _enabledMedChips(BuildContext context) {
  final meds = context.watch<MedicationProvider?>();
  if (meds == null) return const [];
  return [
    for (final m in meds.items)
      if (m.enabled) MedChip(m.id, m.name),
  ];
}
```

> Note: `context.watch<MedicationProvider?>()` (nullable type) returns `null` rather than throwing when the provider is absent — this is why the "no medications" form test and the existing form tests keep working.

In `calendar_screen.dart` (line ~226), change the `DayEntryForm(key: _formKey, date: widget.date)` to:
```dart
            Expanded(
              child: DayEntryForm(
                key: _formKey,
                date: widget.date,
                medications: _enabledMedChips(context),
              ),
            ),
```
Move `_enabledMedChips` to a shared spot to avoid duplication: put it in `lib/widgets/day_entry_form.dart` as a top-level function `List<MedChip> enabledMedChips(BuildContext context)` (public), and call `enabledMedChips(context)` from both screens. Remove the local copy. (DRY.)

In `insights_screen.dart`, thread medication names into `_CycleHistory`:
- Change `_CycleHistory` to accept `final Map<int, String> medNames;` (add to constructor), and its `summarize` call to `CycleOverviewService.summarize(c, logs, medNames: medNames)`.
- At the `_CycleHistory(cycles: cycles, logs: logProvider.logs)` call site (line ~187), build the map:
```dart
                  _CycleHistory(
                    cycles: cycles,
                    logs: logProvider.logs,
                    medNames: {
                      for (final m in (context.watch<MedicationProvider?>()?.items ?? const []))
                        m.id: m.name,
                    },
                  ),
```
Import `MedicationProvider` and `provider` in `insights_screen.dart` if not already.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/day_log_screen_test.dart`
Then the full suite: `flutter test` and `flutter analyze`.
Expected: PASS / clean. (Existing calendar/insights tests that pump without a `MedicationProvider` still pass because `enabledMedChips` returns `const []` and the med-name map is empty.)

- [ ] **Step 5: Commit**

```bash
git add lib/screens/calendar/calendar_screen.dart lib/screens/log/day_log_screen.dart lib/screens/insights/insights_screen.dart lib/widgets/day_entry_form.dart test/day_log_screen_test.dart
git commit -m "feat: supply enabled medications to the day editor and cycle overview"
```

---

### Task 6: `MedicationAdherenceService` (days logged per med, per cycle)

**Files:**
- Create: `lib/models/medication_adherence.dart`
- Create: `lib/services/medication_adherence_service.dart`
- Test: `test/medication_adherence_test.dart` (create)

**Interfaces:**
- Consumes: `kMedicationKeyPrefix`, `decodeGroup` (Task 1); `Cycle`, `DailyLog`, `Medication`; `dateOnly` from `common/date_utils.dart`.
- Produces:
  - `class MedAdherenceEntry { final int medId; final String name; final int daysLogged; final int cycleLength; }`
  - `class MedicationAdherence { final List<MedAdherenceEntry> entries; bool get hasData => entries.isNotEmpty; }`
  - `MedicationAdherence MedicationAdherenceService.forCycle(Cycle cycle, List<DailyLog> logs, List<Medication> meds)`

- [ ] **Step 1: Write the failing test**

```dart
// test/medication_adherence_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/cycle_calculator.dart';
import 'package:menstrul_track/services/medication_adherence_service.dart';

void main() {
  test('counts days each enabled medication was logged in the cycle', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final logRepo = DailyLogRepository(db);
    final medRepo = MedicationRepository(db);

    final ironId = await medRepo.add(name: 'Iron', enabled: true);
    final oldId = await medRepo.add(name: 'Stopped', enabled: false);

    // 3-day period → one complete cycle if a later period exists; keep it simple
    // with two period runs so the first cycle has a length.
    for (final d in [1, 2, 3]) {
      await logRepo.upsert(
        date: DateTime(2026, 1, d),
        flow: FlowIntensity.medium,
        symptomsJson: encodeDayTags(
            flags: d < 3 ? {'med_$ironId', 'med_$oldId'} : {'med_$ironId'}),
      );
    }
    await logRepo.upsert(
        date: DateTime(2026, 1, 29), flow: FlowIntensity.medium);

    final logs = await logRepo.getAll();
    final meds = await medRepo.getAll();
    final cycles = CycleCalculator.computeCycles(logs);
    final firstCycle = cycles.first; // Jan 1 start, length 28

    final adherence =
        MedicationAdherenceService.forCycle(firstCycle, logs, meds);

    expect(adherence.hasData, isTrue);
    expect(adherence.entries, hasLength(1)); // disabled med excluded
    final iron = adherence.entries.single;
    expect(iron.name, 'Iron');
    expect(iron.daysLogged, 3);
    expect(iron.cycleLength, 28);

    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/medication_adherence_test.dart`
Expected: FAIL — service/model undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/models/medication_adherence.dart
/// Days a single medication was logged within one cycle. [cycleLength] is the
/// bar's denominator — a scale, NOT an adherence target (we don't store dosing
/// frequency, so no percentage is implied).
class MedAdherenceEntry {
  const MedAdherenceEntry({
    required this.medId,
    required this.name,
    required this.daysLogged,
    required this.cycleLength,
  });

  final int medId;
  final String name;
  final int daysLogged;
  final int cycleLength;
}

/// Per-medication days-logged for one cycle. Descriptive only.
class MedicationAdherence {
  const MedicationAdherence(this.entries);
  final List<MedAdherenceEntry> entries;
  bool get hasData => entries.isNotEmpty;
}
```

```dart
// lib/services/medication_adherence_service.dart
import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/cycle.dart';
import '../models/medication_adherence.dart';

/// Counts, per enabled medication, how many days it was logged within a cycle.
/// Pure function of (cycle, logs, meds). No percentage — just a day-count and
/// the cycle length as a bar scale.
class MedicationAdherenceService {
  const MedicationAdherenceService._();

  static MedicationAdherence forCycle(
    Cycle cycle,
    List<DailyLog> logs,
    List<Medication> meds,
  ) {
    final start = dateOnly(cycle.start);
    final nextStart = cycle.lengthDays == null
        ? null
        : start.add(Duration(days: cycle.lengthDays!));
    final cycleLength = cycle.lengthDays ?? cycle.periodLengthDays;

    bool inCycle(DateTime raw) {
      final d = dateOnly(raw);
      return !d.isBefore(start) && (nextStart == null || d.isBefore(nextStart));
    }

    // Pre-count med_<id> day tallies across the cycle.
    final tally = <int, int>{};
    for (final l in logs) {
      if (!inCycle(l.date)) continue;
      for (final key in decodeGroup(l.symptoms, kMedicationKeyPrefix)) {
        final id = int.tryParse(key.substring(kMedicationKeyPrefix.length));
        if (id != null) tally[id] = (tally[id] ?? 0) + 1;
      }
    }

    final entries = <MedAdherenceEntry>[
      for (final m in meds)
        if (m.enabled && (tally[m.id] ?? 0) > 0)
          MedAdherenceEntry(
            medId: m.id,
            name: m.name,
            daysLogged: tally[m.id]!,
            cycleLength: cycleLength,
          ),
    ]..sort((a, b) {
        final byCount = b.daysLogged.compareTo(a.daysLogged);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });

    return MedicationAdherence(entries);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/medication_adherence_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/medication_adherence.dart lib/services/medication_adherence_service.dart test/medication_adherence_test.dart
git commit -m "feat: add MedicationAdherenceService (days logged per cycle)"
```

---

### Task 7: "Medications this cycle" adherence section on Insights

**Files:**
- Modify: `lib/screens/insights/insights_screen.dart` (build the adherence model + `_MedicationAdherenceList` widget + section)
- Test: `test/insights_medication_adherence_test.dart` (create)

**Interfaces:**
- Consumes: `MedicationAdherenceService.forCycle` (Task 6); `MedicationProvider.items`; `LogProvider.cycles`/`.logs`; existing `_SectionLabel`, `LinearProgressIndicator` bar style from `_SymptomFrequencyList`.
- Produces: a "Medications this cycle" section, gated on `adherence.hasData`, hidden when no `MedicationProvider` is present. No "%" text anywhere.

- [ ] **Step 1: Write the failing test**

```dart
// test/insights_medication_adherence_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/medication_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/providers/medication_provider.dart';
import 'package:menstrul_track/screens/insights/insights_screen.dart';

void main() {
  testWidgets('shows a Medications this cycle bar, never a percentage',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final logRepo = DailyLogRepository(db);
    final medRepo = MedicationRepository(db);
    final ironId = await medRepo.add(name: 'Iron', enabled: true);

    // Two period runs → the first cycle has a length; Iron logged 3 days.
    for (final d in [1, 2, 3]) {
      await logRepo.upsert(
        date: DateTime(2026, 1, d),
        flow: FlowIntensity.medium,
        symptomsJson: encodeDayTags(flags: {'med_$ironId'}),
      );
    }
    await logRepo.upsert(date: DateTime(2026, 1, 29), flow: FlowIntensity.medium);

    final logs = LogProvider(logRepo);
    await logs.load();
    final meds = MedicationProvider(medRepo);
    await meds.load();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LogProvider>.value(value: logs),
        ChangeNotifierProvider<MedicationProvider>.value(value: meds),
      ],
      child: const MaterialApp(home: InsightsScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Medications this cycle'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('Medications this cycle'), findsOneWidget);
    expect(find.text('Iron'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing); // no false precision
    await db.close();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/insights_medication_adherence_test.dart`
Expected: FAIL — "Medications this cycle" not found.

- [ ] **Step 3: Write minimal implementation**

In `insights_screen.dart` build method (where `flow`/`symptoms` are computed, ~line 62), compute adherence for the most recent complete cycle:

```dart
    final meds = context.watch<MedicationProvider?>()?.items ?? const <Medication>[];
    final completeCycles = cycles.where((c) => c.isComplete).toList();
    final adherence = completeCycles.isEmpty
        ? const MedicationAdherence([])
        : MedicationAdherenceService.forCycle(
            completeCycles.last, logProvider.logs, meds);
```

Add the section in the `ListView` children, after the "Cycle history" block (gate on data):

```dart
            if (adherence.hasData) ...[
              const SizedBox(height: 24),
              _SectionLabel('Medications this cycle'),
              _MedicationAdherenceList(adherence: adherence),
            ],
```

Add the widget (model the bar on `_SymptomFrequencyList`):

```dart
/// Per-medication days-logged for the most recent complete cycle, as bars scaled
/// to the cycle length. A count, never a percentage (dosing frequency isn't
/// stored, so no adherence target is implied).
class _MedicationAdherenceList extends StatelessWidget {
  const _MedicationAdherenceList({required this.adherence});
  final MedicationAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in adherence.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text(e.name,
                            style: Theme.of(context).textTheme.bodyMedium)),
                    Text('logged ${e.daysLogged} ${e.daysLogged == 1 ? 'day' : 'days'}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            )),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.cycleLength == 0
                        ? 0
                        : (e.daysLogged / e.cycleLength).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

Add imports to `insights_screen.dart`: `../../models/medication_adherence.dart`, `../../services/medication_adherence_service.dart`, `../../db/database.dart` (for `Medication`), `../../providers/medication_provider.dart`, `package:provider/provider.dart` (if not already imported).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/insights_medication_adherence_test.dart`
Then full suite: `flutter test` and `flutter analyze`.
Expected: PASS / clean. Existing Insights tests without a `MedicationProvider` still pass (adherence is empty → section hidden).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/insights/insights_screen.dart test/insights_medication_adherence_test.dart
git commit -m "feat: add Medications this cycle adherence section to Insights"
```

---

### Task 8: Full-suite green + analyzer + device verification

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `flutter test`
Expected: all green (prior 234 + the new medication tests).

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: On-device smoke (respect the shared device — do not commandeer another `flutter run`)**

- Settings → Medications → add one (e.g. "Vitamin D", enabled).
- Open a day in the Calendar → confirm the "Medications" chip group shows "Vitamin D"; tap it; Save.
- Log it across 2–3 days of a past period.
- Insights → confirm a Cycle Overview (tap a cycle) shows the "Medications" section, and the "Medications this cycle" bar renders with "logged N days" and **no %**.

- [ ] **Step 4: Final commit (if any verification tweaks were needed)**

```bash
git add -A
git commit -m "chore: verify medication intake feature on device"
```

---

## Self-Review

**Spec coverage:**
- §1 data layer (`med_<id>`, reserved prefix) → Task 1. ✅
- §2 logging surface (`DayEntryForm` chips, optional param, enabled-only, initState/save) → Tasks 4 & 5. ✅
- §3 Cycle Overview (model field, service `medNames` tally, screen section) → Tasks 2 & 3. ✅
- §4 adherence (days-logged, no %, pure service + Insights bar) → Tasks 6 & 7. ✅
- §5 testing (each behavior TDD) → tests in every task. ✅
- §6 device verification → Task 8. ✅

**Placeholder scan:** none — every code step shows complete code.

**Type consistency:**
- `kMedicationKeyPrefix` used identically in Tasks 1/2/4/6.
- `summarize(Cycle, List<DailyLog>, {Map<int,String> medNames})` defined in Task 2, called with `medNames:` in Task 5. ✅
- `MedChip(int id, String name)` defined Task 4, constructed in Task 5's `enabledMedChips`. ✅
- `MedAdherenceEntry`/`MedicationAdherence`/`forCycle` defined Task 6, consumed Task 7 (`.entries`, `.hasData`, `.name`, `.daysLogged`, `.cycleLength`). ✅
- `enabledMedChips(BuildContext)` made public in `day_entry_form.dart` (Task 5) and called from both screens. ✅
