# LunaTrack Marketing Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static 18-URL marketing site for LunaTrack in `site/`, deployed to Firebase Hosting, whose build fails if it reproduces any defect found in the flo.health teardown.

**Architecture:** Astro compiles Markdown + `.astro` components to static HTML in `site/dist/`. Zero JavaScript ships by default; the four calculator widgets are the only hydrated islands (`client:load`), and their maths lives in a framework-free, unit-tested TypeScript module so it can be tested without a browser. One component (`SeoHead.astro`) emits every `<title>`, canonical and JSON-LD block sitewide, so duplicate-emitter bugs are structurally impossible. A post-build audit script (`npm run verify`) re-runs the teardown's defect register against `dist/` and exits non-zero on regression. Firebase Hosting serves `site/dist` with canonicalisation and security headers declared in `firebase.json`.

**Tech Stack:** Astro 7.3.2, Tailwind CSS 4.3.3 (via `@tailwindcss/vite`), `@astrojs/sitemap` 3.7.4, `@fontsource/public-sans` 5.3.0, Vitest 5.0.0, Node 24.12.0 / npm 11.6.2, Firebase CLI 15.22.4.

**Spec:** `docs/superpowers/specs/2026-09-13-lunatrack-site-design.md`
**Source research:** `docs/research/flo-health-teardown.md` (defect IDs A1–A5, B1–B10, D1–D10 below are that document's)

---

## Global Constraints

### Positioning — READ THIS BEFORE WRITING ANY COPY

**Spec D8 is factually wrong about the product and is corrected here.** D8 claims the three
surviving differentiators are "works with no account", "free", and "no data sale". Two of those
do not survive contact with the codebase:

| D8 claim | Verdict | Evidence |
|---|---|---|
| "works with no account" | **FALSE** | `PRIVACY_POLICY.md:22-24` — *"Do you need an account? Yes."* `firebase_auth: ^6.5.7` (`pubspec.yaml:71`). "Continue without syncing" (`lib/screens/auth/sign_in_screen.dart:189`) is an **offline fallback offered only when the cloud is unreachable**, not a supported no-account mode. |
| "free" | **MISLEADING** | `in_app_purchase: ^3.3.0` (`pubspec.yaml:64`). `PRIVACY_POLICY.md:161` — *"Purchasing Premium removes all ads."* A free ad-supported tier plus a paid tier is structurally the same shape as Flo Premium. |
| "no data sale" | **TRUE** | `PRIVACY_POLICY.md:77`, `:154-160` — non-personalised ads only, no health data or identifiers to the ad network. |

The `pubspec.yaml:2` description (*"private, offline … all stored on your device"*) is **stale**;
it predates the Firebase auth + sync work and contradicts the current `PRIVACY_POLICY.md`.
Do not source marketing copy from it.

**The claims this site is permitted to make**, each verifiable in `PRIVACY_POLICY.md`:

1. **Your device is the source of truth.** Everything is written to the on-device database first; the cloud copy is a mirror. The app works fully offline. (`PRIVACY_POLICY.md:36-40`)
2. **The on-device database is encrypted at rest** with a 256-bit key generated on-device and held in the OS keystore. (`PRIVACY_POLICY.md:43-45`) — state the documented carve-out: the sync component's working copy is not covered by that encryption.
3. **Your health data is never sent to advertisers.** Non-personalised ads only. (`PRIVACY_POLICY.md:154-160`)
4. **No ads on the sensitive screens** — symptom logging, diary and health insights carry none. (`PRIVACY_POLICY.md:159-160`) This is the most specific and least imitable claim available; lead with it.
5. **Photo descriptions are off until you turn them on**, per account and per device. (`PRIVACY_POLICY.md:109-116`)

**Banned strings, enforced by `npm run verify` (Task 3):** `no account`, `without an account`,
`completely free`, `100% free`, `fully private`, `we can't see`, `we cannot see`, `end-to-end`,
`zero-knowledge`, `anonymous`. The last four are false — `PRIVACY_POLICY.md:89` states plainly
that the operator *can* read cloud data. Shipping a claim Flo can disprove in one screenshot is
worse than shipping no claim.

### Everything else

- **Node floor is `>=22.12.0`** (Astro 7 `engines`). This box runs v24.12.0. Record the floor in `site/package.json` `engines`.
- **Tailwind 4, not 3.** Spec D5 names `@astrojs/tailwind`; that package (6.0.2) peer-requires `astro ^3||^4||^5` and `tailwindcss ^3.0.24`, which would pin a new project two majors behind on a deprecated integration. Use `@tailwindcss/vite` and translate the Stitch token block to CSS `@theme`. **Token values are copied verbatim; only the config syntax changes.**
- **`site/` is hermetic.** It has its own `package.json`. Never add a Node dependency to the repo root, and never touch `pubspec.yaml`, `lib/`, or `test/`. The 906-test Flutter suite must be provably unaffected.
- **No dependency outside the list in Task 1 Step 2 without asking the user first** (per `~/.claude/CLAUDE.md`).
- **npm only.** Never introduce pnpm or yarn into `site/`. Commit `site/package-lock.json`.
- **`SITE` is declared exactly once**, in `site/src/consts.ts`. Every absolute URL is built with `new URL(path, SITE)`. Never concatenate URL strings — that is precisely how Flo produced `https://flo.health//search` on every page (D3).
- **Only `SeoHead.astro` emits `<title>`, `<meta name="description">`, `<link rel="canonical">`, Open Graph tags, or `<script type="application/ld+json">`.** No page, layout or component emits these directly.
- **Every calculator computes in the browser only.** No `fetch`, no `navigator.sendBeacon`, no form POST, no analytics call may carry a user-entered date. Enforced by Task 3.
- **Images:** `astro:assets` only, output WebP/AVIF, always with intrinsic `width` and `height` (D9, CLS).
- **Titles ≤ 60 chars; meta descriptions 70–155 chars.** Enforced at build (Task 4) and in the audit (Task 3).
- Conventional Commits (`feat:` / `fix:` / `docs:` / `test:` / `chore:`). Commit after every task. Current branch is `feat/stitch-redesign`; **do not commit to `main`**.
- Run `npm run build && npm run verify` in `site/` before marking any task done.

---

## File Structure

```
site/
  package.json            npm scripts, engines, dependency manifest
  astro.config.mjs        integrations: sitemap; vite plugin: tailwind
  tsconfig.json           strict TS, extends astro/tsconfigs/strict
  vitest.config.ts        unit tests for src/lib only
  scripts/audit.mjs       the executable defect register (D10) — no deps
  src/
    consts.ts             SITE, ORG, NAV, banned-claim list — single source of truth
    types.ts              shared TS interfaces (FaqEntry, ArticleMeta, Crumb, Source)
    lib/
      cycle.ts            pure date maths for all four calculators
      cycle.test.ts       Vitest unit tests
    content.config.ts     Zod schemas for the articles collection (D3)
    content/articles/     six .md files
    components/
      SeoHead.astro       THE ONLY emitter of title/canonical/OG/JSON-LD (D2)
      Header.astro        site nav
      Footer.astro        site footer
      Faq.astro           renders FAQ list; feeds FAQPage schema via SeoHead
      Disclaimer.astro    non-diagnostic notice (D6)
      ReviewNotice.astro  "not medically reviewed" banner (D4)
      Calculator.astro    widget markup + inline <script type="module"> (no UI framework)
    layouts/
      Base.astro          html/head/body shell; takes SEO props, passes to SeoHead
      Article.astro       article chrome: byline, dates, sources, review notice
      Tool.astro          calculator chrome: widget slot, prose slot, FAQ, disclaimer
    pages/
      index.astro         /
      features.astro      /features
      privacy.astro       /privacy
      download.astro      /download
      privacy-policy.astro
      terms.astro
      tools/index.astro   /tools
      tools/period-calculator.astro
      tools/ovulation-calculator.astro
      tools/cycle-length-calculator.astro
      tools/due-date-calculator.astro
      articles/index.astro
      articles/[...slug].astro
      404.astro
    styles/global.css     @theme token block (ported from Stitch) + base styles
```

**Responsibility boundaries.** `src/lib/cycle.ts` knows dates and nothing about the DOM, so it
is unit-testable without a browser. `SeoHead.astro` knows schema and nothing about page content,
so a schema fix is one file. `scripts/audit.mjs` reads only `dist/`, so it tests the artifact
that actually ships rather than the source that produces it.

---

### Task 1: Scaffold `site/` with design tokens and a building shell

**Files:**
- Create: `site/package.json`, `site/astro.config.mjs`, `site/tsconfig.json`
- Create: `site/src/consts.ts`, `site/src/styles/global.css`
- Create: `site/src/layouts/Base.astro`, `site/src/pages/index.astro`
- Modify: `.gitignore` (append two lines after line 54)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `SITE`, `ORG`, `NAV`, `BANNED_CLAIMS` exported from `site/src/consts.ts`; a `Base.astro` layout accepting `{ title: string; description: string; path: string }`.

- [ ] **Step 1: Create the directory and the npm manifest**

Create `site/package.json`:

```json
{
  "name": "lunatrack-site",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "engines": { "node": ">=22.12.0" },
  "scripts": {
    "dev": "astro dev",
    "build": "astro build",
    "preview": "astro preview",
    "verify": "node scripts/audit.mjs",
    "test": "vitest run",
    "check": "astro check"
  }
}
```

- [ ] **Step 2: Install the dependency set**

This is the complete dependency list. Adding anything else requires asking the user first.

```bash
cd site
npm install astro@^7.3.2 @astrojs/sitemap@^3.7.4 tailwindcss@^4.3.3 @tailwindcss/vite@^4.3.3 @fontsource/public-sans@^5.3.0
npm install -D vitest@^5.0.0 @astrojs/check@^0.9.10 typescript@^6.0.3
```

**Every version is pinned deliberately; do not substitute `@latest` for any of them.**
`@astrojs/check@0.9.10` — the newest release that exists — declares
`peerDependencies: { typescript: '^5.0.0 || ^6.0.0' }`, while `typescript@latest` is **7.0.2**.
Resolving TypeScript by tag therefore fails with `ERESOLVE`. TypeScript **6.0.3** is a stable
release inside the supported range (npm's `beta` dist-tag still points at `6.0.0-beta`, which
makes 6.x look pre-release when it is not), and the full set above resolves clean — verified
by `npm install --dry-run` on 2026-09-13.

Expected: `node_modules/` created, `package-lock.json` written, no peer-dependency errors.
If npm reports a peer conflict anyway, STOP and report it — do not pass `--force` or
`--legacy-peer-deps`. Silencing a peer conflict hides a real incompatibility until runtime.

- [ ] **Step 3: Ignore build artefacts before anything is committed**

Append to `.gitignore` (the file currently ends with the `lib/firebase_options.dart` block):

```
# Astro marketing site (site/) — Node artefacts
site/node_modules/
site/dist/
site/.astro/
```

Verify nothing large is stageable:

```bash
git status --short | grep -c 'site/node_modules'
```

Expected: `0`

- [ ] **Step 4: Write the single source of site-wide constants**

Create `site/src/consts.ts`. `SITE` is the only place a hostname appears anywhere in the project.

```ts
/** The canonical origin. Changing the domain is a one-line edit here. */
export const SITE = 'https://lunatrack.web.app'

export const ORG = {
  name: 'LunaTrack',
  legalName: 'LunaTrack',
  logo: '/images/logo.png',
  sameAs: [
    'https://play.google.com/store/apps/details?id=com.lunatrack.app',
  ],
} as const

/**
 * Nav is built up as the routes exist. The audit fails the build on a link to a
 * page that has not been built, so `/tools` is added in Task 6 and `/articles`
 * in Task 7 — not before.
 */
export const NAV = [
  { href: '/features', label: 'Features' },
  { href: '/privacy', label: 'Your data' },
  { href: '/download', label: 'Download' },
] as const

/**
 * Claims this site may not make. See the Global Constraints section of the plan:
 * the app requires an account, has a paid tier, and stores readable cloud data.
 * `scripts/audit.mjs` fails the build if any of these appears in rendered text.
 */
/**
 * Sentinel for spec D4: an article no clinician has reviewed. Declared HERE, in a
 * plain module, so `content.config.ts`, `ReviewNotice.astro` and `SeoHead.astro`
 * all compare the same literal. If the visible notice and the emitted schema ever
 * disagreed about what counts as unreviewed, the page could claim a medical review
 * that did not happen — the exact failure D4 exists to prevent.
 */
export const UNREVIEWED = 'Not medically reviewed'

export const BANNED_CLAIMS = [
  'no account',
  'without an account',
  'completely free',
  '100% free',
  'fully private',
  "we can't see",
  'we cannot see',
  'end-to-end',
  'zero-knowledge',
  'anonymous',
] as const
```

- [ ] **Step 5: Port the Stitch design tokens to a Tailwind 4 `@theme` block**

Create `site/src/styles/global.css`. Values are copied verbatim from
`docs/design/stitch/04-insights.html` and cross-checked against `lib/theme/app_theme.dart`
(`:92` seed, `:107` ink, `:34-39` phase colours).

```css
@import "tailwindcss";
@import "@fontsource/public-sans/400.css";
@import "@fontsource/public-sans/500.css";
@import "@fontsource/public-sans/600.css";
@import "@fontsource/public-sans/700.css";

/* Class-based dark mode, matching the Stitch mockups' darkMode: "class". */
@custom-variant dark (&:where(.dark, .dark *));

@theme {
  --color-primary: #3A2A30;
  --color-seed: #F7A8C4;
  --color-seed-strong: #E97B93;
  --color-surface: #FFFFFF;
  --color-surface-tint: #FDF0F4;
  --color-surface-dark: #1C1B1F;
  --color-surface-dark-2: #2B292C;
  --color-outline: #E6E1E5;

  --color-menstrual: #D64F6E;
  --color-follicular: #6FB3A8;
  --color-ovulatory: #7E9CE8;
  --color-luteal: #D9A15B;
  --color-fertile: #9CCFC6;
  --color-predicted: #B0A8C0;

  --radius-DEFAULT: 0.5rem;
  --radius-lg: 1rem;
  --radius-xl: 1.5rem;
  --radius-card: 20px;
  --radius-btn: 16px;

  --spacing-btn-h: 52px;

  --font-body: "Public Sans", ui-sans-serif, system-ui, sans-serif;
  --font-headline: "Public Sans", ui-sans-serif, system-ui, sans-serif;
}

html { color-scheme: light dark; }
body { font-family: var(--font-body); }
```

Self-hosting the font via `@fontsource` rather than Google Fonts removes a third-party
connection from a health site (spec D5).

- [ ] **Step 6: Configure Astro**

Create `site/astro.config.mjs`:

```js
import { defineConfig } from 'astro/config'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'
import { SITE } from './src/consts.ts'

export default defineConfig({
  site: SITE,
  trailingSlash: 'never',
  build: { format: 'file' },   // /tools/period-calculator.html -> cleanUrls in Firebase
  integrations: [sitemap()],
  // assetsInlineLimit: 0 forces island code to a real /_astro/*.js file rather
  // than an inline <script>. The production CSP is `script-src 'self'`, which
  // blocks inline scripts — leaving them inlined would silently break all four
  // calculators on the deployed site while everything looked fine locally.
  vite: { plugins: [tailwindcss()], build: { assetsInlineLimit: 0 } },
})
```

Create `site/tsconfig.json`:

```json
{
  "extends": "astro/tsconfigs/strict",
  "include": [".astro/types.d.ts", "**/*"],
  "exclude": ["dist"]
}
```

- [ ] **Step 7: Write a minimal shell that builds**

Create `site/src/layouts/Base.astro`. It deliberately does NOT emit SEO tags yet — `SeoHead`
arrives in Task 2, and this layout will delegate to it. Emitting them here first and moving
them later is how a project ends up with two emitters, which is Flo's D2.

```astro
---
import '../styles/global.css'
interface Props { title: string; description: string; path: string }
const { title, description, path } = Astro.props
---
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>{title}</title>
    <meta name="description" content={description} />
  </head>
  <body class="bg-surface text-primary dark:bg-surface-dark dark:text-white">
    <main>
      <slot />
    </main>
  </body>
</html>
```

Create `site/src/pages/index.astro`:

```astro
---
import Base from '../layouts/Base.astro'
---
<Base
  title="LunaTrack — period and cycle tracking"
  description="LunaTrack is a period and cycle tracker that keeps your device as the source of truth, works fully offline, and never sends health data to advertisers."
  path="/"
>
  <h1 class="text-3xl font-bold">LunaTrack</h1>
</Base>
```

- [ ] **Step 8: Verify the build produces static HTML**

```bash
cd site && npm run build
test -f dist/index.html && grep -c '<h1' dist/index.html
```

Expected: build succeeds; `1`.

Confirm zero JavaScript shipped — this is the headline reason Astro was chosen (D1):

```bash
find site/dist -name '*.js' | wc -l
```

Expected: `0`

- [ ] **Step 9: Confirm the Flutter side is untouched**

```bash
cd /Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track
git status --short -- lib/ test/ pubspec.yaml
```

Expected: no output. `site/` must never appear in a Flutter diff.

- [ ] **Step 10: Commit**

```bash
git add .gitignore site/
git commit -m "feat(site): scaffold Astro marketing site with LunaTrack design tokens"
```

---

### Task 2: The single SEO and schema emitter

**Files:**
- Create: `site/src/types.ts`, `site/src/components/SeoHead.astro`
- Modify: `site/src/layouts/Base.astro` (replace the inline head tags from Task 1 Step 7)

**Interfaces:**
- Consumes: `SITE`, `ORG` from `site/src/consts.ts`.
- Produces: `SeoHead.astro` accepting
  `{ title: string; description: string; path: string; type?: 'website' | 'article'; article?: ArticleMeta; faq?: FaqEntry[]; breadcrumbs?: Crumb[] }`
  where `ArticleMeta = { author: string; reviewedBy: string; datePublished: Date; dateModified: Date }`,
  `FaqEntry = { q: string; a: string }`, and `Crumb = { name: string; path: string }`.
  Every later task passes SEO data through this component and never emits head tags itself.

- [ ] **Step 1: Declare the shared types in a plain module**

Types live in `site/src/types.ts`, **not** exported from an `.astro` frontmatter fence.
Astro components reliably export only their default component; named type re-exports from the
fence are not a supported interface. Every component that needs these imports them from here.

```ts
export interface ArticleMeta {
  author: string
  reviewedBy: string
  datePublished: Date
  dateModified: Date
}
export interface FaqEntry { q: string; a: string }
export interface Crumb { name: string; path: string }
export interface Source { title: string; url: string }
```

- [ ] **Step 2: Write the emitter**

Create `site/src/components/SeoHead.astro`. Note that **every** URL is built with `new URL()`.
Flo's `SearchAction` target was `https://flo.health//search` on every page tested (D3) because
it concatenated a base and a path; `new URL('/search', SITE).href` cannot produce a double slash.

```astro
---
import { SITE, ORG, UNREVIEWED } from '../consts.ts'
import type { ArticleMeta, FaqEntry, Crumb } from '../types.ts'

interface Props {
  title: string
  description: string
  path: string
  type?: 'website' | 'article'
  article?: ArticleMeta
  faq?: FaqEntry[]
  breadcrumbs?: Crumb[]
}

const {
  title, description, path,
  type = 'website', article, faq, breadcrumbs,
} = Astro.props as Props

/** The one and only way a URL is built in this project. */
const abs = (p: string) => new URL(p, SITE).href
const canonical = abs(path)

const graph: Record<string, unknown>[] = [
  {
    '@type': 'Organization',
    '@id': abs('/#organization'),
    name: ORG.name,
    legalName: ORG.legalName,
    url: abs('/'),
    logo: abs(ORG.logo),
    sameAs: [...ORG.sameAs],
  },
  {
    '@type': 'WebSite',
    '@id': abs('/#website'),
    url: abs('/'),
    name: ORG.name,
    publisher: { '@id': abs('/#organization') },
    inLanguage: 'en',
  },
]

if (article) {
  const node: Record<string, unknown> = {
    '@type': article.reviewedBy === UNREVIEWED ? 'Article' : 'MedicalWebPage',
    '@id': `${canonical}#article`,
    headline: title,
    description,
    url: canonical,
    mainEntityOfPage: canonical,   // a plain URL; never a pointer to a node we do not emit
    author: { '@type': 'Person', name: article.author },
    publisher: { '@id': abs('/#organization') },
    datePublished: article.datePublished.toISOString(),
    dateModified: article.dateModified.toISOString(),
    isPartOf: { '@id': abs('/#website') },
  }
  if (article.reviewedBy !== UNREVIEWED) {
    node.reviewedBy = { '@type': 'Person', name: article.reviewedBy }
  }
  graph.push(node)
}

if (faq?.length) {
  graph.push({
    '@type': 'FAQPage',
    '@id': `${canonical}#faq`,
    mainEntity: faq.map((f) => ({
      '@type': 'Question',
      name: f.q,
      acceptedAnswer: { '@type': 'Answer', text: f.a },
    })),
  })
}

if (breadcrumbs?.length) {
  graph.push({
    '@type': 'BreadcrumbList',
    '@id': `${canonical}#breadcrumbs`,
    // position is an integer, not a string. Flo shipped strings here (D10-low).
    itemListElement: breadcrumbs.map((c, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: c.name,
      item: abs(c.path),
    })),
  })
}

const jsonLd = { '@context': 'https://schema.org', '@graph': graph }
---
<title>{title}</title>
<meta name="description" content={description} />
<link rel="canonical" href={canonical} />
<meta property="og:type" content={type} />
<meta property="og:title" content={title} />
<meta property="og:description" content={description} />
<meta property="og:url" content={canonical} />
<meta property="og:site_name" content={ORG.name} />
<meta name="twitter:card" content="summary_large_image" />
<script type="application/ld+json" set:html={JSON.stringify(jsonLd)} />
```

- [ ] **Step 3: Delegate from the layout**

Replace the `<title>` and `<meta name="description">` lines in `site/src/layouts/Base.astro`
with the component, so exactly one emitter remains:

```astro
---
import '../styles/global.css'
import SeoHead from '../components/SeoHead.astro'
import type { ArticleMeta, FaqEntry, Crumb } from '../types.ts'

interface Props {
  title: string
  description: string
  path: string
  type?: 'website' | 'article'
  article?: ArticleMeta
  faq?: FaqEntry[]
  breadcrumbs?: Crumb[]
}
const props = Astro.props as Props
---
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <SeoHead {...props} />
  </head>
  <body class="bg-surface text-primary dark:bg-surface-dark dark:text-white">
    <main>
      <slot />
    </main>
  </body>
</html>
```

- [ ] **Step 4: Rebuild and verify the emitted schema by hand**

```bash
cd site && npm run build
node -e "
const fs=require('fs');
const html=fs.readFileSync('dist/index.html','utf8');
const m=html.match(/<script type=\"application\/ld\+json\">(.*?)<\/script>/s);
const g=JSON.parse(m[1]);
const ids=g['@graph'].map(n=>n['@id']);
console.log('nodes:', g['@graph'].map(n=>n['@type']).join(','));
console.log('ids unique:', new Set(ids).size===ids.length);
console.log('double slash:', JSON.stringify(g).includes('web.app//'));
"
```

Expected:
```
nodes: Organization,WebSite
ids unique: true
double slash: false
```

Also confirm exactly one canonical and one title:

```bash
grep -c '<link rel="canonical"' dist/index.html; grep -c '<title>' dist/index.html
```

Expected: `1` and `1`.

- [ ] **Step 5: Commit**

```bash
git add site/
git commit -m "feat(site): add single sitewide SEO and JSON-LD emitter"
```

---

### Task 3: The teardown's defect register as an executable build gate

This task exists before any content is written. An audit added after eighteen pages exist gets
relaxed until it passes; an audit that comes first shapes the pages instead.

**Files:**
- Create: `site/scripts/audit.mjs`

**Interfaces:**
- Consumes: `BANNED_CLAIMS` from `site/src/consts.ts`; the built `site/dist/` tree.
- Produces: `npm run verify`, exiting `0` on pass and `1` with a printed failure list otherwise.
  Every later task must leave `npm run verify` green.

- [ ] **Step 1: Write the audit script**

Create `site/scripts/audit.mjs`. It uses only Node built-ins — no parser dependency, because the
only HTML it ever reads is HTML this project generated.

```js
#!/usr/bin/env node
/**
 * Executable form of the flo.health defect register.
 * Every assertion below cites the defect it prevents; see
 * docs/research/flo-health-teardown.md.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, relative, sep } from 'node:path'
import { BANNED_CLAIMS } from '../src/consts.ts'

const DIST = new URL('../dist/', import.meta.url).pathname
const failures = []
const fail = (page, msg) => failures.push(`${page}: ${msg}`)

/** Pages exempt from marketing-claim scanning: reproduced legal documents. */
const CLAIM_EXEMPT = new Set(['/privacy-policy', '/terms'])
/** Pages allowed to ship a hydrated island, with their JS byte budget. */
const JS_BUDGET = { '/tools/period-calculator': 8192, '/tools/ovulation-calculator': 8192,
                    '/tools/cycle-length-calculator': 8192, '/tools/due-date-calculator': 8192 }

function walk(dir) {
  return readdirSync(dir).flatMap((e) => {
    const p = join(dir, e)
    return statSync(p).isDirectory() ? walk(p) : [p]
  })
}

const files = walk(DIST)
const htmlFiles = files.filter((f) => f.endsWith('.html'))
if (htmlFiles.length === 0) { console.error('audit: dist/ has no HTML. Run `npm run build` first.'); process.exit(1) }

/** dist/tools/x.html -> /tools/x ; dist/index.html -> / */
const routeOf = (f) => {
  const r = '/' + relative(DIST, f).split(sep).join('/').replace(/\.html$/, '')
  return r === '/index' ? '/' : r.replace(/\/index$/, '')
}
const routes = new Set(htmlFiles.map(routeOf))

const text = (html) => html
  .replace(/<script[\s\S]*?<\/script>/gi, ' ')
  .replace(/<style[\s\S]*?<\/style>/gi, ' ')
  .replace(/<[^>]+>/g, ' ')
  .replace(/&nbsp;/g, ' ')
  .replace(/\s+/g, ' ')

const all = (re, s) => [...s.matchAll(re)]

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
      if (m[1].slice(8).includes('//')) fail(page, `double slash in schema URL ${m[1]} (Flo D3)`)
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
    if (!/\bwidth=/.test(tag) || !/\bheight=/.test(tag)) fail(page, `<img> without width/height (CLS, Flo D9)`)
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
      try { jsBytes += statSync(join(DIST, src.slice(1))).size } catch { fail(page, `<script src="${src}"> has no file in dist/`) }
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
    const body = text(html).toLowerCase()
    for (const claim of BANNED_CLAIMS) {
      if (body.includes(claim)) fail(page, `contains unsupportable claim "${claim}" — see plan Global Constraints`)
    }
  }

  // --- B3: every internal link resolves ---------------------------------
  for (const m of all(/<a\b[^>]*href="(\/[^"#?]*)"/gi, html)) {
    const target = m[1].replace(/\/$/, '') || '/'
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
```

- [ ] **Step 2: Confirm Node can import the TypeScript constants**

`audit.mjs` imports `../src/consts.ts`. Node strips TypeScript types natively from v22.18
onward, so no flag and no build step is needed — the `verify` script stays plain
`node scripts/audit.mjs`. Verify it on this machine before relying on it:

```bash
cd site && node -e "import('./src/consts.ts').then(m => console.log('ok:', m.SITE, m.BANNED_CLAIMS.length))"
```

Expected: `ok: https://lunatrack.web.app 10`.
If this errors, the Node version is below the floor recorded in `package.json` — stop and report
it rather than adding a bundler.

- [ ] **Step 3: Close the one dangling schema reference that already exists**

The new dangling-reference assertion catches a real defect in `SeoHead.astro` from Task 2:
`mainEntityOfPage` points at `<canonical>#webpage`, but no `WebPage` node is ever emitted at
that `@id`. It does not surface yet — the article node only renders when a page passes the
`article` prop, which none do until Task 7 — so fix it now rather than letting Task 7 trip over
it. In `site/src/components/SeoHead.astro`, replace:

```ts
    mainEntityOfPage: { '@id': `${canonical}#webpage` },
```

with a plain URL, which schema.org accepts and which cannot dangle:

```ts
    mainEntityOfPage: canonical,   // a plain URL; never a pointer to a node we do not emit
```

- [ ] **Step 4: Run the audit**

```bash
cd site && npm run build && npm run verify
```

Expected: `audit passed: 1 pages, 1 routes, 0 problems`.

The Task 1 homepage already satisfies every rule — its title is 37 characters and its
description is 150, both in range, and Task 2 supplied the canonical, Open Graph tags and a
single clean JSON-LD block. A pass here is the correct result, but it proves almost nothing:
an assertion that has never failed is not known to be wired up. Step 4 fixes that.

- [ ] **Step 5: Prove every class of assertion actually bites**

Break one rule at a time, confirm the specific message, and revert before moving on.

**4a — a link to a page that does not exist (B3):**

```bash
cd site
sed -i '' 's|<h1 class="text-3xl font-bold">LunaTrack</h1>|<h1 class="text-3xl font-bold">LunaTrack</h1><a href="/does-not-exist">x</a>|' src/pages/index.astro
npm run build >/dev/null && npm run verify; echo "exit=$?"
sed -i '' 's|<a href="/does-not-exist">x</a>||' src/pages/index.astro
```

Expected: `✗ /: internal link to /does-not-exist has no built page (Flo B3)` and `exit=1`.

**4b — an over-long title (A4):**

```bash
cd site
sed -i '' 's|title="LunaTrack — period and cycle tracking"|title="LunaTrack — the period and cycle tracking app that keeps your data on your own device"|' src/pages/index.astro
npm run build >/dev/null && npm run verify; echo "exit=$?"
sed -i '' 's|title="LunaTrack — the period and cycle tracking app that keeps your data on your own device"|title="LunaTrack — period and cycle tracking"|' src/pages/index.astro
```

Expected: `✗ /: title is 85 chars (max 60)` and `exit=1`.

**4c — an unsupportable marketing claim (the Global Constraints table):**

```bash
cd site
sed -i '' 's|<h1 class="text-3xl font-bold">LunaTrack</h1>|<h1 class="text-3xl font-bold">LunaTrack — works with no account</h1>|' src/pages/index.astro
npm run build >/dev/null && npm run verify; echo "exit=$?"
sed -i '' 's|<h1 class="text-3xl font-bold">LunaTrack — works with no account</h1>|<h1 class="text-3xl font-bold">LunaTrack</h1>|' src/pages/index.astro
```

Expected: `✗ /: contains unsupportable claim "no account" — see plan Global Constraints`
and `exit=1`. This is the assertion that matters most; it is the one standing between a
rushed edit and a false claim on a health site.

**4d — confirm the tree is clean again:**

```bash
cd site && npm run build && npm run verify; echo "exit=$?"
git diff --stat src/pages/index.astro
```

Expected: `audit passed: 1 pages, 1 routes, 0 problems`, `exit=0`, and no diff.

- [ ] **Step 6: Commit**

```bash
git add site/
git commit -m "test(site): add build-time audit enforcing the flo.health defect register"
```

---

### Task 4: Cycle maths as a pure, unit-tested module

The only real logic on this site. It lives apart from the DOM so it can be tested in
milliseconds without a browser, and so the same functions can later be reused elsewhere.

**Files:**
- Create: `site/src/lib/cycle.ts`
- Test: `site/src/lib/cycle.test.ts`
- Create: `site/vitest.config.ts`

**Interfaces:**
- Consumes: nothing.
- Produces, all exported from `site/src/lib/cycle.ts`:
  - `MS_PER_DAY: number`
  - `parseISO(iso: string): number` — throws `RangeError` on a non-`YYYY-MM-DD` or invalid date
  - `formatISO(epochMs: number): string`
  - `addDays(epochMs: number, days: number): number`
  - `predictPeriods(lastStartISO: string, cycleLength: number, periodLength: number, count?: number): PeriodWindow[]` where `PeriodWindow = { start: string; end: string }`
  - `predictOvulation(lastStartISO: string, cycleLength: number): Ovulation` where `Ovulation = { nextPeriod: string; ovulation: string; fertileStart: string; fertileEnd: string }`
  - `analyseCycles(startISOs: string[]): CycleStats` where `CycleStats = { lengths: number[]; average: number; shortest: number; longest: number; variation: number; regularity: 'regular' | 'irregular' }`
  - `estimateDueDate(lmpISO: string, cycleLength: number, todayISO: string): DueDate` where `DueDate = { dueDate: string; conception: string; trimester2Start: string; trimester3Start: string; gestationalWeeks: number; gestationalDays: number }`

  Task 6 imports exactly these names.

**Domain constants, and why each is what it is:**

| Constant | Value | Rationale |
|---|---|---|
| `MIN_CYCLE` / `MAX_CYCLE` | 21 / 45 | The range the app already treats as plausible; outside it, an estimator should refuse rather than guess. |
| `MIN_PERIOD` / `MAX_PERIOD` | 1 / 10 | Same reasoning. |
| Luteal phase | 14 days, fixed | The standard simplification behind every consumer ovulation calculator. The luteal phase is the *less* variable half, which is why the subtraction is done from the next period rather than added to the last. The articles must say plainly that this is an assumption. |
| Fertile window | ovulation − 5 … ovulation + 1 | Six days: sperm viability (~5 days) plus the ovum's ~24 hours. |
| Gestation | 280 days + (cycleLength − 28) | Naegele's rule, cycle-length adjusted. Unadjusted Naegele silently assumes a 28-day cycle and is wrong by exactly the amount the user's cycle differs. |
| Regularity threshold | variation ≤ 7 days | A 7-day spread between shortest and longest is the most commonly cited consumer threshold. **This is a judgement call with clinical overtones — confirm the number with the user before shipping, and make the page say "this is not a diagnosis" regardless.** |

- [ ] **Step 1: Configure Vitest**

Create `site/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['src/lib/**/*.test.ts'],
    environment: 'node',
  },
})
```

- [ ] **Step 2: Write the failing tests**

Create `site/src/lib/cycle.test.ts`. Every expected value below was computed independently and
verified before being written down.

```ts
import { describe, it, expect } from 'vitest'
import {
  parseISO, formatISO, addDays,
  predictPeriods, predictOvulation, analyseCycles, estimateDueDate,
} from './cycle.ts'

describe('date primitives', () => {
  it('round-trips an ISO date through UTC midnight', () => {
    expect(formatISO(parseISO('2026-09-01'))).toBe('2026-09-01')
  })

  it('crosses a month boundary without drifting', () => {
    expect(formatISO(addDays(parseISO('2026-09-29'), 4))).toBe('2026-10-03')
  })

  it('handles a non-leap February', () => {
    expect(formatISO(addDays(parseISO('2026-02-28'), 1))).toBe('2026-03-01')
  })

  it('rejects a malformed date', () => {
    expect(() => parseISO('01/09/2026')).toThrow(RangeError)
  })

  it('rejects a date that does not exist', () => {
    expect(() => parseISO('2026-02-30')).toThrow(RangeError)
  })
})

describe('predictPeriods', () => {
  it('projects three cycles forward from the last start', () => {
    expect(predictPeriods('2026-09-01', 28, 5, 3)).toEqual([
      { start: '2026-09-29', end: '2026-10-03' },
      { start: '2026-10-27', end: '2026-10-31' },
      { start: '2026-11-24', end: '2026-11-28' },
    ])
  })

  it('makes a one-day period start and end on the same date', () => {
    expect(predictPeriods('2026-09-01', 28, 1, 1)).toEqual([
      { start: '2026-09-29', end: '2026-09-29' },
    ])
  })

  it('rejects a cycle length outside 21-45', () => {
    expect(() => predictPeriods('2026-09-01', 20, 5, 1)).toThrow(RangeError)
    expect(() => predictPeriods('2026-09-01', 46, 5, 1)).toThrow(RangeError)
  })

  it('rejects a period length outside 1-10', () => {
    expect(() => predictPeriods('2026-09-01', 28, 0, 1)).toThrow(RangeError)
    expect(() => predictPeriods('2026-09-01', 28, 11, 1)).toThrow(RangeError)
  })
})

describe('predictOvulation', () => {
  it('counts back fourteen days from the next period', () => {
    expect(predictOvulation('2026-09-01', 28)).toEqual({
      nextPeriod: '2026-09-29',
      ovulation: '2026-09-15',
      fertileStart: '2026-09-10',
      fertileEnd: '2026-09-16',
    })
  })

  it('moves ovulation later for a longer cycle, keeping the luteal phase fixed', () => {
    const r = predictOvulation('2026-09-01', 35)
    expect(r.nextPeriod).toBe('2026-10-06')
    expect(r.ovulation).toBe('2026-09-22')
  })
})

describe('analyseCycles', () => {
  it('derives lengths, average and spread from period start dates', () => {
    expect(analyseCycles([
      '2026-06-01', '2026-06-29', '2026-07-30', '2026-08-27',
    ])).toEqual({
      lengths: [28, 31, 28],
      average: 29,
      shortest: 28,
      longest: 31,
      variation: 3,
      regularity: 'regular',
    })
  })

  it('calls a spread wider than seven days irregular', () => {
    const r = analyseCycles(['2026-01-01', '2026-01-23', '2026-03-05'])
    expect(r.lengths).toEqual([22, 41])
    expect(r.variation).toBe(19)
    expect(r.regularity).toBe('irregular')
  })

  it('treats exactly seven days of spread as still regular', () => {
    const r = analyseCycles(['2026-01-01', '2026-01-25', '2026-02-25'])
    expect(r.variation).toBe(7)
    expect(r.regularity).toBe('regular')
  })

  it('sorts input that arrives out of order', () => {
    expect(analyseCycles(['2026-06-29', '2026-06-01']).lengths).toEqual([28])
  })

  it('needs at least two starts to compute a length', () => {
    expect(() => analyseCycles(['2026-06-01'])).toThrow(RangeError)
  })

  it('rejects duplicate dates, which would imply a zero-day cycle', () => {
    expect(() => analyseCycles(['2026-06-01', '2026-06-01'])).toThrow(RangeError)
  })
})

describe('estimateDueDate', () => {
  it('applies Naegele for a 28-day cycle', () => {
    expect(estimateDueDate('2026-01-01', 28, '2026-03-01')).toEqual({
      dueDate: '2026-10-08',
      conception: '2026-01-15',
      trimester2Start: '2026-04-09',
      trimester3Start: '2026-07-16',
      gestationalWeeks: 8,
      gestationalDays: 3,
    })
  })

  it('shifts the due date by the cycle-length difference', () => {
    expect(estimateDueDate('2026-01-01', 32, '2026-03-01').dueDate).toBe('2026-10-12')
  })

  it('reports zero gestation on the LMP date itself', () => {
    const r = estimateDueDate('2026-01-01', 28, '2026-01-01')
    expect(r.gestationalWeeks).toBe(0)
    expect(r.gestationalDays).toBe(0)
  })
})
```

- [ ] **Step 3: Run the tests and confirm they fail for the right reason**

```bash
cd site && npx vitest run
```

Expected: FAIL — `Failed to resolve import "./cycle.ts"`. Not an assertion failure; the module
does not exist yet.

- [ ] **Step 4: Implement the module**

Create `site/src/lib/cycle.ts`. All arithmetic is in UTC. Using local dates here would make the
result depend on the visitor's timezone and shift by a day across a DST boundary.

```ts
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
```

- [ ] **Step 5: Run the tests and confirm they pass**

```bash
cd site && npx vitest run
```

Expected: `Test Files 1 passed`, `Tests 20 passed`.

- [ ] **Step 6: Commit**

```bash
git add site/
git commit -m "feat(site): add unit-tested cycle maths for the calculators"
```

---

### Task 5: Shared chrome and the six core pages

**Files:**
- Create: `site/src/components/Header.astro`, `Footer.astro`, `Disclaimer.astro`
- Create: `site/src/pages/features.astro`, `privacy.astro`, `download.astro`, `privacy-policy.astro`, `terms.astro`, `404.astro`
- Modify: `site/src/pages/index.astro`, `site/src/layouts/Base.astro`

**Interfaces:**
- Consumes: `Base.astro` (Task 2), `NAV`/`ORG` from `consts.ts` (Task 1).
- Produces: `Header.astro` and `Footer.astro` (no props); `Disclaimer.astro` accepting `{ kind: 'tool' | 'article' }`. Tasks 6 and 7 use all three.

**Internal-linking rule for this task.** Teardown finding B1: Flo's homepage spends 11 links on
`/tools` and exactly 1 on a 431-URL article library, and B2 found 59–69% of every page's links
are nav/footer boilerplate. The homepage here must carry **contextual** links — in prose, inside
`<main>` — to all four calculators and at least three articles, over and above whatever the
header and footer repeat. With 18 URLs the whole site is within two clicks of the homepage;
the point is to keep it that way as the site grows.

- [ ] **Step 1: Build the header**

Create `site/src/components/Header.astro`:

```astro
---
import { NAV, ORG } from '../consts.ts'
const path = Astro.url.pathname.replace(/\/$/, '') || '/'
---
<header class="border-b border-outline">
  <nav aria-label="Main" class="mx-auto flex max-w-5xl flex-wrap items-center gap-4 px-4 py-4">
    <a href="/" class="font-bold text-lg">{ORG.name}</a>
    <ul class="flex flex-wrap gap-4 text-sm">
      {NAV.map((item) => (
        <li>
          <a
            href={item.href}
            aria-current={path === item.href ? 'page' : undefined}
            class="hover:underline"
          >{item.label}</a>
        </li>
      ))}
    </ul>
  </nav>
</header>
```

A real `<nav>` with an `aria-label` — Flo ships its navigation in unlabelled `<div>`s (A4-low).

- [ ] **Step 2: Build the footer and the disclaimer**

Create `site/src/components/Footer.astro`:

```astro
---
import { ORG } from '../consts.ts'
const year = new Date().getFullYear()
---
<footer class="mt-16 border-t border-outline">
  <nav aria-label="Footer" class="mx-auto max-w-5xl px-4 py-8 text-sm">
    <ul class="flex flex-wrap gap-4">
      <li><a href="/features" class="hover:underline">Features</a></li>
      <li><a href="/privacy" class="hover:underline">Your data</a></li>
      <li><a href="/privacy-policy" class="hover:underline">Privacy policy</a></li>
      <li><a href="/terms" class="hover:underline">Terms</a></li>
    </ul>
    <p class="mt-4 opacity-70">© {year} {ORG.name}. Not a medical device.</p>
  </nav>
</footer>
```

Create `site/src/components/Disclaimer.astro`:

```astro
---
interface Props { kind: 'tool' | 'article' }
const { kind } = Astro.props as Props
const text = kind === 'tool'
  ? 'This calculator gives an estimate based on averages. It is not a diagnosis, not contraception, and not a substitute for advice from a doctor or midwife.'
  : 'This article is general information, not medical advice. If something about your cycle worries you, speak to a doctor.'
---
<aside role="note" class="my-8 rounded-lg border border-outline bg-surface-tint p-4 text-sm dark:bg-surface-dark-2">
  <strong>Please read:</strong> {text}
</aside>
```

- [ ] **Step 3: Wire the chrome into the layout**

In `site/src/layouts/Base.astro`, import `Header` and `Footer` and place them around the
existing `<main>`:

```astro
  <body class="bg-surface text-primary dark:bg-surface-dark dark:text-white">
    <Header />
    <main class="mx-auto max-w-5xl px-4 py-8">
      <slot />
    </main>
    <Footer />
  </body>
```

- [ ] **Step 4: Write the six core pages**

Each uses `Base` and passes `title` (≤60 chars), `description` (70–155 chars) and `path`.
Copy must obey the Global Constraints positioning table — the audit enforces it.

`site/src/pages/features.astro` — what the app does, mapped to shipped features: predictions,
symptom and mood logging, medication marks, weight, BBT, ovulation tests, reminders, app lock,
doctor-ready PDF export, photo timeline (noting descriptions are off by default).

`site/src/pages/privacy.astro` — the plain-language data page. It must name, in this order:
the account requirement, Firebase cloud sync and that stored data is readable by the operator,
Google AdMob with non-personalised ads and the ad-free screens, and Gemini photo descriptions
being off until enabled. Then link to `/privacy-policy` for the full text. A data page that
omits the ad SDK is worth less than no data page (spec D8).

`site/src/pages/download.astro` — Google Play badge only. **Do not render an App Store badge**;
iOS availability is unconfirmed (spec open question). Link to `/features` and `/privacy`.

`site/src/pages/privacy-policy.astro` — renders the existing `PRIVACY_POLICY.md` from the repo
root. **Never copy the file into `site/`**: two copies of a legal document drift, and the stale
one is the one a user reads. Import it, in this order of preference:

1. `import { Content } from '../../../PRIVACY_POLICY.md'` — Astro renders it directly.
2. If Vite refuses the out-of-root path, add `vite: { server: { fs: { allow: ['..'] } } }` to
   `astro.config.mjs` and retry.
3. If it still fails, report **BLOCKED**. Do not duplicate the file to work around it.

Strip the `> ⚠️ Before publishing` reviewer block at `PRIVACY_POLICY.md:13-20` — it is an
internal to-do list, not policy text. Filter it at render time rather than editing the source
file, which the Play Console listing depends on.

`site/src/pages/terms.astro` — plain terms: no warranty, not a medical device, not contraception,
age requirement, Play billing governs purchases, contact address.

`site/src/pages/404.astro` — short, with links to `/`, `/tools` and `/articles`.

- [ ] **Step 5: Rewrite the homepage with a real link budget**

`site/src/pages/index.astro` gains, inside `<main>`: a headline built on the permitted claims,
a contextual prose link to each of the four calculators, contextual links to at least three
articles, and a link to `/privacy` and `/download`. Keep the existing 150-character
description from Task 1 unless the new copy makes a better one; the audit enforces 70-155.

- [ ] **Step 6: Build, audit, and check the link budget by hand**

```bash
cd site && npm run build && npm run verify
```

Expected: `audit passed: 7 pages, 7 routes, 0 problems` — the six core pages plus `/404`.

`/tools` and `/articles` do not exist yet, so neither `NAV` (Task 1) nor the footer above links
to them. Do not add those links here; Task 6 adds `/tools` and Task 7 adds `/articles`, each
alongside the pages it creates. The audit treats a link to an unbuilt page as a failure, which
is what keeps this staged rather than aspirational.

Measure the boilerplate ratio the teardown used (B2):

```bash
cd site
node -e "
const fs=require('fs');const h=fs.readFileSync('dist/index.html','utf8');
const main=h.split('<main')[1].split('</main>')[0];
const n=s=>new Set([...s.matchAll(/href=\"(\/[^\"#?]*)\"/g)].map(m=>m[1])).size;
console.log('contextual links in <main>:',n(main),'| total on page:',n(h));
"
```

Expected at this task: **at least 5** unique contextual links in `<main>` — which is every
non-home route that exists so far (`/features`, `/privacy`, `/download`, `/privacy-policy`,
`/terms`). Five is the ceiling here, not a shortfall: `/tools` and `/articles` are not built
until Tasks 6 and 7. The target rises with the route count — **>=6 after Task 6** adds `/tools`,
**>=7 after Task 7** adds `/articles`.

If `<main>` has fewer links than the header and footer combined, the page is chrome with a
paragraph attached — rewrite it.

- [ ] **Step 8: Commit**

```bash
git add site/
git commit -m "feat(site): add site chrome and the six core pages"
```

---

### Task 6: Four calculators, each a full editorial page

**Files:**
- Create: `site/src/components/Calculator.astro`, `site/src/components/Faq.astro`
- Create: `site/src/layouts/Tool.astro`
- Create: `site/src/pages/tools/index.astro`
- Create: `site/src/pages/tools/period-calculator.astro`, `ovulation-calculator.astro`, `cycle-length-calculator.astro`, `due-date-calculator.astro`

**Interfaces:**
- Consumes: every export of `src/lib/cycle.ts` (Task 4); `Base.astro`, `Disclaimer.astro`, `SeoHead`'s `faq` and `breadcrumbs` props.
- Produces: `Tool.astro` accepting `{ title: string; description: string; path: string; faq: FaqEntry[] }` with named slots `widget` and default slot for prose.

**The load-bearing requirement: ~2,000 words of prose per page.** Teardown B9 measured Flo's
calculators at an average of **2,942 words**. That is why they rank where bare widgets do not.
A calculator page that is only a widget will not rank, and building four of them is the single
highest-leverage item in Part C of the teardown. Each page needs: what the calculator does,
how the maths works and its stated assumptions, how to read the result, what affects accuracy,
when the estimate is unreliable, when to see a clinician, and the FAQ block.

- [ ] **Step 1: Build the FAQ component**

Create `site/src/components/Faq.astro`. It renders the visible list; the *same array* is passed
to `SeoHead` for `FAQPage` schema, so the markup and the structured data cannot drift apart.

```astro
---
import type { FaqEntry } from '../types.ts'
interface Props { items: FaqEntry[] }
const { items } = Astro.props as Props
---
<section class="mt-12">
  <h2 class="text-2xl font-bold">Common questions</h2>
  <dl class="mt-4 space-y-6">
    {items.map((f) => (
      <div>
        <dt class="font-semibold">{f.q}</dt>
        <dd class="mt-1 opacity-90">{f.a}</dd>
      </div>
    ))}
  </dl>
</section>
```

- [ ] **Step 2: Build the calculator widget**

Create `site/src/components/Calculator.astro`. It takes a `kind` and renders the right inputs,
then an inline module script that imports the maths and wires the form. **No `fetch`, no
`sendBeacon`, no network call of any kind** — Task 3's audit fails the build if one appears.

```astro
---
interface Props { kind: 'period' | 'ovulation' | 'cycle-length' | 'due-date' }
const { kind } = Astro.props as Props
---
<form id="calc" data-kind={kind} class="rounded-card border border-outline p-4">
  <p class="mb-4 text-sm opacity-80">
    This runs entirely in your browser. The dates you type are never sent anywhere.
  </p>
  <noscript>
    <p class="mb-4 rounded-lg border border-outline bg-surface-tint p-3 text-sm">
      This calculator needs JavaScript, because the maths runs on your device rather
      than on a server. With JavaScript off it stays switched off deliberately, so
      your dates are never put into the address bar.
    </p>
  </noscript>

  <!--
    The whole control group ships disabled and the module below re-enables it.
    The form has no `action`, so any submit without JS would GET the current URL
    with every field appended — putting a menstrual date into the address bar,
    history and any bookmark. Gating the FIELDSET rather than just the submit
    button is deliberate: a disabled fieldset makes every control non-focusable
    and not a successful control, so there is nothing to type and nothing to
    serialise, and the guarantee does not rest on how a given browser handles
    implicit (Enter-key) submission with a disabled default button. The CSP is
    `script-src 'self'`, which rules out an inline onsubmit.
  -->
  <fieldset id="calc-fields" disabled class="m-0 border-0 p-0 disabled:opacity-60">

  {kind === 'cycle-length' ? (
    <fieldset>
      <legend class="font-semibold">The first day of your last few periods</legend>
      <input type="date" name="d1" required class="mt-2 block" />
      <input type="date" name="d2" required class="mt-2 block" />
      <input type="date" name="d3" class="mt-2 block" />
      <input type="date" name="d4" class="mt-2 block" />
    </fieldset>
  ) : (
    <label class="block font-semibold">
      First day of your last period
      <input type="date" name="last" required class="mt-2 block" />
    </label>
  )}

  {kind !== 'cycle-length' && (
    <label class="mt-4 block font-semibold">
      Average cycle length (days)
      <input type="number" name="cycle" min="21" max="45" value="28" required class="mt-2 block" />
    </label>
  )}

  {kind === 'period' && (
    <label class="mt-4 block font-semibold">
      How many days your period usually lasts
      <input type="number" name="period" min="1" max="10" value="5" required class="mt-2 block" />
    </label>
  )}

  <button type="submit" class="mt-6 h-btn-h rounded-btn bg-seed px-6 font-semibold text-primary">
    Calculate
  </button>
  </fieldset>

  <output id="result" class="mt-6 block" aria-live="polite"></output>
  <p id="error" role="alert" class="mt-2 text-menstrual"></p>
</form>

<script>
  import {
    predictPeriods, predictOvulation, analyseCycles, estimateDueDate, formatISO,
  } from '../lib/cycle.ts'

  const form = document.getElementById('calc') as HTMLFormElement
  // Safe to accept input now: the handler below keeps every value on this device.
  document.getElementById('calc-fields')?.removeAttribute('disabled')
  const out = document.getElementById('result')!
  const err = document.getElementById('error')!
  const kind = form.dataset.kind!

  const human = (iso: string) =>
    new Date(iso + 'T00:00:00Z').toLocaleDateString(undefined, {
      weekday: 'short', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC',
    })

  form.addEventListener('submit', (e) => {
    e.preventDefault()
    err.textContent = ''
    out.innerHTML = ''
    const f = new FormData(form)
    const num = (k: string) => Number(f.get(k))
    try {
      if (kind === 'period') {
        const rows = predictPeriods(String(f.get('last')), num('cycle'), num('period'), 3)
        out.innerHTML = '<h3 class="font-bold">Your next three periods</h3><ul>' +
          rows.map((r) => `<li>${human(r.start)} to ${human(r.end)}</li>`).join('') + '</ul>'
      } else if (kind === 'ovulation') {
        const r = predictOvulation(String(f.get('last')), num('cycle'))
        out.innerHTML =
          `<h3 class="font-bold">Estimated ovulation: ${human(r.ovulation)}</h3>` +
          `<p>Most fertile days: ${human(r.fertileStart)} to ${human(r.fertileEnd)}</p>` +
          `<p>Next period expected: ${human(r.nextPeriod)}</p>`
      } else if (kind === 'cycle-length') {
        const dates = ['d1', 'd2', 'd3', 'd4'].map((k) => String(f.get(k) ?? '')).filter(Boolean)
        const s = analyseCycles(dates)
        out.innerHTML =
          `<h3 class="font-bold">Average cycle: ${s.average} days</h3>` +
          `<p>Shortest ${s.shortest}, longest ${s.longest}, a spread of ${s.variation} days.</p>` +
          `<p>That pattern looks <strong>${s.regularity}</strong>. This is a description, not a diagnosis.</p>`
      } else {
        const r = estimateDueDate(String(f.get('last')), num('cycle'), formatISO(Date.now()))
        out.innerHTML =
          `<h3 class="font-bold">Estimated due date: ${human(r.dueDate)}</h3>` +
          `<p>You are about ${r.gestationalWeeks} weeks and ${r.gestationalDays} days along.</p>` +
          `<p>Second trimester from ${human(r.trimester2Start)}, third from ${human(r.trimester3Start)}.</p>`
      }
    } catch (e) {
      err.textContent = e instanceof Error ? e.message : 'Please check the values you entered.'
    }
  })
</script>
```

Astro compiles this `<script>` to a bundled module and emits a `<script src>` tag. The audit's
per-page JS budget (8192 bytes, Task 3) covers it.

- [ ] **Step 3: Build the Tool layout**

Create `site/src/layouts/Tool.astro`:

```astro
---
import Base from './Base.astro'
import Faq from '../components/Faq.astro'
import Disclaimer from '../components/Disclaimer.astro'
import type { FaqEntry } from '../types.ts'

interface Props { title: string; description: string; path: string; faq: FaqEntry[] }
const { title, description, path, faq } = Astro.props as Props
---
<Base
  title={title}
  description={description}
  path={path}
  faq={faq}
  breadcrumbs={[
    { name: 'Home', path: '/' },
    { name: 'Calculators', path: '/tools' },
    { name: title, path },
  ]}
>
  <h1 class="text-3xl font-bold">{title}</h1>
  <div class="mt-6"><slot name="widget" /></div>
  <Disclaimer kind="tool" />
  <article class="prose"><slot /></article>
  <Faq items={faq} />
</Base>
```

- [ ] **Step 4: Write the four calculator pages**

Each page imports `Tool` and `Calculator`, supplies a `faq` array of 5–7 real questions, and
writes **~2,000 words** into the default slot. Required sections per page, as `<h2>`:

| Page | Sections |
|---|---|
| `/tools/period-calculator` | How this works · What "cycle length" means and how to measure it · Why your dates will drift · What changes a cycle (illness, stress, travel, contraception, perimenopause) · When a late period is worth a doctor's visit · Tracking instead of guessing |
| `/tools/ovulation-calculator` | How the date is estimated · Why we count back from the next period, not forward from the last · The six-day fertile window and where it comes from · Signs that corroborate the estimate (BBT, cervical mucus, LH tests) · Why this is not contraception · When to seek advice |
| `/tools/cycle-length-calculator` | What this measures · How to count a cycle correctly (start to start) · What a typical range looks like · What "regular" means here and its limits · What makes cycles vary · What to bring to a doctor |
| `/tools/due-date-calculator` | Naegele's rule in plain English · Why cycle length changes the answer · Gestational vs conception age · Trimester boundaries · Why scans beat calculators · What the date does and does not mean |

Each page must link contextually to at least two other calculators and one article, and must
state explicitly that nothing entered is transmitted.

- [ ] **Step 5: Build the `/tools` index**

`site/src/pages/tools/index.astro` lists all four with a one-sentence description each, plus
~300 words on what these estimators can and cannot tell you.

Now that the route exists, add `/tools` to both nav surfaces: `{ href: '/tools', label:
'Calculators' }` after the `/features` entry in `NAV` (`src/consts.ts`), and
`<li><a href="/tools" class="hover:underline">Calculators</a></li>` after the Features item in
`Footer.astro`. Do **not** add `/articles` — that route arrives in Task 7.

- [ ] **Step 6: Verify word counts, then build and audit**

```bash
cd site && npm run build
for f in dist/tools/*.html; do
  w=$(sed -e 's/<script[^>]*>.*<\/script>//g' -e 's/<[^>]*>/ /g' "$f" | wc -w)
  echo "$w words  $f"
done
```

Expected: each of the four calculator pages ≥ 1800 words. `/tools/index.html` ≥ 300.
A page under 1800 has not met the requirement that makes it rank — write more, do not lower it.

```bash
cd site && npm run verify
```

Expected: `audit passed: 12 pages, 12 routes, 0 problems`.

Re-measure the homepage link budget now that `/tools` exists — the homepage must link it
contextually in prose, not only from the nav:

```bash
cd site && node -e "
const fs=require('fs');const h=fs.readFileSync('dist/index.html','utf8');
const main=h.split('<main')[1].split('</main>')[0];
console.log('unique contextual links:',new Set([...main.matchAll(/href=\"(\/[^\"#?]*)\"/g)].map(m=>m[1])).size);
"
```

Expected: **>=6**.

Confirm the calculators cannot leak an input:

```bash
grep -rlE 'fetch\(|sendBeacon|XMLHttpRequest' site/dist/tools/ | wc -l
```

Expected: `0`

- [ ] **Step 7: Test the maths in a real browser**

```bash
cd site && npm run preview
```

Open `http://localhost:4321/tools/period-calculator` and enter `2026-09-01`, cycle `28`,
period `5`. Expected output: `2026-09-29 to 2026-10-03`, `2026-10-27 to 2026-10-31`,
`2026-11-24 to 2026-11-28` — the exact values asserted in Task 4.
Then enter cycle `20`. Note what actually happens: the input carries `min="21" max="45"`, so a
standards-compliant browser blocks the submit with its OWN native validation bubble and the
custom message never runs. That is fine — native validation is the better first line — but it
means the `cycle.ts` `RangeError` copy is a BACKSTOP, not the normal path. To see the backstop,
test a value the native constraints cannot catch, such as clearing the date field's value via
devtools or submitting a malformed date; `#error` must then show the module's message rather
than leaving a blank result.

- [ ] **Step 8: Commit**

```bash
git add site/
git commit -m "feat(site): add four client-side calculators with editorial pages"
```

---

### Task 7: The articles collection, with E-E-A-T enforced by the schema

**Files:**
- Create: `site/src/content.config.ts`
- Create: `site/src/components/ReviewNotice.astro`, `site/src/layouts/Article.astro`
- Create: `site/src/pages/articles/index.astro`, `site/src/pages/articles/[...slug].astro`
- Create: six files under `site/src/content/articles/`

**Interfaces:**
- Consumes: `Base.astro`, `Disclaimer.astro`, `SeoHead`'s `article` prop.
- Produces: the `articles` collection with the frontmatter contract below. Any later article
  that omits a required field fails the build rather than shipping unsourced health content.

> **Astro 7 note:** collections are configured in `src/content.config.ts` (repo root of `src/`,
> **not** `src/content/config.ts` as spec D3 shows — that path was the Astro 4 convention) and
> use the Content Layer `glob()` loader. Rendering is `await render(entry)`, not
> `entry.render()`.

- [ ] **Step 1: Define the collection schema**

Create `site/src/content.config.ts`:

```ts
import { defineCollection, z } from 'astro:content'
import { glob } from 'astro/loaders'
export { UNREVIEWED } from './consts.ts'

const articles = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/articles' }),
  schema: z.object({
    title: z.string().max(60),
    description: z.string().min(70).max(155),
    author: z.string().min(1),
    reviewedBy: z.string().min(1),
    datePublished: z.coerce.date(),
    dateModified: z.coerce.date(),
    sources: z.array(z.object({
      title: z.string().min(1),
      url: z.string().url(),
    })).min(2),
  }),
})

export const collections = { articles }
```

- [ ] **Step 2: Prove the schema actually rejects bad content**

Before writing real articles, confirm the gate bites. Create a deliberately broken file:

```bash
cd site && mkdir -p src/content/articles && cat > src/content/articles/_probe.md <<'EOF'
---
title: Probe
description: Too short
author: LunaTrack
reviewedBy: Not medically reviewed
datePublished: 2026-09-13
dateModified: 2026-09-13
sources: []
---
Body.
EOF
npm run build; echo "exit=$?"
```

Expected: build FAILS, naming `description` (too short) and `sources` (needs ≥2). Then remove it:

```bash
rm site/src/content/articles/_probe.md
```

- [ ] **Step 3: Build the review notice and article layout**

Create `site/src/components/ReviewNotice.astro`:

```astro
---
import { UNREVIEWED } from '../consts.ts'
interface Props { reviewedBy: string }
const { reviewedBy } = Astro.props as Props
---
{reviewedBy === UNREVIEWED ? (
  <p class="rounded-lg border border-luteal bg-surface-tint p-3 text-sm dark:bg-surface-dark-2">
    <strong>Not medically reviewed.</strong> This article was written and fact-checked against the
    sources listed at the end, but no clinician has reviewed it. We would rather say so than imply
    a review that did not happen.
  </p>
) : (
  <p class="text-sm opacity-80">Medically reviewed by {reviewedBy}</p>
)}
```

Create `site/src/layouts/Article.astro`:

```astro
---
import Base from './Base.astro'
import Disclaimer from '../components/Disclaimer.astro'
import ReviewNotice from '../components/ReviewNotice.astro'

interface Source { title: string; url: string }
interface Props {
  title: string; description: string; path: string
  author: string; reviewedBy: string
  datePublished: Date; dateModified: Date
  sources: Source[]
}
const p = Astro.props as Props
const fmt = (d: Date) => d.toISOString().slice(0, 10)
---
<Base
  title={p.title}
  description={p.description}
  path={p.path}
  type="article"
  article={{
    author: p.author, reviewedBy: p.reviewedBy,
    datePublished: p.datePublished, dateModified: p.dateModified,
  }}
  breadcrumbs={[
    { name: 'Home', path: '/' },
    { name: 'Articles', path: '/articles' },
    { name: p.title, path: p.path },
  ]}
>
  <h1 class="text-3xl font-bold">{p.title}</h1>
  <p class="mt-2 text-sm opacity-80">
    By {p.author} · Published <time datetime={fmt(p.datePublished)}>{fmt(p.datePublished)}</time>
    · Updated <time datetime={fmt(p.dateModified)}>{fmt(p.dateModified)}</time>
  </p>
  <div class="mt-4"><ReviewNotice reviewedBy={p.reviewedBy} /></div>
  <Disclaimer kind="article" />
  <article class="prose"><slot /></article>
  <section class="mt-12">
    <h2 class="text-2xl font-bold">Sources</h2>
    <ul class="mt-4 list-disc pl-5">
      {p.sources.map((s) => (
        <li><a href={s.url} rel="noopener" class="underline">{s.title}</a></li>
      ))}
    </ul>
  </section>
</Base>
```

The source links are **dofollow on purpose**. Teardown A5 found Flo places 48 mostly-dofollow
citations on a single article. On YMYL content, demonstrable sourcing is worth more than hoarded
link equity.

- [ ] **Step 4: Build the article routes**

Create `site/src/pages/articles/[...slug].astro`:

```astro
---
import { getCollection, render } from 'astro:content'
import Article from '../../layouts/Article.astro'

export async function getStaticPaths() {
  const entries = await getCollection('articles')
  return entries.map((entry) => ({ params: { slug: entry.id }, props: { entry } }))
}

const { entry } = Astro.props
const { Content } = await render(entry)
const d = entry.data
---
<Article
  title={d.title} description={d.description} path={`/articles/${entry.id}`}
  author={d.author} reviewedBy={d.reviewedBy}
  datePublished={d.datePublished} dateModified={d.dateModified}
  sources={d.sources}
>
  <Content />
</Article>
```

Create `site/src/pages/articles/index.astro` listing all six, newest first, each with its
title, description and published date, plus ~250 words introducing the library.

- [ ] **Step 5: Write the six articles**

All six use `author: LunaTrack` and `reviewedBy: Not medically reviewed` (spec D4), with
`datePublished: 2026-09-13`. Target **~2,000 words each**.

| File | Angle | Verified sources to cite |
|---|---|---|
| `how-period-predictions-work.md` | Predictions are estimates from your own averages; why they drift; what makes them better | NHS Periods; Cleveland Clinic Menstrual Cycle |
| `what-cycle-length-is-normal.md` | Typical ranges, normal variation, what irregular means, when to seek advice | NHS Irregular periods; NHS Periods; ACOG Your first period |
| `what-symptoms-are-worth-tracking.md` | Maps to the app's tracking categories; which symptoms carry signal | NHS PMS; NHS Period pain; ACOG Dysmenorrhea |
| `cycle-phases-explained.md` | Menstrual, follicular, ovulatory, luteal — supports the app's phase palette | Cleveland Clinic Menstrual Cycle; Cleveland Clinic Ovulation |
| `what-to-check-in-a-period-tracker-privacy-policy.md` | A checklist a reader can apply **to LunaTrack too**, and does — including where LunaTrack scores badly | ICO right to erasure; NHS Periods |
| `preparing-a-doctor-ready-cycle-summary.md` | Maps to the shipped PDF export; what a clinician actually wants | NHS Heavy periods; NHS Period pain; ACOG Dysmenorrhea |

**Verified source URLs** (each returned HTTP 200 on 2026-09-13; do not substitute an
unverified URL):

```
NHS Periods                    https://www.nhs.uk/conditions/periods/
NHS Irregular periods          https://www.nhs.uk/symptoms/irregular-periods/
NHS Heavy periods              https://www.nhs.uk/conditions/heavy-periods/
NHS Period pain                https://www.nhs.uk/conditions/period-pain/
NHS PMS                        https://www.nhs.uk/conditions/pre-menstrual-syndrome/
NHS Due date calculator        https://www.nhs.uk/pregnancy/finding-out/due-date-calculator/
Cleveland Clinic Menstrual     https://my.clevelandclinic.org/health/articles/10132-menstrual-cycle
Cleveland Clinic Ovulation     https://my.clevelandclinic.org/health/body/23439-ovulation
ACOG Your first period         https://www.acog.org/womens-health/faqs/your-first-period
ACOG Dysmenorrhea              https://www.acog.org/womens-health/faqs/dysmenorrhea-painful-periods
WHO Infertility                https://www.who.int/news-room/fact-sheets/detail/infertility
ICO Right to erasure           https://ico.org.uk/for-the-public/your-right-to-get-your-data-deleted/
```

Mayo Clinic URLs are deliberately absent: mayoclinic.org returns HTTP 403 to non-browser
clients, so they could not be verified. Do not cite a URL you have not confirmed resolves.

**The privacy-checklist article must apply its own checklist to LunaTrack and publish the
result, including the parts LunaTrack fails** (readable cloud storage, an account requirement,
an ad SDK). An article scoring rivals while exempting itself is the exact move that makes
Flo's `/privacy-portal` content untrustworthy, and a reader who notices will trust nothing
else on the site.

Each article links contextually to at least two other articles and one calculator (B3: keep
everything within two clicks).

- [ ] **Step 6: Add `/articles` to both nav surfaces**

The route now exists, so link it: `{ href: '/articles', label: 'Articles' }` after the `/tools`
entry in `NAV` (`src/consts.ts`), and
`<li><a href="/articles" class="hover:underline">Articles</a></li>` after the Calculators item
in `Footer.astro`. This completes the nav; no later task changes it.

- [ ] **Step 7: Verify every citation still resolves**

A dead citation on health content is worse than no citation. ACOG serves soft 404s with a
200 status, so check the effective URL too:

```bash
cd site
grep -rhoE 'https?://[^ ")]+' src/content/articles/ | sort -u | while read -r u; do
  r=$(curl -o /dev/null -sL -w '%{http_code}|%{url_effective}' -A 'Mozilla/5.0' --max-time 20 "$u")
  case "${r#*|}" in *error/404*) r="SOFT404";; esac
  echo "${r%%|*}  $u"
done
```

Expected: every line reads `200`. Any `404`, `SOFT404` or `403` must be replaced from the
verified list above before committing.

- [ ] **Step 8: Build, check word counts, and audit**

```bash
cd site && npm run build
for f in dist/articles/*.html; do
  w=$(sed -e 's/<script[^>]*>.*<\/script>//g' -e 's/<[^>]*>/ /g' "$f" | wc -w)
  echo "$w words  $f"
done
npm run verify
```

Expected: each article ≥ 1800 words; `audit passed: 19 pages, 19 routes, 0 problems`
(18 public URLs plus `/404`, matching the spec's non-goals section).

Confirm zero JavaScript still ships on article pages — the whole point of D1:

```bash
grep -c '<script' site/dist/articles/how-period-predictions-work.html
```

Expected: `1` (the JSON-LD block only).

- [ ] **Step 9: Commit**

```bash
git add site/
git commit -m "feat(site): add six sourced articles behind a build-enforced E-E-A-T schema"
```

---

### Task 8: Firebase Hosting, canonicalisation, and a preview deploy

**Files:**
- Modify: `firebase.json` (add a `hosting` key alongside the existing `firestore`, `storage`, `emulators`, `flutter` keys)

**Interfaces:**
- Consumes: `site/dist/` produced by Task 7.
- Produces: a live preview URL. Nothing else in the repo depends on this task.

**Do not touch** the existing `firestore`, `storage`, `emulators` or `flutter` keys. The Flutter
app reads them and the emulator scripts depend on the ports.

- [ ] **Step 1: Force island scripts external, so the CSP cannot break them**

Astro inlines small island bundles as `<script type="module">…</script>`. The `Content-Security-Policy`
in Step 2 sends `script-src 'self'`, which blocks inline scripts — so shipping as-is would leave all
four calculators dead in production while they still worked locally, with nothing in the build to
catch it. In `site/astro.config.mjs` change the `vite` line to:

```js
  vite: { plugins: [tailwindcss()], build: { assetsInlineLimit: 0 } },
```

Rebuild and confirm the script is now a real file:

```bash
cd site && npm run build
grep -o '<script[^>]*src="[^"]*"' dist/tools/period-calculator.html
find dist -name '*.js' | wc -l
npm run verify
```

Expected: a `src="/_astro/…js"` attribute, `1` JS file, and the audit still passing 19/19.

- [ ] **Step 2: Add the hosting block**

Insert into `firebase.json` before the closing brace. Astro is configured with
`build.format: 'file'`, so it emits `tools/period-calculator.html`; `cleanUrls` serves that at
`/tools/period-calculator` and 301s the `.html` form to it.

```jsonc
"hosting": {
  "public": "site/dist",
  "cleanUrls": true,
  "trailingSlash": false,
  "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
  "redirects": [
    { "source": "/calculators", "destination": "/tools", "type": 301 },
    { "source": "/blog", "destination": "/articles", "type": 301 },
    { "source": "/privacy.html", "destination": "/privacy", "type": 301 }
  ],
  "headers": [
    {
      "source": "**",
      "headers": [
        { "key": "Strict-Transport-Security", "value": "max-age=31536000; includeSubDomains; preload" },
        { "key": "X-Content-Type-Options", "value": "nosniff" },
        { "key": "X-Frame-Options", "value": "SAMEORIGIN" },
        { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
        { "key": "Permissions-Policy", "value": "camera=(), microphone=(), geolocation=(), interest-cohort=()" },
        { "key": "Content-Security-Policy", "value": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'none'; frame-ancestors 'self'; base-uri 'self'; form-action 'none'" }
      ]
    },
    {
      "source": "**/*.@(js|css|woff2|webp|avif|svg)",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }]
    },
    {
      "source": "**/*.html",
      "headers": [{ "key": "Cache-Control", "value": "public, max-age=0, must-revalidate" }]
    }
  ]
}
```

Two deliberate improvements on flo.health, which passes 8 of 8 canonicalisation tests (A2) but
ships a deprecated `Feature-Policy` and **no CSP at all** (A3): `Permissions-Policy` replaces
`Feature-Policy`, and a real CSP is sent. `connect-src 'none'` is the belt to the audit's
braces — even if a future edit added a `fetch`, the browser would block it, so a cycle date
cannot leave the page.

- [ ] **Step 3: Validate the JSON before deploying anything**

```bash
cd /Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track
node -e "const c=require('./firebase.json'); console.log(Object.keys(c).join(',')); console.log('public:', c.hosting.public)"
```

Expected: `firestore,storage,emulators,flutter,hosting` and `public: site/dist`.
If any pre-existing key is missing, restore it with `git checkout firebase.json` and redo Step 1.

- [ ] **Step 4: Deploy to a preview channel, never to live**

```bash
cd site && npm run build && npm run verify
cd /Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track
firebase hosting:channel:deploy preview --project teddy-2-20649 --expires 7d
```

Expected: a `https://teddy-2-20649--preview-*.web.app` URL.
If the CLI is not authenticated, stop and ask the user to run `! firebase login`.

- [ ] **Step 5: Test canonicalisation against the preview URL**

Set `URL` to the preview host, then run the same checks the teardown ran against flo.health (A2):

```bash
URL="https://teddy-2-20649--preview-xxxx.web.app"   # paste the real one
probe() { printf '%-46s %s\n' "$1" "$(curl -o /dev/null -s -w '%{http_code} -> %{redirect_url}' "$URL$1")"; }
probe "/tools/period-calculator"        # expect 200
probe "/tools/period-calculator.html"   # expect 301 -> /tools/period-calculator
probe "/tools/period-calculator/"       # expect 301 -> /tools/period-calculator
probe "/calculators"                    # expect 301 -> /tools
probe "/no-such-page"                   # expect 404
echo "--- headers ---"
curl -sI "$URL/" | grep -iE 'strict-transport|content-security|x-frame|permissions-policy|referrer'
```

Expected: the five status codes above, and all five security headers present.

- [ ] **Step 6: Manual checks on the preview URL**

- 400px viewport: no horizontal scroll on any of the 18 pages.
- Dark mode renders with the `surface-dark` tokens, not an unstyled white flash.
- Keyboard only: tab through the header, a calculator form and submit it.
- Run all four calculators against the Task 4 worked examples one more time, on the deployed
  build rather than the local preview.

- [ ] **Step 7: Confirm the Flutter app is still untouched**

```bash
cd /Users/macmini/StudioProjects/ai/menstrultrack/menstrul_track
git diff --stat HEAD -- lib/ test/ pubspec.yaml
flutter analyze
flutter test
```

Expected: no diff in `lib/`, `test/` or `pubspec.yaml`; `flutter analyze` clean; the full
suite green. `site/` is a sibling directory with its own toolchain and must not have moved
a single Dart file.

- [ ] **Step 8: Commit**

```bash
git add firebase.json
git commit -m "feat(site): serve the marketing site from Firebase Hosting with CSP and canonical redirects"
```

**Going live is a separate, explicit decision.** `firebase deploy --only hosting` is not part of
this plan; ask the user before running it, and resolve the domain open question first.

---

## Open questions carried forward from the spec

1. **Domain.** `SITE` in `site/src/consts.ts` is set to `https://lunatrack.web.app`. Changing it
   is one line plus a redirect entry; do it before the first live deploy, not after, so no
   canonical URL ever changes after being indexed.
2. **Analytics.** Still deliberately unspecified. Note that the CSP in Task 8 sets
   `connect-src 'none'`, so adding any analytics script is a conscious edit to two files rather
   than something that can slip in.
3. **App Store badge.** `/download` ships Google Play only until iOS availability is confirmed.
4. **Regularity threshold** (Task 4): the ≤7-day variation rule is a judgement call with
   clinical overtones. Confirm with the user before the first live deploy.
5. **Medical review.** Every article ships with the honest `Not medically reviewed` notice. When
   a clinician is engaged, replace the sentinel in each file's frontmatter; `reviewedBy` and
   `MedicalWebPage` then emit automatically with no code change (spec D4).

## Self-review notes

- **Spec coverage.** D1→Task 1; D2→Task 2; D3→Task 7 Step 1; D4→Task 7 Steps 1, 3, 5; D5→Task 1
  Step 5; D6→Tasks 4 and 6; D7→Task 7 Step 5; D8→Global Constraints and Task 5 Step 4;
  D9→Task 8; D10→Task 3.
- **Three spec deviations, each recorded at the point of use:** Tailwind 4 via `@tailwindcss/vite`
  instead of the deprecated `@astrojs/tailwind` (Global Constraints); `src/content.config.ts`
  instead of `src/content/config.ts`, which is the Astro 4 path (Task 7); and the D8 positioning
  correction (Global Constraints), which is the only one that changes what the site *says*.
- **Type consistency.** `FaqEntry`, `ArticleMeta` and `Crumb` are defined once in `SeoHead.astro`
  and imported by `Base.astro`, `Tool.astro` and `Faq.astro`. The eight exports of `cycle.ts`
  named in Task 4 are exactly the names imported in Task 6 Step 2. `UNREVIEWED` is defined in
  `content.config.ts` and imported by `ReviewNotice.astro`; the identical literal string in
  `SeoHead.astro` is intentional, so that the SEO component has no dependency on the content
  layer — if the sentinel ever changes, both must change.
- **Page-count arithmetic.** Task 5 → 7 routes, Task 6 → 12, Task 7 → 19. Nineteen built routes
  is the spec's 18 public URLs plus `/404`.
