/**
 * Whole-day arithmetic and rendering — the only date surface the calculator
 * pages touch.
 *
 * Everything here exists because the same four bugs kept appearing once more
 * than one page needed dates:
 *
 * 1. `new Date(userInput)` and `Date.UTC(y, m - 1, d)` both fail silently.
 *    `Date.parse('2026-02-30T00:00:00Z')` rolls over to March 2 and returns a
 *    perfectly valid timestamp, and `Date.UTC(26, 2, 10)` remaps the year to
 *    1926. `parseISO` in cycle.ts already round-trips the string back and
 *    throws on both, so every entry point here goes through it.
 * 2. `Date.now() / MS_PER_DAY` is the epoch-UTC day, which is off by one for
 *    most of the planet for part of every day. `todayDayNum` reads the
 *    device's LOCAL calendar date instead.
 * 3. `toLocaleDateString` without `timeZone: 'UTC'` shows the previous day —
 *    and the previous weekday — to every viewer west of Greenwich, because the
 *    underlying instant is UTC midnight.
 * 4. Rendering a range as `${a} - ${b}` produces "30 December - 5 January
 *    2027", which reads as 30 December 2027. `dateRange` repeats whichever
 *    parts actually differ.
 */
import { parseISO, formatISO, MS_PER_DAY } from './cycle.ts'

/** A day number: whole days since the epoch. The unit every calculator works in. */
export const dayNum = (iso: string): number => Math.round(parseISO(iso) / MS_PER_DAY)

export const fromDayNum = (n: number): string => formatISO(n * MS_PER_DAY)

/**
 * Today as a day number, from the DEVICE'S LOCAL calendar date.
 *
 * Not `Date.now() / MS_PER_DAY`: that is the UTC day, so a user in UTC-5 at
 * 21:00 local would be told it is already tomorrow, and every "days until"
 * figure on the page would be one short.
 */
export function todayDayNum(): number {
  const n = new Date()
  const p = (x: number) => String(x).padStart(2, '0')
  return dayNum(`${n.getFullYear()}-${p(n.getMonth() + 1)}-${p(n.getDate())}`)
}

/** Throws a RangeError naming the field, rather than letting NaN reach the maths. */
export function requireDay(iso: string | null | undefined, field: string): number {
  if (iso === null || iso === undefined || iso === '') {
    throw new RangeError(`${field} is required.`)
  }
  return dayNum(iso)
}

const FMT: Intl.DateTimeFormatOptions = {
  weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
}

/** Renders one day number. `timeZone: 'UTC'` is mandatory — see note 3 above. */
export function humanDate(n: number): string {
  return new Date(n * MS_PER_DAY).toLocaleDateString(undefined, FMT)
}

/**
 * Renders a range, repeating whatever actually differs between the endpoints.
 *
 * Same month and year  → "Monday 5 to Friday 9 January 2027"
 * Different month      → "Wednesday 30 December to Tuesday 5 January 2027"
 * Different year       → "Wednesday 30 December 2026 to Tuesday 5 January 2027"
 *
 * The middle case is the one that matters: dropping the first month makes the
 * whole range read as belonging to the second one.
 */
export function dateRange(a: number, b: number): string {
  const da = new Date(a * MS_PER_DAY)
  const db = new Date(b * MS_PER_DAY)
  const sameYear = da.getUTCFullYear() === db.getUTCFullYear()
  const sameMonth = sameYear && da.getUTCMonth() === db.getUTCMonth()

  const head: Intl.DateTimeFormatOptions = sameMonth
    ? { weekday: 'long', day: 'numeric', timeZone: 'UTC' }
    : sameYear
      ? { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }
      : FMT

  const first = da.toLocaleDateString(undefined, head)
  return `${first} to ${humanDate(b)}`
}

/** Inclusive whole-day count between two day numbers. */
export const daysBetween = (a: number, b: number): number => b - a
