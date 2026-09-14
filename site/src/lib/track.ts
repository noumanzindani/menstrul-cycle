/**
 * The shared result timeline, as an HTML string.
 *
 * Lifted out of `Calculator.astro`'s module script unchanged. It moved because
 * ten calculator pages cannot each re-declare it, and because one shared island
 * carrying every calculator's code blows the page's JavaScript budget — see
 * `JS_BUDGET` in `scripts/audit.mjs`. Each page now imports only the compute
 * function it uses, and this renderer.
 *
 * Returns markup rather than touching the DOM so the geometry stays testable
 * without a browser.
 */
import { extent, geometry, gradient, type Span } from './band.ts'

export interface Bar { span: Span; color: string }

/** A track's horizontal domain: `days` days starting at day `start`. */
export interface Domain { start: number; days: number }

/**
 * The domain `track()` uses when none is given: the spans' own extent, padded.
 *
 * The padding keeps the rail visible past the outermost band. Without it a lone
 * result fills the track exactly, and a band with nothing either side of it
 * reads as a bar rather than a range.
 */
export function paddedDomain(spans: Span[]): Domain {
  const e = extent(spans)
  const pad = Math.max(1, Math.round(e.days * 0.08))
  return { start: e.start - pad, days: e.days + pad * 2 }
}

/**
 * Draw a set of spans on one shared track.
 *
 * The caption is required, not optional: a faded edge with nothing explaining
 * it reads as a measured confidence interval, which none of these are.
 *
 * `domain` is optional and, when supplied, is used verbatim — that is how the
 * gestational pages hold a fixed 0-294 day axis instead of rescaling it to
 * whatever the reader happened to enter. See `fixedExtent` in band.ts.
 */
export function track(bars: Bar[], caption: string, domain?: Domain): string {
  const d = domain ?? paddedDomain(bars.map((b) => b.span))
  const drawn = bars.map((b) => {
    const g = geometry(b.span, d.start, d.days)
    return `<span class="absolute inset-y-0 rounded-full" style="left:${g.left.toFixed(2)}%;` +
      `width:${g.width.toFixed(2)}%;background:${gradient(b.color, g.stop)}"></span>`
  }).join('')
  return `<div class="relative mt-5 h-4 w-full overflow-hidden rounded-full ` +
    `bg-outline/50 dark:bg-white/10">${drawn}</div>` +
    `<p class="mt-2 max-w-prose text-xs text-ink-muted dark:text-white/55">${caption}</p>`
}
