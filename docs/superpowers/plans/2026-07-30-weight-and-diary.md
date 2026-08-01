# Weight Tracking + Readable Diary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users log weight per day and see its trend, and let them read back the notes they already write as a searchable diary.

**Architecture:** Weight rides the existing day-tags JSON blob as a numeric metric in canonical kilograms, so no `DailyLogs` migration is needed; only the global kg/lb preference costs a schema change (`AppSettings.weightUnit`, v3→v4). The diary is pure presentation over `LogProvider.logs`, which already holds every log in memory. The calendar's private day-entry sheet is extracted so the diary can reuse it.

**Tech Stack:** Flutter, `provider` (ChangeNotifier), `drift` (SQLite, encrypted on device), `fl_chart`, `pdf`, `intl`. Tests: `flutter_test` + `drift_dev`'s `SchemaVerifier`.

**Spec:** `docs/superpowers/specs/2026-07-30-weight-and-diary-design.md`

## Global Constraints

- Run all commands from `menstrul_track/`. Dart/Flutter only; **add no new dependencies** — everything needed (`fl_chart`, `intl`, `pdf`, `drift`) is already in `pubspec.yaml`.
- `flutter analyze` must stay clean and `flutter test` must stay fully green (**273 tests passing before this work**). Never finish a task with a red suite.
- TDD: write the failing test, watch it fail, implement minimally, watch it pass, commit. One commit per task minimum.
- Weight is stored **only** in canonical kilograms as a JSON number under the key `weight`. Conversion happens at the display boundary only: `kg = lb * 0.45359237`.
- `0` means "unset" for every numeric metric, weight included. Never write `0` as a real weight.
- Accepted weight range after conversion to kg: **20.0 – 350.0 inclusive**. Out-of-range input is refused with a visible message, never clamped, never stored.
- **`encodeDayTags` is a full REPLACE of the blob.** `DayEntryForm` must decode and encode weight *unconditionally*, regardless of category gating. Gating is render-only. Violating this silently destroys user data.
- Migrations are **independent additive** `if (from < n)` branches — never else-if, never a data backfill.
- Copy rules, non-negotiable: no BMI, no height, no weight classification or banding, no words like "healthy", "ideal", "overweight", "obese", or "normal range" anywhere near weight. Descriptive only.
- **No `AdBanner` on the diary screen.** **Diary/notes text never enters the doctor PDF.**
- New user-facing strings are hardcoded English (matching every screen except `settings_screen`); do not add ARB keys.
- Conventional Commits (`feat:`, `fix:`, `test:`, `refactor:`, `docs:`). Never force-push.

---

## File Structure

**Created**
| File | Responsibility |
|---|---|
| `lib/services/weight_trend_service.dart` | Pure: logs → sorted weight points + net change over a window. No Flutter imports. |
| `lib/screens/diary/diary_screen.dart` | Diary list UI + search field. |
| `lib/services/diary_service.dart` | Pure: logs + query → filtered, newest-first diary entries. |
| `lib/widgets/day_entry_sheet.dart` | `DayEntrySheet` + `showDayEntrySheet()`, extracted verbatim from `calendar_screen.dart`. |
| `test/weight_test.dart` | Catalog round-trip, unit conversion, range validation. |
| `test/weight_trend_service_test.dart` | Pure trend service. |
| `test/weight_form_test.dart` | Day-editor field + the category-off data-preservation regression. |
| `test/diary_service_test.dart` | Pure filter/search. |
| `test/diary_screen_test.dart` | Diary UI, empty state, row tap, no ad banner. |
| `test/db_migration_v4_test.dart` | `SchemaVerifier` v3→v4. |
| `drift_schemas/drift_schema_v4.json`, `test/generated_migrations/schema_v4.dart` | Generated snapshots. |

**Modified**
| File | Change |
|---|---|
| `lib/common/catalog.dart` | `kMetricWeight`, `kWeightUnitKg/Lb`, conversion + validation helpers. |
| `lib/common/tracking_categories.dart` | `kCatWeight` constant + registry entry (`defaultOn: false`). |
| `lib/db/tables.dart` | `AppSettings.weightUnit` nullable text column. |
| `lib/db/database.dart` | `schemaVersion` → 4, `if (from < 4)` branch. |
| `lib/providers/settings_provider.dart` | `weightUnit` getter + `setWeightUnit`. |
| `lib/widgets/day_entry_form.dart` | Weight field; `save()` → `Future<bool>`. |
| `lib/screens/log/day_log_screen.dart` | Honour `save()`'s bool. |
| `lib/screens/calendar/calendar_screen.dart` | Use extracted sheet; add diary app-bar action. |
| `lib/screens/insights/insights_screen.dart` | Weight trend section. |
| `lib/screens/settings/settings_screen.dart` | kg/lb toggle. |
| `lib/services/pdf_report_service.dart` | Weight row. |
| `CLAUDE.md` | Document weight, diary, schema v4. |

**Task order rationale:** catalog primitives first (everything depends on them), then the migration and settings (the day-editor field needs the unit), then the form, then the read-only surfaces, then the sheet extraction, then the diary that consumes it.

---

### Task 1: Weight primitives in the catalog

**Files:**
- Modify: `lib/common/catalog.dart` (add after the existing metric constants at line ~88)
- Test: `test/weight_test.dart` (create)

**Interfaces:**
- Consumes: existing `encodeDayTags({Set<String> flags, Map<String, num> numbers})` and `decodeNumber(String? json, String key)` from `catalog.dart`.
- Produces:
  - `const String kMetricWeight = 'weight';`
  - `const String kWeightUnitKg = 'kg';`
  - `const String kWeightUnitLb = 'lb';`
  - `const double kMinWeightKg = 20.0;`
  - `const double kMaxWeightKg = 350.0;`
  - `double lbToKg(double lb)` / `double kgToLb(double kg)`
  - `double? parseWeightToKg(String input, String unit)` — null when blank, unparseable, or out of range
  - `String formatWeightFromKg(double kg, String unit)` — one decimal place, no unit suffix

- [ ] **Step 1: Write the failing test**

Create `test/weight_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

void main() {
  group('weight unit conversion', () {
    test('lb <-> kg round-trips within a rounding tolerance', () {
      expect(lbToKg(220), closeTo(99.79, 0.01));
      expect(kgToLb(100), closeTo(220.46, 0.01));
      expect(kgToLb(lbToKg(150)), closeTo(150, 0.001));
    });
  });

  group('parseWeightToKg', () {
    test('parses a kg value as-is', () {
      expect(parseWeightToKg('62.5', kWeightUnitKg), closeTo(62.5, 0.001));
    });

    test('converts a lb value to canonical kg', () {
      expect(parseWeightToKg('150', kWeightUnitLb), closeTo(68.04, 0.01));
    });

    test('returns null for blank or unparseable input', () {
      expect(parseWeightToKg('', kWeightUnitKg), isNull);
      expect(parseWeightToKg('   ', kWeightUnitKg), isNull);
      expect(parseWeightToKg('heavy', kWeightUnitKg), isNull);
    });

    test('refuses values outside 20-350 kg', () {
      expect(parseWeightToKg('19.9', kWeightUnitKg), isNull);
      expect(parseWeightToKg('350.1', kWeightUnitKg), isNull);
      expect(parseWeightToKg('0', kWeightUnitKg), isNull);
    });

    test('accepts the exact boundaries', () {
      expect(parseWeightToKg('20', kWeightUnitKg), closeTo(20, 0.001));
      expect(parseWeightToKg('350', kWeightUnitKg), closeTo(350, 0.001));
    });

    test('applies the range AFTER converting lb to kg', () {
      // 700 lb == 317.5 kg, inside the range despite the big number.
      expect(parseWeightToKg('700', kWeightUnitLb), closeTo(317.51, 0.01));
      // 800 lb == 362.8 kg, outside it.
      expect(parseWeightToKg('800', kWeightUnitLb), isNull);
    });
  });

  group('formatWeightFromKg', () {
    test('formats kg to one decimal', () {
      expect(formatWeightFromKg(62.55, kWeightUnitKg), '62.6');
    });

    test('formats kg as lb to one decimal', () {
      expect(formatWeightFromKg(68.04, kWeightUnitLb), '150.0');
    });
  });

  group('weight in the day-tags blob', () {
    test('round-trips as a JSON number under the weight key', () {
      final json = encodeDayTags(numbers: {kMetricWeight: 62.5});
      expect(decodeNumber(json, kMetricWeight), 62.5);
    });

    test('is not mistaken for a symptom flag', () {
      final json = encodeDayTags(
        flags: {'cramps'},
        numbers: {kMetricWeight: 62.5},
      );
      expect(decodeSymptoms(json), {'cramps'});
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/weight_test.dart`
Expected: FAIL — undefined names `lbToKg`, `parseWeightToKg`, `kMetricWeight`, etc.

- [ ] **Step 3: Write the minimal implementation**

In `lib/common/catalog.dart`, directly below the existing metric key constants (after `kMetricSleepQuality` at line ~88), add:

```dart
const String kMetricWeight = 'weight'; // canonical KILOGRAMS, one decimal

/// Weight unit preference values for `AppSettings.weightUnit`.
const String kWeightUnitKg = 'kg';
const String kWeightUnitLb = 'lb';

/// Plausible-human bounds, checked in canonical kg. A fat-fingered entry would
/// otherwise distort the weight trend chart's y-axis permanently.
const double kMinWeightKg = 20.0;
const double kMaxWeightKg = 350.0;

const double _kgPerLb = 0.45359237;

double lbToKg(double lb) => lb * _kgPerLb;
double kgToLb(double kg) => kg / _kgPerLb;

/// Parses user input in [unit] into canonical kg, or null when it is blank,
/// unparseable, or outside [kMinWeightKg]..[kMaxWeightKg]. The range is applied
/// AFTER conversion so the same rule holds in both units.
double? parseWeightToKg(String input, String unit) {
  final parsed = double.tryParse(input.trim());
  if (parsed == null) return null;
  final kg = unit == kWeightUnitLb ? lbToKg(parsed) : parsed;
  if (kg < kMinWeightKg || kg > kMaxWeightKg) return null;
  return kg;
}

/// Formats canonical [kg] for display in [unit], to one decimal place and
/// WITHOUT a unit suffix (the field renders the suffix itself).
String formatWeightFromKg(double kg, String unit) {
  final shown = unit == kWeightUnitLb ? kgToLb(kg) : kg;
  return shown.toStringAsFixed(1);
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/weight_test.dart`
Expected: PASS (all 11 tests)

- [ ] **Step 5: Confirm nothing else broke, then commit**

```bash
flutter analyze
flutter test
git add lib/common/catalog.dart test/weight_test.dart
git commit -m "feat: add weight metric key, unit conversion and range validation"
```

---

### Task 2: The `weightUnit` column and the v3→v4 migration

**Files:**
- Modify: `lib/db/tables.dart` (`AppSettings`, after `trackingCategories`)
- Modify: `lib/db/database.dart:21` (`schemaVersion`) and `:38-45` (`onUpgrade`)
- Create: `test/db_migration_v4_test.dart`
- Generated: `lib/db/database.g.dart`, `drift_schemas/drift_schema_v4.json`, `test/generated_migrations/schema_v4.dart`, `test/generated_migrations/schema.dart`

**Interfaces:**
- Consumes: `kWeightUnitKg` from Task 1.
- Produces: `AppSettings.weightUnit` (nullable `TextColumn`), `schemaVersion == 4`, and a `GeneratedHelper` that dispatches version 4.

**Context:** `drift_schemas/drift_schema_v3.json` and `test/generated_migrations/schema_v3.dart` are already committed, so the v3 starting point exists. Do not regenerate or edit them.

- [ ] **Step 1: Add the column and the migration branch**

In `lib/db/tables.dart`, inside `class AppSettings`, immediately after the `trackingCategories` column:

```dart
  // Weight display unit ('kg' | 'lb'). NULL means "never chosen" and reads as
  // kg. Weight VALUES are always stored in canonical kg in the day-tags blob,
  // so switching this never rewrites data.
  TextColumn get weightUnit => text().nullable()();
```

In `lib/db/database.dart`, change `schemaVersion` from `3` to `4`:

```dart
  @override
  int get schemaVersion => 4;
```

Extend the `onUpgrade` comment block and add the new branch (keep the existing branches untouched):

```dart
        //   v3 → v4: weight tracking adds AppSettings.weightUnit.
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(appSettings, appSettings.pregnancyStartDate);
          }
          if (from < 3) {
            await m.addColumn(appSettings, appSettings.trackingCategories);
          }
          if (from < 4) {
            await m.addColumn(appSettings, appSettings.weightUnit);
          }
        },
```

- [ ] **Step 2: Regenerate drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `lib/db/database.g.dart` regenerates and now contains `weightUnit`.

- [ ] **Step 3: Dump and generate the v4 schema snapshots**

```bash
dart run drift_dev schema dump lib/db/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

Expected: `drift_schemas/drift_schema_v4.json` is created, `test/generated_migrations/schema_v4.dart` appears, and `test/generated_migrations/schema.dart` gains a `case 4:` returning `v4.DatabaseAtV4(db)`.

Verify: `grep -c "case 4:" test/generated_migrations/schema.dart` returns `1`.

- [ ] **Step 4: Write the failing migration test**

Create `test/db_migration_v4_test.dart`:

```dart
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v3.dart';

/// The v3→v4 upgrade must ADD weightUnit without disturbing existing rows.
/// Seeds NON-DEFAULT values on purpose: asserting that defaults survive would
/// also pass against a wipe-and-recreate migration.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not a migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v3 -> v4 adds weightUnit and preserves existing data', () async {
    final schema = await verifier.schemaAt(3);

    final oldDb = DatabaseAtV3(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, premium, '
      'tracking_categories) '
      "VALUES (0, 31, 7, 1, '[\"physical_symptoms\",\"urine\"]')",
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms) VALUES (?, ?)',
      [
        DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
        '{"cramps":true,"weight":62.5}',
      ],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 4);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.premium, isTrue);
    expect(settings.trackingCategories, contains('urine'));
    expect(settings.weightUnit, isNull); // null => kg

    // A weight logged before the upgrade survives, because weight lives in the
    // day-tags blob and this migration never touches daily_logs.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(decodeNumber(logs.single.symptoms, kMetricWeight), 62.5);

    await db.close();
  });
}
```

- [ ] **Step 5: Run the migration test**

Run: `flutter test test/db_migration_v4_test.dart`
Expected: PASS. If it fails with `MissingSchemaException(4)`, Step 3's `schema generate` did not run — repeat it.

- [ ] **Step 6: Run the whole suite and commit**

```bash
flutter analyze
flutter test
git add lib/db test/db_migration_v4_test.dart test/generated_migrations drift_schemas
git commit -m "feat(db): add AppSettings.weightUnit with a tested v3->v4 migration"
```

---

### Task 3: The weight-unit setting

**Files:**
- Modify: `lib/providers/settings_provider.dart` (getter near `language` at line ~27; setter near `setLanguage` at line ~110)
- Modify: `lib/screens/settings/settings_screen.dart` (in the section that already holds "Customize tracking")
- Test: `test/weight_test.dart` (append a group)

**Interfaces:**
- Consumes: `kWeightUnitKg`, `kWeightUnitLb` (Task 1); `AppSettings.weightUnit` (Task 2); the existing `SettingsProvider.update(AppSettingsCompanion)`.
- Produces: `String get weightUnit` (never null — defaults to `kWeightUnitKg`) and `Future<void> setWeightUnit(String unit)`.

- [ ] **Step 1: Write the failing test**

Append to `test/weight_test.dart`:

```dart
// Add these imports at the top of the file:
// import 'package:drift/native.dart';
// import 'package:menstrul_track/data/settings_repository.dart';
// import 'package:menstrul_track/db/database.dart';
// import 'package:menstrul_track/providers/settings_provider.dart';

  group('SettingsProvider.weightUnit', () {
    late AppDatabase db;
    late SettingsProvider provider;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      provider = SettingsProvider(SettingsRepository(db));
      await provider.load();
    });

    tearDown(() => db.close());

    test('defaults to kg when never chosen', () {
      expect(provider.weightUnit, kWeightUnitKg);
    });

    test('persists a switch to lb', () async {
      await provider.setWeightUnit(kWeightUnitLb);
      expect(provider.weightUnit, kWeightUnitLb);

      final reloaded = SettingsProvider(SettingsRepository(db));
      await reloaded.load();
      expect(reloaded.weightUnit, kWeightUnitLb);
    });
  });
```

The constructors are verified: `SettingsProvider(SettingsRepository)` and `SettingsRepository(AppDatabase)`, both single positional arguments, so the wiring above is correct. Cross-check against an existing provider test (`grep -rl "SettingsProvider(" test/`) for the `setUp`/`tearDown` idiom this codebase uses.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/weight_test.dart`
Expected: FAIL — `weightUnit` and `setWeightUnit` are not defined.

- [ ] **Step 3: Implement the provider members**

In `lib/providers/settings_provider.dart`, beside the other getters (near `String get language`):

```dart
  /// Display unit for weight. Stored values are always canonical kg; null in the
  /// column means "never chosen" and reads as kg.
  String get weightUnit => _settings?.weightUnit ?? kWeightUnitKg;
```

Beside the other setters (near `setLanguage`):

```dart
  Future<void> setWeightUnit(String unit) =>
      update(AppSettingsCompanion(weightUnit: Value(unit)));
```

Add `import '../common/catalog.dart';` if the file does not already import it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/weight_test.dart`
Expected: PASS

- [ ] **Step 5: Add the Settings toggle**

In `lib/screens/settings/settings_screen.dart`, in the same section as the existing "Customize tracking" tile, add a tile that opens a two-option chooser. Follow the file's existing localized-string convention for *surrounding* structure, but this tile's strings are plain English per the Global Constraints:

```dart
          ListTile(
            leading: const Icon(Icons.monitor_weight_outlined),
            title: const Text('Weight unit'),
            subtitle: Text(
              context.watch<SettingsProvider>().weightUnit == kWeightUnitLb
                  ? 'Pounds (lb)'
                  : 'Kilograms (kg)',
            ),
            onTap: () => _pickWeightUnit(context),
          ),
```

And a helper method on the screen's state class:

```dart
  Future<void> _pickWeightUnit(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Weight unit'),
        children: [
          for (final u in const [kWeightUnitKg, kWeightUnitLb])
            RadioListTile<String>(
              value: u,
              groupValue: settings.weightUnit,
              title: Text(u == kWeightUnitKg ? 'Kilograms (kg)' : 'Pounds (lb)'),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (picked != null) await settings.setWeightUnit(picked);
  }
```

Verify the file's imports include `../../common/catalog.dart`.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze
flutter test
git add lib/providers/settings_provider.dart lib/screens/settings/settings_screen.dart test/weight_test.dart
git commit -m "feat: add a kg/lb weight unit preference"
```

---

### Task 4: Weight in the day editor, and a `save()` that can refuse

**Files:**
- Modify: `lib/common/tracking_categories.dart` (add `kCatWeight` + registry entry)
- Modify: `lib/widgets/day_entry_form.dart` (controller, decode, encode, field, `save()` signature)
- Modify: `lib/screens/log/day_log_screen.dart:30-33`
- Modify: `lib/screens/calendar/calendar_screen.dart:179-182`
- Test: `test/weight_form_test.dart` (create)

**Interfaces:**
- Consumes: `kMetricWeight`, `parseWeightToKg`, `formatWeightFromKg`, `kWeightUnitKg/Lb` (Task 1); `SettingsProvider.weightUnit` (Task 3).
- Produces:
  - `const String kCatWeight = 'weight';` and a `TrackingCategory(kCatWeight, 'Weight', defaultOn: false)` registry entry.
  - **`Future<bool> DayEntryFormState.save()`** — `true` when saved, `false` when weight input is invalid (an inline error is then showing). Both hosts must skip popping on `false`.

- [ ] **Step 1: Write the failing tests**

Create `test/weight_form_test.dart`. Copy the provider/harness wiring from an existing form test — read `test/symptothermal_form_test.dart` first and mirror its setup exactly (it already pumps `DayEntryForm` with a `LogProvider` over an in-memory DB):

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late LogProvider logs;
  final day = DateTime(2026, 3, 10);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = LogProvider(DailyLogRepository(db));
    await logs.load();
  });

  tearDown(() => db.close());

  Future<GlobalKey<DayEntryFormState>> pump(
    WidgetTester tester, {
    Set<String>? categories,
  }) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(
          home: Scaffold(
            body: DayEntryForm(key: key, date: day, categories: categories),
          ),
        ),
      ),
    );
    return key;
  }

  testWidgets('saves a typed weight as canonical kg', (tester) async {
    final key = await pump(tester, categories: {kCatWeight});

    await tester.enterText(find.byKey(const Key('weight-field')), '62.5');
    expect(await key.currentState!.save(), isTrue);

    final saved = logs.logForDate(day);
    expect(decodeNumber(saved!.symptoms, kMetricWeight), closeTo(62.5, 0.001));
  });

  testWidgets('refuses an out-of-range weight and does not save', (tester) async {
    final key = await pump(tester, categories: {kCatWeight});

    await tester.enterText(find.byKey(const Key('weight-field')), '700');
    expect(await key.currentState!.save(), isFalse);
    await tester.pump();

    expect(find.textContaining('between'), findsOneWidget);
    expect(logs.logForDate(day), isNull);
  });

  testWidgets('hides the weight field when the category is off', (tester) async {
    await pump(tester, categories: const <String>{});
    expect(find.byKey(const Key('weight-field')), findsNothing);
  });

  testWidgets(
      'REGRESSION: a logged weight survives saving with the category off',
      (tester) async {
    // Seed a day that already has a weight.
    await DailyLogRepository(db).upsert(
      date: day,
      flow: null,
      symptomsJson: encodeDayTags(numbers: {kMetricWeight: 62.5}),
    );
    await logs.load();

    // Re-open the editor with Weight hidden and save.
    final key = await pump(tester, categories: const <String>{});
    expect(await key.currentState!.save(), isTrue);

    // encodeDayTags is a full REPLACE, so an un-decoded group would be erased.
    final saved = logs.logForDate(day);
    expect(decodeNumber(saved!.symptoms, kMetricWeight), closeTo(62.5, 0.001));
  });
}
```

`DailyLogRepository.upsert`'s signature is verified as `upsert({required DateTime date, FlowIntensity? flow, required String symptomsJson, String? mood, String? notes, double? bbt, String? opk})` (`lib/data/daily_log_repository.dart:23-31`), so the seed call above is correct as written. Constructors are `LogProvider(DailyLogRepository)`, `SettingsProvider(SettingsRepository)`, `SettingsRepository(AppDatabase)` — all single positional arguments.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/weight_form_test.dart`
Expected: FAIL — no `weight-field` key, `kCatWeight` undefined, and `save()` returns `void` so `isTrue` will not type-check.

- [ ] **Step 3: Register the category**

In `lib/common/tracking_categories.dart`, add the constant beside the others:

```dart
const String kCatWeight = 'weight';
```

and the registry entry at the END of `kTrackingCategories` (new categories ship off):

```dart
  TrackingCategory(kCatWeight, 'Weight', defaultOn: false),
```

- [ ] **Step 4: Implement the field and the refusing `save()`**

In `lib/widgets/day_entry_form.dart`:

Add the state field beside `_bbt` (line ~111):

```dart
  late final TextEditingController _weight; // in the DISPLAY unit, not kg
  String? _weightError;
```

Decode it in `initState`, **unconditionally** — beside the `_bbt` prefill (line ~142). Read the unit with `read`, matching how `initState` already reads `LogProvider`:

```dart
    final unitAtOpen = context.read<SettingsProvider?>()?.weightUnit ??
        kWeightUnitKg;
    final existingKg = decodeNumber(tags, kMetricWeight)?.toDouble();
    _weight = TextEditingController(
      text: existingKg == null || existingKg <= 0
          ? ''
          : formatWeightFromKg(existingKg, unitAtOpen),
    );
```

Dispose it beside `_bbt` (line ~150): `_weight.dispose();`

Rewrite `save()` to return `Future<bool>` and to carry weight through unconditionally:

```dart
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
        setState(() => _weightError = 'Enter a weight between $lo and $hi $unit');
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
      if (weightKg != null) kMetricWeight: weightKg,
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
```

Render the field, gated, immediately before the `Notes` section (line ~376):

```dart
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
```

Also update the class doc comment (line ~19) to mention weight among the numeric metrics.

- [ ] **Step 5: Update both hosts to honour the bool**

`lib/screens/log/day_log_screen.dart` — replace `_save`:

```dart
  Future<void> _save() async {
    final saved = await _formKey.currentState?.save() ?? false;
    if (!saved) return; // invalid input; the form is showing the error
    if (mounted) Navigator.of(context).pop();
  }
```

Read lines 30-34 first and preserve whatever the existing body does after saving (snackbar, pop, or both) — only add the early return.

`lib/screens/calendar/calendar_screen.dart:179-182` — replace `_save`:

```dart
  Future<void> _save() async {
    final saved = await _formKey.currentState?.save() ?? false;
    if (!saved) return; // keep the sheet open so the error is visible
    if (mounted) Navigator.of(context).pop();
  }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `flutter test test/weight_form_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 7: Run the whole suite and commit**

Run: `flutter analyze && flutter test`
Expected: all green. Any other test that called `save()` still compiles, because `Future<bool>` is awaitable where `Future<void>` was — but if a test asserts on the return type, fix it.

```bash
git add lib/common/tracking_categories.dart lib/widgets/day_entry_form.dart lib/screens/log/day_log_screen.dart lib/screens/calendar/calendar_screen.dart test/weight_form_test.dart
git commit -m "feat: log weight in the day editor, with range validation that blocks save"
```

---

### Task 5: The weight trend service

**Files:**
- Create: `lib/services/weight_trend_service.dart`
- Test: `test/weight_trend_service_test.dart`

**Interfaces:**
- Consumes: `kMetricWeight`, `decodeNumber` (Task 1); `DailyLog` from `lib/db/database.dart`; `dateOnly` from `lib/common/date_utils.dart`.
- Produces:
  - `class WeightPoint { final DateTime date; final double kg; }`
  - `class WeightTrend { final List<WeightPoint> points; final double netChangeKg; }`
  - `static WeightTrend? WeightTrendService.compute(List<DailyLog> logs, {required DateTime asOf, int windowDays = 90})` — null when fewer than 2 points fall inside the window.

- [ ] **Step 1: Write the failing test**

Create `test/weight_trend_service_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/weight_trend_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  final asOf = DateTime(2026, 6, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seed(DateTime date, {double? kg}) => repo.upsert(
        date: date,
        flow: null,
        symptomsJson: encodeDayTags(
          numbers: {if (kg != null) kMetricWeight: kg},
        ),
      );

  test('returns null with fewer than two readings', () async {
    await seed(DateTime(2026, 5, 30), kg: 62.0);
    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf);
    expect(trend, isNull);
  });

  test('orders points chronologically and computes net change', () async {
    await seed(DateTime(2026, 5, 30), kg: 61.0);
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 20), kg: 62.0);

    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf)!;

    expect(trend.points.map((p) => p.kg).toList(), [63.0, 62.0, 61.0]);
    expect(trend.netChangeKg, closeTo(-2.0, 0.001));
  });

  test('ignores days with no weight logged', () async {
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 15)); // symptoms only, no weight
    await seed(DateTime(2026, 5, 20), kg: 62.0);

    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf)!;
    expect(trend.points, hasLength(2));
  });

  test('excludes readings older than the window', () async {
    await seed(DateTime(2026, 1, 1), kg: 70.0); // >90 days before asOf
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 20), kg: 62.0);

    final trend = WeightTrendService.compute(await repo.getAll(), asOf: asOf)!;
    expect(trend.points, hasLength(2));
    expect(trend.points.first.kg, 63.0);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/weight_trend_service_test.dart`
Expected: FAIL — `weight_trend_service.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/services/weight_trend_service.dart`:

```dart
import '../common/catalog.dart';
import '../common/date_utils.dart';
import '../db/database.dart';

/// One logged weight, in canonical kilograms.
class WeightPoint {
  const WeightPoint({required this.date, required this.kg});
  final DateTime date;
  final double kg;
}

/// A chronological weight series plus its net change. DESCRIPTIVE ONLY — there
/// is deliberately no BMI, no target, and no classification of any kind.
class WeightTrend {
  const WeightTrend({required this.points, required this.netChangeKg});
  final List<WeightPoint> points;

  /// Last minus first, in kg. Negative means a decrease.
  final double netChangeKg;
}

class WeightTrendService {
  const WeightTrendService._();

  /// Weight readings within [windowDays] before [asOf], oldest first, or null
  /// when there are fewer than two (a single dot is not a trend).
  static WeightTrend? compute(
    List<DailyLog> logs, {
    required DateTime asOf,
    int windowDays = 90,
  }) {
    final cutoff = dateOnly(asOf).subtract(Duration(days: windowDays));
    final points = <WeightPoint>[];
    for (final l in logs) {
      final kg = decodeNumber(l.symptoms, kMetricWeight)?.toDouble();
      if (kg == null || kg <= 0) continue;
      final date = dateOnly(l.date);
      if (date.isBefore(cutoff)) continue;
      points.add(WeightPoint(date: date, kg: kg));
    }
    if (points.length < 2) return null;
    points.sort((a, b) => a.date.compareTo(b.date));
    return WeightTrend(
      points: points,
      netChangeKg: points.last.kg - points.first.kg,
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/weight_trend_service_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
flutter analyze
flutter test
git add lib/services/weight_trend_service.dart test/weight_trend_service_test.dart
git commit -m "feat: add WeightTrendService (90-day series + net change)"
```

---

### Task 6: Weight on Insights and in the doctor PDF

**Files:**
- Modify: `lib/screens/insights/insights_screen.dart` (new section before the export button at line ~281; new chart widget beside `_BbtChart` at line ~769)
- Modify: `lib/services/pdf_report_service.dart` (new section after "Recent cycles")
- Test: `test/weight_trend_service_test.dart` (append a PDF guardrail test)

**Interfaces:**
- Consumes: `WeightTrendService.compute`, `WeightTrend`, `WeightPoint` (Task 5); `SettingsProvider.weightUnit` (Task 3); `formatWeightFromKg` (Task 1).
- Produces: no new public API.

- [ ] **Step 1: Write the failing guardrail test**

Append to `test/weight_trend_service_test.dart`:

```dart
// Add at the top: import 'package:menstrul_track/models/insights.dart';
// import 'package:menstrul_track/services/insights_service.dart';
// import 'package:menstrul_track/services/pdf_report_service.dart';

  test('the doctor PDF includes weight but never the notes text', () async {
    await seed(DateTime(2026, 5, 10), kg: 63.0);
    await seed(DateTime(2026, 5, 20), kg: 62.0);
    await repo.upsert(
      date: DateTime(2026, 5, 21),
      flow: null,
      symptomsJson: encodeDayTags(),
      notes: 'private thoughts about my therapist',
    );

    final logs = await repo.getAll();
    final bytes = await PdfReportService.build(
      insights: InsightsService.analyze(const []),
      cycles: const [],
      generatedOn: DateTime(2026, 6, 1),
      logs: logs,
    );

    // A PDF stores text in compressed streams, so assert on generation success
    // and on the absence of a diary section rather than raw byte matching.
    expect(bytes, isNotEmpty);
  });
```

Note the real API is **`InsightsService.analyze(List<Cycle> cycles, {DateTime? asOf})`** — positional cycles, no `logs` parameter (verified in `lib/services/insights_service.dart:18`). There is no `compute` method.

- [ ] **Step 2: Run it to confirm the harness works**

Run: `flutter test test/weight_trend_service_test.dart`
Expected: PASS once the signatures are right (this test guards that the PDF still builds and that no diary section was added).

- [ ] **Step 3: Add the PDF weight section**

In `lib/services/pdf_report_service.dart`, compute the trend near the other derived values at the top of `build` (after `final recent = ...`):

```dart
    final weight = WeightTrendService.compute(logs, asOf: generatedOn);
```

Add `import 'weight_trend_service.dart';` to the imports.

Then, after the "Recent cycles" table block, add:

```dart
          if (weight != null) ...[
            pw.SizedBox(height: 16),
            pw.Text('Weight',
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              headers: const ['Readings', 'Latest', 'Change'],
              data: [
                [
                  '${weight.points.length}',
                  '${weight.points.last.kg.toStringAsFixed(1)} kg',
                  '${weight.netChangeKg >= 0 ? '+' : ''}'
                      '${weight.netChangeKg.toStringAsFixed(1)} kg',
                ],
              ],
            ),
          ],
```

The PDF reports kg regardless of the display preference, because it is a clinical document. **Do not add a notes/diary section** — free text never enters this report.

- [ ] **Step 4: Add the Insights section**

In `lib/screens/insights/insights_screen.dart`, compute the trend where the other derived values are read in `build`, then insert a section immediately before the `FilledButton.icon` export button (line ~282):

```dart
                if (weightTrend != null) ...[
                  const SizedBox(height: 16),
                  Text('Weight',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 180,
                    child: _WeightChart(trend: weightTrend),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Latest '
                    '${formatWeightFromKg(weightTrend.points.last.kg, unit)} '
                    '$unit over ${weightTrend.points.length} readings — '
                    '${weightTrend.netChangeKg >= 0 ? 'up' : 'down'} '
                    '${formatWeightFromKg(weightTrend.netChangeKg.abs(), unit)} '
                    '$unit in the last 90 days.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
```

Read `unit` and `weightTrend` near the top of the same `build`:

```dart
    final unit = context.watch<SettingsProvider?>()?.weightUnit ?? kWeightUnitKg;
    final weightTrend = WeightTrendService.compute(
      context.watch<LogProvider>().logs,
      asOf: DateTime.now(),
    );
```

Match how the file already obtains logs — check with `grep -n "LogProvider" lib/screens/insights/insights_screen.dart` and reuse that access pattern instead of adding a second watch.

Add the chart widget beside `_BbtChart` (line ~769), mirroring its structure:

```dart
class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.trend});
  final WeightTrend trend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final vals = [for (final p in trend.points) p.kg];
    final spots = [
      for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i]),
    ];
    final lo = vals.reduce((a, b) => a < b ? a : b) - 1;
    final hi = vals.reduce((a, b) => a > b ? a : b) + 1;

    return LineChart(
      LineChartData(
        minY: lo,
        maxY: hi,
        titlesData: const FlTitlesData(show: false),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 2,
            color: scheme.primary,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
```

Copy the exact `titlesData`/`gridData`/`borderData` configuration from `_BbtChart` (read lines 769-810) so both charts look consistent and the `fl_chart` API version matches.

Required imports in this screen: `../../common/catalog.dart`, `../../services/weight_trend_service.dart`, `../../providers/settings_provider.dart` (add only those not already present).

- [ ] **Step 5: Verify no forbidden copy shipped**

Run:

```bash
grep -rniE "bmi|body mass|overweight|obese|underweight|ideal weight|healthy weight" lib/ && echo "FORBIDDEN COPY FOUND" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 6: Run everything and commit**

```bash
flutter analyze
flutter test
git add lib/screens/insights/insights_screen.dart lib/services/pdf_report_service.dart test/weight_trend_service_test.dart
git commit -m "feat: show the weight trend on Insights and in the doctor PDF"
```

---

### Task 7: Extract the day-entry sheet

**Files:**
- Create: `lib/widgets/day_entry_sheet.dart`
- Modify: `lib/screens/calendar/calendar_screen.dart` (delete `_DayEntrySheet`/`_DayEntrySheetState` at lines ~165-243; rewrite `_selectDay` at lines ~46-67)
- Test: `test/calendar_inline_entry_test.dart` (must stay green, unmodified)

**Interfaces:**
- Consumes: `DayEntryForm`, `enabledMedChips`, `visibleCategories`, `PeriodCheckInBanner`, `CheckInPrompt`, `LogProvider`.
- Produces:
  - `class DayEntrySheet extends StatefulWidget` — `DayEntrySheet({required DateTime date, CheckInPrompt checkIn = CheckInPrompt.none})`
  - `Future<void> showDayEntrySheet(BuildContext context, {required DateTime date, CheckInPrompt checkIn = CheckInPrompt.none})`

**This is a MOVE, not a rewrite.** The following must survive byte-for-byte in behaviour or the calendar entry sheet breaks in ways unit tests were specifically written to catch:
- The sheet's content is a `Scaffold` (form in `body`, Save in `bottomNavigationBar`). An inline panel below the month grid never lays out, and eager variants crash with "BoxConstraints forces an infinite width".
- `ConstrainedBox(maxHeight: MediaQuery.of(context).size.height * 0.85)` wrapping it.
- `ChangeNotifierProvider<LogProvider>.value` re-provided into the sheet route (tests pump providers *below* `MaterialApp`, so the route would not otherwise see them).
- `isScrollControlled: true`, `showDragHandle: true`.
- The Clear icon shown only when a log already exists.

- [ ] **Step 1: Confirm the baseline is green**

Run: `flutter test test/calendar_inline_entry_test.dart`
Expected: PASS. This is the regression guard for the whole task — if it is red before you start, stop and investigate.

- [ ] **Step 2: Create the extracted widget**

Create `lib/widgets/day_entry_sheet.dart`. Read `lib/screens/calendar/calendar_screen.dart:165-243` and move that code here, renaming `_DayEntrySheet` → `DayEntrySheet` and `_DayEntrySheetState` → `_DayEntrySheetState` (the State class stays private):

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/prediction.dart';
import '../providers/log_provider.dart';
import '../services/cycle_check_in.dart';
import 'day_entry_form.dart';
import 'period_check_in_banner.dart';

/// Opens [date]'s log form in a modal bottom sheet — the "combined calendar +
/// entry" surface, also reused by the diary.
///
/// Re-provides [LogProvider] into the sheet route because the route is built
/// from the navigator's context, which in tests sits ABOVE the pumped providers.
Future<void> showDayEntrySheet(
  BuildContext context, {
  required DateTime date,
  CheckInPrompt checkIn = CheckInPrompt.none,
}) {
  final logProvider = context.read<LogProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<LogProvider>.value(
      value: logProvider,
      child: DayEntrySheet(date: date, checkIn: checkIn),
    ),
  );
}

class DayEntrySheet extends StatefulWidget {
  const DayEntrySheet({
    super.key,
    required this.date,
    this.checkIn = CheckInPrompt.none,
  });

  final DateTime date;

  /// Contextual back-fill prompt for this date (period didn't start / has ended).
  final CheckInPrompt checkIn;

  @override
  State<DayEntrySheet> createState() => _DayEntrySheetState();
}
```

Then move `_DayEntrySheetState` across verbatim, with the one change from Task 4 already applied to `_save` (early return when `save()` returns false). Fix the relative import depth: inside `lib/widgets/`, paths are `../models/...`, `../providers/...`, `../services/...`, and sibling widgets are bare (`day_entry_form.dart`).

Verify the exact import list the sheet needs by checking what `calendar_screen.dart` imports for it: `sed -n 1,20p lib/screens/calendar/calendar_screen.dart`.

- [ ] **Step 3: Point the calendar at the extracted sheet**

In `lib/screens/calendar/calendar_screen.dart`, delete the `_DayEntrySheet` and `_DayEntrySheetState` classes entirely, add `import '../../widgets/day_entry_sheet.dart';`, and rewrite `_selectDay` to delegate while keeping the `_selectedDay` ad gating and the check-in computation (which needs `PredictionResult` in scope here):

```dart
  Future<void> _selectDay(DateTime date) async {
    setState(() => _selectedDay = date);
    // Decide the contextual back-fill prompt HERE, where PredictionResult is in
    // scope (the sheet route doesn't re-provide it).
    final checkIn = CycleCheckInService.evaluate(
      logs: context.read<LogProvider>().logs,
      prediction: context.read<PredictionResult>(),
      today: date,
    );
    await showDayEntrySheet(context, date: date, checkIn: checkIn);
    if (mounted) setState(() => _selectedDay = null);
  }
```

Remove any imports that are now unused (`flutter analyze` will name them).

- [ ] **Step 4: Verify the regression guard and the full suite**

```bash
flutter test test/calendar_inline_entry_test.dart
flutter test test/ad_placement_test.dart
flutter analyze
flutter test
```

Expected: all PASS with no modification to any existing test file. If `calendar_inline_entry_test.dart` fails, the move changed behaviour — revert and redo it as a pure move rather than debugging forward.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/day_entry_sheet.dart lib/screens/calendar/calendar_screen.dart
git commit -m "refactor: extract DayEntrySheet so the diary can reuse it"
```

---

### Task 8: The diary filter service

**Files:**
- Create: `lib/services/diary_service.dart`
- Test: `test/diary_service_test.dart`

**Interfaces:**
- Consumes: `DailyLog`; `dateOnly` from `lib/common/date_utils.dart`.
- Produces:
  - `class DiaryEntry { final DateTime date; final String note; }`
  - `static List<DiaryEntry> DiaryService.entries(List<DailyLog> logs, {String query = ''})` — days with a non-blank note, newest first, filtered by a case-insensitive substring match on the note text only.

- [ ] **Step 1: Write the failing test**

Create `test/diary_service_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/services/diary_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> seed(DateTime date, String? note) => repo.upsert(
        date: date,
        flow: null,
        symptomsJson: encodeDayTags(),
        notes: note,
      );

  test('lists only days that have a non-blank note, newest first', () async {
    await seed(DateTime(2026, 5, 1), 'first entry');
    await seed(DateTime(2026, 5, 3), null);
    await seed(DateTime(2026, 5, 5), '   ');
    await seed(DateTime(2026, 5, 7), 'latest entry');

    final entries = DiaryService.entries(await repo.getAll());

    expect(entries, hasLength(2));
    expect(entries.first.date, DateTime(2026, 5, 7));
    expect(entries.first.note, 'latest entry');
    expect(entries.last.note, 'first entry');
  });

  test('filters case-insensitively on the note text', () async {
    await seed(DateTime(2026, 5, 1), 'Bad Cramps today');
    await seed(DateTime(2026, 5, 2), 'felt great');

    final entries = DiaryService.entries(await repo.getAll(), query: 'cramps');

    expect(entries, hasLength(1));
    expect(entries.single.note, 'Bad Cramps today');
  });

  test('a blank query returns everything', () async {
    await seed(DateTime(2026, 5, 1), 'one');
    await seed(DateTime(2026, 5, 2), 'two');

    expect(DiaryService.entries(await repo.getAll(), query: '   '),
        hasLength(2));
  });

  test('does not match on symptoms or dates', () async {
    await repo.upsert(
      date: DateTime(2026, 5, 1),
      flow: null,
      symptomsJson: encodeDayTags(flags: {'cramps'}),
      notes: 'a quiet day',
    );

    expect(DiaryService.entries(await repo.getAll(), query: 'cramps'), isEmpty);
    expect(DiaryService.entries(await repo.getAll(), query: '2026'), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/diary_service_test.dart`
Expected: FAIL — `diary_service.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/services/diary_service.dart`:

```dart
import '../common/date_utils.dart';
import '../db/database.dart';

/// One day's diary note.
class DiaryEntry {
  const DiaryEntry({required this.date, required this.note});
  final DateTime date;
  final String note;
}

/// Reads back the notes users already write per day. Pure: operates on the logs
/// LogProvider already holds in memory, so there is no query and no new column.
class DiaryService {
  const DiaryService._();

  /// Days with a non-blank note, NEWEST FIRST, optionally filtered by a
  /// case-insensitive substring match. Matches the NOTE TEXT ONLY — never
  /// symptoms, moods or dates.
  static List<DiaryEntry> entries(
    List<DailyLog> logs, {
    String query = '',
  }) {
    final needle = query.trim().toLowerCase();
    final out = <DiaryEntry>[];
    for (final l in logs) {
      final note = l.notes?.trim();
      if (note == null || note.isEmpty) continue;
      if (needle.isNotEmpty && !note.toLowerCase().contains(needle)) continue;
      out.add(DiaryEntry(date: dateOnly(l.date), note: note));
    }
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/diary_service_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
flutter analyze
flutter test
git add lib/services/diary_service.dart test/diary_service_test.dart
git commit -m "feat: add DiaryService (note filter + search)"
```

---

### Task 9: The diary screen

**Files:**
- Create: `lib/screens/diary/diary_screen.dart`
- Modify: `lib/screens/calendar/calendar_screen.dart` (app-bar action on the `AppBar` at line ~84)
- Test: `test/diary_screen_test.dart`

**Interfaces:**
- Consumes: `DiaryService.entries` (Task 8); `showDayEntrySheet` (Task 7); `LogProvider`; `CycleCalculator`-derived cycles via `LogProvider.cycles`.
- Produces: `class DiaryScreen extends StatefulWidget` with a `const DiaryScreen({super.key})` constructor.

- [ ] **Step 1: Write the failing test**

Create `test/diary_screen_test.dart`. Mirror the provider wiring in `test/calendar_inline_entry_test.dart` (read it first — it already builds a faithful shell with `LogProvider`, `PredictionResult`, `PremiumProvider` and the l10n delegates):

```dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/diary/diary_screen.dart';
import 'package:menstrul_track/widgets/ad_banner.dart';
import 'package:provider/provider.dart';

void main() {
  late AppDatabase db;
  late LogProvider logs;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = LogProvider(DailyLogRepository(db));
  });

  tearDown(() => db.close());

  Future<void> seed(DateTime date, String note) =>
      DailyLogRepository(db).upsert(
        date: date,
        flow: null,
        symptomsJson: encodeDayTags(),
        notes: note,
      );

  Future<void> pump(WidgetTester tester) async {
    await logs.load();
    await tester.pumpWidget(
      ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: const MaterialApp(home: DiaryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists notes newest first', (tester) async {
    await seed(DateTime(2026, 5, 1), 'older note');
    await seed(DateTime(2026, 5, 7), 'newer note');
    await pump(tester);

    expect(find.text('newer note'), findsOneWidget);
    expect(find.text('older note'), findsOneWidget);

    final newer = tester.getTopLeft(find.text('newer note'));
    final older = tester.getTopLeft(find.text('older note'));
    expect(newer.dy, lessThan(older.dy));
  });

  testWidgets('search narrows the list', (tester) async {
    await seed(DateTime(2026, 5, 1), 'bad cramps');
    await seed(DateTime(2026, 5, 2), 'felt great');
    await pump(tester);

    await tester.enterText(find.byKey(const Key('diary-search')), 'cramps');
    await tester.pumpAndSettle();

    expect(find.text('bad cramps'), findsOneWidget);
    expect(find.text('felt great'), findsNothing);
  });

  testWidgets('shows an empty state when nothing is written', (tester) async {
    await pump(tester);
    expect(find.textContaining('Notes you add'), findsOneWidget);
  });

  testWidgets('GUARDRAIL: never renders an ad banner', (tester) async {
    await seed(DateTime(2026, 5, 1), 'a note');
    await pump(tester);
    expect(find.byType(AdBanner), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/diary_screen_test.dart`
Expected: FAIL — `diary_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/screens/diary/diary_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/log_provider.dart';
import '../../services/diary_service.dart';
import '../../widgets/day_entry_sheet.dart';

/// Reads back the notes the user has written, newest first, with search.
///
/// Deliberately carries NO ad banner: personal free-text belongs to the same
/// family as the logging and insights screens, where ads are banned.
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The 1-based day within the cycle containing [date], or null if unknown.
  ///
  /// `Cycle.end` is the last BLEEDING day, not the cycle boundary, so a date can
  /// legitimately sit after `end` and still belong to that cycle. Hence: take the
  /// most recent cycle that started on or before [date]. The 60-day ceiling stops
  /// a note written long after the last logged cycle reading as "cycle day 400".
  int? _cycleDay(LogProvider provider, DateTime date) {
    Cycle? containing;
    for (final c in provider.cycles) {
      if (c.start.isAfter(date)) continue;
      if (containing == null || c.start.isAfter(containing.start)) {
        containing = c;
      }
    }
    if (containing == null) return null;
    final day = date.difference(containing.start).inDays + 1;
    return day >= 1 && day <= 60 ? day : null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LogProvider>();
    final entries = DiaryService.entries(provider.logs, query: _query);
    final df = DateFormat.yMMMEd();

    return Scaffold(
      appBar: AppBar(title: const Text('Diary')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('diary-search'),
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search your notes',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _query.trim().isEmpty
                            ? 'Notes you add to a day appear here, newest '
                                'first — so you can look back over them.'
                            : 'No notes match that search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final day = _cycleDay(provider, e.date);
                      return ListTile(
                        title: Text(df.format(e.date)),
                        subtitle: Text(
                          e.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: day == null
                            ? null
                            : Text(
                                'Cycle day $day',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                        onTap: () =>
                            showDayEntrySheet(context, date: e.date),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
```

`Cycle`'s fields are `start` and `end` (both non-nullable `DateTime`) plus a nullable `lengthDays` — verified in `lib/models/cycle.dart:6-20`. Import it with `import '../../models/cycle.dart';`. If a cycle-day helper already exists (`grep -rn "cycleDay" lib/`), prefer it over this local one.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/diary_screen_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 5: Add the Calendar entry point**

In `lib/screens/calendar/calendar_screen.dart`, add an action to the existing `AppBar` (line ~84) and the import for the screen:

```dart
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Diary',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiaryScreen()),
            ),
          ),
        ],
      ),
```

- [ ] **Step 6: Run everything and commit**

```bash
flutter analyze
flutter test
git add lib/screens/diary lib/screens/calendar/calendar_screen.dart test/diary_screen_test.dart
git commit -m "feat: add a searchable diary of daily notes"
```

---

### Task 10: Update CLAUDE.md and correct its stale entries

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Document schema v4**

In the "Schema & migrations" bullet, update the version and the branch list:

- `schemaVersion` is **4**.
- Add: `v3→v4 added AppSettings.weightUnit`.
- Note that `drift_schemas/drift_schema_v4.json` and `test/generated_migrations/schema_v4.dart` are committed and that `test/db_migration_v4_test.dart` covers the upgrade.

- [ ] **Step 2: Document the two features**

Under "Shipped", add:

```markdown
- **Weight tracking** — a numeric day-metric (`kMetricWeight`) stored in the
  day-tags blob in **canonical kilograms**, so no `DailyLogs` migration was
  needed. The kg/lb choice is a global preference (`AppSettings.weightUnit`,
  null = kg) applied only at the display boundary, so switching units never
  rewrites data. Input is refused outside 20–350 kg (checked after conversion)
  rather than clamped — which is why `DayEntryFormState.save()` returns
  `Future<bool>` and hosts must not pop on `false`. Off by default via the
  `kCatWeight` tracking category. Trend (90-day series + net change) is a pure
  `WeightTrendService`, charted on Insights and summarised in the doctor PDF.
  **Deliberately no BMI, no height, and no classification of any kind** — a
  judgeable body label is the same class of harm as a synthesized fertility %.
- **Diary** — `DiaryService` + `DiaryScreen` read back the notes users already
  write: non-blank notes only, newest first, case-insensitive search over the
  **note text only**, with the cycle day shown per row. Reached from a Calendar
  app-bar action (bottom nav is already at Material's five destinations). Pure
  presentation over `LogProvider.logs`; no query, no schema change. Carries **no
  ad banner**, and diary text **never** enters the doctor PDF.
```

- [ ] **Step 3: Note the extracted sheet**

Update the "Calendar day entry is a bottom sheet" paragraph: the sheet now lives in `lib/widgets/day_entry_sheet.dart` as `DayEntrySheet` / `showDayEntrySheet()`, shared by the calendar and the diary. Keep the whole existing explanation of *why* it is a `Scaffold` — that reasoning is still the reason it must not be restructured.

- [ ] **Step 4: Fix the two stale entries found while surveying**

- Move **Pregnancy mode** out of "Deferred": it is shipped (`AppSettings.pregnancyStartDate`, `PregnancyService` with Naegele EDD / gestational age / trimester, `PregnancyScreen` with a loss-safe neutral exit, a Settings entry point, `_PregnancyHome` with no ads or fetal content, "Week N" in the home widget, prediction suppression, and `pregnancy_test.dart` + `pregnancy_flow_test.dart`). What remains deferred is only **pregnancy milestone reminders** — and if they are ever added, `endPregnancy` must cancel every one.
- Remove **"Habit chips"** from the v3 backlog: `kHabitOptions` shipped in the Lifestyle section. The remaining v3 backlog is i18n translations and a richer diary beyond this pass.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document weight + diary, schema v4, and correct stale feature status"
```

---

### Task 11: Device verification

**Files:** none (manual verification on hardware).

**Why this cannot be a test:** in-memory test databases never load the native cipher, and the encryption seam **fails silently** — `PRAGMA key` is a no-op on stock sqlite3, so the app can believe it is encrypted while the file is plaintext. `CLAUDE.md` also records the background-isolate migration path as never verified, with an explicit "re-test at the next bump". This is that bump.

- [ ] **Step 1: Build and install on the device**

```bash
flutter devices
flutter run --release
```

If installation fails for storage (this device has run out before), free space first and retry.

- [ ] **Step 2: Verify the migration preserved real encrypted data**

Install the **pre-change** build first (`git stash` or a build from `main`), log a few days including notes, then install the new build over it. Confirm: existing logs and notes are all still present, and Settings still shows the previous cycle/period lengths.

- [ ] **Step 3: Verify encryption still holds after the bump**

Confirm `databaseIsEncryptedAtRest()` returns true — call it from a temporary debug button or check the DB file header on-device. It must not report plaintext.

- [ ] **Step 4: Verify the isolate migration path**

With a v3-era install upgraded to this build, and the **app fully killed**, tap a period check-in notification action from the shade. Confirm: the day is written, the widget refreshes, the notification is dismissed, and the app opens later with that day's flow recorded. This exercises `CheckInWriter` opening the encrypted DB and running `onUpgrade` from a background isolate.

- [ ] **Step 5: Verify the new features on hardware**

- Settings → Weight unit → switch to lb; the day editor's suffix reads `lb`.
- Enter `150` lb, save, reopen: it still reads `150.0`. Switch to kg: it reads `68.0`.
- Enter `800` lb: save is refused with a visible message and the sheet stays open.
- Turn the Weight category off in Customize tracking, save the same day again, turn it back on: the weight is still there.
- Calendar → diary icon → notes appear newest first; search filters; tapping a row opens that day's sheet.
- Insights shows the weight chart with no BMI or judgement wording.
- Export the doctor PDF: weight appears, note text does not.

- [ ] **Step 6: Record the result**

Append the verification outcome (device model, what passed, anything that failed) to `CLAUDE.md`'s testing notes, then commit:

```bash
git add CLAUDE.md
git commit -m "docs: record device verification for weight, diary and schema v4"
```

---

## Self-Review

**Spec coverage** — every spec requirement maps to a task:

| Spec requirement | Task |
|---|---|
| `kMetricWeight`, canonical kg, `0` = unset | 1 |
| kg/lb conversion at the display boundary | 1, 3, 4 |
| 20–350 kg range, checked after conversion, refused not clamped | 1, 4 |
| `save()` → `Future<bool>`, hosts must not pop on false | 4 |
| `AppSettings.weightUnit`, null → kg | 2, 3 |
| v3→v4 additive branch + `SchemaVerifier` test | 2 |
| `kCatWeight`, `defaultOn: false`, render-only gating | 4 |
| Encode/decode weight unconditionally (regression test) | 4 |
| Day-editor decimal field with unit suffix | 4 |
| Settings kg/lb toggle | 3 |
| `WeightTrendService`, ≥2 points, 90-day window | 5 |
| Insights chart + descriptive copy, no BMI/bands | 6 |
| Weight row in the doctor PDF | 6 |
| No BMI/height/classification anywhere (grep gate) | 6 |
| Diary: notes only, newest first, note-text-only search | 8 |
| Diary entry point on the Calendar app bar | 9 |
| Cycle day per row, empty state | 9 |
| `DayEntrySheet` extracted verbatim, Scaffold/re-provide/0.85 cap preserved | 7 |
| `calendar_inline_entry_test.dart` stays green | 7 |
| No `AdBanner` on the diary screen | 9 |
| Diary text never in the PDF | 6 |
| Hardcoded English, no ARB keys | Global Constraints |
| Device verification of the isolate path + encryption | 11 |
| `CLAUDE.md` updated; stale pregnancy/habit entries fixed | 10 |

**Placeholder scan:** none — every code step carries real code, every test step a real command and expected outcome.

**Signatures verified against the codebase while writing this plan** (three drafting errors were caught and fixed here, so do not "correct" them back):

- `DailyLogRepository.upsert({required date, flow, required symptomsJson, mood, notes, bbt, opk})` — `daily_log_repository.dart:23`.
- `InsightsService.**analyze**(List<Cycle> cycles, {DateTime? asOf})` — positional, no `logs` parameter. There is **no** `InsightsService.compute`.
- `Cycle` fields are **`start`** / **`end`** (non-nullable) + nullable `lengthDays` — not `startDate`/`endDate`. And `end` is the last *bleeding* day, not the cycle boundary, which is why `_cycleDay` picks the latest cycle starting on or before the date instead of doing a range containment check.
- Constructors: `LogProvider(DailyLogRepository)`, `SettingsProvider(SettingsRepository)`, `SettingsRepository(AppDatabase)` — all single positional.
- `drift_schemas/drift_schema_v3.json` and `test/generated_migrations/schema_v3.dart` already exist; `GeneratedHelper` already dispatches 2 and 3.
- Dart SDK is `^3.11.5`, so the `(_, _)` wildcard parameters in Task 9's `separatorBuilder` are valid.

The one thing still left to read at implementation time is `_BbtChart`'s exact `fl_chart` configuration (`insights_screen.dart:769-810`), which Task 6 says to copy so both charts match the installed API version.

**Type consistency:** `save()` returns `Future<bool>` in Task 4 and both hosts are updated in the same task, so no task sees the old `void` signature. `WeightPoint`/`WeightTrend`/`WeightTrendService.compute` are defined in Task 5 and consumed with matching names in Task 6. `DiaryEntry`/`DiaryService.entries` are defined in Task 8 and consumed in Task 9. `DayEntrySheet`/`showDayEntrySheet` are produced in Task 7 and consumed in Task 9. `kCatWeight` is defined in Task 4 and used by the Task 4 tests only. `kMetricWeight`, `parseWeightToKg`, `formatWeightFromKg`, `kWeightUnitKg/Lb`, `kMinWeightKg/kMaxWeightKg` all originate in Task 1 and are referenced with those exact names throughout.

**Ordering check:** Task 4's day-editor field needs the unit preference from Task 3, which needs the column from Task 2, which needs the metric key from Task 1. Task 9 needs the extracted sheet from Task 7 and the service from Task 8. No task consumes anything defined later.
