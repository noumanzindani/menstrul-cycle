/**
 * Due date from an embryo transfer.
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
import { CONCEPTION_OFFSET_DAYS } from '../gestation.ts'

/** Days from transfer to the due date, by embryo age. 266 − age. */
export const IVF_OFFSET: Readonly<Record<number, number>> = {
  2: 264, 3: 263, 4: 262, 5: 261, 6: 260, 7: 259,
}

/** The ages a transfer is actually performed at, and all the page offers. */
export const IVF_SELECTABLE_AGES = [3, 5, 6] as const

export interface IvfDueDate {
  transferDay: number
  /** Echoed back, coerced and allow-listed, so nothing downstream re-reads the form. */
  embryoAge: number
  /** Days from transfer to the due date for this embryo age. */
  offsetDays: number
  conceptionEquivalent: number
  gestationalAnchor: number
  dueDate: number
  /** The as-of day, when one was given — so callers need not re-derive it. */
  asOfDay: number | null
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
  if (asOfDay !== null && asOfDay < transferDay) {
    throw new RangeError('The as-of date cannot be before the transfer.')
  }
  // Coerced and allow-listed ONCE, above. The bug this guards: with `embryoAge`
  // arriving as a string, `transferDay - (embryoAge + 14)` concatenates to
  // `transferDay - "514"` — the due date still prints correctly because object
  // keys are strings and `-` coerces, while the anchor and every gestational age
  // derived from it are wrong by 500 days.
  const conceptionEquivalent = transferDay - embryoAge
  const gestationalAnchor = conceptionEquivalent - CONCEPTION_OFFSET_DAYS
  return {
    transferDay,
    embryoAge,
    offsetDays: IVF_OFFSET[embryoAge],
    conceptionEquivalent,
    gestationalAnchor,
    dueDate: transferDay + IVF_OFFSET[embryoAge],
    asOfDay,
    gestationalDaysAt: asOfDay === null ? null : asOfDay - gestationalAnchor,
  }
}
