/** The canonical origin. Changing the domain is a one-line edit here. */
export const SITE = 'https://lunatrack.web.app'

/**
 * Sentinel for spec D4. Lives here (not in content.config.ts) so SeoHead.astro can
 * import it without a content-layer dependency, and content.config.ts re-exports it
 * so existing importers keep working. Never replace this with a name that is not a
 * real reviewer.
 */
export const UNREVIEWED = 'Not medically reviewed'

export const ORG = {
  name: 'LunarFlow',
  legalName: 'LunarFlow',
  // No `logo` yet — there is no real asset at /images/logo.png and dist/images/
  // does not exist. Add a real logo/OG image back here (and to the Organization
  // node in SeoHead.astro) once one exists; a schema.org URL pointing at a 404
  // is worse than omitting the property.
  sameAs: [
    'https://play.google.com/store/apps/details?id=com.lunatrack.app',
  ],
} as const

/**
 * Nav is built up as the routes exist. The audit fails the build on a link to a
 * page that has not been built, so `/tools` is added in Task 6 and `/articles`
 * in Task 7 — not before.
 */
/**
 * Top-level nav. An entry with `children` renders as a dropdown; the parent is
 * still a REAL link to the section index, which is what makes the menu work
 * without JavaScript — the panel opens on :hover and :focus-within, and anyone
 * who cannot trigger either (touch, or a reader that does not move focus) lands
 * on a page that lists the same links.
 *
 * Deliberately no `aria-expanded`: it cannot be updated without JS, and a value
 * hardcoded to "false" while the panel is visibly open lies to assistive tech.
 *
 * The six pregnancy calculators are NOT here yet. The audit fails the build on a
 * link to a page that has not been built, so each one joins this list in the same
 * commit as its page.
 */
export const NAV = [
  {
    href: '/features',
    label: 'Product',
    children: [
      { href: '/features', label: 'Everything it tracks' },
      { href: '/privacy', label: 'Your data' },
      { href: '/privacy-policy', label: 'Privacy policy' },
      { href: '/terms', label: 'Terms' },
    ],
  },
  {
    href: '/tools',
    label: 'Calculators',
    children: [
      { href: '/tools/period-calculator', label: 'Period calculator' },
      { href: '/tools/ovulation-calculator', label: 'Ovulation calculator' },
      { href: '/tools/cycle-length-calculator', label: 'Menstrual cycle calculator' },
      { href: '/tools/due-date-calculator', label: 'Pregnancy due date calculator' },
      { href: '/tools/pregnancy-weeks-to-months', label: 'Pregnancy weeks to months' },
      { href: '/tools/ivf-due-date-calculator', label: 'IVF and FET due date calculator' },
      { href: '/tools/ultrasound-due-date-calculator', label: 'Due date by ultrasound' },
      { href: '/tools/pregnancy-test-calculator', label: 'Pregnancy test calculator' },
    ],
  },
  { href: '/articles', label: 'Articles' },
  { href: '/download', label: 'Download' },
] as const

/**
 * Claims this site may not make. See the Global Constraints section of the plan:
 * the app requires an account, has a paid tier, and stores readable cloud data.
 * `scripts/audit.mjs` fails the build if any of these appears in rendered text.
 */
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
