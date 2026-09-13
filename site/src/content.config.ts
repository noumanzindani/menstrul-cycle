import { defineCollection, z } from 'astro:content'
import { glob } from 'astro/loaders'
import { UNREVIEWED } from './consts.ts'

/** Sentinel for spec D4, centralised in consts.ts; re-exported so existing importers work. */
export { UNREVIEWED }

const articles = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/articles' }),
  schema: z.object({
    title: z.string().max(60),
    description: z.string().min(70).max(155),
    author: z.string().min(1),
    // Must be either the exact sentinel or a genuinely different value — never a
    // near-miss like a case variant of the sentinel ("Not Medically Reviewed"),
    // which would silently flip the page to MedicalWebPage and fabricate a
    // Person in schema. The exact-sentinel check is case-sensitive by design.
    reviewedBy: z.string().min(1).refine(
      (v) => v === UNREVIEWED || v.toLowerCase() !== UNREVIEWED.toLowerCase(),
      { message: `reviewedBy must be exactly "${UNREVIEWED}" or a real reviewer's name — not a differently-cased variant of the sentinel` },
    ),
    datePublished: z.coerce.date(),
    dateModified: z.coerce.date(),
    sources: z.array(z.object({
      title: z.string().min(1),
      url: z.string().url(),
    })).min(2),
  }),
})

export const collections = { articles }
