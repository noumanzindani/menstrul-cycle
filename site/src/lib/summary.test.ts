import { describe, it, expect } from 'vitest'
import { ivfSummary, plainText, DEFER_LINE } from './summary.ts'
import { ivfDueDate } from './pregnancy.ts'
import { dayNum } from './days.ts'

/** Deterministic formatter: the snapshot must not depend on the runtime locale. */
const fmt = (d: number) => `<day ${d}>`

describe('plainText', () => {
  it('drops an empty section rather than printing a bare heading', () => {
    const s = plainText('T', [{ heading: 'A', rows: [] }, { heading: 'B', rows: ['x'] }], ['f'])
    expect(s).not.toContain('A')
    expect(s).toContain('B\n- x')
  })
})

describe('ivfSummary', () => {
  const t = dayNum('2026-09-14')

  it('is exactly this text, with no as-of date', () => {
    // Pinned deliberately. This block is the artefact that circulates: it gets
    // pasted into a note or a message, and every safety frame the page puts
    // around these numbers stays behind on the page. A change here is a change
    // to what a reader will act on, so it should require editing this test.
    expect(ivfSummary(ivfDueDate(t, 5), fmt)).toMatchInlineSnapshot(`
      "LunarFlow — IVF and FET due date estimate

      What you entered
      - Embryo transfer date: <day 20710>
      - Embryo age at transfer: day 5

      Result
      - Estimated due date: <day 20971> — transfer date plus 261 days
      - Fertilisation-equivalent date, gestational day 14 (estimate): <day 20705>
      - Last-period-equivalent date, gestational day 0 (estimate): <day 20691>

      Estimated milestone dates
      - End of first trimester (estimate): <day 20788>
      - Start of second trimester (estimate): <day 20789>
      - Anatomy scan window opens (estimate): <day 20817>
      - Anatomy scan window closes (estimate): <day 20844>
      - Start of third trimester (estimate): <day 20887>
      - Estimated due date (estimate): <day 20971>

      Gestational-age reference dates for this anchor
      - 37w0d (estimate): <day 20950>
      - 39w0d (estimate): <day 20964>
      - 40w0d (estimate): <day 20971>
      - 41w0d (estimate): <day 20978>
      - 41w6d (estimate): <day 20984>

      Every date above is an estimate worked out from the dates you entered.
      If your clinic or maternity team has given you a due date, use theirs.
      "
    `)
  })

  it('adds the as-of date and the gestational age when one is given', () => {
    const s = ivfSummary(ivfDueDate(t, 5, t + 40), fmt)
    expect(s).toContain(`- Dates worked out as of: <day ${t + 40}>`)
    expect(s).toContain('Gestational age on that date (estimate): 8w3d, which is 59 days of ' +
      'pregnancy so far, counted from the last-period-equivalent date')
  })

  it('never says "days since the transfer" for the gestational-age figure', () => {
    // At the transfer itself a day-5 embryo is already 19 gestational days. A
    // reader who reads that figure as days since their transfer is out by
    // exactly the 14 days this page exists to explain.
    const s = ivfSummary(ivfDueDate(t, 5, t), fmt)
    expect(s).toContain('19 days of pregnancy so far')
    expect(s.toLowerCase()).not.toContain('since the transfer')
    expect(s.toLowerCase()).not.toContain('since your transfer')
  })

  it('marks every derived date as an estimate', () => {
    const s = ivfSummary(ivfDueDate(t, 3, t + 10), fmt)
    for (const line of s.split('\n').filter((l) => l.startsWith('- ') && l.includes('<day'))) {
      const isInput = line.startsWith('- Embryo transfer date') ||
        line.startsWith('- Dates worked out as of')
      if (!isInput) expect(line.toLowerCase()).toContain('estimate')
    }
  })

  it('ends by deferring to the reader’s own care team', () => {
    expect(ivfSummary(ivfDueDate(t, 6), fmt).trimEnd().endsWith(DEFER_LINE)).toBe(true)
  })

  it('names no pregnancy state anywhere in the block', () => {
    const s = ivfSummary(ivfDueDate(t, 5, t + 280), fmt).toLowerCase()
    for (const word of ['full term', 'post term', 'post-term', 'overdue', 'late']) {
      expect(s).not.toContain(word)
    }
  })
})
