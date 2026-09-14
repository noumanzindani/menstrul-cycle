/**
 * Pure arithmetic for the five pregnancy calculators — a re-export barrel.
 *
 * Every function takes and returns DAY NUMBERS (see days.ts), never Date objects
 * and never ISO strings, so the arithmetic is testable without a timezone and the
 * pages cannot reintroduce a parsing bug.
 *
 * The shared anchor: gestational day 0 is the first day of the last menstrual
 * period, 14 days before conception. Where a calculator's natural input is a
 * conception-relative date (an IVF transfer, a dating scan), it converts to that
 * anchor immediately so nothing downstream has to remember which one it holds.
 *
 * The formulas themselves live one per module under `preg/`, because a single
 * module exporting all five put all five into the page bundle of every page that
 * used one — a chunk's exports are the union of what all its importing pages
 * need, so the bundler cannot drop the rest. This file exists so callers and
 * tests need not care which module a formula sits in.
 *
 * These formulas were each checked by an independent reviewer who recomputed the
 * worked examples by hand; the invariants asserted in pregnancy.test.ts are the
 * ones that caught real errors.
 */
export { HCG_LAG_DAYS, testTiming, type TestTiming } from './preg/test-timing.ts'
export { implantationWindow, type ImplantationWindow } from './preg/implantation.ts'
export { weeksToMonths, type GaBasis, type WeeksToMonths } from './preg/weeks-to-months.ts'
export { IVF_OFFSET, IVF_SELECTABLE_AGES, ivfDueDate, type IvfDueDate } from './preg/ivf.ts'
export { redatingThresholdDays, scanDueDate, type ScanDueDate } from './preg/scan.ts'
