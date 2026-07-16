# One-tap check-in — design

**Date:** 2026-07-16 · **Status:** Phase A implemented (code-complete; device
verification pending) · Phase B (widget button) deferred
**Feature area:** retention / logging friction

---

## Goal

Let the user answer the daily period check-in **in one tap, without opening the app** —
from the notification shade (Phase A) and the home-screen widget (Phase B).

## Why this, why now

LunaTrack is feature-complete through Phase 4. The chosen lever is retention, and the
binding constraint on a daily-logging app is the cost of logging. Today the cheapest
possible log is roughly six interactions plus a cold app launch:

> unlock → find app → wait for launch → tap "Log today" → tap flow → tap Save

This costs more than it looks, because of two existing design decisions:

- `CycleCalculator` **derives** cycles from consecutive logged bleeding days, and both
  `PredictionResult.confidence` and `.fertilityConfidence` are gated on data volume. A
  skipped log is not just a gap in a chart — it degrades prediction confidence, which
  suppresses the fertility band and ovulation marker. Logging friction attacks the app's
  core value directly.
- `HomeWidgetService` exposes only `push(...)` — the widget is a one-way display.
  `notification_service.dart` has **zero** notification actions. Every path to a logged
  day currently runs through a cold app launch.

## Non-goals

- **No one-tap "yes, it started."** Confirming bleeding requires choosing an intensity;
  that path opens the app, exactly as the Home card does today. This spec adds no new
  logging semantics.
- **No iOS widget interactivity.** The iOS widget does not exist yet (documented only in
  `WIDGET_INTEGRATION.md`). Phase B is Android-only, consistent with the shipped widget.
  iOS notification actions come free via `DarwinNotificationAction` and are in scope.
- **No new settings screen.** See "Privacy" — the chosen default needs no toggle.
- **No new logging dimensions**, no gamification, no streaks.

---

## Design decisions

### 1. Precomputed notification horizon (replaces the static nudge)

**Problem.** `scheduleDailyLogNudge` schedules ONE repeating notification whose text is
frozen at schedule time (`matchDateTimeComponents: DateTimeComponents.time`, body
*"Tap to log your flow and symptoms"*). But the check-in question — "Did it start?" vs
"Has it ended?" vs *nothing* — depends on `(logs, prediction, today)`. A repeating
notification cannot decide at fire time.

**Decision.** Precompute a horizon. `CycleCheckInService.evaluate()` is pure and
deterministic in `(logs, prediction, day)`, and **logs cannot change while the app is
closed** — except via our own notification action, which runs in a background isolate
that can reschedule. So:

- Compute the prompt for each of the next **N days** and schedule N one-shot
  notifications with the correct text and action baked in.
- Recompute the whole horizon on app foreground and inside the background handler after
  it writes.
- **Exactly one notification per day**: the check-in question if there is one, otherwise
  the existing generic "How are you today?" nudge. Never two. This *replaces* the static
  repeating nudge rather than adding alongside it.

**Horizon length: 14 days.** Trade-off: the horizon only extends when the app is opened
or an action is tapped. A user who ignores the app for longer than the horizon stops
getting nudges — a regression against today's infinitely-repeating nudge. 14 days keeps
the alarm count trivial while making that scenario rare; a user silent for two weeks has
churned for reasons a notification will not fix.

**Rejected:** a `WorkManager` daily job to extend the horizon. New dependency and a new
background-execution surface, to fix a case (>14 days idle) that does not matter.

### 2. `setFlowIfEmpty` — make data-preservation structural

**Problem.** `DailyLogRepository.upsert()` rewrites the whole row (flow, symptoms, mood,
notes, bbt, opk). `CycleCheckInService.evaluate()` prompts whenever `flow == null` —
which includes days where the user logged cramps, a mood, and a BBT but no flow.

Today `PeriodCheckInBanner._mark` avoids clobbering those by hand: it reads
`existing?.symptoms ?? '{}'`, `existing?.mood`, … and re-passes them through `saveDay`.
That works, but it is a **convention every caller must remember**, and it is a
read-modify-write.

**Decision.** Add `DailyLogRepository.setFlowIfEmpty({date, flow})` that touches ONLY the
`flow` column, mirroring the existing `setBbtIfEmpty` precedent (single-column,
non-destructive, returns whether it wrote). Two properties matter:

- **Structural, not remembered** — a background caller cannot clobber symptoms even if it
  wants to.
- **Atomic** — no read-modify-write for a background isolate to race against the UI.

It also gives idempotency for free (below).

### 3. Privacy: `visibility: secret`

One-tap logging works by putting cycle state on the lock screen. For this app that is a
safety problem, not a UX detail — roommates, partners, parents, coercive control.

The current `_details` sets no `visibility`. That default is worse than it appears:
Android's `VISIBILITY_PRIVATE` only hides content when the *user* has separately enabled
"hide sensitive notification content," and most devices ship with "show all" — so the
full text lands on the lock screen by default.

**Decision.** `visibility: NotificationVisibility.secret` with explicit text.

- Never appears on the lock screen → nothing leaks to a glance.
- Still in the shade after unlock → keeps the real win (1 tap vs. 6). The step given up
  is "answer without unlocking the phone," which was never the friction.
- No new setting, no new strings, no branch to test. Safe for everyone by default.

**Rejected: discreet wording.** If the body reads a neutral "Tap to check in," the button
"Didn't start" becomes unanswerable — the user cannot know what they are confirming.
Discretion and one-tap are mutually exclusive on the same surface, so the honest lever is
*presence* (secret vs. public), not *wording*.

**Emergent benefit:** because the notification is only answerable after unlock, the
Android keystore is always available when the handler runs — eliminating a whole class of
"keystore unavailable before first unlock" background failure for free.

### 4. Mirror the Home card exactly

| Prompt | Action button | Writes |
|---|---|---|
| `didItStart` | "Didn't start" | `flow = FlowIntensity.none` |
| `hasItEnded` | "Mark ended here" | `flow = FlowIntensity.none` |

Both one-tap answers write the same primitive (a confirmed no-bleeding day). Body-tap
opens the app. Strings are taken verbatim from `PeriodCheckInBanner` so the notification
is a remote control for the existing card, not a second source of truth.

---

## Architecture

```
notification action tap  (or widget button tap, Phase B)
  → background isolate  (@pragma('vm:entry-point'))
  → DartPluginRegistrant.ensureInitialized()      // so flutter_secure_storage works
  → open encrypted DB (keystore → PRAGMA key)
  → CheckInWriter → DailyLogRepository.setFlowIfEmpty(day, none)
  → recompute prediction (pure) → reschedule horizon → push widget
  → cancel the answered notification
  → app on resume reloads logs (a 2nd connection wrote behind its back)
```

`CheckInWriter` is the single shared entry point behind both surfaces, so Phase B is UI
plumbing over a solved problem.

### Files

| File | Change |
|---|---|
| `lib/services/check_in_notifications.dart` | **NEW** — pure horizon planner + scheduler |
| `lib/services/check_in_writer.dart` | **NEW** — shared background write path |
| `lib/services/notification_actions.dart` | **NEW** — `vm:entry-point` handler |
| `lib/data/daily_log_repository.dart` | `+ setFlowIfEmpty` |
| `lib/services/notification_service.dart` | actions + `visibility: secret` in `_details`; background callback in `initialize`; retire `scheduleDailyLogNudge` |
| `lib/providers/reminder_provider.dart` | `reschedule` gains `logs`, schedules the horizon in place of the repeating nudge |
| `lib/db/connection.dart` | `+ PRAGMA busy_timeout` |
| `lib/main.dart` | reload logs on `AppLifecycleState.resumed` |
| `lib/services/home_widget_service.dart` | *(Phase B)* `HomeWidgetData` gains `prompt` |
| `android/.../LunaWidgetProvider.kt` | *(Phase B)* per-button `PendingIntent`s, hide when `prompt == none` |

### Notification IDs

The horizon owns the whole daily-nudge slot. Every day's notification — check-in question
OR generic fallback — is a one-shot from a new base, `idCheckInBase = 4000`, offset by day
index (`4000..4013`). These never collide with medications (2000+) or custom reminders
(3000+).

`idLogNudge` (1001) is **retired**: the repeating nudge it identified is replaced by the
horizon. `reschedule` must `cancel(idLogNudge)` once on migration so any nudge scheduled
by a previous install version does not fire alongside the horizon and double-notify.

### Ownership: `ReminderProvider.reschedule`

The horizon is scheduled from `ReminderProvider.reschedule`, which already owns this
exact job — it schedules the log nudge, schedules one-shots (`periodSoon`), and cancels
when a reminder is disabled. Two consequences:

- **The horizon is gated on the existing `ReminderType.logNudge` toggle** and uses its
  configured hour/minute. If the user turned the daily nudge off, no check-in
  notifications are scheduled. Resurrecting notifications someone explicitly disabled
  would be a bug, not a feature.
- **`reschedule(PredictionResult)` gains `logs`** — the planner needs
  `(logs, prediction, today)`. Signature becomes
  `reschedule(PredictionResult prediction, List<DailyLog> logs)`; update its call sites.

---

## Error handling

- **Stale notification self-heals.** One scheduled 3 days ago and already answered
  in-app? `setFlowIfEmpty` no-ops — because the log *is* the answer flag. Same mechanism
  makes double-taps safe. No dedupe state required.
- **DB locked.** There is no `-wal` sidecar (journal mode is delete/truncate), so a
  foreground app holding the DB plus a shade tap can collide. `PRAGMA busy_timeout` (5s)
  makes the writer wait rather than throw. If it still fails, the user's tap must never
  be silently dropped. **Mechanism** (refined during planning): the action sets
  `cancelNotification: false`, and the handler dismisses the notification only after a
  *successful* write. A failed write therefore leaves the question standing, which is
  itself the retry affordance — no new copy, no "couldn't save" string, no fallback
  launch path. An escaping exception in a bare background isolate would be invisible, so
  `answerNoBleeding` catches and reports `false` rather than throwing.
- **Keystore unavailable.** Moot by construction (see Privacy).
- **No widget host / no plugin** (tests, desktop): swallowed, mirroring the existing
  `HomeWidgetService.push` behaviour.
- **Provider staleness.** The background isolate writes via a second connection; the
  foreground `LogProvider` will not observe it. Reload on resume.

## Testing

Split by what is honestly testable:

- **Pure horizon planner** — unit tests, no plugins: `(logs, prediction, today) →
  [(day, prompt)]`. Covers: no-prompt days fall back to the generic nudge; exactly one
  notification per day; horizon boundary.
- **Respects the existing toggle** — with `ReminderType.logNudge` disabled, the horizon
  schedules nothing. This is the regression guard against resurrecting notifications the
  user turned off.
- **`setFlowIfEmpty`** — in-memory DB: preserves symptoms/mood/notes/bbt/opk; no-ops when
  a flow is already present (idempotency + stale-notification cases).
- **Guardrail** — notification copy never contains "safe" and carries no fertility
  framing; check-in is period-timing only. Mirrors the existing structural guards.
- **Device-only (mandatory).** The background isolate → keystore → encrypted DB path
  **cannot** be unit tested, for the same structural reason encryption could not be: in
  memory test DBs never exercise the cipher, and there is no background isolate under
  `flutter test`. A green suite proves nothing here. Verify on the OnePlus (Android 12):
  fire the check-in, tap the action with the app killed, confirm the day is written, the
  widget refreshes, and the notification is cancelled.

## Guardrails held

- Check-in is **period-timing only** — no fertility framing, so the "safe" guardrail is
  untouched.
- No health data leaves the encrypted DB. **A `SharedPreferences` "pending log" queue was
  explicitly rejected**: it would write "period started today" into unencrypted storage,
  undoing the at-rest guarantee verified on device on 2026-07-16 and declared in
  `PRIVACY_POLICY.md`.
- Notifications are local only — no FCM, no server. The `$0`/on-device thesis is intact.
- Ads never co-render with logging; this feature adds no ad surface.

## Risks

| Risk | Mitigation |
|---|---|
| Plugin registration in the background isolate is the whole feature's crux | Phase A exists to prove exactly this; Phase B reuses it |
| >14 days idle → nudges stop (regression vs. today's repeating nudge) | Accepted; see Horizon |
| Two isolates, one SQLite file, no WAL | `busy_timeout` + open-app fallback |
| New user-facing strings add i18n debt (#6 deferred) | Strings reused verbatim from `PeriodCheckInBanner`; no new setting |

## Open questions

None. Ownership resolved above (`ReminderProvider.reschedule`).
