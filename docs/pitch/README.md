# Investor deck

`deck.html` is the source. `../LunarFlow-Investor-Deck.pdf` is the rendered output
(21 slides, 960×540pt = 16:9).

## Re-render after editing

```bash
# from menstrul_track/
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --disable-gpu --no-pdf-header-footer \
  --run-all-compositor-stages-before-draw --virtual-time-budget=12000 \
  --print-to-pdf="$PWD/docs/LunarFlow-Investor-Deck.pdf" \
  "file://$PWD/docs/pitch/deck.html"
```

No dependencies beyond Chrome. Fonts are loaded by relative path from
`site/dist/_astro/` (Fraunces Variable + Public Sans, the same faces as the
marketing site) and are subset-embedded into the PDF.

## Conventions

**Brand theme (owner-specified 2026-09-14).** Primary pink `#F489AF` is the dominant
accent, `#FDF2F2` the page background, `#CB6A8A` all display typography.

- **This deliberately reverses the marketing site's "pink is NOT the base" rule.** That
  rule exists because Flo, Clue and Stardust are all pink and pink-as-base is the category
  default. The owner directed pink for the deck anyway. Do not "fix" the deck back to the
  site palette, and do not push the deck palette onto `site/` — they are two surfaces with
  two decisions.
- `--ink` (`#5C3543`) and `--ink-muted` (`#7E5464`) are **deepened shades of the same rose
  hue**, not new colours. Body copy set in `#CB6A8A` lands near 3:1 on the blush
  background, which is not readable at 11px on a phone. Headings keep `#CB6A8A` as
  specified. Do not set body text or 9.5px table headers in `--blush`.
- **The six cycle phases became one rose ramp** — menstrual `#CB6A8A` → follicular
  `#F489AF` → ovulatory `#F7A9B5` → luteal `#FBC2CC`. The original teal/blue/orange
  encoding was outside the brand. The band still encodes real day counts (5/8/3/12 of 28);
  only the hue changed.
- **Every page carries the app mark** via `.rail .mark`'s background image
  (`assets/lunarflow-mark.png`), so new slides get it with no extra markup.
- **Motifs are CSS, not images:** the crescent is an offset `inset` box-shadow on a round
  div, the sparkles are inline SVG data URIs, the wave and botanical sprig are inline SVG.
  The crescent was originally an SVG two-arc path and **silently rendered as a disc** —
  when an arc's radius is shorter than its chord, SVG scales the radius up to fit. Do not
  reintroduce that construction.
- **Decoration yields to content.** The botanical sprig was cut from the sources slide
  because it sat behind live text. Cover only.
- Every slide's content must clear the footer rail. To check after an edit, inject a probe
  that compares each `.slide`'s deepest child against its `.rail` top and `--dump-dom` the
  result; anything with negative clearance overflows in print but looks fine in a browser.
- After changing the palette, **grep for orphaned tokens**: `var(--danger)` and
  `var(--primary)` survived the first theme pass in inline styles and silently dropped a
  pull-quote's accent bar, because a shorthand with an unresolvable colour is discarded
  whole.

## Blanks that are deliberate

Slide 20 ("The ask") carries dashed placeholders for raise amount, valuation,
instrument, runway, installs, D30 retention, intake completion and Premium
conversion. Every other number in the deck is sourced on slide 21. Fill the blanks;
don't estimate them, or the sourcing on the rest stops meaning anything.
