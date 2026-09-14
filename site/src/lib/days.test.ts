import { describe, it, expect } from 'vitest'
import { dayNum, fromDayNum, requireDay, humanDate, dateRange, daysBetween } from './days.ts'

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
  it('states the month once when both ends share it', () => {
    const s = dateRange(dayNum('2027-01-05'), dayNum('2027-01-09'))
    expect(s.match(/January/g)).toHaveLength(1)
    expect(s).toContain('2027')
  })

  it('repeats the month when the ends differ, so the first is not read as the second', () => {
    // "30 December to 5 January 2027" reads as 30 December 2027. It is 2026.
    const s = dateRange(dayNum('2026-12-30'), dayNum('2027-01-05'))
    expect(s).toContain('December')
    expect(s).toContain('January')
  })

  it('repeats the year when the ends fall in different years', () => {
    const s = dateRange(dayNum('2026-12-30'), dayNum('2027-01-05'))
    expect(s).toContain('2026')
    expect(s).toContain('2027')
  })
})

describe('daysBetween', () => {
  it('is a plain signed difference', () => {
    expect(daysBetween(dayNum('2026-09-14'), dayNum('2026-09-21'))).toBe(7)
    expect(daysBetween(dayNum('2026-09-21'), dayNum('2026-09-14'))).toBe(-7)
  })
})
