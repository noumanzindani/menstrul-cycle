export const MS_PER_DAY = 86_400_000

const MIN_CYCLE = 21
const MAX_CYCLE = 45
const MIN_PERIOD = 1
const MAX_PERIOD = 10
/** Length of the luteal phase, assumed fixed. See the plan's constants table. */
const LUTEAL_DAYS = 14
/** Sperm viability (5 days) plus the ovum's ~24 hours. */
const FERTILE_BEFORE = 5
const FERTILE_AFTER = 1
const GESTATION_DAYS = 280
const REFERENCE_CYCLE = 28
const TRIMESTER_2_DAY = 98   // 14 weeks
const TRIMESTER_3_DAY = 196  // 28 weeks — ACOG/NHS: T1 wk 1-13, T2 wk 14-27, T3 wk 28-40
/** Spread between shortest and longest cycle still described as regular. */
const REGULAR_MAX_VARIATION = 7

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

function assertRange(name: string, value: number, min: number, max: number): void {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new RangeError(`${name} must be a whole number between ${min} and ${max}, got ${value}`)
  }
}

export interface PeriodWindow { start: string; end: string }

export function predictPeriods(
  lastStartISO: string,
  cycleLength: number,
  periodLength: number,
  count = 3,
): PeriodWindow[] {
  assertRange('Cycle length', cycleLength, MIN_CYCLE, MAX_CYCLE)
  assertRange('Period length', periodLength, MIN_PERIOD, MAX_PERIOD)
  assertRange('Count', count, 1, 12)
  const last = parseISO(lastStartISO)
  return Array.from({ length: count }, (_, i) => {
    const start = addDays(last, cycleLength * (i + 1))
    return { start: formatISO(start), end: formatISO(addDays(start, periodLength - 1)) }
  })
}

export interface Ovulation {
  nextPeriod: string
  ovulation: string
  fertileStart: string
  fertileEnd: string
}

export function predictOvulation(lastStartISO: string, cycleLength: number): Ovulation {
  assertRange('Cycle length', cycleLength, MIN_CYCLE, MAX_CYCLE)
  const next = addDays(parseISO(lastStartISO), cycleLength)
  const ov = addDays(next, -LUTEAL_DAYS)
  return {
    nextPeriod: formatISO(next),
    ovulation: formatISO(ov),
    fertileStart: formatISO(addDays(ov, -FERTILE_BEFORE)),
    fertileEnd: formatISO(addDays(ov, FERTILE_AFTER)),
  }
}

export interface CycleStats {
  lengths: number[]
  average: number
  shortest: number
  longest: number
  variation: number
  regularity: 'regular' | 'irregular'
}

export function analyseCycles(startISOs: string[]): CycleStats {
  if (startISOs.length < 2) {
    throw new RangeError('Need at least two period start dates to measure a cycle')
  }
  const days = startISOs.map(parseISO).sort((a, b) => a - b)
  const lengths = days.slice(1).map((d, i) => Math.round((d - days[i]) / MS_PER_DAY))
  if (lengths.some((n) => n <= 0)) {
    throw new RangeError('Period start dates must all be different')
  }
  const shortest = Math.min(...lengths)
  const longest = Math.max(...lengths)
  const variation = longest - shortest
  const mean = lengths.reduce((a, b) => a + b, 0) / lengths.length
  return {
    lengths,
    average: Math.round(mean * 10) / 10,
    shortest,
    longest,
    variation,
    regularity: variation <= REGULAR_MAX_VARIATION ? 'regular' : 'irregular',
  }
}

export interface DueDate {
  dueDate: string
  conception: string
  trimester2Start: string
  trimester3Start: string
  gestationalWeeks: number
  gestationalDays: number
}

export function estimateDueDate(lmpISO: string, cycleLength: number, todayISO: string): DueDate {
  assertRange('Cycle length', cycleLength, MIN_CYCLE, MAX_CYCLE)
  const lmp = parseISO(lmpISO)
  const elapsed = Math.round((parseISO(todayISO) - lmp) / MS_PER_DAY)
  if (elapsed < 0) throw new RangeError('The last period cannot be in the future')
  return {
    dueDate: formatISO(addDays(lmp, GESTATION_DAYS + (cycleLength - REFERENCE_CYCLE))),
    conception: formatISO(addDays(lmp, cycleLength - LUTEAL_DAYS)),
    trimester2Start: formatISO(addDays(lmp, TRIMESTER_2_DAY)),
    trimester3Start: formatISO(addDays(lmp, TRIMESTER_3_DAY)),
    gestationalWeeks: Math.floor(elapsed / 7),
    gestationalDays: elapsed % 7,
  }
}
