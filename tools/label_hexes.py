#!/usr/bin/env python3
"""
Rende una regione della mappa con le coordinate esagonali sovrapposte.

Serve per trascrivere a mano i dati che solo un occhio puo' leggere: le frecce
"not adjacent" stampate sulla mappa, e i porti. Con le etichette q,r visibili
si legge direttamente quale coppia di esagoni va negata.

    python tools/label_hexes.py <x0> <y0> <x1> <y1> <output.png> [scala] [--all]

--all etichetta TUTTI gli esagoni del reticolo, non solo quelli giocabili.
Serve sempre quando si lavora vicino alla terraferma: se un esagono non e' nel
grafo i suoi lati non compaiono, e una freccia "not adjacent" finisce
attribuita al lato etichettato piu' vicino invece che a quello giusto. E'
esattamente l'errore che ha colpito la freccia della Bretagna.
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
    if len(sys.argv) < 6:
        print(__doc__)
        return 1
    x0, y0, x1, y1 = (int(v) for v in sys.argv[1:5])
    out = sys.argv[5]
    scale = float(sys.argv[6]) if len(sys.argv) > 6 and not sys.argv[6].startswith("--") else 2.0

    use_all = "--all" in sys.argv
    if use_all:
        g = json.load(open(os.path.join(ROOT, "reports", "lattice.json")))
        lat = g
        g["hexes"] = [dict(h, neighbors=[]) for h in g["hexes"]]
        g["blocked_edges"] = []
    else:
        g = json.load(open(os.path.join(ROOT, "core", "data", "map_graph.json")))
        lat = g["lattice"]
    e1, e2 = lat["basis_e1"], lat["basis_e2"]
    ox, oy = lat["origin_px"]
    R = lat["circumradius_px"]
    th = lat["theta_deg"]
    playable = {(h["q"], h["r"]) for h in g["hexes"]}
    blocked = {(b["aq"], b["ar"], b["bq"], b["br"]) for b in g.get("blocked_edges", [])}

    im = Image.open(MAP).convert("RGB").crop((x0, y0, x1, y1))
    im = im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS)
    d = ImageDraw.Draw(im, "RGBA")
    f = font(int(15 * scale))

    qmin = qmax = rmin = rmax = 0
    for h in g["hexes"]:
        cx, cy = h["cx"], h["cy"]
        if not (x0 - R <= cx <= x1 + R and y0 - R <= cy <= y1 + R):
            continue
        sx, sy = (cx - x0) * scale, (cy - y0) * scale
        pts = [(sx + R * scale * math.cos(math.radians(th + 30 + 60 * k)),
                sy + R * scale * math.sin(math.radians(th + 30 + 60 * k)))
               for k in range(6)]
        d.polygon(pts, outline=(255, 40, 40, 220))
        for i in range(6):
            d.line([pts[i], pts[(i + 1) % 6]], fill=(255, 40, 40, 220),
                   width=max(1, int(2 * scale)))
        lab = "%d,%d" % (h["q"], h["r"])
        bb = d.textbbox((0, 0), lab, font=f)
        w, hh = bb[2] - bb[0], bb[3] - bb[1]
        d.rectangle([sx - w / 2 - 4, sy - hh / 2 - 3, sx + w / 2 + 4, sy + hh / 2 + 3],
                    fill=(255, 255, 255, 225))
        d.text((sx - w / 2, sy - hh / 2 - 2), lab, fill=(0, 0, 0), font=f)

    # lati gia' negati, per controllare il lavoro fatto
    for (aq, ar, bq, br) in blocked:
        a = (ox + aq * e1[0] + ar * e2[0], oy + aq * e1[1] + ar * e2[1])
        b = (ox + bq * e1[0] + br * e2[0], oy + bq * e1[1] + br * e2[1])
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        if not (x0 <= mid[0] <= x1 and y0 <= mid[1] <= y1):
            continue
        vx, vy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(vx, vy) or 1
        px, py = -vy / n * R * 0.5, vx / n * R * 0.5
        d.line([((mid[0] - px - x0) * scale, (mid[1] - py - y0) * scale),
                ((mid[0] + px - x0) * scale, (mid[1] + py - y0) * scale)],
               fill=(0, 90, 255, 255), width=max(3, int(5 * scale)))

    im.save(out)
    print("scritto %s (%dx%d)" % (out, im.width, im.height))
    return 0


if __name__ == "__main__":
    sys.exit(main())
