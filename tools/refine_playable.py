#!/usr/bin/env python3
"""
M1c - Rifinitura dell'area giocabile per connessione del mare.

Il criterio della presenza delle linee sbagliava agli estremi: le tabelle e il
pannello della Battaglia hanno bordi dritti che passano per linee di reticolo,
e alcuni esagoni fuori cornice sono finiti fra i giocabili (verificato a mano:
a est della Danimarca non c'e' alcun reticolo, eppure 19,-7 risultava giocabile).

Criterio decisivo: l'oceano giocabile e' UNA regione connessa di pixel
azzurro-chiari. Si riempie a partire da un punto in mezzo all'Atlantico e si
tiene ogni esagono che ne contiene abbastanza.

  mare      (181,211,227)  ->  B-R alto, luminosita' alta   -> incluso
  pannello  (130,164,169)  ->  B-R alto, luminosita' bassa  -> escluso
  box porto (204,159,140)  ->  B-R negativo                 -> escluso
  tabelle   bianco/grigio  ->  B-R ~ 0                      -> escluso
  terra     (162,162,135)  ->  B-R negativo                 -> escluso

Gli esagoni usati dai 22 scenari ufficiali restano giocabili per definizione.

Output: aggiorna core/data/map_graph.json + reports/refine_overlay.png
"""
import json
import math
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
REP = os.path.join(ROOT, "reports")
GRAPH = os.path.join(ROOT, "core", "data", "map_graph.json")
ANNOT = os.path.join(ROOT, "core", "data", "map_annotations.json")

DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

# punti sicuramente in mare aperto, da cui partire col riempimento
SEEDS = [(1500, 1700), (2000, 2000), (2600, 700), (1200, 1200), (3000, 500)]
MIN_SEA_FRACTION = 0.22

# Esagoni esclusi dopo verifica visiva a forte ingrandimento: hanno abbastanza
# azzurro da passare il filtro del mare, ma sulla mappa NON c'e' alcun reticolo
# stampato perche' stanno oltre la cornice, sul pannello della Battaglia.
#
# Il criterio automatico "fuori cornice" (riempimento dai bordi dell'immagine)
# e' stato provato e scartato: la cornice non e' una curva chiusa ovunque, il
# riempimento tracima nell'oceano e cancellerebbe esagoni veri. Un elenco corto
# e verificato a occhio e' piu' onesto di un'euristica che sbaglia in silenzio.
MANUAL_EXCLUDE = {
    (19, -7),    # (3184,1287) oltre la cornice a est di Kiel, sul pannello Battaglia
    (19, -6),    # (3131,1494) idem
}


def main():
    g = json.load(open(GRAPH))
    lat = g["lattice"]
    R = lat["circumradius_px"]
    th = lat["theta_deg"]
    rad = int(lat["inradius_px"] * 0.75)

    val = json.load(open(os.path.join(REP, "lattice_validation.json")))
    used = {(h["q"], h["r"]) for h in val["used_hexes"]}

    # Esagoni che devono restare giocabili anche se sono tutta terraferma,
    # perche' contengono un porto (RB p.13: il porto appartiene al suo esagono).
    forced = set()
    if os.path.exists(ANNOT):
        ann = json.load(open(ANNOT))
        for h in ann.get("force_playable", {}).get("hexes", []):
            forced.add((h["q"], h["r"]))
    if forced:
        print("[refine] esagoni forzati giocabili (porti su terraferma): %s"
              % sorted(forced))

    im = Image.open(MAP).convert("RGB")
    W, H = im.size
    a = np.asarray(im, dtype=np.int16)
    bright = a.mean(axis=2)
    br = a[:, :, 2] - a[:, :, 0]
    # La cornice della mappa e' una linea scura continua (luminosita' 40-140,
    # misurata attraversandola vicino a Kiel). Il pannello della Battaglia sta
    # FUORI da essa ma in alcuni punti e' abbastanza chiaro e azzurrato da
    # passare il filtro del mare: senza barriera il riempimento vi trabocca e
    # promuove esagoni inesistenti (verificato: 19,-7 e 19,-6).
    frame = ndimage.binary_dilation(bright < 150, structure=np.ones((3, 3)))
    sea = (br > 12) & (bright > 178) & ~frame
    sea = ndimage.binary_closing(sea, structure=np.ones((5, 5)))

    lbl, n = ndimage.label(sea)
    seed_labels = set()
    for (sx, sy) in SEEDS:
        v = lbl[sy, sx]
        if v:
            seed_labels.add(int(v))
    if not seed_labels:
        raise SystemExit("nessun seme e' caduto in mare: controlla le coordinate")
    ocean = np.isin(lbl, list(seed_labels))
    print(f"[refine] oceano connesso: {ocean.sum()/1e6:.2f} Mpixel "
          f"({100.0*ocean.sum()/(W*H):.1f}% della mappa)")

    # Secondo criterio: la banda ESTERNA alla cornice. Riempiendo dai quattro
    # angoli dell'immagine sui pixel non scuri si ottiene tutto cio' che sta
    # fuori dal bordo stampato. Serve perche' il solo criterio del mare lascia
    # passare le zone chiare e azzurrate del pannello della Battaglia
    # (verificato a occhio: 19,-7 e 19,-6 sono fuori cornice, senza reticolo).
    lbl2, _ = ndimage.label(bright >= 150)
    corner_ids = set()
    for (cx_, cy_) in [(5, 5), (W - 5, 5), (5, H - 5), (W - 5, H - 5), (W - 5, H // 2)]:
        v = lbl2[cy_, cx_]
        if v:
            corner_ids.add(int(v))
    outside = np.isin(lbl2, list(corner_ids))
    print(f"[refine] fuori cornice: {outside.sum()/1e6:.2f} Mpixel")

    yy, xx = np.mgrid[-rad:rad + 1, -rad:rad + 1]
    disc = (xx * xx + yy * yy) <= rad * rad

    keep, drop = [], []
    for h in g["hexes"]:
        ix, iy = int(round(h["cx"])), int(round(h["cy"]))
        x0, x1, y0, y1 = ix - rad, ix + rad + 1, iy - rad, iy + rad + 1
        if x0 < 0 or y0 < 0 or x1 > W or y1 > H:
            frac, out_frac = 0.0, 1.0
        else:
            frac = float(ocean[y0:y1, x0:x1][disc].mean())
            out_frac = float(outside[y0:y1, x0:x1][disc].mean())
        h["sea_frac"] = round(frac, 3)
        h["outside_frac"] = round(out_frac, 3)
        key = (h["q"], h["r"])
        if key in MANUAL_EXCLUDE:
            h["_why"] = "escluso a mano (verificato: nessun reticolo stampato)"
            drop.append(h)
        elif key in forced or key in used or frac >= MIN_SEA_FRACTION:
            keep.append(h)
        else:
            h["_why"] = "troppo poco mare"
            drop.append(h)

    print(f"[refine] scartati {len(drop)} esagoni su {len(g['hexes'])}:")
    for h in sorted(drop, key=lambda d: -d["sea_frac"]):
        print(f"    q={h['q']:3d} r={h['r']:3d} ({h['cx']:6.0f},{h['cy']:6.0f}) "
              f"mare={h['sea_frac']:.2f} fuori={h['outside_frac']:.2f} "
              f"terra={h['land_frac']:.2f}  [{h['_why']}]")

    # ricalcola la componente principale e le adiacenze
    play = {(h["q"], h["r"]) for h in keep}
    seen, comps = set(), []
    for start in play:
        if start in seen:
            continue
        comp, dq = set(), deque([start])
        seen.add(start)
        while dq:
            c = dq.popleft()
            comp.add(c)
            for d in DIRS:
                nb = (c[0] + d[0], c[1] + d[1])
                if nb in play and nb not in seen:
                    seen.add(nb)
                    dq.append(nb)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    print(f"[refine] componenti: {[len(c) for c in comps]}")
    main_comp = comps[0]
    keep = [h for h in keep if (h["q"], h["r"]) in main_comp]
    play = main_comp

    for h in keep:
        q, r = h["q"], h["r"]
        h["neighbors"] = [{"dir": i, "q": q + d[0], "r": r + d[1]}
                          for i, d in enumerate(DIRS) if (q + d[0], r + d[1]) in play]
    g["hexes"] = keep
    g["hex_count"] = len(keep)
    deg = [len(h["neighbors"]) for h in keep]
    print(f"[refine] esagoni giocabili: {len(keep)}, grado medio "
          f"{sum(deg)/len(deg):.2f} (min {min(deg)}, max {max(deg)})")

    json.dump(g, open(GRAPH, "w"), indent=1)
    print("[refine] scritto core/data/map_graph.json")

    ov = im.copy()
    d = ImageDraw.Draw(ov, "RGBA")
    for h in keep:
        cs = [(h["cx"] + R * math.cos(math.radians(th + 30 + 60 * k)),
               h["cy"] + R * math.sin(math.radians(th + 30 + 60 * k))) for k in range(6)]
        col = (255, 200, 0, 80) if h["land_frac"] > 0.35 else (0, 220, 255, 55)
        d.polygon(cs, fill=col, outline=(255, 255, 255, 170))
    ov.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(REP, "refine_overlay.png"))
    print("[refine] scritto reports/refine_overlay.png")


if __name__ == "__main__":
    main()
