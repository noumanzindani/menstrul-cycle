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
      expect(t.earliestUsefulTest).toBe(t.periodDue - 2)
      expect(t.timingReliable).toBe(t.periodDue + 7)
      expect(t.timingReliable - t.earliestUsefulTest).toBe(9)
      expect(t.implantLatest + HCG_LAG_DAYS).toBe(t.periodDue + 1)
    }
  })

  it('orders every milestone, so a timeline can never render backwards', () => {
    for (const c of ALL_CYCLES) {
      const t = testTiming(0, c)
      const seq = [t.ovulation, t.implantEarliest, t.implantCommonStart,
        t.implantCommonEnd, t.implantLatest, t.earliestUsefulTest, t.timingReliable]
      expect([...seq].sort((a, b) => a - b)).toEqual(seq)
    }
  })

  it('works a concrete example', () => {
    const lmp = dayNum('2026-09-01')
    const t = testTiming(lmp, 28)
    expect(t.periodDue - lmp).toBe(28)
    expect(t.ovulation - lmp).toBe(14)
    expect(t.earliestUsefulTest - lmp).toBe(26)
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
  it('anchors the pregnancy from the scan and dates term 280 days on', () => {
    const s = dayNum('2026-09-14')
    const r = scanDueDate(s, 12, 0)
    expect(r.gestationalAnchor).toBe(s - 84)
    expect(r.dueDate).toBe(r.gestationalAnchor + TERM_DAY)
    expect(r.conceptionEquivalent).toBe(r.gestationalAnchor + CONCEPTION_OFFSET_DAYS)
  })

  it('omits the comparison when no last period is given', () => {
    expect(scanDueDate(dayNum('2026-09-14'), 12, 0).comparison).toBeNull()
  })

  it('keeps the last-period date when the gap exactly equals the threshold', () => {
    // 8w0d scan, LMP implying 8w5d: gap 5 days, threshold 5 at that age.
    const s = dayNum('2026-09-14')
    const lmp = s - wdToDays(8, 5)
    const r = scanDueDate(s, 8, 0, lmp)
    expect(r.comparison!.thresholdDays).toBe(5)
    expect(Math.abs(r.comparison!.differenceDays)).toBe(5)
    expect(r.comparison!.supportsRedating).toBe(false) // strict: not ">"
  })

  it('supports redating one day past the threshold', () => {
    const s = dayNum('2026-09-14')
    const lmp = s - wdToDays(8, 6)
    const r = scanDueDate(s, 8, 0, lmp)
    expect(Math.abs(r.comparison!.differenceDays)).toBe(6)
    expect(r.comparison!.supportsRedating).toBe(true)
  })

  it('keeps the difference consistent with both due dates', () => {
    const s = dayNum('2026-09-14')
    const lmp = s - wdToDays(10, 2)
    const r = scanDueDate(s, 9, 0, lmp)
    expect(r.comparison!.differenceDays).toBe(r.dueDate - r.comparison!.lmpDueDate)
  })

  it('refuses an out-of-range gestational age', () => {
    const s = dayNum('2026-09-14')
    expect(() => scanDueDate(s, 3, 0)).toThrow(RangeError)
    expect(() => scanDueDate(s, 43, 0)).toThrow(RangeError)
    expect(() => scanDueDate(s, 12, 7)).toThrow(RangeError)
  })
})
