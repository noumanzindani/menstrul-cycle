/**
 * When a home pregnancy test can show anything.
 *
 * One calculator per module, not one module for all five. A barrel that exported
 * every formula put every formula into the page bundle of every page that needed
 * one of them: measured, the IVF page paid 2,455 bytes for a chunk holding the
 * test-timing, implantation, weeks-to-months and scan-dating arithmetic it never
 * calls. The bundler cannot drop them, because a chunk's exports are the union of
 * what all its importing pages need.
 *
 * `../pregnancy.ts` re-exports all of these, so callers and tests need not care
 * which file a formula lives in.
 */
import { assertRange } from '../days.ts'
import { CONCEPTION_OFFSET_DAYS } from '../gestation.ts'

/** Days between implantation and a home urine test having anything to detect. */
export const HCG_LAG_DAYS = 3

export interface TestTiming {
  ovulation: number
  implantEarliest: number
  implantCommonStart: number
  implantCommonEnd: number
  implantLatest: number
  earliestUsefulTest: number
  periodDue: number
  timingReliable: number
}

/**
 * When a home urine test could show anything, from the last period.
 *
 * The luteal phase is treated as FIXED at 14 days and the cycle length absorbs
 * all the variation — that is the standard calendar assumption, and it is why
 * every output below is expressible as an offset from the next period rather
 * than from the last one.
 */
export function testTiming(lmpDay: number, cycleLength: number): TestTiming {
  assertRange('Cycle length', cycleLength, 21, 45)
  const periodDue = lmpDay + cycleLength
  const ovulation = periodDue - CONCEPTION_OFFSET_DAYS
  return {
    ovulation,
    implantEarliest: ovulation + 6,
    implantCommonStart: ovulation + 8,
    implantCommonEnd: ovulation + 10,
    implantLatest: ovulation + 12,
    // Midpoint of the common implantation window, plus the detection lag.
    earliestUsefulTest: ovulation + 9 + HCG_LAG_DAYS,
    periodDue,
    // A week past the due date: beyond here a negative is not a timing problem.
    timingReliable: ovulation + 21,
  }
}
