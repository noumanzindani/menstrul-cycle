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
import { MS_PER_DAY } from './constants.ts'

export { MS_PER_DAY }

const ISO = /^\d{4}-\d{2}-\d{2}$/

/** Parse `YYYY-MM-DD` to UTC midnight. Throws rather than returning NaN. */
export function parseISO(iso: string): number {
  if (!ISO.test(iso)) throw new RangeError(`Expected YYYY-MM-DD, got "${iso}"`)
  const t = Date.parse(`${iso}T00:00:00Z`)
  if (Number.isNaN(t)) throw new RangeError(`Not a real date: "${iso}"`)
  // Date.parse accepts 2026-02-30 in some engines by rolling over; reject that.
  if (new Date(t).toISOString().slice(0, 10) !== iso) throw new RangeError(`Not a real date: "${iso}"`)
  return t
}

export function formatISO(epochMs: number): string {
  return new Date(epochMs).toISOString().slice(0, 10)
}

export function addDays(epochMs: number, days: number): number {
  return epochMs + days * MS_PER_DAY
}

export function assertRange(name: string, value: number, min: number, max: number): void {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new RangeError(`${name} must be a whole number between ${min} and ${max}, got ${value}`)
  }
}

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

/** The earliest date any calculator here treats as a real entry. */
export const PLAUSIBLE_FIRST_DAY_ISO = '2000-01-01'

/**
 * A required date, bounded to a plausible window, named in the error.
 *
 * The bound is checked here rather than left to the input's `min`/`max`: those are
 * baked in at build time and drift as the deploy ages, and a typed year like 2062
 * otherwise produces a confident due date four decades out.
 *
 * `maxAheadDays: 0` means "not after today", which pages with a field that can only
 * describe something already past use. It gets its own message: "check the year" is
 * the right hint for a mistyped 2062 and the wrong one for a date the reader chose
 * deliberately, which is what tomorrow almost always is.
 */
export function requireDayWithin(
  iso: string | null | undefined, field: string, maxAheadDays = 400,
): number {
  const d = requireDay(iso, field)
  if (d > todayDayNum() + maxAheadDays) {
    throw new RangeError(maxAheadDays === 0
      ? `${field} cannot be in the future.`
      : `${field} is too far ahead for this page to work with — check the year.`)
  }
  if (d < dayNum(PLAUSIBLE_FIRST_DAY_ISO)) {
    throw new RangeError(`${field} is too far in the past for this page — check the year.`)
  }
  return d
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

/**
 * Renders one day number. `timeZone: 'UTC'` is mandatory — see note 3 above.
 *
 * `locale` is for tests only, matching `dateRange`: production passes nothing and
 * gets the reader's own. Never assemble a date out of parts to control its order —
 * see the note on `dateRange` for what that cost.
 */
export function humanDate(n: number, locale?: string): string {
  return new Date(n * MS_PER_DAY).toLocaleDateString(locale, FMT)
}

/**
 * The same date with an abbreviated weekday, for dense result lists.
 *
 * Separate from `humanDate` rather than a parameter because the choice is per
 * surface, not per call: a list of three predicted periods wants "Mon", a single
 * headline due date wants "Monday", and a page that mixed the two inside one
 * result block would look like two different calculators.
 */
export function humanDateShort(n: number): string {
  return new Date(n * MS_PER_DAY).toLocaleDateString(undefined, { ...FMT, weekday: 'short' })
}

/**
 * Renders a range, repeating only what actually differs between the endpoints.
 *
 * Same month and year  → "Thursday, September 17 – Wednesday, September 23, 2026"
 * Different month      → "Wednesday, December 30, 2026 – Tuesday, January 5, 2027"
 *
 * That eliding is the whole point: "30 December to 5 January 2027" reads as 30
 * December 2027, and it is 2026.
 *
 * `Intl.DateTimeFormat.formatRange` does it, and this function used to do it by
 * hand — picking a partial option set per case and letting `toLocaleDateString`
 * render it. That is what broke: a partial set of `{ weekday, day }` has no
 * defined order, and under en-US it came out "17 Thursday". Found by driving the
 * pregnancy test page, which was the first caller; the existing tests asserted
 * that "January" appeared once rather than what order the words were in, so they
 * passed throughout. Never hand-assemble a date; ask Intl for the whole thing.
 *
 * `locale` exists so a test can pin the ORDER of the words under a named locale.
 * Production always passes nothing and gets the reader's own.
 */
export function dateRange(a: number, b: number, locale?: string): string {
  return new Intl.DateTimeFormat(locale, FMT)
    .formatRange(new Date(a * MS_PER_DAY), new Date(b * MS_PER_DAY))
}

/** Inclusive whole-day count between two day numbers. */
export const daysBetween = (a: number, b: number): number => b - a
