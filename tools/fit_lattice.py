#!/usr/bin/env python3
"""
M1a (3) - Fit globale del reticolo esagonale sull'intera mappa.

Da detect_centers.py sappiamo:
  - passo centro-centro s ~ 213.3 px
  - direzioni dei vicini a 44.5 + k*60 gradi  (reticolo ruotato di ~14.5 gradi)

Qui:
  1. rileva i centri su tutta la mappa (non solo su una finestra)
  2. fit ai minimi quadrati di (s, theta, origin) su tutti i centri affidabili
  3. enumera l'intero reticolo che copre la mappa
  4. produce un overlay a piena risoluzione per verifica visiva

Output: reports/lattice.json, reports/overlay_full.png, reports/overlay_zoom_*.png
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from scipy.optimize import least_squares
from scipy.spatial import cKDTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
OUT = os.path.join(ROOT, "reports")
os.makedirs(OUT, exist_ok=True)

S0 = 213.26          # passo iniziale
THETA0 = 44.49       # angolo della prima direzione dei vicini (gradi)


def line_mask(gray, bg_size=61):
    bg = ndimage.uniform_filter(gray, size=bg_size)
    hp = np.clip(gray - bg, 0, None)
    s = np.percentile(hp, 99.0)
    return np.clip(hp / s, 0, 1) if s > 0 else np.zeros_like(hp)


def detect_all_centers():
    im = Image.open(MAP).convert("L")
    W, H = im.size
    gray = np.asarray(im, dtype=np.float64)
    mask = line_mask(gray)
    binm = ndimage.binary_closing(mask > 0.35, structure=np.ones((3, 3)))
    dist = ndimage.distance_transform_edt(~binm)
    mx = ndimage.maximum_filter(dist, size=91)
    peaks = (dist == mx) & (dist > 40)
    lbl, n = ndimage.label(peaks)
    cents = ndimage.center_of_mass(peaks, lbl, range(1, n + 1))
    pts = np.array([(c[1], c[0]) for c in cents])
    print(f"[fit] {len(pts)} centri candidati su tutta la mappa ({W}x{H})")
    return pts, (W, H)


def basis(s, theta_deg):
    t = math.radians(theta_deg)
    e1 = np.array([s * math.cos(t), s * math.sin(t)])
    t2 = math.radians(theta_deg + 60.0)
    e2 = np.array([s * math.cos(t2), s * math.sin(t2)])
    return e1, e2


def fit(pts):
    """Minimizza la distanza dei centri rilevati dal reticolo ideale."""

    def residuals(p):
        s, th, ox, oy = p
        e1, e2 = basis(s, th)
        M = np.array([e1, e2]).T           # 2x2, colonne = base
        Minv = np.linalg.inv(M)
        rel = pts - np.array([ox, oy])
        qr = rel @ Minv.T                  # coordinate frazionarie
        snapped = np.round(qr)
        err = (qr - snapped) @ M.T         # errore in pixel
        return err.ravel()

    # origine iniziale: un centro rilevato vicino al centro mappa
    c0 = pts[np.argmin(np.linalg.norm(pts - pts.mean(axis=0), axis=1))]
    p0 = [S0, THETA0, c0[0], c0[1]]

    # robustezza: due passate, scartando gli outlier dopo la prima
    res = least_squares(residuals, p0, loss="soft_l1", f_scale=8.0)
    s, th, ox, oy = res.x
    e1, e2 = basis(s, th)
    M = np.array([e1, e2]).T
    Minv = np.linalg.inv(M)
    qr = (pts - np.array([ox, oy])) @ Minv.T
    err = np.linalg.norm((qr - np.round(qr)) @ M.T, axis=1)
    keep = err < 25.0
    print(f"[fit] passata 1: {keep.sum()}/{len(pts)} centri entro 25 px")

    def residuals2(p):
        s, th, ox, oy = p
        e1, e2 = basis(s, th)
        M = np.array([e1, e2]).T
        Minv = np.linalg.inv(M)
        rel = pts[keep] - np.array([ox, oy])
        qr = rel @ Minv.T
        return ((qr - np.round(qr)) @ M.T).ravel()

    res2 = least_squares(residuals2, res.x, loss="soft_l1", f_scale=4.0)
    s, th, ox, oy = res2.x
    e1, e2 = basis(s, th)
    M = np.array([e1, e2]).T
    Minv = np.linalg.inv(M)
    qr = (pts[keep] - np.array([ox, oy])) @ Minv.T
    err = np.linalg.norm((qr - np.round(qr)) @ M.T, axis=1)
    print(f"[fit] passata 2: s={s:.3f} theta={th:.4f} origin=({ox:.2f},{oy:.2f})")
    print(f"[fit] errore residuo: medio {err.mean():.2f} px, max {err.max():.2f} px, "
          f"p95 {np.percentile(err,95):.2f} px")
    return dict(s=float(s), theta=float(th), ox=float(ox), oy=float(oy)), keep, err


def hex_corners(c, s, theta_deg):
    """
    Vicini a theta + k*60  =>  i lati sono perpendicolari a queste direzioni,
    quindi i vertici stanno a theta + 30 + k*60, a distanza R = s/sqrt(3).
    """
    R = s / math.sqrt(3.0)
    return [(c[0] + R * math.cos(math.radians(theta_deg + 30 + 60 * k)),
             c[1] + R * math.sin(math.radians(theta_deg + 30 + 60 * k)))
            for k in range(6)]


def main():
    pts, (W, H) = detect_all_centers()
    par, keep, err = fit(pts)
    s, th, ox, oy = par["s"], par["theta"], par["ox"], par["oy"]
    e1, e2 = basis(s, th)
    M = np.array([e1, e2]).T
    Minv = np.linalg.inv(M)

    # enumera tutti gli esagoni che coprono la mappa (con margine)
    corners_img = np.array([[0, 0], [W, 0], [0, H], [W, H]], dtype=float)
    qr_c = (corners_img - np.array([ox, oy])) @ Minv.T
    qmin, qmax = int(math.floor(qr_c[:, 0].min())) - 2, int(math.ceil(qr_c[:, 0].max())) + 2
    rmin, rmax = int(math.floor(qr_c[:, 1].min())) - 2, int(math.ceil(qr_c[:, 1].max())) + 2

    hexes = []
    for q in range(qmin, qmax + 1):
        for r in range(rmin, rmax + 1):
            c = np.array([ox, oy]) + q * e1 + r * e2
            if -s <= c[0] <= W + s and -s <= c[1] <= H + s:
                hexes.append({"q": q, "r": r, "cx": round(float(c[0]), 2),
                              "cy": round(float(c[1]), 2)})
    print(f"[fit] reticolo: {len(hexes)} esagoni coprono la mappa "
          f"(q {qmin}..{qmax}, r {rmin}..{rmax})")

    out = {
        "map_image": "Atlantic Chase Map120.jpg",
        "map_size": [W, H],
        "spacing_px": round(s, 4),
        "theta_deg": round(th, 4),
        "origin_px": [round(ox, 3), round(oy, 3)],
        "circumradius_px": round(s / math.sqrt(3.0), 4),
        "inradius_px": round(s / 2.0, 4),
        "basis_e1": [round(float(e1[0]), 4), round(float(e1[1]), 4)],
        "basis_e2": [round(float(e2[0]), 4), round(float(e2[1]), 4)],
        "fit_residual_mean_px": round(float(err.mean()), 3),
        "fit_residual_max_px": round(float(err.max()), 3),
        "fit_inliers": int(keep.sum()),
        "fit_candidates": int(len(pts)),
        "q_range": [qmin, qmax],
        "r_range": [rmin, rmax],
        "hex_count": len(hexes),
        "hexes": hexes,
    }
    with open(os.path.join(OUT, "lattice.json"), "w") as f:
        json.dump(out, f, indent=2)

    # ---- overlay a piena risoluzione, poi ridotto per ispezione ----
    im = Image.open(MAP).convert("RGB")
    d = ImageDraw.Draw(im)
    for h in hexes:
        cs = hex_corners((h["cx"], h["cy"]), s, th)
        d.polygon(cs, outline=(255, 0, 0))
        d.line([cs[-1], cs[0]], fill=(255, 0, 0), width=3)
        for i in range(5):
            d.line([cs[i], cs[i + 1]], fill=(255, 0, 0), width=3)
        d.ellipse([h["cx"] - 5, h["cy"] - 5, h["cx"] + 5, h["cy"] + 5], fill=(255, 255, 0))
    im.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(OUT, "overlay_full.png"))
    for name, box in [("nw", (900, 200, 2100, 1000)),
                      ("center", (1400, 1200, 2600, 2000)),
                      ("uk", (2300, 900, 3500, 1700))]:
        im.crop(box).save(os.path.join(OUT, f"overlay_zoom_{name}.png"))
    print("Scritto reports/lattice.json + overlay_full.png + 3 zoom")


if __name__ == "__main__":
    main()
