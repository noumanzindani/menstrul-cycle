/**
 * Geometry for soft-edged prediction bands.
 *
 * Every calculator on this site returns dates that are estimates, and the
 * site's own copy says so — periods because "small differences compound the
 * further out a prediction reaches", due dates because "most arrive within
 * about two weeks either side". A hard bar drawn on a timeline contradicts
 * that copy; a band that fades at both ends agrees with it.
 *
 * Pure functions only. No DOM, no dates — day offsets in, percentages out —
 * so the arithmetic is unit-testable and the island stays small.
 */

export interface Span {
  /** Day offset where the confident core begins, relative to the timeline origin. */
  from: number
  /** Day offset where the confident core ends, inclusive. */
  to: number
  /** Days of softening added to EACH side. 0 draws a hard edge. */
  feather: number
}

export interface Geometry {
  /** Left edge of the drawn element, as a percentage of the track. */
  left: number
  /** Width of the drawn element, as a percentage of the track. */
  width: number
  /**
   * Where the gradient reaches full opacity, as a percentage of the element's
   * OWN width — so the feather scales with the element, not the track.
   */
  stop: number
}

/** Inclusive day count of a span's confident core. */
export const coreDays = (s: Span) => Math.max(1, s.to - s.from + 1)

/** Total drawn extent of a span, feather included. */
export const totalDays = (s: Span) => coreDays(s) + s.feather * 2

/**
 * The day range a whole set of spans occupies, feathers included. Callers use
 * this as the track's extent so no band is ever clipped at either end.
 */
export function extent(spans: Span[]): { start: number; end: number; days: number } {
  if (spans.length === 0) return { start: 0, end: 0, days: 1 }
  let start = Infinity
  let end = -Infinity
  for (const s of spans) {
    start = Math.min(start, s.from - s.feather)
    end = Math.max(end, s.to + s.feather)
  }
  // +1 because both ends are inclusive day numbers, not instants.
  return { start, end, days: Math.max(1, end - start + 1) }
}

/**
 * Place one span on a track running from `start` for `days` days.
 *
 * `stop` is deliberately capped below 50: at exactly 50 the two gradient
 * halves meet and the band never reaches full colour, which would read as
 * "entirely uncertain" rather than "uncertain at the edges".
 */
export function geometry(span: Span, start: number, days: number): Geometry {
  const drawnFrom = span.from - span.feather
  const drawn = totalDays(span)

  const left = ((drawnFrom - start) / days) * 100
  const width = (drawn / days) * 100
  const stop = span.feather === 0 ? 0 : Math.min(45, (span.feather / drawn) * 100)

  return { left, width, stop }
}

/**
 * A CSS gradient that is transparent at both ends and solid through the middle.
 * A zero feather returns a flat colour so hard-edged spans cost no gradient.
 */
export function gradient(color: string, stop: number): string {
  if (stop <= 0) return color
  return (
    `linear-gradient(90deg,transparent 0%,${color} ${stop.toFixed(2)}%,` +
    `${color} ${(100 - stop).toFixed(2)}%,transparent 100%)`
  )
}

/**
 * Feather for the Nth predicted cycle, zero-indexed.
 *
 * This is a QUALITATIVE ramp, not a measured confidence interval — the
 * calculator never asks for the cycle-to-cycle variation that a real interval
 * would need. It encodes only the ordering the site's copy already states:
 * each cycle further out is less certain than the one before. Any caption
 * rendered alongside it must say that, or the fade reads as a measurement.
 */
export const cycleFeather = (index: number) => 1 + index
