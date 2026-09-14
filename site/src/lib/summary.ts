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
 *
 * This file holds only the assembler and the lines every block shares. Each page's
 * own block lives in `summary/<page>.ts`, for the reason spelled out in
 * `preg/test-timing.ts`: `ivfSummary` needs `MILESTONES`, `TERM_REFERENCE` and
 * `gaLabel` from gestation.ts, and with everything in one module every page that
 * copied any block paid for all of that. A chunk's exports are the union of what
 * its importing pages need, so the bundler cannot drop the rest.
 */
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
