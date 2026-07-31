#!/usr/bin/env python3
"""
M1a (2) - Rilevamento diretto dei centri esagonali.

La calibrazione angolare dice che il reticolo e' regolare (3 famiglie a 60 gradi,
passo ~106.5 px). Qui evitiamo la deduzione analitica e misuriamo i centri:

  1. maschera delle linee (chiare sul mare)
  2. distance transform dell'inverso -> i centri sono i punti piu' lontani
     da qualunque linea
  3. massimi locali -> centri candidati
  4. istogramma dei vettori ai primi vicini -> base del reticolo

Output: reports/lattice_fit.json + reports/centers_overlay.png
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
OUT = os.path.join(ROOT, "reports")
os.makedirs(OUT, exist_ok=True)

# oceano aperto, pulito
BOX = (950, 1250, 2650, 2350)


def line_mask(gray, bg_size=61):
    bg = ndimage.uniform_filter(gray, size=bg_size)
    hp = np.clip(gray - bg, 0, None)
    s = np.percentile(hp, 99.0)
    return np.clip(hp / s, 0, 1) if s > 0 else np.zeros_like(hp)


def detect(box):
    x0, y0, x1, y1 = box
    im = Image.open(MAP).convert("L").crop(box)
    gray = np.asarray(im, dtype=np.float64)
    mask = line_mask(gray)

    binm = mask > 0.35
    binm = ndimage.binary_closing(binm, structure=np.ones((3, 3)))
    Image.fromarray((binm * 255).astype(np.uint8)).save(os.path.join(OUT, "bin_lines.png"))

    dist = ndimage.distance_transform_edt(~binm)
    # massimi locali con raggio minimo 45 px (meta' del passo misurato)
    mx = ndimage.maximum_filter(dist, size=91)
    peaks = (dist == mx) & (dist > 35)
    lbl, n = ndimage.label(peaks)
    cents = ndimage.center_of_mass(peaks, lbl, range(1, n + 1))
    pts = np.array([(c[1], c[0]) for c in cents])  # (x, y) locali
    print(f"[centers] {len(pts)} centri candidati")
    return pts, (x0, y0), mask


def lattice_basis(pts, kmax=6):
    """Vettori piu' frequenti verso i primi vicini -> base del reticolo."""
    from scipy.spatial import cKDTree
    tree = cKDTree(pts)
    vecs = []
    for p in pts:
        d, idx = tree.query(p, k=kmax + 1)
        for j in idx[1:]:
            v = pts[j] - p
            if v[0] < 0 or (abs(v[0]) < 1e-6 and v[1] < 0):
                v = -v  # canonicalizza il verso
            vecs.append(v)
    vecs = np.array(vecs)

    # clustering grezzo su griglia da 6 px
    key = np.round(vecs / 6.0).astype(int)
    from collections import Counter
    cnt = Counter(map(tuple, key))
    modes = []
    for k, c in cnt.most_common(40):
        v = np.array(k, dtype=float) * 6.0
        n = np.linalg.norm(v)
        if n < 40:
            continue
        if any(np.linalg.norm(v - m[0]) < 25 for m in modes):
            continue
        sel = vecs[np.all(np.abs(vecs - v) < 12, axis=1)]
        if len(sel) < 5:
            continue
        modes.append((sel.mean(axis=0), len(sel)))
        if len(modes) == 6:
            break
    modes.sort(key=lambda t: -t[1])
    return modes


def main():
    pts, origin, mask = detect(BOX)
    modes = lattice_basis(pts)
    print("\n[lattice] vettori dominanti fra centri adiacenti:")
    info = []
    for v, c in modes:
        ang = math.degrees(math.atan2(v[1], v[0])) % 180.0
        nrm = float(np.linalg.norm(v))
        print(f"    v = ({v[0]:8.2f},{v[1]:8.2f})  |v| = {nrm:7.2f}  ang = {ang:6.2f}  n = {c}")
        info.append({"vx": round(float(v[0]), 3), "vy": round(float(v[1]), 3),
                     "len": round(nrm, 3), "angle_deg": round(ang, 3), "count": c})

    # overlay diagnostico
    im = Image.open(MAP).crop(BOX).convert("RGB")
    d = ImageDraw.Draw(im)
    for (x, y) in pts:
        d.ellipse([x - 6, y - 6, x + 6, y + 6], outline=(255, 0, 0), width=3)
    im.save(os.path.join(OUT, "centers_overlay.png"))

    with open(os.path.join(OUT, "lattice_fit.json"), "w") as f:
        json.dump({"box": BOX, "n_centers": len(pts), "modes": info}, f, indent=2)
    print("\nScritto reports/lattice_fit.json e centers_overlay.png")


if __name__ == "__main__":
    main()
