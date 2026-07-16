# One-Tap Check-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user answer the daily period check-in in one tap from the notification shade (Phase A) and the home-screen widget (Phase B), without opening the app.

**Architecture:** A pure planner precomputes one notification per day for a 14-day horizon (safe because `CycleCheckInService.evaluate()` is deterministic and logs cannot change while the app is closed). Tapping an action wakes a background isolate, which registers plugins, opens the **encrypted** DB via the OS keystore, writes one column through `setFlowIfEmpty`, then reschedules the horizon and refreshes the widget. Phase B reuses that same `CheckInWriter` behind widget buttons.

**Tech Stack:** Flutter, drift (SQLite via sqlite3mc, encrypted), provider, `flutter_local_notifications` **22.0.1**, `flutter_local_notifications_platform_interface` 9.1.0, `home_widget` **0.9.3**, `flutter_secure_storage` 10.x, Kotlin/RemoteViews (Android).

**Spec:** `docs/superpowers/specs/2026-07-16-one-tap-check-in-design.md`

## Global Constraints

- **Never** the word "safe" near any fertility/ovulation surface. Check-in is period-timing only — no fertility framing.
- **No health data outside the encrypted DB.** A `SharedPreferences` "pending log" queue is explicitly rejected. (Pre-existing exception: the widget's `value`/`caption` strings — see Task 7 note.)
- **No new user-facing sentences.** All copy is reused verbatim from `lib/widgets/period_check_in_banner.dart`. The i18n sweep (#6) is deferred; new strings add debt.
- Copy, verbatim: `didItStart` → body `'Your period was expected around now.'`, action `"Didn't start"`. `hasItEnded` → body `'This period has run to its usual length.'`, action `'Mark ended here'`. Generic fallback → title `'How are you today?'`, body `'Tap to log your flow and symptoms.'`. Check-in notification title: `'LunaTrack'`.
- Both one-tap answers write exactly `FlowIntensity.none`. There is **no** one-tap "yes".
- `visibility: NotificationVisibility.secret` on check-in notifications.
- Horizon = **14 days**. `idCheckInBase = 4000` (ids `4000..4013`). Must not collide with medications (2000+) or custom reminders (3000+).
- The horizon is gated on the existing `ReminderType.logNudge` toggle and uses its hour/minute.
- `minSdk = 26`. Android-only for actions/widget buttons; iOS gets notifications without buttons.
- Local notifications only — no FCM, no server. The `$0`/on-device thesis is non-negotiable.
- `flutter analyze` clean and **all tests green** before every commit.

## Verified API facts (do not re-derive)

- `initialize({required InitializationSettings settings, DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse, DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse})` — `flutter_local_notifications_plugin.dart:111`.
- `DidReceiveBackgroundNotificationResponseCallback = void Function(NotificationResponse)`.
- `NotificationResponse` fields: `id`, `actionId`, `input`, `payload`, `data`.
- `AndroidNotificationAction(String id, String title, {bool showsUserInterface = false, bool cancelNotification = true, ...})` — `cancelNotification` defaults **true**, so the notification dismisses itself on tap. No manual cancel needed.
- `AndroidNotificationDetails(..., NotificationVisibility? visibility, List<AndroidNotificationAction>? actions)`.
- `NotificationVisibility.{private, public, secret}`.
- **Visibility works, but subtly:** the plugin calls `builder.setVisibility(...)` on the *notification* (`FlutterLocalNotificationsPlugin.java:931`) and never `setLockscreenVisibility` on the *channel*. At `minSdk 26` the channel would supersede the notification — but `NotificationChannel` defaults to `VISIBILITY_NO_OVERRIDE`, which defers to the notification's value. So reusing the existing `cycle_reminders` channel is safe. **Limit:** `SECRET` only hides on a *secure* lock screen; a swipe-only device has nothing to protect.
- `PredictionService.predict(List<Cycle> cycles, {int fallbackCycleLength = 28, int fallbackPeriodLength = 5, DateTime? asOf, bool capConfidenceToLow = false, List<DailyLog> logs = const []})`.
- `HomeWidgetBackgroundIntent.getBroadcast(context, uri)` (Kotlin) + `HomeWidget.registerInteractivityCallback(FutureOr<void> Function(Uri?))` (Dart).
- Tests use `AppDatabase.forTesting(NativeDatabase.memory())`; test files are `test/<feature>_test.dart`.

---

### Task 1: `setFlowIfEmpty` — make data-preservation structural

`DailyLogRepository.upsert()` rewrites the whole row. `PeriodCheckInBanner._mark` currently dodges that by re-passing `existing?.symptoms`, `existing?.mood`, … — a convention every caller must remember, and a read-modify-write a background isolate would race. This task replaces the convention with a guarantee.

**Files:**
- Modify: `lib/data/daily_log_repository.dart`
- Test: `test/check_in_write_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `Future<bool> DailyLogRepository.setFlowIfEmpty({required DateTime date, required FlowIntensity flow})` — returns `true` if it wrote, `false` if the day already had a flow.

- [ ] **Step 1: Write the failing test**

Create `test/check_in_write_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/data/daily_log_repository.dart';
import 'package:menstrul_track/db/database.dart';
import 'package:menstrul_track/models/enums.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('writes flow on an empty day', () async {
    final repo = DailyLogRepository(db);
    final day = DateTime(2026, 7, 16);

    final wrote = await repo.setFlowIfEmpty(date: day, flow: FlowIntensity.none);

    expect(wrote, isTrue);
    expect((await repo.getForDate(day))!.flow, FlowIntensity.none);
  });

  test('preserves symptoms/mood/notes/bbt/opk — the whole point', () async {
    final repo = DailyLogRepository(db);
    final day = DateTime(2026, 7, 16);
    await repo.upsert(
      date: day,
      symptomsJson: '{"cramps":true}',
      mood: 'calm',
      notes: 'kept',
      bbt: 36.6,
      opk: 'positive',
    );

    final wrote = await repo.setFlowIfEmpty(date: day, flow: FlowIntensity.none);

    expect(wrote, isTrue);
    final log = (await repo.getForDate(day))!;
    expect(log.flow, FlowIntensity.none);
    expect(log.symptoms, '{"cramps":true}');
    expect(log.mood, 'calm');
    expect(log.notes, 'kept');
    expect(log.bbt, 36.6);
    expect(log.opk, 'positive');
  });

  test('never overwrites a flow the user already logged (idempotent; stale '
      'notification and double-tap are both no-ops)', () async {
    final repo = DailyLogRepository(db);
    final day = DateTime(2026, 7, 16);
    await repo.upsert(date: day, flow: FlowIntensity.heavy, symptomsJson: '{}');

    final wrote = await repo.setFlowIfEmpty(date: day, flow: FlowIntensity.none);

    expect(wrote, isFalse);
    expect((await repo.getForDate(day))!.flow, FlowIntensity.heavy);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/check_in_write_test.dart`
Expected: FAIL — `The method 'setFlowIfEmpty' isn't defined for the type 'DailyLogRepository'`.

- [ ] **Step 3: Write minimal implementation**

In `lib/data/daily_log_repository.dart`, add after `setBbtIfEmpty`:

```dart
  /// Records [flow] for [date] ONLY if the day has no flow yet, touching ONLY
  /// the `flow` column so symptoms/mood/notes/bbt/opk survive. Mirrors
  /// [setBbtIfEmpty]: single-column, non-destructive, idempotent.
  ///
  /// This is what makes the notification/widget check-in safe. [upsert] rewrites
  /// the whole row, so a background caller using it would erase a day the user
  /// had already filled in. Here that is impossible by construction rather than
  /// by remembering to re-pass every field.
  ///
  /// Idempotency falls out for free: a double-tap, or a notification scheduled
  /// days ago and answered in-app since, both no-op — the log IS the answer flag
  /// (see [CycleCheckInService]).
  ///
  /// Returns true if a value was written.
  Future<bool> setFlowIfEmpty({
    required DateTime date,
    required FlowIntensity flow,
  }) async {
    final d = dateOnly(date);
    final existing = await getForDate(d);
    if (existing == null) {
      await _db.into(_db.dailyLogs).insert(
            DailyLogsCompanion.insert(date: d, flow: Value(flow)),
          );
      return true;
    }
    if (existing.flow != null) return false; // already answered
    await (_db.update(_db.dailyLogs)..where((t) => t.id.equals(existing.id)))
        .write(DailyLogsCompanion(
      flow: Value(flow),
      updatedAt: Value(DateTime.now()),
    ));
    return true;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/check_in_write_test.dart && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/data/daily_log_repository.dart test/check_in_write_test.dart
git commit -m "feat: add non-destructive setFlowIfEmpty for background check-in writes"
```

---

### Task 2: Pure horizon planner

**Files:**
- Create: `lib/services/check_in_notifications.dart`
- Test: `test/check_in_horizon_test.dart` (create)

**Interfaces:**
- Consumes: `CycleCheckInService.evaluate({logs, prediction, today})`, `CheckInPrompt`.
- Produces:
  - `class CheckInSlot { final int dayOffset; final DateTime date; final CheckInPrompt prompt; }`
  - `CheckInPlanner.horizonDays` → `int` (14)
  - `CheckInPlanner.plan({required List<DailyLog> logs, required PredictionResult prediction, required DateTime today})` → `List<CheckInSlot>`
  - `CheckInPlanner.slotsToSchedule({required List<DailyLog> logs, required PredictionResult prediction, required DateTime today, required bool enabled})` → `List<CheckInSlot>` (empty when `enabled == false`)
  - `CheckInCopy.title(CheckInPrompt)` → `String`; `CheckInCopy.body(CheckInPrompt)` → `String`; `CheckInCopy.actionLabel(CheckInPrompt)` → `String?` (null ⇒ no button); `CheckInCopy.actionId` → `String`

- [ ] **Step 1: Write the failing test**

Create `test/check_in_horizon_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/models/enums.dart';
import 'package:menstrul_track/models/prediction.dart';
import 'package:menstrul_track/services/check_in_notifications.dart';
import 'package:menstrul_track/services/cycle_check_in.dart';

void main() {
  // Copied verbatim from test/cycle_check_in_test.dart — PredictionResult has
  // no `.empty()` constructor; every field is required.
  PredictionResult pred({DateTime? next, int avgPeriod = 5}) => PredictionResult(
        averageCycleLength: 28,
        cycleVariabilityDays: 1,
        averagePeriodLength: avgPeriod,
        cyclesTracked: 3,
        confidence: PredictionConfidence.high,
        lastPeriodStart: DateTime(2026, 1, 1),
        cycleDay: 1,
        currentPhase: CyclePhase.luteal,
        nextPeriodStart: next,
        nextPeriodWindowStart: next,
        nextPeriodWindowEnd: next,
        ovulationDay: null,
        fertileWindowStart: null,
        fertileWindowEnd: null,
      );

  test('plans exactly one slot per day for the horizon', () {
    final today = DateTime(2026, 7, 16);
    final prediction = pred();

    final slots =
        CheckInPlanner.plan(logs: const [], prediction: prediction, today: today);

    expect(slots.length, CheckInPlanner.horizonDays);
    expect(slots.first.dayOffset, 0);
    expect(slots.first.date, today);
    expect(slots.last.dayOffset, CheckInPlanner.horizonDays - 1);
    expect(slots.last.date, today.add(Duration(days: CheckInPlanner.horizonDays - 1)));
  });

  test('a day with no question still gets the generic nudge — never two '
      'notifications, never zero', () {
    final today = DateTime(2026, 7, 16);
    // nextPeriodStart: null ⇒ nothing is due ⇒ evaluate() returns none.
    final prediction = pred();

    final slots =
        CheckInPlanner.plan(logs: const [], prediction: prediction, today: today);

    // No prediction => nothing to ask.
    expect(slots.every((s) => s.prompt == CheckInPrompt.none), isTrue);
    expect(CheckInCopy.title(CheckInPrompt.none), 'How are you today?');
    expect(CheckInCopy.body(CheckInPrompt.none), 'Tap to log your flow and symptoms.');
    expect(CheckInCopy.actionLabel(CheckInPrompt.none), isNull);
  });

  test('copy is reused verbatim from the Home card', () {
    expect(CheckInCopy.body(CheckInPrompt.didItStart),
        'Your period was expected around now.');
    expect(CheckInCopy.actionLabel(CheckInPrompt.didItStart), "Didn't start");
    expect(CheckInCopy.body(CheckInPrompt.hasItEnded),
        'This period has run to its usual length.');
    expect(CheckInCopy.actionLabel(CheckInPrompt.hasItEnded), 'Mark ended here');
  });

  test('GUARDRAIL: a disabled logNudge schedules NOTHING — never resurrect '
      'notifications the user turned off', () {
    final today = DateTime(2026, 7, 16);
    // nextPeriodStart: null ⇒ nothing is due ⇒ evaluate() returns none.
    final prediction = pred();

    expect(
      CheckInPlanner.slotsToSchedule(
        logs: const [],
        prediction: prediction,
        today: today,
        enabled: false,
      ),
      isEmpty,
    );
    expect(
      CheckInPlanner.slotsToSchedule(
        logs: const [],
        prediction: prediction,
        today: today,
        enabled: true,
      ),
      hasLength(CheckInPlanner.horizonDays),
    );
  });

  test('GUARDRAIL: no check-in copy ever says "safe" or frames fertility', () {
    for (final p in CheckInPrompt.values) {
      final text = '${CheckInCopy.title(p)} ${CheckInCopy.body(p)} '
          '${CheckInCopy.actionLabel(p) ?? ''}'.toLowerCase();
      expect(text.contains('safe'), isFalse, reason: 'never "safe": $p');
      expect(text.contains('fertile'), isFalse, reason: 'period timing only: $p');
      expect(text.contains('ovulation'), isFalse, reason: 'period timing only: $p');
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/check_in_horizon_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:menstrul_track/services/check_in_notifications.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `lib/services/check_in_notifications.dart`:

```dart
import '../common/date_utils.dart';
import '../db/database.dart';
import '../models/prediction.dart';
import 'cycle_check_in.dart';

/// One day's slot in the notification horizon. [dayOffset] doubles as the
/// notification-id offset from `NotificationService.idCheckInBase`.
class CheckInSlot {
  const CheckInSlot({
    required this.dayOffset,
    required this.date,
    required this.prompt,
  });

  final int dayOffset;
  final DateTime date;

  /// [CheckInPrompt.none] means "no question today" → the generic nudge.
  final CheckInPrompt prompt;
}

/// Precomputes which question (if any) each of the next [horizonDays] days
/// should ask.
///
/// WHY A HORIZON. `zonedSchedule` bakes a notification's text in at schedule
/// time, but the check-in question depends on (logs, prediction, today). A
/// single repeating notification therefore cannot ask the right thing. This is
/// only sound because [CycleCheckInService.evaluate] is pure and deterministic,
/// and logs CANNOT change while the app is closed — except via our own
/// notification action, whose background handler reschedules the horizon.
///
/// TRADE-OFF: the horizon only extends when the app is opened or an action is
/// tapped. A user idle longer than [horizonDays] stops being nudged. Accepted:
/// someone silent for two weeks has churned for reasons a notification will not
/// fix. A WorkManager job to extend it was rejected as a new dependency and a
/// new background-execution surface for a case that does not matter.
class CheckInPlanner {
  const CheckInPlanner._();

  static const int horizonDays = 14;

  static List<CheckInSlot> plan({
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required DateTime today,
  }) {
    final start = dateOnly(today);
    return List<CheckInSlot>.generate(horizonDays, (i) {
      final date = start.add(Duration(days: i));
      return CheckInSlot(
        dayOffset: i,
        date: date,
        prompt: CycleCheckInService.evaluate(
          logs: logs,
          prediction: prediction,
          today: date,
        ),
      );
    });
  }

  /// [plan] gated on the user's existing `ReminderType.logNudge` toggle.
  ///
  /// Kept pure and separate from the scheduling loop so this rule is TESTABLE:
  /// `NotificationService` is plugin-bound and cannot be exercised under
  /// `flutter test`, but "disabled ⇒ schedule nothing" is the one rule that
  /// must never regress. Scheduling check-ins for someone who turned
  /// notifications off would be a bug, not a feature.
  static List<CheckInSlot> slotsToSchedule({
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required DateTime today,
    required bool enabled,
  }) =>
      enabled
          ? plan(logs: logs, prediction: prediction, today: today)
          : const <CheckInSlot>[];
}

/// Notification copy. Every string is reused VERBATIM from
/// `widgets/period_check_in_banner.dart` so the notification is a remote control
/// for the Home card, not a second source of truth — and so the deferred i18n
/// sweep (#6) gains no new debt.
class CheckInCopy {
  const CheckInCopy._();

  /// Sent back as `NotificationResponse.actionId`.
  static const String actionId = 'check_in_no_bleeding';

  static String title(CheckInPrompt prompt) =>
      prompt == CheckInPrompt.none ? 'How are you today?' : 'LunaTrack';

  static String body(CheckInPrompt prompt) => switch (prompt) {
        CheckInPrompt.none => 'Tap to log your flow and symptoms.',
        CheckInPrompt.didItStart => 'Your period was expected around now.',
        CheckInPrompt.hasItEnded => 'This period has run to its usual length.',
      };

  /// null ⇒ no action button (the generic nudge just opens the app).
  static String? actionLabel(CheckInPrompt prompt) => switch (prompt) {
        CheckInPrompt.none => null,
        CheckInPrompt.didItStart => "Didn't start",
        CheckInPrompt.hasItEnded => 'Mark ended here',
      };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/check_in_horizon_test.dart && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/check_in_notifications.dart test/check_in_horizon_test.dart
git commit -m "feat: add pure check-in notification horizon planner"
```

---

### Task 3: Notification actions, secret visibility, background callback

**Files:**
- Modify: `lib/services/notification_service.dart`

**Interfaces:**
- Consumes: `CheckInCopy.actionId`.
- Produces:
  - `NotificationService.idCheckInBase` → `int` (4000); `NotificationService.checkInNotificationId(int dayOffset)` → `int`
  - `NotificationService.scheduleCheckIn({required int id, required DateTime date, required int hour, required int minute, required String title, required String body, String? actionLabel})` → `Future<void>`
  - `NotificationService.init({DidReceiveBackgroundNotificationResponseCallback? onBackgroundAction})` → `Future<void>`

**Note (no test):** this task is plugin-bound; there is no assertable behaviour under `flutter test`. Its copy is already guarded by Task 2's guardrail test, and its real verification is Task 6 (device).

- [ ] **Step 1: Add the ids and the scheduler**

In `lib/services/notification_service.dart`, add imports:

```dart
import 'check_in_notifications.dart';
```

Add after `idCustomBase`:

```dart
  /// Check-in one-shots, offset by day index (4000..4013). The horizon owns the
  /// whole daily-nudge slot, so these never coexist with [idLogNudge].
  static const int idCheckInBase = 4000;
  static int checkInNotificationId(int dayOffset) => idCheckInBase + dayOffset;
```

- [ ] **Step 2: Add `scheduleCheckIn`**

Add after `scheduleOneShot`:

```dart
  /// A one-shot check-in notification on [date] at [hour]:[minute], carrying an
  /// optional one-tap [actionLabel].
  ///
  /// [visibility] is SECRET: one-tap logging otherwise puts cycle state on the
  /// lock screen, which for this app is a safety problem, not a UX detail. The
  /// notification still sits in the shade after unlock, so the real win (1 tap
  /// vs. ~6) survives; only "answer without unlocking" is given up.
  ///
  /// This works despite `minSdk 26`: the plugin sets visibility on the
  /// NOTIFICATION, never the channel, and NotificationChannel defaults to
  /// VISIBILITY_NO_OVERRIDE — which defers to the notification. (SECRET only
  /// hides on a SECURE lock screen; a swipe-only device has nothing to protect.)
  ///
  /// The payload carries the TARGET DATE as ISO-8601. The handler must not use
  /// `DateTime.now()`: a notification that fires at 20:00 and is tapped at 00:30
  /// would otherwise write the wrong day.
  ///
  /// iOS gets the notification without buttons (Darwin actions need registered
  /// categories; iOS is deferred). Body-tap opens the app there.
  static Future<void> scheduleCheckIn({
    required int id,
    required DateTime date,
    required int hour,
    required int minute,
    required String title,
    required String body,
    String? actionLabel,
  }) async {
    await cancel(id);
    final when =
        tz.TZDateTime(tz.local, date.year, date.month, date.day, hour, minute);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;

    final android = AndroidNotificationDetails(
      'cycle_reminders',
      'Cycle reminders',
      channelDescription: 'Period, fertile-window and daily-log reminders',
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.secret,
      actions: actionLabel == null
          ? null
          : <AndroidNotificationAction>[
              AndroidNotificationAction(
                CheckInCopy.actionId,
                actionLabel,
                // Write in the background; do not launch the UI.
                showsUserInterface: false,
                // Deliberately FALSE (the default is true). If the notification
                // self-dismissed on tap and the background write then failed
                // (DB locked, keystore hiccup), the user's tap would be
                // silently lost with no affordance to retry. Instead the
                // notification survives the tap and the handler cancels it ONLY
                // after a successful write — so failure leaves the question
                // standing, which IS the retry affordance, and costs no new
                // copy. See onCheckInAction (Task 5).
                cancelNotification: false,
              ),
            ],
    );

    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails:
          NotificationDetails(android: android, iOS: const DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: date.toIso8601String(),
    );
  }
```

- [ ] **Step 3: Wire the background callback into `init`**

Replace the `init` signature and its `initialize` call:

```dart
  static Future<void> init({
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundAction,
  }) async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
      onDidReceiveBackgroundNotificationResponse: onBackgroundAction,
    );
    _ready = true;
  }
```

- [ ] **Step 4: Retire the repeating nudge**

Delete `scheduleDailyLogNudge` (the horizon replaces it). Keep `idLogNudge` — Task 5 cancels it once, so a nudge left over from a previous install cannot double-notify.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` — and all tests pass except any that referenced `scheduleDailyLogNudge`. If a test breaks, it is Task 5's caller that must change; leave the test failing only if Task 5 fixes it, otherwise fix the reference now.

```bash
git add lib/services/notification_service.dart
git commit -m "feat: add check-in notification actions with secret lock-screen visibility"
```

---

### Task 4: `CheckInWriter` — the shared background write path

The crux of the feature. Runs with **no UI, no providers, and no plugin registry unless we ask for one**, against an **encrypted** DB.

**Files:**
- Create: `lib/services/check_in_writer.dart`
- Modify: `lib/db/connection.dart`

**Interfaces:**
- Consumes: `DailyLogRepository.setFlowIfEmpty`, `CheckInPlanner.slotsToSchedule`, `CheckInCopy`, `NotificationService.scheduleCheckIn`, `NotificationService.checkInNotificationId`, `HomeWidgetService.push`, `buildHomeWidgetData`, `CycleCalculator.computeCycles`, `ReminderRepository.getByType`.
- Produces:
  - `PredictionService.forMode({required List<Cycle> cycles, required List<DailyLog> logs, required TrackingMode mode, required int cycleLength, required int periodLength, DateTime? asOf})` → `PredictionResult`
  - `CheckInWriter.answerNoBleeding(DateTime date)` → `Future<bool>` — **true only if a row was written**; false if the day was already answered OR the write threw. Task 5's handler cancels the notification only on `true`.
  - `CheckInWriter.scheduleHorizon({required List<DailyLog> logs, required PredictionResult prediction, required int hour, required int minute, required bool enabled})` → `Future<void>`

- [ ] **Step 1: Add `busy_timeout` to the DB connection**

In `lib/db/connection.dart`, inside `NativeDatabase(file, setup: (rawDb) { ... })`, after the `PRAGMA key` block and before `PRAGMA foreign_keys`:

```dart
        // Two isolates share this file once the notification/widget check-in
        // can write in the background, and there is no WAL sidecar (journal
        // mode is delete/truncate) — so a foreground app holding the DB plus a
        // shade tap can collide. Wait rather than throw "database is locked".
        rawDb.execute('PRAGMA busy_timeout = 5000;');
```

- [ ] **Step 2: Extract the prediction construction (prevents isolate divergence)**

`main.dart:70-87` assembles the prediction from settings inside a `ProxyProvider2`.
The background isolate has no provider tree and must assemble it too. Copy-pasting
that logic would let the two drift apart — and a background isolate predicting
differently from the app would schedule a horizon asking questions the app itself
would not ask. Extract it once.

In `lib/services/prediction_service.dart`, add:

```dart
  /// The ONE place prediction inputs are assembled from settings.
  ///
  /// `main.dart`'s ProxyProvider2 and the background [CheckInWriter] MUST agree.
  /// If the isolate predicted differently from the app, the notification horizon
  /// would ask questions the app itself would never ask.
  static PredictionResult forMode({
    required List<Cycle> cycles,
    required List<DailyLog> logs,
    required TrackingMode mode,
    required int cycleLength,
    required int periodLength,
    DateTime? asOf,
  }) =>
      predict(
        // Suppress all period/fertility predictions during pregnancy.
        mode == TrackingMode.pregnancy ? const <Cycle>[] : cycles,
        fallbackCycleLength: cycleLength,
        fallbackPeriodLength: periodLength,
        // Perimenopause: erratic cycles → cap confidence to low, which
        // self-suppresses the ovulation marker + fertility band app-wide.
        capConfidenceToLow: mode == TrackingMode.perimenopause,
        logs: mode == TrackingMode.pregnancy ? const <DailyLog>[] : logs,
        asOf: asOf,
      );
```

Then replace the body of `main.dart`'s `ProxyProvider2<LogProvider, SettingsProvider,
PredictionResult>` update callback with a call to it:

```dart
          update: (_, log, settings, _) => PredictionService.forMode(
            cycles: log.cycles,
            logs: log.logs,
            mode: settings.mode,
            cycleLength: settings.cycleLength,
            periodLength: settings.periodLength,
          ),
```

Run: `flutter test`
Expected: `All tests passed!` — this is a pure refactor; any failure means `forMode`
does not faithfully reproduce the old inline logic. Fix `forMode`, not the test.

- [ ] **Step 3: Write `CheckInWriter`**

Create `lib/services/check_in_writer.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../data/daily_log_repository.dart';
import '../data/reminder_repository.dart';
import '../db/database.dart';
import '../models/enums.dart';
import '../models/prediction.dart';
import 'check_in_notifications.dart';
import 'cycle_calculator.dart';
import 'home_widget_service.dart';
import 'notification_service.dart';
import 'prediction_service.dart';

/// The single write path behind BOTH the notification action and the widget
/// button (Phase B). Everything here runs in a BACKGROUND ISOLATE: there is no
/// UI, no provider tree, and no plugin registry until we ask for one.
///
/// Opening the DB here means opening the ENCRYPTED DB: the keystore passphrase
/// is fetched via flutter_secure_storage, which is a plugin — hence
/// [DartPluginRegistrant.ensureInitialized]. Without it the isolate cannot read
/// the key and the write fails.
///
/// The keystore is always available when this runs, by construction: check-in
/// notifications are SECRET, so they are only answerable after the phone is
/// unlocked.
class CheckInWriter {
  const CheckInWriter._();

  /// Marks [date] as a confirmed no-bleeding day (`flow = none`) — the single
  /// primitive behind both "Didn't start" and "Mark ended here".
  ///
  /// Returns false when the day already had a flow (stale notification, or
  /// answered in-app since it was scheduled). That is a success, not an error:
  /// the log IS the answer flag.
  ///
  /// Returns false ALSO if the write threw. Nothing above this frame can catch
  /// it — the caller is the OS delivering an action tap into a bare isolate, so
  /// an escaping exception is a silent, invisible failure. Instead we swallow
  /// it and report false, and the caller leaves the notification standing so the
  /// user can retry. The expected cause is a locked DB (two isolates, no WAL);
  /// `PRAGMA busy_timeout` already makes that rare.
  static Future<bool> answerNoBleeding(DateTime date) async {
    // Background isolates start with no plugins registered — without this,
    // flutter_secure_storage cannot read the keystore and the encrypted DB
    // cannot be opened at all.
    DartPluginRegistrant.ensureInitialized();

    AppDatabase? db;
    try {
      db = AppDatabase();
      final logRepo = DailyLogRepository(db);
      final wrote = await logRepo.setFlowIfEmpty(
        date: date,
        flow: FlowIntensity.none,
      );

      // Our own write is the one thing that CAN change the logs while the app
      // is closed, so the precomputed horizon is now stale — rebuild it, and
      // refresh the widget so it does not contradict what the user just told us.
      await _refreshDerivedSurfaces(db, logRepo);
      return wrote;
    } catch (_) {
      return false; // caller keeps the notification alive as the retry path
    } finally {
      await db?.close();
    }
  }

  static Future<void> _refreshDerivedSurfaces(
    AppDatabase db,
    DailyLogRepository logRepo,
  ) async {
    final logs = await logRepo.getAll();
    final settings = await db.getSettings();
    final prediction = PredictionService.forMode(
      cycles: CycleCalculator.computeCycles(logs),
      logs: logs,
      mode: settings.mode,
      cycleLength: settings.defaultCycleLength,
      periodLength: settings.defaultPeriodLength,
    );

    // NOTE: Task 7 (Phase B) adds a required `prompt:` argument here. Until
    // then this call has no prompt — do not add one now or this will not
    // compile.
    await HomeWidgetService.push(
      buildHomeWidgetData(
        prediction: prediction,
        mode: settings.mode,
        pregnancyStartDate: settings.pregnancyStartDate,
      ),
    );

    // Reminder hour/minute/enabled live in the Reminders TABLE, not AppSettings.
    final nudge = await ReminderRepository(db).getByType(ReminderType.logNudge);
    await scheduleHorizon(
      logs: logs,
      prediction: prediction,
      hour: nudge?.hour ?? 20,
      minute: nudge?.minute ?? 0,
      enabled: nudge?.enabled ?? false,
    );
  }

  /// Schedules one notification per day across the horizon: the check-in
  /// question if there is one, otherwise the generic nudge. Never two, never
  /// zero.
  ///
  /// Gated on [enabled] — the user's existing `ReminderType.logNudge` toggle,
  /// via the pure [CheckInPlanner.slotsToSchedule] (which is where that rule is
  /// tested). Scheduling check-ins for someone who turned notifications OFF
  /// would be a bug, not a feature.
  static Future<void> scheduleHorizon({
    required List<DailyLog> logs,
    required PredictionResult prediction,
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    // Clear the whole block first: the horizon shrinks as well as grows (a day
    // that had a question yesterday may have none today), and a stale one-shot
    // left behind would ask a question we have already answered.
    for (var i = 0; i < CheckInPlanner.horizonDays; i++) {
      await NotificationService.cancel(NotificationService.checkInNotificationId(i));
    }

    final slots = CheckInPlanner.slotsToSchedule(
      logs: logs,
      prediction: prediction,
      today: DateTime.now(),
      enabled: enabled,
    );
    for (final slot in slots) {
      await NotificationService.scheduleCheckIn(
        id: NotificationService.checkInNotificationId(slot.dayOffset),
        date: slot.date,
        hour: hour,
        minute: minute,
        title: CheckInCopy.title(slot.prompt),
        body: CheckInCopy.body(slot.prompt),
        actionLabel: CheckInCopy.actionLabel(slot.prompt),
      );
    }
  }
}
```

> **Verified schema facts** (from `lib/db/tables.dart`, do not re-derive):
> `AppSettings.mode` is `intEnum<TrackingMode>()` — already a `TrackingMode`,
> NOT a String, so no `.byName()` conversion. Length settings are
> `defaultCycleLength` / `defaultPeriodLength`. There is **no**
> `capConfidenceToLow` column — it is derived from
> `mode == TrackingMode.perimenopause`, which is exactly what
> `PredictionService.forMode` encapsulates. Reminder `hour`/`minute`/`enabled`
> live in the **`Reminders` table** keyed by `type` (`intEnum<ReminderType>`),
> reachable via `ReminderRepository.getByType(ReminderType.logNudge)` →
> `Future<Reminder?>`.

- [ ] **Step 4: Verify it compiles and the suite is green**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/check_in_writer.dart lib/db/connection.dart \
        lib/services/prediction_service.dart lib/main.dart
git commit -m "feat: add shared background check-in writer with busy_timeout"
```

---

### Task 5: Entry point, provider wiring, and call sites

`reschedule` is currently called from **only** `reminders_screen.dart` — i.e. only when the user edits reminders. A horizon wired only there would go stale for weeks. This task gives it the call sites it needs.

**Files:**
- Create: `lib/services/notification_actions.dart`
- Modify: `lib/providers/reminder_provider.dart`, `lib/screens/reminders/reminders_screen.dart`, `lib/screens/app_gate.dart`, `lib/main.dart`

**Interfaces:**
- Consumes: `CheckInWriter.answerNoBleeding`, `CheckInWriter.scheduleHorizon`, `CheckInCopy.actionId`, `NotificationService.cancel`.
- Produces: top-level `onCheckInAction(NotificationResponse response)`; `ReminderProvider.reschedule(PredictionResult prediction, List<DailyLog> logs)`.

**Note (no new test):** the one rule here that must never regress — "disabled
toggle ⇒ schedule nothing" — is already covered by Task 2's pure
`slotsToSchedule` guardrail test. The rest of this task is plugin/lifecycle
wiring with nothing assertable under `flutter test`; it is verified in Task 6.

- [ ] **Step 1: Write the background entry point**

Create `lib/services/notification_actions.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'check_in_notifications.dart';
import 'check_in_writer.dart';
import 'notification_service.dart';

/// Top-level background handler for notification action taps.
///
/// MUST be top-level (not a closure or a static method) and MUST carry
/// `@pragma('vm:entry-point')`, or tree-shaking will drop it in release builds
/// and the action will silently do nothing.
@pragma('vm:entry-point')
Future<void> onCheckInAction(NotificationResponse response) async {
  if (response.actionId != CheckInCopy.actionId) return;

  // The payload carries the TARGET day. Never use DateTime.now() here: a
  // notification that fires at 20:00 and is tapped at 00:30 would write the
  // wrong day.
  final payload = response.payload;
  if (payload == null) return;
  final date = DateTime.tryParse(payload);
  if (date == null) return;

  final wrote = await CheckInWriter.answerNoBleeding(date);

  // Dismiss ONLY on success. The action sets cancelNotification: false, so a
  // failed write leaves the question standing — the user can tap again. This is
  // the whole "never silently drop the tap" path, and it costs no new copy.
  if (wrote && response.id != null) {
    await NotificationService.cancel(response.id!);
  }
}
```

> `answerNoBleeding` returns false for an ALREADY-ANSWERED day too, which would
> leave that notification visible. That is acceptable and rare (it means a stale
> notification whose day was answered in-app), and the next `scheduleHorizon`
> clears the whole id block anyway. Do not "fix" it by cancelling
> unconditionally — that reintroduces the silent-failure hole.

- [ ] **Step 2: Wire it into `init` and add the missing call sites**

In `lib/main.dart`, where `NotificationService.init()` is called, pass the handler:

```dart
  await NotificationService.init(onBackgroundAction: onCheckInAction);
  // One-time migration: the horizon replaces the old repeating nudge. Cancel it
  // so a nudge scheduled by a previous install cannot double-notify.
  await NotificationService.cancel(NotificationService.idLogNudge);
```

In `lib/providers/reminder_provider.dart`, change the signature and replace the log-nudge block:

```dart
  Future<void> reschedule(
    PredictionResult prediction,
    List<DailyLog> logs,
  ) async {
    // Daily nudge + check-in horizon: ONE notification per day, whichever is
    // most relevant. Gated on the user's existing logNudge toggle.
    await CheckInWriter.scheduleHorizon(
      logs: logs,
      prediction: prediction,
      hour: hourOf(ReminderType.logNudge),
      minute: minuteOf(ReminderType.logNudge),
      enabled: isEnabled(ReminderType.logNudge),
    );

    // ... periodSoon / fertileWindow blocks unchanged ...
```

Update both call sites in `lib/screens/reminders/reminders_screen.dart` to pass logs:

```dart
    await provider.reschedule(prediction, context.read<LogProvider>().logs);
```

In `lib/screens/app_gate.dart`, add a `resumed` branch to the existing
`didChangeAppLifecycleState` (the observer is already registered):

```dart
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      // A background isolate may have written via a SECOND connection while we
      // were away — this provider cannot have observed it. Reload, then rebuild
      // the horizon from the fresh logs.
      final logs = context.read<LogProvider>();
      final reminders = context.read<ReminderProvider>();
      final prediction = context.read<PredictionResult>();
      logs.load().then((_) => reminders.reschedule(prediction, logs.logs));
    }
```

> Check the actual accessor for the logs list on `LogProvider` (`logs`?) and
> confirm `PredictionResult` is provided in the tree at this point — `main.dart`
> exposes it via `ProxyProvider2`. Adapt names to reality; do not invent.

- [ ] **Step 3: Verify**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 4: Commit**

```bash
git add lib/services/notification_actions.dart lib/providers/reminder_provider.dart \
        lib/screens/reminders/reminders_screen.dart lib/screens/app_gate.dart \
        lib/main.dart
git commit -m "feat: wire check-in horizon scheduling and background action handler"
```

---

### Task 6: Device verification — Phase A (MANDATORY)

**A green suite proves nothing here.** In-memory test DBs never exercise the cipher, and there is no background isolate under `flutter test` — the same structural reason encryption itself had to be verified on-device on 2026-07-16.

**Files:** none (verification only).

- [ ] **Step 1: Build and install**

```bash
flutter build apk --debug
adb -s cdc8bb52 install -r build/app/outputs/flutter-apk/app-debug.apk
```
Expected: `Success`

- [ ] **Step 2: Force a check-in notification**

Set the daily-log reminder to ~2 minutes ahead (Settings → Reminders), ensure a state where `evaluate()` returns `didItStart` (a logged period ≥ 1 cycle ago and none today), then background the app.

- [ ] **Step 3: Verify SECRET visibility**

Lock the device with a **secure** lock (PIN/pattern — SECRET is a no-op on swipe-only). Wait for the notification.
Expected: **nothing on the lock screen.** Unlock → the notification IS in the shade, with body `Your period was expected around now.` and one button `Didn't start`.

- [ ] **Step 4: Verify the background write with the app KILLED**

```bash
adb -s cdc8bb52 shell am force-stop com.lunatrack.app
```
Tap `Didn't start` in the shade. Then:

```bash
adb -s cdc8bb52 logcat -d | grep -iE "not a database|SqliteException|FATAL|secure_storage.*(error|fail)"
```
Expected: no output, and the notification **disappears** — which is itself a
signal: the action sets `cancelNotification: false`, so the notification is
dismissed only by the handler after a SUCCESSFUL write. A notification that
lingers after the tap means the background write failed.

- [ ] **Step 5: Verify the day was actually written**

Launch the app; open today in the calendar.
Expected: today shows a confirmed no-bleeding day; the Home check-in card is gone; the widget (if added) has refreshed.

This is the single most important step in the plan: it proves a background isolate registered plugins, read the keystore, decrypted the DB, and committed one column.

- [ ] **Step 6: Verify idempotency and preservation on-device**

Log symptoms (no flow) on a future-dated check-in day, then answer its notification.
Expected: flow becomes "none" AND the symptoms survive — Task 1's guarantee, proven through the real cipher.

- [ ] **Step 7: Record the evidence**

Update `hand.md` (§ YOU ARE HERE) and `CLAUDE.md` (Feature status) with what was verified, the device, and the date — matching the encryption entry's format.

```bash
git add hand.md CLAUDE.md
git commit -m "docs: record device verification of one-tap check-in (Phase A)"
```

---

### Task 7: Phase B — widget prompt data

**Files:**
- Modify: `lib/services/home_widget_service.dart`
- Test: `test/home_widget_test.dart` (extend)

**Interfaces:**
- Consumes: `CheckInPrompt`.
- Produces: `HomeWidgetData.prompt` (`CheckInPrompt`); `buildHomeWidgetData({..., required CheckInPrompt prompt})`.

> **PRIVACY NOTE — read before starting.** `home_widget` stores widget data in
> **SharedPreferences** (see `LunaWidgetProvider.onUpdate`'s `widgetData
> .getString(...)`), which is app-private but **not encrypted**. The widget
> ALREADY puts cycle-derived strings there (`'Late'` / `'Period may be late'`).
> Adding `prompt` extends that. This is judged acceptable ONLY because the
> widget's entire purpose is to render this on the home screen — the prefs copy
> is strictly less exposed than the pixels. It is NOT a licence to park other
> health data outside the encrypted DB. See the Risks section of the spec.

- [ ] **Step 1: Write the failing test**

Append to `test/home_widget_test.dart`:

```dart
  test('carries the check-in prompt so the widget knows which question to show',
      () {
    final data = buildHomeWidgetData(
      prediction: somePrediction, // reuse this file's existing fixture
      mode: TrackingMode.track,
      prompt: CheckInPrompt.didItStart,
      now: DateTime(2026, 7, 16),
    );
    expect(data.prompt, CheckInPrompt.didItStart);
  });

  test('pregnancy suppresses the check-in prompt — period questions are wrong '
      'there', () {
    final data = buildHomeWidgetData(
      prediction: somePrediction,
      mode: TrackingMode.pregnancy,
      pregnancyStartDate: DateTime(2026, 3, 1),
      prompt: CheckInPrompt.didItStart,
      now: DateTime(2026, 7, 16),
    );
    expect(data.prompt, CheckInPrompt.none);
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/home_widget_test.dart`
Expected: FAIL — no named parameter `prompt`.

- [ ] **Step 3: Implement**

Add `prompt` to `HomeWidgetData` (include it in `==`/`hashCode` so redundant pushes are still skipped), add `required CheckInPrompt prompt` to `buildHomeWidgetData`, and force `CheckInPrompt.none` in the pregnancy branch (period prompts are wrong there — mirroring why that branch already suppresses period predictions). Push it in `HomeWidgetService.push`:

```dart
      await HomeWidget.saveWidgetData<String>('prompt', data.prompt.name);
```

Update the `buildHomeWidgetData` call in `CheckInWriter._refreshDerivedSurfaces` and anywhere else it is constructed (`main.dart` `ProxyProvider`), passing the prompt from `CycleCheckInService.evaluate`.

- [ ] **Step 4: Verify**

Run: `flutter test && flutter analyze`
Expected: `All tests passed!` and `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/services/home_widget_service.dart test/home_widget_test.dart lib/main.dart lib/services/check_in_writer.dart
git commit -m "feat: push check-in prompt to the home-screen widget"
```

---

### Task 8: Phase B — widget buttons

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/menstrul_track/LunaWidgetProvider.kt`, `android/app/src/main/res/layout/luna_widget.xml`, `lib/main.dart`
- Create: (nothing)

**Interfaces:**
- Consumes: `CheckInWriter.answerNoBleeding`.
- Produces: an interactivity callback registered via `HomeWidget.registerInteractivityCallback`.

- [ ] **Step 1: Add the button to the layout**

In `android/app/src/main/res/layout/luna_widget.xml`, add below the caption:

```xml
    <Button
        android:id="@+id/widget_action"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:visibility="gone"
        android:text="" />
```

- [ ] **Step 2: Wire per-button intents in the provider**

In `LunaWidgetProvider.kt`, add the import and replace the `apply` block's tail:

```kotlin
import android.net.Uri
import android.view.View
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
```

```kotlin
                val prompt = widgetData.getString("prompt", "none") ?: "none"
                val label = when (prompt) {
                    "didItStart" -> "Didn't start"
                    "hasItEnded" -> "Mark ended here"
                    else -> null
                }
                if (label == null) {
                    setViewVisibility(R.id.widget_action, View.GONE)
                } else {
                    setViewVisibility(R.id.widget_action, View.VISIBLE)
                    setTextViewText(R.id.widget_action, label)
                    setOnClickPendingIntent(
                        R.id.widget_action,
                        HomeWidgetBackgroundIntent.getBroadcast(
                            context,
                            Uri.parse("lunatrack://checkin"),
                        ),
                    )
                }
                // Whole-widget tap still opens the app.
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
```

> The labels are duplicated in Kotlin because RemoteViews cannot call Dart.
> Keep them byte-identical to `CheckInCopy.actionLabel`. If they ever diverge,
> the widget lies about what the button does.

- [ ] **Step 3: Register the Dart callback**

In `lib/services/notification_actions.dart`, add:

```dart
/// Background handler for widget button taps. Same rules as [onCheckInAction]:
/// top-level + vm:entry-point, or release builds tree-shake it away.
@pragma('vm:entry-point')
Future<void> onWidgetCheckInAction(Uri? uri) async {
  if (uri?.host != 'checkin') return;
  // The widget renders only TODAY's question, so today is the target day.
  await CheckInWriter.answerNoBleeding(DateTime.now());
}
```

In `lib/main.dart`, after `NotificationService.init(...)`:

```dart
  await HomeWidget.registerInteractivityCallback(onWidgetCheckInAction);
```

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/kotlin/com/example/menstrul_track/LunaWidgetProvider.kt \
        android/app/src/main/res/layout/luna_widget.xml \
        lib/services/notification_actions.dart lib/main.dart
git commit -m "feat: add one-tap check-in button to the home-screen widget"
```

---

### Task 9: Device verification — Phase B (MANDATORY)

**Files:** none (verification only).

- [ ] **Step 1: Build, install, add the widget**

```bash
flutter build apk --debug
adb -s cdc8bb52 install -r build/app/outputs/flutter-apk/app-debug.apk
```
Add the LunaTrack widget to the home screen.

- [ ] **Step 2: Verify the button appears only when there is a question**

Expected: with no check-in due, **no button** (`View.GONE`). With `didItStart` due, the button reads `Didn't start` — byte-identical to the notification's.

- [ ] **Step 3: Verify the write with the app killed**

```bash
adb -s cdc8bb52 shell am force-stop com.lunatrack.app
```
Tap the widget button. Then:

```bash
adb -s cdc8bb52 logcat -d | grep -iE "not a database|SqliteException|FATAL"
```
Expected: no output; the widget re-renders without the button (the question is answered); opening the app shows today as a confirmed no-bleeding day.

- [ ] **Step 4: Record the evidence**

Update `hand.md` and `CLAUDE.md` as in Task 6 Step 7.

```bash
git add hand.md CLAUDE.md
git commit -m "docs: record device verification of one-tap check-in (Phase B)"
```

---

## Known hazards for the implementer

- **The background callback is typed `void Function(NotificationResponse)`.**
  Dart lets an `async` function satisfy it (any return type is assignable to
  `void`), but nothing awaits it — so the isolate can in principle be torn down
  before `answerNoBleeding` finishes. This is the single most likely way this
  feature "works on my machine" and silently fails in the wild. Task 6 Step 4 is
  the check that matters: force-stop the app first, so the isolate is created
  cold and has the least help. If writes land when the app is warm but not when
  it is killed, this is why.
- **`@pragma('vm:entry-point')` is load-bearing in release only.** A debug build
  will happily run a handler that release-mode tree-shaking deletes. If Phase A
  passes in debug, re-check once with `flutter build apk --release` before
  believing it.
- **Kotlin label duplication** (Task 8): RemoteViews cannot call Dart, so
  `"Didn't start"` exists in both `CheckInCopy` and `LunaWidgetProvider.kt`. If
  they diverge, the widget button lies about what it does.

## Out of scope — noted, not done

- **`periodSoon` / `fertileWindow` notifications are still lock-screen visible.**
  "Your period may start tomorrow." on a lock screen is the same leak this plan
  fixes for check-ins. Making them SECRET too is a one-line change per detail
  block, but it alters existing notification behaviour, which the spec did not
  approve. Raise it with the owner.
- **iOS notification actions** need `DarwinNotificationCategory` registration at
  init. iOS is deferred; iOS gets buttonless notifications.
- **Widget prefs are unencrypted** (Task 7 note). Consider tightening the
  `PRIVACY_POLICY.md` sentence "Your data is **encrypted at rest**" to scope
  explicitly to the database, since the widget's derived strings are not.
