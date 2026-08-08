# Product-Change Timer (LunaTrack v1)

## Context

LunaTrack has no way to answer the one question a user asks mid-period: *"how long has this been in?"* Every existing surface is keyed to a **day** — `DailyLogs.date` is UNIQUE at local midnight — so nothing in the app tracks an intra-day event.

This adds a **change timer**: tap a product chip when you insert/apply one, see a live elapsed count on Home, get a best-effort notification when you reach the duration you set, tap "Changed it" to restart.

The feature is unusual for this codebase in one respect: it is **adjacent to a real medical emergency** (toxic shock syndrome). That shapes every decision below. The governing principle from the Council's Safety seat:

> **The in-app card is the primary surface. The notification is an accessory that may never arrive.** The app never promises delivery, never counts down, and never authors a duration as its own medical advice.

**Council rulings** (Product / Safety / Feasibility, all three seats):
- **Free.** Never Premium — consistent with `CLAUDE.md`'s "all tracking is FREE".
- **Inexact alarms stay.** `USE_EXACT_ALARM` is Play-restricted to alarm/calendar apps; a foreground service means a permanent status-bar icon (continuous self-disclosure, the exact threat `visibility: secret` prevents). Neither buys reliability — an OEM force-stop drops alarms regardless of exactness.
- **Ephemeral, no history.** One in-progress session, no timestamped log. This deletes an entire class of obligations: no retention policy, no PDF exclusion, no sync-exclusion guards, no v6 migration.
- **VETOED — storing anything in the day-tags blob.** `sync_mapper.dart:33` sends `DailyLogs.symptoms` to Firestore as a real map, and `firestore.rules` is not deployed. Timestamps of intimate physical acts must not go near it.
- **VETOED — countdowns, "safe", "overdue", a TSS symptom checker, gamification, and the home-screen widget** (which renders outside `AppLock`).

---

## Architecture

### State: one `Reminders` row. Zero migration.

`schemaVersion` stays at **5**. The active session is a single row:

| Column | Value |
|---|---|
| `type` | `ReminderType.productChange` — **appended at index 5** (`lib/models/enums.dart:27-34`; the file header states values persist by integer index, append-only) |
| `hour` / `minute` | `0` / `0` — sentinel. These columns are NOT NULL and documented as "0–23, local time"; a session has no time-of-day. Document this on the enum value rather than working around it. |
| `enabled` | `true` while a session runs |
| `payload` | `{"insertedAt": <epochMillis>, "product": "tampon", "intervalMinutes": 240}` |

**Why this is safe** (verified, not assumed):
- Nothing in `lib/` iterates `ReminderType.values`. `reminders_screen.dart:77-128` hardcodes the three smart types.
- `ReminderProvider.load()` (`reminder_provider.dart:43-51`) buckets any non-`custom` type into `_byType` — a singleton session row fits exactly.
- `ReminderProvider.reschedule()` (`:112-158`) touches only `logNudge`/`periodSoon`/`fertileWindow`. **A new type is inert.**
- `ReminderProvider.setReminder()` (`:101-103`) preserves `payload` for non-`periodSoon` types.
- `daysBefore()` (`:29-37`) reads `payload` for any type but is fully defensive — `try/catch`, returns 2.
- `AppDatabase.deleteAllData()` (`database.dart:98`) already deletes `reminders`.
- `Reminders` is deliberately **not synced** (no reference in `sync_mapper.dart` / `sync_service.dart`) — exactly the privacy property Safety demanded.

**One real break:** `backup_service.dart:103` exports *every* reminder row and `:135-153` restores them. A backup taken mid-session, restored three days later, resurrects a "71 hours" timer. **Filter `productChange` rows out of the export list.**

### Products and durations

Defaults are the Council's conservative set. **Durations are user-editable, but capped — the app will never help you exceed the packaging.** The cap is a **refusal**, not a silent clamp (mirrors the weight-input precedent where `DayEntryFormState.save()` returns `Future<bool>`).

| Chip | Default | Hard cap | Cap copy |
|---|---|---|---|
| Pad | 4h | 12h (sanity only) | — |
| Tampon | 4h | **8h** | "Tampon packaging generally says not to leave one in longer than 8 hours." |
| Cup / disc | 8h | **12h** | "Cup manufacturers generally say to empty it at least every 12 hours." |
| Period underwear | 8h | 12h (sanity only) | "Absorbency varies by brand — check yours." |

`ProductType` is persisted **by name** in JSON, not `intEnum` — ordering is free.

**Duration is a pure function of `(productType, userSetting)`.** Never `f(flow)`, `f(cycleDay)`, or `f(phase)` — inference from cycle data would turn the timer into a synthesized clinical recommendation.

**No quiet-hours deferral in v1.** Product proposed holding 23:00–07:00 reminders until 07:00, but that pushes a 04:00 tampon reminder to 9h — past the 8h cap the whole design exists to respect. Users who want to sleep through choose a longer duration (pad allows 12h). Deferred to v2 as configurable quiet hours.

### Notifications

**New channel** `product_change` — *not* a reuse of `cycle_reminders` (the user must be able to silence one without the other) and *not* `medication_reminders`. Channel name and description render in Android Settings → Notifications on a possibly-supervised phone, so both are neutral:

```
channelId:          'product_change'
channelName:        'Timed reminders'
channelDescription: 'Reminders you set yourself'
visibility:         NotificationVisibility.secret   // mandatory, two reasons
```

`secret` is mandatory for a reason beyond privacy: it means the action cannot be tapped before unlock, which **guarantees the Android Keystore is available** when the background isolate opens the encrypted DB. The rationale comment at `notification_service.dart:94-101` is load-bearing — inherit it.

- **Title:** fixed `'LunaTrack'`. No product word, no menstrual word.
- **Body (default):** time only — `"It's been 4h 20m since 09:14."`
- **Product word is opt-in, default OFF** (shaped like the existing gender-neutral-language preference). `secret` is honored by AOSP but not guaranteed across Wear OS bridging, Phone Link mirroring, or Notification History — the default body must be harmless if it leaks.

**Two slots, ids 5000 and 5001** (5000+ is free; 1001–1003, 2000+, 3000+, 4000–4013 are taken):

| id | Fires at | Why |
|---|---|---|
| 5000 | `insertedAt + interval` | The reminder |
| 5001 | `insertedAt + interval + 30m` | Delivery redundancy, **not** a nag |

**Hard constraint:** `inexactAllowWhileIdle` resolves to `setAndAllowWhileIdle`, which Android rate-limits to roughly once per 9–15 minutes per app. Slots closer than ~15 min are silently swallowed. 30 min is the safe spacing. Never add a third slot.

`NotificationService` needs one new method — `scheduleOneShot` (`:277-298`) takes `date + hour + minute` and cannot express "now + 4h":

```dart
static Future<void> scheduleAt({required int id, required DateTime when, ...})
```

Use `tz.TZDateTime.from(when, tz.local)` — **not** the `tz.TZDateTime(tz.local, y, m, d, h, min)` constructor used at `:288`, which drops seconds and rounds to a minute boundary.

### The ticker — the app's first

There is no `Timer.periodic`, `Ticker`, or `AnimationController` anywhere in `lib/` today. Design:

- **A private leaf `StatefulWidget`** (`_ElapsedText`) that returns only the `Text`. `setState` dirties that Element alone; the Home `ListView` (`home_screen.dart:332-375`) and every sibling card are untouched.
- **60-second interval, boundary-aligned**, via a self-rescheduling one-shot: `next = Duration(seconds: 60 - (elapsed.inSeconds % 60))`. Naive `Timer.periodic(60s)` fires 60s after *mount*, leaving the display stale by up to 59s.
- **Not 1 second.** `app_lock.dart:242` wraps the app in `TickerMode(enabled: false)` when locked — which mutes `Ticker`s but **not** `Timer`s. A 1s timer keeps calling `setState` behind the lock, and `RenderOffstage.performLayout` still lays out its child. 60s is one wasted layout per minute; 1s is 60.
- **Never accumulate.** `build()` computes `DateTime.now().difference(insertedAt)` from scratch. The `Timer` is only a rebuild trigger. This makes lock/Doze/backgrounding correct by construction.
- Discipline: `dispose()` cancels; `didUpdateWidget` re-aligns when `insertedAt` changes; `if (!mounted) return;` before every `setState`.
- A `WidgetsBindingObserver` on `resumed` triggers a rebuild (4 precedents exist; `home_widget_sync.dart:53-60` is canonical).

### Home placement — and the trap that would cost you a day

The card goes in **`_PredictionBody`** (`home_screen.dart:303+`), gated:

```dart
if (session != null) ...[ _ProductTimerCard(session: session), const SizedBox(height: 12) ],
```

Placed alongside the existing `if (checkIn != CheckInPrompt.none)` idiom at `:339-342`. Running/past-target sits above `_CycleRingCard`; the idle chip card sits below `_CheckInCard` and renders only when today's flow is a bleeding value.

**The gate is not cosmetic — it is the single line that stops the ticker from hanging the test suite.** 50 test files call `pumpAndSettle`, which pumps until no frame is scheduled; a live `Timer` calling `setState` schedules frames forever, so it never settles and times out after 10 minutes *per call*. No existing fixture has an active session, so the gate keeps them all green.

Placing it in `_PredictionBody` rather than `HomeScreen.build` also keeps it below the pregnancy early-return at `:33-35`, so `pregnancy_flow_test.dart` does not break (8 files instead of 9).

**Edge case to handle in Task 7:** switching into pregnancy mode with a live session. Extend the existing cancel block at `pregnancy_screen.dart:29-30` (which already cancels `idPeriodSoon`/`idFertile`) to end the session and cancel 5000/5001, with a line in the confirm sheet noting it. Do not let it orphan silently.

### New provider

A dedicated **`ProductSessionProvider`** over `ReminderRepository`, not an extension of `ReminderProvider` — that class is about scheduled clock reminders and should not acquire a second, different responsibility. Same 8-file test cost either way.

`ReminderRepository.getByType` uses `getSingleOrNull()` (`reminder_repository.dart:14-16`), which **throws** on 2+ rows. The repository must upsert, never insert. Test it — the failure mode is an exception, not a wrong value.

---

## Copy rules (add to `CLAUDE.md` → Guardrails)

- **Never "safe", "safely", "risk-free", "you're fine", "still good", "no rush", "okay for another".** Same rule and reason as the fertility surfaces.
- **Never a countdown.** Elapsed counts **up** from the logged time. The app never shows time *remaining* — that manufactures a danger moment the app cannot locate and is false precision on a value it does not know (absorbency, flow, individual risk). Banned: `remaining`, `left`, `until`, `time's up`. **This also rules out a progress bar**, which is a countdown drawn as pixels.
- **Never "overdue", "late", "danger", "urgent", "warning", "emergency".** "Overdue" implies LunaTrack set a deadline. The only permitted framing is *"past the 4h **you set**."*
- **"TSS" / "toxic shock syndrome" appears exactly once**, in a static user-initiated "About change reminders" sheet, in neutral one-sentence framing pointing at the product's instructions and a clinician. Never in a notification or a card the user did not tap into.
- **No symptom checker, ever.** No fever/rash/vomiting list, no triage, no emergency affordance — that is a diagnostic instrument, the same class already vetoed for LH-strip auto-interpretation (Apple 1.4.1).
- **LunaTrack never authors a duration.** Durations are *attributed* ("tampon packaging generally says…"), never asserted ("we recommend…", "the safe maximum is…").
- **The reminder must be described as best-effort wherever it is configured.** Copy-must-say, not copy-may-say.
- **No red card, no warning triangle, no "!", no DND bypass, no full-screen intent.** Past-target renders the elapsed number alone in `colorScheme.error` on the normal card colour.
- **No gamification** — no streaks, scores, adherence %, or lateness tallies. A compliance score on intimate hygiene, aimed partly at teenagers, is a shame mechanic.

**Required strings:**

| Surface | Copy |
|---|---|
| Idle card | "Reminders may arrive late, or not at all — phone battery settings can block them." |
| Running | "Logged at 09:14 · **4h 20m ago**" |
| Past target | "Logged at 09:14 · **8h 41m ago** — past the 8h you set." |
| Past target by >30 min | + "This reminder may not have arrived on time." |
| Every duration picker | "Follow the instructions that came with your product." |

The >30-minute delay disclosure is the **structural defeat of inference-from-silence** — the harm where the *absence* of a notification is read as "not time yet." It needs no bad words to occur, and no copy elsewhere fixes it. Do not drop it.

---

## Tasks (TDD-ordered)

Sizes: **S ≈ 2h · M ≈ 4–6h**.

| # | Task | Size | RED test |
|---|---|---|---|
| 1 | `ProductType` enum + wear-limit metadata (name-persisted, cap table) | S | `product_timer_plan_test.dart` › *"a ProductType knows whether it carries a wear-time cap"* |
| 2 | **Pure planner** `ProductTimerPlan.plan/planIfEnabled` — mirrors `CheckInHorizon` (`check_in_notifications.dart:93-125`). Highest value per line in the feature. | M | *"plans a reminder at insertedAt + interval and a follow-up 30 minutes later"* |
| 3 | Payload codec (encode/decode session identity) — mirrors `decodeCheckInPayload` (`:27-37`): returns `null` on malformed input, **never throws** | S | `product_timer_payload_test.dart` › *"round-trips insertedAt; returns null for a malformed payload instead of throwing"* |
| 4 | `NotificationService.scheduleAt(DateTime)` + `product_change` channel + `cancelProductTimer()` | S | **No honest RED exists** — `NotificationService` is untestable by design via the `_ready` guard (`:117-125`). Assert the plan in #2 and mark this untested glue, as the rest of the file already is. Say so rather than faking a test. |
| 5 | `ProductSessionRepository` + `ProductSessionProvider` over the `Reminders` row | M | `product_session_repository_test.dart` › *"starting a session twice replaces the row rather than creating a second"* |
| 6 | `_ProductTimerCard` + `_ElapsedText` leaf ticker | M | `product_timer_card_test.dart` › *"elapsed text advances one minute after `pump(Duration(minutes: 1))`"* — **use `pump`, never `pumpAndSettle`, anywhere in this file** |
| 7 | Home gating in `_PredictionBody`; update 8 provider lists; pregnancy-mode session cancel | S | `product_timer_home_test.dart` › *"Home with no active session settles and shows no timer card"* ← **the suite-hang guard** |
| 8 | Start/stop UI — chips + duration editor with the cap refusal (`DayEntrySheet` precedent) | M | `product_timer_cap_test.dart` › *"a tampon duration above 8h is refused and the reason is attributed, not authored"* |
| 9 | Backup hygiene — filter `productChange` from export (`backup_service.dart:103`) | S | `backup_test.dart` › *"an exported in-progress session does not restore as a running timer"* |
| 10 | Notification action: Android action + **second `DarwinNotificationCategory` at `init`** (`:52-61`) + dispatch branch in `notification_actions.dart:28` + `ProductChangeWriter` (mirrors `check_in_writer.dart:30-43`, incl. the never-throw / return-bool contract) | M | `product_timer_payload_test.dart` › *"a payload from a stale session is rejected"* |
| 11 | Copy guardrail tests + `CLAUDE.md` guardrail section | S | `product_timer_copy_test.dart` (below) |
| 12 | **Fix pre-existing `_medDetails` leak** (`notification_service.dart:106-115`) — add `visibility: secret`, remove "birth control" from the OS-visible channel description | S | assert the channel description contains no `'birth control'` |
| 13 | **Device verification pass** — a checklist, not a test. Schedule it or it won't happen. | — | — |

Task 10 is deliberately last so it can be dropped without reworking anything if it destabilises.

### Guardrail tests (Task 11)

House style, `expect(find.textContaining(...), findsNothing)`:

- `product_timer_copy_test.dart` — banned: `safe`/`Safe`, `TSS`, `toxic`, `overdue`, `danger`, `urgent`, `risk`. Positive: `4h 20m` renders, the start time renders, the best-effort caveat renders.
- `product_timer_no_countdown_test.dart` — pure formatter emits no `remaining`/`left`/`until`; elapsed strictly increases.
- `product_timer_sync_exclusion_test.dart` — source scan asserting `sync_mapper.dart` and `sync_service.dart` never name the session; `dailyLogToMap` output contains no product key.
- `product_timer_notification_test.dart` — pure factory returns `visibility == secret`, `channelId == 'product_change'`, title `== 'LunaTrack'`; default body and channel metadata contain none of `tampon/cup/pad/disc/period/menstrual/underwear`. *(Requires the `NotificationDetails` be built by a pure factory function so it is assertable without the plugin.)*
- `product_timer_no_flow_inference_test.dart` — `defaultDurationFor(type)` takes no `logs`/`prediction`/`phase` parameter and is identical across heavy- and light-flow log sets.
- `product_timer_notification_id_test.dart` — 5000/5001 do not intersect `idPeriodSoon`, `idFertile`, `idMedicationBase+`, `idCustomBase+`, or `CheckInHorizon.idCheckInBase..+13`; and `rescheduleHorizon` does not cancel a live session.
- `product_timer_manifest_test.dart` — `AndroidManifest.xml` contains none of `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM`, `FOREGROUND_SERVICE`, `USE_FULL_SCREEN_INTENT`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, and no `<service` element.
- `product_timer_ad_placement_test.dart` — extend `ad_placement_test.dart`; no `AdBanner` on the timer surface.
- `product_timer_home_widget_exclusion_test.dart` — `buildHomeWidgetData(...)` contains no session field with a timer running (the widget renders outside `AppLock`).

### Existing tests that need edits

**8 files, one line each** — add `ProductSessionProvider` to the hand-declared provider list:

`ad_placement_test.dart` · `home_checkin_prompt_test.dart` · `home_cycle_ring_test.dart` · `home_insight_highlight_test.dart` · `home_pms_card_test.dart` · `ovulation_confirmed_home_test.dart` · `perimenopause_test.dart` · `symptothermal_home_test.dart`

`pregnancy_flow_test.dart` does **not** break — it hits the `isPregnant` early return at `home_screen.dart:33-35`.

---

## Files touched

**New:** `lib/models/product_type.dart` · `lib/services/product_timer_plan.dart` · `lib/services/product_timer_payload.dart` · `lib/services/product_change_writer.dart` · `lib/data/product_session_repository.dart` · `lib/providers/product_session_provider.dart` · `lib/widgets/product_timer_card.dart`

**Modified:** `lib/models/enums.dart` (append `productChange`) · `lib/services/notification_service.dart` (`scheduleAt`, `product_change` channel, Darwin category, `_medDetails` fix) · `lib/services/notification_actions.dart` (dispatch branch) · `lib/screens/home/home_screen.dart` (`_PredictionBody`) · `lib/services/backup_service.dart` (export filter) · `lib/screens/pregnancy/pregnancy_screen.dart` (session cancel) · `lib/main.dart` (provider registration) · `CLAUDE.md`

**Not touched, deliberately:** `lib/db/database.dart`, `lib/db/tables.dart`, `drift_schemas/`, `test/generated_migrations/`, `lib/services/sync_mapper.dart`, `firestore.rules`. **If a diff proposes a change to any of these, the ephemeral design has been breached.**

---

## Verification

```bash
cd /Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track
flutter analyze          # must be clean
flutter test             # 534 existing + ~35 new, all green
```

**Watch for:** any test that hangs rather than fails is the ticker escaping its gate (Task 7). Kill it and check the `if (session != null)` guard before debugging anything else.

**Device verification (required, not optional)** — same standing rule as the encryption seam. On the OnePlus Nord N200:

1. Start a tampon timer, background the app, confirm the notification arrives and **record the actual delay**.
2. Tap "Changed it" **with the app force-killed** — confirm the session restarts (the isolate → keystore → cipher → write path cannot be unit-tested; `_ready` guards make the seam an absence, not a mock).
3. Set an 8h overnight timer, leave the phone stationary and unplugged, record delivery delay. **If it does not fire at all, that result goes into the setup copy — it is not engineered around.**
4. Reboot mid-session — confirm the notification survives (`ScheduledNotificationBootReceiver` is registered at `AndroidManifest.xml:39-47`; verify once rather than trusting it).
5. Confirm nothing appears on the lock screen, and that the channel name in Settings → Notifications reads "Timed reminders".

---

## Deferred to v2

Timestamped history + the heavy-menstrual-bleeding screen ("soaking through every 2h" is the standard clinical measure — the best thing this can grow into, and it needs saturation input, not just frequency) · configurable quiet hours / night-shift support · multiple simultaneous timers (`getSingleOrNull` structurally forbids it today) · snooze · home-screen-widget countdown (needs a native `Chronometer`; the provider re-renders last-pushed data and has only two string slots) · opt-in `SCHEDULE_EXACT_ALARM` toggle · i18n (English literals per house rule).

**Rejected permanently:** leak prediction (predicts a physical event from a clock; a false negative is a leak the app implied wouldn't happen — the same false-precision family as a conception %) · supply/inventory tracking.
