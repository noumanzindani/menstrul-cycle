/**
 * Gestational-age arithmetic, shared by the weeks-to-months, IVF and
 * ultrasound calculators.
 *
 * ONE convention, stated once: every day number in this module is counted from
 * gestational day 0, which is the first day of the last menstrual period. That
 * is 14 days before conception. Mixing the two anchors by 14 days is the single
 * most common bug in this class of calculator, so the conception offset is a
 * named constant that aliases LUTEAL_DAYS rather than a literal 14 anyone can
 * retype differently.
 */
import { LUTEAL_DAYS, GESTATION_DAYS } from './constants.ts'

/** Conception sits this many days after gestational day 0. Aliased so it cannot drift. */
export const CONCEPTION_OFFSET_DAYS = LUTEAL_DAYS // 14
/** Gestational day of the estimated due date. Aliased for the same reason. */
export const TERM_DAY = GESTATION_DAYS // 280

export const EARLY_TERM_DAY = 259 // 37w0d
export const FULL_TERM_DAY = 273 // 39w0d
export const LATE_TERM_DAY = 287 // 41w0d
export const TERM_END_DAY = 293 // 41w6d
export const POST_TERM_DAY = 294 // 42w0d

/** The converter's upper bound: 45w6d. Beyond this the inputs are not credible. */
export const MAX_GA_DAY = 321

export const TRIMESTER_2_START = 98 // 14w0d
export const TRIMESTER_3_START = 196 // 28w0d

/**
 * First gestational day of each pregnancy month, 1-indexed by position.
 *
 * Pregnancy months are NOT calendar months and 40 weeks is not 10 of them.
 * These are the conventional 4/4/5/4/4/5/4/4/5-week blocks, which is why the
 * boundaries are irregular. Exported as one table so the page, the band label
 * and the tests cannot disagree about where a month starts.
 */
export const MONTH_START_DAYS = [0, 28, 63, 98, 126, 161, 196, 224, 252] as const

export const wdToDays = (weeks: number, days: number): number => 7 * weeks + days

export interface GaParts { neg: boolean; weeks: number; days: number }

/**
 * Splits a gestational day count into weeks and days, SIGN-MAGNITUDE.
 *
 * Never `Math.floor(d / 7)` with a remainder: for d = -3 that yields weeks -1,
 * days 4, which renders as "-1w4d" — a value that is neither -3 days nor
 * -11 days and is simply wrong. Negative counts occur legitimately on the
 * ultrasound page, where a scan can date a pregnancy earlier than the LMP
 * implies.
 */
export function gaParts(days: number): GaParts {
  const neg = days < 0
  const mag = neg ? -days : days
  const weeks = Math.floor(mag / 7)
  return { neg, weeks, days: mag - 7 * weeks }
}

/** "22w3d", or "−1w3d" for a negative count (U+2212, not a hyphen). */
export function gaLabel(days: number): string {
  const p = gaParts(days)
  return `${p.neg ? '−' : ''}${p.weeks}w${p.days}d`
}

export function trimesterOf(day: number): 1 | 2 | 3 {
  if (day < TRIMESTER_2_START) return 1
  if (day < TRIMESTER_3_START) return 2
  return 3
}

export interface MonthPosition {
  month: number
  startDay: number
  endDay: number
  dayOfMonth: number
}

/**
 * Which pregnancy month a gestational day falls in.
 *
 * Returns null at and after TERM_DAY rather than inventing a tenth month. The
 * post-term branch is explicit because leaving it to array coercion silently
 * produced `month: undefined` rendered as "month undefined".
 */
export function pregnancyMonth(day: number): MonthPosition | null {
  if (day < 0 || day >= TERM_DAY) return null
  let i = 0
  while (i + 1 < MONTH_START_DAYS.length && MONTH_START_DAYS[i + 1] <= day) i += 1
  const startDay = MONTH_START_DAYS[i]
  const endDay = i + 1 < MONTH_START_DAYS.length ? MONTH_START_DAYS[i + 1] - 1 : TERM_DAY - 1
  return { month: i + 1, startDay, endDay, dayOfMonth: day - startDay + 1 }
}

/**
 * Milestones as ONE table. Each page's prose, its rendered rows and its tests all
 * read this, so a milestone cannot be listed in one place and missing from
 * another — which is how one spec's worked example ended up with 11 rows against
 * its own 13-row milestone list.
 *
 * Deliberately NO term or post-term rows. Those are in TERM_REFERENCE below, and
 * they are labelled by gestational age rather than by name, because "full term"
 * and "post term" are states a care team assigns to a pregnancy. A calendar
 * subtraction is not a status, and a page that prints one next to a date the
 * reader has passed has made a clinical assessment it cannot stand behind.
 */
export const MILESTONES: ReadonlyArray<readonly [string, number]> = [
  ['End of first trimester', TRIMESTER_2_START - 1],
  ['Start of second trimester', TRIMESTER_2_START],
  ['Anatomy scan window opens', 126], // 18w0d
  ['Anatomy scan window closes', 153], // 21w6d
  ['Start of third trimester', TRIMESTER_3_START],
  ['Estimated due date', TERM_DAY],
] as const

/**
 * The gestational-age boundaries antenatal care uses to describe timing near the
 * end of a pregnancy, as ages rather than names.
 *
 * Rendered as a STATIC reference: the same rows for every reader, one neutral
 * hue, never highlighted, never compared against an as-of date, and with no
 * distinct rendering at or past the last row. The moment a row lights up because
 * the reader has reached it, the table has become a risk gauge.
 */
export const TERM_REFERENCE: ReadonlyArray<number> = [
  EARLY_TERM_DAY, FULL_TERM_DAY, TERM_DAY, LATE_TERM_DAY, TERM_END_DAY,
] as const

export function milestoneDates(anchorDay: number): Array<{ label: string; day: number }> {
  return MILESTONES.map(([label, offset]) => ({ label, day: anchorDay + offset }))
}
