import { describe, it, expect } from 'vitest'
import { plainText, DEFER_LINE } from './summary.ts'
import { ivfSummary } from './summary/ivf.ts'
import { testTimingSummary } from './summary/test-timing.ts'
import { ivfDueDate, testTiming } from './pregnancy.ts'
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

describe('testTimingSummary', () => {
  const lmp = dayNum('2026-09-01')
  const block = (cycle = 28) => testTimingSummary(testTiming(lmp, cycle), cycle, lmp, fmt)

  it('is exactly this text', () => {
    // Pinned for the same reason as the block above: this is what gets pasted
    // into a message, so changing a word here is changing what somebody acts on.
    expect(block()).toMatchInlineSnapshot(`
      "LunarFlow — pregnancy test timing estimate

      What you entered
      - First day of last period: <day 20697>
      - Usual cycle length: 28 days

      Estimated dates
      - Earliest suggested test date (estimated): <day 20723>
      - Period due (estimated): <day 20725>
      - Latest a test could first turn positive (estimated): <day 20726>
      - From this date a negative is no longer a timing question (estimated): <day 20732>

      Estimated background dates these are worked out from
      - Ovulation (estimated): <day 20711>
      - Implantation window (estimated): <day 20717> to <day 20723>
      - Most common part of that window (estimated): <day 20719> to <day 20721>

      Every date above is an estimate from a calendar assumption: that ovulation happened 14 days before the next period was due. A cycle that ovulated earlier or later moves all of them.
      A test taken earlier than the suggested date can be negative and the pregnancy still be there. Testing again later is what settles it.
      This is not medical advice. Speak to a doctor, nurse or pharmacist about a result you are unsure of.
      "
    `)
  })

  it('marks EVERY estimated date, the period due date included', () => {
    // B7. The period due date is the most misread number this page produces, and
    // in an earlier draft it was the one row that went out bare.
    for (const cycle of [21, 28, 35, 45]) {
      const rows = block(cycle).split('\n').filter((l) => l.startsWith('- ') && l.includes('<day'))
      expect(rows.length).toBe(8)
      for (const row of rows) {
        const isInput = row.startsWith('- First day of last period')
        if (!isInput) expect(row.toLowerCase()).toContain('estimated')
      }
    }
  })

  it('says a negative before the suggested date settles nothing', () => {
    expect(block()).toContain('can be negative and the pregnancy still be there')
  })

  it('points at a person for a result, and names no condition or outcome', () => {
    const s = block().toLowerCase()
    expect(s).toContain('doctor, nurse or pharmacist')
    for (const word of ['miscarriage', 'ectopic', 'chemical pregnancy', 'viable', 'abnormal']) {
      expect(s).not.toContain(word)
    }
  })
})
