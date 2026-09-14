/**
 * The copyable text block for the IVF and FET due date calculator.
 *
 * Separate from `../summary.ts` so that the gestation tables below reach only the
 * pages that render them — see the note there.
 */
import { gaLabel, MILESTONES, TERM_REFERENCE } from '../gestation.ts'
import type { IvfDueDate } from '../pregnancy.ts'
import { plainText, DEFER_LINE, type DayFormatter } from '../summary.ts'

export function ivfSummary(r: IvfDueDate, fmt: DayFormatter): string {
  const entered = [
    `Embryo transfer date: ${fmt(r.transferDay)}`,
    `Embryo age at transfer: day ${r.embryoAge}`,
  ]
  if (r.asOfDay !== null) entered.push(`Dates worked out as of: ${fmt(r.asOfDay)}`)

  const result = [
    `Estimated due date: ${fmt(r.dueDate)} — transfer date plus ${r.offsetDays} days`,
    `Fertilisation-equivalent date, gestational day 14 (estimate): ${fmt(r.conceptionEquivalent)}`,
    `Last-period-equivalent date, gestational day 0 (estimate): ${fmt(r.gestationalAnchor)}`,
  ]
  if (r.gestationalDaysAt !== null) {
    result.push(
      `Gestational age on that date (estimate): ${gaLabel(r.gestationalDaysAt)}, which is ` +
      `${r.gestationalDaysAt} days of pregnancy so far, counted from the ` +
      `last-period-equivalent date`)
  }

  return plainText(
    'LunarFlow — IVF and FET due date estimate',
    [
      { heading: 'What you entered', rows: entered },
      { heading: 'Result', rows: result },
      {
        heading: 'Estimated milestone dates',
        rows: MILESTONES.map(([label, offset]) =>
          `${label} (estimate): ${fmt(r.gestationalAnchor + offset)}`),
      },
      {
        heading: 'Gestational-age reference dates for this anchor',
        rows: TERM_REFERENCE.map((offset) =>
          `${gaLabel(offset)} (estimate): ${fmt(r.gestationalAnchor + offset)}`),
      },
    ],
    [
      'Every date above is an estimate worked out from the dates you entered.',
      DEFER_LINE,
    ],
  )
}
