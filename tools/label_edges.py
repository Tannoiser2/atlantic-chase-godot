#!/usr/bin/env python3
"""
Come label_hexes.py, ma etichetta i PUNTI MEDI DEI LATI invece dei centri.

Ogni freccia "not adjacent" stampata sulla mappa attraversa esattamente un lato
esagonale: con il punto medio etichettato si legge senza ambiguita' quale coppia
di esagoni va negata.

    python tools/label_edges.py <x0> <y0> <x1> <y1> <output.png> [scala]
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def font(size):
    for p in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
              "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:                                   # noqa: BLE001
                pass
    return ImageFont.load_default()


def main():
    x0, y0, x1, y1 = (int(v) for v in sys.argv[1:5])
    out = sys.argv[5]
    scale = float(sys.argv[6]) if len(sys.argv) > 6 else 2.0

    g = json.load(open(os.path.join(ROOT, "core", "data", "map_graph.json")))
    lat = g["lattice"]
    e1, e2 = lat["basis_e1"], lat["basis_e2"]
    ox, oy = lat["origin_px"]
    R = lat["circumradius_px"]
    th = lat["theta_deg"]
    play = {(h["q"], h["r"]): (h["cx"], h["cy"]) for h in g["hexes"]}
    blocked = {tuple(sorted([(b["aq"], b["ar"]), (b["bq"], b["br"])]))
               for b in g.get("blocked_edges", [])}

    im = Image.open(MAP).convert("RGB").crop((x0, y0, x1, y1))
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    d = ImageDraw.Draw(im, "RGBA")
    f = font(int(13 * scale))

    for h in g["hexes"]:
        cx, cy = h["cx"], h["cy"]
        if not (x0 - R <= cx <= x1 + R and y0 - R <= cy <= y1 + R):
            continue
        sx, sy = (cx - x0) * scale, (cy - y0) * scale
        pts = [(sx + R * scale * math.cos(math.radians(th + 30 + 60 * k)),
                sy + R * scale * math.sin(math.radians(th + 30 + 60 * k)))
               for k in range(6)]
        for i in range(6):
            d.line([pts[i], pts[(i + 1) % 6]], fill=(255, 60, 60, 190),
                   width=max(1, int(1.5 * scale)))

    seen = set()
    for (q, r), (cx, cy) in play.items():
        for dq, dr in DIRS:
            n = (q + dq, r + dr)
            if n not in play:
                continue
            key = tuple(sorted([(q, r), n]))
            if key in seen:
                continue
            seen.add(key)
            nx, ny = play[n]
            mx, my = (cx + nx) / 2, (cy + ny) / 2
            if not (x0 <= mx <= x1 and y0 <= my <= y1):
                continue
            sx, sy = (mx - x0) * scale, (my - y0) * scale
            lab = "%d,%d|%d,%d" % (key[0][0], key[0][1], key[1][0], key[1][1])
            bb = d.textbbox((0, 0), lab, font=f)
            w, hh = bb[2] - bb[0], bb[3] - bb[1]
            col = (255, 235, 120, 245) if key in blocked else (255, 255, 255, 235)
            d.rectangle([sx - w / 2 - 4, sy - hh / 2 - 3,
                         sx + w / 2 + 4, sy + hh / 2 + 4], fill=col,
                        outline=(0, 0, 0, 200))
            d.text((sx - w / 2, sy - hh / 2 - 2), lab, fill=(0, 0, 0), font=f)

    im.save(out)
    print("scritto %s (%dx%d)" % (out, im.width, im.height))


if __name__ == "__main__":
    main()
