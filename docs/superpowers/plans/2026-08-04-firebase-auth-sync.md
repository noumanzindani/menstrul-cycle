# Firebase Auth + Firestore Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add required email/password accounts and cross-device sync of daily logs and settings to LunaTrack, mirroring the local drift database into a per-user Firestore subtree.

**Architecture:** Drift stays the single source of truth for every UI read and write; a `SyncService` mirrors `DailyLogs` and `AppSettings` to `users/{uid}` in a **named** Firestore database (`lunatrack`) inside the shared `hbgapp-c3c88` project. Conflicts resolve last-write-wins per day document on the `updatedAt` column that `DailyLogs` already maintains. Deletions propagate via a new `SyncTombstones` table rather than a soft-delete flag.

**Tech Stack:** Flutter 3.41.9, drift 2.34, provider, `firebase_core` / `firebase_auth` / `cloud_firestore`, Firebase emulator + `@firebase/rules-unit-testing` for security-rule tests.

**Spec:** `docs/superpowers/specs/2026-08-04-firebase-auth-sync-design.md`

## Global Constraints

- Firebase project: **`hbgapp-c3c88`**. Firestore database: **`lunatrack`** (named, NOT `(default)`).
- **Never call `FirebaseFirestore.instance`** anywhere in `lib/` — it targets `(default)`, the wrong database under the wrong ruleset. All access goes through `lunaFirestore()` in `lib/services/firestore_ref.dart`.
- Android app registers as **`com.lunatrack.app`** (the `applicationId`), not the `com.example.menstrul_track` namespace.
- Auth provider: **Email/Password only**. Do NOT disable other providers in the Firebase console — provider settings are project-wide and four unrelated apps share this project.
- `minSdk` is already **26**; do not change it.
- Security rules must use `request.auth.uid == userId`, **never** a bare `request.auth != null`.
- Drift migrations use independent `if (from < n)` branches (never `else if`), additive only.
- **A drift schema snapshot must be dumped for version N while N is still current.** `drift_schema_v4.json` already exists, so v4→v5 is testable; dump v5 immediately after the bump so v6 is testable later.
- The existing 308-test suite must stay green after every task. Sync is additive; an existing failure means the mirror leaked into the primary read/write path.
- Sync `DailyLogs` and `AppSettings` only. Never sync `Reminders`, `Medications`, or `PeriodEntries`.
- Commit after every task using Conventional Commits (`feat:` / `fix:` / `docs:` / `test:`).

---

### Task 1: Firebase project setup, dependencies, and the single database accessor

Wires the app to Firebase and locks in the named-database invariant before any feature code can get it wrong.

**Files:**
- Create: `lib/services/firestore_ref.dart`
- Create: `test/firestore_ref_test.dart`
- Modify: `pubspec.yaml` (dependencies)
- Modify: `android/settings.gradle.kts` (plugins block)
- Modify: `android/app/build.gradle.kts` (plugins block)
- Modify: `lib/main.dart:32-43` (`main()`)
- Replace: `android/app/google-services.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `FirebaseFirestore lunaFirestore()` — the only Firestore accessor in the app. `const String kLunaDatabaseId = 'lunatrack'`.

- [ ] **Step 1: Console setup (manual, in the Firebase console)**

These are console actions, not code. Do them first — later steps fail without them.

1. Open project `hbgapp-c3c88` → **Firestore Database** → note the location of the existing `(default)` database.
2. **Create database** → database ID `lunatrack` → **same location as `(default)`** → start in *production mode* (locked). Location cannot be changed later.
3. **Authentication** → **Sign-in method** → enable **Email/Password**. Leave every other provider exactly as it is.
4. **Project settings** → **Add app** → Android → package name **`com.lunatrack.app`** → register → download `google-services.json`.

- [ ] **Step 2: Replace the stale google-services.json**

The file currently at `android/app/google-services.json` belongs to an unrelated project (`rwp-ride-with-purpose`). Delete it and drop in the file downloaded in Step 1.

```bash
rm android/app/google-services.json
mv ~/Downloads/google-services.json android/app/google-services.json
python3 -c "
import json; d=json.load(open('android/app/google-services.json'))
print('project:', d['project_info']['project_id'])
print('packages:', [c['client_info']['android_client_info']['package_name'] for c in d['client']])
"
```

Expected output: `project: hbgapp-c3c88` and `packages: ['com.lunatrack.app']`. If the package is anything else, the Gradle plugin will fail the build with "No matching client found".

- [ ] **Step 3: Add the Flutter dependencies**

```bash
flutter pub add firebase_core firebase_auth cloud_firestore
```

- [ ] **Step 4: Add the Google Services Gradle plugin**

In `android/settings.gradle.kts`, add to the existing `plugins { … }` block (after the `org.jetbrains.kotlin.android` line):

```kotlin
    id("com.google.gms.google-services") version "4.4.2" apply false
```

In `android/app/build.gradle.kts`, add to the existing `plugins { … }` block (after `dev.flutter.flutter-gradle-plugin`):

```kotlin
    id("com.google.gms.google-services")
```

- [ ] **Step 5: Write the failing test for the database accessor**

Create `test/firestore_ref_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/firestore_ref.dart';

/// LunaTrack MUST NOT use the `(default)` Firestore database: `hbgapp-c3c88` is
/// shared with four unrelated apps, and `(default)` has ONE project-wide
/// ruleset. A named database carries its own rules. This test pins the id so a
/// rename can't silently move menstrual data under someone else's rules.
void main() {
  test('the LunaTrack database id is the named database, not (default)', () {
    expect(kLunaDatabaseId, 'lunatrack');
    expect(kLunaDatabaseId, isNot('(default)'));
  });
}
```

- [ ] **Step 6: Run the test to verify it fails**

Run: `flutter test test/firestore_ref_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:menstrul_track/services/firestore_ref.dart'`.

- [ ] **Step 7: Write the accessor**

Create `lib/services/firestore_ref.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// The named Firestore database LunaTrack owns.
///
/// The Firebase project (`hbgapp-c3c88`) is shared with four unrelated apps.
/// Firestore's `(default)` database has exactly ONE ruleset for the whole
/// project, so a permissive rule written for any of those apps would expose
/// LunaTrack's menstrual logs. A NAMED database carries its own independent
/// ruleset, which is the only isolation available without a new project.
const String kLunaDatabaseId = 'lunatrack';

/// The ONLY Firestore handle the app may use.
///
/// `FirebaseFirestore.instance` targets `(default)` — using it anywhere writes
/// health data to the wrong database under the wrong rules. Always call this.
FirebaseFirestore lunaFirestore() => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: kLunaDatabaseId,
    );
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `flutter test test/firestore_ref_test.dart`
Expected: PASS.

- [ ] **Step 9: Initialise Firebase in main()**

In `lib/main.dart`, add the import alongside the existing ones:

```dart
import 'package:firebase_core/firebase_core.dart';
```

Then in `main()`, immediately after `WidgetsFlutterBinding.ensureInitialized();` and **before** `NotificationService.init(...)`:

```dart
  // Must complete before any Firebase service is touched. Reads
  // android/app/google-services.json at build time.
  await Firebase.initializeApp();
```

- [ ] **Step 10: Verify the app still builds and the suite is green**

```bash
flutter analyze
flutter test
flutter build apk --debug
```

Expected: analyze clean, all tests pass (309 now: 308 + the new one), APK builds. A "No matching client found for package name" Gradle error means Step 2 used the wrong `google-services.json`.

- [ ] **Step 11: Document the gitignored config file**

`google-services.json` is gitignored (`.gitignore:48`), so a fresh clone cannot build. Add to `README.md` under a new `## Firebase setup` heading:

```markdown
## Firebase setup

`android/app/google-services.json` is intentionally gitignored (it identifies the
Firebase project). To build from a fresh clone, download it from the Firebase
console: project `hbgapp-c3c88` → Project settings → the `com.lunatrack.app`
Android app → `google-services.json`, and place it at `android/app/`.

LunaTrack uses the **named** Firestore database `lunatrack`, not `(default)`.
```

- [ ] **Step 12: Commit**

```bash
git add pubspec.yaml pubspec.lock android/settings.gradle.kts android/app/build.gradle.kts \
        lib/services/firestore_ref.dart lib/main.dart test/firestore_ref_test.dart README.md
git commit -m "feat: wire up Firebase against the named lunatrack database"
```

---

### Task 2: Schema v5 — sync tombstones and sync timestamps

Adds the two pieces of local bookkeeping sync needs. Purely additive; no existing column or query changes.

**Files:**
- Modify: `lib/db/tables.dart` (add `SyncTombstones`, add `AppSettings.lastSyncedAt`)
- Modify: `lib/db/database.dart:11-13` (table list), `:21` (`schemaVersion`), `:38-47` (`onUpgrade`)
- Create: `drift_schemas/drift_schema_v5.json` (generated)
- Create: `test/generated_migrations/schema_v5.dart` (generated)
- Create: `test/db_migration_v5_test.dart`
- Modify: `test/db_migration_v3_test.dart`, `test/db_migration_v4_test.dart` (re-point at 5)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: table `SyncTombstones { DateTime date (unique), DateTime deletedAt }`; column `AppSettings.lastSyncedAt` (nullable `DateTime`); `AppDatabase.schemaVersion == 5`.

- [ ] **Step 1: Add the table and column**

In `lib/db/tables.dart`, add after the `DailyLogs` class (ends line 34):

```dart
/// A day whose local log was deleted and whose deletion has not yet been
/// pushed to Firestore.
///
/// `DailyLogRepository.deleteForDate` performs a hard DELETE, which leaves a
/// deleted day indistinguishable from a day that never existed — the next pull
/// would resurrect it from the server. A tombstone records the intent.
///
/// This is a separate table rather than a `deleted` flag on `DailyLogs` on
/// purpose: a flag would require adding `where(deleted == false)` to EVERY
/// existing read path (repositories, CycleCalculator, insights, diary, PDF
/// export), and missing one silently resurfaces deleted days in a doctor's
/// report. A tombstone table leaves all existing queries untouched.
class SyncTombstones extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()(); // normalized to local midnight
  DateTimeColumn get deletedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date},
      ];
}
```

In the same file, add to `AppSettings` after `weightUnit` (line 85):

```dart
  // High-water mark for Firestore sync: rows with `updatedAt` after this need
  // pushing, remote docs after this need pulling. NULL means "never synced",
  // which correctly triggers a full initial pull.
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  // When the settings row itself last changed. `DailyLogs` already has its own
  // `updatedAt`; settings had none, and without it sync cannot tell a locally
  // edited preference from a stale one — so a device syncing later would push
  // its old settings over another device's newer change.
  DateTimeColumn get settingsUpdatedAt => dateTime().nullable()();
```

- [ ] **Step 2: Register the table and bump the version**

In `lib/db/database.dart`, change the `@DriftDatabase` annotation (line 11-13):

```dart
@DriftDatabase(
  tables: [
    PeriodEntries,
    DailyLogs,
    Reminders,
    Medications,
    AppSettings,
    SyncTombstones,
  ],
)
```

Change line 21:

```dart
  int get schemaVersion => 5;
```

Add to `onUpgrade`, after the `if (from < 4)` branch (independent `if`, never `else if`):

```dart
          if (from < 5) {
            await m.createTable(syncTombstones);
            await m.addColumn(appSettings, appSettings.lastSyncedAt);
            await m.addColumn(appSettings, appSettings.settingsUpdatedAt);
          }
```

Also extend the comment block above `onUpgrade` with:

```dart
        //   v4 → v5: sync adds the SyncTombstones table + AppSettings.lastSyncedAt.
```

- [ ] **Step 3: Stamp settingsUpdatedAt on every real settings change**

In `lib/data/settings_repository.dart`, replace `update` and add a second method:

```dart
  /// Applies a user-facing settings change and stamps `settingsUpdatedAt` so
  /// sync can tell a locally edited preference from a stale one.
  Future<void> update(AppSettingsCompanion changes) async {
    await _db.getSettings(); // ensure the row exists
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(0))).write(
      changes.copyWith(settingsUpdatedAt: Value(DateTime.now())),
    );
  }

  /// Writes sync bookkeeping ONLY. Deliberately does NOT stamp
  /// `settingsUpdatedAt`: advancing the sync high-water mark is not a user
  /// edit, and stamping it would make every sync look like a settings change
  /// and push endlessly.
  Future<void> updateSyncState(AppSettingsCompanion changes) async {
    await _db.getSettings();
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(0)))
        .write(changes);
  }
```

Add `import 'package:drift/drift.dart';` at the top of the file if it is not already there.

- [ ] **Step 4: Regenerate drift code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `lib/db/database.g.dart` regenerates with `syncTombstones`, `lastSyncedAt`, and `settingsUpdatedAt`.

- [ ] **Step 5: Dump and generate the v5 schema snapshot**

```bash
dart run drift_dev schema dump lib/db/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
ls drift_schemas/ test/generated_migrations/
```

Expected: `drift_schema_v5.json` and `schema_v5.dart` now exist. This must happen while v5 is current — it is not derivable later.

- [ ] **Step 6: Write the failing migration test**

Create `test/db_migration_v5_test.dart`:

```dart
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/db/database.dart';

import 'generated_migrations/schema.dart';
import 'generated_migrations/schema_v4.dart';

/// v4 → v5 must ADD the sync tombstone table and `lastSyncedAt` without
/// disturbing existing rows. Seeds NON-DEFAULT values on purpose: asserting
/// defaults survive would also pass against a wipe-and-recreate migration.
///
/// An in-memory `AppDatabase.forTesting` cannot replace this — it runs
/// `onCreate`/`createAll()` at the CURRENT schema and never executes
/// `onUpgrade`, so it passes whether or not the migration exists.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('v4 -> v5 adds sync bookkeeping and preserves existing data', () async {
    final schema = await verifier.schemaAt(4);

    final oldDb = DatabaseAtV4(schema.newConnection());
    await oldDb.customStatement(
      'INSERT INTO app_settings '
      '(id, default_cycle_length, default_period_length, weight_unit) '
      'VALUES (0, 30, 6, ?)',
      ['lb'],
    );
    await oldDb.customStatement(
      'INSERT INTO daily_logs (date, symptoms) VALUES (?, ?)',
      [DateTime(2026, 3, 3).millisecondsSinceEpoch ~/ 1000, '{"cramps":true}'],
    );
    await oldDb.close();

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);

    final settings = await db.getSettings();
    expect(settings.defaultCycleLength, 30);
    expect(settings.defaultPeriodLength, 6);
    expect(settings.weightUnit, 'lb'); // v4 data untouched
    expect(settings.lastSyncedAt, isNull); // null => never synced => full pull
    expect(settings.settingsUpdatedAt, isNull); // null => never edited locally

    // The pre-existing log row survived the upgrade.
    final logs = await db.select(db.dailyLogs).get();
    expect(logs, hasLength(1));
    expect(logs.single.symptoms, '{"cramps":true}');

    // The new table exists and is empty.
    final tombstones = await db.select(db.syncTombstones).get();
    expect(tombstones, isEmpty);

    await db.close();
  });
}
```

- [ ] **Step 7: Run it to verify it passes**

Run: `flutter test test/db_migration_v5_test.dart`
Expected: PASS. (The generated code from Steps 3–4 already makes this work; the test is the guard against future regressions.)

- [ ] **Step 8: Re-point the older migration tests at v5**

Per `CLAUDE.md`, `migrateAndValidate(db, n)` upgrades to the database's own `schemaVersion`, so old tests cannot keep validating an intermediate version. In **`test/db_migration_v3_test.dart`** change `migrateAndValidate(db, 4)` to `migrateAndValidate(db, 5)`, update the test name to `'v2 -> v5 adds every intervening column and preserves existing data'`, and add before the final `await db.close()`:

```dart
    // Proves the `from < 5` branch also ran on this v2-era hop.
    expect(settings.lastSyncedAt, isNull);
```

Apply the same three changes to **`test/db_migration_v4_test.dart`** (its own start version, name updated to `'v3 -> v5 …'`).

- [ ] **Step 9: Run the full suite**

Run: `flutter test`
Expected: all pass (310 now). A failure in `db_migration_v3_test` means Step 8 was missed.

- [ ] **Step 10: Commit**

```bash
git add lib/db/tables.dart lib/db/database.dart lib/db/database.g.dart \
        lib/data/settings_repository.dart \
        drift_schemas/drift_schema_v5.json test/generated_migrations/schema_v5.dart \
        test/db_migration_v5_test.dart test/db_migration_v3_test.dart test/db_migration_v4_test.dart
git commit -m "feat(db): add sync tombstones and lastSyncedAt with a tested v4->v5 migration"
```

---

### Task 3: Record a tombstone when a day is deleted

**Files:**
- Modify: `lib/data/daily_log_repository.dart:119-122` (`deleteForDate`)
- Create: `test/sync_tombstone_test.dart`

**Interfaces:**
- Consumes: `SyncTombstones` table (Task 2).
- Produces: `DailyLogRepository.deleteForDate` writes a tombstone; `Future<List<SyncTombstone>> getTombstones()`; `Future<void> clearTombstone(DateTime date)`.

- [ ] **Step 1: Write the failing test**

Create `test/sync_tombstone_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  test('deleting a day records a tombstone so the deletion can be pushed',
      () async {
    final day = DateTime(2026, 5, 10);
    await repo.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');

    await repo.deleteForDate(day);

    expect(await repo.getForDate(day), isNull);
    final tombstones = await repo.getTombstones();
    expect(tombstones, hasLength(1));
    expect(tombstones.single.date, DateTime(2026, 5, 10));
  });

  test('deleting the same day twice keeps exactly one tombstone', () async {
    final day = DateTime(2026, 5, 11);
    await repo.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');

    await repo.deleteForDate(day);
    await repo.deleteForDate(day);

    expect(await repo.getTombstones(), hasLength(1));
  });

  test('clearTombstone removes it once the deletion has been pushed', () async {
    final day = DateTime(2026, 5, 12);
    await repo.upsert(date: day, flow: FlowIntensity.heavy, symptomsJson: '{}');
    await repo.deleteForDate(day);

    await repo.clearTombstone(day);

    expect(await repo.getTombstones(), isEmpty);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/sync_tombstone_test.dart`
Expected: FAIL — `The method 'getTombstones' isn't defined for the type 'DailyLogRepository'`.

- [ ] **Step 3: Implement**

In `lib/data/daily_log_repository.dart`, replace `deleteForDate` (lines 119-122) with:

```dart
  /// Deletes the log for [date] and records a tombstone in the SAME
  /// transaction. Without the tombstone a hard-deleted row is indistinguishable
  /// from one that never existed, and the next sync pull would resurrect it.
  Future<void> deleteForDate(DateTime date) async {
    final d = dateOnly(date);
    await _db.transaction(() async {
      await (_db.delete(_db.dailyLogs)..where((t) => t.date.equals(d))).go();
      // `date` is UNIQUE, so a repeat delete replaces rather than duplicates.
      await _db.into(_db.syncTombstones).insertOnConflictUpdate(
            SyncTombstonesCompanion.insert(
              date: d,
              deletedAt: Value(DateTime.now()),
            ),
          );
    });
  }

  /// Days deleted locally whose deletion has not yet reached Firestore.
  Future<List<SyncTombstone>> getTombstones() =>
      _db.select(_db.syncTombstones).get();

  /// Clears a tombstone after its remote document has been deleted.
  Future<void> clearTombstone(DateTime date) async {
    final d = dateOnly(date);
    await (_db.delete(_db.syncTombstones)..where((t) => t.date.equals(d))).go();
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/sync_tombstone_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: all pass. `deleteForDate` is called by the day editor and calendar — an existing failure here means the transaction broke a caller.

- [ ] **Step 6: Commit**

```bash
git add lib/data/daily_log_repository.dart test/sync_tombstone_test.dart
git commit -m "feat: record a tombstone when a day log is deleted"
```

---

### Task 4: Device id and the pure DailyLog ⇄ Firestore mapper

Pure conversion with no Firebase dependency, so it is fully unit-testable.

**Files:**
- Create: `lib/services/device_id.dart`
- Create: `lib/services/sync_mapper.dart`
- Create: `test/sync_mapper_test.dart`

**Interfaces:**
- Consumes: `DailyLog`, `DailyLogsCompanion` (drift, Task 2).
- Produces:
  - `String syncDocId(DateTime date)` → `'2026-08-04'`
  - `Map<String, dynamic> dailyLogToMap(DailyLog log, {required String deviceId})`
  - `DailyLogsCompanion dailyLogFromMap(Map<String, dynamic> map)`
  - `DateTime? updatedAtFromMap(Map<String, dynamic> map)`
  - `Future<String> DeviceId.get()`

- [ ] **Step 1: Write the failing test**

Create `test/sync_mapper_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/sync_mapper.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DailyLogRepository(db);
  });

  tearDown(() => db.close());

  test('doc id is the ISO date, zero-padded', () {
    expect(syncDocId(DateTime(2026, 8, 4)), '2026-08-04');
    expect(syncDocId(DateTime(2026, 12, 31)), '2026-12-31');
  });

  test('round-trips every field, including reserved tag prefixes', () async {
    // Reserved prefixes (med_, sex_, cm_, …) ride the same symptoms blob and
    // must survive sync exactly — a dropped prefix silently loses a whole
    // tracking category.
    const symptoms =
        '{"cramps":true,"med_pill":true,"sex_protected":true,"weight":61.5}';
    final day = DateTime(2026, 8, 4);
    await repo.upsert(
      date: day,
      flow: FlowIntensity.medium,
      symptomsJson: symptoms,
      mood: 'calm',
      notes: 'felt fine',
      bbt: 36.6,
      opk: 'positive',
    );
    final log = (await repo.getForDate(day))!;

    final map = dailyLogToMap(log, deviceId: 'device-abc');
    final companion = dailyLogFromMap(map);

    expect(companion.date.value, day);
    expect(companion.flow.value, FlowIntensity.medium);
    expect(companion.symptoms.value, symptoms);
    expect(companion.mood.value, 'calm');
    expect(companion.notes.value, 'felt fine');
    expect(companion.bbt.value, 36.6);
    expect(companion.opk.value, 'positive');
    expect(map['deviceId'], 'device-abc');
  });

  test('round-trips a sparse row with a null flow and an empty blob', () async {
    final day = DateTime(2026, 8, 5);
    await repo.upsert(date: day, symptomsJson: '{}');
    final log = (await repo.getForDate(day))!;

    final companion = dailyLogFromMap(dailyLogToMap(log, deviceId: 'd'));

    expect(companion.flow.value, isNull);
    expect(companion.symptoms.value, '{}');
    expect(companion.mood.value, isNull);
  });

  test('symptoms travel as a map, not an opaque JSON string', () async {
    final day = DateTime(2026, 8, 6);
    await repo.upsert(date: day, symptomsJson: '{"cramps":true}');
    final log = (await repo.getForDate(day))!;

    final map = dailyLogToMap(log, deviceId: 'd');

    expect(map['symptoms'], isA<Map<String, dynamic>>());
    expect(map['symptoms']['cramps'], isTrue);
  });

  test('an out-of-range flow index decodes to null instead of crashing',
      () async {
    // Defensive: a future app version could write an enum index this build
    // doesn't know. Losing one field beats failing the whole sync.
    final map = {
      'date': '2026-08-07',
      'flow': 99,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2026, 8, 7).millisecondsSinceEpoch,
    };

    expect(dailyLogFromMap(map).flow.value, isNull);
  });

  test('updatedAtFromMap reads the epoch-millis timestamp', () {
    final t = DateTime(2026, 8, 4, 12, 30);
    expect(
      updatedAtFromMap({'updatedAt': t.millisecondsSinceEpoch}),
      t,
    );
    expect(updatedAtFromMap({}), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/sync_mapper_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../services/sync_mapper.dart'`.

- [ ] **Step 3: Write the mapper**

Create `lib/services/sync_mapper.dart`:

```dart
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';
import '../models/enums.dart';

/// Firestore document id for a day: the local ISO-8601 date, e.g. `2026-08-04`.
///
/// Mirrors the `uniqueKeys => [{date}]` constraint on `DailyLogs`, which makes
/// remote writes idempotent — a day cannot be duplicated and a re-push simply
/// overwrites, so the sync loop can safely repeat work but never lose data.
String syncDocId(DateTime date) {
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}

/// Encodes a local row for Firestore.
///
/// `symptoms` is written as a real map rather than the raw JSON string so the
/// console is readable and the field stays queryable later. `flow` travels as
/// the enum INDEX, matching `intEnum` locally: storing the name would break
/// silently if the enum were reordered, whereas an index breaks loudly on an
/// out-of-range value (which [dailyLogFromMap] handles).
Map<String, dynamic> dailyLogToMap(
  DailyLog log, {
  required String deviceId,
}) {
  return {
    'date': syncDocId(log.date),
    'flow': log.flow?.index,
    'symptoms': jsonDecode(log.symptoms) as Map<String, dynamic>,
    'mood': log.mood,
    'notes': log.notes,
    'bbt': log.bbt,
    'opk': log.opk,
    'createdAt': log.createdAt.millisecondsSinceEpoch,
    'updatedAt': log.updatedAt.millisecondsSinceEpoch,
    'deviceId': deviceId,
  };
}

/// Decodes a Firestore document into a drift companion ready to upsert.
DailyLogsCompanion dailyLogFromMap(Map<String, dynamic> map) {
  final parts = (map['date'] as String).split('-');
  final date = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );

  final flowIndex = map['flow'] as int?;
  final flow = (flowIndex != null &&
          flowIndex >= 0 &&
          flowIndex < FlowIntensity.values.length)
      ? FlowIntensity.values[flowIndex]
      : null;

  final symptoms = (map['symptoms'] as Map?)?.cast<String, dynamic>() ?? {};

  return DailyLogsCompanion(
    date: Value(date),
    flow: Value(flow),
    symptoms: Value(jsonEncode(symptoms)),
    mood: Value(map['mood'] as String?),
    notes: Value(map['notes'] as String?),
    bbt: Value((map['bbt'] as num?)?.toDouble()),
    opk: Value(map['opk'] as String?),
    updatedAt: Value(updatedAtFromMap(map) ?? DateTime.now()),
  );
}

/// The remote row's last-modified time, used for last-write-wins merging.
DateTime? updatedAtFromMap(Map<String, dynamic> map) {
  final millis = map['updatedAt'] as int?;
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/sync_mapper_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Add the device id helper**

Create `lib/services/device_id.dart`:

```dart
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A stable per-install identifier, stamped on every synced document.
///
/// Diagnostic only — it never participates in merge decisions, so a
/// regenerated id (e.g. after a reinstall) cannot cause data loss.
class DeviceId {
  static const _key = 'luna_device_id';
  static const _storage = FlutterSecureStorage();

  static Future<String> get() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) return existing;
    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _key, value: id);
    return id;
  }
}
```

- [ ] **Step 6: Run the full suite and commit**

```bash
flutter analyze && flutter test
git add lib/services/sync_mapper.dart lib/services/device_id.dart test/sync_mapper_test.dart
git commit -m "feat: add the pure DailyLog <-> Firestore mapper and device id"
```

---

### Task 5: Last-write-wins merge decision

A pure function, isolated so the conflict policy is testable without any network or database.

**Files:**
- Create: `lib/services/sync_merge.dart`
- Create: `test/sync_merge_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum MergeDecision { takeRemote, keepLocal, unchanged }` and
  `MergeDecision decideMerge({DateTime? local, DateTime? remote})`.

- [ ] **Step 1: Write the failing test**

Create `test/sync_merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/sync_merge.dart';

/// Last-write-wins at the WHOLE-DAY level. Field-level merge was rejected in
/// the spec: `encodeDayTags` is a full REPLACE, so merging individual tags from
/// two devices would synthesise a tag set the user never authored on either.
/// Whole-document LWW can lose an edit; field merge can INVENT one. For a
/// health log, losing is safer than inventing.
void main() {
  final earlier = DateTime(2026, 8, 4, 10);
  final later = DateTime(2026, 8, 4, 11);

  test('a newer remote wins', () {
    expect(decideMerge(local: earlier, remote: later), MergeDecision.takeRemote);
  });

  test('a newer local wins', () {
    expect(decideMerge(local: later, remote: earlier), MergeDecision.keepLocal);
  });

  test('identical timestamps change nothing', () {
    expect(
      decideMerge(local: earlier, remote: earlier),
      MergeDecision.unchanged,
    );
  });

  test('a day that exists only remotely is taken', () {
    expect(decideMerge(local: null, remote: later), MergeDecision.takeRemote);
  });

  test('a day that exists only locally is kept', () {
    expect(decideMerge(local: later, remote: null), MergeDecision.keepLocal);
  });

  test('neither side present is unchanged', () {
    expect(decideMerge(local: null, remote: null), MergeDecision.unchanged);
  });

  test('a future-dated remote still resolves without throwing', () {
    // `updatedAt` comes from device time, so a device with a badly wrong clock
    // can produce a timestamp far in the future. Sync must resolve it, not
    // crash — the wrong side winning is recoverable, a crash loop is not.
    final future = DateTime(2099, 1, 1);
    expect(decideMerge(local: later, remote: future), MergeDecision.takeRemote);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/sync_merge_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../services/sync_merge.dart'`.

- [ ] **Step 3: Implement**

Create `lib/services/sync_merge.dart`:

```dart
/// What sync should do with one day, given both sides' last-modified times.
enum MergeDecision {
  /// Overwrite the local row with the remote document.
  takeRemote,

  /// Keep (and push) the local row.
  keepLocal,

  /// Both sides agree, or neither exists.
  unchanged,
}

/// Last-write-wins over a whole day document.
///
/// Deliberately NOT field-level: `encodeDayTags` rebuilds the entire symptoms
/// blob from form state, so merging individual tags across devices would
/// fabricate a combination the user never entered. See the design spec §6.
///
/// Timestamps come from device clocks, so this must tolerate skew — including
/// a remote timestamp in the future — without throwing.
MergeDecision decideMerge({DateTime? local, DateTime? remote}) {
  if (local == null && remote == null) return MergeDecision.unchanged;
  if (local == null) return MergeDecision.takeRemote;
  if (remote == null) return MergeDecision.keepLocal;
  if (remote.isAfter(local)) return MergeDecision.takeRemote;
  if (local.isAfter(remote)) return MergeDecision.keepLocal;
  return MergeDecision.unchanged;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/sync_merge_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/sync_merge.dart test/sync_merge_test.dart
git commit -m "feat: add the last-write-wins merge decision for sync"
```

---

### Task 6: AuthService and AuthProvider

An abstract `AuthService` so every screen test runs against a fake with no network.

**Files:**
- Create: `lib/services/auth_service.dart`
- Create: `lib/providers/auth_provider.dart`
- Create: `test/auth_provider_test.dart`

**Interfaces:**
- Consumes: `firebase_auth` (Task 1).
- Produces:
  - `class AppUser { final String uid; final String? email; }`
  - `enum AuthErrorCode { invalidEmail, emailInUse, weakPassword, wrongCredentials, networkError, requiresRecentLogin, unknown }`
  - `class AuthFailure implements Exception { final AuthErrorCode code; }`
  - `abstract class AuthService` with `authStateChanges()`, `currentUser`, `signUp`, `signIn`, `signOut`, `sendPasswordReset`, `deleteAccount`
  - `class FirebaseAuthService implements AuthService`
  - `enum AuthState { unknown, signedOut, signedIn }`
  - `class AuthProvider extends ChangeNotifier` with `state`, `user`, `busy`, `lastError`, and the same five actions

- [ ] **Step 1: Write the failing test**

Create `test/auth_provider_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/services/auth_service.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _current;
  AuthFailure? nextFailure;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;

  @override
  AppUser? get currentUser => _current;

  void emit(AppUser? user) {
    _current = user;
    _controller.add(user);
  }

  @override
  Future<void> signUp({required String email, required String password}) async {
    if (nextFailure != null) throw nextFailure!;
    emit(AppUser(uid: 'uid-1', email: email));
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (nextFailure != null) throw nextFailure!;
    emit(AppUser(uid: 'uid-1', email: email));
  }

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<void> sendPasswordReset(String email) async {
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> deleteAccount() async => emit(null);

  void dispose() => _controller.close();
}

void main() {
  late FakeAuthService fake;
  late AuthProvider provider;

  setUp(() {
    fake = FakeAuthService();
    provider = AuthProvider(fake);
  });

  tearDown(() {
    provider.dispose();
    fake.dispose();
  });

  test('starts in unknown so the gate can show a splash, not a flash of login',
      () {
    expect(provider.state, AuthState.unknown);
  });

  test('signing in moves to signedIn and exposes the user', () async {
    await provider.signIn(email: 'a@b.com', password: 'secret123');
    await Future<void>.delayed(Duration.zero);

    expect(provider.state, AuthState.signedIn);
    expect(provider.user?.uid, 'uid-1');
    expect(provider.user?.email, 'a@b.com');
  });

  test('signing out moves to signedOut', () async {
    await provider.signIn(email: 'a@b.com', password: 'secret123');
    await Future<void>.delayed(Duration.zero);

    await provider.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(provider.state, AuthState.signedOut);
    expect(provider.user, isNull);
  });

  test('a failure surfaces as lastError and leaves the user signed out',
      () async {
    fake.nextFailure = AuthFailure(AuthErrorCode.wrongCredentials);

    await provider.signIn(email: 'a@b.com', password: 'nope');

    expect(provider.lastError, AuthErrorCode.wrongCredentials);
    expect(provider.state, AuthState.unknown);
    expect(provider.busy, isFalse);
  });

  test('busy is false again after a failure so the button re-enables',
      () async {
    fake.nextFailure = AuthFailure(AuthErrorCode.networkError);

    await provider.signUp(email: 'a@b.com', password: 'secret123');

    expect(provider.busy, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/auth_provider_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../services/auth_service.dart'`.

- [ ] **Step 3: Write the service**

Create `lib/services/auth_service.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';

/// The signed-in user, reduced to what the app actually needs. Keeping
/// `firebase_auth` types out of providers and widgets is what lets every screen
/// test run against a fake with no network.
class AppUser {
  const AppUser({required this.uid, this.email});
  final String uid;
  final String? email;
}

/// App-level auth error categories. Firebase's string codes are mapped here so
/// the UI can show a specific message without importing `firebase_auth`.
enum AuthErrorCode {
  invalidEmail,
  emailInUse,
  weakPassword,
  wrongCredentials,
  networkError,
  requiresRecentLogin,
  unknown,
}

class AuthFailure implements Exception {
  AuthFailure(this.code);
  final AuthErrorCode code;

  @override
  String toString() => 'AuthFailure($code)';
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  AppUser? get currentUser;
  Future<void> signUp({required String email, required String password});
  Future<void> signIn({required String email, required String password});
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);

  /// Deletes the Firebase Auth user. Callers MUST delete the Firestore subtree
  /// first — deleting the auth user first orphans the health data with no
  /// signed-in identity able to reach it.
  Future<void> deleteAccount();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth])
      : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  AppUser? _map(User? u) =>
      u == null ? null : AppUser(uid: u.uid, email: u.email);

  @override
  Stream<AppUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  @override
  Future<void> signUp({
    required String email,
    required String password,
  }) async {
    await _run(() => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _run(() => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ));
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> deleteAccount() =>
      _run(() async => _auth.currentUser?.delete());

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_codeFor(e.code));
    }
  }

  AuthErrorCode _codeFor(String code) {
    switch (code) {
      case 'invalid-email':
        return AuthErrorCode.invalidEmail;
      case 'email-already-in-use':
        return AuthErrorCode.emailInUse;
      case 'weak-password':
        return AuthErrorCode.weakPassword;
      // Modern Firebase collapses wrong-password and user-not-found into
      // `invalid-credential` on purpose (it avoids account enumeration). The
      // older codes are kept for older SDK/back-end combinations.
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return AuthErrorCode.wrongCredentials;
      case 'network-request-failed':
        return AuthErrorCode.networkError;
      case 'requires-recent-login':
        return AuthErrorCode.requiresRecentLogin;
      default:
        return AuthErrorCode.unknown;
    }
  }
}
```

- [ ] **Step 4: Write the provider**

Create `lib/providers/auth_provider.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';

/// `unknown` exists so the gate can show a splash on cold start instead of a
/// flash of the sign-in screen before Firebase restores the session.
enum AuthState { unknown, signedOut, signedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._service) {
    _sub = _service.authStateChanges().listen(_onUser);
  }

  final AuthService _service;
  late final StreamSubscription<AppUser?> _sub;

  AuthState _state = AuthState.unknown;
  AppUser? _user;
  bool _busy = false;
  AuthErrorCode? _lastError;

  AuthState get state => _state;
  AppUser? get user => _user;
  bool get busy => _busy;
  AuthErrorCode? get lastError => _lastError;

  void _onUser(AppUser? user) {
    _user = user;
    _state = user == null ? AuthState.signedOut : AuthState.signedIn;
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _service.signIn(email: email, password: password));

  Future<void> signUp({required String email, required String password}) =>
      _guard(() => _service.signUp(email: email, password: password));

  Future<void> sendPasswordReset(String email) =>
      _guard(() => _service.sendPasswordReset(email));

  Future<void> signOut() => _guard(_service.signOut);

  /// Runs an action with busy/error bookkeeping. `busy` is always cleared, so a
  /// failed sign-in re-enables the button instead of stranding the user.
  Future<void> _guard(Future<void> Function() action) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
    } on AuthFailure catch (e) {
      _lastError = e.code;
    } catch (_) {
      _lastError = AuthErrorCode.unknown;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/auth_provider_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
flutter analyze && flutter test
git add lib/services/auth_service.dart lib/providers/auth_provider.dart test/auth_provider_test.dart
git commit -m "feat: add AuthService and AuthProvider for email/password accounts"
```

---

### Task 7: Sign-in, sign-up, and password-reset screens

**Files:**
- Create: `lib/screens/auth/sign_in_screen.dart`
- Create: `lib/screens/auth/sign_up_screen.dart`
- Create: `lib/screens/auth/forgot_password_screen.dart`
- Create: `lib/screens/auth/auth_error_text.dart`
- Create: `test/auth_screens_test.dart`

**Interfaces:**
- Consumes: `AuthProvider`, `AuthErrorCode` (Task 6).
- Produces: `SignInScreen`, `SignUpScreen`, `ForgotPasswordScreen`, and `String messageForAuthError(AuthErrorCode)`.

- [ ] **Step 1: Write the failing test**

Create `test/auth_screens_test.dart`. It reuses the `FakeAuthService` shape from Task 6 (repeated here so this file stands alone):

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/screens/auth/sign_in_screen.dart';
import 'package:menstrul_track/screens/auth/sign_up_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:provider/provider.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  AuthFailure? nextFailure;
  String? lastEmail;
  String? lastPassword;
  int signInCalls = 0;

  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => null;
  @override
  Future<void> signUp({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {
    lastEmail = email;
    if (nextFailure != null) throw nextFailure!;
  }

  @override
  Future<void> deleteAccount() async {}
  void dispose() => _controller.close();
}

Widget _wrap(Widget child, FakeAuthService fake) {
  return ChangeNotifierProvider(
    create: (_) => AuthProvider(fake),
    child: MaterialApp(home: child),
  );
}

void main() {
  late FakeAuthService fake;

  setUp(() => fake = FakeAuthService());
  tearDown(() => fake.dispose());

  testWidgets('sign-in submits the entered credentials', (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));

    await tester.enterText(find.byKey(const Key('signIn.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signIn.password')), 'secret123');
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(fake.lastEmail, 'a@b.com');
    expect(fake.lastPassword, 'secret123');
  });

  testWidgets('sign-in blocks an empty email without calling the service',
      (tester) async {
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));

    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(fake.signInCalls, 0);
    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('a wrong-credentials failure is shown to the user',
      (tester) async {
    fake.nextFailure = AuthFailure(AuthErrorCode.wrongCredentials);
    await tester.pumpWidget(_wrap(const SignInScreen(), fake));

    await tester.enterText(find.byKey(const Key('signIn.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signIn.password')), 'nope1234');
    await tester.tap(find.byKey(const Key('signIn.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
  });

  testWidgets('sign-up rejects a password shorter than 8 characters',
      (tester) async {
    await tester.pumpWidget(_wrap(const SignUpScreen(), fake));

    await tester.enterText(find.byKey(const Key('signUp.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signUp.password')), 'short');
    await tester.enterText(find.byKey(const Key('signUp.confirm')), 'short');
    await tester.tap(find.byKey(const Key('signUp.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(fake.lastPassword, isNull);
  });

  testWidgets('sign-up rejects mismatched confirmation', (tester) async {
    await tester.pumpWidget(_wrap(const SignUpScreen(), fake));

    await tester.enterText(find.byKey(const Key('signUp.email')), 'a@b.com');
    await tester.enterText(find.byKey(const Key('signUp.password')), 'secret123');
    await tester.enterText(find.byKey(const Key('signUp.confirm')), 'secret124');
    await tester.tap(find.byKey(const Key('signUp.submit')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(fake.lastPassword, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/auth_screens_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../screens/auth/sign_in_screen.dart'`.

- [ ] **Step 3: Write the error-message mapper**

Create `lib/screens/auth/auth_error_text.dart`:

```dart
import '../../services/auth_service.dart';

/// User-facing copy for an auth failure.
///
/// `wrongCredentials` deliberately does NOT distinguish "no such account" from
/// "wrong password" — telling them apart lets anyone test whether an email is
/// registered, which for a menstrual tracker is itself sensitive.
String messageForAuthError(AuthErrorCode code) {
  switch (code) {
    case AuthErrorCode.invalidEmail:
      return 'That email address is not valid.';
    case AuthErrorCode.emailInUse:
      return 'An account already exists for that email.';
    case AuthErrorCode.weakPassword:
      return 'Choose a stronger password.';
    case AuthErrorCode.wrongCredentials:
      return 'Email or password is incorrect.';
    case AuthErrorCode.networkError:
      return 'No connection. Check your network and try again.';
    case AuthErrorCode.requiresRecentLogin:
      return 'Please sign in again to continue.';
    case AuthErrorCode.unknown:
      return 'Something went wrong. Please try again.';
  }
}
```

- [ ] **Step 4: Write the sign-in screen**

Create `lib/screens/auth/sign_in_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_error_text.dart';
import 'forgot_password_screen.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<AuthProvider>().signIn(
          email: _email.text,
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sign in',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('signIn.email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your email'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('signIn.password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Enter your password'
                        : null,
                  ),
                  if (auth.lastError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      messageForAuthError(auth.lastError!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('signIn.submit'),
                    onPressed: auth.busy ? null : _submit,
                    child: auth.busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Sign in'),
                  ),
                  TextButton(
                    key: const Key('signIn.forgot'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
                    child: const Text('Forgot password?'),
                  ),
                  TextButton(
                    key: const Key('signIn.toSignUp'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SignUpScreen(),
                      ),
                    ),
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Write the sign-up screen**

Create `lib/screens/auth/sign_up_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_error_text.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<AuthProvider>().signUp(
          email: _email.text,
          password: _password.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('signUp.email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Enter your email';
                    if (!value.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signUp.password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Use at least 8 characters'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('signUp.confirm'),
                  controller: _confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm password'),
                  validator: (v) => (v != _password.text)
                      ? 'Passwords do not match'
                      : null,
                ),
                if (auth.lastError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    messageForAuthError(auth.lastError!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('signUp.submit'),
                  onPressed: auth.busy ? null : _submit,
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Write the password-reset screen**

Create `lib/screens/auth/forgot_password_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'auth_error_text.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.sendPasswordReset(_email.text);
    if (!mounted) return;
    // Confirm regardless of whether the address is registered: revealing which
    // emails have accounts would leak that someone uses a period tracker.
    if (auth.lastError == null) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _sent
              ? const Text(
                  'If an account exists for that address, a reset link is on '
                  'its way. Check your inbox and spam folder.',
                  key: Key('forgot.sent'),
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('forgot.email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your email'
                            : null,
                      ),
                      if (auth.lastError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          messageForAuthError(auth.lastError!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('forgot.submit'),
                        onPressed: auth.busy ? null : _submit,
                        child: const Text('Send reset link'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `flutter test test/auth_screens_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 8: Commit**

```bash
flutter analyze && flutter test
git add lib/screens/auth test/auth_screens_test.dart
git commit -m "feat: add sign-in, sign-up and password-reset screens"
```

---

### Task 8: Gate the app behind authentication

**Files:**
- Modify: `lib/main.dart` (register `AuthProvider`)
- Modify: `lib/screens/app_gate.dart:44-68` (`build`)
- Create: `test/auth_gate_test.dart`

**Interfaces:**
- Consumes: `AuthProvider`, `AuthState` (Task 6); `SignInScreen` (Task 7).
- Produces: `AppGate` renders sign-in when signed out, a splash while `unknown`, and the existing onboarding/lock/shell chain when signed in.

- [ ] **Step 1: Write the failing test**

Create `test/auth_gate_test.dart`:

```dart
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/providers/auth_provider.dart';
import 'package:menstrul_track/providers/settings_provider.dart';
import 'package:menstrul_track/screens/app_gate.dart';
import 'package:menstrul_track/screens/auth/sign_in_screen.dart';
import 'package:menstrul_track/services/auth_service.dart';
import 'package:provider/provider.dart';

class FakeAuthService implements AuthService {
  final _controller = StreamController<AppUser?>.broadcast();
  @override
  Stream<AppUser?> authStateChanges() => _controller.stream;
  @override
  AppUser? get currentUser => null;
  void emit(AppUser? u) => _controller.add(u);
  @override
  Future<void> signUp({required String email, required String password}) async {}
  @override
  Future<void> signIn({required String email, required String password}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> sendPasswordReset(String email) async {}
  @override
  Future<void> deleteAccount() async {}
  void dispose() => _controller.close();
}

void main() {
  late AppDatabase db;
  late FakeAuthService fake;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    fake = FakeAuthService();
  });

  tearDown(() async {
    fake.dispose();
    await db.close();
  });

  Widget wrap() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider(fake)),
          ChangeNotifierProvider(
            create: (_) => SettingsProvider(SettingsRepository(db))..load(),
          ),
        ],
        child: const MaterialApp(home: AppGate()),
      );

  testWidgets('shows a splash, not the sign-in form, before auth is known',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump();

    expect(find.byType(SignInScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows sign-in once the user is known to be signed out',
      (tester) async {
    await tester.pumpWidget(wrap());
    fake.emit(null);
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('a signed-in user reaches the normal app chain, not sign-in',
      (tester) async {
    await tester.pumpWidget(wrap());
    fake.emit(const AppUser(uid: 'uid-1', email: 'a@b.com'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/auth_gate_test.dart`
Expected: FAIL — `Could not find the correct Provider<AuthProvider>` (the gate does not read it yet).

- [ ] **Step 3: Add the auth branch to AppGate**

In `lib/screens/app_gate.dart`, add the imports:

```dart
import '../providers/auth_provider.dart';
import 'auth/sign_in_screen.dart';
```

Then in `build`, insert **before** the existing `final settings = context.watch<SettingsProvider>();` line:

```dart
    final auth = context.watch<AuthProvider>();

    // Cold start: Firebase restores the session asynchronously. Showing a
    // splash here avoids a flash of the sign-in form for an already-signed-in
    // user.
    if (auth.state == AuthState.unknown) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // An account is required (design spec §7.1).
    if (auth.state == AuthState.signedOut) {
      return const SignInScreen();
    }
```

- [ ] **Step 4: Register AuthProvider in main.dart**

In `lib/main.dart` add the imports:

```dart
import 'providers/auth_provider.dart';
import 'services/auth_service.dart';
```

Then add as the **first** `ChangeNotifierProvider` in the `MultiProvider` list (immediately after `Provider<AppDatabase>.value(...)`):

```dart
        ChangeNotifierProvider(
          create: (_) => AuthProvider(FirebaseAuthService()),
        ),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/auth_gate_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: all pass. Any widget test that pumps `AppGate` without an `AuthProvider` now fails — add the provider to that test's wrapper rather than weakening the gate.

- [ ] **Step 7: Commit**

```bash
flutter analyze && flutter test
git add lib/screens/app_gate.dart lib/main.dart test/auth_gate_test.dart
git commit -m "feat: require sign-in before the app shell"
```

---

### Task 9: SyncService — push, pull, and commit the high-water mark

**Files:**
- Create: `lib/services/sync_service.dart`
- Create: `test/sync_service_test.dart`

**Interfaces:**
- Consumes: `lunaFirestore()` (Task 1), `SyncTombstones`/`lastSyncedAt` (Task 2), tombstone accessors (Task 3), mapper (Task 4), `decideMerge` (Task 5).
- Produces: `class SyncService { SyncService({required AppDatabase db, required FirebaseFirestore firestore, required String uid, required String deviceId}); Future<void> syncNow(); }`

- [ ] **Step 1: Add the fake Firestore dev dependency**

`cloud_firestore` cannot run in a unit test. `fake_cloud_firestore` provides an in-memory implementation of the same interface.

```bash
flutter pub add --dev fake_cloud_firestore
```

- [ ] **Step 2: Write the failing test**

Create `test/sync_service_test.dart`:

```dart
// `show Value` avoids drift's Column/Table names colliding with flutter_test.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/data/settings_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/services/sync_service.dart';

void main() {
  late AppDatabase db;
  late DailyLogRepository logs;
  late FakeFirebaseFirestore firestore;
  late SyncService sync;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logs = DailyLogRepository(db);
    firestore = FakeFirebaseFirestore();
    sync = SyncService(
      db: db,
      firestore: firestore,
      uid: 'uid-1',
      deviceId: 'device-1',
    );
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>?> remoteDay(String id) async {
    final doc =
        await firestore.collection('users/uid-1/dailyLogs').doc(id).get();
    return doc.data();
  }

  test('pushes a local day to users/{uid}/dailyLogs/{date}', () async {
    await logs.upsert(
      date: DateTime(2026, 8, 4),
      flow: FlowIntensity.medium,
      symptomsJson: '{"cramps":true}',
    );

    await sync.syncNow();

    final doc = await remoteDay('2026-08-04');
    expect(doc, isNotNull);
    expect(doc!['flow'], FlowIntensity.medium.index);
    expect(doc['symptoms']['cramps'], isTrue);
    expect(doc['deviceId'], 'device-1');
  });

  test('pulls a remote-only day into the local database', () async {
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-09').set({
      'date': '2026-08-09',
      'flow': FlowIntensity.light.index,
      'symptoms': <String, dynamic>{'headache': true},
      'updatedAt': DateTime(2026, 8, 9, 10).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    final local = await logs.getForDate(DateTime(2026, 8, 9));
    expect(local, isNotNull);
    expect(local!.flow, FlowIntensity.light);
    expect(local.symptoms, '{"headache":true}');
  });

  test('a newer remote overwrites the local row', () async {
    final day = DateTime(2026, 8, 10);
    await logs.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');

    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-10').set({
      'date': '2026-08-10',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    expect((await logs.getForDate(day))!.flow, FlowIntensity.heavy);
  });

  test('an older remote does not clobber a newer local row', () async {
    final day = DateTime(2026, 8, 11);
    await firestore.collection('users/uid-1/dailyLogs').doc('2026-08-11').set({
      'date': '2026-08-11',
      'flow': FlowIntensity.heavy.index,
      'symptoms': <String, dynamic>{},
      'updatedAt': DateTime(2020, 1, 1).millisecondsSinceEpoch,
    });
    await logs.upsert(date: day, flow: FlowIntensity.light, symptomsJson: '{}');

    await sync.syncNow();

    expect((await logs.getForDate(day))!.flow, FlowIntensity.light);
  });

  test('a deleted day is removed remotely and the tombstone is cleared',
      () async {
    final day = DateTime(2026, 8, 12);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();
    expect(await remoteDay('2026-08-12'), isNotNull);

    await logs.deleteForDate(day);
    await sync.syncNow();

    expect(await remoteDay('2026-08-12'), isNull);
    expect(await logs.getTombstones(), isEmpty);
  });

  test('a deleted day is not resurrected by the next pull', () async {
    final day = DateTime(2026, 8, 13);
    await logs.upsert(date: day, flow: FlowIntensity.medium, symptomsJson: '{}');
    await sync.syncNow();
    await logs.deleteForDate(day);
    await sync.syncNow();

    await sync.syncNow(); // a second pull must not bring it back

    expect(await logs.getForDate(day), isNull);
  });

  test('lastSyncedAt advances after a successful run', () async {
    final settings = SettingsRepository(db);
    expect((await settings.get()).lastSyncedAt, isNull);

    await logs.upsert(
      date: DateTime(2026, 8, 14),
      flow: FlowIntensity.light,
      symptomsJson: '{}',
    );
    await sync.syncNow();

    expect((await settings.get()).lastSyncedAt, isNotNull);
  });

  test('one user cannot see another user\'s collection path', () async {
    await logs.upsert(
      date: DateTime(2026, 8, 15),
      flow: FlowIntensity.light,
      symptomsJson: '{}',
    );
    await sync.syncNow();

    final other =
        await firestore.collection('users/uid-2/dailyLogs').get();
    expect(other.docs, isEmpty);
  });

  test('syncs preference settings but never device-local ones', () async {
    final settings = SettingsRepository(db);
    await settings.update(const AppSettingsCompanion(
      defaultCycleLength: Value(31),
      weightUnit: Value('lb'),
      premium: Value(true),
      appLockEnabled: Value(true),
    ));

    await sync.syncNow();

    final doc =
        await firestore.doc('users/uid-1/settings/current').get();
    expect(doc.data()!['defaultCycleLength'], 31);
    expect(doc.data()!['weightUnit'], 'lb');
    // Device-local concerns must NOT travel: `premium` is an IAP entitlement
    // tied to a Play account, and app lock is a per-device security choice.
    expect(doc.data()!.containsKey('premium'), isFalse);
    expect(doc.data()!.containsKey('appLockEnabled'), isFalse);
  });

  test('pulls newer remote settings into the local row', () async {
    final settings = SettingsRepository(db);
    await firestore.doc('users/uid-1/settings/current').set({
      'mode': TrackingMode.track.index,
      'defaultCycleLength': 33,
      'defaultPeriodLength': 5,
      'themeMode': 'system',
      'language': 'en',
      'genderNeutralLanguage': false,
      'pregnancyStartDate': null,
      'trackingCategories': null,
      'weightUnit': 'lb',
      'updatedAt':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });

    await sync.syncNow();

    final local = await settings.get();
    expect(local.defaultCycleLength, 33);
    expect(local.weightUnit, 'lb');
  });

  test('signing out does not wipe local data', () async {
    // Design spec §7.3: sign-out must never delete the device's logs — a user
    // switching accounts would otherwise lose everything.
    await logs.upsert(
      date: DateTime(2026, 8, 16),
      flow: FlowIntensity.light,
      symptomsJson: '{}',
    );
    await sync.syncNow();

    // Tearing sync down is all that happens on sign-out.
    expect(await logs.getAll(), hasLength(1));
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `flutter test test/sync_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../services/sync_service.dart'`.

- [ ] **Step 4: Implement the service**

Create `lib/services/sync_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';

import '../data/daily_log_repository.dart';
import '../data/settings_repository.dart';
import '../db/database.dart';
import 'sync_mapper.dart';
import 'sync_merge.dart';

/// Mirrors the local drift database into `users/{uid}` in the `lunatrack`
/// Firestore database.
///
/// Drift remains the single source of truth: the UI never waits on this, and
/// the app is fully usable offline. Sync is a mirror bolted alongside the
/// existing read/write path, never in front of it.
class SyncService {
  SyncService({
    required AppDatabase db,
    required FirebaseFirestore firestore,
    required this.uid,
    required this.deviceId,
  })  : _db = db,
        _firestore = firestore,
        _logs = DailyLogRepository(db),
        _settings = SettingsRepository(db);

  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  final DailyLogRepository _logs;
  final SettingsRepository _settings;
  final String uid;
  final String deviceId;

  bool _running = false;

  CollectionReference<Map<String, dynamic>> get _remoteLogs =>
      _firestore.collection('users/$uid/dailyLogs');

  DocumentReference<Map<String, dynamic>> get _remoteSettings =>
      _firestore.doc('users/$uid/settings/current');

  /// Runs one full push + pull cycle.
  ///
  /// `lastSyncedAt` advances ONLY on full success, so a partial failure simply
  /// re-attempts the same window next time. Re-pushing an already-pushed day is
  /// harmless because documents are keyed by date and writes are idempotent —
  /// the design tolerates duplicate work but never data loss.
  Future<void> syncNow() async {
    if (_running) return; // overlapping runs would fight over the same window
    _running = true;
    try {
      final row = await _settings.get();
      final since = row.lastSyncedAt;
      await _pushTombstones();
      await _pushLogs(since);
      await _pullLogs(since);
      await _pushSettings(row, since);
      await _pullSettings(since);
      // `updateSyncState`, NOT `update`: advancing the high-water mark is not a
      // user edit, and stamping `settingsUpdatedAt` here would make every sync
      // look like a settings change and push forever.
      await _settings.updateSyncState(
        AppSettingsCompanion(lastSyncedAt: Value(DateTime.now())),
      );
    } finally {
      _running = false;
    }
  }

  /// Deletions first: pushing a local row for a day that was just deleted
  /// elsewhere would otherwise recreate it.
  Future<void> _pushTombstones() async {
    for (final t in await _logs.getTombstones()) {
      await _remoteLogs.doc(syncDocId(t.date)).delete();
      await _logs.clearTombstone(t.date);
    }
  }

  Future<void> _pushLogs(DateTime? since) async {
    final rows = await _db.select(_db.dailyLogs).get();
    for (final row in rows) {
      if (since != null && !row.updatedAt.isAfter(since)) continue;
      await _remoteLogs
          .doc(syncDocId(row.date))
          .set(dailyLogToMap(row, deviceId: deviceId));
    }
  }

  Future<void> _pullLogs(DateTime? since) async {
    final snapshot = await _remoteLogs.get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final remoteUpdated = updatedAtFromMap(data);
      final companion = dailyLogFromMap(data);
      final local = await _logs.getForDate(companion.date.value);

      final decision = decideMerge(
        local: local?.updatedAt,
        remote: remoteUpdated,
      );
      if (decision != MergeDecision.takeRemote) continue;

      await _db.into(_db.dailyLogs).insertOnConflictUpdate(companion);
    }
  }

  /// Preference fields only.
  ///
  /// `premium` (a Play-account IAP entitlement), `appLockEnabled` (a per-device
  /// security choice), `onboardingComplete`, `lastSyncedAt` and `id` are
  /// deliberately device-local and never travel. Syncing `premium` in
  /// particular would let one purchase unlock ads on every device signed into
  /// the account, which is not what was bought.
  Future<void> _pushSettings(AppSetting row, DateTime? since) async {
    final changed = row.settingsUpdatedAt;
    if (changed == null) return; // never edited locally — nothing to push
    if (since != null && !changed.isAfter(since)) return;

    await _remoteSettings.set({
      'mode': row.mode.index,
      'defaultCycleLength': row.defaultCycleLength,
      'defaultPeriodLength': row.defaultPeriodLength,
      'themeMode': row.themeMode,
      'language': row.language,
      'genderNeutralLanguage': row.genderNeutralLanguage,
      'pregnancyStartDate': row.pregnancyStartDate?.millisecondsSinceEpoch,
      'trackingCategories': row.trackingCategories,
      'weightUnit': row.weightUnit,
      'updatedAt': changed.millisecondsSinceEpoch,
    });
  }

  Future<void> _pullSettings(DateTime? since) async {
    final doc = await _remoteSettings.get();
    final data = doc.data();
    if (data == null) return;

    final remoteUpdated = updatedAtFromMap(data);
    final local = (await _settings.get()).settingsUpdatedAt;
    if (decideMerge(local: local, remote: remoteUpdated) !=
        MergeDecision.takeRemote) {
      return;
    }

    final pregnancyMillis = data['pregnancyStartDate'] as int?;
    final modeIndex = data['mode'] as int?;
    await _settings.updateSyncState(
      AppSettingsCompanion(
        // Guard the enum index: a future version could write one this build
        // doesn't know, and losing one field beats failing the whole sync.
        mode: (modeIndex != null &&
                modeIndex >= 0 &&
                modeIndex < TrackingMode.values.length)
            ? Value(TrackingMode.values[modeIndex])
            : const Value.absent(),
        defaultCycleLength: Value(data['defaultCycleLength'] as int),
        defaultPeriodLength: Value(data['defaultPeriodLength'] as int),
        themeMode: Value(data['themeMode'] as String),
        language: Value(data['language'] as String),
        genderNeutralLanguage: Value(data['genderNeutralLanguage'] as bool),
        pregnancyStartDate: Value(pregnancyMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(pregnancyMillis)),
        trackingCategories: Value(data['trackingCategories'] as String?),
        weightUnit: Value(data['weightUnit'] as String?),
        settingsUpdatedAt: Value(remoteUpdated!),
      ),
    );
  }
}
```

Add `import '../models/enums.dart';` to the file's imports for `TrackingMode`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/sync_service_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 6: Commit**

```bash
flutter analyze && flutter test
git add lib/services/sync_service.dart test/sync_service_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: add SyncService with push, pull and tombstone propagation"
```

---

### Task 10: Claim existing local data on first sign-in

Anyone upgrading has local logs and no account. Without this they hit a sign-in wall in front of their own data.

**Files:**
- Create: `lib/screens/auth/claim_local_data_sheet.dart`
- Modify: `lib/screens/app_gate.dart` (show the sheet once when signed in with unclaimed local rows)
- Create: `test/claim_local_data_test.dart`

**Interfaces:**
- Consumes: `AuthProvider` (Task 6), `SyncService` (Task 9), `DailyLogRepository`.
- Produces: `Future<bool?> showClaimLocalDataSheet(BuildContext context, {required int dayCount})` — returns `true` to upload, `false` to keep local only, `null` if dismissed.

- [ ] **Step 1: Write the failing test**

Create `test/claim_local_data_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/screens/auth/claim_local_data_sheet.dart';

void main() {
  Future<bool?> show(WidgetTester tester, int count) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showClaimLocalDataSheet(context,
                    dayCount: count);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('states how many days are on the device', (tester) async {
    await show(tester, 42);
    expect(find.textContaining('42 days'), findsOneWidget);
  });

  testWidgets('adding to the account returns true', (tester) async {
    await show(tester, 3);
    await tester.tap(find.byKey(const Key('claim.upload')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('claim.upload')), findsNothing);
  });

  testWidgets('keeping data on the device offers a non-destructive choice',
      (tester) async {
    await show(tester, 3);

    // The decline path must be clearly non-destructive: it never deletes.
    expect(find.byKey(const Key('claim.keepLocal')), findsOneWidget);
    expect(find.textContaining('stay on this device'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/claim_local_data_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../claim_local_data_sheet.dart'`.

- [ ] **Step 3: Write the sheet**

Create `lib/screens/auth/claim_local_data_sheet.dart`:

```dart
import 'package:flutter/material.dart';

/// Asks whether the logs already on this device should be added to the account
/// that just signed in.
///
/// Declining must NEVER delete anything — the rows stay local and untouched.
/// Returns true to upload, false to keep local only, null if dismissed.
Future<bool?> showClaimLocalDataSheet(
  BuildContext context, {
  required int dayCount,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add your existing logs?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            'You have $dayCount days logged on this device. Add them to this '
            'account so they sync to your other devices? If you skip, they '
            'stay on this device and nothing is deleted.',
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('claim.upload'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add to my account'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('claim.keepLocal'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep on this device only'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/claim_local_data_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire the sheet into AppGate**

In `lib/screens/app_gate.dart`, add to `_AppGateState`:

```dart
  bool _claimPromptShown = false;

  /// Offers to upload pre-existing local logs the first time an account signs
  /// in on this device. Runs after the frame so it can show a modal sheet.
  void _maybePromptClaim(BuildContext context) {
    if (_claimPromptShown) return;
    _claimPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final db = context.read<AppDatabase>();
      final settings = context.read<SettingsProvider>();
      // Only ask when there is local data that predates this account.
      if (settings.lastSyncedAt != null) return;
      final count = (await DailyLogRepository(db).getAll()).length;
      if (count == 0 || !mounted) return;
      final upload = await showClaimLocalDataSheet(context, dayCount: count);
      if (upload != true || !mounted) return;
      await context.read<SyncTrigger>().syncNow();
    });
  }
```

Call it from `build`, immediately after the `AuthState.signedOut` branch:

```dart
    _maybePromptClaim(context);
```

Add the imports `../data/daily_log_repository.dart`, `../db/database.dart`, `auth/claim_local_data_sheet.dart`, and `../services/sync_trigger.dart`.

- [ ] **Step 6: Add the SyncTrigger the gate depends on**

Create `lib/services/sync_trigger.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../db/database.dart';
import 'device_id.dart';
import 'firestore_ref.dart';
import 'sync_service.dart';

/// Owns the current user's [SyncService] and exposes a single entry point the
/// UI can call. Rebuilt whenever the signed-in uid changes.
class SyncTrigger extends ChangeNotifier {
  SyncTrigger(this._db);
  final AppDatabase _db;

  String? _uid;
  SyncService? _service;

  /// Called when the signed-in user changes. A null uid tears sync down without
  /// touching local data — signing out must never wipe the device.
  Future<void> setUser(String? uid) async {
    if (uid == _uid) return;
    _uid = uid;
    if (uid == null) {
      _service = null;
      return;
    }
    _service = SyncService(
      db: _db,
      firestore: lunaFirestore(),
      uid: uid,
      deviceId: await DeviceId.get(),
    );
    await syncNow();
  }

  /// Coalesces bursts of local writes into one sync.
  ///
  /// The day editor saves the whole row on every field change, so syncing per
  /// write would fire a dozen times while a user fills in one day.
  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    // Network failures must never surface as a crash in the UI; the next
    // trigger retries the same window because lastSyncedAt did not advance.
    try {
      await _service?.syncNow();
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
```

Add `import 'dart:async';` to that file, and declare the field alongside `_service`:

```dart
  Timer? _debounce;
```

- [ ] **Step 7: Register SyncTrigger and drive it from auth + log changes**

In `lib/main.dart`, add `import 'services/sync_trigger.dart';` and register the trigger immediately after the `AuthProvider` entry:

```dart
        ChangeNotifierProvider(create: (_) => SyncTrigger(database)),
```

Then, still inside the `providers:` list, add this after the existing `ProxyProvider2` entries — it is the debounced post-write trigger from design spec §4.5:

```dart
        // Local writes schedule a debounced sync. Returns void because nothing
        // consumes it; it exists purely for the side effect of reacting to a
        // LogProvider change.
        ProxyProvider2<LogProvider, SyncTrigger, void>(
          update: (_, log, trigger, _) => trigger.scheduleSync(),
        ),
```

Finally, in `LunaTrackApp.build`, wrap the existing `Consumer<SettingsProvider>` so a change of signed-in user rebuilds the sync service:

```dart
      child: Consumer2<AuthProvider, SyncTrigger>(
        builder: (context, auth, trigger, child) {
          // Fire-and-forget: the UI never blocks on sync. A null uid tears sync
          // down and leaves local data alone.
          trigger.setUser(auth.user?.uid);
          return child!;
        },
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) {
            // …existing MaterialApp body, unchanged…
          },
        ),
      ),
```

- [ ] **Step 8: Sync on app resume**

`_AppGateState` already implements `WidgetsBindingObserver` for the app lock. Extend its existing `didChangeAppLifecycleState` (`lib/screens/app_gate.dart:34-42`) by adding a resumed branch:

```dart
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      // Pull anything logged on another device while we were away.
      context.read<SyncTrigger>().syncNow();
    }
```

- [ ] **Step 9: Expose lastSyncedAt on SettingsProvider**

The claim prompt reads it to tell a brand-new account from one that has already synced. In `lib/providers/settings_provider.dart`, alongside the existing getters:

```dart
  DateTime? get lastSyncedAt => _settings?.lastSyncedAt;
```

- [ ] **Step 10: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: all pass. Any widget test that pumps `AppGate` now also needs a
`SyncTrigger` in its provider wrapper.

- [ ] **Step 11: Commit**

```bash
git add lib/screens/auth/claim_local_data_sheet.dart lib/screens/app_gate.dart \
        lib/services/sync_trigger.dart lib/providers/settings_provider.dart lib/main.dart \
        test/claim_local_data_test.dart
git commit -m "feat: sync on sign-in, resume and local writes, and claim existing logs"
```

---

### Task 11: Account section in Settings, with deletion

**Files:**
- Create: `lib/services/account_deletion_service.dart`
- Create: `lib/screens/settings/account_section.dart`
- Modify: `lib/screens/settings/settings_screen.dart` (insert the section)
- Create: `test/account_deletion_test.dart`

**Interfaces:**
- Consumes: `AuthService` (Task 6), `lunaFirestore()` (Task 1).
- Produces: `class AccountDeletionService { Future<void> deleteEverything(); }` and `AccountSection` widget.

- [ ] **Step 1: Write the failing test**

Create `test/account_deletion_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/account_deletion_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> seed(String uid) async {
    await firestore.collection('users/$uid/dailyLogs').doc('2026-08-04').set(
      {'date': '2026-08-04', 'symptoms': <String, dynamic>{}},
    );
    await firestore.collection('users/$uid/settings').doc('current').set(
      {'defaultCycleLength': 28},
    );
    await firestore.doc('users/$uid').set({'email': 'a@b.com'});
  }

  test('deletes the whole user subtree, not just the root document', () async {
    await seed('uid-1');

    await AccountDeletionService(firestore: firestore, uid: 'uid-1')
        .deleteFirestoreData();

    // Deleting only `users/{uid}` would leave these orphaned and unreachable —
    // a Play policy violation and a real privacy failure.
    expect(
      (await firestore.collection('users/uid-1/dailyLogs').get()).docs,
      isEmpty,
    );
    expect(
      (await firestore.collection('users/uid-1/settings').get()).docs,
      isEmpty,
    );
    expect((await firestore.doc('users/uid-1').get()).exists, isFalse);
  });

  test('never touches another user\'s data', () async {
    await seed('uid-1');
    await seed('uid-2');

    await AccountDeletionService(firestore: firestore, uid: 'uid-1')
        .deleteFirestoreData();

    expect(
      (await firestore.collection('users/uid-2/dailyLogs').get()).docs,
      hasLength(1),
    );
  });

  test('re-running after a partial delete completes cleanly', () async {
    await seed('uid-1');
    final service = AccountDeletionService(firestore: firestore, uid: 'uid-1');

    await service.deleteFirestoreData();
    await service.deleteFirestoreData(); // resumable, must not throw

    expect((await firestore.doc('users/uid-1').get()).exists, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/account_deletion_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../account_deletion_service.dart'`.

- [ ] **Step 3: Implement**

Create `lib/services/account_deletion_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Deletes a user's server-side data.
///
/// Firestore does NOT delete subcollections when a parent document is deleted,
/// so removing `users/{uid}` alone leaves the health data orphaned and
/// unreachable — a Google Play User Data policy violation as well as a genuine
/// privacy failure. Every known subcollection is deleted explicitly.
///
/// The order matters: subcollections first, root document last. A crash
/// mid-delete therefore leaves the root document present, so re-running finds
/// and finishes the job. Running it twice is safe.
class AccountDeletionService {
  AccountDeletionService({required this.firestore, required this.uid});

  final FirebaseFirestore firestore;
  final String uid;

  /// Every subcollection under `users/{uid}`. Adding a new one to the sync
  /// model REQUIRES adding it here, or deletion silently leaves data behind.
  static const _subcollections = ['dailyLogs', 'settings'];

  Future<void> deleteFirestoreData() async {
    for (final name in _subcollections) {
      // Page through in batches: a long-running user could have thousands of
      // days, and a single unbounded read can exhaust memory.
      while (true) {
        final batch = await firestore
            .collection('users/$uid/$name')
            .limit(300)
            .get();
        if (batch.docs.isEmpty) break;
        final writes = firestore.batch();
        for (final doc in batch.docs) {
          writes.delete(doc.reference);
        }
        await writes.commit();
      }
    }
    await firestore.doc('users/$uid').delete();
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/account_deletion_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Add the Settings account section**

Create `lib/screens/settings/account_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../db/database.dart';
import '../../providers/auth_provider.dart';
import '../../services/account_deletion_service.dart';
import '../../services/firestore_ref.dart';

/// Signed-in identity, sign-out, and account deletion.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  Future<void> _confirmDelete(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and every log stored in the '
          'cloud. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('account.confirmDelete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final db = context.read<AppDatabase>();

    // Firestore data FIRST: deleting the auth user first would leave the
    // subtree orphaned with no identity able to reach it.
    await AccountDeletionService(firestore: lunaFirestore(), uid: uid)
        .deleteFirestoreData();
    // Then the local mirror. Without this the logs stay on the device, and the
    // claim-local-data prompt would offer to upload the "deleted" data into the
    // next account created here.
    await db.deleteAllData();
    await auth.deleteAccount();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Account'),
          subtitle: Text(auth.user?.email ?? 'Not signed in'),
        ),
        ListTile(
          key: const Key('account.signOut'),
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          subtitle: const Text('Your logs stay on this device'),
          onTap: () => context.read<AuthProvider>().signOut(),
        ),
        ListTile(
          key: const Key('account.delete'),
          leading: Icon(
            Icons.delete_forever,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Delete account'),
          subtitle: const Text('Permanently removes your cloud data'),
          onTap: () => _confirmDelete(context),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Add deleteAccount to AuthProvider**

In `lib/providers/auth_provider.dart`, add alongside the other actions:

```dart
  Future<void> deleteAccount() => _guard(_service.deleteAccount);
```

- [ ] **Step 7: Insert the section into Settings**

In `lib/screens/settings/settings_screen.dart`, add the import
`import 'account_section.dart';` and place `const AccountSection(),` as the
**first** child of the settings list, above the existing entries.

- [ ] **Step 8: Correct the deleteAllData doc comment**

`AppDatabase.deleteAllData` (`lib/db/database.dart:53`) documents itself as "no
accounts, so this is the full right-to-erasure path". That stops being true once
data also lives server-side, and leaving it would mislead the next contributor
into treating the local wipe as sufficient. Replace the doc comment with:

```dart
  /// Wipes all LOCAL user data and resets settings to defaults.
  ///
  /// This is NOT the full right-to-erasure path any more — logs also live in
  /// Firestore under `users/{uid}`. Erasure means
  /// `AccountDeletionService.deleteFirestoreData()` AND this. The in-app
  /// "delete all my data" control clears the device; "Delete account"
  /// (Settings → Account) does both.
```

- [ ] **Step 9: Run the full suite and commit**

```bash
flutter analyze && flutter test
git add lib/services/account_deletion_service.dart lib/screens/settings/account_section.dart \
        lib/screens/settings/settings_screen.dart lib/providers/auth_provider.dart \
        lib/db/database.dart test/account_deletion_test.dart
git commit -m "feat: add account section with sign-out and full account deletion"
```

---

### Task 12: Security rules and emulator tests

The highest-value task in the plan: with plaintext storage, this file is the only thing between one user's menstrual history and every other account in a five-product Firebase project.

**Files:**
- Create: `firestore.rules`
- Create: `firebase.json`
- Create: `.firebaserc`
- Create: `firebase_test/package.json`
- Create: `firebase_test/rules.test.js`
- Modify: `.gitignore` (add `firebase_test/node_modules/`)

**Interfaces:**
- Consumes: the Firestore layout from Tasks 9 and 11.
- Produces: a deployed ruleset for the `lunatrack` database.

- [ ] **Step 1: Write the rules**

Create `firestore.rules`:

```js
rules_version = '2';

// LunaTrack — named database `lunatrack` in project hbgapp-c3c88.
//
// The project is shared with four unrelated apps, and health data is stored in
// PLAINTEXT, so this ruleset is the entire privacy boundary. The uid check is
// load-bearing: a bare `request.auth != null` would expose every user's
// menstrual history to any signed-in user of ANY app in the project.
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId;
    }
  }
}
```

- [ ] **Step 2: Add the Firebase CLI config**

Create `.firebaserc`:

```json
{
  "projects": {
    "default": "hbgapp-c3c88"
  }
}
```

Create `firebase.json` — note the `database` key, which targets the named database rather than `(default)`:

```json
{
  "firestore": [
    {
      "database": "lunatrack",
      "rules": "firestore.rules"
    }
  ],
  "emulators": {
    "firestore": { "port": 8080 },
    "ui": { "enabled": false }
  }
}
```

- [ ] **Step 3: Write the failing rules test**

Create `firebase_test/package.json`:

```json
{
  "name": "lunatrack-rules-tests",
  "private": true,
  "scripts": {
    "test": "firebase emulators:exec --only firestore --project hbgapp-c3c88 'jest --runInBand'"
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^3.0.4",
    "jest": "^29.7.0"
  }
}
```

Create `firebase_test/rules.test.js`:

```js
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'hbgapp-c3c88',
    firestore: {
      rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(() => testEnv.cleanup());
beforeEach(() => testEnv.clearFirestore());

const dayPath = (uid) => `users/${uid}/dailyLogs/2026-08-04`;
const day = { date: '2026-08-04', flow: 2, symptoms: { cramps: true } };

test('a user can write and read their own day log', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(db.doc(dayPath('alice')).set(day));
  await assertSucceeds(db.doc(dayPath('alice')).get());
});

// THE test. `request.auth != null` instead of a uid comparison is the single
// most common Firestore vulnerability, and in this shared project it would
// expose menstrual data to users of four unrelated apps.
test('a signed-in user CANNOT read another user\'s day log', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(dayPath('alice')).set(day);
  });
  const mallory = testEnv.authenticatedContext('mallory').firestore();
  await assertFails(mallory.doc(dayPath('alice')).get());
});

test('a signed-in user CANNOT write to another user\'s subtree', async () => {
  const mallory = testEnv.authenticatedContext('mallory').firestore();
  await assertFails(mallory.doc(dayPath('alice')).set(day));
});

test('an unauthenticated client can read nothing', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(dayPath('alice')).set(day);
  });
  const anon = testEnv.unauthenticatedContext().firestore();
  await assertFails(anon.doc(dayPath('alice')).get());
});

test('a user cannot list the whole users collection', async () => {
  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertFails(alice.collection('users').get());
});

test('settings are protected by the same uid rule', async () => {
  const alice = testEnv.authenticatedContext('alice').firestore();
  await assertSucceeds(
    alice.doc('users/alice/settings/current').set({ defaultCycleLength: 28 }),
  );
  const mallory = testEnv.authenticatedContext('mallory').firestore();
  await assertFails(mallory.doc('users/alice/settings/current').get());
});
```

- [ ] **Step 4: Install and run the rules tests**

```bash
cd firebase_test && npm install && npm test
```

Expected: 6 tests PASS. If `a signed-in user CANNOT read another user's day log` fails, the rules use a bare `request.auth != null` — fix `firestore.rules` before going further.

- [ ] **Step 5: Ignore node_modules**

Add to `.gitignore`:

```
firebase_test/node_modules/
```

- [ ] **Step 6: Deploy the rules**

```bash
cd .. && firebase deploy --only firestore:rules --project hbgapp-c3c88
```

Expected: deploy succeeds and reports the `lunatrack` database. **Verify in the console that the `(default)` database's rules were NOT modified** — four other apps depend on them.

- [ ] **Step 7: Commit**

```bash
git add firestore.rules firebase.json .firebaserc firebase_test/package.json \
        firebase_test/package-lock.json firebase_test/rules.test.js .gitignore
git commit -m "feat: add uid-scoped Firestore rules with emulator tests"
```

---

### Task 13: Compliance and documentation

Not optional. Shipping accounts without this makes the published privacy policy false and breaches Google Play's User Data policy.

**Files:**
- Modify: `PRIVACY_POLICY.md`
- Modify: `CLAUDE.md` (project overview + architecture + schema sections)
- Create: `docs/account-deletion.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.
- Produces: accurate user-facing disclosures.

- [ ] **Step 1: Rewrite the privacy policy**

`PRIVACY_POLICY.md` currently states data never leaves the device. That becomes false the moment this ships. Replace the data-handling section with:

```markdown
## What we collect and where it is stored

LunaTrack requires an account (email address and password). When you are signed
in, the following is stored on Google Cloud infrastructure (Firebase Firestore),
associated with your account:

- Daily logs: flow, symptoms, mood, notes, basal body temperature, ovulation
  test results, and any optional tracking categories you enable (including
  medication, sexual activity, weight, and diary notes).
- Your app settings and preferences.

This data is stored in an identifiable form and is readable by the operator of
the service. It is not sold, and it is not shared with advertisers.

Reminders you schedule remain on your device and are never uploaded.

## Retention and deletion

Your data is retained until you delete it. You can permanently delete your
account and all associated cloud data from **Settings → Account → Delete
account** inside the app. You can also request deletion without the app — see
`docs/account-deletion.md`.

## Advertising

Ads are non-personalised and are never shown on the logging or insights screens.
Ad partners do not receive your health data.
```

- [ ] **Step 2: Write the off-app deletion route**

Google Play requires a web-accessible deletion request route in the store listing. Create `docs/account-deletion.md`:

```markdown
# Deleting your LunaTrack account

## In the app (immediate)

Settings → Account → **Delete account**. This permanently removes your account
and every log stored in the cloud. It cannot be undone.

## Without the app

Email the address listed on the Play Store listing from the address you signed
up with, with the subject "Delete my LunaTrack account". The account and all
associated data are deleted within 30 days.

## What is deleted

Everything under your account: all daily logs (flow, symptoms, mood, notes,
BBT, OPK, and every optional tracking category), your settings, and the account
itself. Logs held only on your device are removed when you uninstall the app.
```

- [ ] **Step 3: Correct CLAUDE.md**

The "Project overview" section still claims no backend and no account. Replace the core-thesis paragraph with:

```markdown
**LunaTrack** is a menstrual/period tracker built with Flutter, with an account
and cross-device sync.

- **Accounts are required** (Firebase Auth, email/password). Daily logs and
  settings sync to Firestore in **plaintext** under `users/{uid}`.
- **Drift remains the single source of truth.** The UI never reads from or
  writes to Firestore directly; `SyncService` mirrors drift ⇄ Firestore, so the
  app stays fully usable offline.
- **Firebase project `hbgapp-c3c88`, named database `lunatrack`.** Never use
  `FirebaseFirestore.instance` (it targets `(default)`, which is shared with
  four unrelated apps under one ruleset) — always use `lunaFirestore()` from
  `lib/services/firestore_ref.dart`.
- **Firebase Auth's user pool is project-wide**, so LunaTrack shares its user
  list with those four apps. Rules key on `uid`, so no data crosses over.
- Reminders, medications, and period entries are deliberately NOT synced.
- Conflicts resolve **last-write-wins per day** on `DailyLogs.updatedAt`.
  Field-level merge is deliberately avoided: `encodeDayTags` is a full REPLACE,
  so merging tags across devices would fabricate entries the user never made.
- Deletions propagate through the `SyncTombstones` table, not a soft-delete
  flag — a flag would require `where(deleted == false)` on every existing read
  path.
```

In the "Schema & migrations" bullet, change `schemaVersion` is **4** to **5** and append:

```markdown
  v4→v5 added the `SyncTombstones` table plus `AppSettings.lastSyncedAt` and
  `AppSettings.settingsUpdatedAt`. Note the two settings-repository entry
  points: `update()` stamps `settingsUpdatedAt` (a user edit, so it pushes),
  `updateSyncState()` deliberately does not (sync bookkeeping — stamping it
  would make every sync look like an edit and push forever).
```

Also add to the "Key design decisions" list:

```markdown
- **Only preference settings sync.** `premium` (a Play-account IAP entitlement),
  `appLockEnabled` (a per-device security choice), `onboardingComplete` and the
  sync bookkeeping columns are deliberately device-local. Syncing `premium`
  would unlock ads on every device signed into the account, which is not what
  was purchased.
```

- [ ] **Step 4: Note the Play Data Safety changes**

Add to `README.md` under the `## Firebase setup` heading added in Task 1:

```markdown
### Before publishing

The Play **Data Safety** form must declare health data as **collected AND
transmitted**, tied to the user's identity, with the account-deletion route from
`docs/account-deletion.md`. The store listing must include the deletion URL.
Shipping accounts without these is a User Data policy violation.
```

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze && flutter test
cd firebase_test && npm test && cd ..
git add PRIVACY_POLICY.md CLAUDE.md docs/account-deletion.md README.md
git commit -m "docs: disclose cloud storage, account deletion and the sync architecture"
```

---

## Final verification

- [ ] `flutter analyze` clean
- [ ] `flutter test` — all green (expect ~345 tests: 308 existing + ~37 new)
- [ ] `cd firebase_test && npm test` — 6 rules tests green, including cross-user denial
- [ ] `flutter build apk --release` succeeds
- [ ] `grep -rn "FirebaseFirestore.instance" lib/` returns **nothing** (only `instanceFor` via `lunaFirestore()`)
- [ ] Manual device check: sign up → log a day → sign out → sign in on a second device → the day appears
- [ ] Manual device check: airplane mode → log a day → the app works → reconnect → the day syncs
- [ ] Manual device check: change a setting on device A → it appears on device B
- [ ] Manual device check: Settings → Account → Delete account → the Firestore subtree is gone in the console AND the device's local logs are cleared
- [ ] Manual device check: sign out → local logs are still there → sign in again → no duplicate days
- [ ] Console check: the `(default)` database's rules are unchanged (four other apps depend on them)
