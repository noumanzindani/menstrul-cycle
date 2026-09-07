# LunaTrack — Stitch UI Design Brief

Council-adjudicated, 2026-09-07. Three seats: **Product / Safety / Feasibility**,
same convention as `docs/superpowers/plans/`.

This document is an **input to Google Stitch**, not a spec for engineers. Section 2
is pasted once as the design system; Section 4 is pasted one screen at a time.
Section 1 exists so that whoever runs it knows which Stitch output to reject.

---

## 0. How to use this

1. Paste **PROMPT A** (§2) into Stitch as the project/design-system prompt.
2. For each screen, paste **PROMPT B** (§3, ~10 lines, unchanged every time)
   followed by that screen's prompt from §4.
3. Check every result against the reject-list in §5 before accepting it.

Generate in this order — later screens reuse components established by earlier ones:
**S09 Today → S10 Calendar → S14 Day Log → S12 Insights → S11 Forecast → S13 Settings**,
then everything else.

---

## 1. Council rulings

The Safety seat holds veto power in this repo. These are not style preferences;
each one traces to a ruling already recorded in `CLAUDE.md`.

### Design thesis (Product seat)

> **Calm clinical honesty.** LunaTrack's differentiator is that it refuses to
> lie to you: no invented percentages, no "safe days", no promise that a
> notification will arrive. The UI must *feel* like that — generous whitespace,
> soft non-alarmist colour, one hero answer per screen, and no urgency styling
> anywhere. It is the un-gamified tracker.

Consequences the designer must hold:
- **No streaks, badges, confetti, rings-to-close, or completion percentages.**
  Gamification aimed partly at teenagers is a shame mechanic. Vetoed.
- **No red.** Rose `#D64F6E` is the menstrual token, not an alert colour. Nothing
  in this app is an emergency, and nothing may be styled as one.
- **Signature element: the month ring.** The `MonthRing` on Today is the app's
  one distinctive visual. Treat it as the brand mark.

### VETOED (Safety seat) — reject any Stitch output containing these

| Vetoed | Why |
|---|---|
| The word **"safe"** anywhere near fertility/ovulation | Prediction is the calendar method. "Safe day" reads as contraception and is a real-user-harm risk. |
| **Any fertility percentage or score** ("87% chance") | False precision from a calendar-only estimate. The band is qualitative: **Lower / Higher / Peak** only. |
| A **countdown or progress bar** on the change timer | A bar is a countdown in pixels. Elapsed counts **UP** only; time remaining is never shown. |
| **"Overdue" / "urgent" / "danger" / "you're fine" / "no rush"** | The only permitted framing for a passed target is *"past the 4h **you set**"* — the target is the user's, so the app is never the one calling it late. |
| **BMI, a weight class, or any body judgement** | Same class of harm as a synthesized fertility %. Weight shows a value and a trend line, never a label. |
| An **AI "diagnosis"** of a photo — condition names, severity scores, treatment | A description is never an interpretation. Sheet copy is descriptive prose plus a fixed caveat line. |
| **Ads on the logging or insights screens** | Structurally tested. Banners appear only on Today, Calendar, Forecast, Settings. |
| **Cycle content in a lock-screen notification preview** | Notifications are `visibility: secret`. Mock-ups must show a generic collapsed notification. |
| A **TSS symptom checker, triage, or emergency call affordance** | Medical-device function. |

### Feasibility seat — hard constraints from the existing code

- **Material 3 (Material You), Android, portrait, 360×800dp.** `useMaterial3: true`.
- **Exactly 5 bottom-nav destinations** — Material's maximum, and the app is at it:
  `Today · Calendar · Forecast · Insights · Settings`. **Diary and Media are
  app-bar actions on Calendar**, never nav items. Do not add a sixth tab.
- **Primary buttons are full-width, stacked, 52dp tall.** `filledButtonTheme` sets
  `minimumSize: Size.fromHeight(52)` = infinite width. Two filled buttons side by
  side is not a style choice here, it is a layout bug that ships clipped controls.
  Side-by-side actions must be text/outlined buttons, or equal-weight and explicitly split.
- **Exact radii: cards 20dp, filled buttons 16dp, chips 12dp.** Card elevation **0**.
- **Flat app bar** — elevation 0, left-aligned title, surface-coloured, no tint on scroll.
- **Light and dark are both required.** Both palettes are given in PROMPT A.
- Day entry has **two hosts**: a full screen (from Today) and a bottom sheet (from
  Calendar). Same form, different chrome.

---

## 2. PROMPT A — design system (paste once)

```
Create a design system for "LunaTrack", an Android menstrual-cycle tracking app.

Style: Material 3 / Material You. Mobile portrait, 360x800dp. Font: Roboto.
Mood: calm, private, clinical-but-warm, unhurried. Soft and supportive, never
alarmist, never playful. Generous whitespace. No gamification of any kind — no
streaks, badges, confetti, trophies or completion rings.

LIGHT THEME
- Background / surface: pure white #FFFFFF
- Primary text: #3A2A30 (warm near-black)
- Seed / primary accent: baby pink #F7A8C4
- Cards and sheets: soft pink tint derived from the seed, elevation 0
- Cycle phase colours:
    Menstrual  #D64F6E (rose)
    Follicular #6FB3A8 (soft teal)
    Ovulatory  #7E9CE8 (periwinkle)
    Luteal     #D9A15B (warm amber)
    Fertile    #9CCFC6 (light teal wash)
    Predicted  #B0A8C0 (muted lavender-grey, used for all estimated/unknown states)

DARK THEME
- Phase colours: Menstrual #E97B93, Follicular #7FC7BB, Ovulatory #98B0EE,
  Luteal #E3B579, Fertile #5E8A82, Predicted #6E6885
- Dark surfaces carry the same soft-pink tint at low chroma.

SHAPE AND CONTROLS
- Cards: 20dp corner radius, elevation 0, filled (no borders, no drop shadows)
- Filled buttons: 16dp radius, 52dp tall, FULL WIDTH, stacked vertically —
  never two filled buttons side by side in a row
- Chips: 12dp radius, selectable, used heavily for symptom/mood tagging
- App bar: flat, elevation 0, surface-coloured, title left-aligned
- Bottom navigation: 5 destinations, Material 3 NavigationBar with a pill indicator

COMPONENTS TO ESTABLISH
1. Info card — 20dp radius, filled, a small phase-coloured dot or icon, a short
   label line, and one large value line. This is the workhorse of the app.
2. Month ring — a circular ring of one small arc segment per day of the current
   month, each segment tinted by that day's phase colour, today's segment shown
   dotted. The ring's centre holds the date, the cycle day, and the phase name.
   This is the app's signature visual.
3. Disclaimer banner — a low-contrast, non-alarming inline strip with a small
   info icon and one line of fine print. It is a permanent designed element, not
   an error state.
4. Chip grid — wrapping rows of selectable chips with a small icon and a label.
5. Ad banner slot — a 320x50 placeholder pinned to the very bottom, ABOVE the
   bottom navigation bar, visually separated and clearly not app content.

TONE OF COPY
Plain, second-person, unhurried, never clinical-cold and never cute. Estimates are
always labelled as estimates. Never use the words "safe", "overdue", "urgent",
"danger", or "you're fine". Never display a fertility or pregnancy percentage.
```

---

## 3. PROMPT B — global rules (prepend to every screen prompt)

```
Follow the LunaTrack design system. Material 3, Android, 360x800dp portrait,
Roboto, white background with baby-pink cards, cards 20dp radius elevation 0,
filled buttons 16dp radius 52dp tall and full width (never two side by side),
chips 12dp radius, flat app bar.

NEVER include: the word "safe"; any fertility, ovulation or pregnancy percentage
or score; a countdown, a progress bar or a "time remaining" figure; the words
"overdue", "urgent", "danger", "you're fine" or "no rush"; a BMI or any weight
category label; a medical diagnosis, condition name or severity rating; streaks,
badges, confetti or gamification; red alert styling.

Fertility is shown ONLY as a qualitative band: "Lower", "Higher" or "Peak".
Every screen that mentions fertility or ovulation ends with the disclaimer
banner: "Estimates only — not a contraceptive method."
```

---

## 4. Screen prompts

### Group A — Onboarding & account (6)

**S01 · Splash / gate.** Full-bleed white. Centred: the LunaTrack wordmark above a
small static month-ring mark in soft pink, and a slim indeterminate progress line.
Nothing else — no tagline, no illustration of a body.

**S02 · Sign in.** App bar–less. Wordmark and ring mark at the top third. Email and
password outlined text fields with floating labels. Full-width filled "Sign in".
Below it, two text buttons stacked: "Create an account" and "Forgot password?".
At the very bottom, a low-contrast outlined button "Continue without syncing" with
one line of fine print: "Cloud sync is unavailable right now. Everything stays on
this device." Show a variant where that bottom block is absent (the normal case).

**S03 · Sign up.** Same layout as S02. Email, password, confirm-password fields,
inline validation text in the error colour under the field. Full-width filled
"Create account". Below the button, a fine-print block: "Your daily logs and
settings sync to our server so they reach your other devices. They are encrypted
in transit and stored in plain text — we can read them. Photos are stored
unencrypted." Then a text button "Read the privacy policy".

**S04 · Forgot password.** App bar with back arrow, title "Reset password". One
email field, one line of explanation, a full-width filled "Send reset link", and a
success state showing a calm confirmation card instead of a toast.

**S05 · Onboarding, 4 steps.** A stepper with a slim linear progress line under the
app bar, one question per screen, and a full-width filled "Continue" pinned to the
bottom. Steps: (1) "When did your last period start?" — an inline month calendar,
with a text button "I'm not sure"; (2) "How long is your cycle, usually?" — a large
number stepper, default 28, with the sub-label "days from the first day of one
period to the next"; (3) "How long does your period last?" — number stepper,
default 5; (4) "What are you using LunaTrack for?" — two large selectable cards,
"Track my cycle" and "Trying to conceive", each with a one-line description.
Generate all four.

**S06 · Claim-local-data sheet.** A modal bottom sheet, 20dp top corners, drag
handle. Title "Use the data already on this device?". Body: this device has
logs that were saved before signing in — choose whether to upload them to the
account, or keep the account's own data. Two stacked full-width buttons: filled
"Upload this device's data", outlined "Keep the account's data". A text button
"Decide later" beneath. This is a consent decision — do not style either option
as the obvious default.

### Group B — App lock (2)

**S07 · Lock screen.** Full white, no app bar, no back affordance. Centred ring
mark, then a 6-dot PIN indicator, then a 3x4 numeric keypad with large circular
touch targets. Below, a text button "Use fingerprint" with a fingerprint icon.
Show an error variant where the dots shake and one line of red-free error text
reads "That PIN didn't match." **The screen must not name the app's purpose** —
no cycle content, no phase colour, nothing that identifies this as a period
tracker to someone looking over a shoulder.

**S08 · Set up app lock.** App bar "App lock". A short explainer card, a PIN entry
and confirm flow reusing S07's keypad, and a switch row "Also allow fingerprint".

### Group C — The five tabs (5)

**S09 · TODAY (hero screen).** The most important screen in the app. Scrolling
column, app bar title "Today" with a small settings-free right side. In order:

1. **Phase card** — full width, filled with the current phase colour at low
   opacity, a phase dot, the phase name ("Luteal phase"), and a large "Day 19"
   cycle-day figure.
2. **Month ring card** — the signature ring, centred, roughly 200dp, one arc
   segment per day of the current month tinted by phase, today's segment dotted.
   Ring centre: the date, "Day 19", the phase name. Below the ring, a compact
   legend with a coloured dot and label per role — Period, Predicted, Fertile,
   Ovulation — where **Fertile and Ovulation entries appear only when the ring
   actually paints such a segment**.
3. **Check-in card** — appears only when the app has a question. Title "Did your
   period start?" or "Has your period ended?", then three actions: two chip-style
   buttons "Not yet" and "It ended", plus a text button "Log it".
4. **Next period card** — an info card, label "Next period", value "in 10 days ·
   around 17 Sep", and a small "estimate" tag. A variant reads "3 days late".
5. **Fertile window card** — info card. **Its content depends on the cycle day and
   must be derived, never chosen.** `_FertileCard` always renders the card, but:
   - **Inside** the window: label "Fertile window (now)", the date range, and a
     band row — a coloured dot plus "Lower / Higher chance today (estimated)" or
     "Most fertile today (estimated)".
   - **Outside** it (the day-19 scenario used for these mocks): the window rolls
     forward one cycle, the label becomes "Estimated fertile window", the value is
     the rolled **date range**, and there is **NO band row at all** —
     `fertilityBand` returns `none`, so the footer is null.

   The card is a date range; the band is the only fertility *signal*, and only the
   band self-suppresses. **No number, no percentage, no gradient scale.** The
   three-step band component belongs in the S31 component sheet, not forced onto a
   luteal day so it can be seen.
6. **Insight highlight card** — a quiet card with a small chart-line icon, title
   "Your patterns", and one plain sentence, e.g. "Your recent cycles are running
   about 2 days shorter than earlier ones."
7. **Product timer start row** — a label "Change timer" and four chips: Pad,
   Tampon, Cup / disc, Period underwear.
8. **Disclaimer banner**, then the ad banner slot at the very bottom.

Generate **four** variants of this screen:

1. **Full state**, as described above.
2. **First run, date given** (see §6). The phase card and month ring render
   normally; the next-period card shows a date with an "estimate" tag plus a
   second fine-print line, "Low confidence — based on what you told us at setup";
   the fertile card and every fertile/ovulation segment in the ring are
   **entirely absent**, not greyed or placeholdered; and a full-width filled
   "Log today" sits below. No insight-highlight card.
3. **First run, no date given** (see §6). The phase card reads "Cycle day —" with
   no phase colour, the ring is a single flat grey outline with no segments and
   no legend, and there is no next-period card at all. In their place, one
   centred block: "Nothing logged yet", one line — "Your cycle picture builds
   from the days you log" — and a full-width filled "Log today".
4. **Low-confidence state** for an established user: the fertile card and the
   ring's fertile segments are absent and the next-period card carries a
   "low confidence" tag.

**S09b · Product timer — running.** The card from S09 in its active state: product
name "Tampon", a large **elapsed** figure counting **up** ("3h 12m"), the sub-line
"since 09:40 · you set 4h", and a full-width outlined "Changed it" button.
**No ring, no arc, no bar, no remaining time.** Generate a second variant, past
the target, whose only difference is the value reading "5h 02m", a sub-line "past
the 4h you set", and one extra fine-print line: "Reminders are best-effort — one
may not have arrived." Nothing turns red, nothing is emphasised, no icon changes.

**S10 · Calendar.** App bar "Calendar" with two right-hand icon actions: a book
icon (Diary) and a photo-stack icon (Media). Below it a month grid, weekday
initials, and day cells where each cell is a circle tinted by its phase colour —
solid for logged bleeding days, a soft ring outline for predicted days, a light
teal wash for fertile days, a small dot marker for ovulation, and a tiny pip under
any day carrying a log. Month navigation chevrons with the month name. Below the
grid, a small legend. Ad banner at the bottom. Generate a second variant with the
day-entry bottom sheet open over it.

**S11 · Forecast.** App bar "Forecast". A vertical list of upcoming cycles, one
card each: a date range in large type ("16 – 21 Sep"), a "Period" label with the
rose dot, and beneath it a lighter row for the estimated fertile window with the
teal dot. Each card carries a small "estimate" tag. A leading explainer card in
plain language: predictions come from the days you log, and improve as you log
more. Disclaimer banner, then ad banner.

**S12 · Insights.** App bar "Insights". **No ad banner on this screen.** Sections,
each a card:
1. **Cycle length** — a bar chart of the last 6 cycles in days, with an average line.
2. **Your patterns** — 3–4 plain-sentence rows, each with a small leading icon:
   cycle-length trend, regularity, period-length trend, and a symptom-to-phase
   correlation ("You most often log headaches around your luteal phase").
3. **Symptom frequency** — a horizontal bar list of the most-logged symptoms.
4. **Basal body temperature** — a line chart in periwinkle with a subtle marked
   thermal shift, captioned "An observation, not a diagnosis."
5. **Weight** — a 90-day line chart and a net-change figure. **No BMI, no category,
   no target, no ideal range band.**
6. A full-width filled button "Export a report for my doctor (PDF)".
Disclaimer banner last.

**S13 · Settings.** App bar "Settings". Grouped list sections with small
uppercase headers: **Account** (email row, "Sync now" with a "Last synced 2 min
ago" subtitle, "Sign out", and a destructive-styled "Request account deletion");
**Cycle** (mode, average cycle length, average period length); **Tracking**
("Customize tracking", "Medications", "Reminders"); **Appearance** (theme
light/dark/system, language, a "Gender-neutral language" switch);
**Privacy & security** (app lock switch, "Backup & restore", "Delete all my data"
in the destructive style); **About** (Premium, privacy policy, version).
Ad banner at the bottom.

### Group D — Logging (3)

**S14 · Day log (full screen).** The densest screen in the app. App bar with a
close X and the date "Sunday, 7 September"; a full-width filled **"Save"** in a
bottom bar. **No ad banner anywhere on this screen.** Scrolling sections, each
with a small uppercase header:
1. **Flow** — 5 selectable icon chips: Spotting, Light, Medium, Heavy, Flooding.
   Each chip's icon is a droplet whose FILL FRACTION encodes intensity, in a
   single constant rose — the colour must not also fade across the ramp.
   Directly beneath, a switch row "Period ended today" with the subtitle
   "Marks today as no bleeding".
2. **Physical symptoms** — a wrapping grid of exactly 22 icon chips (cramps,
   headache, bloating, fatigue, nausea, backache, acne, cravings, dizziness,
   insomnia, hot flashes, …). Multi-select.
3. **Emotional symptoms** — a separate wrapping grid of exactly 8 icon chips.
4. **Mood** — a wrapping grid of exactly 8 icon chips. Always shown.
5. **Pain** — a slider labelled "Pain level", 0–10, value displayed.
6. **Discharge** — 5 single-select chips: Dry, Sticky, Creamy, Watery, Egg-white.
7. **Temperature & ovulation tests** — a decimal numeric field for basal body
   temperature, then 3 single-select chips: Negative, Positive, Peak.
8. **Vulva & vagina** — a wrapping chip grid.
9. **Sex** — 3 chips, single-select.
10. **Sexual health** — a wrapping chip grid.
11. **Lifestyle** — 5 chips (caffeine, alcohol, exercise, smoking, meditation).
12. **Medications** — checkbox rows drawn from the user's own medication list.
13. **Urine**, **Digestion**, **Skin & hair** — three further chip-grid sections.
14. **Wellbeing** — five compact steppers in a column: "Water (glasses)" 0–12,
    "Sleep (hours)" 0–12h, "Energy" x/5, "Stress" x/5, "Sleep quality" x/5.
15. **Weight** — a decimal field with a kg/lb suffix. **No BMI, no category, no
    ideal range, no target.**
16. **Notes** — a multi-line text area, "Anything you want to remember…".

Sections 2, 3, 6, 8, 9, 10, 11, 12, 13, 14 and 15 are individually switchable in
Settings; Flow, Mood, Pain, Temperature & ovulation tests, and Notes are always
present and must never be drawn as toggleable.

Show a second variant with only Flow, Mood, Pain and Notes visible,
representing a user who has turned most categories off.

**S15 · Day entry bottom sheet.** The same form as S14 rendered as a modal bottom
sheet at ~90% height: 20dp top corners, drag handle, the date as a sheet title,
the scrolling form, and the full-width filled "Save" pinned in the sheet's own
bottom bar. Include the period check-in strip at the top of the sheet when
relevant: "Did your period start on this day?" with "Not yet" / "It ended" chips.

**S16 · Diary.** App bar "Diary" with a search icon that expands into an inline
search field. A list of cards, newest first: each shows the date, a small "Day 14"
cycle-day tag, and the note text at 2–3 lines. Empty state: a calm centred
illustration-free block, "Notes you write on a day show up here." **No ad banner.**

### Group E — Media & descriptions (5)

**S17 · Media timeline.** App bar "Photos & videos" with a back arrow and an
overflow menu. A 3-column grid of square thumbnails with 2dp gaps, a small play
badge on videos, and date group headers ("September 2026"). A floating action
button, bottom-right, with a camera-plus icon. Empty state: a centred block,
"Nothing here yet", one line of fine print — "Photos are uploaded to your account
and are **not** encrypted on our servers" — and a filled "Add a photo or video".

**S18 · Media viewer.** Full-bleed black background, the image centred, a
translucent top bar with back, date, and a delete icon, and a bottom action row
with two outlined actions: "Describe" (a sparkle icon) and "Delete". No auto-play,
no filters, no editing tools.

**S19 · Description consent sheet.** A modal bottom sheet. Title "Describe this
photo?". Body, in plain language: this sends the photo to Google's AI service, it
leaves your device and your account, it is off by default, and it can be turned on
for this account only. A small bulleted list of what the feature will and will not
do — "It describes what is visible. It will not name a condition, rate severity,
or suggest treatment." Two **stacked full-width** buttons: filled "Allow", then
outlined "Not now". Critically: the Allow button must be fully inside the 360dp
viewport — never place these two buttons side by side in a row.

**S20 · Description result sheet.** A modal bottom sheet at ~80% height. The
thumbnail is small and pinned top-left with the date. Below it a chat transcript:
the model's description as a plain-prose block, then alternating user question
bubbles (right, pink) and answer blocks (left, plain). A fixed caveat line under
**every** answer in small low-contrast type: "This describes what's visible. It
isn't a medical opinion." A bottom composer with a text field and a send icon,
plus a small counter "6 of 20 messages left today". Show a second variant where
the composer is disabled with the line "You've used today's 20 messages."

**S21 · Media upload failure.** Not a toast. An inline card in the timeline's
place: "That didn't upload", one line — "LunaTrack only saves photos once the
upload finishes, so nothing was kept" — and an outlined "Try again".

### Group F — Feature screens (5)

**S22 · Cycle overview.** Reached from Insights. App bar "Cycle overview". A
horizontal timeline bar for the current cycle segmented into the four phases in
their colours with a "today" marker, then a card per phase with its name, day
range, and a short plain description of what commonly happens.

**S23 · Medications.** App bar "Medications" with an add action. List rows: name,
dose, and a schedule subtitle, each with an overflow menu. Empty state, "Add the
medications you want to tick off each day." Add/edit is a bottom sheet with name,
dose and a simple schedule selector.

**S24 · Reminders.** App bar "Reminders". Three switch rows, each with a time
picker revealed when on: "Daily log reminder", "Period coming soon" (with a
"2 days before" stepper), and "Fertile window". A fine-print block at the bottom:
"Reminders are best-effort. Your phone's battery settings can delay or drop them."
Then a mock of the collapsed notification itself — showing only the app name and
a neutral title, **with no cycle content visible**, captioned "This is all that
shows on your lock screen."

**S25 · Customize tracking.** App bar "Customize tracking". A short explainer, then
a list of 14 switch rows: Physical symptoms, Emotional symptoms, Sexual activity,
Discharge, Vulva & vagina, Sexual health, Lifestyle, "Water, sleep, energy &
stress", Medications, Sleep quality, Urine, Digestion, Skin & hair, Weight. A
footer note: "Flow, pain, mood and notes are always available."

**S26 · Pregnancy.** App bar "Pregnancy". A large card with "Week 14" and a
trimester label, a slim segmented progress line across three trimesters, and an
estimated due date row. **No fetal-size comparisons, no fruit, no illustrations of
a fetus, no ads.** At the bottom, a plainly-worded, non-celebratory outlined
button "End pregnancy tracking" — its confirm dialog must be neutral in tone and
must not ask why.

### Group G — Account & commerce (4)

**S27 · Premium.** App bar–less, close X top-left. A calm hero: the ring mark, the
title "LunaTrack Premium", and the single benefit stated honestly — "Removes ads.
That's it. Every tracking feature is free and always will be." A price row, one
full-width filled "Buy once — $X", and a text button "Restore purchase". **No
countdown timer, no "limited offer", no crossed-out price, no feature-comparison
table implying tracking is gated.**

**S28 · Account section (in Settings).** The email row with a small verified tick,
"Last synced" subtitle, a "Sync now" row, "Sign out", and a destructive-styled
"Request account deletion" row.

**S29 · Deletion requested (pending).** A full screen shown ahead of everything
else. A centred card: "Account deletion requested", the plain explanation that
data on this device has already been erased, that the account's cloud copy is
scheduled for deletion, and the date. Then a full-width filled "Cancel deletion
request" and a text button "Sign out". Neutral in tone — this is reversible, so
nothing should feel final or punitive.

**S30 · Delete all my data (dialog).** An alert dialog, title "Delete everything
on this device?", body stating both halves plainly: everything on this phone is
erased, and the copy in your account is left alone — deleting that is a separate
request. Stacked actions, the destructive one clearly labelled "Delete from this
device".

### Group H — Persistent components (1 sheet)

**S31 · Component sheet.** One artboard laying out, at real size: the disclaimer
banner; the "Cloud sync unavailable" banner; the ad banner slot in position above
the nav bar; the info card in its three states (value / estimate-tagged /
suppressed-low-confidence); the selectable chip in default, selected and disabled;
the month ring at 3 sizes; and the bottom navigation bar with each of the 5 tabs
active. Provide light and dark side by side.

---

## 5. Reject-list — QA every Stitch output against this

- [ ] Does any screen contain the word **"safe"**?
- [ ] Any **percentage** attached to fertility, ovulation or conception?
- [ ] Any **countdown, arc, ring or bar** on the change timer?
- [ ] Does the timer show **remaining** time instead of elapsed?
- [ ] The words **overdue / urgent / danger / you're fine / no rush**?
- [ ] A **BMI**, weight category, ideal-range band or target weight?
- [ ] A **condition name, severity score or treatment suggestion** in the description sheet?
- [ ] An **ad banner** on Day log (S14/S15), Insights (S12), Diary (S16), Media, or Pregnancy?
- [ ] **Two filled buttons side by side** in any row?
- [ ] More than **5 bottom-nav destinations**?
- [ ] **Cycle content visible** in the notification mock or on the lock screen?
- [ ] **Streaks, badges, confetti, trophies** or a completion ring?
- [ ] Red used as an alert colour anywhere?
- [ ] Is the **disclaimer banner** present on Today, Forecast, Insights and Cycle overview?
- [ ] Are **light and dark** both produced?

---

## 6. Ruling — the two first-run states

**Ruled 2026-09-07 by the product owner, after a Feasibility check that changed
the question.** The brief originally posed this as one undesigned state. It is two,
and which one a user gets is already decided by the code.

`OnboardingScreen._finish()` does not merely save settings — when the user answers
"When did your last period start?", it **seeds a real `DailyLog`** at that date with
`flow: FlowIntensity.medium` ("Seed the last period so cycle stats have a starting
anchor"). So that user is *not* a zero-log user. `CycleCalculator` finds one cycle,
`lastStart != null`, and `PredictionService.predictFromLogs` takes its normal path:
`cycleDay`, `currentPhase` and `nextPeriodStart` are all genuinely computed.
Confidence, though, is derived from completed cycle *lengths*, of which there are
none — so it lands at the floor, and `fertilityBand` returns `none` for any
confidence of `none`/`low`.

**Ruling: show the estimate, tagged low-confidence** (variant 2 above). The number
is real, it is the user's own input, and labelling its weakness is more honest than
withholding it. The fertility band stays suppressed by the existing gate — this
ruling does not touch it, and must never be read as licence to soften it.

**But the "I'm not sure" branch is a different screen.** Step 1 of onboarding offers
a text button to skip the date. Take it and no log is seeded, `lastStart == null`,
and `predictFromLogs` returns its defaults-only result — `cycleDay: null`,
`currentPhase: unknown`, `nextPeriodStart: null`. There is no estimate to tag,
because there is no estimate. That user gets variant 3: honest emptiness and a
single call to action.

Designing only one of these would leave whichever user got the other looking at a
screen of broken cards.

---

## 7. Lessons from the generation runs (append to §5 when QA'ing)

Added 2026-09-07 after generating 29 of the 32 screens. These are the failures
that actually occurred, not hypotheticals.

### The ring is the hardest component to specify

- **"A ring of one arc segment per day" reads to the model as "a donut."** The
  first Today screen came back as a single solid dark ring. Say *how* to draw it:
  one `<circle>` per phase run, `stroke-dasharray` producing one dash per day,
  `stroke-dashoffset` positioning the run, later circles overpainting earlier
  ones. That phrasing produces the right thing first time.
- **Never write a day number without saying which kind it is.** The ring is
  indexed by DAY OF MONTH; "Day 19" in its centre is the CYCLE day. A prompt
  saying "day 19 (today)" put the dotted marker 12 days off. Write
  "**7 September**, which is cycle day 19".

### Check the scenario before you check the pixels

The screen that survived the whole first QA pass was still telling two stories:
the ring painted a period across 1–5 September while every card said *Day 19,
luteal, next period in 9 days*. No guardrail grep catches that, because every
individual string is fine.

**Before generating any screen that shows cycle state, write the scenario down
once and derive everything from it** — last period start, today's date, cycle
length — then check each element against it. For this set: cycle day 1 =
20 August, average cycle 28. Run it through the REAL constants in
`prediction_service.dart` (`_lutealDays = 14`, `_fertilePreOvulation = 5`,
`_fertilePostOvulation = 1`) rather than estimating:

> ovulation = 20 Aug + (28 - 14) = **3 Sep** · fertile = **29 Aug - 4 Sep**
> next period = **17 Sep** · today 7 Sep = **cycle day 19**, luteal

The same slip put **"Fertile window: Higher" on a luteal day** — a false fertile
signal, produced by this brief itself (§4 S09 item 5, now corrected). The band must
be derived from the cycle day, never picked to make the component look good. And
the honest answer turned out to be neither "Higher" nor "Lower": on day 19 the
card shows a rolled-forward **date range with no band at all**. When a question is
framed as a binary, check the code before answering it — the code had a third
option.

### `stroke-dasharray` repeats around the WHOLE circle

The single worst rendering bug in the set, invisible to every text-based QA check
because it is not text. Eight `<circle>` elements each painting one run of days
with `stroke-dasharray="7 2.21"` do NOT paint one run each — a dash pattern tiles
the entire circumference, so every circle painted the whole ring and the last one
drawn won everywhere.

**Specify the ring with `pathLength="30"`.** That normalises the circle to 30
units, so 1 unit = 1 day and a run of N days starting on day D is exactly
`stroke-dasharray="N (30-N)"` with `stroke-dashoffset="-(D-1)"`. The gap
explicitly spans the rest of the ring, so nothing can tile. Per-day tick
separators are then a single extra circle at `"0.09 0.91"` — that one is *meant*
to repeat, because its pattern sums to exactly one day. A dotted "today" segment
uses dash values summing to exactly 30, so the pattern covers the ring once.

**And never `stroke-linecap="round"` on the dotted day.** A round cap adds half the
stroke width to EACH end of every dash — with `stroke-width="10"` that is 5 user
units, and since 1 pathLength unit here is only ~9.2 user units, each cap adds
**0.54 units** to a 0.22-unit dot. The three dots each more than tripled in width
and fused into one solid blob wider than a whole day. Cap extension is measured in
**user units, not pathLength units**: `pathLength` rescales the dash array but not
the stroke geometry, and the two live in different coordinate spaces. Use butt caps
and size the dots so 3 dots + 2 gaps fit inside one unit.

A knock-on: whatever colour the "Estimate" legend key shows must actually be
painted somewhere. The design system reserves lavender `#B0A8C0` for ALL estimated
states, so the predicted next-period run is lavender, not rose — and a legend
entry appears only when a matching segment exists.

### Prompt phrasings that worked

- For stacked buttons, one instruction is not enough. What worked:
  "each on its OWN LINE, each spanning the FULL WIDTH", then a separate
  ALL-CAPS paragraph repeating it, then the reason ("this has caused a real
  shipped bug"). The consent sheet came back correct on the first attempt.
- For a two-sided consent choice, say what must NOT happen: no "Recommended"
  badge, no preselection, no size or saturation difference, no greying out.
- Stating the *reason* for a prohibition raises compliance markedly. "No fetal
  size comparisons … because this screen must be survivable by someone who has
  had a loss" produced a clean screen; the bare list of banned nouns did not
  always.

### Stitch API behaviour

- `generate_screen_from_text` stops responding after roughly 28 calls in a
  session (network-level failure, not an error message). `edit_screens` and
  `get_screen` keep working — it is a per-endpoint limit. Budget for it: batch
  4 generations at a time, not 6, and expect to finish across two sessions.
- `download_assets` reports success and writes nothing. `list_screens` returns
  `{}`. `get_screen` is the only reliable path to a screen's file URL, and its
  response is compact.
- A file URL is a frozen snapshot: DOM-operation edits do not mint a new one.
  Apply the same edit locally, or the repo copy silently lags.

- **One `generate_screen_from_text` call at a time.** Two in parallel both fail
  with `fetch failed`, and so does a call fired immediately after a success. What
  looked like a hard quota ("dead after ~28 calls") was largely this — retrying a
  failure instantly is the one thing guaranteed not to work. Do other work
  between calls and they keep landing.
- **The two models fail differently on a big prompt, and Flash fails silently.**
  An 8-group component sheet timed out on `GEMINI_3_1_PRO` four times running.
  `GEMINI_3_FLASH` returned it — having dropped two whole groups and faked the
  month ring, while its prose summary described a complete sheet. Count the
  groups in the output; do not read the summary.
- **`deviceType` in the response describes the screenshot canvas, not the layout.**
  A sheet came back `DESKTOP` / `width: 2560` whose markup was a single
  `max-w-lg` column. Judge the HTML.
