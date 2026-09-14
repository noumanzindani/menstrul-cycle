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
import { CONCEPTION_OFFSET_DAYS, TERM_DAY, wdToDays } from '../gestation.ts'

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
