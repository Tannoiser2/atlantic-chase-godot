#!/usr/bin/env python3
"""
M1b (4) - Classificazione automatica del terreno per esagono.

Il clustering dei colori della mappa da':
    mare   (181,211,227) (170,188,188) (208,224,238)   -> B-R fra +18 e +46
    terra  (162,162,135)                               -> B-R = -27
    bianco (255,255,255) / grigio (113,107,107)        -> B-R ~ 0

Quindi il discriminante e' semplicemente B-R.

Un esagono e' escluso dal gioco se:
  - il suo centro cade dentro una Zone del modulo (tracce, box porto,
    caselle Operazione, pannello della Battaglia) -> non e' mare navigabile
  - e' prevalentemente terra
  - e' prevalentemente coperto da tabelle / fuori dalla cornice della mappa

Output: reports/terrain.json + reports/terrain_overlay.png
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
REP = os.path.join(ROOT, "reports")

SEA, LAND, BLOCKED = "sea", "land", "blocked"


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
    arr = np.asarray(im, dtype=np.int16)
    br = arr[:, :, 2] - arr[:, :, 0]          # B - R
    sea_px = br > 10
    land_px = br < -10

    R = lat["circumradius_px"]
    rad = int(lat["inradius_px"] * 0.78)

    # maschera disco riutilizzabile
    yy, xx = np.mgrid[-rad:rad + 1, -rad:rad + 1]
    disc = (xx * xx + yy * yy) <= rad * rad

    out = []
    for h in lat["hexes"]:
        cx, cy = h["cx"], h["cy"]
        ix, iy = int(round(cx)), int(round(cy))
        x0, x1 = ix - rad, ix + rad + 1
        y0, y1 = iy - rad, iy + rad + 1
        if x0 < 0 or y0 < 0 or x1 > W or y1 > H:
            # esagono a cavallo del bordo immagine: ritaglia
            xs0, ys0 = max(0, x0), max(0, y0)
            xs1, ys1 = min(W, x1), min(H, y1)
            if xs1 <= xs0 or ys1 <= ys0:
                out.append({**h, "terrain": BLOCKED, "reason": "fuori mappa",
                            "sea": 0.0, "land": 0.0})
                continue
            m = disc[ys0 - y0:ys0 - y0 + (ys1 - ys0), xs0 - x0:xs0 - x0 + (xs1 - xs0)]
            s = sea_px[ys0:ys1, xs0:xs1][m].mean()
            l = land_px[ys0:ys1, xs0:xs1][m].mean()
            edge = True
        else:
            s = sea_px[y0:y1, x0:x1][disc].mean()
            l = land_px[y0:y1, x0:x1][disc].mean()
            edge = False

        zname = None
        for z in zones:
            b = z["bbox"]
            if b[0] <= cx <= b[2] and b[1] <= cy <= b[3] and \
                    point_in_poly(cx, cy, z["polygon"]):
                zname = z["name"]
                break

        if zname:
            t, reason = BLOCKED, f"zona '{zname}'"
        elif l >= 0.40:
            t, reason = LAND, "terra"
        elif s >= 0.55:
            t, reason = SEA, "mare"
        elif edge:
            t, reason = BLOCKED, "bordo mappa"
        else:
            t, reason = BLOCKED, "tabella/fuori cornice"

        rec = {**h, "terrain": t, "reason": reason,
               "sea": round(float(s), 3), "land": round(float(l), 3)}
        if (h["q"], h["r"]) in used:
            rec["used_by_scenarios"] = True
        out.append(rec)

    n = {}
    for r in out:
        n[r["terrain"]] = n.get(r["terrain"], 0) + 1
    print("=== Classificazione automatica ===")
    for k, v in sorted(n.items(), key=lambda t: -t[1]):
        print(f"  {k:9s} {v}")

    # controllo: gli esagoni usati dagli scenari devono risultare mare
    bad = [r for r in out if r.get("used_by_scenarios") and r["terrain"] != SEA]
    print(f"\n=== Controllo contro gli scenari ufficiali ===")
    print(f"  esagoni usati dagli scenari: {len(used)}")
    print(f"  di cui NON classificati mare: {len(bad)}")
    for r in bad:
        print(f"    q={r['q']:3d} r={r['r']:3d}  ({r['cx']:.0f},{r['cy']:.0f})  "
              f"-> {r['terrain']} [{r['reason']}]  mare={r['sea']:.2f} terra={r['land']:.2f}")

    json.dump({"hexes": out}, open(os.path.join(REP, "terrain.json"), "w"), indent=2)

    # overlay diagnostico
    col = {SEA: (0, 200, 255), LAND: (120, 200, 60), BLOCKED: (255, 40, 40)}
    ov = im.copy()
    d = ImageDraw.Draw(ov, "RGBA")
    theta = lat["theta_deg"]
    for r in out:
        cs = [(r["cx"] + R * math.cos(math.radians(theta + 30 + 60 * k)),
               r["cy"] + R * math.sin(math.radians(theta + 30 + 60 * k))) for k in range(6)]
        c = col[r["terrain"]]
        d.polygon(cs, fill=(c[0], c[1], c[2], 70), outline=(c[0], c[1], c[2], 255))
        if r.get("used_by_scenarios"):
            d.ellipse([r["cx"] - 14, r["cy"] - 14, r["cx"] + 14, r["cy"] + 14],
                      fill=(255, 255, 0, 220))
    ov.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(REP, "terrain_overlay.png"))
    print("\nScritto reports/terrain.json + terrain_overlay.png")


if __name__ == "__main__":
    main()
