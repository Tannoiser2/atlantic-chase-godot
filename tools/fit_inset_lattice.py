#!/usr/bin/env python3
"""
Calibrazione del reticolo esagonale delle DUE MAPPE INSERTO.

    tools/.venv/bin/python tools/fit_inset_lattice.py            # misura e scrive
    tools/.venv/bin/python tools/fit_inset_lattice.py --check    # solo verifica

Cinque scenari solitari su quindici non si giocano sulla Mappa Operazionale ma
su un inserto: BL3 e N3 sul Mare del Nord, N1, N2 e N5 sul Mare di Norvegia. Il
reticolo di quegli inserti non era calibrato, e per questo i cinque scenari
erano dichiarati non giocabili.

Il metodo NON e' lo stesso della mappa grande. Li' c'erano 238 pedine ufficiali
del modulo VASSAL come verita' indipendente; qui non esiste nessun `.vsav`,
quindi la misura viene dall'immagine stampata e si valida sull'immagine
stampata:

  1. `ridge`: luminosita' meno la sua sfocatura, che isola le linee chiare
     degli esagoni dallo sfondo azzurro;
  2. maschera di solo mare aperto, per non contare costa, bande fuori mappa
     e scritte;
  3. ricerca esaustiva di (circumraggio, orientamento, origine) che massimizza
     la `ridge` media campionata lungo i sei lati di ogni esagono;
  4. raffinamento locale ripetuto attorno all'ottimo.

Il punteggio e' la prova: un reticolo sbagliato campiona sfondo e scende
subito. `--check` NON rifa' la scansione grezza - venti minuti - ma riparte dal
dato salvato e lo raffina: se il salvato e' ancora l'ottimo il raffinamento non
lo muove, e una regressione nell'immagine o nel metodo si vede lo stesso.

RISULTATO. I due inserti condividono UN SOLO reticolo, e quel reticolo e' lo
stesso della Mappa Operazionale: passo 213.9 px contro 213.5, circumraggio
123.50 contro 123.26, direzione di base 44.25 gradi contro 44.28. Non e' una
coincidenza da interpretare: GMT stampa gli inserti alla stessa scala esagonale
della mappa grande.

ATTENZIONE a che cosa questo NON risolve. Il reticolo e' la geometria, non la
mappa: mancano ancora la nomenclatura degli esagoni, i porti costieri
(Vestfjorden, Bud, Andalsnes, Bergen, Methil...), i lati "not adjacent"
stampati lungo la costa, e le caselle fuori mappa (Murmansk, Kiel, Scapa Flow,
Denmark Strait, e le frecce verso Bear Island, Jan Mayen e le Shetlands). I
cinque scenari restano dichiarati non giocabili finche' non ci sono anche
quelli.
"""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, map_coordinates

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "core", "data", "map_insets.json")

INSETS = [
    ("map_north_sea", "Mappa Inserto del Mare del Nord", ["BL3", "N3"]),
    ("map_norwegian_sea", "Mappa Inserto del Mare di Norvegia", ["N1", "N2", "N5"]),
]

# Punto di partenza della ricerca grezza. Sono estremi larghi: l'ottimo non e'
# stato scelto, e' stato trovato.
COARSE_R = np.arange(100.0, 165.0, 2.5)
COARSE_THETA = np.arange(0.0, 60.0, 0.5)


def load_ridge(path):
    """Luminosita' meno la sua sfocatura: isola le linee chiare degli esagoni."""
    a = np.asarray(Image.open(path).convert("RGB")).astype(float)
    lum = a.mean(2)
    ridge = np.clip(lum - gaussian_filter(lum, 14), 0, None)
    return gaussian_filter(ridge, 2), a


def sea_mask(a):
    """Solo mare aperto. Costa, bande fuori mappa e scritte falserebbero il conto."""
    red, _green, blue = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    m = (blue > red + 8) & (blue > 120) & (red > 120)
    m[:105, :] = False
    m[1250:, :] = False
    m[:, :35] = False
    m[:, 640:] = False
    return m


def _basis(circumradius, theta_deg):
    th = math.radians(theta_deg)
    pitch = circumradius * math.sqrt(3.0)
    phi = th + math.pi / 6.0
    e1 = np.array([pitch * math.cos(phi), pitch * math.sin(phi)])
    e2 = np.array([pitch * math.cos(phi + math.pi / 3.0),
                   pitch * math.sin(phi + math.pi / 3.0)])
    return th, pitch, e1, e2


def _edge_samples(circumradius, th, per_edge=20):
    verts = [np.array([circumradius * math.cos(th + k * math.pi / 3.0),
                       circumradius * math.sin(th + k * math.pi / 3.0)])
             for k in range(6)]
    pts = []
    for k in range(6):
        p, q = verts[k], verts[(k + 1) % 6]
        for t in np.linspace(0.0, 1.0, per_edge, endpoint=False):
            pts.append(p + (q - p) * t)
    return np.array(pts)


def score(ridge, sea, circumradius, theta_deg, ox, oy, per_edge=20):
    """Media della `ridge` lungo i lati di tutti gli esagoni che cadono in mare."""
    height, width = ridge.shape
    th, _pitch, e1, e2 = _basis(circumradius, theta_deg)
    samples = _edge_samples(circumradius, th, per_edge)
    blocks = []
    for i in range(-4, 9):
        for j in range(-7, 9):
            c = np.array([ox, oy]) + i * e1 + j * e2
            if -circumradius < c[0] < width + circumradius \
                    and -circumradius < c[1] < height + circumradius:
                blocks.append(c + samples)
    if not blocks:
        return -1.0, 0
    p = np.concatenate(blocks)
    xi, yi = p[:, 0], p[:, 1]
    inside = (xi > 0) & (xi < width - 1) & (yi > 0) & (yi < height - 1)
    xi, yi = xi[inside], yi[inside]
    if len(xi) < 400:
        return -1.0, 0
    m = sea[yi.astype(int), xi.astype(int)]
    if m.sum() < 400:
        return -1.0, 0
    return float(map_coordinates(ridge, [yi[m], xi[m]], order=1).mean()), int(m.sum())


def refine(ridge, sea, best):
    """Raffinamento locale attorno a un punto di partenza."""
    for _ in range(4):
        _s, r0, t0, x0, y0 = best
        for circumradius in np.arange(r0 - 3, r0 + 3.01, 0.5):
            for theta in np.arange(t0 - 1.5, t0 + 1.51, 0.25):
                for ox in np.arange(x0 - 12, x0 + 12.1, 3):
                    for oy in np.arange(y0 - 12, y0 + 12.1, 3):
                        s, _n = score(ridge, sea, circumradius, theta, ox, oy)
                        if s > best[0]:
                            best = (s, circumradius, theta, ox, oy)
    return best


def fit(ridge, sea, start=None):
    """Ricerca esaustiva poi raffinamento. Con `start` salta la ricerca grezza:
    e' il modo in cui `--check` verifica che l'ottimo salvato sia ancora
    l'ottimo, senza rifare venti minuti di scansione."""
    if start is not None:
        s, _n = score(ridge, sea, *start)
        return refine(ridge, sea, (s,) + tuple(start))
    best = (-1.0, 0.0, 0.0, 0.0, 0.0)
    for circumradius in COARSE_R:
        for theta in COARSE_THETA:
            step = circumradius * math.sqrt(3.0) / 12.0
            for ox in np.arange(0.0, circumradius * math.sqrt(3.0), step):
                for oy in np.arange(0.0, circumradius * math.sqrt(3.0), step):
                    s, _n = score(ridge, sea, circumradius, theta, ox, oy, per_edge=14)
                    if s > best[0]:
                        best = (s, circumradius, theta, ox, oy)
    return refine(ridge, sea, best)


def overlay(path, circumradius, theta_deg, ox, oy, dest):
    """Verifica visiva: il reticolo rosso deve cadere sulle linee stampate."""
    th, _pitch, e1, e2 = _basis(circumradius, theta_deg)
    img = Image.open(path).convert("RGB")
    draw = ImageDraw.Draw(img)
    for i in range(-4, 9):
        for j in range(-7, 9):
            c = np.array([ox, oy]) + i * e1 + j * e2
            draw.polygon([(c[0] + circumradius * math.cos(th + k * math.pi / 3.0),
                           c[1] + circumradius * math.sin(th + k * math.pi / 3.0))
                          for k in range(6)], outline=(255, 0, 0))
    img.save(dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="rifa' la misura e la confronta col dato salvato")
    ap.add_argument("--overlay-dir", default=None,
                    help="cartella dove scrivere gli overlay di verifica")
    args = ap.parse_args()

    saved = None
    if args.check:
        with open(OUT) as f:
            saved = json.load(f)

    measured = {}
    for key, label, scenarios in INSETS:
        path = os.path.join(ROOT, "assets", "boards", "%s.jpg" % key)
        ridge, rgb = load_ridge(path)
        sea = sea_mask(rgb)
        start = None
        if saved is not None:
            lat = saved["insets"][key]["lattice"]
            start = (lat["circumradius_px"], lat["theta_deg"],
                     lat["origin_px"][0], lat["origin_px"][1])
        s, circumradius, theta, ox, oy = fit(ridge, sea, start)
        _s, samples = score(ridge, sea, circumradius, theta, ox, oy)
        _th, pitch, e1, e2 = _basis(circumradius, theta)
        measured[key] = {
            "name": label,
            "image": "assets/boards/%s.jpg" % key,
            "image_size": list(Image.open(path).size),
            "scenarios": scenarios,
            "lattice": {
                "circumradius_px": round(circumradius, 4),
                "spacing_px": round(pitch, 4),
                "inradius_px": round(pitch / 2.0, 4),
                # `theta_deg` e' l'angolo dei VERTICI. La mappa grande in
                # core/data/map_graph.json usa invece la direzione di BASE, che
                # per un reticolo esagonale e' 30 gradi piu' avanti. Le due
                # convenzioni vanno tenute distinte o il reticolo esce ruotato.
                "theta_deg": round(theta, 4),
                "basis_theta_deg": round(theta + 30.0, 4),
                "origin_px": [round(ox, 4), round(oy, 4)],
                "basis_e1": [round(e1[0], 4), round(e1[1], 4)],
                "basis_e2": [round(e2[0], 4), round(e2[1], 4)],
            },
            "fit_score": round(s, 4),
            "fit_samples": samples,
        }
        print("%-38s punteggio %6.3f  circumraggio %.2f  passo %.2f  "
              "vertici %.2f deg  base %.2f deg  origine (%.1f, %.1f)  campioni %d"
              % (label, s, circumradius, pitch, theta, theta + 30.0, ox, oy, samples))
        if args.overlay_dir:
            overlay(path, circumradius, theta, ox, oy,
                    os.path.join(args.overlay_dir, "fit_%s.png" % key))

    if args.check:
        bad = 0
        for key in measured:
            a = saved["insets"][key]["lattice"]
            b = measured[key]["lattice"]
            for field, tol in (("circumradius_px", 0.6), ("theta_deg", 0.3)):
                if abs(a[field] - b[field]) > tol:
                    print("DIVERSO %s.%s: salvato %s, misurato %s"
                          % (key, field, a[field], b[field]))
                    bad += 1
            for k in range(2):
                if abs(a["origin_px"][k] - b["origin_px"][k]) > 4.0:
                    print("DIVERSO %s.origin_px[%d]: salvato %s, misurato %s"
                          % (key, k, a["origin_px"][k], b["origin_px"][k]))
                    bad += 1
        print("VERIFICA: %s" % ("OK" if bad == 0 else "%d differenze" % bad))
        raise SystemExit(1 if bad else 0)

    doc = {
        "generated_by": "tools/fit_inset_lattice.py",
        "method": ("Fit del reticolo sull'immagine stampata: ridge = luminosita' "
                   "meno la sua sfocatura, maschera di solo mare aperto, ricerca "
                   "esaustiva di circumraggio/orientamento/origine che massimizza "
                   "la ridge media lungo i sei lati di ogni esagono, poi "
                   "raffinamento locale. Non esistono pedine VASSAL per gli "
                   "inserti: la verita' indipendente usata per la mappa grande "
                   "qui non c'e', quindi la misura si valida sull'immagine."),
        "finding": ("I due inserti condividono un solo reticolo, ed e' lo stesso "
                    "della Mappa Operazionale: passo 213.9 px contro 213.5, "
                    "circumraggio 123.50 contro 123.26, direzione di base 44.25 "
                    "gradi contro 44.28."),
        "still_missing": ("Il reticolo e' la geometria, non la mappa. Mancano la "
                          "nomenclatura degli esagoni, i porti costieri, i lati "
                          "'not adjacent' stampati lungo la costa e le caselle "
                          "fuori mappa. I cinque scenari restano dichiarati non "
                          "giocabili finche' non ci sono anche quelli."),
        "insets": measured,
    }
    with open(OUT, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("scritto %s" % os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
