import { describe, it, expect } from 'vitest'
import {
  parseISO, formatISO, addDays,
  predictPeriods, predictOvulation, analyseCycles, estimateDueDate,
} from './cycle.ts'

describe('date primitives', () => {
  it('round-trips an ISO date through UTC midnight', () => {
    expect(formatISO(parseISO('2026-09-01'))).toBe('2026-09-01')
  })

  it('crosses a month boundary without drifting', () => {
    expect(formatISO(addDays(parseISO('2026-09-29'), 4))).toBe('2026-10-03')
  })

  it('handles a non-leap February', () => {
    expect(formatISO(addDays(parseISO('2026-02-28'), 1))).toBe('2026-03-01')
  })

  it('rejects a malformed date', () => {
    expect(() => parseISO('01/09/2026')).toThrow(RangeError)
  })

  it('rejects a date that does not exist', () => {
    expect(() => parseISO('2026-02-30')).toThrow(RangeError)
  })
})

describe('predictPeriods', () => {
  it('projects three cycles forward from the last start', () => {
    expect(predictPeriods('2026-09-01', 28, 5, 3)).toEqual([
      { start: '2026-09-29', end: '2026-10-03' },
      { start: '2026-10-27', end: '2026-10-31' },
      { start: '2026-11-24', end: '2026-11-28' },
    ])
  })

  it('makes a one-day period start and end on the same date', () => {
    expect(predictPeriods('2026-09-01', 28, 1, 1)).toEqual([
      { start: '2026-09-29', end: '2026-09-29' },
    ])
  })

  it('rejects a cycle length outside 21-45', () => {
    expect(() => predictPeriods('2026-09-01', 20, 5, 1)).toThrow(RangeError)
    expect(() => predictPeriods('2026-09-01', 46, 5, 1)).toThrow(RangeError)
  })

  it('rejects a period length outside 1-10', () => {
    expect(() => predictPeriods('2026-09-01', 28, 0, 1)).toThrow(RangeError)
    expect(() => predictPeriods('2026-09-01', 28, 11, 1)).toThrow(RangeError)
  })

  it('accepts the inclusive range boundaries', () => {
    expect(predictPeriods('2026-09-01', 21, 10, 12)).toHaveLength(12)
    expect(predictPeriods('2026-09-01', 45, 1, 1)[0].start).toBe('2026-10-16')
  })

  it('rejects a non-integer or NaN cycle length', () => {
    expect(() => predictPeriods('2026-09-01', 28.5, 5, 1)).toThrow(RangeError)
    expect(() => predictPeriods('2026-09-01', NaN, 5, 1)).toThrow(RangeError)
  })
})

describe('predictOvulation', () => {
  it('counts back fourteen days from the next period', () => {
    expect(predictOvulation('2026-09-01', 28)).toEqual({
      nextPeriod: '2026-09-29',
      ovulation: '2026-09-15',
      fertileStart: '2026-09-10',
      fertileEnd: '2026-09-16',
    })
  })

  it('moves ovulation later for a longer cycle, keeping the luteal phase fixed', () => {
    const r = predictOvulation('2026-09-01', 35)
    expect(r.nextPeriod).toBe('2026-10-06')
    expect(r.ovulation).toBe('2026-09-22')
  })

  it('rejects a cycle length outside 21-45', () => {
    expect(() => predictOvulation('2026-09-01', 20)).toThrow(RangeError)
    expect(() => predictOvulation('2026-09-01', 46)).toThrow(RangeError)
  })
})

describe('analyseCycles', () => {
  it('derives lengths, average and spread from period start dates', () => {
    expect(analyseCycles([
      '2026-06-01', '2026-06-29', '2026-07-30', '2026-08-27',
    ])).toEqual({
      lengths: [28, 31, 28],
      average: 29,
      shortest: 28,
      longest: 31,
      variation: 3,
      regularity: 'regular',
    })
  })

  it('calls a spread wider than seven days irregular', () => {
    const r = analyseCycles(['2026-01-01', '2026-01-23', '2026-03-05'])
    expect(r.lengths).toEqual([22, 41])
    expect(r.variation).toBe(19)
    expect(r.regularity).toBe('irregular')
  })

  it('treats exactly seven days of spread as still regular', () => {
    const r = analyseCycles(['2026-01-01', '2026-01-25', '2026-02-25'])
    expect(r.variation).toBe(7)
    expect(r.regularity).toBe('regular')
  })

  it('sorts input that arrives out of order', () => {
    expect(analyseCycles(['2026-06-29', '2026-06-01']).lengths).toEqual([28])
  })

  it('needs at least two starts to compute a length', () => {
    expect(() => analyseCycles(['2026-06-01'])).toThrow(RangeError)
  })

  it('rejects duplicate dates, which would imply a zero-day cycle', () => {
    expect(() => analyseCycles(['2026-06-01', '2026-06-01'])).toThrow(RangeError)
  })

  it('calls a spread of eight days irregular', () => {
    const r = analyseCycles(['2026-01-01', '2026-01-25', '2026-02-26'])
    expect(r.lengths).toEqual([24, 32])
    expect(r.variation).toBe(8)
    expect(r.regularity).toBe('irregular')
  })
})

describe('estimateDueDate', () => {
  it('applies Naegele for a 28-day cycle', () => {
    expect(estimateDueDate('2026-01-01', 28, '2026-03-01')).toEqual({
      dueDate: '2026-10-08',
      conception: '2026-01-15',
      trimester2Start: '2026-04-09',
      trimester3Start: '2026-07-16',
      gestationalWeeks: 8,
      gestationalDays: 3,
    })
  })

  it('shifts the due date by the cycle-length difference', () => {
    expect(estimateDueDate('2026-01-01', 32, '2026-03-01').dueDate).toBe('2026-10-12')
  })

  it('reports zero gestation on the LMP date itself', () => {
    const r = estimateDueDate('2026-01-01', 28, '2026-01-01')
    expect(r.gestationalWeeks).toBe(0)
    expect(r.gestationalDays).toBe(0)
  })

  it('rejects a cycle length outside 21-45', () => {
    expect(() => estimateDueDate('2026-01-01', 5, '2026-03-01')).toThrow(RangeError)
    expect(() => estimateDueDate('2026-01-01', 60, '2026-03-01')).toThrow(RangeError)
  })

  it('rejects an LMP in the future', () => {
    expect(() => estimateDueDate('2026-01-01', 28, '2025-01-01')).toThrow(RangeError)
  })
})
