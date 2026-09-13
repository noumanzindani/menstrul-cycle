---
title: How Period Predictions Actually Work
description: Period and ovulation predictions project your own typed average forward. Here is the exact arithmetic behind them, and why real cycles drift from it.
author: LunaTrack
reviewedBy: Not medically reviewed
datePublished: 2026-09-13
dateModified: 2026-09-13
sources:
  - title: NHS — Periods
    url: https://www.nhs.uk/conditions/periods/
  - title: Cleveland Clinic — Menstrual Cycle
    url: https://my.clevelandclinic.org/health/articles/10132-menstrual-cycle
---

A period tracker's calendar looks confident. It puts a red dot on a specific future
date and calls it your "next period," and it puts another dot a couple of weeks
earlier and calls it "ovulation." Confidence is the wrong impression to leave. Every
one of those dates is a projection built from a small number you typed in, or a
short run of your own history, run through the same fixed arithmetic every time. It
is a reasonable estimate, not a measurement of anything that has not happened yet.
This article walks through exactly what that arithmetic does, why it drifts away
from your real cycle over time, and what actually makes a prediction more or less
trustworthy.

## What a prediction is actually built from

Strip away the calendar UI and a period prediction is a small piece of arithmetic
applied to two numbers: the start date of your last period, and an average cycle
length. The calculator adds the cycle length to the last start date to get the next
one, then repeats that addition to project further periods after that. A period
window is simply that start date plus your typical period length, minus a day.
Nothing about symptoms, mood, temperature, or how you are feeling factors into
where that dot lands — the projection only ever knows the one number you gave it.

That is true whether the number comes from a single guess typed into a calculator
or from months of your own logged history. The [period
calculator](/tools/period-calculator) on this site asks you directly for an
average cycle length, because it has nothing else to go on in a single visit. An
app that has been logging your actual period start dates for a few months can
compute that average itself instead of asking you to guess it — but it is still
computing an average and still projecting it forward with the same addition. More
history changes how good the input number is; it does not change the shape of the
method.

This matters because it sets a hard ceiling on what a prediction can promise. The
arithmetic assumes your next cycle will be exactly as long as your typical one.
Real cycles are not that disciplined, which is the whole subject of the next
section — but first it is worth being precise about ovulation, because the method
behind it is less obvious than the period date.

## How ovulation and the fertile window are estimated

It would seem natural to estimate ovulation by counting forward from the start of
a period, the same way period dates are projected. That is not how it is done here,
and it is not how most cycle math is done, because it would be wrong more often.
The reason is asymmetry between the two halves of a cycle. The first half — from
the start of a period to ovulation, called the follicular phase — is the part that
stretches or shrinks when a cycle runs longer or shorter than usual. The second
half — from ovulation to the next period, the luteal phase — stays much closer to a
fixed length in most cycles, commonly cited as being close to fourteen days.
Cleveland Clinic's overview of the menstrual cycle describes this same pattern:
cycle-length variation is concentrated in the run-up to ovulation, not in the
stretch that follows it.

Because the luteal phase is the more stable half, the reliable way to locate
ovulation is to count backward from the next period rather than forward from the
last one. The method used here does exactly that: it takes the projected date of
your next period and subtracts a fixed fourteen days to land on an estimated
ovulation day. The fertile window is then built around that single day — five days
before it, to account for how many days sperm can remain viable in the reproductive
tract, plus one day after it, to account for roughly how long a released egg can
still be fertilized. That five-days-before, one-day-after window is what the
[ovulation calculator](/tools/ovulation-calculator) on this site shows you, and it
is the same arithmetic behind any ovulation date an app shows you unless it has
told you otherwise.

Notice what this means in practice: an ovulation estimate is only as good as the
period prediction it is counted backward from, plus one more assumption — that your
luteal phase actually is close to fourteen days, which is a population average, not
a guarantee about your own body. Two layers of averaging sit underneath a single
dot on a calendar. Neither the app nor a calculator can tell you that ovulation
happened; both are telling you where it is expected to have happened, assuming two
separate averages both held for this particular cycle.

## Why predictions drift

If a cycle-length average were exactly the same every cycle, projecting it forward
would work indefinitely and a tracker's accuracy would never fade. Cycles are not
that consistent. The NHS describes a normal cycle length as anywhere from
twenty-four to thirty-eight days, and describes it as normal for that length to
vary somewhat from one cycle to the next even in someone without any underlying
condition. A projection built on a single fixed average cannot represent that
variation — it can only offer the average itself, over and over, as its best guess
for a cycle that in reality wobbles around that average rather than repeating it.

Several ordinary things push a cycle away from its own recent average: illness,
travel and jet lag, a change in sleep or stress, significant weight change,
starting or stopping hormonal contraception, and the years leading into
perimenopause, when cycle length often becomes noticeably less predictable before
periods stop altogether. None of these show up anywhere in the arithmetic. A
prediction has no way to know that you were unwell last week, so it will keep
projecting the same old average until enough real period dates have been logged to
pull that average toward what is actually happening now. This is the mechanical
reason a tracker's estimate can feel accurate for months and then suddenly miss by
several days: nothing about the method changed, but your cycle did, and the
averaging is always looking slightly backward.

It is also worth being honest about a different kind of drift: rounding. An
average cycle length is rarely a whole number — thirty and a half days is a
perfectly normal average across a handful of real cycles — and any calculator has
to decide how to handle the fraction. Small rounding choices compound slightly
over several projected cycles in a row, which is one more reason the third or
fourth projected period on a calendar deserves less confidence than the very next
one.

## What makes a prediction better or worse

Two things move a prediction from "rough guess" toward "reasonably useful
estimate," and both are about the input, never about the arithmetic, which never
changes.

The first is how much real history is behind the average. A single guessed number
typed into a calculator carries no information about how much your own cycles
actually vary — it is one data point standing in for a pattern. An average computed
from several of your own logged period start dates is a genuine measurement of your
recent pattern, and it improves every time a new period is logged, because the
average simply updates to include it. This is the practical difference between
typing a number into a one-off calculator and letting an app accumulate your
history over time: the arithmetic is identical, but the number it is fed keeps
getting better.

The second is how regular that history actually is. If your last several cycles
have landed within a few days of each other, the spread between your shortest and
longest recent cycle is small, and a single average genuinely represents most of
what is going on — the projection and the next real period are likely to land
close together. If your recent cycles have varied by a couple of weeks or more,
that same average is doing much more work smoothing over real variation, and any
single projected date should be read as the center of a fairly wide range rather
than a firm appointment. The [cycle-length calculator](/tools/cycle-length-calculator)
on this site exists specifically to surface that spread: enter a handful of recent
start dates and it reports your average alongside your shortest and longest cycle,
so you can see for yourself whether your own pattern is tight or wide before
trusting a projection built on top of it.

Put simply: a prediction is a photograph of your recent average, not a forecast of
your next cycle's actual biology. The more consistent your recent cycles have been,
and the more of them the average is drawn from, the closer that photograph tends to
resemble what happens next. Neither condition can ever make it a certainty.

## What a prediction is not

A predicted date is not a diagnosis, and it does not know anything about your
health beyond the dates it was given. An estimated ovulation day and fertile window
are not a method of contraception — they describe where ovulation is statistically
likely to fall for an average cycle, not a guarantee about a specific one, and
relying on them to avoid or plan a pregnancy carries real risk given everything
above about drift and averaging. If your own cycles keep landing well outside what
a prediction expects, that pattern itself is worth mentioning to a doctor — not
because the calculator was wrong, but because a cycle that will not settle into any
stable average is a different question than the arithmetic here is built to answer.

LunaTrack's own [prediction features](/features) work on exactly the method
described above — a typed or logged average projected forward, ovulation counted
back from the next projected period assuming a fourteen-day luteal phase — because
that is the standard, defensible way to do calendar-based estimation, not because
it is more clever than that. If you are trying to decide whether an app's
predictions, or any tracker's, are worth trusting with sensitive health
information in the first place, the data handling behind the prediction matters
just as much as the arithmetic — see [what to check in a period tracker's privacy
policy](/articles/what-to-check-in-a-period-tracker-privacy-policy) for a checklist
you can apply to any app, including this one.

## Try the arithmetic yourself

Every calculator referenced above runs the same maths described here, in your own
browser, using only the dates you type in. The [period
calculator](/tools/period-calculator) projects your next few periods; the
[ovulation calculator](/tools/ovulation-calculator) counts backward from that
projection to estimate a fertile window; the [cycle-length
calculator](/tools/cycle-length-calculator) shows you how much your own recent
cycles actually vary. Trying more than one against your own recent dates is a fast
way to get a feel for how wide a "reasonable estimate" really is for your own
pattern, before treating any single date on a calendar as more certain than it is.
