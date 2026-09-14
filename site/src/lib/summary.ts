/**
 * The plain-text block a reader can copy out of a calculator.
 *
 * This is the artefact that circulates. It gets pasted into a note, a message to
 * a partner, a reply to a relative — and every safety frame the page puts around
 * a number stays on the page. So the frames are built into the text itself: each
 * derived date carries the word "estimate", the due date names the arithmetic it
 * came from, and the block ends by deferring to the reader's own care team.
 *
 * Pure, and takes its date formatter as an argument, so the exact string can be
 * pinned by a test without depending on the runtime locale.
 */
import { gaLabel, MILESTONES, TERM_REFERENCE } from './gestation.ts'
import type { IvfDueDate } from './pregnancy.ts'

export type DayFormatter = (day: number) => string

export interface Section { heading: string; rows: string[] }

/** Assembles a title, headed sections of `- ` rows, and trailing lines. */
export function plainText(title: string, sections: Section[], footer: string[]): string {
  const body = sections
    .filter((s) => s.rows.length > 0)
    .map((s) => `${s.heading}\n${s.rows.map((r) => `- ${r}`).join('\n')}`)
  return [title, ...body, footer.join('\n')].join('\n\n') + '\n'
}

/**
 * The line every copied block ends on.
 *
 * A due date from a clinic supersedes anything on this site, and the reader is
 * far more likely to act on the copied text than on the page it came from.
 */
export const DEFER_LINE =
  'If your clinic or maternity team has given you a due date, use theirs.'

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
