#!/usr/bin/env python3
"""
M1a - Calibrazione del reticolo esagonale di Atlantic Chase Map120.jpg

Strategia:
  1. Isola i pixel delle linee esagonali (chiare su mare azzurro) con un high-pass.
  2. Radon-like: proietta la maschera lungo 180 angoli, misura la "periodicita'"
     della proiezione -> i 3 angoli dominanti sono le orientazioni dei lati.
  3. Per ogni angolo dominante, autocorrelazione della proiezione -> passo.
  4. Deduce orientamento (pointy-top vs flat-top) e parametri del reticolo.

Output: reports/hex_calibration.json + immagini diagnostiche.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)              # atlantic_chase/
SRC = os.path.dirname(ROOT)               # Atlantic_Chase_v2-1/
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
OUT = os.path.join(ROOT, "reports")
os.makedirs(OUT, exist_ok=True)

# Regione di oceano aperto: poche etichette, nessuna tabella, nessuna costa.
# (scelta a mano guardando la mappa completa)
REGIONS = [
    ("atlantic", 950, 1250, 2650, 2350),
    ("norwegian", 2350, 300, 3050, 1000),
]


def line_mask(gray):
    """Pixel delle linee esagonali: piu' chiari del fondo locale."""
    bg = ndimage.uniform_filter(gray, size=61)
    hp = gray - bg
    # le linee sono chiare: tieni solo il positivo, normalizza robustamente
    hp = np.clip(hp, 0, None)
    s = np.percentile(hp, 99.0)
    if s <= 0:
        return np.zeros_like(hp)
    return np.clip(hp / s, 0, 1)


def projection_score(mask, angle_deg):
    """
    Ruota la maschera e somma lungo le colonne.
    Se l'angolo coincide con una famiglia di linee, la proiezione ha picchi
    forti e regolari -> varianza alta.
    """
    rot = ndimage.rotate(mask, angle_deg, reshape=False, order=1, mode="constant")
    # scarta i bordi introdotti dalla rotazione
    h, w = rot.shape
    m = int(min(h, w) * 0.18)
    rot = rot[m:h - m, m:w - m]
    proj = rot.sum(axis=0)
    proj = proj - ndimage.uniform_filter1d(proj, size=81)  # togli il trend
    return float(np.var(proj)), proj


def autocorr_period(proj, lo=60, hi=400):
    """Primo picco significativo dell'autocorrelazione -> passo in pixel."""
    p = proj - proj.mean()
    ac = np.correlate(p, p, mode="full")[len(p) - 1:]
    if ac[0] != 0:
        ac = ac / ac[0]
    hi = min(hi, len(ac) - 2)
    best, best_v = None, -2.0
    for lag in range(lo, hi):
        if ac[lag] > ac[lag - 1] and ac[lag] >= ac[lag + 1] and ac[lag] > best_v:
            best, best_v = lag, ac[lag]
    return best, best_v, ac


def analyse(name, box):
    x0, y0, x1, y1 = box
    im = Image.open(MAP).convert("L").crop((x0, y0, x1, y1))
    gray = np.asarray(im, dtype=np.float64)
    mask = line_mask(gray)

    Image.fromarray((mask * 255).astype(np.uint8)).save(
        os.path.join(OUT, f"mask_{name}.png"))

    # scansione grossolana poi fine
    scores = []
    for a in range(0, 180):
        v, _ = projection_score(mask, a)
        scores.append((a, v))
    scores.sort(key=lambda t: -t[1])

    # prendi i massimi locali separati di almeno 15 gradi
    peaks = []
    for a, v in scores:
        if all(min(abs(a - b), 180 - abs(a - b)) >= 15 for b, _ in peaks):
            peaks.append((a, v))
        if len(peaks) == 5:
            break

    result = {"region": name, "box": box, "orientations": []}
    for a, v in peaks:
        # raffina di +-1 grado a passo 0.25
        best_a, best_v, best_proj = a, v, None
        for da in np.arange(-1.5, 1.51, 0.25):
            vv, pp = projection_score(mask, a + da)
            if vv > best_v:
                best_a, best_v, best_proj = a + da, vv, pp
        if best_proj is None:
            _, best_proj = projection_score(mask, best_a)
        period, strength, _ = autocorr_period(best_proj)
        result["orientations"].append({
            "angle_deg": round(float(best_a), 2),
            "score": round(float(best_v), 2),
            "period_px": period,
            "ac_strength": round(float(strength), 3),
        })
    return result


def main():
    out = []
    for name, *box in REGIONS:
        print(f"[calib] analizzo regione {name} {box} ...", flush=True)
        r = analyse(name, tuple(box))
        out.append(r)
        for o in r["orientations"]:
            print(f"    angolo {o['angle_deg']:7.2f}  score {o['score']:12.1f}"
                  f"  passo {o['period_px']}  ac {o['ac_strength']}")
    with open(os.path.join(OUT, "hex_calibration_raw.json"), "w") as f:
        json.dump(out, f, indent=2)
    print("\nScritto reports/hex_calibration_raw.json")


if __name__ == "__main__":
    main()
