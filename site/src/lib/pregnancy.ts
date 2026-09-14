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
import { CONCEPTION_OFFSET_DAYS, TERM_DAY, MAX_GA_DAY, wdToDays, trimesterOf, pregnancyMonth } from './gestation.ts'

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
  month: number | null
  dayOfMonth: number | null
  postTerm: boolean
}

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

  const w = Math.floor(gestationalDays / 7)
  const pos = pregnancyMonth(gestationalDays)
  return {
    gestationalDays,
    weeks: w,
    days: gestationalDays - 7 * w,
    trimester: trimesterOf(gestationalDays),
    month: pos ? pos.month : null,
    dayOfMonth: pos ? pos.dayOfMonth : null,
    postTerm: gestationalDays >= TERM_DAY,
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
