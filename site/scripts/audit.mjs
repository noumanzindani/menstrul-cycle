#!/usr/bin/env node
/**
 * Executable form of the flo.health defect register.
 * Every assertion below cites the defect it prevents; see
 * docs/research/flo-health-teardown.md.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { BANNED_CLAIMS } from '../src/consts.ts'

const DIST = new URL('../dist/', import.meta.url).pathname
const failures = []
const fail = (page, msg) => failures.push(`${page}: ${msg}`)

/** Pages exempt from marketing-claim scanning: reproduced legal documents.
 * `/terms` is site-authored prose, not a reproduced document, so it is NOT
 * exempt — it is subject to the banned-claim gate like every other page. */
const CLAIM_EXEMPT = new Set(['/privacy-policy'])
/**
 * Pages allowed to ship a hydrated island, with their JS byte budget.
 *
 * Per route, deliberately: a route absent from this map gets 0 bytes, so a new
 * page that ships JavaScript has to be added here by hand, and one heavy page
 * cannot raise the bar for the others.
 *
 * The number counts the whole static import graph, not just the file named in the
 * markup — see moduleClosureBytes. Three structural savings came out of measuring
 * it that way, and all three were shared-barrel problems, which is the failure
 * mode this budget exists to surface:
 *
 *   1. One island held every calculator's arithmetic behind an if/else, so every
 *      calculator page loaded all of it. Split one island per page.
 *   2. `gestation.ts` read two integers from `cycle.ts`, which put the four cycle
 *      predictors into every pregnancy page's graph. Moved to `constants.ts`.
 *   3. `pregnancy.ts` exported all five pregnancy formulas from one module, so
 *      each page carried the other four. Split into `lib/preg/*`, barrel kept.
 *   4. `summary.ts` held `ivfSummary`, which needs `MILESTONES`, `TERM_REFERENCE`
 *      and `gaLabel`, so any page with a copyable block paid for the gestation
 *      tables. Core assembler kept; per-page blocks moved to `summary/<page>.ts`.
 *
 * 8192 is the bar for a calculator whose result is a few dates. The two dating
 * pages are higher because they legitimately render more: two dated tables, a
 * conditional progress readout, and a snapshot-tested copyable summary block.
 * Those figures are what remains after the four savings above, and they carry real
 * headroom rather than sitting one word of copy below the limit.
 *
 * One layer of this is NOT yet split, and the numbers show it: `days.ts` is a single
 * shared chunk reached by every calculator, so an export added for one page is paid
 * for by all eight. `dateRange`, added for the ultrasound page, costs every route
 * about 400 bytes. Nothing is over budget because of it, which is why it has been
 * left alone rather than split on speculation — but it is the next thing to cut if
 * a route gets tight, and it is the reason a route's number can rise without that
 * route changing.
 */
const JS_BUDGET = { '/tools/period-calculator': 8192, '/tools/ovulation-calculator': 8192,
                    '/tools/cycle-length-calculator': 8192, '/tools/due-date-calculator': 8192,
                    '/tools/pregnancy-weeks-to-months': 8192,
                    '/tools/pregnancy-test-calculator': 8192,
                    '/tools/implantation-calculator': 8192,
                    '/tools/ivf-due-date-calculator': 10240,
                    '/tools/ultrasound-due-date-calculator': 10240 }

function walk(dir) {
  return readdirSync(dir).flatMap((e) => {
    const p = join(dir, e)
    return statSync(p).isDirectory() ? walk(p) : [p]
  })
}

if (!existsSync(DIST)) { console.error('audit: dist/ does not exist. Run `npm run build` first.'); process.exit(1) }
const files = walk(DIST)
const htmlFiles = files.filter((f) => f.endsWith('.html'))
if (htmlFiles.length === 0) { console.error('audit: dist/ has no HTML. Run `npm run build` first.'); process.exit(1) }

/** dist/tools/x.html -> /tools/x ; dist/index.html -> / */
const routeOf = (f) => {
  const r = '/' + relative(DIST, f).split(sep).join('/').replace(/\.html$/, '')
  return r === '/index' ? '/' : r.replace(/\/index$/, '')
}
const routes = new Set(htmlFiles.map(routeOf))

/**
 * Every static import specifier in a bundled chunk. Rollup emits relative
 * specifiers (`from"./track.abc.js"`), including bare side-effect imports.
 */
const importsOf = (js) => [
  ...all(/\bfrom\s*["']([^"']+)["']/g, js),
  ...all(/\bimport\s*["']([^"']+)["']/g, js),
].map((m) => m[1])

/**
 * Bytes of JavaScript a <script src> actually costs, following static imports
 * transitively.
 *
 * Measuring only the file named in the markup stopped being honest the moment
 * the calculator island was split per page. Each page's entry chunk is small,
 * but it statically imports the shared chunks (track/band/island/cycle/days),
 * the browser must fetch all of them before the module runs, and Astro emits no
 * modulepreload for them — so they appear nowhere in the HTML. Counting the
 * entry alone would let a page ship 50 KB of shared code and measure 700 bytes.
 *
 * Dynamic `import()` is deliberately NOT followed: this budget is about what
 * the page costs to become interactive, and a dynamic import is not fetched
 * until something asks for it. Nothing on this site uses one today.
 */
function moduleClosureBytes(page, src) {
  let total = 0
  const seen = new Set()
  const queue = [src.slice(1)] // dist-relative, no leading slash
  while (queue.length > 0) {
    const rel = queue.pop()
    if (seen.has(rel)) continue
    seen.add(rel)
    const abs = join(DIST, rel)
    let js
    try {
      total += statSync(abs).size
      js = readFileSync(abs, 'utf8')
    } catch {
      fail(page, `<script src="/${rel}"> has no file in dist/`)
      continue
    }
    const dir = rel.split('/').slice(0, -1).join('/')
    for (const spec of importsOf(js)) {
      if (!spec.startsWith('./') && !spec.startsWith('../')) {
        fail(page, `chunk /${rel} imports "${spec}", which the bundler did not resolve`)
        continue
      }
      queue.push(join(dir, spec).replace(/\\/g, '/'))
    }
  }
  return total
}

const text = (html) => html
  .replace(/<script[\s\S]*?<\/script>/gi, ' ')
  .replace(/<style[\s\S]*?<\/style>/gi, ' ')
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ')
  .replace(/\s+/g, ' ')

const all = (re, s) => [...s.matchAll(re)]

const ATTR_SCAN = /(?:content|alt|title|aria-label|placeholder|value)="([^"]*)"/gi
const scanCorpus = (html) =>
  (text(html) + ' ' + all(ATTR_SCAN, html).map((m) => m[1]).join(' ')).toLowerCase()

let orgIds = new Set(), siteIds = new Set()

for (const file of htmlFiles) {
  const page = routeOf(file)
  const html = readFileSync(file, 'utf8')

  // --- A4: title and description discipline -----------------------------
  const titles = all(/<title>([\s\S]*?)<\/title>/gi, html)
  if (titles.length !== 1) fail(page, `expected 1 <title>, found ${titles.length}`)
  else if (titles[0][1].length > 60) fail(page, `title is ${titles[0][1].length} chars (max 60)`)

  const descs = all(/<meta\s+name="description"\s+content="([^"]*)"/gi, html)
  if (descs.length !== 1) fail(page, `expected 1 meta description, found ${descs.length}`)
  else {
    const n = descs[0][1].length
    if (n < 70 || n > 155) fail(page, `meta description is ${n} chars (want 70-155)`)
  }

  const canon = all(/<link\s+rel="canonical"\s+href="([^"]*)"/gi, html)
  if (canon.length !== 1) fail(page, `expected 1 canonical, found ${canon.length}`)

  for (const prop of ['og:title', 'og:description', 'og:url', 'og:type']) {
    if (!html.includes(`property="${prop}"`)) fail(page, `missing ${prop}`)
  }

  // --- D2, D3: schema integrity ----------------------------------------
  const blocks = all(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/gi, html)
  if (blocks.length !== 1) fail(page, `expected 1 JSON-LD block, found ${blocks.length}`)
  for (const [, raw] of blocks) {
    let parsed
    try { parsed = JSON.parse(raw) } catch (e) { fail(page, `JSON-LD does not parse: ${e.message}`); continue }
    const nodes = parsed['@graph'] ?? [parsed]
    const ids = nodes.map((n) => n['@id']).filter(Boolean)
    if (new Set(ids).size !== ids.length) fail(page, `duplicate @id in JSON-LD (Flo D2)`)

    // D3: no double slash in any emitted URL, ignoring the protocol separator.
    for (const m of all(/"(https?:\/\/[^"]+)"/g, JSON.stringify(parsed))) {
      let u; try { u = new URL(m[1]) } catch { continue }
      if (u.pathname.includes('//')) fail(page, `double slash in schema URL ${m[1]} (Flo D3)`)
    }
    // No dangling references: a lone {'@id': x} is a pointer, and every pointer
    // must resolve to a node actually present in the graph. A node carrying '@id'
    // plus other keys is a definition, not a pointer.
    const declared = new Set(nodes.map((n) => n['@id']).filter(Boolean))
    const refs = []
    const walk = (v) => {
      if (Array.isArray(v)) return v.forEach(walk)
      if (v && typeof v === 'object') {
        const keys = Object.keys(v)
        if (keys.length === 1 && keys[0] === '@id') refs.push(v['@id'])
        else Object.values(v).forEach(walk)
      }
    }
    nodes.forEach(walk)
    for (const r of refs) {
      if (!declared.has(r)) fail(page, `JSON-LD points at ${r}, which no node in the graph declares`)
    }

    for (const n of nodes) {
      if (n['@type'] === 'Organization') orgIds.add(n['@id'])
      if (n['@type'] === 'WebSite') siteIds.add(n['@id'])
      if (n['@type'] === 'BreadcrumbList') {
        for (const li of n.itemListElement ?? []) {
          if (typeof li.position !== 'number') fail(page, `breadcrumb position is not an integer`)
        }
      }
      // D5, D6: health content must carry dates and an author.
      if (n['@type'] === 'Article' || n['@type'] === 'MedicalWebPage') {
        for (const k of ['datePublished', 'dateModified', 'author']) {
          if (!n[k]) fail(page, `article schema missing ${k} (Flo D5/D6)`)
        }
      }
    }
  }

  // --- D9: images -------------------------------------------------------
  for (const [tag] of all(/<img\b[^>]*>/gi, html)) {
    if (!/\swidth=/.test(tag) || !/\sheight=/.test(tag)) fail(page, `<img> without width/height (CLS, Flo D9)`)
    const src = tag.match(/src="([^"]*)"/)?.[1] ?? ''
    if (/\.(png|jpe?g)(\?|$)/i.test(src)) fail(page, `<img> ships ${src}; use WebP/AVIF via astro:assets (Flo D9)`)
  }

  // --- D4, D5: JavaScript weight ---------------------------------------
  // Counts BOTH inline script text and the bytes of every local <script src> it
  // pulls in. Astro bundles island code to /_astro/*.js, so an inline-only
  // measurement would read 0 on exactly the pages that ship JavaScript.
  if (html.includes('cdn.tailwindcss.com')) fail(page, `loads the Tailwind CDN (ships a JIT compiler)`)
  let jsBytes = 0
  for (const m of all(/<script\b([^>]*)>([\s\S]*?)<\/script>/gi, html)) {
    const [, attrs, body] = m
    if (/application\/ld\+json/.test(attrs)) continue
    jsBytes += Buffer.byteLength(body, 'utf8')
    const src = attrs.match(/src="([^"]+)"/)?.[1]
    if (src && src.startsWith('/')) {
      jsBytes += moduleClosureBytes(page, src)
    } else if (src) {
      fail(page, `<script src="${src}"> is off-origin; CSP allows script-src 'self' only`)
    }
  }
  const budget = JS_BUDGET[page] ?? 0
  if (jsBytes > budget) fail(page, `${jsBytes} bytes of JS exceeds budget ${budget} (Flo D4)`)

  // --- Calculators must never transmit an input (spec D6) ---------------
  if (page.startsWith('/tools/')) {
    for (const banned of ['fetch(', 'sendBeacon', 'XMLHttpRequest', 'new WebSocket']) {
      if (html.includes(banned)) fail(page, `calculator page contains ${banned} — inputs must never leave the browser`)
    }
  }

  // --- Positioning: no unsupportable claim ------------------------------
  if (!CLAIM_EXEMPT.has(page)) {
    const body = scanCorpus(html)
    for (const claim of BANNED_CLAIMS) {
      if (body.includes(claim)) fail(page, `contains unsupportable claim "${claim}" — see plan Global Constraints`)
    }
  }

  // --- B3: every internal link resolves ---------------------------------
  // Checks both absolute (leading '/') and relative hrefs. A relative href is
  // resolved against the directory of the page that contains it, the same way a
  // browser resolves it against that page's own URL — a leading-slash-only regex
  // left a relative link (e.g. inside a reproduced legal document) unchecked.
  for (const m of all(/<a\b[^>]*href="([^"]*)"/gi, html)) {
    const href = m[1].split('#')[0].split('?')[0]
    if (!href || /^[a-z][a-z0-9+.-]*:/i.test(href)) continue // empty, or an absolute URL / mailto: / tel: etc.
    let target
    if (href.startsWith('/')) {
      target = href.replace(/\/$/, '') || '/'
    } else {
      const dir = page.slice(0, page.lastIndexOf('/') + 1) || '/'
      target = new URL(href, 'http://x' + dir).pathname.replace(/\/$/, '') || '/'
    }
    if (!routes.has(target)) fail(page, `internal link to ${target} has no built page (Flo B3)`)
  }
}

// --- D2, D8: exactly one organisation and one website identity sitewide --
if (orgIds.size !== 1) failures.push(`sitewide: found ${orgIds.size} distinct Organization @ids, want 1`)
if (siteIds.size !== 1) failures.push(`sitewide: found ${siteIds.size} distinct WebSite @ids, want 1`)

// --- D1, B3: the sitemap covers every built route -----------------------
const sitemapFile = files.find((f) => /sitemap-0\.xml$/.test(f))
if (!sitemapFile) failures.push('sitewide: no sitemap-0.xml in dist/')
else {
  const xml = readFileSync(sitemapFile, 'utf8')
  // build.format:'file' can emit either /x or /x.html into <loc>; normalise both.
  const norm = (u) => (new URL(u).pathname.replace(/\.html$/, '').replace(/\/$/, '') || '/')
  const listed = new Set(all(/<loc>([^<]+)<\/loc>/g, xml).map((m) => norm(m[1])))
  for (const r of routes) {
    if (r === '/404') continue
    if (!listed.has(r)) failures.push(`sitemap: missing ${r}`)
  }
  if (/hreflang="\//.test(xml)) failures.push('sitemap: hreflang holds a URL path, not a language code (Flo D1)')
}

if (failures.length) {
  console.error(`\naudit FAILED — ${failures.length} problem(s):\n`)
  for (const f of failures) console.error('  ✗ ' + f)
  process.exit(1)
}
console.log(`audit passed: ${htmlFiles.length} pages, ${routes.size} routes, 0 problems`)
