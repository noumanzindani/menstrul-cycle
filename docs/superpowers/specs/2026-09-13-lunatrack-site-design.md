# LunaTrack marketing site — design

Date: 2026-09-13
Status: approved design, not yet implemented
Origin: derived from `docs/research/flo-health-teardown.md` — a full technical + internal-linking
audit of flo.health crawled the same day. Defect IDs referenced below (D1–D10, A1–A5, B1–B10)
are that document's, not this one's.

## Problem

LunaTrack has no web presence. The app is complete and tested (906 tests) but is discoverable
only by store search, which means it competes on store-listing keywords against an incumbent
that owns the category's organic search surface.

The flo.health teardown established what that incumbent actually does. Two findings drive this
design:

1. **Flo's conversion engine is calculators, not articles.** Their homepage gives all 11
   `/tools/*` pages their own internal link, while the 431-URL `/menstrual-cycle` library gets
   exactly one (B1). Each calculator is a ~2,942-word editorial page with `FAQPage` schema and a
   small widget attached — the widget earns the click, the prose earns the ranking (B9).
2. **The privacy position is already occupied.** Flo has Anonymous Mode, a whitepaper, ISO 27701,
   open-sourced privacy tech and post-Roe explainers, and publishes the criteria by which rivals
   are judged (B10). A "we're more private" pitch loses a paper comparison LunaTrack cannot
   currently win.

Flo also carries ten verified defects, most of them structural (D1–D10). A greenfield site can
make those defects *unrepresentable* rather than merely avoided — which is the organising idea of
this design.

## Non-goals

- **Not a clone of flo.health.** Flo runs 3,035 URLs, 1,704 articles, 191 bio pages and a
  newsroom. That is a staffed editorial operation. v1 is **18 URLs**: 6 core pages
  (home, features, privacy, download, privacy-policy, terms) + `/tools` index + 4 calculators
  + `/articles` index + 6 articles.
- **No Flutter Web.** A `web/` scaffold exists in this repo; it is not used here. Flutter Web
  renders to canvas with no crawlable HTML and would forfeit every finding in the teardown.
- **No i18n in v1.** Flo's own data shows 13 of its 21 locales have UI but no article library
  (B7). One language, complete, beats five hollow ones.
- **No CMS, no server, no database.** Static output only.
- **No blog, newsroom, author-bio pages, or quizzes in v1.** Deferred.
- **No change to the Flutter app.** This adds a sibling directory and one `firebase.json` key.

## Decisions

### D1 — Astro in a self-contained `site/`, not Flutter Web and not hand-written HTML

```
site/                    ← own package.json; Dart and Node toolchains never mix
  astro.config.mjs
  src/{components,content,layouts,pages,styles}
  scripts/audit.mjs
```

Astro was chosen over Eleventy, Next.js static export and hand-written HTML because it ships
**zero JavaScript by default** and hydrates only components explicitly marked as islands. Article
pages therefore ship 0 KB of JS while calculator pages ship only their own widget. This is the
direct structural answer to Flo's D4 (920 KB–1.2 MB of inline `<script>` per document, 70–84% of
each page).

Hand-written HTML was the serious alternative — zero new dependencies, and the existing Stitch
mockups are already Tailwind. It was rejected on maintenance: a nav change would mean editing
every file, and there is no path from it to 10+ markdown articles.

Node v24.12.0, npm 11.6.2 and Firebase CLI 15.22.4 are already installed, and `functions/`
establishes npm precedent in this repo (pinned to node 20 — independent of `site/`, no conflict).

`.gitignore` currently covers only `firebase_test/node_modules/`; it gains `site/node_modules/`
and `site/dist/`.

### D2 — One SEO emitter, sitewide

`src/components/SeoHead.astro` is the **single** source of `<title>`, meta description, canonical,
Open Graph, and every JSON-LD block. No page emits schema independently.

This exists specifically because of Flo's D2 and D3: two `WebSite` nodes both claiming
`@id: "#website"` with conflicting contents, and a `SearchAction` target of
`https://flo.health//search` — a double slash — present on every page type tested. Both are
duplicate-emitter bugs. With one emitter and all URLs built from a single `SITE` constant via
`new URL()`, neither can occur.

Emitted sitewide: one `Organization` (with `sameAs`, `logo` — Flo's D8 gap) and one `WebSite`.
Per page type: `Article`/`MedicalWebPage`, `FAQPage`, `BreadcrumbList`.

### D3 — Frontmatter schema makes E-E-A-T fields mandatory

```ts
// src/content/config.ts
const articles = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string().max(60),
    description: z.string().min(70).max(155),
    author: z.string(),
    reviewedBy: z.string(),                    // required — see D4
    datePublished: z.coerce.date(),            // required — Flo's D5
    dateModified: z.coerce.date(),
    sources: z.array(z.object({
      title: z.string(), url: z.string().url(),
    })).min(2),                                // no unsourced health content
  }),
})
```

Astro validates content collections at build time, so an article missing its reviewer, its
publication date or its sources **fails the build**. Flo ships health content with no
`datePublished` at all, a `dateModified` two years out of step with its own sitemap `lastmod`
(D5), and no `reviewedBy` despite rendering a visible "Medically reviewed by" byline (D6). Making
these fields required costs nothing now and is nearly impossible to retrofit later.

`title` and `description` carry length bounds so SERP truncation is caught at build, not in
Search Console months later.

### D4 — `reviewedBy` is required, and v1 fills it honestly

v1 sets `reviewedBy: "Not medically reviewed"`, renders a visible notice on every article, and
omits the `reviewedBy` property from emitted schema when it holds that sentinel value.

The field stays **required** rather than optional so that supplying a real reviewer is a
one-line change per article rather than a schema migration. Fabricating a clinician's name would
invert the entire point of the E-E-A-T work and is a real trust and liability problem; shipping
without the notice would be worse. When a named clinician is available, the sentinel is replaced,
the notice disappears, and `reviewedBy` + `MedicalWebPage` begin emitting — no other change.

### D5 — Tailwind as a build integration, never the CDN

The 42 Stitch mockups in `docs/design/stitch/` load `https://cdn.tailwindcss.com`, which ships a
full JIT compiler to the browser. That is Flo's D4 mistake in miniature and must not survive into
production. `@astrojs/tailwind` compiles and purges at build time instead.

The mockups' `tailwind.config` is ported verbatim so the site is visually continuous with the app.
Tokens are taken from `lib/theme/app_theme.dart`, which is authoritative:

| Token | Value | Source |
|---|---|---|
| seed | `#F7A8C4` | `app_theme.dart:92` |
| ink / `onSurface` | `#3A2A30` | `app_theme.dart:107` |
| surface | `#FFFFFF` | Stitch config |
| menstrual / follicular | `#D64F6E` / `#6FB3A8` | `app_theme.dart:34-35` |
| ovulatory / luteal | `#7E9CE8` / `#D9A15B` | `app_theme.dart:36-37` |
| fertile / predicted | `#9CCFC6` / `#B0A8C0` | `app_theme.dart:38-39` |
| type | Public Sans 400/500/600/700 | Stitch config |
| radii | 0.5 / 1 / 1.5rem / full | Stitch config |

Fonts self-host via `@fontsource/public-sans` rather than Google Fonts, removing a third-party
connection from a health site — a privacy detail worth being correct about given the positioning.

### D6 — Four calculators, each a full editorial page, computing client-side only

`/tools/{period,ovulation,cycle-length,due-date}-calculator`, plus a `/tools` index.

Each is a `client:visible` island plus **~2,000 words** of real content and `FAQPage` schema. The
word count is the load-bearing part: B9 found Flo's calculators average 2,942 words, which is why
they rank where bare widgets do not.

All four compute **entirely in the browser**. No input is transmitted, stored, or logged — no
analytics event carries a cycle date. This is stated plainly on each page. For a product whose
differentiator is local-first data handling, a calculator that posted menstrual dates to a server
would be self-refuting.

Every page carries a visible non-diagnostic disclaimer. These are estimators, not medical devices.

### D7 — Six articles, positioned beside Flo rather than against it

| Slug | Angle |
|---|---|
| `how-period-predictions-work` | Why predictions are estimates — sets honest expectations |
| `what-cycle-length-is-normal` | Ranges, variation, when to see a clinician |
| `what-symptoms-are-worth-tracking` | Maps to the app's tracking categories |
| `cycle-phases-explained` | Supports the phase palette used in-app |
| `what-to-check-in-a-period-tracker-privacy-policy` | Direct counter to Flo's own framing article (B10) |
| `preparing-a-doctor-ready-cycle-summary` | Maps to the existing PDF export feature |

Each carries ≥2 dofollow citations to NHS / Mayo / Cleveland Clinic / ACOG. Flo places 48 mostly
-dofollow outbound citations on a single article (A5); on YMYL content, demonstrable sourcing
outranks hoarded link equity. Four of the six map onto shipped app features, so the content
supports the product rather than existing beside it.

### D8 — Positioning: local-first, no account, free — not "private"

Per Part C of the teardown. The three claims that survive comparison with Flo are: **works with
no account** (Flo requires one; Anonymous Mode is a paid-tier posture), **free** (Flo Premium is
paid), and **no data sale**.

`/privacy` discloses AdMob, Firebase sync and Gemini photo descriptions in plain language,
before a reviewer discovers them. Naming them first is the only version of this page that
survives scrutiny; a privacy page that omits the ad SDK is worth less than no page.

The existing `PRIVACY_POLICY.md` is reused as `/privacy-policy` rather than rewritten.

### D9 — Firebase Hosting, with canonicalisation in config

`firebase.json` gains a `hosting` block alongside the existing `firestore` and `storage` keys.
Project `teddy-2-20649` is already configured.

```jsonc
"hosting": {
  "public": "site/dist",
  "cleanUrls": true,        // /tools/period-calculator, no .html
  "trailingSlash": false,   // matches Flo's 301 behaviour (A2)
  "redirects": [ /* legacy paths -> canonical, 301 */ ],
  "headers": [
    // HSTS, nosniff, SAMEORIGIN, Referrer-Policy, Permissions-Policy, CSP
    // immutable 1y cache for hashed assets; short cache for HTML
  ]
}
```

Flo passes 8 of 8 canonicalisation tests (A2) — that behaviour is the target and is reproduced
declaratively. Two improvements on Flo: `Permissions-Policy` rather than the deprecated
`Feature-Policy`, and a real `Content-Security-Policy`, which flo.health does not send at all
(A3).

Images go through `astro:assets` → WebP/AVIF with intrinsic `width`/`height`, answering D9
(Flo: zero next-gen formats, dimensions on 1–3 of 27–41 images). `@astrojs/sitemap` generates the
sitemap, so the malformed-`hreflang` class of bug (D1 — 3,131 bad attributes) cannot be written
by hand.

### D10 — The teardown's defect register becomes an executable test

`site/scripts/audit.mjs` runs against `dist/` and fails the build on regression:

| Assertion | Guards |
|---|---|
| Every page: title ≤60, description 70–155, one canonical, OG tags | A4 |
| All JSON-LD parses; no duplicate `@id`; no `//` in any emitted URL | D2, D3 |
| Exactly one `Organization` + one `WebSite` sitewide | D2, D8 |
| Articles carry `datePublished`, `author`, `sources` | D5, D6 |
| Every `<img>` has `width` + `height`; no `.png`/`.jpg` in output | D9 |
| No `cdn.tailwindcss.com`; per-page JS budget enforced | D4, D5 |
| Sitemap covers every built route; every internal link resolves | B3 |

Exposed as `npm run verify`. This is the part of the design most worth keeping: an audit that
runs once is a document, an audit that runs on every build is a guarantee.

## Verification

1. `cd site && npm run build` — clean, and `npm run verify` passes every assertion in D10.
2. `firebase hosting:channel:deploy preview` — a real preview URL before anything goes live.
3. Manual: mobile at 400px, dark mode, keyboard navigation, all four calculators against
   hand-worked examples.
4. Repo hygiene: `flutter analyze` and the 906 Flutter tests are untouched and still pass —
   nothing in `site/` can affect them.

## Open questions

- **Domain.** Not yet chosen. Firebase supplies `*.web.app` until one is connected; `SITE` is a
  single constant, so switching is one line plus redirects.
- **Analytics.** Deliberately unspecified. A privacy-positioned site should not ship Google
  Analytics without a decision; a log-based or cookieless option is preferable. Deferred, not
  forgotten.
- **App Store link.** iOS availability unconfirmed; `/download` renders whichever badges are real.
