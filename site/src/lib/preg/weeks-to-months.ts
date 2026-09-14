/**
 * Gestational weeks and days to a pregnancy month and trimester.
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
import {
  CONCEPTION_OFFSET_DAYS, TERM_DAY, MAX_GA_DAY, TRIMESTER_2_START, TRIMESTER_3_START,
  wdToDays, trimesterOf, pregnancyMonth,
} from '../gestation.ts'

export type GaBasis = 'lmp' | 'conception'

export interface WeeksToMonths {
  gestationalDays: number
  weeks: number
  days: number
  trimester: 1 | 2 | 3
  /** True at and after 40w0d. Every month field below is null when it is. */
  postTerm: boolean
  month: number | null
  monthStartDay: number | null
  monthEndDay: number | null
  /** 4 or 5 — pregnancy months are not calendar months and not all the same length. */
  monthWeeks: number | null
  dayOfMonth: number | null
  weekOfMonth: number | null
  daysToNextMonth: number | null
  /** 9 past term: all nine months ARE complete, which is why `month` went null. */
  monthsComplete: number
  /** Null in the third trimester — there is no fourth. */
  daysToNextTrimester: number | null
  /** Null past term: a countdown to a date already passed is not a countdown. */
  daysToTerm: number | null
  /** Null below gestational day 14: under LMP dating conception has not happened. */
  conceptionWeeks: number | null
  conceptionDays: number | null
  /** Elapsed time in two other units, to one decimal. NOT the month you are in. */
  fourWeekMonths: number
  averageCalendarMonths: number
}

/** 365.25 / 12. The average calendar month, for the elapsed-time restatement only. */
const AVERAGE_MONTH_DAYS = 30.4375

const oneDecimal = (n: number): number => Math.round(n * 10) / 10

/**
 * Converts a gestational age to a pregnancy month and trimester.
 *
 * `basis` is required rather than assumed. A figure quoted from conception is
 * 14 days behind the same figure quoted from the last period, and silently
 * picking one is how a converter ends up two weeks wrong for everybody who read
 * their number off a different kind of chart.
 */
export function weeksToMonths(weeks: number, days: number, basis: GaBasis): WeeksToMonths {
  if (!Number.isInteger(weeks) || weeks < 0 || weeks > 45) {
    throw new RangeError('Weeks must be a whole number between 0 and 45.')
  }
  if (!Number.isInteger(days) || days < 0 || days > 6) {
    throw new RangeError('Days must be a whole number between 0 and 6 — 7 days is another whole week.')
  }
  if (basis !== 'lmp' && basis !== 'conception') {
    throw new RangeError('Counted from: choose last period or conception.')
  }

  const gestationalDays = wdToDays(weeks, days) + (basis === 'conception' ? CONCEPTION_OFFSET_DAYS : 0)
  if (gestationalDays > MAX_GA_DAY) {
    throw new RangeError(basis === 'conception'
      ? 'This converter covers up to 45 weeks 6 days counted from your last period — 43 weeks 6 days counted from conception.'
      : 'This converter covers up to 45 weeks 6 days.')
  }

  const d = gestationalDays
  const w = Math.floor(d / 7)
  const trimester = trimesterOf(d)

  // The post-term branch is explicit rather than left to coercion. Reading the
  // month out of MONTH_START_DAYS past term gives `month - 1 === -1`, hence
  // `MONTH_START_DAYS[-1] === undefined`, and the page then prints "-1 months
  // complete" with a NaN day-of-month — reachable from an ordinary 40w0d entry.
  const pos = pregnancyMonth(d)
  const months = pos === null
    ? {
        month: null, monthStartDay: null, monthEndDay: null, monthWeeks: null,
        dayOfMonth: null, weekOfMonth: null, daysToNextMonth: null, monthsComplete: 9,
      }
    : {
        month: pos.month,
        monthStartDay: pos.startDay,
        monthEndDay: pos.endDay,
        monthWeeks: (pos.endDay + 1 - pos.startDay) / 7,
        dayOfMonth: pos.dayOfMonth,
        weekOfMonth: Math.floor((d - pos.startDay) / 7) + 1,
        daysToNextMonth: pos.endDay + 1 - d,
        monthsComplete: pos.month - 1,
      }

  return {
    gestationalDays: d,
    weeks: w,
    days: d - 7 * w,
    trimester,
    postTerm: pos === null,
    ...months,
    daysToNextTrimester: trimester === 1 ? TRIMESTER_2_START - d
      : trimester === 2 ? TRIMESTER_3_START - d : null,
    // Null past term rather than negative: the page emits no countdown at all
    // there, because "14 days past 40 weeks" beside a term window reads as a
    // risk gauge, which is a thing this page has no standing to be.
    daysToTerm: pos === null ? null : TERM_DAY - d,
    // No clamp at zero: before day 14, LMP dating puts conception in the future,
    // and "0 weeks since conception" would assert it had already happened.
    conceptionWeeks: d < CONCEPTION_OFFSET_DAYS ? null : Math.floor((d - CONCEPTION_OFFSET_DAYS) / 7),
    conceptionDays: d < CONCEPTION_OFFSET_DAYS ? null : (d - CONCEPTION_OFFSET_DAYS) % 7,
    fourWeekMonths: oneDecimal(d / 28),
    averageCalendarMonths: oneDecimal(d / AVERAGE_MONTH_DAYS),
  }
}
