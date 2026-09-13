import { describe, it, expect } from 'vitest'
import {
  coreDays, totalDays, extent, geometry, gradient, cycleFeather, type Span,
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
