/**
 * Header graphics for articles, keyed by slug.
 *
 * Membership is the switch: an article in this map gets a header, one that is
 * not stays text-only. That is deliberate rather than deriving the filename
 * from the slug — every graphic here is a DATA graphic, and a data graphic
 * needs alt text that states what the data says. Derivation would let a new
 * article silently inherit a missing file or a generic description, and a
 * chart described as "header image" is worse than no image at all.
 *
 * Each file is 2048x430 (2x of 1024x215), WebP, drawn from the same phase
 * figures and the same band geometry the site uses everywhere else.
 */
export interface ArticleHeader {
  src: string
  alt: string
}

export const ARTICLE_HEADERS: Record<string, ArticleHeader> = {
  'cycle-phases-explained': {
    src: '/article-headers/cycle-phases-explained.webp',
    alt: 'A 28-day cycle drawn to scale in four bands: menstrual 5 days, follicular 8 days, ovulatory 3 days, luteal 12 days.',
  },
  'how-period-predictions-work': {
    src: '/article-headers/how-period-predictions-work.webp',
    alt: 'Three predicted periods on one timeline. Each band fades further at its edges than the one before it, showing confidence falling the further ahead the prediction reaches.',
  },
  'preparing-a-doctor-ready-cycle-summary': {
    src: '/article-headers/preparing-a-doctor-ready-cycle-summary.webp',
    alt: 'Five recorded cycles as horizontal bars measured from zero: April 28 days, May 31, June 27, July 34, August 29. July is the longest and is marked.',
  },
  'what-cycle-length-is-normal': {
    src: '/article-headers/what-cycle-length-is-normal.webp',
    alt: 'A scale of cycle lengths with the usual adult range, 21 to 35 days, shaded and hard-edged, and 28 days marked inside it.',
  },
  'what-symptoms-are-worth-tracking': {
    src: '/article-headers/what-symptoms-are-worth-tracking.webp',
    alt: 'A faded 28-day phase band with logged symptoms plotted as dots, clustering in the menstrual, ovulatory and luteal phases rather than spreading evenly.',
  },
  'what-to-check-in-a-period-tracker-privacy-policy': {
    src: '/article-headers/what-to-check-in-a-period-tracker-privacy-policy.webp',
    alt: 'A checklist of four questions a privacy policy has to answer: who can read your data, whether it is sold or shared, what happens when you delete, and where it is stored.',
  },
}
