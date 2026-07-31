#!/usr/bin/env python3
"""
M1b (5) - Determinazione dell'area giocabile con criterio geometrico.

Il criterio del colore sbaglia: il reticolo prosegue sopra le isole britanniche
e quegli esagoni SONO giocabili (contengono mare). Viceversa le tabelle stampate
sull'Iberia o fuori cornice non hanno reticolo.

Criterio corretto: un esagono fa parte dell'area di gioco se i suoi lati sono
davvero disegnati sulla mappa. Misuriamo, per ciascun lato, la frazione di
campioni che cadono su una linea del reticolo.

  edge_presence alto  -> l'esagono e' disegnato -> giocabile
  edge_presence basso -> nessun reticolo li'    -> fuori area

Il colore resta utile come attributo secondario (quanta terra contiene l'esagono),
che servira' per il rendering e per la lista dei lati "not adjacent".

Output: reports/playable.json + reports/playable_overlay.png
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
REP = os.path.join(ROOT, "reports")

SAMPLES_PER_EDGE = 40


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            if x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                inside = not inside
    return inside


def main():
    lat = json.load(open(os.path.join(REP, "lattice.json")))
    zones = [z for z in json.load(open(os.path.join(REP, "zones.json")))
             if z["map"] == "Main Map"]
    val = json.load(open(os.path.join(REP, "lattice_validation.json")))
    used = {(h["q"], h["r"]) for h in val["used_hexes"]}

    im = Image.open(MAP).convert("RGB")
    W, H = im.size
    arr = np.asarray(im, dtype=np.float32)
    gray = arr.mean(axis=2)
    bg = ndimage.uniform_filter(gray, size=61)
    hp = np.clip(gray - bg, 0, None)
    scale = np.percentile(hp, 99.0)
    mask = np.clip(hp / scale, 0, 1)
    # dilata leggermente: le linee sono sottili e il reticolo ha errore ~1 px
    maskd = ndimage.maximum_filter(mask, size=7)

    br = arr[:, :, 2] - arr[:, :, 0]
    land_px = br < -10
    sea_px = br > 10

    R = lat["circumradius_px"]
    theta = lat["theta_deg"]
    rad = int(lat["inradius_px"] * 0.78)
    yy, xx = np.mgrid[-rad:rad + 1, -rad:rad + 1]
    disc = (xx * xx + yy * yy) <= rad * rad

    def corners(cx, cy):
        return [(cx + R * math.cos(math.radians(theta + 30 + 60 * k)),
                 cy + R * math.sin(math.radians(theta + 30 + 60 * k))) for k in range(6)]

    def edge_presence(cx, cy):
        """frazione media di campioni su linea, e valore per singolo lato"""
        cs = corners(cx, cy)
        per_edge = []
        for k in range(6):
            x1, y1 = cs[k]
            x2, y2 = cs[(k + 1) % 6]
            t = np.linspace(0.15, 0.85, SAMPLES_PER_EDGE)   # evita i vertici
            xs = np.clip((x1 + (x2 - x1) * t).astype(int), 0, W - 1)
            ys = np.clip((y1 + (y2 - y1) * t).astype(int), 0, H - 1)
            inb = (xs > 0) & (xs < W - 1) & (ys > 0) & (ys < H - 1)
            v = maskd[ys, xs]
            per_edge.append(float((v > 0.30).mean()) if inb.any() else 0.0)
        return per_edge

    out = []
    for h in lat["hexes"]:
        cx, cy = h["cx"], h["cy"]
        ix, iy = int(round(cx)), int(round(cy))
        x0, x1 = ix - rad, ix + rad + 1
        y0, y1 = iy - rad, iy + rad + 1
        if 0 <= x0 and 0 <= y0 and x1 <= W and y1 <= H:
            landf = float(land_px[y0:y1, x0:x1][disc].mean())
            seaf = float(sea_px[y0:y1, x0:x1][disc].mean())
        else:
            landf = seaf = 0.0

        pe = edge_presence(cx, cy)
        pres = float(np.mean(pe))

        zname = None
        if 0 <= cx < W and 0 <= cy < H:
            for z in zones:
                b = z["bbox"]
                if b[0] <= cx <= b[2] and b[1] <= cy <= b[3] and \
                        point_in_poly(cx, cy, z["polygon"]):
                    zname = z["name"]
                    break

        out.append({
            "q": h["q"], "r": h["r"], "cx": cx, "cy": cy,
            "edge_presence": round(pres, 3),
            "edges": [round(e, 3) for e in pe],
            "land": round(landf, 3), "sea": round(seaf, 3),
            "zone": zname,
            "used": (h["q"], h["r"]) in used,
        })

    pres_used = [o["edge_presence"] for o in out if o["used"]]
    pres_other = [o["edge_presence"] for o in out if not o["used"]]
    print("=== edge_presence ===")
    print(f"  esagoni usati dagli scenari (n={len(pres_used)}): "
          f"min {min(pres_used):.3f}  mediana {np.median(pres_used):.3f}")
    print(f"  altri                      (n={len(pres_other)}): "
          f"mediana {np.median(pres_other):.3f}")

    # soglia: sotto il minimo osservato sugli esagoni certamente giocabili
    thr = max(0.25, min(pres_used) * 0.85)
    print(f"  soglia scelta: {thr:.3f}")

    for o in out:
        o["playable"] = bool(o["edge_presence"] >= thr and o["zone"] is None)
    n_play = sum(o["playable"] for o in out)
    print(f"\n  esagoni giocabili: {n_play} / {len(out)}")
    miss = [o for o in out if o["used"] and not o["playable"]]
    print(f"  esagoni usati dagli scenari ma NON giocabili: {len(miss)}")
    for o in miss:
        print(f"    q={o['q']} r={o['r']} pres={o['edge_presence']:.2f} zone={o['zone']}")

    json.dump({"threshold": thr, "hexes": out},
              open(os.path.join(REP, "playable.json"), "w"), indent=2)

    ov = im.copy()
    d = ImageDraw.Draw(ov, "RGBA")
    for o in out:
        cs = corners(o["cx"], o["cy"])
        if o["playable"]:
            c = (255, 210, 0, 90) if o["land"] > 0.35 else (0, 220, 255, 70)
        else:
            c = (255, 30, 30, 55)
        d.polygon(cs, fill=c, outline=(c[0], c[1], c[2], 200))
        if o["used"]:
            d.ellipse([o["cx"] - 13, o["cy"] - 13, o["cx"] + 13, o["cy"] + 13],
                      fill=(60, 255, 60, 230))
    ov.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(REP, "playable_overlay.png"))
    print("\nScritto reports/playable.json + playable_overlay.png")


if __name__ == "__main__":
    main()
