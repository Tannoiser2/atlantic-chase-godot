#!/usr/bin/env python3
"""
M1a (4) - Allineamento del reticolo per correlazione FFT.

Il fit ai minimi quadrati sui centri rilevati fallisce: i candidati su terra e
sulle tabelle sono outlier troppo numerosi. Qui usiamo un metodo diretto e
molto piu' robusto:

  - la traslazione ottimale del reticolo e' il picco della cross-correlazione
    fra la maschera delle linee della mappa e uno stencil del reticolo disegnato
  - la cross-correlazione si calcola in una sola FFT per ogni coppia (theta, s)
  - si scandisce una griglia fine di (theta, s) e si tiene il picco piu' alto

Output: reports/lattice.json (definitivo) + overlay di verifica
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.signal import fftconvolve

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
OUT = os.path.join(ROOT, "reports")
os.makedirs(OUT, exist_ok=True)

# finestra di oceano aperto usata per l'allineamento
BOX = (950, 1250, 2650, 2350)


def line_mask_full():
    im = Image.open(MAP).convert("L")
    gray = np.asarray(im, dtype=np.float32)
    bg = ndimage.uniform_filter(gray, size=61)
    hp = np.clip(gray - bg, 0, None)
    s = np.percentile(hp, 99.0)
    return np.clip(hp / s, 0, 1).astype(np.float32), im.size


def hex_corners(cx, cy, s, theta):
    R = s / math.sqrt(3.0)
    return [(cx + R * math.cos(math.radians(theta + 30 + 60 * k)),
             cy + R * math.sin(math.radians(theta + 30 + 60 * k)))
            for k in range(6)]


def stencil(shape, s, theta, width=5):
    """Reticolo disegnato con origine al centro dell'immagine."""
    h, w = shape
    img = Image.new("F", (w, h), 0.0)
    d = ImageDraw.Draw(img)
    t = math.radians(theta)
    e1 = np.array([s * math.cos(t), s * math.sin(t)])
    e2 = np.array([s * math.cos(t + math.radians(60)), s * math.sin(t + math.radians(60))])
    o = np.array([w / 2.0, h / 2.0])
    n = int(max(w, h) / s) + 3
    for q in range(-n, n + 1):
        for r in range(-n, n + 1):
            c = o + q * e1 + r * e2
            if not (-s <= c[0] <= w + s and -s <= c[1] <= h + s):
                continue
            cs = hex_corners(c[0], c[1], s, theta)
            for i in range(6):
                d.line([cs[i], cs[(i + 1) % 6]], fill=1.0, width=width)
    a = np.asarray(img, dtype=np.float32)
    return a - a.mean()


def best_shift(mask, s, theta):
    st = stencil(mask.shape, s, theta)
    m = mask - mask.mean()
    corr = fftconvolve(m, st[::-1, ::-1], mode="same")
    idx = int(np.argmax(corr))
    dy, dx = np.unravel_index(idx, corr.shape)
    h, w = mask.shape
    # spostamento dell'origine rispetto al centro immagine
    return float(corr[dy, dx]), (dx - w / 2.0), (dy - h / 2.0)


def main():
    full, (W, H) = line_mask_full()
    x0, y0, x1, y1 = BOX
    mask = full[y0:y1, x0:x1]

    best = None
    print("[refine] scansione (theta, s) ...")
    for theta in np.arange(43.8, 45.31, 0.15):
        for s in np.arange(212.0, 214.61, 0.4):
            sc, dx, dy = best_shift(mask, float(s), float(theta))
            if best is None or sc > best[0]:
                best = (sc, float(theta), float(s), dx, dy)
                print(f"    theta={theta:6.2f} s={s:7.2f} score={sc:12.1f}  <- migliore")
    sc, theta, s, dx, dy = best

    # rifinitura fine attorno al migliore
    print("[refine] rifinitura ...")
    for theta_ in np.arange(theta - 0.15, theta + 0.151, 0.03):
        for s_ in np.arange(s - 0.4, s + 0.41, 0.1):
            sc_, dx_, dy_ = best_shift(mask, float(s_), float(theta_))
            if sc_ > sc:
                sc, theta, s, dx, dy = sc_, float(theta_), float(s_), dx_, dy_
    print(f"[refine] theta={theta:.4f}  s={s:.4f}  score={sc:.1f}")

    # origine assoluta in coordinate mappa
    ox = x0 + (x1 - x0) / 2.0 + dx
    oy = y0 + (y1 - y0) / 2.0 + dy
    print(f"[refine] origine reticolo = ({ox:.2f}, {oy:.2f})")

    t = math.radians(theta)
    e1 = np.array([s * math.cos(t), s * math.sin(t)])
    e2 = np.array([s * math.cos(t + math.radians(60)), s * math.sin(t + math.radians(60))])
    M = np.array([e1, e2]).T
    Minv = np.linalg.inv(M)

    # normalizza l'origine sull'esagono piu' vicino all'angolo alto-sinistro
    qr = (np.array([0.0, 0.0]) - np.array([ox, oy])) @ Minv.T
    shift = np.floor(qr)
    ox, oy = np.array([ox, oy]) + shift[0] * e1 + shift[1] * e2

    corners_img = np.array([[0, 0], [W, 0], [0, H], [W, H]], dtype=float)
    qr_c = (corners_img - np.array([ox, oy])) @ Minv.T
    qmin, qmax = int(math.floor(qr_c[:, 0].min())) - 1, int(math.ceil(qr_c[:, 0].max())) + 1
    rmin, rmax = int(math.floor(qr_c[:, 1].min())) - 1, int(math.ceil(qr_c[:, 1].max())) + 1

    hexes = []
    for q in range(qmin, qmax + 1):
        for r in range(rmin, rmax + 1):
            c = np.array([ox, oy]) + q * e1 + r * e2
            if -s * 0.6 <= c[0] <= W + s * 0.6 and -s * 0.6 <= c[1] <= H + s * 0.6:
                hexes.append({"q": q, "r": r,
                              "cx": round(float(c[0]), 2), "cy": round(float(c[1]), 2)})
    print(f"[refine] {len(hexes)} esagoni coprono la mappa")

    # qualita': quanto forte e' la maschera lungo i lati del reticolo scelto
    out = {
        "map_image": "Atlantic Chase Map120.jpg",
        "map_size": [W, H],
        "spacing_px": round(s, 4),
        "theta_deg": round(theta, 4),
        "origin_px": [round(float(ox), 3), round(float(oy), 3)],
        "circumradius_px": round(s / math.sqrt(3.0), 4),
        "inradius_px": round(s / 2.0, 4),
        "basis_e1": [round(float(e1[0]), 4), round(float(e1[1]), 4)],
        "basis_e2": [round(float(e2[0]), 4), round(float(e2[1]), 4)],
        "align_score": round(float(sc), 2),
        "q_range": [qmin, qmax], "r_range": [rmin, rmax],
        "hex_count": len(hexes),
        "hexes": hexes,
    }
    with open(os.path.join(OUT, "lattice.json"), "w") as f:
        json.dump(out, f, indent=2)

    im = Image.open(MAP).convert("RGB")
    d = ImageDraw.Draw(im)
    for h in hexes:
        cs = hex_corners(h["cx"], h["cy"], s, theta)
        for i in range(6):
            d.line([cs[i], cs[(i + 1) % 6]], fill=(255, 0, 0), width=3)
        d.ellipse([h["cx"] - 6, h["cy"] - 6, h["cx"] + 6, h["cy"] + 6], fill=(255, 255, 0))
    im.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(OUT, "overlay_full.png"))
    for name, box in [("nw", (900, 200, 2100, 1000)),
                      ("center", (1400, 1200, 2600, 2000)),
                      ("uk", (2300, 900, 3500, 1700)),
                      ("norway", (2600, 200, 3800, 1000))]:
        im.crop(box).save(os.path.join(OUT, f"overlay_zoom_{name}.png"))
    print("Scritto reports/lattice.json + overlay")


if __name__ == "__main__":
    main()
