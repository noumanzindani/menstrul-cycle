import { describe, it, expect } from 'vitest'
import {
  HCG_LAG_DAYS, testTiming, implantationWindow, weeksToMonths,
  ivfDueDate, IVF_OFFSET, IVF_SELECTABLE_AGES,
  scanDueDate, redatingThresholdDays,
} from './pregnancy.ts'
import { CONCEPTION_OFFSET_DAYS, TERM_DAY, wdToDays } from './gestation.ts'
import { dayNum } from './days.ts'

const ALL_CYCLES = Array.from({ length: 25 }, (_, i) => 21 + i) // 21..45

describe('testTiming', () => {
  it('holds every stated invariant across the whole cycle range', () => {
    for (const c of ALL_CYCLES) {
      const t = testTiming(0, c)
      expect(t.ovulation).toBe(t.periodDue - CONCEPTION_OFFSET_DAYS)
      expect(t.implantEarliest).toBe(t.ovulation + 6)
      expect(t.implantLatest).toBe(t.ovulation + 12)
      expect(t.timingReliable).toBe(t.periodDue + 7)
      // Each test date is pinned to the derivation the page describes, NOT to the
      // other one. With a 3-day lag `earliestSuggestedTest` happens to land on
      // `implantLatest`; asserting THAT equality would have frozen a zero-day
      // detection lag into the suite while the page's own margin paragraph said a
      // test can turn positive days after the last possible implantation day.
      const commonMid = (t.implantCommonStart + t.implantCommonEnd) / 2
      expect(t.earliestSuggestedTest).toBe(commonMid + HCG_LAG_DAYS)
      expect(t.latestDetectable).toBe(t.implantLatest + HCG_LAG_DAYS)
      // The two the page's prose states as offsets from the period being due.
      expect(t.earliestSuggestedTest).toBe(t.periodDue - 2)
      expect(t.latestDetectable).toBe(t.periodDue + 1)
    }
  })

  it('leaves room for hCG to rise between the last implantation day and a reliable negative', () => {
    // The margin the page promises in prose. If HCG_LAG_DAYS ever changed, this is
    // the assertion that should move — not the one tying two outputs together.
    const t = testTiming(0, 28)
    expect(t.latestDetectable - t.implantLatest).toBe(HCG_LAG_DAYS)
    expect(t.timingReliable).toBeGreaterThan(t.latestDetectable)
  })

  it('orders every milestone, so a timeline can never render backwards', () => {
    for (const c of ALL_CYCLES) {
      const t = testTiming(0, c)
      const seq = [t.ovulation, t.implantEarliest, t.implantCommonStart,
        t.implantCommonEnd, t.implantLatest, t.earliestSuggestedTest, t.periodDue,
        t.latestDetectable, t.timingReliable]
      expect([...seq].sort((a, b) => a - b)).toEqual(seq)
    }
  })

  it('works a concrete example', () => {
    const lmp = dayNum('2026-09-01')
    const t = testTiming(lmp, 28)
    expect(t.periodDue - lmp).toBe(28)
    expect(t.ovulation - lmp).toBe(14)
    expect(t.earliestSuggestedTest - lmp).toBe(26)
    expect(t.latestDetectable - lmp).toBe(29)
  })

  it('refuses a cycle length outside 21 to 45', () => {
    expect(() => testTiming(0, 20)).toThrow(RangeError)
    expect(() => testTiming(0, 46)).toThrow(RangeError)
    expect(() => testTiming(0, 28.5)).toThrow(RangeError)
  })
})

describe('implantationWindow', () => {
  it('places the window 6 to 12 days after ovulation, common 8 to 10', () => {
    const w = implantationWindow(0, 28)
    expect(w.ovulation).toBe(14)
    expect(w.windowStart - w.ovulation).toBe(6)
    expect(w.windowEnd - w.ovulation).toBe(12)
    expect(w.commonStart - w.ovulation).toBe(8)
    expect(w.commonEnd - w.ovulation).toBe(10)
  })

  it('keeps the common window inside the full window for every input', () => {
    for (const c of ALL_CYCLES) {
      for (let l = 10; l <= 16; l += 1) {
        if (l >= c) continue
        const w = implantationWindow(0, c, l)
        expect(w.commonStart).toBeGreaterThanOrEqual(w.windowStart)
        expect(w.commonEnd).toBeLessThanOrEqual(w.windowEnd)
      }
    }
  })

  it('moves ovulation when the luteal length is given', () => {
    expect(implantationWindow(0, 28, 12).ovulation).toBe(16)
    expect(implantationWindow(0, 28, 16).ovulation).toBe(12)
  })

  it('refuses a luteal phase that is not shorter than the cycle', () => {
    expect(() => implantationWindow(0, 21, 16)).not.toThrow()
    expect(() => implantationWindow(0, 14, 14)).toThrow(RangeError)
  })

  it('refuses a luteal length outside 10 to 16', () => {
    expect(() => implantationWindow(0, 28, 9)).toThrow(RangeError)
    expect(() => implantationWindow(0, 28, 17)).toThrow(RangeError)
  })
})

describe('weeksToMonths', () => {
  it('adds 14 days when the figure is counted from conception', () => {
    expect(weeksToMonths(8, 0, 'lmp').gestationalDays).toBe(56)
    expect(weeksToMonths(8, 0, 'conception').gestationalDays).toBe(70)
  })

  it('reports nine months, never ten', () => {
    const months = new Set<number>()
    for (let w = 0; w <= 39; w += 1) {
      for (let d = 0; d <= 6; d += 1) {
        const m = weeksToMonths(w, d, 'lmp').month
        if (m !== null) months.add(m)
      }
    }
    expect([...months].sort((a, b) => a - b)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9])
  })

  it('returns a null month past term instead of inventing one', () => {
    const r = weeksToMonths(40, 0, 'lmp')
    expect(r.postTerm).toBe(true)
    expect(r.month).toBeNull()
    expect(r.dayOfMonth).toBeNull()
    expect(weeksToMonths(39, 6, 'lmp').month).toBe(9)
  })

  it('uses the app trimester boundaries', () => {
    expect(weeksToMonths(13, 6, 'lmp').trimester).toBe(1) // day 97
    expect(weeksToMonths(14, 0, 'lmp').trimester).toBe(2) // day 98
    expect(weeksToMonths(27, 6, 'lmp').trimester).toBe(2) // day 195
    expect(weeksToMonths(28, 0, 'lmp').trimester).toBe(3) // day 196
  })

  it('never reports seven days', () => {
    for (let w = 0; w <= 45; w += 1) {
      for (let d = 0; d <= 6; d += 1) {
        if (wdToDays(w, d) > 321) continue
        expect(weeksToMonths(w, d, 'lmp').days).toBeLessThan(7)
      }
    }
  })

  it('refuses seven days, a fractional week, and an unknown basis', () => {
    expect(() => weeksToMonths(8, 7, 'lmp')).toThrow(RangeError)
    expect(() => weeksToMonths(8.5, 0, 'lmp')).toThrow(RangeError)
    expect(() => weeksToMonths(8, 0, 'guess' as never)).toThrow(RangeError)
  })

  it('refuses a figure past its stated ceiling, in both bases', () => {
    expect(() => weeksToMonths(46, 0, 'lmp')).toThrow(RangeError)
    expect(() => weeksToMonths(44, 0, 'conception')).toThrow(/43 weeks 6 days/)
  })

  it('never emits a negative or NaN month field, at or past term', () => {
    // The coercion this guards: month - 1 === -1, MONTH_START_DAYS[-1] is
    // undefined, and the page prints "-1 months complete" with a NaN day of the
    // month. Reachable from an ordinary 40w0d entry, so it is not an edge case.
    for (let w = 40; w <= 45; w += 1) {
      const r = weeksToMonths(w, 0, 'lmp')
      expect(r.postTerm).toBe(true)
      expect(r.monthsComplete).toBe(9)
      for (const v of [r.month, r.monthStartDay, r.monthEndDay, r.monthWeeks,
        r.dayOfMonth, r.weekOfMonth, r.daysToNextMonth, r.daysToTerm]) {
        expect(v).toBeNull()
      }
    }
  })

  it('emits no term countdown past term, and a positive one before it', () => {
    expect(weeksToMonths(39, 6, 'lmp').daysToTerm).toBe(1)
    expect(weeksToMonths(40, 0, 'lmp').daysToTerm).toBeNull()
    for (let d = 0; d < 280; d += 1) {
      expect(weeksToMonths(Math.floor(d / 7), d % 7, 'lmp').daysToTerm).toBeGreaterThan(0)
    }
  })

  it('counts months complete as one less than the month you are in', () => {
    expect(weeksToMonths(0, 0, 'lmp').monthsComplete).toBe(0)
    expect(weeksToMonths(3, 6, 'lmp').monthsComplete).toBe(0) // day 27, still month 1
    expect(weeksToMonths(4, 0, 'lmp').monthsComplete).toBe(1) // day 28, month 2
  })

  it('gives every month four or five whole weeks, summing to term', () => {
    let total = 0
    const seen = new Map<number, number>()
    for (let d = 0; d < 280; d += 1) {
      const r = weeksToMonths(Math.floor(d / 7), d % 7, 'lmp')
      expect([4, 5]).toContain(r.monthWeeks)
      seen.set(r.month!, r.monthWeeks!)
    }
    for (const weeks of seen.values()) total += weeks
    expect(seen.size).toBe(9)
    expect(total * 7).toBe(280)
  })

  it('keeps the day of the month inside the month it reports', () => {
    for (let d = 0; d < 280; d += 1) {
      const r = weeksToMonths(Math.floor(d / 7), d % 7, 'lmp')
      expect(r.dayOfMonth).toBe(d - r.monthStartDay! + 1)
      expect(r.dayOfMonth).toBeGreaterThanOrEqual(1)
      expect(r.dayOfMonth).toBeLessThanOrEqual(r.monthEndDay! - r.monthStartDay! + 1)
      expect(r.daysToNextMonth).toBe(r.monthEndDay! + 1 - d)
      expect(r.weekOfMonth).toBeGreaterThanOrEqual(1)
      expect(r.weekOfMonth).toBeLessThanOrEqual(r.monthWeeks!)
    }
  })

  it('counts down to the next trimester, and not past the third', () => {
    expect(weeksToMonths(0, 0, 'lmp').daysToNextTrimester).toBe(98)
    expect(weeksToMonths(13, 6, 'lmp').daysToNextTrimester).toBe(1)
    expect(weeksToMonths(14, 0, 'lmp').daysToNextTrimester).toBe(98)
    expect(weeksToMonths(27, 6, 'lmp').daysToNextTrimester).toBe(1)
    expect(weeksToMonths(28, 0, 'lmp').daysToNextTrimester).toBeNull()
  })

  it('withholds a conception figure before conception could have happened', () => {
    expect(weeksToMonths(1, 6, 'lmp').conceptionWeeks).toBeNull() // day 13
    expect(weeksToMonths(1, 6, 'lmp').conceptionDays).toBeNull()
    expect(weeksToMonths(2, 0, 'lmp').conceptionWeeks).toBe(0)    // day 14
    expect(weeksToMonths(2, 0, 'lmp').conceptionDays).toBe(0)
    expect(weeksToMonths(10, 0, 'lmp').conceptionWeeks).toBe(8)
  })

  it('restates elapsed time without claiming it is the month you are in', () => {
    const r = weeksToMonths(40, 0, 'lmp')
    // The figure the page's own rationale rejects, printed only as elapsed time.
    expect(r.fourWeekMonths).toBe(10)
    expect(r.averageCalendarMonths).toBe(9.2)
    expect(r.month).toBeNull()
  })
})

describe('ivfDueDate', () => {
  it('agrees with itself three ways, for every selectable embryo age', () => {
    const t = dayNum('2026-09-14')
    for (const age of IVF_SELECTABLE_AGES) {
      const r = ivfDueDate(t, age)
      expect(r.dueDate).toBe(t + IVF_OFFSET[age])
      expect(r.dueDate).toBe(r.gestationalAnchor + TERM_DAY)
      expect(r.dueDate).toBe(r.conceptionEquivalent + 266)
    }
  })

  it('derives every offset from 266 minus the embryo age', () => {
    for (const [age, offset] of Object.entries(IVF_OFFSET)) {
      expect(offset).toBe(266 - Number(age))
    }
  })

  it('puts a day-5 transfer two days ahead of a day-3 one', () => {
    const t = dayNum('2026-09-14')
    expect(ivfDueDate(t, 3).dueDate - ivfDueDate(t, 5).dueDate).toBe(2)
  })

  it('reports gestational age only when a date is supplied', () => {
    const t = dayNum('2026-09-14')
    expect(ivfDueDate(t, 5).gestationalDaysAt).toBeNull()
    // On transfer day itself a day-5 embryo is 19 days gestational (14 + 5).
    expect(ivfDueDate(t, 5, t).gestationalDaysAt).toBe(19)
  })

  it('refuses an embryo age the page does not offer', () => {
    expect(() => ivfDueDate(0, 4)).toThrow(RangeError)
    expect(() => ivfDueDate(0, 0)).toThrow(RangeError)
  })

  it('refuses a string embryo age, the concatenation bug, rather than coercing it', () => {
    // With `embryoAge` as a string, `transferDay - (embryoAge + 14)` concatenates:
    // 20710 - ('5' + 14) === 20710 - 514. The due date still looks right, because
    // object keys are strings and `-` coerces, while the anchor and every date
    // derived from it are 500 days out. The allow-list is what makes that
    // impossible, so it must reject the string form too.
    expect(() => ivfDueDate(20710, '5' as never)).toThrow(RangeError)
  })

  it('echoes the age and offset back, so nothing downstream re-reads the form', () => {
    const r = ivfDueDate(dayNum('2026-09-14'), 5)
    expect(r.embryoAge).toBe(5)
    expect(r.offsetDays).toBe(261)
    expect(r.dueDate).toBe(r.transferDay + r.offsetDays)
    expect(r.gestationalAnchor).toBe(r.conceptionEquivalent - 14)
  })

  it('reports the as-of day it was given, and refuses one before the transfer', () => {
    const t = dayNum('2026-09-14')
    expect(ivfDueDate(t, 5).asOfDay).toBeNull()
    expect(ivfDueDate(t, 5, t + 30).asOfDay).toBe(t + 30)
    expect(() => ivfDueDate(t, 5, t - 1)).toThrow(/cannot be before the transfer/)
  })
})

describe('redatingThresholdDays', () => {
  it('widens as the pregnancy advances', () => {
    expect(redatingThresholdDays(62)).toBe(5)
    expect(redatingThresholdDays(63)).toBe(7)
    expect(redatingThresholdDays(111)).toBe(7)
    expect(redatingThresholdDays(112)).toBe(10)
    expect(redatingThresholdDays(153)).toBe(10)
    expect(redatingThresholdDays(154)).toBe(14)
    expect(redatingThresholdDays(195)).toBe(14)
    expect(redatingThresholdDays(196)).toBe(21)
  })

  it('never narrows as gestation increases', () => {
    let prev = 0
    for (let g = 0; g <= 300; g += 1) {
      const t = redatingThresholdDays(g)
      expect(t).toBeGreaterThanOrEqual(prev)
      prev = t
    }
  })
})

describe('scanDueDate', () => {
  const s = dayNum('2026-09-14')
  const at = (gaWeeks: number, gaDays: number, extra = {}) =>
    scanDueDate({ scanDay: s, gaWeeks, gaDays, ...extra })

  it('anchors the pregnancy from the scan and dates term 280 days on', () => {
    const r = at(12, 0)
    expect(r.gestationalAge).toBe(84)
    expect(r.gestationalAnchor).toBe(s - 84)
    expect(r.dueDate).toBe(r.gestationalAnchor + TERM_DAY)
    expect(r.conceptionEquivalent).toBe(r.gestationalAnchor + CONCEPTION_OFFSET_DAYS)
  })

  it('omits the comparison when no last period is given', () => {
    expect(at(12, 0).comparison).toBeNull()
  })

  it('selects the threshold row by the LAST PERIOD age, not the scan age', () => {
    // The blocker, with the inputs that expose it. Scan says 8w2d (58 days); the
    // last period implies 9w1d (64 days) at the scan, so the gap is 6 days.
    // Indexed by the scan's own age the threshold is 5 and the page would say
    // redate; indexed by the last period's it is 7 and the page says keep.
    // Opposite recommendations from identical inputs, so the choice matters.
    const r = at(8, 2, { lmpDay: s - 64 })
    expect(r.comparison!.gaByLmp).toBe(64)
    expect(r.comparison!.thresholdDays).toBe(7)
    expect(Math.abs(r.comparison!.differenceDays)).toBe(6)
    expect(r.comparison!.supportsRedating).toBe(false)
    // Indexing the other way would have returned 5, which is the bug.
    expect(redatingThresholdDays(58)).toBe(5)
  })

  it('prints the age that selected the row, so the choice is auditable', () => {
    expect(at(18, 3, { lmpDay: s - wdToDays(18, 3) }).comparison!.gaByLmp).toBe(wdToDays(18, 3))
  })

  it('keeps the last-period date when the gap exactly equals the threshold', () => {
    const r = at(8, 0, { lmpDay: s - wdToDays(8, 5) })
    expect(r.comparison!.thresholdDays).toBe(5)
    expect(Math.abs(r.comparison!.differenceDays)).toBe(5)
    expect(r.comparison!.supportsRedating).toBe(false) // strict: not ">"
    expect(r.comparison!.atThreshold).toBe(true)
  })

  it('supports redating one day past the threshold', () => {
    const r = at(8, 0, { lmpDay: s - wdToDays(8, 6) })
    expect(Math.abs(r.comparison!.differenceDays)).toBe(6)
    expect(r.comparison!.supportsRedating).toBe(true)
    expect(r.comparison!.atThreshold).toBe(false)
  })

  it('keeps the difference consistent with both due dates', () => {
    const r = at(9, 0, { lmpDay: s - wdToDays(10, 2) })
    expect(r.comparison!.differenceDays).toBe(r.dueDate - r.comparison!.lmpDueDate)
    expect(r.comparison!.differenceDays).toBe(r.comparison!.gaByLmp - r.gestationalAge)
  })

  it('answers nothing at all once the last period implies 28 weeks or more', () => {
    // An estimate from a first-trimester scan is essentially never redated by a
    // third-trimester one. Running the day-gap comparison there inverts the
    // guidance it claims to apply, so the page must not answer.
    const r = scanDueDate({ scanDay: s, gaWeeks: 30, gaDays: 0, lmpDay: s - wdToDays(33, 0) })
    expect(r.comparison!.suppressed).toBe('late-scan')
    expect(r.comparison!.supportsRedating).toBeNull()
    // The dates and the gap are still reported; only the recommendation is
    // withheld. The sign is positive: the scan reads 30w0d where the last period
    // implies 33w0d, so the scan puts the anchor 21 days LATER and the due date
    // with it.
    expect(r.comparison!.differenceDays).toBe(21)
    expect(r.comparison!.thresholdDays).toBe(21)
  })

  it('answers nothing when the reader says an earlier scan set their dates', () => {
    const r = at(8, 0, { lmpDay: s - wdToDays(12, 0), datesAlreadySet: true })
    expect(r.comparison!.suppressed).toBe('dates-already-set')
    expect(r.comparison!.supportsRedating).toBeNull()
  })

  it('flags a borderline threshold row only when the two ages fall in different rows', () => {
    // 62/63 is a row boundary; 97/98 carries the same threshold on both sides.
    expect(at(8, 6, { lmpDay: s - 63 }).comparison!.nearThreshold).toBe(true)
    expect(at(13, 6, { lmpDay: s - 98 }).comparison!.nearThreshold).toBe(false)
  })

  it('counts to the due date from the as-of day, and past it as a negative', () => {
    const r = at(12, 0, { asOfDay: s + 10 })
    expect(r.gestationalDaysAt).toBe(94)
    expect(r.daysToDueDate).toBe(r.dueDate - (s + 10))
    const past = at(12, 0, { asOfDay: s + 210 })
    expect(past.daysToDueDate).toBeLessThan(0)
  })

  it('lets the as-of day sit before the scan, which is what backdating is for', () => {
    const r = at(12, 0, { asOfDay: s - 20 })
    expect(r.gestationalDaysAt).toBe(64)
    expect(r.daysToDueDate).toBeGreaterThan(0)
  })

  it('stops counting down past 308 days from the anchor', () => {
    const anchor = s - 84
    expect(at(12, 0, { asOfDay: anchor + 308 }).daysToDueDate).not.toBeNull()
    expect(at(12, 0, { asOfDay: anchor + 309 }).daysToDueDate).toBeNull()
  })

  it('refuses an out-of-range gestational age, and 42w6d with it', () => {
    expect(() => at(3, 0)).toThrow(RangeError)
    expect(() => at(43, 0)).toThrow(RangeError)
    expect(() => at(12, 7)).toThrow(RangeError)
    // 4-42 weeks with 0-6 days admits 42w6d; the total is what is capped.
    expect(() => at(42, 0)).not.toThrow()
    expect(() => at(42, 1)).toThrow(/42 weeks 0 days/)
  })

  it('refuses a last period that cannot precede the scan, as one rule', () => {
    expect(() => at(12, 0, { lmpDay: s })).toThrow(/before the scan/)
    expect(() => at(12, 0, { lmpDay: s + 1 })).toThrow(/before the scan/)
  })

  it('refuses a last-period date too close to or too far from the scan', () => {
    expect(() => at(12, 0, { lmpDay: s - 27 })).toThrow(/four weeks/)
    expect(() => at(12, 0, { lmpDay: s - 28 })).not.toThrow()
    expect(() => at(12, 0, { lmpDay: s - 320 })).not.toThrow()
    expect(() => at(12, 0, { lmpDay: s - 321 })).toThrow(/check the year/)
  })

  it('refuses an as-of date nowhere near the pregnancy it describes', () => {
    const anchor = s - 84
    expect(() => at(12, 0, { asOfDay: anchor - 31 })).toThrow(RangeError)
    expect(() => at(12, 0, { asOfDay: anchor + 401 })).toThrow(RangeError)
  })
})
