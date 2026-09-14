/**
 * The numeric conventions more than one module needs, and nothing else.
 *
 * They live in their own module for a structural reason, not a stylistic one.
 * When they sat in cycle.ts, `gestation.ts` had to import from cycle.ts to read
 * two integers — which put the four cycle predictors (`predictPeriods`,
 * `predictOvulation`, `analyseCycles`, `estimateDueDate`) into the module graph of
 * every pregnancy calculator page, where none of them is reachable. The bundler
 * cannot drop them: it can only see that the module is imported.
 *
 * A constants-only module tree-shakes to nothing, so importing from here costs a
 * page no bytes for values it does not read.
 */
export const MS_PER_DAY = 86_400_000

/** Length of the luteal phase, assumed fixed. See the plan's constants table. */
export const LUTEAL_DAYS = 14
export const GESTATION_DAYS = 280
export const REFERENCE_CYCLE = 28
export const TRIMESTER_2_DAY = 98   // 14 weeks
export const TRIMESTER_3_DAY = 196  // 28 weeks — ACOG/NHS: T1 wk 1-13, T2 wk 14-27, T3 wk 28-40
