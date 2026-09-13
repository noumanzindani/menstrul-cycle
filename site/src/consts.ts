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
  { href: '/tools', label: 'Calculators' },
  { href: '/articles', label: 'Articles' },
  { href: '/privacy', label: 'Your data' },
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
