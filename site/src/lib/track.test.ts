import { describe, it, expect } from 'vitest'
import { track, paddedDomain, type Bar } from './track.ts'
import { hard, mark, fixedExtent } from './band.ts'

const pcts = (html: string): number[] =>
  [...html.matchAll(/left:([\d.-]+)%;width:([\d.]+)%/g)].flatMap((m) => [+m[1], +m[2]])

describe('paddedDomain', () => {
  it('pads both sides so the rail stays visible past the outermost band', () => {
    const d = paddedDomain([hard(0, 99)])
    expect(d.start).toBe(-8)
    expect(d.days).toBe(116)
  })

  it('always pads at least one day, so a single-day result is not the whole track', () => {
    const d = paddedDomain([mark(10)])
    expect(d.start).toBe(9)
    expect(d.days).toBe(3)
  })

  it('includes the feather, so a faded edge is never clipped', () => {
    expect(paddedDomain([{ from: 10, to: 10, feather: 5 }]).start).toBeLessThan(5)
  })
})

describe('track', () => {
  const bars: Bar[] = [{ span: hard(10, 20), color: 'red' }]

  it('never lets a band fill the whole track', () => {
    const [left, width] = pcts(track(bars, 'caption'))
    expect(left).toBeGreaterThan(0)
    expect(left + width).toBeLessThan(100)
  })

  it('renders the caption, which is why it is a required argument', () => {
    expect(track(bars, 'Because a fade is not a margin of error')).toContain(
      'Because a fade is not a margin of error')
  })

  it('draws a flat colour for a hard edge and a gradient for a feathered one', () => {
    expect(track(bars, 'x')).toContain('background:red')
    expect(track([{ span: { from: 10, to: 20, feather: 4 }, color: 'red' }], 'x'))
      .toContain('linear-gradient')
  })

  it('holds an explicit domain instead of rescaling to the data', () => {
    const d = fixedExtent(0, 294)
    const one = pcts(track([{ span: mark(84), color: 'red' }], 'x', d))
    const two = pcts(track(
      [{ span: mark(84), color: 'red' }, { span: mark(266), color: 'blue' }], 'x', d))
    // The 84-day mark must not move when a second, later bar joins it. Without an
    // explicit domain it would: the track would stretch to reach day 266 and the
    // reader would see the first result slide left for no reason they typed.
    expect(two.slice(0, 2)).toEqual(one)
  })

  it('places every bar of a shared domain on one axis', () => {
    const d = fixedExtent(0, 294)
    const html = track(
      [{ span: hard(0, 97), color: 'a' }, { span: hard(98, 195), color: 'b' },
       { span: hard(196, 279), color: 'c' }], 'x', d)
    const [l1, w1, l2, w2, l3] = pcts(html)
    expect(l1).toBeCloseTo(0, 6)
    expect(l1 + w1).toBeCloseTo(l2, 6)
    expect(l2 + w2).toBeCloseTo(l3, 6)
  })
})
