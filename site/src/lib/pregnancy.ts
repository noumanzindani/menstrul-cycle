/**
 * Pure arithmetic for the five pregnancy-related calculators.
 *
 * Every function takes and returns DAY NUMBERS (see days.ts), never Date
 * objects and never ISO strings, so the arithmetic is testable without a
 * timezone and the pages cannot reintroduce a parsing bug.
 *
 * The shared anchor: gestational day 0 is the first day of the last menstrual
 * period, 14 days before conception. Where a calculator's natural input is a
 * conception-relative date (IVF transfer, dating scan), it converts to that
 * anchor immediately so nothing downstream has to remember which one it holds.
 *
 * These formulas were each checked by an independent reviewer who recomputed
 * the worked examples by hand; the invariants asserted in pregnancy.test.ts are
 * the ones that caught real errors.
 */
import { assertRange } from './cycle.ts'
import {
  CONCEPTION_OFFSET_DAYS, TERM_DAY, MAX_GA_DAY, TRIMESTER_2_START, TRIMESTER_3_START,
  wdToDays, trimesterOf, pregnancyMonth,
} from './gestation.ts'

/** Days between implantation and a home urine test having anything to detect. */
export const HCG_LAG_DAYS = 3

/* ------------------------------------------------------------------ *
 * 1. Pregnancy test timing
 * ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ *
 * 2. Implantation window
 * ------------------------------------------------------------------ */

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
  lmpDay: number, cycleLength: number, lutealLength = CONCEPTION_OFFSET_DAYS,
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

/* ------------------------------------------------------------------ *
 * 3. Weeks to months
 * ------------------------------------------------------------------ */

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

/* ------------------------------------------------------------------ *
 * 4. IVF / FET due date
 * ------------------------------------------------------------------ */

/** Days from transfer to the due date, by embryo age. 266 − age. */
export const IVF_OFFSET: Readonly<Record<number, number>> = {
  2: 264, 3: 263, 4: 262, 5: 261, 6: 260, 7: 259,
}

/** The ages a transfer is actually performed at, and all the page offers. */
export const IVF_SELECTABLE_AGES = [3, 5, 6] as const

export interface IvfDueDate {
  transferDay: number
  conceptionEquivalent: number
  gestationalAnchor: number
  dueDate: number
  gestationalDaysAt: number | null
}

/**
 * Due date from an embryo transfer.
 *
 * This is the one due date on the site that is not an estimate of a conception
 * date — the fertilisation date is known to the day, so the only uncertainty
 * left is the length of the pregnancy itself.
 */
export function ivfDueDate(
  transferDay: number, embryoAge: number, asOfDay: number | null = null,
): IvfDueDate {
  if (!IVF_SELECTABLE_AGES.includes(embryoAge as 3 | 5 | 6)) {
    throw new RangeError('Embryo age at transfer must be day 3, day 5 or day 6.')
  }
  const conceptionEquivalent = transferDay - embryoAge
  const gestationalAnchor = conceptionEquivalent - CONCEPTION_OFFSET_DAYS
  return {
    transferDay,
    conceptionEquivalent,
    gestationalAnchor,
    dueDate: transferDay + IVF_OFFSET[embryoAge],
    gestationalDaysAt: asOfDay === null ? null : asOfDay - gestationalAnchor,
  }
}

/* ------------------------------------------------------------------ *
 * 5. Ultrasound due date
 * ------------------------------------------------------------------ */

/**
 * How far a scan estimate must differ from a last-period estimate before
 * published guidance supports redating, keyed by the gestational age the LAST
 * PERIOD implies at the time of the scan.
 *
 * The threshold widens as pregnancy advances because later scans measure size,
 * and size varies more between pregnancies the further along they are.
 */
export function redatingThresholdDays(gaByLmp: number): number {
  if (gaByLmp <= 62) return 5
  if (gaByLmp <= 97) return 7
  if (gaByLmp <= 111) return 7
  if (gaByLmp <= 153) return 10
  if (gaByLmp <= 195) return 14
  return 21
}

export interface ScanDueDate {
  gestationalAnchor: number
  dueDate: number
  conceptionEquivalent: number
  /** Present only when a last-period date was supplied. */
  comparison: {
    lmpDueDate: number
    differenceDays: number
    thresholdDays: number
    supportsRedating: boolean
    nearThreshold: boolean
  } | null
}

export function scanDueDate(
  scanDay: number, gaWeeks: number, gaDays: number, lmpDay: number | null = null,
): ScanDueDate {
  if (!Number.isInteger(gaWeeks) || gaWeeks < 4 || gaWeeks > 42) {
    throw new RangeError('Gestational age at the scan must be between 4 and 42 weeks.')
  }
  if (!Number.isInteger(gaDays) || gaDays < 0 || gaDays > 6) {
    throw new RangeError('Days must be a whole number between 0 and 6 — 7 days is another whole week.')
  }

  const gestationalAnchor = scanDay - wdToDays(gaWeeks, gaDays)
  const dueDate = gestationalAnchor + TERM_DAY

  let comparison: ScanDueDate['comparison'] = null
  if (lmpDay !== null) {
    // The threshold is selected by the age the LAST PERIOD implies at the scan,
    // not the age the scan reported — the question is whether the LMP estimate
    // is still credible, so it is the one being tested.
    const gaByLmp = scanDay - lmpDay
    const thresholdDays = redatingThresholdDays(gaByLmp)
    const differenceDays = gestationalAnchor - lmpDay
    comparison = {
      lmpDueDate: lmpDay + TERM_DAY,
      differenceDays,
      thresholdDays,
      // Strict: exactly at the threshold, guidance keeps the last-period date.
      supportsRedating: Math.abs(differenceDays) > thresholdDays,
      nearThreshold: redatingThresholdDays(scanDay - gestationalAnchor) !== thresholdDays,
    }
  }

  return {
    gestationalAnchor,
    dueDate,
    conceptionEquivalent: gestationalAnchor + CONCEPTION_OFFSET_DAYS,
    comparison,
  }
}
