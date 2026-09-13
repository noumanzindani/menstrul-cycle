import { defineCollection, z } from 'astro:content'
import { glob } from 'astro/loaders'

/** Sentinel for spec D4. Never replace this with a name that is not a real reviewer. */
export const UNREVIEWED = 'Not medically reviewed'

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
