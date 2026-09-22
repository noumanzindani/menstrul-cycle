# Instagram carousels

Two sets, both 1080 × 1350 (4:5 portrait feed), sharing one stylesheet.

| | Source | Upload these | Proof |
|---|---|---|---|
| **Consumer** (9 cards) | `consumer.html` | `consumer/card-1.png` … `card-9.png` | `LunarFlow-consumer-carousel.pdf` |
| **Founder** (6 cards) | `founder.html` | `founder/card-1.png` … `card-6.png` | `LunarFlow-founder-carousel.pdf` |

Post the **PNGs** — Instagram re-compresses anything else. The PDFs are only for
reviewing a whole set at once.

## Re-render after editing

```bash
# from menstrul_track/
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for set in consumer founder; do
  "$CH" --headless --disable-gpu --no-pdf-header-footer \
    --run-all-compositor-stages-before-draw --virtual-time-budget=14000 \
    --print-to-pdf="$PWD/docs/social/LunarFlow-${set}-carousel.pdf" \
    "file://$PWD/docs/social/${set}.html"
  rm -f "docs/social/${set}"/*.png
  pdftoppm -png -scale-to-x 1080 -scale-to-y 1350 \
    "docs/social/LunarFlow-${set}-carousel.pdf" "docs/social/${set}/card"
done
```

`-scale-to-x/-scale-to-y` is what guarantees exactly 1080 × 1350. Chrome writes the page
at 810 × 1013.04pt rather than a clean 1012.5, so rendering at a fixed DPI lands on 1351px
and Instagram resamples it. Don't drop those flags.

## Conventions

- **Same brand theme as the deck** (`../pitch/README.md` has the palette rules and why
  body copy is not `#CB6A8A`). The logo is `../pitch/assets/lunarflow-mark.png` — one copy,
  referenced by both.
- **Type is sized for a phone, not the canvas.** 1080px wide renders ~400px in hand, so
  body copy is 36px and nothing goes below 25px. If you add a card, hold that floor.
- **Cards are top-anchored,** with the footer pinned. Headlines therefore start at the same
  height on every swipe, and the tail whitespace varies. That is deliberate — a headline
  that jumps vertically as you swipe reads as broken.
- **Every card carries the mark** in `.foot`. Don't ship a card without it.
- Check clearance after editing by injecting a probe that compares each `.card`'s deepest
  child against its `.foot` top — and **exclude `.spacer`, `.moon` and `.wave`**, or every
  card reports a false overflow from the flex spacer.

## Claims to be comfortable with before posting

- **The consumer set names no competitor** and makes no accuracy claim about anyone else.
  Card 2 commits publicly to never showing a fertility percentage; card 7 states plainly
  that **cloud backup is not end-to-end encrypted yet**. Both are true today — if either
  changes, the card has to change with it.
- **Card 6 lists the exact ovulation-suppressing methods** from
  `kOvulationSuppressingContraception` in `lib/common/catalog.dart`. If that set changes,
  update the card.
- **The founder set names Flo and cites litigation figures** (FTC 2021; the $56M
  Google/Flo settlement, Sept 2025) and the accuracy research. All sourced on the last
  slide of the investor deck. Posting them under your own name is your call.
