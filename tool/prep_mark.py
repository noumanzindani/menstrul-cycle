#!/usr/bin/env python3
"""Turn a supplied raster illustration into a LunaTrack chip mark.

Background removal is a flood fill INWARD FROM THE EDGES, not a global
near-white test: these illustrations have white inside them (eyes, teeth,
highlights) and a global test punches holes straight through those.

Usage: prep_mark.py SRC DST [--largest]

--largest keeps only the largest connected opaque blob, which strips a caption
baked in below the art. It is UNSAFE for art whose subject is several
free-standing pieces -- it would keep one and drop the rest -- so it is opt-in.
"""
import sys
from collections import deque
from PIL import Image

WHITE = 238    # >= this on all channels, at the edge, is background
FEATHER = 205  # one-pixel softening band so the cut edge is not aliased
SIZE = 96

# --desat mode. Background is then "light AND COLOURLESS" rather than "light",
# which is a different question and the right one for two source shapes the
# brightness test cannot handle:
#
#   * A very pale TINTED disc. `Ovulation Phase.png` fills its disc with
#     (254,236,248) -- every channel clears WHITE=238, so the flood fill ate
#     irregularly into the disc and left a moth-eaten circle. Its channel spread
#     is 18, where true white's is 0.
#   * A baked-in transparency CHECKERBOARD. `Menstrual Phase.png` ships the
#     grey/white grid as real pixels (the file is RGB, with no alpha at all).
#     Its squares measure (254,254,254) and (225,224,223) -- spreads of 0 and 2,
#     so both read as background here while the artwork does not.
#
# Not the default: it would cut a deliberately grey or white SUBJECT out of its
# own drawing, and several marks in this set are exactly that.
DESAT_SPREAD = 6   # max(r,g,b) - min(r,g,b) at or below this is colourless
DESAT_VALUE = 190  # ...and this bright, at the edge, is background


def cut_background(im, desat=False):
    w, h = im.size
    px = im.load()
    bg = [[False] * w for _ in range(h)]
    q = deque()

    def is_bg(r, g, b):
        if desat:
            return (max(r, g, b) - min(r, g, b) <= DESAT_SPREAD
                    and max(r, g, b) >= DESAT_VALUE)
        return r >= WHITE and g >= WHITE and b >= WHITE

    def seed(x, y):
        if not bg[y][x]:
            r, g, b, a = px[x, y]
            if a > 0 and is_bg(r, g, b):
                bg[y][x] = True
                q.append((x, y))

    for x in range(w):
        seed(x, 0)
        seed(x, h - 1)
    for y in range(h):
        seed(0, y)
        seed(w - 1, y)

    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                seed(nx, ny)

    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if bg[y][x]:
                px[x, y] = (r, g, b, 0)
            elif r >= FEATHER and g >= FEATHER and b >= FEATHER:
                # Near-white but interior: keep it, softened, so the boundary
                # between kept and cut does not read as a hard jagged step.
                px[x, y] = (r, g, b, min(a, 160))
    return im


def largest_blob(im):
    w, h = im.size
    px = im.load()
    seen = [[False] * w for _ in range(h)]
    best = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or px[sx, sy][3] == 0:
                continue
            blob = []
            q = deque([(sx, sy)])
            seen[sy][sx] = True
            while q:
                x, y = q.popleft()
                blob.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] \
                            and px[nx, ny][3] > 0:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(blob) > len(best):
                best = blob
    keep = set(best)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and (x, y) not in keep:
                r, g, b, _ = px[x, y]
                px[x, y] = (r, g, b, 0)
    return im


def main():
    src, dst = sys.argv[1], sys.argv[2]
    im = Image.open(src).convert('RGBA')
    im = cut_background(im, desat='--desat' in sys.argv)
    if '--largest' in sys.argv:
        im = largest_blob(im)
    box = im.getbbox()
    if box:
        im = im.crop(box)
    # Square it on the longer side so every mark lands on the same grid and
    # nothing is stretched.
    w, h = im.size
    side = max(w, h)
    sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - w) // 2, (side - h) // 2))
    sq.resize((SIZE, SIZE), Image.LANCZOS).save(dst)
    print(f'{dst}  {side}x{side} -> {SIZE}x{SIZE}')


if __name__ == '__main__':
    main()
