import { describe, it, expect } from 'vitest'
import {
  CONCEPTION_OFFSET_DAYS, TERM_DAY, MAX_GA_DAY, MONTH_START_DAYS,
  TRIMESTER_2_START, TRIMESTER_3_START,
  wdToDays, gaParts, gaLabel, trimesterOf, pregnancyMonth,
  MILESTONES, milestoneDates,
} from './gestation.ts'
import { LUTEAL_DAYS, GESTATION_DAYS } from './cycle.ts'

describe('anchors', () => {
  it('measures everything from the last period, 14 days before conception', () => {
    expect(CONCEPTION_OFFSET_DAYS).toBe(14)
    expect(TERM_DAY).toBe(280)
  })

  it('aliases the cycle module rather than re-literalling the constants', () => {
    // If these ever diverge, one page is counting from conception and another
    // from the last period — the 14-day bug this module exists to prevent.
    expect(CONCEPTION_OFFSET_DAYS).toBe(LUTEAL_DAYS)
    expect(TERM_DAY).toBe(GESTATION_DAYS)
  })

  it('places term 266 days after conception', () => {
    expect(TERM_DAY - CONCEPTION_OFFSET_DAYS).toBe(266)
  })
})

describe('wdToDays', () => {
  it('converts weeks and days to a day count', () => {
    expect(wdToDays(0, 0)).toBe(0)
    expect(wdToDays(40, 0)).toBe(280)
    expect(wdToDays(22, 3)).toBe(157)
  })
})

describe('gaParts / gaLabel', () => {
  it('splits a positive count', () => {
    expect(gaParts(157)).toEqual({ neg: false, weeks: 22, days: 3 })
    expect(gaLabel(157)).toBe('22w3d')
  })

  it('is sign-magnitude, so a small negative is not rendered as minus one week', () => {
    // floor/remainder gives weeks -1, days 4 for -3 — neither -3 nor -11 days.
    expect(gaParts(-3)).toEqual({ neg: true, weeks: 0, days: 3 })
    expect(gaLabel(-3)).toBe('−0w3d')
  })

  it('handles a larger negative count', () => {
    expect(gaParts(-10)).toEqual({ neg: true, weeks: 1, days: 3 })
    expect(gaLabel(-10)).toBe('−1w3d')
  })

  it('uses a real minus sign, not a hyphen', () => {
    expect(gaLabel(-3).charCodeAt(0)).toBe(0x2212)
  })

  it('never reports seven days, which is another whole week', () => {
    for (let d = -60; d <= 330; d += 1) expect(gaParts(d).days).toBeLessThan(7)
  })
})

describe('trimesterOf', () => {
  it('uses the ACOG/NHS day boundaries the app already uses', () => {
    expect(trimesterOf(0)).toBe(1)
    expect(trimesterOf(97)).toBe(1)
    expect(trimesterOf(TRIMESTER_2_START)).toBe(2)
    expect(trimesterOf(195)).toBe(2)
    expect(trimesterOf(TRIMESTER_3_START)).toBe(3)
    expect(trimesterOf(TERM_DAY)).toBe(3)
  })
})

describe('pregnancyMonth', () => {
  it('starts month 1 on gestational day 0', () => {
    expect(pregnancyMonth(0)).toMatchObject({ month: 1, startDay: 0, dayOfMonth: 1 })
  })

  it('advances at each published boundary and nowhere else', () => {
    MONTH_START_DAYS.forEach((start, i) => {
      expect(pregnancyMonth(start)?.month).toBe(i + 1)
      if (start > 0) expect(pregnancyMonth(start - 1)?.month).toBe(i)
    })
  })

  it('returns null at term rather than inventing a tenth month', () => {
    expect(pregnancyMonth(TERM_DAY)).toBeNull()
    expect(pregnancyMonth(TERM_DAY + 20)).toBeNull()
    expect(pregnancyMonth(TERM_DAY - 1)?.month).toBe(9)
  })

  it('returns null for a negative day rather than a bogus month', () => {
    expect(pregnancyMonth(-1)).toBeNull()
  })

  it('gives nine months, not ten, across the whole pregnancy', () => {
    const months = new Set<number>()
    for (let d = 0; d < TERM_DAY; d += 1) months.add(pregnancyMonth(d)!.month)
    expect(months.size).toBe(9)
  })

  it('covers every day from 0 to term with no gap', () => {
    for (let d = 0; d < TERM_DAY; d += 1) {
      const m = pregnancyMonth(d)!
      expect(d).toBeGreaterThanOrEqual(m.startDay)
      expect(d).toBeLessThanOrEqual(m.endDay)
    }
  })
})

describe('MAX_GA_DAY', () => {
  it('is 45w6d — the converter refuses anything less credible', () => {
    expect(MAX_GA_DAY).toBe(wdToDays(45, 6))
  })
})

describe('MILESTONES', () => {
  it('is ordered by offset, so a timeline never renders out of sequence', () => {
    const offsets = MILESTONES.map(([, o]) => o)
    expect([...offsets].sort((a, b) => a - b)).toEqual(offsets)
  })

  it('carries the due date at term', () => {
    expect(MILESTONES.find(([l]) => l === 'Estimated due date')?.[1]).toBe(TERM_DAY)
  })

  it('offsets every milestone from the anchor, and stays the same length', () => {
    const anchor = 20000
    const dates = milestoneDates(anchor)
    expect(dates).toHaveLength(MILESTONES.length)
    dates.forEach((d, i) => expect(d.day).toBe(anchor + MILESTONES[i][1]))
  })
})
