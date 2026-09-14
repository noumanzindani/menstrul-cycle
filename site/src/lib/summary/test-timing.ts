/**
 * The copyable text block for the pregnancy test timing calculator.
 *
 * Every date here is an estimate off a calendar assumption, so every row says so.
 * That is not decoration: this block is what gets pasted into a message, and a row
 * reading "Period due: Tuesday 13 October" with the estimate qualifier left behind
 * on the page is the single most misread line the page produces.
 */
import type { TestTiming } from '../pregnancy.ts'
import { plainText, type DayFormatter } from '../summary.ts'

export function testTimingSummary(
  r: TestTiming, cycleLength: number, lmpDay: number, fmt: DayFormatter,
): string {
  return plainText(
    'LunarFlow — pregnancy test timing estimate',
    [
      {
        heading: 'What you entered',
        rows: [
          `First day of last period: ${fmt(lmpDay)}`,
          `Usual cycle length: ${cycleLength} days`,
        ],
      },
      {
        heading: 'Estimated dates',
        rows: [
          `Earliest suggested test date (estimated): ${fmt(r.earliestSuggestedTest)}`,
          `Period due (estimated): ${fmt(r.periodDue)}`,
          `Latest a test could first turn positive (estimated): ${fmt(r.latestDetectable)}`,
          `From this date a negative is no longer a timing question (estimated): ` +
          `${fmt(r.timingReliable)}`,
        ],
      },
      {
        heading: 'Estimated background dates these are worked out from',
        rows: [
          `Ovulation (estimated): ${fmt(r.ovulation)}`,
          `Implantation window (estimated): ${fmt(r.implantEarliest)} to ` +
          `${fmt(r.implantLatest)}`,
          `Most common part of that window (estimated): ${fmt(r.implantCommonStart)} to ` +
          `${fmt(r.implantCommonEnd)}`,
        ],
      },
    ],
    [
      'Every date above is an estimate from a calendar assumption: that ovulation ' +
      'happened 14 days before the next period was due. A cycle that ovulated earlier ' +
      'or later moves all of them.',
      'A test taken earlier than the suggested date can be negative and the pregnancy ' +
      'still be there. Testing again later is what settles it.',
      'This is not medical advice. Speak to a doctor, nurse or pharmacist about a ' +
      'result you are unsure of.',
    ],
  )
}
