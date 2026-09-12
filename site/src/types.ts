export interface ArticleMeta {
  author: string
  reviewedBy: string
  datePublished: Date
  dateModified: Date
}
export interface FaqEntry { q: string; a: string }
export interface Crumb { name: string; path: string }
export interface Source { title: string; url: string }
