import { describe, it, expect } from 'vitest'
import {
  coreDays, totalDays, extent, geometry, gradient, cycleFeather,
  hard, mark, fixedExtent, pointPct, type Span,
} from './band.ts'

const span = (from: number, to: number, feather = 0): Span => ({ from, to, feather })

describe('coreDays', () => {
  it('counts both end days', () => {
    expect(coreDays(span(0, 4))).toBe(5)
  })

  it('treats a single day as one day, not zero', () => {
    expect(coreDays(span(7, 7))).toBe(1)
  })

  it('never returns less than one, even if the range is inverted', () => {
    expect(coreDays(span(9, 3))).toBe(1)
  })
})

describe('totalDays', () => {
  it('adds the feather to both sides', () => {
    expect(totalDays(span(10, 14, 3))).toBe(5 + 6)
  })

  it('equals the core when there is no feather', () => {
    expect(totalDays(span(10, 14, 0))).toBe(5)
  })
})

describe('extent', () => {
  it('returns a usable track for no spans rather than Infinity', () => {
    expect(extent([])).toEqual({ start: 0, end: 0, days: 1 })
  })

  it('includes the feather at both ends', () => {
    // Core 10-14, feather 2 → drawn 8..16, which is 9 inclusive days.
    expect(extent([span(10, 14, 2)])).toEqual({ start: 8, end: 16, days: 9 })
  })

  it('spans the union of several bands', () => {
    const e = extent([span(0, 4, 1), span(28, 32, 2), span(56, 60, 3)])
    expect(e.start).toBe(-1)
    expect(e.end).toBe(63)
    expect(e.days).toBe(65)
  })
})

describe('geometry', () => {
  it('places a band that fills the whole track at 0% for 100%', () => {
    const g = geometry(span(0, 9, 0), 0, 10)
    expect(g.left).toBeCloseTo(0)
    expect(g.width).toBeCloseTo(100)
  })

  it('offsets the left edge by the feather, not just the core', () => {
    // Track 0..19. Core 10-14 with feather 2 draws from day 8.
    const g = geometry(span(10, 14, 2), 0, 20)
    expect(g.left).toBeCloseTo(40)
    expect(g.width).toBeCloseTo(45)
  })

  it('reports no gradient stop when there is no feather', () => {
    expect(geometry(span(10, 14, 0), 0, 20).stop).toBe(0)
  })

  it('expresses the stop against the band width, not the track', () => {
    // Drawn width 9 days, feather 2 → 2/9 ≈ 22.2% of the band itself.
    expect(geometry(span(10, 14, 2), 0, 100).stop).toBeCloseTo(22.22, 1)
  })

  it('caps the stop below half so the band always reaches full colour', () => {
    // A feather far larger than the core would otherwise push the stop past 50.
    const g = geometry(span(10, 10, 40), 0, 200)
    expect(g.stop).toBe(45)
    expect(g.stop).toBeLessThan(50)
  })
})

describe('gradient', () => {
  it('returns a flat colour when nothing is feathered', () => {
    expect(gradient('red', 0)).toBe('red')
  })

  it('is transparent at both ends and solid between the stops', () => {
    const g = gradient('red', 20)
    expect(g).toContain('transparent 0%')
    expect(g).toContain('red 20.00%')
    expect(g).toContain('red 80.00%')
    expect(g).toContain('transparent 100%')
  })
})

describe('cycleFeather', () => {
  it('grows with each cycle further out, matching the site copy', () => {
    expect(cycleFeather(0)).toBe(1)
    expect(cycleFeather(1)).toBe(2)
    expect(cycleFeather(2)).toBe(3)
  })

  it('never returns zero, so no prediction is drawn as certain', () => {
    for (let i = 0; i < 6; i += 1) expect(cycleFeather(i)).toBeGreaterThan(0)
  })
})

describe('hard / mark', () => {
  it('draws no fade at all, so a conversion is not shown as an estimate', () => {
    expect(hard(10, 20).feather).toBe(0)
    expect(mark(10).feather).toBe(0)
    expect(gradient('red', geometry(hard(10, 20), 0, 40).stop)).toBe('red')
  })

  it('makes a mark exactly one day wide', () => {
    expect(coreDays(mark(10))).toBe(1)
    expect(totalDays(mark(10))).toBe(1)
  })
})

describe('fixedExtent', () => {
  it('counts both ends, like extent()', () => {
    expect(fixedExtent(0, 294)).toEqual({ start: 0, end: 294, days: 295 })
    expect(fixedExtent(5, 5)).toEqual({ start: 5, end: 5, days: 1 })
  })

  it('does not move when the data does — the point of stating it', () => {
    const d = fixedExtent(0, 294)
    // Same domain, two very different results: the second must sit further right,
    // which is exactly what extent() would destroy by rescaling to fit.
    const early = geometry(mark(84), d.start, d.days).left
    const late = geometry(mark(266), d.start, d.days).left
    expect(late).toBeGreaterThan(early)
  })
})

describe('pointPct', () => {
  it('centres the day in its cell, matching geometry()', () => {
    const d = fixedExtent(0, 100)
    for (const day of [0, 1, 50, 99, 100]) {
      const g = geometry(mark(day), d.start, d.days)
      expect(pointPct(day, d.start, d.days)).toBeCloseTo(g.left + g.width / 2, 10)
    }
  })

  it('stays inside the track for every day of the domain', () => {
    const d = fixedExtent(0, 294)
    for (let day = 0; day <= 294; day += 1) {
      const p = pointPct(day, d.start, d.days)
      expect(p).toBeGreaterThan(0)
      expect(p).toBeLessThan(100)
    }
  })
})
