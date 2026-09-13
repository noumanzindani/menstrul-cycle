# LunaTrack marketing site

A static marketing site for the LunaTrack Android app. Astro, zero JavaScript on
every page except the four calculators, deployed to Firebase Hosting.

19 routes: 6 core pages, 4 calculators, 6 articles, 2 indexes, plus a 404.

---

## Commands

Run from this directory (`menstrul_track/site`).

```bash
npm install
npm run dev        # dev server, http://localhost:4321
npm run build      # static build into dist/
npm run preview    # serve the built dist/ (daemonises; stop with `npx astro preview stop`)
npm run verify     # the site audit — MUST pass before any deploy
npm test           # 43 unit tests (cycle maths + band geometry)
npm run check      # astro check (TypeScript)
```

`npm run verify` builds nothing — run `npm run build` first or it audits a stale `dist/`.

### Deploying

No Firebase command has ever been run for this site. `firebase.json` at the repo root
carries the `hosting` block (public `site/dist`, `cleanUrls`, redirects, CSP and cache
headers). Preview before production:

```bash
firebase hosting:channel:deploy preview
```

---

## The two constraints everything else follows from

**1. Zero JavaScript, enforced at build time.** `scripts/audit.mjs` assigns every page a
JS budget, and the default is **zero**:

```js
const JS_BUDGET = { '/tools/period-calculator': 8192, ... }   // 4 calculators only
const budget = JS_BUDGET[page] ?? 0                            // everything else: 0 bytes
```

Adding any script to any other page fails `npm run verify`. This is deliberate, not an
oversight — it means adding JS is a conscious act that edits the audit.

**2. `script-src 'self'`.** The CSP in `firebase.json` blocks inline scripts and every
CDN. Two consequences:

- `astro.config.mjs` sets `build.assetsInlineLimit: 0` so Astro emits the calculator
  island as an external `/_astro/*.js` file instead of inlining it. **This line is
  load-bearing** — without it the CSP kills all four calculators in production while
  everything passes locally.
- No GSAP, Framer Motion, Lottie, or any CDN library. All motion is CSS-native.

---

## Design system

Defined in `src/styles/global.css`. The governing rule: **a visual device has to report
something true, or it gets cut.**

### Type

| Role | Face | Notes |
|---|---|---|
| Display | Fraunces Variable | `@fontsource-variable/fraunces/wonk.css`, 35.8 KB latin. Use `.display` / `.display-sm`, never raw `font-headline` — the classes carry the `WONK` / `SOFT` / `opsz` settings that stop it reading as a stock serif. |
| Body | Public Sans | 400/500/600/700, self-hosted. |
| Long-form | `.prose` | Hand-rolled, **not** `@tailwindcss/typography`. Markdown emits bare `h2`/`p`/`ul` and Tailwind Preflight resets them, so without this block every article is an undifferentiated wall of text. |

### Colour

Pink is **deliberately not the base palette**. Flo, Clue and Stardust are all pink;
pink-as-base is the category default. Ink `#3A2A30` and warm paper `#FAF6F3` carry the
page, and the six cycle-phase colours are the only saturated values on the site.

Brand colours and semantic colours are graded against different WCAG bars, so they are
separate tokens:

```
--color-menstrual   #D64F6E   DATA colour — bands, rules, markers (3:1 bar)
--color-danger      #B8344F   error TEXT on paper, 5.37:1 (4.5:1 bar)
--color-danger-dark #F08099   error TEXT on dark,  6.73:1
```

Do not use `text-menstrual` for body-size text — it is 3.76:1 and fails AA.

### Dark mode

Follows the OS via `prefers-color-scheme`, with `.dark` / `.light` classes able to
override. It is **not** class-only: nothing here can add a class (zero JS budget), so
class-only silently made every `dark:` utility on every page dead code.

### Components

| Component | What it encodes |
|---|---|
| `PhaseBand.astro` | A 28-day cycle **to scale** — menstrual 5, follicular 8, ovulatory 3, luteal 12 days. Widths are the real day counts; don't "tidy" them to equal thirds. |
| `CycleFocus.astro` | Which part of a cycle a given calculator can speak to. Positioned from real day numbers. |
| `Section.astro` | A section with a phase-tinted rule. `phase` **defaults to `neutral`** so using a colour is a conscious act. A section with no honest phase mapping gets a grey rule. |
| `Calculator.astro` | The only JS island. Imports tested maths from `lib/cycle.ts`; never does date arithmetic inline. |

### Prediction bands

`src/lib/band.ts` — pure geometry, unit-tested, no DOM and no dates. Every calculator
result is drawn as a band that fades at the edges, because every result is an estimate
and the site's own copy says so.

Three rules that are easy to break by accident:

1. **The cycle-length calculator is hard-edged on purpose** (`feather: 0`). It reports
   cycles the user actually had — measurements, not predictions. The contrast is what
   makes the fade mean anything. Do not "fix" it to match the others.
2. **`cycleFeather` is a qualitative ramp, not a confidence interval.** The calculator
   never collects the cycle-to-cycle variation a real interval would need. Every caption
   next to a fade must say so, or the visual becomes a false clinical claim — the same
   false-precision ground that vetoed a synthesized fertility % in the app.
3. **The gradient stop caps at 45%.** At 50% the two halves meet and the band never
   reaches full colour, which reads as "entirely uncertain" rather than "uncertain at the
   edges". The due-date band hits this cap, so the rule is live.

### Motion

CSS-native, zero bytes, **tiered** under `prefers-reduced-motion` rather than nuked —
removing every transition makes elements teleport, which is its own disorientation.

| Moment | Technique |
|---|---|
| Hero band draw-in | `clip-path` keyframe, 900 ms, once |
| Section rules grow | `animation-timeline: view()`, behind `@supports` |
| Page → page | `@view-transition { navigation: auto }` |
| Press feedback | `.pressable` — Tier 3, survives the reduced-motion net |

---

## The audit

`scripts/audit.mjs` (`npm run verify`) is an executable defect register — Node built-ins
only, no dependencies. It enforces, per page:

- Title ≤ 60 chars, meta description 70–155, exactly one canonical, OG tags present
- JSON-LD parses; no duplicate `@id`; **no dangling `{'@id': …}` pointers**; no `//` in
  schema URLs; breadcrumb `position` an integer; articles carry `datePublished`/`author`
- Images have real `width`/`height` and are not `.png`/`.jpg`
- The JS budget above; no off-origin scripts; no `fetch`/`sendBeacon`/`XMLHttpRequest`
  anywhere under `/tools/*`
- **Banned claims** (`src/consts.ts` `BANNED_CLAIMS`) scanned across text *and* attribute
  values — "no account", "completely free", "fully private", "end-to-end", "anonymous"
  and others are false for this app and are made unrepresentable rather than merely
  discouraged
- Internal links resolve; sitemap covers every route; exactly one `Organization` and one
  `WebSite` sitewide

---

## Claude Code setup

To pick up where this left off, the environment matters as much as the code.

### Plugins (from the official marketplace)

Enabled when this work was done:

```
superpowers  frontend-design  firebase  remember  commit-commands  code-review
pr-review-toolkit  feature-dev  security-guidance  semgrep  skill-creator
claude-md-management  learning-output-style  explanatory-output-style
```

`frontend-design` is the one that drove the visual pass:

```bash
claude plugin enable frontend-design@claude-plugins-official
```

### Skills used, in order

1. `superpowers:brainstorming` — competitor teardown → design spec
2. `superpowers:writing-plans` — spec → `docs/superpowers/plans/2026-09-13-lunatrack-site.md`
3. `superpowers:subagent-driven-development` — 8 tasks, fresh subagent each, review between
4. `superpowers:finishing-a-development-branch` — branch integration
5. `frontend-design` — the visual direction, type scale and self-critique pass

### Third-party skill repos

Added as a marketplace (registered in `~/.claude/settings.json`):

```bash
claude plugin marketplace add iart-ai/web-animation-skills
claude plugin install web-animation-skills@web-animation-skills
```

Cloned for reference only, **not installed** — clone them again if you want them:

```bash
git clone --depth 1 https://github.com/dylantarre/animation-principles.git
git clone --depth 1 https://github.com/iart-ai/motion-design-skills.git
```

- `animation-principles` — 144 skills, pure markdown, **no `marketplace.json`** so it
  cannot be installed as a marketplace. Useful as a reference: its timing-scale and
  emotional-outcome taxonomies (`comfort-safety` especially) map well onto this subject.
- `motion-design-skills` — mostly After Effects, Remotion and beat-sync. **Video
  production, not web.** Skip it for this project.
- `web-animation-skills` — GSAP, SVG, Lottie, micro-interactions. Its `accessible-animation`
  skill is the genuinely useful one here; the library skills are unusable under the zero-JS
  budget.

---

## Open decisions for the owner

1. `your-email@example.com` is still a placeholder in `src/pages/terms.astro` and in the
   repo-root `PRIVACY_POLICY.md`.
2. The "Do not publish this policy, or the app, until that job is in operation"
   blockquote renders on `/privacy-policy`, because that page injects the owner's
   `PRIVACY_POLICY.md` verbatim. Decide whether it should be stripped for the public page.
3. Confirm the 7-day regularity threshold in `lib/cycle.ts` and the trimester convention
   (T2 from day 98, T3 from day 196 — ACOG/NHS).
4. Nothing has been deployed. Authorise a preview channel when ready.

## Not verified

The site has never been opened in a browser by the agent that built it — the Claude in
Chrome extension was not connected. Everything is verified structurally: compiled CSS,
served HTML, aria-labels, contrast ratios computed from the tokens, route status codes,
and the band geometry checked numerically. **Visual review is outstanding.**
