# Expanded Tracking Categories + "Customize tracking" — Implementation Plan (Phase A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add urine, digestion, skin & hair and sleep-quality tracking plus a wider vulva & vagina list, and let users choose which categories appear in the day editor — all free, with no health surface behind the paywall.

**Architecture:** New chip groups ride the existing `DailyLogs.symptoms` JSON under reserved prefixes (`urn_`, `dig_`, `skin_`), exactly like `med_` — no migration for tracking data. Only the *category preference* needs a schema change: one nullable column on `AppSettings`, `schemaVersion` 2 → 3. Gating is render-only; decode and encode always cover every group.

**Tech Stack:** Flutter, `provider` (ChangeNotifier), `drift` 2.34 (SQLite, encrypted on-device), `flutter gen-l10n`. Tests use `AppDatabase.forTesting(NativeDatabase.memory())`; the migration test uses `SchemaVerifier` from `drift_dev/api/migrations.dart`.

**Spec:** `docs/superpowers/specs/2026-07-21-tracking-categories-design.md`

## Global Constraints

- **`encodeDayTags` is a full replace, not a merge** (`lib/common/catalog.dart:156-163`). `save()` rebuilds the JSON from form state; anything not in state at save time is destroyed.
- **Category filtering happens in `build` ONLY.** `initState` decodes every group and iterates the **unfiltered** `_metricConfigs`; `save()` re-encodes everything. Precedent: medications gate render-only at `day_entry_form.dart:264` while decoding at `:96` and re-encoding at `:120`.
- **No paywall on any surface** — no `PremiumProvider` read anywhere in this work.
- **No new dependency.**
- **New categories default OFF**, so no existing user's day editor grows unasked.
- **Chip labels stay hardcoded English** (`day_entry_form.dart` uses l10n zero times); **the settings screen must be localized** (`settings_screen.dart` uses `context.l10n` 61 times).
- **TDD** — failing test first (RED → GREEN → REFACTOR). `flutter analyze` clean, `flutter test` green.
- **Conventional Commits** (`feat:` / `test:` / `chore:` / `docs:`).
- Run all commands from `/Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track`.

**Task 0 is already complete** — `drift_schemas/drift_schema_v2.json` was dumped while the code was still at v2 and committed as `4926e66`. Do not re-dump v2; it is no longer derivable once Task 3 lands.

---

### Task 1: Catalog additions

**Files:**
- Modify: `lib/common/catalog.dart` (prefixes near line 61; `kReservedTagPrefixes` at line 65; option lists after `kHabitOptions` at line 142; widen `kVaginalOptions` at line 117; metric key near line 81)
- Test: `test/tracking_catalog_test.dart` (create)
- Test: `test/day_tags_test.dart` (modify — lines 33-43)

**Interfaces:**
- Consumes: existing `encodeDayTags`, `decodeSymptoms`, `decodeGroup`, `TrackOption`.
- Produces: `kUrineKeyPrefix`, `kDigestionKeyPrefix`, `kSkinKeyPrefix`, `kMetricSleepQuality`, `kUrineOptions`, `kDigestionOptions`, `kSkinOptions`, three new `vag_` options.

- [ ] **Step 1: Write the failing test**

```dart
// test/tracking_catalog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/catalog.dart';

void main() {
  test('new group keys are reserved and group-decodable', () {
    final json = encodeDayTags(
        flags: {'cramps', 'urn_frequent', 'dig_gas', 'skin_rash'});

    expect(decodeSymptoms(json), contains('cramps'));
    expect(decodeSymptoms(json), isNot(contains('urn_frequent')));
    expect(decodeSymptoms(json), isNot(contains('dig_gas')));
    expect(decodeSymptoms(json), isNot(contains('skin_rash')));

    expect(decodeGroup(json, kUrineKeyPrefix), {'urn_frequent'});
    expect(decodeGroup(json, kDigestionKeyPrefix), {'dig_gas'});
    expect(decodeGroup(json, kSkinKeyPrefix), {'skin_rash'});
  });

  test('sleep quality is a number, so it never reads as a symptom', () {
    final json = encodeDayTags(numbers: {kMetricSleepQuality: 4});
    expect(decodeSymptoms(json), isEmpty);
    expect(decodeNumber(json, kMetricSleepQuality), 4);
    // Distinct from sleep hours — exact-key lookup, no prefix confusion.
    expect(decodeNumber(json, kMetricSleep), isNull);
  });

  test('every option key is globally unique', () {
    final keys = [
      ...kSymptomOptions, ...kEmotionalOptions, ...kMoodOptions,
      ...kSexOptions, ...kDischargeOptions, ...kVaginalOptions,
      ...kSexualHealthOptions, ...kHabitOptions, ...kOpkOptions,
      ...kUrineOptions, ...kDigestionOptions, ...kSkinOptions,
    ].map((o) => o.key).toList();

    expect(keys.toSet().length, keys.length,
        reason: 'duplicate option key across catalog lists');
  });

  test('no NEW option label collides with an existing one', () {
    // find.text is exact-match and throws on multi-match, so a duplicate
    // label both confuses the UI and makes widget tests unwritable.
    final existing = [
      ...kSymptomOptions, ...kEmotionalOptions, ...kMoodOptions,
      ...kSexOptions, ...kDischargeOptions, ...kSexualHealthOptions,
      ...kHabitOptions,
    ].map((o) => o.label).toSet();

    final added = [
      ...kUrineOptions, ...kDigestionOptions, ...kSkinOptions,
      ...kVaginalOptions,
    ];

    for (final o in added) {
      expect(existing.contains(o.label), isFalse,
          reason: '"${o.label}" (${o.key}) duplicates an existing label');
    }
  });

  test('no new prefix would capture a pre-existing key', () {
    // A badly chosen prefix ("skin" without the underscore) would silently
    // pull existing symptoms out of decodeSymptoms and out of the doctor PDF.
    final legacy = [
      ...kSymptomOptions, ...kEmotionalOptions, ...kMoodOptions,
    ].map((o) => o.key);

    for (final p in [kUrineKeyPrefix, kDigestionKeyPrefix, kSkinKeyPrefix]) {
      for (final k in legacy) {
        expect(k.startsWith(p), isFalse,
            reason: '$k would be captured by prefix $p');
      }
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tracking_catalog_test.dart`
Expected: FAIL — `kUrineKeyPrefix` undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

In `lib/common/catalog.dart`, after `kMedicationKeyPrefix` (line 61):

```dart
const String kUrineKeyPrefix = 'urn_'; // urinary symptoms
const String kDigestionKeyPrefix = 'dig_'; // digestion / bowel
const String kSkinKeyPrefix = 'skin_'; // skin & hair
```

Add all three to `kReservedTagPrefixes` (line 65), after `kMedicationKeyPrefix`.

Add the metric key alongside the others (after line 81):

```dart
const String kMetricSleepQuality = 'sleep_quality'; // 1–5
```

Widen `kVaginalOptions` (line 117) with three entries. **`vag_swelling` must be labelled "Vulval swelling"** — plain "Swelling" already exists at line 36:

```dart
  TrackOption('vag_swelling', 'Vulval swelling'),
  TrackOption('vag_lumps', 'Lumps or bumps'),
  TrackOption('vag_discomfort', 'Discomfort'),
```

Add the three new lists after `kHabitOptions` (line 142):

```dart
/// Urinary symptoms (boolean multi-select, [kUrineKeyPrefix]).
const List<TrackOption> kUrineOptions = [
  TrackOption('urn_frequent', 'Frequent'),
  TrackOption('urn_urgency', 'Urgency'),
  TrackOption('urn_burning', 'Burning or pain'),
  TrackOption('urn_dark', 'Dark colour'),
  TrackOption('urn_cloudy', 'Cloudy'),
  TrackOption('urn_blood', 'Blood in urine'),
  TrackOption('urn_leaking', 'Leaking'),
];

/// Digestion / bowel (boolean multi-select, [kDigestionKeyPrefix]). Deliberately
/// excludes diarrhea/constipation/bloating/nausea — those are already plain
/// symptoms in [kSymptomOptions] and must not be restated under a second key.
const List<TrackOption> kDigestionOptions = [
  TrackOption('dig_gas', 'Gas'),
  TrackOption('dig_heartburn', 'Heartburn'),
  TrackOption('dig_no_bm', 'No bowel movement'),
  TrackOption('dig_loose_stool', 'Loose stool'),
  TrackOption('dig_hard_stool', 'Hard stool'),
];

/// Skin & hair (boolean multi-select, [kSkinKeyPrefix]). Excludes `acne`, which
/// is already a plain symptom.
const List<TrackOption> kSkinOptions = [
  TrackOption('skin_dry', 'Dry skin'),
  TrackOption('skin_oily', 'Oily skin'),
  TrackOption('skin_itchy', 'Itchy skin'),
  TrackOption('skin_rash', 'Rash'),
  TrackOption('skin_hair_loss', 'Hair loss'),
  TrackOption('skin_hair_oily', 'Oily hair'),
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tracking_catalog_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Harden the existing reserved-prefix test**

`test/day_tags_test.dart:33-43` hardcodes its prefix list, so new prefixes are not covered automatically. Replace that test's body so it derives from the constant and covers every present and future prefix:

```dart
  test('every reserved prefix is stripped from decodeSymptoms', () {
    for (final prefix in kReservedTagPrefixes) {
      final key = '${prefix}example';
      final json = encodeDayTags(flags: {'cramps', key});
      expect(decodeSymptoms(json), contains('cramps'));
      expect(decodeSymptoms(json), isNot(contains(key)),
          reason: '$prefix leaked into decodeSymptoms');
      expect(decodeGroup(json, prefix), {key});
    }
  });
```

- [ ] **Step 6: Run the full suite**

Run: `flutter test && flutter analyze`
Expected: all green, no analyzer issues.

- [ ] **Step 7: Commit**

```bash
git add lib/common/catalog.dart test/tracking_catalog_test.dart test/day_tags_test.dart
git commit -m "feat: add urine, digestion and skin tracking keys to the catalog"
```

---

### Task 2: Category registry

**Files:**
- Create: `lib/common/tracking_categories.dart`
- Test: `test/tracking_categories_test.dart` (create)

**Interfaces:**
- Produces: `class TrackingCategory { final String id; final String label; final bool defaultOn; }`, `const List<TrackingCategory> kTrackingCategories`, `Set<String> defaultEnabledCategoryIds()`, and one `const String kCat…` id constant per category.

**Why id constants:** Task 5 gates sections with `categories.contains(...)`. If the id string were re-typed there as a literal, a typo would silently hide a section — `Set.contains` never throws. One named constant, referenced everywhere, removes that class of bug.

- [ ] **Step 1: Write the failing test**

```dart
// test/tracking_categories_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/common/tracking_categories.dart';

void main() {
  test('ids are unique', () {
    final ids = kTrackingCategories.map((c) => c.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('the five new categories default OFF, existing ones default ON', () {
    Set<String> idsWhere(bool on) => kTrackingCategories
        .where((c) => c.defaultOn == on)
        .map((c) => c.id)
        .toSet();

    expect(idsWhere(false), {
      kCatSleepQuality,
      kCatUrine,
      kCatDigestion,
      kCatSkin,
    });
    expect(idsWhere(true), contains(kCatPhysicalSymptoms));
    expect(idsWhere(true), contains(kCatMedications));
  });

  test('defaultEnabledCategoryIds returns exactly the defaultOn ids', () {
    expect(
      defaultEnabledCategoryIds(),
      kTrackingCategories.where((c) => c.defaultOn).map((c) => c.id).toSet(),
    );
  });

  test('every category has a non-empty label', () {
    for (final c in kTrackingCategories) {
      expect(c.label.trim(), isNotEmpty, reason: '${c.id} has no label');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tracking_categories_test.dart`
Expected: FAIL — file `tracking_categories.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/common/tracking_categories.dart

/// A day-editor section the user can show or hide from Settings › Customize
/// tracking. Hiding affects RENDERING ONLY — the day editor still decodes and
/// re-encodes every group, so a hidden category never loses logged data.
///
/// Deliberately NOT toggleable, and therefore absent from this list: Flow,
/// "Period ended today", Pain, BBT/OPK and Notes. Those are the app's core
/// cycle and fertility data — hiding them would break its primary function.
class TrackingCategory {
  const TrackingCategory(this.id, this.label, {this.defaultOn = true});

  final String id;
  final String label;

  /// New categories ship OFF so no existing user's day editor grows unasked.
  final bool defaultOn;
}

const String kCatPhysicalSymptoms = 'physical_symptoms';
const String kCatEmotional = 'emotional';
const String kCatSex = 'sex';
const String kCatDischarge = 'discharge';
const String kCatVaginal = 'vaginal';
const String kCatSexualHealth = 'sexual_health';
const String kCatLifestyle = 'lifestyle';
const String kCatWellbeing = 'wellbeing';
const String kCatMedications = 'medications';
const String kCatSleepQuality = 'sleep_quality';
const String kCatUrine = 'urine';
const String kCatDigestion = 'digestion';
const String kCatSkin = 'skin';

const List<TrackingCategory> kTrackingCategories = [
  TrackingCategory(kCatPhysicalSymptoms, 'Physical symptoms'),
  TrackingCategory(kCatEmotional, 'Emotional symptoms'),
  TrackingCategory(kCatSex, 'Sexual activity'),
  TrackingCategory(kCatDischarge, 'Discharge'),
  TrackingCategory(kCatVaginal, 'Vulva & vagina'),
  TrackingCategory(kCatSexualHealth, 'Sexual health'),
  TrackingCategory(kCatLifestyle, 'Lifestyle'),
  TrackingCategory(kCatWellbeing, 'Water, sleep, energy & stress'),
  TrackingCategory(kCatMedications, 'Medications'),
  TrackingCategory(kCatSleepQuality, 'Sleep quality', defaultOn: false),
  TrackingCategory(kCatUrine, 'Urine', defaultOn: false),
  TrackingCategory(kCatDigestion, 'Digestion', defaultOn: false),
  TrackingCategory(kCatSkin, 'Skin & hair', defaultOn: false),
];

/// The ids enabled for a user who has never opened Customize tracking.
Set<String> defaultEnabledCategoryIds() =>
    {for (final c in kTrackingCategories) if (c.defaultOn) c.id};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tracking_categories_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/common/tracking_categories.dart test/tracking_categories_test.dart
git commit -m "feat: add the tracking-category registry"
```

---

### Task 3: Schema column + v2→v3 migration

**Files:**
- Modify: `lib/db/tables.dart` (add column to `AppSettings`, after line 77)
- Modify: `lib/db/database.dart` (`schemaVersion` line 21; `onUpgrade` lines 35-39)
- Generate: `lib/db/database.g.dart`, `drift_schemas/drift_schema_v3.json`, `test/generated_migrations/`
- Test: `test/db_migration_v3_test.dart` (create)

**Interfaces:**
- Produces: `AppSetting.trackingCategories` (`String?`) and `AppSettingsCompanion.trackingCategories`, consumed by Task 4.

**Why an in-memory test is not acceptable here:** `AppDatabase.forTesting(NativeDatabase.memory())` runs `onCreate` → `createAll()` against the *current* schema and never executes `onUpgrade`. Such a test passes whether or not the migration exists. It must not be written.

- [ ] **Step 1: Add the column and bump the version**

In `lib/db/tables.dart`, inside `class AppSettings` after `pregnancyStartDate` (line 77):

```dart
  // Enabled day-editor categories as a JSON array of ids (see
  // common/tracking_categories.dart). NULL means "use defaults", so existing
  // rows need no backfill.
  TextColumn get trackingCategories => text().nullable()();
```

In `lib/db/database.dart` line 21:

```dart
  int get schemaVersion => 3;
```

and extend `onUpgrade` (line 35), keeping the existing v2 branch:

```dart
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(appSettings, appSettings.pregnancyStartDate);
          }
          if (from < 3) {
            await m.addColumn(appSettings, appSettings.trackingCategories);
          }
        },
```

- [ ] **Step 2: Regenerate drift output and capture the v3 snapshot**

```bash
dart run build_runner build --delete-conflicting-outputs
dart run drift_dev schema dump lib/db/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

Confirm `drift_schemas/drift_schema_v3.json` now exists alongside the v2 file, and that `test/generated_migrations/schema.dart` exports a `GeneratedHelper` class. Open that file and note the exact class name — use it verbatim in Step 3.

- [ ] **Step 3: Write the failing migration test**

```dart
// test/db_migration_v3_test.dart
import 'package:drift_dev/api/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';

/// The v2→v3 upgrade must ADD the column without disturbing existing rows.
/// Seeds NON-DEFAULT values on purpose: asserting that defaults survive would
/// also pass against a wipe-and-recreate migration.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v2 -> v3 adds trackingCategories and preserves existing data',
      () async {
    final connection = await verifier.startAt(2);

    await connection.executor.runCustom(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, premium) '
      'VALUES (0, 31, 7, 1)',
      const [],
    );
    await connection.executor.runCustom(
      "INSERT INTO daily_logs (date, symptoms) VALUES (?, ?)",
      [DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000, '{"cramps":true}'],
    );

    final db = AppDatabase.forTesting(connection);
    await verifier.migrateAndValidate(db, 3);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 31);
    expect(settings.defaultPeriodLength, 7);
    expect(settings.premium, isTrue);
    expect(settings.trackingCategories, isNull); // null => use defaults

    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, contains('cramps'));

    await db.close();
  });
}
```

> If `daily_logs` column names or the date encoding differ from the above, read `drift_schemas/drift_schema_v2.json` — it lists every v2 column name and type verbatim — and adjust the raw SQL to match. Do not change the assertions.

- [ ] **Step 4: Run the test**

Run: `flutter test test/db_migration_v3_test.dart`
Expected: PASS. If it fails on schema mismatch, the `onUpgrade` branch or the regeneration in Step 2 is wrong — fix that, not the test.

- [ ] **Step 5: Run the full suite**

Run: `flutter test && flutter analyze`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/db/ drift_schemas/ test/generated_migrations/ test/db_migration_v3_test.dart
git commit -m "feat(db): add trackingCategories column with v2->v3 migration"
```

---

### Task 4: SettingsProvider category preference

**Files:**
- Modify: `lib/providers/settings_provider.dart` (add getter + setter alongside the existing getters)
- Test: `test/settings_categories_test.dart` (create)

**Interfaces:**
- Consumes: `AppSetting.trackingCategories` (Task 3); `defaultEnabledCategoryIds()`, `kCat…` constants (Task 2); existing `update(AppSettingsCompanion)` (`settings_provider.dart:44`).
- Produces: `Set<String> get enabledCategories` and `Future<void> setCategoryEnabled(String id, bool on)`, consumed by Tasks 5 and 6.

**Critical decoding rule:** an **empty** stored array means "the user turned everything off" and must stay empty. Only `null` falls back to defaults. Treating empty as "unset" would resurrect every category the user just disabled.

- [ ] **Step 1: Write the failing test**

```dart
// test/settings_categories_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/settings_provider.dart';

void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  test('a null column falls back to the registry defaults', () {
    expect(settings.enabledCategories, defaultEnabledCategoryIds());
    expect(settings.enabledCategories, isNot(contains(kCatUrine)));
    expect(settings.enabledCategories, contains(kCatPhysicalSymptoms));
  });

  test('enabling a category round-trips through the database', () async {
    await settings.setCategoryEnabled(kCatUrine, true);
    expect(settings.enabledCategories, contains(kCatUrine));

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, contains(kCatUrine));
  });

  test('disabling a default-on category round-trips', () async {
    await settings.setCategoryEnabled(kCatLifestyle, false);
    expect(settings.enabledCategories, isNot(contains(kCatLifestyle)));

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, isNot(contains(kCatLifestyle)));
  });

  test('turning everything off persists as empty, NOT as reset-to-defaults',
      () async {
    for (final c in kTrackingCategories) {
      await settings.setCategoryEnabled(c.id, false);
    }
    expect(settings.enabledCategories, isEmpty);

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, isEmpty,
        reason: 'empty must not be treated as unset');
  });

  test('an unknown id stored by a future version is ignored, not crashed on',
      () async {
    await settings.update(const AppSettingsCompanion(
      trackingCategories: Value('["urine","not_a_real_category"]'),
    ));
    await settings.load();
    expect(settings.enabledCategories, contains(kCatUrine));
    expect(settings.enabledCategories, isNot(contains('not_a_real_category')));
  });

  test('malformed JSON falls back to defaults instead of throwing', () async {
    await settings.update(
        const AppSettingsCompanion(trackingCategories: Value('{not json')));
    await settings.load();
    expect(settings.enabledCategories, defaultEnabledCategoryIds());
  });
}
```

Add these imports at the top of the test for the last two cases:

```dart
import 'package:drift/drift.dart' show Value;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/settings_categories_test.dart`
Expected: FAIL — `enabledCategories` is not defined for `SettingsProvider`.

- [ ] **Step 3: Write minimal implementation**

Add `import 'dart:convert';` and `import '../common/tracking_categories.dart';` to `lib/providers/settings_provider.dart`, then add alongside the other getters:

```dart
  /// Day-editor categories the user has switched on. A NULL column means the
  /// user has never customised this, so the registry defaults apply. An EMPTY
  /// array means they turned everything off — that is a real choice and must
  /// not be reset to defaults. Unknown ids (written by a newer build) and
  /// malformed JSON are ignored.
  Set<String> get enabledCategories {
    final raw = _settings?.trackingCategories;
    if (raw == null) return defaultEnabledCategoryIds();

    final known = {for (final c in kTrackingCategories) c.id};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return defaultEnabledCategoryIds();
      return {
        for (final e in decoded)
          if (e is String && known.contains(e)) e,
      };
    } on FormatException {
      return defaultEnabledCategoryIds();
    }
  }

  Future<void> setCategoryEnabled(String id, bool on) {
    final next = {...enabledCategories};
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return update(AppSettingsCompanion(
      trackingCategories: Value(jsonEncode(next.toList())),
    ));
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/settings_categories_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Confirm old backups still restore**

Add to `test/settings_backup_test.dart` — a pre-v3 `.lunabak` has no `trackingCategories` key:

```dart
  test('settings JSON without trackingCategories restores as null', () {
    final row = AppSetting.fromJson(const {
      'id': 0,
      'mode': 0,
      'defaultCycleLength': 28,
      'defaultPeriodLength': 5,
      'themeMode': 'system',
      'language': 'en',
      'genderNeutralLanguage': false,
      'appLockEnabled': false,
      'premium': false,
      'onboardingComplete': true,
    });
    expect(row.trackingCategories, isNull);
  });
```

- [ ] **Step 6: Run the full suite and commit**

```bash
flutter test && flutter analyze
git add lib/providers/settings_provider.dart test/settings_categories_test.dart test/settings_backup_test.dart
git commit -m "feat: persist which tracking categories the user has enabled"
```

---

### Task 5: Day editor gating + the three new chip groups

**Files:**
- Modify: `lib/widgets/day_entry_form.dart`
- Modify: `lib/screens/log/day_log_screen.dart` (the `DayEntryForm(...)` call)
- Modify: `lib/screens/calendar/calendar_screen.dart` (the `DayEntryForm(...)` call)
- Test: `test/day_entry_form_categories_test.dart` (create)

**Interfaces:**
- Consumes: `kCat…` constants and `kTrackingCategories` (Task 2); `SettingsProvider.enabledCategories` (Task 4); the new option lists and `kMetricSleepQuality` (Task 1); existing `_SectionLabel(String)`, `_FilterChips({options, isSelected, onToggle})`, `_MetricSlider`.
- Produces: `DayEntryForm({..., Set<String> categories})` and top-level `Set<String> visibleCategories(BuildContext)`.

**Naming:** the helper is `visibleCategories`, **not** `enabledCategories` — that name is already the `SettingsProvider` getter, and the two have deliberately different fallbacks.

**Fallback:** `visibleCategories` returns **every** id when no `SettingsProvider` is in scope. It must **not** copy `enabledMedChips`' empty-set fallback (`day_entry_form.dart:47-54`) — `DayLogScreen` and `CalendarScreen` pass this value straight through, and an empty set would blank every chip group in the ~10 existing widget tests that pump those screens without a `SettingsProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/day_entry_form_categories_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/catalog.dart';
import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/log_provider.dart';
import 'package:menstrul_track/screens/log/day_log_screen.dart';
import 'package:menstrul_track/widgets/day_entry_form.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;
  late LogProvider logs;
  final date = DateTime(2026, 4, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
    logs = LogProvider(repo);
    await logs.load();
  });
  tearDown(() => db.close());

  Widget wrap(Widget child) => ChangeNotifierProvider<LogProvider>.value(
        value: logs,
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('an enabled category renders its section', (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: {kCatUrine},
    )));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Urine'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Urine'), findsOneWidget);
    expect(find.text('Blood in urine'), findsOneWidget);
  });

  testWidgets('a disabled category renders nothing', (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: const {},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Urine'), findsNothing);
    expect(find.text('Blood in urine'), findsNothing);
    expect(find.text('Lifestyle'), findsNothing);
  });

  testWidgets('a new group round-trips through save', (tester) async {
    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: {kCatUrine},
    )));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Frequent'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frequent'));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    expect(decodeGroup(logs.logForDate(date)?.symptoms, kUrineKeyPrefix),
        {'urn_frequent'});
  });

  // THE critical test: the numeric path is where gating can silently erase
  // data, because _metricConfigs feeds BOTH initState decode and build render.
  testWidgets('a DISABLED metric keeps its stored value across a save',
      (tester) async {
    await repo.upsert(
      date: date,
      flow: null,
      symptomsJson: encodeDayTags(numbers: {kMetricSleep: 8}),
    );
    await logs.load();

    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: const {}, // wellbeing OFF -> sleep slider not rendered
    )));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    expect(decodeNumber(logs.logForDate(date)?.symptoms, kMetricSleep), 8,
        reason: 'gating must be render-only; initState must decode everything');
  });

  testWidgets('a DISABLED chip group keeps its stored values across a save',
      (tester) async {
    await repo.upsert(
      date: date,
      flow: null,
      symptomsJson: encodeDayTags(flags: {'urn_frequent', 'habit_exercise'}),
    );
    await logs.load();

    final key = GlobalKey<DayEntryFormState>();
    await tester.pumpWidget(wrap(DayEntryForm(
      key: key,
      date: date,
      categories: const {},
    )));
    await tester.pumpAndSettle();
    await key.currentState!.save();

    final saved = logs.logForDate(date)?.symptoms;
    expect(decodeGroup(saved, kUrineKeyPrefix), {'urn_frequent'});
    expect(decodeGroup(saved, kHabitKeyPrefix), {'habit_exercise'});
  });

  testWidgets('DayLogScreen with no SettingsProvider renders every category',
      (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<LogProvider>.value(
      value: logs,
      child: MaterialApp(home: DayLogScreen(date: date)),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.dragUntilVisible(
      find.text('Lifestyle'), find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Lifestyle'), findsOneWidget);
  });

  testWidgets('medications need BOTH the category on and a configured med',
      (tester) async {
    await tester.pumpWidget(wrap(DayEntryForm(
      date: date,
      categories: const {},
      medications: const [MedChip(1, 'Iron')],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Iron'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/day_entry_form_categories_test.dart`
Expected: FAIL — no `categories` parameter on `DayEntryForm`.

- [ ] **Step 3: Write minimal implementation**

In `lib/widgets/day_entry_form.dart`:

Add the import `import '../common/tracking_categories.dart';` and `import '../providers/settings_provider.dart';`.

Add the constructor parameter:

```dart
  const DayEntryForm({
    super.key,
    required this.date,
    this.shrinkWrap = false,
    this.medications = const [],
    this.categories = kAllCategoryIds,
  });

  final DateTime date;
  final bool shrinkWrap;
  final List<MedChip> medications;

  /// Which sections to RENDER. Defaults to everything so the form stays
  /// pumpable without a SettingsProvider. Gating never affects decode/encode.
  final Set<String> categories;
```

Add next to `enabledMedChips`:

```dart
/// Every category id — the fail-open default for [DayEntryForm.categories].
final Set<String> kAllCategoryIds = {
  for (final c in kTrackingCategories) c.id,
};

/// Categories the user has switched on, or ALL of them when no
/// [SettingsProvider] is in scope. Deliberately fails OPEN: an empty set here
/// would blank every section for callers that pump a screen without settings.
Set<String> visibleCategories(BuildContext context) {
  final settings = context.watch<SettingsProvider?>();
  if (settings == null || !settings.loaded) return kAllCategoryIds;
  return settings.enabledCategories;
}
```

Add three state sets next to `_medications`:

```dart
  final Set<String> _urine = {};
  final Set<String> _digestion = {};
  final Set<String> _skin = {};
```

Decode them **unconditionally** in `initState`, after the `_medications` line (`:96`):

```dart
    _urine.addAll(decodeGroup(tags, kUrineKeyPrefix));
    _digestion.addAll(decodeGroup(tags, kDigestionKeyPrefix));
    _skin.addAll(decodeGroup(tags, kSkinKeyPrefix));
```

Add them to the `flags` set in `save()` (`:115`), after `..._medications`:

```dart
      ..._urine,
      ..._digestion,
      ..._skin,
```

Add sleep quality to `_metricConfigs` (`:57`) — **do not filter this list here**:

```dart
  (label: 'Sleep quality', key: kMetricSleepQuality, max: 5, suffix: '/5'),
```

In `build`, wrap each existing section in its category check, e.g. the habits block at `:257`:

```dart
        if (widget.categories.contains(kCatLifestyle)) ...[
          // ...existing Lifestyle _SectionLabel + _FilterChips unchanged...
        ],
```

Apply the same pattern with `kCatPhysicalSymptoms`, `kCatEmotional`, `kCatSex`, `kCatDischarge`, `kCatVaginal`, `kCatSexualHealth`, and add `widget.categories.contains(kCatMedications) &&` to the existing medications condition at `:264`.

Render the three new groups from one loop — they are structurally identical, so hand-copying three blocks would be needless duplication:

```dart
        for (final g in [
          (kCatUrine, 'Urine', kUrineOptions, _urine),
          (kCatDigestion, 'Digestion', kDigestionOptions, _digestion),
          (kCatSkin, 'Skin & hair', kSkinOptions, _skin),
        ])
          if (widget.categories.contains(g.$1)) ...[
            const SizedBox(height: 20),
            _SectionLabel(g.$2),
            _FilterChips(
              options: g.$3,
              isSelected: g.$4.contains,
              onToggle: (key, sel) =>
                  setState(() => sel ? g.$4.add(key) : g.$4.remove(key)),
            ),
          ],
```

Give the previously unlabelled slider block a header and filter it **in `build` only** (`:277`):

```dart
        if (widget.categories.contains(kCatWellbeing) ||
            widget.categories.contains(kCatSleepQuality)) ...[
          const SizedBox(height: 20),
          _SectionLabel('Wellbeing'),
        ],
        for (final m in _metricConfigs)
          if (widget.categories.contains(
              m.key == kMetricSleepQuality ? kCatSleepQuality : kCatWellbeing))
            _MetricSlider(
              label: m.label,
              value: _metrics[m.key] ?? 0,
              max: m.max,
              suffix: m.suffix,
              onChanged: (v) => setState(() => _metrics[m.key] = v),
            ),
```

- [ ] **Step 4: Wire the two callers**

In `lib/screens/log/day_log_screen.dart`:

```dart
      body: DayEntryForm(
        key: _formKey,
        date: widget.date,
        medications: enabledMedChips(context),
        categories: visibleCategories(context),
      ),
```

In `lib/screens/calendar/calendar_screen.dart`:

```dart
            Expanded(
              child: DayEntryForm(
                key: _formKey,
                date: widget.date,
                medications: enabledMedChips(context),
                categories: visibleCategories(context),
              ),
            ),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/day_entry_form_categories_test.dart`
Expected: PASS (7 tests).

Then the full suite: `flutter test`. If any pre-existing widget test goes red, `visibleCategories` is failing closed — re-read Step 3's fallback rule rather than editing the old tests.

- [ ] **Step 6: Analyzer and commit**

```bash
flutter analyze
git add lib/widgets/day_entry_form.dart lib/screens/log/day_log_screen.dart lib/screens/calendar/calendar_screen.dart test/day_entry_form_categories_test.dart
git commit -m "feat: gate day-editor sections by tracking category"
```

---

### Task 6: "Customize tracking" settings screen

**Files:**
- Create: `lib/screens/settings/tracking_categories_screen.dart`
- Modify: `lib/l10n/app_en.arb` (add keys)
- Modify: `lib/screens/settings/settings_screen.dart` (entry point near the Medications tile at line 322)
- Test: `test/tracking_categories_screen_test.dart` (create)

**Interfaces:**
- Consumes: `kTrackingCategories` (Task 2); `SettingsProvider.enabledCategories` / `setCategoryEnabled` (Task 4); existing `context.l10n` extension (`lib/common/l10n.dart:9`).

**Copy rule:** the screen must **not** claim the data appears in Insights or the doctor PDF. Neither is true for prefixed groups — `decodeSymptoms` strips them. The only accurate promise in Phase A is that the data stays on the device.

- [ ] **Step 1: Add the l10n keys**

In `lib/l10n/app_en.arb`, alongside the other `settings*` keys:

```json
  "settingsTrackingTitle": "Customize tracking",
  "settingsTrackingSubtitle": "Choose what appears when you log a day",
  "settingsTrackingNote": "Turning a category off only hides it from the day editor. Anything you've already logged is kept on this device.",
```

Regenerate: `flutter gen-l10n`

- [ ] **Step 2: Write the failing test**

```dart
// test/tracking_categories_screen_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:menstrul_track/common/tracking_categories.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/l10n/app_localizations.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/settings/tracking_categories_screen.dart';
import 'package:menstrul_track/theme/app_theme.dart';

void main() {
  late AppDatabase db;
  late SettingsProvider settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsProvider(SettingsRepository(db));
    await settings.load();
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider<SettingsProvider>.value(
      value: settings,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TrackingCategoriesScreen(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every category and reflects the defaults',
      (tester) async {
    await pump(tester);
    expect(find.byType(SwitchListTile), findsNWidgets(kTrackingCategories.length));

    SwitchListTile tileFor(String label) =>
        tester.widget<SwitchListTile>(find.ancestor(
          of: find.text(label),
          matching: find.byType(SwitchListTile),
        ));

    expect(tileFor('Urine').value, isFalse);
    expect(tileFor('Physical symptoms').value, isTrue);
  });

  testWidgets('toggling a switch persists the choice', (tester) async {
    await pump(tester);

    await tester.dragUntilVisible(
      find.text('Urine'), find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urine'));
    await tester.pumpAndSettle();

    expect(settings.enabledCategories, contains(kCatUrine));

    final reloaded = SettingsProvider(SettingsRepository(db));
    await reloaded.load();
    expect(reloaded.enabledCategories, contains(kCatUrine));
  });

  testWidgets('does not promise Insights or PDF visibility', (tester) async {
    await pump(tester);
    expect(find.textContaining('Insights'), findsNothing);
    expect(find.textContaining('PDF'), findsNothing);
    expect(find.textContaining('doctor'), findsNothing);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/tracking_categories_screen_test.dart`
Expected: FAIL — `tracking_categories_screen.dart` does not exist.

- [ ] **Step 4: Write minimal implementation**

```dart
// lib/screens/settings/tracking_categories_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/l10n.dart';
import '../../common/tracking_categories.dart';
import '../../providers/settings_provider.dart';

/// Lets the user choose which sections appear in the day editor. Hiding a
/// category is a display choice only — logged data is never deleted, which is
/// what the note below the title promises (and all it promises: prefixed groups
/// do not reach Insights or the doctor PDF).
class TrackingCategoriesScreen extends StatelessWidget {
  const TrackingCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final enabled = settings.enabledCategories;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsTrackingTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              context.l10n.settingsTrackingNote,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          for (final c in kTrackingCategories)
            SwitchListTile(
              title: Text(c.label),
              value: enabled.contains(c.id),
              onChanged: (v) => settings.setCategoryEnabled(c.id, v),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Add the Settings entry point**

In `lib/screens/settings/settings_screen.dart`, import the new screen and add a `ListTile` directly after the Medications tile (line 328), matching the surrounding pattern exactly:

```dart
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(context.l10n.settingsTrackingTitle),
            subtitle: Text(context.l10n.settingsTrackingSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const TrackingCategoriesScreen()),
            ),
          ),
```

- [ ] **Step 6: Run tests and commit**

```bash
flutter test && flutter analyze
git add lib/screens/settings/ lib/l10n/ test/tracking_categories_screen_test.dart
git commit -m "feat: add the Customize tracking settings screen"
```

---

### Task 7: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Suite and analyzer**

```bash
flutter test
flutter analyze
```
Expected: all green (246 before this plan, plus the new tests), no analyzer issues.

- [ ] **Step 2: Build**

```bash
flutter build apk --debug
```

- [ ] **Step 3: Migration on real hardware — the only real evidence**

In-memory tests never load sqlite3mc, so the encrypted-file migration is unproven until this runs. Install **over** the existing build; do **not** uninstall first:

```bash
adb -s cdc8bb52 install -r build/app/outputs/flutter-apk/app-debug.apk
```

Open the app and confirm the June 1–3 logs, the July 1 log and the "Vitamin D" medication all survive.

- [ ] **Step 4: Background-isolate migration**

`CheckInWriter` opens a bare `AppDatabase()` from a notification action with the app killed, so the migration may first run there with no UI to report failure. After the install-over in Step 3 but **before** opening the app, tap a check-in action in the notification shade if one is pending; then open the app and confirm settings and logs are intact.

- [ ] **Step 5: Device smoke**

- Settings → Customize tracking → confirm Urine, Digestion, Skin & hair and Sleep quality are **off** by default.
- Enable all four → open a calendar day → confirm the three chip groups render with section headers and the Sleep quality slider appears.
- Log one item from each group plus a Sleep quality value → Save → reopen the day → confirm all persisted.
- **The data-loss path:** disable Urine, reopen that day, change something unrelated, Save, then re-enable Urine and reopen — the urine selection must still be there.
- Turn every category off → confirm the day editor still shows Flow, Pain, BBT/OPK and Notes, and that reopening Settings shows everything still off (not silently reset to defaults).

- [ ] **Step 6: Commit any verification fixes**

```bash
git add -A
git commit -m "chore: verify tracking categories on device"
```

---

## Self-Review

**Spec coverage:**
- Tracking stays free → no `PremiumProvider` read in any task. ✅
- New categories (urine/digestion/skin/sleep quality) → Task 1 + Task 5. ✅
- Widened vulva & vagina → Task 1. ✅
- Customize tracking screen → Task 6. ✅
- Category preference persistence + migration → Tasks 3 & 4. ✅
- Data-loss constraint (render-only gating) → Task 5 Step 3, tested in Task 5 Step 1 (both metric and chip paths). ✅
- Accurate copy → Task 6 Step 1 + the negative test in Step 2. ✅
- Localization → Task 6 Step 1. ✅
- Phase B (Insights, PDF, export sheet) → explicitly out of scope. ✅

**Placeholder scan:** none — every step carries the code or command it needs. Task 3 Step 3 contains one conditional instruction (adjust raw SQL to the v2 snapshot if column names differ), which is a verification step against a committed artefact, not a TBD.

**Type consistency:**
- `TrackingCategory(id, label, {defaultOn})` defined Task 2, consumed Tasks 4/5/6. ✅
- `defaultEnabledCategoryIds()` defined Task 2, used Task 4. ✅
- `enabledCategories` / `setCategoryEnabled(String, bool)` defined Task 4, used Tasks 5/6. ✅
- `visibleCategories(BuildContext)` and `kAllCategoryIds` defined Task 5, used in both callers — distinct from the provider getter by name and by fallback. ✅
- `kUrineOptions` / `kDigestionOptions` / `kSkinOptions` and `kMetricSleepQuality` defined Task 1, consumed Task 5. ✅
- `MedChip(int, String)` and `enabledMedChips(BuildContext)` are pre-existing (shipped `51cb865`) and used unchanged. ✅
