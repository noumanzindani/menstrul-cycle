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
 *
 * The luteal length comes from `../constants.ts` rather than `CONCEPTION_OFFSET_DAYS`
 * in `../gestation.ts`, which is the same integer. Reading it from gestation.ts put
 * `MILESTONES`, `TERM_REFERENCE`, `pregnancyMonth` and `milestoneDates` into this
 * page's bundle for the sake of the number 14 — the same failure as above, one
 * layer down. It is also the more accurate name here: nothing on this page is
 * counting a gestation, it is counting a luteal phase.
 */
import { assertRange } from '../days.ts'
import { LUTEAL_DAYS } from '../constants.ts'

/**
 * Days between implantation and a home urine test having anything to detect.
 *
 * hCG is produced only once the embryo has implanted, and a urine test needs it
 * to reach a threshold concentration. Three days is a commonly cited interval to
 * that point; it is an approximation, and the page says so.
 */
export const HCG_LAG_DAYS = 3

export interface TestTiming {
  ovulation: number
  implantEarliest: number
  implantCommonStart: number
  implantCommonEnd: number
  implantLatest: number
  /** Midpoint of the common implantation window, plus `HCG_LAG_DAYS`. */
  earliestSuggestedTest: number
  /**
   * The latest a test could FIRST turn positive: the latest implantation day plus
   * the lag. This is the whole answer to "I tested negative — could I still be
   * pregnant?", and it is why `timingReliable` sits further out again.
   */
  latestDetectable: number
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
  const ovulation = periodDue - LUTEAL_DAYS

  // Implantation is 6-12 days after ovulation, most often 8-10.
  const implantCommonStart = ovulation + 8
  const implantCommonEnd = ovulation + 10
  const implantLatest = ovulation + 12

  // The midpoint of the common window is where most of the probability sits, so
  // that — not the last possible day — is what the suggested test date is built
  // on. Deriving it from the two window edges and the lag, rather than writing
  // the sum, is what stops the two from drifting apart: with a 3-day lag the
  // result happens to land on `implantLatest`, and a test that pinned THAT
  // coincidence would have frozen a zero-day detection lag into the suite while
  // this page's own margin paragraph said the opposite.
  const implantCommonMid = (implantCommonStart + implantCommonEnd) / 2

  return {
    ovulation,
    implantEarliest: ovulation + 6,
    implantCommonStart,
    implantCommonEnd,
    implantLatest,
    earliestSuggestedTest: implantCommonMid + HCG_LAG_DAYS,
    latestDetectable: implantLatest + HCG_LAG_DAYS,
    periodDue,
    // A week past the due date: beyond here a negative is not a timing problem.
    timingReliable: ovulation + 21,
  }
}
