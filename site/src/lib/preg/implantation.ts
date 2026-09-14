/**
 * The days implantation would most likely fall on.
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
 * The default luteal length comes from `../constants.ts` rather than
 * `CONCEPTION_OFFSET_DAYS` in `../gestation.ts`, which is the same integer.
 * Reading it from gestation.ts put `MILESTONES`, `TERM_REFERENCE` and the month
 * and milestone helpers into this page's bundle for the sake of the number 14.
 * It is also the more accurate name here: this module counts a luteal phase, not
 * a gestation.
 */
import { assertRange } from '../days.ts'
import { LUTEAL_DAYS } from '../constants.ts'

export interface ImplantationWindow {
  ovulation: number
  windowStart: number
  windowEnd: number
  commonStart: number
  commonEnd: number
  nextPeriodDue: number
}

/**
 * Implantation is 6-12 days after ovulation, most often 8-10.
 *
 * The luteal length is an input here, unlike testTiming, because someone using
 * this page may already know their own from charting. It is still bounded:
 * outside 10-16 days the calendar method has nothing useful to say.
 */
export function implantationWindow(
  lmpDay: number, cycleLength: number, lutealLength = LUTEAL_DAYS,
): ImplantationWindow {
  assertRange('Cycle length', cycleLength, 21, 45)
  assertRange('Luteal phase length', lutealLength, 10, 16)
  if (lutealLength >= cycleLength) {
    throw new RangeError('The luteal phase has to be shorter than the whole cycle.')
  }
  const ovulation = lmpDay + (cycleLength - lutealLength)
  return {
    ovulation,
    windowStart: ovulation + 6,
    windowEnd: ovulation + 12,
    commonStart: ovulation + 8,
    commonEnd: ovulation + 10,
    nextPeriodDue: lmpDay + cycleLength,
  }
}
