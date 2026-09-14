import { describe, it, expect } from 'vitest'
import {
  dayNum, fromDayNum, requireDay, requireDayWithin, humanDate, humanDateShort,
  dateRange, daysBetween, todayDayNum,
} from './days.ts'

describe('dayNum / fromDayNum', () => {
  it('round-trips an ISO date', () => {
    expect(fromDayNum(dayNum('2026-09-14'))).toBe('2026-09-14')
  })

  it('counts whole days, not milliseconds', () => {
    expect(dayNum('2026-01-02') - dayNum('2026-01-01')).toBe(1)
  })

  it('crosses a leap day correctly', () => {
    expect(dayNum('2028-03-01') - dayNum('2028-02-28')).toBe(2)
  })

  it('rejects a date that does not exist, rather than rolling it over', () => {
    // Date.parse('2026-02-30T00:00:00Z') silently returns March 2 in V8.
    expect(() => dayNum('2026-02-30')).toThrow(RangeError)
  })

  it('rejects a two-digit year rather than remapping it to the 1900s', () => {
    expect(() => dayNum('26-03-10')).toThrow(RangeError)
  })
})

describe('requireDay', () => {
  it('names the field when the value is missing', () => {
    expect(() => requireDay('', 'Transfer date')).toThrow(/Transfer date/)
    expect(() => requireDay(null, 'Scan date')).toThrow(/Scan date/)
    expect(() => requireDay(undefined, 'Scan date')).toThrow(/Scan date/)
  })

  it('returns a day number for a real date', () => {
    expect(requireDay('2026-09-14', 'x')).toBe(dayNum('2026-09-14'))
  })
})

describe('humanDate', () => {
  it('renders the date that was asked for, not the one before it', () => {
    // Fails if timeZone:'UTC' is dropped and the runner sits west of Greenwich.
    expect(humanDate(dayNum('2026-09-14'))).toContain('14')
    expect(humanDate(dayNum('2026-09-14'))).toContain('September')
    expect(humanDate(dayNum('2026-09-14'))).toContain('2026')
  })
})

describe('dateRange', () => {
  it('never puts the day number before the weekday, in any locale', () => {
    // The regression that made this function Intl-backed. It used to pick a
    // PARTIAL option set per case — `{ weekday, day }` when both ends shared a
    // month — and a partial set has no defined word order: under en-US it came
    // out "17 Thursday". Found by driving the pregnancy test page, the first
    // caller. The tests that were here asserted that "January" appeared exactly
    // once, which is a fact about the old implementation rather than about
    // correctness, so they passed the whole time.
    // Compared with whitespace normalised: ICU puts thin spaces (U+2009) inside a
    // range's parts, and exactly where is its business and changes between ICU
    // versions. The word ORDER is the property being pinned here.
    const norm = (s: string) => s.replace(/\s+/g, ' ')
    expect(norm(dateRange(dayNum('2026-09-17'), dayNum('2026-09-23'), 'en-US')))
      .toBe('Thursday, September 17 – Wednesday, September 23, 2026')
    expect(norm(dateRange(dayNum('2026-09-17'), dayNum('2026-09-23'), 'en-GB')))
      .toBe('Thursday 17 September – Wednesday 23 September 2026')

    const day = '(Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day'
    for (const loc of ['en-US', 'en-GB', 'en-AU', 'en-CA', 'de-DE', 'ja-JP']) {
      expect(norm(dateRange(dayNum('2027-01-05'), dayNum('2027-01-09'), loc)))
        .not.toMatch(new RegExp(`\\d\\s*${day}`))
    }
  })

  it('never lets the first end borrow the second end’s month or year', () => {
    // "30 December to 5 January 2027" reads as 30 December 2027. It is 2026.
    // Both ends must carry whatever differs between them.
    for (const loc of ['en-US', 'en-GB']) {
      const s = dateRange(dayNum('2026-12-30'), dayNum('2027-01-05'), loc)
      expect(s).toContain('December')
      expect(s).toContain('January')
      expect(s).toContain('2026')
      expect(s).toContain('2027')
    }
  })

  it('states the year once when both ends share it', () => {
    for (const loc of ['en-US', 'en-GB']) {
      const s = dateRange(dayNum('2027-01-05'), dayNum('2027-01-09'), loc)
      expect(s.match(/2027/g)).toHaveLength(1)
    }
  })

  it('renders a single day as a single date rather than a range of one', () => {
    const d = dayNum('2027-01-05')
    expect(dateRange(d, d, 'en-GB')).toBe(humanDate(d, 'en-GB'))
  })
})

describe('requireDayWithin', () => {
  it('accepts a date inside the window', () => {
    expect(requireDayWithin('2026-09-14', 'Transfer date')).toBe(dayNum('2026-09-14'))
  })

  it('rejects a mistyped year in either direction, naming the field', () => {
    expect(() => requireDayWithin('1999-12-31', 'Transfer date')).toThrow(/Transfer date/)
    expect(() => requireDayWithin('2062-01-01', 'Transfer date')).toThrow(/check the year/)
  })

  it('allows a date within the stated look-ahead but not past it', () => {
    const t = todayDayNum()
    expect(requireDayWithin(fromDayNum(t + 400), 'x')).toBe(t + 400)
    expect(() => requireDayWithin(fromDayNum(t + 401), 'x')).toThrow(RangeError)
  })

  it('says "cannot be in the future" for a zero-day ceiling, not "check the year"', () => {
    // The ultrasound and implantation pages pass 0 for a field that can only
    // describe something already past. Tomorrow is a deliberate entry there, not a
    // mistyped year, so the hint has to be the other one.
    const t = todayDayNum()
    expect(requireDayWithin(fromDayNum(t), 'Scan date', 0)).toBe(t)
    expect(() => requireDayWithin(fromDayNum(t + 1), 'Scan date', 0))
      .toThrow('Scan date cannot be in the future.')
    expect(() => requireDayWithin('1999-12-31', 'Scan date', 0))
      .toThrow(/too far in the past/)
  })

  it('still requires a value at all', () => {
    expect(() => requireDayWithin('', 'Scan date')).toThrow(/Scan date is required/)
  })
})
