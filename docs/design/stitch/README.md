# Stitch output — LunaTrack UI (2026-09-07)

Generated from `docs/design/2026-09-07-stitch-ui-brief.md`.

**Canonical source:** Stitch project `9646473112535211876`
→ https://stitch.withgoogle.com/projects/9646473112535211876
Design system asset: `6181781185961493441`.

Open any `.html` directly in a browser. They are self-contained (Tailwind CDN +
Material Symbols), so they render standalone with no build step.

**All 32 of the brief's screen prompts are exported here**, as 42 files — six
prompts asked for two states each, and the secondary variants have since been
added as files 36–42. What is still outstanding is listed at the bottom.

Files 01–35 came out of Stitch whole. Files 36–40 were **composed locally** from
the components in those exports, because on 2026-09-07 the Stitch generate
endpoint stopped returning full-page screens — see "Stitch API behaviours"
below, which is where the evidence for that lives. Each such file says so in an
HTML comment at the top of its `<main>`. Files 41 and 42 are ordinary Stitch
exports.

## Files

| File | Brief | Screen |
|---|---|---|
| `01-today.html` | S09 | Today dashboard — hero, month ring |
| `02-calendar.html` | S10 | Calendar month grid |
| `03-day-log.html` | S14 | Day log entry form |
| `04-insights.html` | S12 | Insights (ad-free) |
| `05-forecast.html` | S11 | Forecast |
| `06-settings.html` | S13 | Settings |
| `07-change-timer.html` | S09b | Change timer — running and past-target |
| `08-photo-describe.html` | S20 | Photo description conversation sheet |
| `09-sign-in.html` | S02 | Sign in, with the local-only hatch |
| `10-onboarding.html` | S05 | Onboarding, 4 steps |
| `11-media-timeline.html` | S17 | Photos & videos grid |
| `12-premium.html` | S27 | Premium (one-time, ad removal only) |
| `13-reminders.html` | S24 | Reminders + lock-screen mock |
| `14-customize-tracking.html` | S25 | Customize tracking, 14 switches |
| `15-diary.html` | S16 | Diary |
| `16-diary-empty.html` | S16 | Diary, empty state |
| `17-cycle-overview.html` | S22 | Cycle overview, four phases |
| `18-medications.html` | S23 | Medications list |
| `19-medications-add-sheet.html` | S23 | Add-medication sheet |
| `20-deletion-pending.html` | S29 | Account deletion pending |
| `21-delete-all-dialog.html` | S30 | Delete all my data (dialog) |
| `22-splash.html` | S01 | Splash / gate |
| `23-sign-up.html` | S03 | Create account + plaintext disclosure |
| `24-forgot-password.html` | S04 | Reset password |
| `25-forgot-password-sent.html` | S04 | Reset password, sent |
| `26-claim-data-sheet.html` | S06 | Claim local data consent sheet |
| `27-app-lock-setup.html` | S08 | Set up app lock |
| `28-media-viewer.html` | S18 | Media viewer (black) |
| `29-photo-consent-sheet.html` | S19 | Describe-photo consent sheet |
| `30-media-upload-failure.html` | S21 | Upload failure, inline |
| `31-account.html` | S28 | Account section |
| `32-pregnancy.html` | S26 | Pregnancy |
| `33-app-lock.html` | S07 | Lock / PIN entry |
| `34-day-entry-sheet.html` | S15 | Day entry bottom sheet |
| `35-components.html` | S31 | Component specimen sheet |
| `36-today-first-run-date.html` | S09 v2 | Today — first run, a date was given |
| `37-today-first-run-no-date.html` | S09 v3 | Today — first run, "I'm not sure" |
| `38-today-low-confidence.html` | S09 v4 | Today — low confidence, established user |
| `39-calendar-day-sheet.html` | S10 | Calendar, day-entry sheet open over the grid |
| `40-day-log-minimal.html` | S14 | Day log — minimal, core groups only |
| `41-sign-in-no-hatch.html` | S02 | Sign in, WITHOUT the local-only hatch |
| `42-photo-describe-limit.html` | S20 | Photo description — daily cap reached |

PNGs exist only for the first six screens, from the earlier export. The HTML is
the artefact; the screenshots were never the source of truth.

### The three Today variants, and why they are three

`OnboardingScreen._finish()` seeds a real `DailyLog` at the date the user gives,
with `flow: medium`. So the answer to "when did your last period start?" decides
which of two completely different screens the user then sees, and both had to be
designed:

- **`36` — a date was given.** `lastStart != null`, so `cycleDay`, `currentPhase`
  and `nextPeriodStart` are all genuinely computed. Confidence is at the floor
  only because no cycle has *completed*. The estimate is therefore shown and
  **tagged low-confidence** — it is the user's own input, and labelling its
  weakness is more honest than withholding it (§6 of the brief).
- **`37` — "I'm not sure".** No log is seeded, `lastStart == null`, and
  `predictFromLogs` returns defaults only: `cycleDay` null, phase unknown,
  `nextPeriodStart` null. There is no estimate to tag **because there is no
  estimate**, so the screen carries none — just honest emptiness and one CTA.
- **`38` — low confidence, established user.** Same arithmetic as `01-today`
  (cycle day 1 = 20 Aug → 7 Sep is cycle day 19, luteal, next period 17 Sep).
  What differs is the *confidence*, not the numbers.

In `36` and `38` alike the fertility gate does the work: `fertilityBand` returns
`none`, so the fertile card and every fertile/ovulation ring segment are **absent
rather than greyed**, and the words "fertile" and "ovulation" appear nowhere in
the visible copy of either file. Suppressed days fall back to their phase colour.

Each ring was re-derived and **rendered with the day numbers drawn around it**
before being trusted, per the QA note at the bottom of this file. That caught a
defect a text scan cannot see: in `36`, today (7 Sep) is the first day of the
follicular run, and the dotted "today" marker is painted in the *same* colour as
the run beneath it — so it was invisible. The run is now drawn at 0.35 opacity
with the dots at full strength, which is the same convention `01-today` already
used for its amber-on-amber luteal day. **A dotted day only reads if the run under
it is lighter than the dots.**

Legends follow the existing rule that a key appears only when a matching segment
is actually painted: `36` shows Period + Estimate, `38` shows Estimate alone (no
logged bleeding day falls in September in that scenario), and `37` has no legend
at all because its ring has no segments.

## Hand-patched after export — and why

Four files were edited locally rather than in Stitch. Each is recorded here
because a later re-export from the project will silently revert them.

- **`03-day-log.html`** — the WELLBEING card shipped with only "Water" and
  "Sleep (hours)". Added **Energy**, **Stress** and **Sleep quality**.
- **`02-calendar.html`** — the `book` (Diary) icon sat in the app bar's LEADING
  slot, where Android users read it as a back control on a top-level tab. Both
  actions are now trailing.
- **`11-media-timeline.html`** — the populated grid carried no storage
  disclosure; the brief only put that line in the empty state, and Stitch only
  generated the populated one. Added the permanent strip "Photos are uploaded to
  your account and are not encrypted on our servers." (Same edit is applied in
  the live project.)
- **`01-today.html`** — see below.
- **`35-components.html`** — the generator dropped groups 7 (ad slot) and 8
  (navigation bar) entirely, and drew the month ring as a four-quadrant CSS
  border trick rather than per-day segments. Both dropped groups were written by
  hand, and the fake ring was replaced with the real one at all three sizes. A
  four-colour border in the file that is supposed to BE the component's source of
  truth is worse than no specimen at all.

### The Today screen was telling two different stories

The generated ring painted a **period across 1-5 September** while every card
beside it said *Day 19*, *Luteal*, *next period in 9 days*. Those cannot both be
true. The confusion is worth naming because it is easy to repeat: **the ring is
indexed by DAY OF MONTH; "Day 19" is the CYCLE day.** Two different numbers.

Everything on the screen is now derived from ONE written-down scenario, run
through the real arithmetic in `lib/services/prediction_service.dart`
(`_lutealDays = 14`, `_fertilePreOvulation = 5`, `_fertilePostOvulation = 1`):

> cycle day 1 = **20 August**, average cycle 28, period 5 days.
> → ovulation = 20 Aug + (28 - 14) = **3 September** (cycle day 15)
> → fertile window = 3 Sep - 5 … +1 = **29 Aug - 4 Sep**
> → next period = **17 September** (so "in 10 days", not 9)
> → today = **7 September** = **cycle day 19**, luteal

| September | Cycle day | Role |
|---|---|---|
| 1-2 | 13-14 | fertile |
| 3 | 15 | estimated ovulation |
| 4 | 16 | fertile (window closes) |
| 5-16 | 17-28 | luteal |
| **7** | **19** | **today** (dotted) |
| 17-21 | - | estimated next period |
| 22-30 | - | follicular |

#### The fertile card: the answer was a third option

The open question was framed as a binary — show "Lower", or show nothing. Reading
`_FertileCard` in `lib/screens/home/home_screen.dart` settles it as **neither**:

- The card **always renders** when a fertile window exists. On cycle day 19 the
  window has passed, so the widget **rolls it forward one cycle** (+28d) and shows
  **26 Sep - 2 Oct**, and the title drops the "(now)" suffix, becoming
  **"Estimated fertile window"**.
- The **band** (`Lower` / `Higher` / `Peak`) is computed from the RAW current-cycle
  window, not the rolled one. Today is outside it, so `fertilityBand` returns
  `FertilityBand.none`, and `footer:` is therefore **null** — no band label, no dot,
  no three-step meter.

So the card is a **date range**; the band is the only fertility *signal*, and only
the band self-suppresses. The mock now matches that exactly. The brief's original
"Higher" was a false fertile signal on a luteal day; "Lower" would have been a
quieter version of the same mistake, because on day 19 there should be no band at
all. The three-step meter component now lives in `35-components.html`, which is
where a component belongs when no real screen state shows it.

#### The ring was also painting itself over

Not visible in a thumbnail, and no guardrail catches it: **`stroke-dasharray`
repeats around the ENTIRE path.** Each of the eight `<circle>` runs was painting
dashes for the full 276-unit circumference, not just its own span, so the last
one drawn (follicular teal) covered the whole ring. The layering only appeared to
work because each later circle happened to overpaint the earlier ones.

The fix is structural rather than arithmetic: **`pathLength="30"`** normalises the
circle to 30 units, so 1 unit = 1 day and a run is simply
`stroke-dasharray="N (30-N)"` at `stroke-dashoffset="-(day-1)"` — the gap
explicitly spans the rest of the ring, so nothing can repeat. Two consequences:

- Per-day tick separators are drawn by a **single** extra circle with
  `stroke-dasharray="0.09 0.91"`. That one is *meant* to repeat: the pattern sums
  to exactly one day.
- Today's dotted segment uses six dash values summing to exactly 30, so the
  pattern covers the ring once and its three dots land inside day 7 alone —
  with **butt caps, never `stroke-linecap="round"`**. A round cap adds half the
  stroke width to each end of every dash: 5 user units, which is **0.54 pathLength
  units** here, against a 0.22-unit dot. The three dots tripled in width and fused
  into one solid amber blob wider than a whole day. Cap extension is in user units;
  `pathLength` rescales the dash array but not the stroke geometry.

A third consequence followed: the estimated next-period run is now painted in the
**lavender `#B0A8C0`** predicted token rather than rose, because the design system
reserves lavender for *all* estimated states and the legend's "Estimate" key had
no matching arc. The legend's solid "Period" entry was removed — no logged
bleeding day falls in September in this scenario, and the app's rule is that a
legend entry appears only when a matching segment is actually painted.

## Caveats

- **Every exported file is light mode.** A Stitch design system carries one
  `colorMode`, so dark cannot be re-themed out of this one — it needs its own.
  That second system now exists (`assets/8873628026339279935`); no screen has
  been generated against it yet. See "Still outstanding".
- **`08-photo-describe.html` contains a synthetic "medical-style skin photo"**
  that Stitch generated on its own as a background. Replace or blur it before
  this mock circulates — a realistic clinical-looking image invites exactly the
  interpretation the feature is built to refuse.

## Still outstanding

Every screen prompt in the brief is exported, and so is every secondary variant
that was outstanding before 2026-09-07 — the two first-run Today states, the
low-confidence Today state, the calendar with the day sheet open, the minimal
day log, the disabled-composer description sheet and the hatch-less sign-in are
now files `36`–`42`.

What is left is **dark mode**, and it is blocked rather than merely undone:

- A **dark design system now exists**: `assets/8873628026339279935`
  ("LunaTrack — dark"), created in the same project via `create_design_system`
  with `colorMode: DARK`. Its `designMd` is the light system's, re-tokenised —
  dark phase palette as primary (Menstrual `#E97B93`, Follicular `#7FC7BB`,
  Ovulatory `#98B0EE`, Luteal `#E3B579`, Fertile `#5E8A82`, Predicted `#6E6885`),
  base `#121011`, elevated cards `#221E20`, text `#F2E9EC`, and one dark-specific
  ring note: **the per-day tick separators must be drawn in the card colour, not
  white**, or the ring reads as dashes on dark instead of segments.
- **No dark screen has been generated.** The five load-bearing ones (Today,
  Calendar, Insights, Day log, Settings) are all full pages, and full pages are
  exactly what the endpoint would not return that day. The design system is
  ready; the generations are not.

Do not "solve" this by hex-swapping the light files. Two spots break under a
naive swap and both are on-accent text: the nav pill (`bg-[#F7A8C4]
text-[#3A2A30]`) and the filled CTA both need to KEEP dark text on pink, while
every other `#3A2A30` becomes `#F2E9EC`. A global replace inverts them into
unreadable light-on-pink, and no text-based check catches it.

## Stitch API behaviours worth knowing before you re-export

- **`download_assets` reports success and writes nothing.** It returned
  "Assets downloaded to …" twice while creating no directory and no files. Do not
  trust its return value; check the filesystem.
- **`list_screens` returns `{}`** even with 30+ screens in the project. Use
  `get_screen` with a screen id instead — it works, and its response is compact
  (no `designMd` echo), unlike `generate_screen_from_text`.
- **A screen's file URL is a frozen snapshot.** An edit applied as DOM operations
  updates the hosted screen but does NOT mint a new URL, and `get_screen` returns
  the same URL as before. The only way to get post-edit HTML locally is to apply
  the same DOM operation by hand — which is what happened with the media-timeline
  disclosure above.
- **The Stitch agent's self-report is not evidence.** It has claimed to have made
  an edit that grep proved absent. Verify by content, every time.
- **Issue `generate_screen_from_text` one call at a time.** Two fired in parallel
  both returned `Network failure connecting to Stitch API: fetch failed`, and a
  call issued immediately after a success usually fails too. Sequential, with the
  gap that ordinary work between calls provides, is reliable. The earlier
  "quota exhausted after ~28 calls" reading was partly this: retrying a failure
  straight away is the one thing guaranteed not to work.
- **The two models fail differently on a large prompt, and Flash fails silently.**
  The 8-group component sheet timed out on `GEMINI_3_1_PRO` four times.
  `GEMINI_3_FLASH` completed it — but dropped groups 7 and 8 entirely and faked
  the month ring, while its summary text described a complete sheet. A generation
  that returns is not a generation that is complete: count the groups.
- **`deviceType` in the response describes the screenshot canvas, not the layout.**
  The component sheet came back as `DESKTOP` / `width: 2560`, but the markup is a
  single `max-w-lg` column. Judge the HTML, not the metadata.

### 2026-09-07: the endpoint stopped returning full-page screens

Recorded because it cost most of a session, and because three plausible theories
were wrong before the right one showed up. Every failure was the same opaque
`Network failure connecting to Stitch API: fetch failed` — there is no error
message to read, so the only way to learn anything is controlled experiments.

The result, from 12 calls: **`generate_screen_from_text` succeeds on small
screens and fails on large ones.** Nothing else predicted it.

| Screen asked for | Output size | Result |
|---|---|---|
| Sign in (no hatch) | 6.8 KB | success, twice |
| Photo-description sheet, cap reached | 7.8 KB | success |
| One "Next period" card, alone on a page | 3.8 KB | success |
| Today (any of the three variants) | would be ~10 KB+ | fail, 5 attempts |
| Day log, minimal — only 5 sections | would be ~11 KB | fail, 4 attempts |
| Settings, dark | would be ~12 KB | fail |

What was ruled out, each by a deliberate test rather than by argument:

- **Not prompt size.** A 1.6 KB prompt failed; a 1.66 KB prompt succeeded. Sizes
  from 1.6 KB to 5.4 KB were tried. Prompt length does not predict anything —
  what the prompt *asks the model to draw* does.
- **Not the endpoint being down, and not a rate limit or a per-session quota.**
  The byte-identical sign-in prompt was re-sent after six consecutive failures
  and succeeded immediately. Cooldowns of 90 s, 150 s and 300 s changed nothing
  in either direction.
- **Not `GEMINI_3_1_PRO` specifically.** `GEMINI_3_FLASH` fails on the same
  screens, so this is not the Pro-times-out-on-big-prompts effect already
  recorded above.
- **Not literal `<svg>`/`<circle>` markup in the prompt**, and **not the
  menstrual vocabulary** either. The single-card generation that succeeded is
  titled "Next period card (low confidence)" and is full of the same words as
  the screens that failed.

Two practical consequences:

- **A failure is fast; a success is slow.** Once you notice that, you can tell
  the two apart before the result even lands, which is the cheapest signal
  available here.
- **A timed-out generation is unrecoverable.** The tool docs say to poll
  `get_screen` after a connection error, but `get_screen` needs an id and the id
  only ever arrives in the response you did not get. `list_screens` still returns
  `{}` and `get_project` does not enumerate screens, so there is no way back to a
  screen a failed call may have created. `get_project`'s `updateTime` does move,
  which is enough to confirm a call landed and nothing more.

**The workaround that worked:** ask Stitch for a *component* rather than a page —
those come back — and assemble the page locally from it plus the components in
the existing exports. That is the provenance of files `36`–`40`; the "Next period"
card inside `36` and `38` is genuinely Stitch-generated (screen
`ad37f368375d41df98d1d26a09bf14cd`), retokenised onto each file's palette.

## QA performed

**Render the page, do not reason about it.** The Chrome extension is not required:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --hide-scrollbars --window-size=800,900 --screenshot=/tmp/out.png \
  --virtual-time-budget=4000 "file://$PWD/01-today.html"
```

This is what caught the fused-dot blob, which no text scan could see and which the
arithmetic said was correct. For the ring specifically, extract the `<svg>` into a
throwaway page at ~560px with the day numbers drawn around it — then the mapping
from segment to calendar day is checkable at a glance instead of by counting arcs.

Strip tags with a real HTML parser that **skips `<script>` and `<style>`**, not
with a regex. A naive strip scans the Tailwind config and the CSS as if it were
copy, and then reports `safe` (from `pb-safe` / `safe-area-inset`), `%` (from
every CSS length) and `weight` (from `font-weight`) on files that are perfectly
clean. All three were seen on this set; all three are noise.

Every screen is checked by stripping tags and scanning the **rendered text**,
which catches things a 157px thumbnail cannot. Current results across all 42
files: **0 files with issues.**

- No **"safe"**, "overdue", "urgent", "danger", "you're fine", "no rush", "BMI",
  "streak", "badge" or "remaining" in any visible copy — **0 hits**.
- No **percentage** within 60 characters of any fertility, ovulation, conception
  or pregnancy word.
- The change timer has **zero** `<circle>` / `<progress>` / `stroke-dasharray`
  elements — no countdown, no arc, no bar.
- Ads present on Today and Settings; **absent** from Day log, Insights and Diary.
- `29-photo-consent-sheet.html` — the Allow / Not now buttons are in a
  `flex flex-col` container, both `w-full`. The 2026-08-13 device bug, where
  Allow rendered off-screen and consent could not be granted, is **not**
  reproduced.
- `12-premium.html` — no urgency, no crossed-out price, no subscription. (A grep
  for `subscri` matches only the honest fine print "No subscription.")
- `32-pregnancy.html` — no fetal or fruit size comparison, no baby imagery, no
  congratulatory language, no exclamation mark; neutral exit present.
- `11-media-timeline.html` — no `getDownloadURL`.
- `20-deletion-pending.html` — cancellable, with the scheduled date.
- `33-app-lock.html` — the whole visible text is *LunaTrack · Enter your PIN ·
  0-9 · Use biometrics instead · Forgot PIN?* and nothing else. No date, no cycle
  day, no health word, no blurred preview of the app behind the lock. The only
  match for a leak-word scan is "track" inside the app's own name.
- `34-day-entry-sheet.html` — no ad, no fertility content, Save pinned in its own
  footer; the only side-by-side pair is two OUTLINED buttons, which is allowed.
- `35-components.html` — all 8 groups present, 5 nav-bar states, 3 real rings.
- `21-delete-all-dialog.html` — states both halves (device erased, account copy
  left alone).
- `36` / `38` — the visible copy contains **no** "fertile" and **no** "ovulation";
  the only matches in the file are the phase name "Follicular", the Tailwind
  colour tokens and the explanatory HTML comments. No fertile card, no band, no
  three-step meter. `37` additionally has no next-period card and no legend.
- `39-calendar-day-sheet.html` — **no ad banner**: `_selectedDay` gates the
  calendar ad off while the sheet is open, and ads never co-render with logging.
  Still exactly 5 nav destinations. The two check-in actions are **outlined**
  buttons in their row, never filled — one Save, in the sheet's own bottom bar.
- `40-day-log-minimal.html` — exactly 5 sections (Flow, Mood, Pain level,
  Temperature & ovulation tests, Notes), no ad banner, and the omitted categories
  are genuinely **absent**: greps for Physical symptoms, Emotional symptoms,
  Wellbeing, Weight, Discharge, Medications and Lifestyle all return 0. They are
  not drawn as disabled or "locked" rows, and there is no nudge to re-enable them.
- `41-sign-in-no-hatch.html` — greps for "without syncing" and "unavailable"
  return 0. The whole visible text is *LunaTrack · Email · Password · Sign in ·
  Create an account · Forgot password?* No nav bar, no ad.
- `42-photo-describe-limit.html` — the caveat line appears **twice, once under
  each answer**; the counter says "You've used today's 20 messages" and the word
  "photos" appears nowhere in it, because the cap counts messages (every turn
  bills). No upgrade, buy-more or reset-countdown affordance. The description
  copy names only colour, size and position — no condition, no severity, no
  treatment. Its `<title>` was the one hand-patch: Stitch shipped it as
  "Conversation History".

Three earlier QA "failures" were the grep being blunt, not real defects: the
premium `subscri` match above, `flex` matching `flex-col`, and `Skin &amp; hair`
not matching a search for `Skin & hair`. Worth remembering — a naive scan over
HTML produces false positives in all three of those shapes.

A fifth, and the funniest: scanning for `diagnos` flags `04-insights.html`, on
the line **"An observation, not a diagnosis."** — the caption the brief requires
precisely *because* the chart is not one. The banned-word list and the disclaimer
that disowns the banned thing are made of the same letters, so any check for a
forbidden concept will hit the copy promising its absence. Read the match before
believing it.

A fourth, added by the ring work: a scan for `stroke-dasharray` without
`pathLength` flags four files that are perfectly correct. Sign-in, Premium and
Splash use **decorative** dashed circles — a logo mark, an accent arc, a splash
ring — where tiling around the whole circumference is exactly the intent, and
Insights dashes a chart baseline. A month ring is specifically **3+ dasharray
circles painted in phase colours**; only those need `pathLength`. Both real rings
(`01-today`, `35-components`) have it.

**And the limit of grep, which is the more useful lesson.** The two worst defects
found in this whole set were invisible to it. A ring contradicting the cards
beside it passes every word check, because each individual string is fine. A
`stroke-dasharray` silently repeating around the whole circle is not a string at
all. Both were found by asking *what scenario is this screen claiming, and does
the arithmetic hold* — check the scenario before you check the pixels.
