/**
 * Due date from a dating scan, and the redating comparison.
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
import { CONCEPTION_OFFSET_DAYS, TERM_DAY, TRIMESTER_3_START, wdToDays } from '../gestation.ts'

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

/** The gestational-age ceiling past which g(T) is not a dating figure at all. */
export const MAX_SCAN_GA_DAYS = 294   // 42w0d
/** A last-period date implying less than this at the scan is a mis-entry, not a date. */
export const MIN_GA_BY_LMP = 28
/** More than this and the year is wrong, not the pregnancy. */
export const MAX_GA_BY_LMP = 320

export interface ScanComparison {
  lmpDueDate: number
  /** Anchor minus last-period date: also EDD minus EDD_lmp, and G_lmp minus G. */
  differenceDays: number
  thresholdDays: number
  /** The age that SELECTED the threshold row. Printed, so the choice is auditable. */
  gaByLmp: number
  /**
   * Whether published guidance supports the scan's estimate over the last
   * period's — or null when the page must not answer at all. See `suppressed`.
   */
  supportsRedating: boolean | null
  /**
   * Why the recommendation is withheld.
   *
   * 'late-scan': an estimate from a first-trimester scan is essentially never
   * redated by a third-trimester one, so running the day-gap comparison there
   * inverts the guidance it claims to apply — a large late discrepancy is a size
   * finding for a care team, not a dating correction.
   * 'dates-already-set': the reader has said an earlier scan set their dates, so
   * the last-period estimate is not the one in use and comparing to it is moot.
   */
  suppressed: 'late-scan' | 'dates-already-set' | null
  /** The gap equals the threshold exactly: one more day would flip the answer. */
  atThreshold: boolean
  /** The two ages fall in different threshold rows, so the row itself is borderline. */
  nearThreshold: boolean
}

export interface ScanDueDate {
  /** G: the gestational age the scan reported, in days. */
  gestationalAge: number
  gestationalAnchor: number
  dueDate: number
  conceptionEquivalent: number
  asOfDay: number | null
  /** g(T): gestational age on the as-of day. Negative before the anchor. */
  gestationalDaysAt: number | null
  /**
   * Days from the as-of day to the due date, negative once past it.
   *
   * Null past 308 days from the anchor: beyond there the arithmetic is still
   * correct and a countdown printed beside it is no longer informative, only
   * alarming.
   */
  daysToDueDate: number | null
  comparison: ScanComparison | null
}

export interface ScanInput {
  scanDay: number
  gaWeeks: number
  gaDays: number
  lmpDay?: number | null
  asOfDay?: number | null
  /** The reader has told us an earlier scan already set their dates. */
  datesAlreadySet?: boolean
}

export function scanDueDate(input: ScanInput): ScanDueDate {
  const { scanDay, gaWeeks, gaDays, lmpDay = null, asOfDay = null,
    datesAlreadySet = false } = input

  if (!Number.isInteger(gaWeeks) || gaWeeks < 4 || gaWeeks > 42) {
    throw new RangeError('Gestational age at the scan must be between 4 and 42 weeks.')
  }
  if (!Number.isInteger(gaDays) || gaDays < 0 || gaDays > 6) {
    throw new RangeError('Days must be a whole number between 0 and 6 — 7 days is another whole week.')
  }
  const gestationalAge = wdToDays(gaWeeks, gaDays)
  // 4-42 weeks with 0-6 days admits 42w6d, which the page's own reasoning calls
  // not a dating figure. Cap the total, not each field.
  if (gestationalAge > MAX_SCAN_GA_DAYS) {
    throw new RangeError('This page covers scans up to 42 weeks 0 days.')
  }

  const gestationalAnchor = scanDay - gestationalAge
  const dueDate = gestationalAnchor + TERM_DAY

  if (asOfDay !== null &&
      (asOfDay < gestationalAnchor - 30 || asOfDay > gestationalAnchor + 400)) {
    throw new RangeError('The as-of date is too far from the pregnancy these dates describe.')
  }
  const gestationalDaysAt = asOfDay === null ? null : asOfDay - gestationalAnchor

  let comparison: ScanComparison | null = null
  if (lmpDay !== null) {
    // One predicate, not two: `lmpDay > scanDay` and a negative age at the scan
    // are the same mistake described twice.
    if (lmpDay >= scanDay) {
      throw new RangeError('The last period has to start before the scan.')
    }
    const gaByLmp = scanDay - lmpDay
    if (gaByLmp < MIN_GA_BY_LMP) {
      throw new RangeError('That last-period date is less than four weeks before the scan — check it.')
    }
    if (gaByLmp > MAX_GA_BY_LMP) {
      throw new RangeError('That last-period date is more than 45 weeks before the scan — check the year.')
    }

    // THE THRESHOLD ROW IS SELECTED BY THE LAST PERIOD'S AGE, not the scan's.
    // ACOG CO 700's table is LMP-based, and indexing by the estimate under test is
    // circular. It changes real answers: G = 58, G_lmp = 64, gap 6 → by G the
    // threshold is 5 and the page says redate; by G_lmp it is 7 and the page says
    // keep. Opposite recommendations from identical inputs.
    const thresholdDays = redatingThresholdDays(gaByLmp)
    const differenceDays = gestationalAnchor - lmpDay
    const gap = Math.abs(differenceDays)
    const suppressed = datesAlreadySet ? 'dates-already-set'
      : gaByLmp >= TRIMESTER_3_START ? 'late-scan' : null

    comparison = {
      lmpDueDate: lmpDay + TERM_DAY,
      differenceDays,
      thresholdDays,
      gaByLmp,
      // Strict: exactly at the threshold, guidance keeps the last-period date.
      supportsRedating: suppressed === null ? gap > thresholdDays : null,
      suppressed,
      atThreshold: gap === thresholdDays,
      nearThreshold: redatingThresholdDays(gestationalAge) !== thresholdDays,
    }
  }

  return {
    gestationalAge,
    gestationalAnchor,
    dueDate,
    conceptionEquivalent: gestationalAnchor + CONCEPTION_OFFSET_DAYS,
    asOfDay,
    gestationalDaysAt,
    // Driven off the age at the as-of day, not off G: the reader can backdate the
    // as-of field, and the countdown should follow the date they asked about.
    daysToDueDate: gestationalDaysAt === null || gestationalDaysAt > 308
      ? null : dueDate - asOfDay!,
    comparison,
  }
}
