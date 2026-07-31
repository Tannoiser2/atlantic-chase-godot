#!/usr/bin/env python3
"""
M1b (3) - Validazione indipendente del reticolo.

I 22 salvataggi ufficiali contengono pedine Traiettoria e Stazione piazzate a
mano sulla mappa. Se il reticolo e' corretto, ogni pedina deve cadere vicino a
un centro esagonale. Questo e' un test di correttezza che non dipende da come
abbiamo ricavato il reticolo.

Produce anche l'elenco degli esagoni effettivamente usati dagli scenari
ufficiali: e' il nucleo minimo della mappa giocabile.
"""
import csv
import json
import math
import os
from collections import Counter, defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REP = os.path.join(ROOT, "reports")


def load_lattice():
    with open(os.path.join(REP, "lattice.json")) as f:
        return json.load(f)


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xint = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < xint:
                inside = not inside
    return inside


def main():
    lat = load_lattice()
    e1 = np.array(lat["basis_e1"])
    e2 = np.array(lat["basis_e2"])
    o = np.array(lat["origin_px"])
    M = np.array([e1, e2]).T
    Minv = np.linalg.inv(M)

    with open(os.path.join(REP, "zones.json")) as f:
        zones = [z for z in json.load(f) if z["map"] == "Main Map"]

    def snap(x, y):
        qr = (np.array([x, y], dtype=float) - o) @ Minv.T
        # arrotondamento esagonale corretto: prova i 4 candidati interi vicini
        best, bestd = None, 1e18
        for dq in (math.floor(qr[0]), math.ceil(qr[0])):
            for dr in (math.floor(qr[1]), math.ceil(qr[1])):
                c = o + dq * e1 + dr * e2
                d = math.hypot(c[0] - x, c[1] - y)
                if d < bestd:
                    best, bestd = (int(dq), int(dr)), d
        return best, bestd

    files = sorted(f for f in os.listdir(os.path.join(REP, "vsav")) if f.endswith(".csv"))
    residuals = defaultdict(list)
    used_hexes = Counter()
    zone_hits = Counter()
    unresolved = []

    for fn in files:
        with open(os.path.join(REP, "vsav", fn)) as fh:
            for row in csv.DictReader(fh):
                if row["map"] != "Main Map" or row["kind"] != "piece":
                    continue
                x, y = int(row["x"]), int(row["y"])
                img = row["image"]
                zname = None
                for z in zones:
                    bx = z["bbox"]
                    if bx[0] <= x <= bx[2] and bx[1] <= y <= bx[3] and \
                            point_in_poly(x, y, z["polygon"]):
                        zname = z["name"]
                        break
                if zname:
                    zone_hits[zname] += 1
                    continue
                hx, d = snap(x, y)
                if img.startswith("Trajectory_"):
                    residuals["trajectory"].append(d)
                    used_hexes[hx] += 1
                elif img.startswith("Station_"):
                    residuals["station"].append(d)
                    used_hexes[hx] += 1
                elif img.startswith("Ship_") or img.startswith("Markers_") \
                        or img.startswith("Leader_"):
                    residuals["other"].append(d)
                    if d < 90:
                        used_hexes[hx] += 1
                else:
                    unresolved.append((fn, row["name"], x, y, d))

    print("=== Residui di aggancio al reticolo (px) ===")
    for k in ("trajectory", "station", "other"):
        v = np.array(residuals[k]) if residuals[k] else np.array([0.0])
        print(f"  {k:11s} n={len(residuals[k]):4d}  medio {v.mean():6.1f}  "
              f"mediana {np.median(v):6.1f}  p90 {np.percentile(v,90):6.1f}  max {v.max():6.1f}")
    print(f"\n  (apotema = {lat['inradius_px']:.1f} px: un residuo sotto questa soglia"
          f" significa 'dentro l'esagono giusto')")

    traj = np.array(residuals["trajectory"])
    ok = (traj < lat["inradius_px"]).mean() * 100 if len(traj) else 0
    st = np.array(residuals["station"])
    ok2 = (st < lat["inradius_px"]).mean() * 100 if len(st) else 0
    print(f"\n  Traiettorie dentro l'esagono: {ok:.1f}%")
    print(f"  Stazioni    dentro l'esagono: {ok2:.1f}%")

    print(f"\n=== Esagoni usati dagli scenari ufficiali: {len(used_hexes)} ===")
    qs = [h[0] for h in used_hexes]
    rs = [h[1] for h in used_hexes]
    print(f"  q in [{min(qs)},{max(qs)}]  r in [{min(rs)},{max(rs)}]")

    print(f"\n=== Pedine finite in una Zone (box porto / tracce): {sum(zone_hits.values())} ===")
    for z, c in zone_hits.most_common(20):
        print(f"  {z:28s} {c}")

    out = {
        "residuals": {k: [round(float(x), 2) for x in v] for k, v in residuals.items()},
        "used_hexes": [{"q": q, "r": r, "count": c} for (q, r), c in used_hexes.items()],
        "zone_hits": dict(zone_hits),
    }
    with open(os.path.join(REP, "lattice_validation.json"), "w") as f:
        json.dump(out, f, indent=2)
    print("\nScritto reports/lattice_validation.json")


if __name__ == "__main__":
    main()
