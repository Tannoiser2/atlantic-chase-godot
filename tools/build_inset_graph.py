#!/usr/bin/env python3
"""
Nomenclatura e grafo degli esagoni delle DUE MAPPE INSERTO.

    tools/.venv/bin/python tools/build_inset_graph.py
    tools/.venv/bin/python tools/build_inset_graph.py --overlay-dir /tmp

Secondo passo dopo `tools/fit_inset_lattice.py`, che misura il reticolo. Qui il
reticolo diventa un elenco di esagoni con un nome, una classificazione del
terreno e le adiacenze.

## Come si chiamano gli esagoni

Coordinate assiali `(q, r)`, come `core/data/map_graph.json` per la mappa
grande, con le stesse sei direzioni. L'origine NON e' scelta a occhio: `(0, 0)`
e' la cella del reticolo il cui centro e' piu' vicino all'angolo in alto a
sinistra della CORNICE STAMPATA, e la cornice e' misurata dall'immagine, non
decisa. `q` cresce lungo `e1`, `r` lungo `e2`.

E' una convenzione interna, non una regola GMT: sugli inserti non c'e' nessuna
numerazione stampata da rispettare, esattamente come sulla mappa grande. Quello
che conta e' che sia riproducibile, e lo e': stessa immagine, stessi nomi.

## Come si classifica il terreno

Quattro categorie, per colore, campionando punti dentro l'esagono:

  fuori     oltre la cornice stampata, misurata riga per riga e colonna per
            colonna (x 30..992, y 30..1292 su tutte e due le immagini);
  casella   le bande e i riquadri fuori mappa stampati DENTRO la cornice -
            Murmansk, Kiel, Scapa Flow, Portsmouth, Denmark Strait, Mare di
            Norvegia. Sono zone di sosta, non esagoni;
  terra     l'oliva della terraferma;
  mare      l'azzurro.

Un esagono e' giocabile se e' abbastanza mare. Poi due pulizie topologiche, le
stesse che `build_map_graph.py` fa sulla mappa grande, perche' i criteri locali
sbagliano sulle coste frastagliate e quelli topologici no:

  1. si tiene solo la componente connessa piu' grande: gli isolotti di esagoni
     staccati sono artefatti del colore;
  2. si riempiono i buchi: un esagono circondato solo da esagoni giocabili e'
     giocabile.

## Le frecce "non adiacente"

Regolamento p.4: "non e' consentita una Traiettoria attraverso esagoni 'non
adiacenti'. E' consentito il Supporto Aereo". La FAQ di p.44 lo conferma. Il
riquadro del Canale KW sulla stessa pagina dice che "i due esagoni collegati da
una freccia" sono i due interessati: la freccia scavalca il lato che nega.

Le posizioni sono lette sulle immagini ingrandite col reticolo etichettato
sopra; il lato lo ricava il programma, prendendo i due esagoni piu' vicini e
fermandosi se non risultano adiacenti. Sei frecce sul Mare del Nord, tre sul
Mare di Norvegia.

Quando una freccia tocca un esagono che la classificazione ha scartato, il lato
viene marcato `disputed` invece di essere corretto di nascosto. Il fascicolo
stampa una freccia per negare un'adiacenza, e negarla ha senso solo fra esagoni
in gioco: o il colore ha sbagliato, o la freccia e' solo un avviso
cartografico. Non si decide qui.

## Che cosa questo NON fa

Non collega le caselle fuori mappa e non mette le basi aeree. Finche' mancano
quelle, piu' un secondo MapGraph nel motore e il disegno dell'inserto nella
GUI, i cinque scenari inserto restano dichiarati non giocabili. La verita'
indipendente per validarli sono le illustrazioni di schieramento del fascicolo,
che disegnano i segmenti di Traiettoria iniziali sull'inserto.
"""
import argparse
import json
import math
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LATTICE = os.path.join(ROOT, "core", "data", "map_insets.json")
OUT = os.path.join(ROOT, "core", "data", "inset_graphs.json")

# Le sei direzioni assiali, nello stesso ordine che usa il codice Godot e
# `tools/build_map_graph.py`. Cambiarne l'ordine cambia i numeri `dir` salvati.
DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

# Cornice stampata, misurata sul salto di luminosita' ai bordi. Identica sulle
# due immagini perche' GMT le stampa dallo stesso modello.
FRAME = (30, 30, 992, 1292)

# Un esagono e' giocabile da questa frazione di mare in su. Sotto, la costa
# norvegese e le isole scozzesi porterebbero dentro mezze penisole.
SEA_MIN = 0.45

# I nomi dei porti sono LETTI sull'immagine stampata, non dedotti. La chiave e'
# la posizione del pallino trovata dal rilevatore; se un pallino resta senza
# nome o un nome senza pallino il programma si ferma, cosi' una modifica
# all'immagine o al rilevatore non passa in silenzio con meta' dei porti.
#
# Attenzione all'angolo in basso a destra del Mare del Nord, dove le etichette
# sono fitte: il pallino ciano accanto a "KW Kanal" e' KIEL (l'etichetta sta
# sotto), quello piu' a sinistra e' Wilhelmshaven. Verificato su ritaglio
# ingrandito.
PORT_NAMES = {
    "map_north_sea": [
        ((179, 155), "Scapa Flow"),
        ((38, 545), "Methil"),
        ((911, 257), "Bergen"),
        ((861, 495), "Stavanger"),
        ((827, 565), "Egersund"),
        ((957, 664), "Kristiansand"),
        ((882, 1238), "Kiel"),
        ((658, 1278), "Wilhelmshaven"),
    ],
    "map_norwegian_sea": [
        ((903, 69), "Tromso"),
        ((866, 192), "Harstad"),
        ((920, 214), "Narvik"),
        ((876, 387), "Bodo"),
        ((865, 774), "Namsos"),
        ((867, 893), "Trondheim"),
        ((706, 1021), "Bud"),
        ((765, 1041), "Andalsnes"),
    ],
}
NAME_TOLERANCE_PX = 12

# Le frecce "non adiacente", lette sulle immagini ingrandite col reticolo
# etichettato sopra. Regolamento p.4: "non e' consentita una Traiettoria
# attraverso esagoni 'non adiacenti'. E' consentito il Supporto Aereo", e la
# FAQ di p.44 lo ripete: "una Traiettoria puo' collegare solamente esagoni
# adiacenti, non quelli attraverso una freccia 'non adiacente'".
#
# La posizione e' il centro della freccia. Il riquadro del Canale KW a p.4 dice
# che "i due esagoni collegati da una freccia" sono i due interessati, quindi il
# lato negato e' quello che la freccia scavalca: il programma lo ricava dai due
# esagoni piu' vicini e si ferma se non sono adiacenti.
NOT_ADJACENT = {
    "map_north_sea": [
        ((70, 385), "Scozia, fra Moray Firth e Firth of Forth"),
        ((78, 1180), "Gran Bretagna, fra The Wash e il Tamigi"),
        ((492, 1262), "Paesi Bassi, Texel"),
        ((880, 535), "Norvegia, fra Stavanger ed Egersund"),
        ((918, 1105), "Jutland"),
        ((880, 1198), "Kiel Bay"),
    ],
    "map_norwegian_sea": [
        ((945, 720), "Norvegia, a nord di Namsos"),
        ((915, 940), "Norvegia, a Trondheim"),
        ((790, 1120), "Norvegia, a sud di Andalsnes"),
    ],
}


def find_port_dots(a):
    """I pallini dei porti stampati sull'inserto.

    Quattro forme, e ognuna ha il suo colore: rosso pieno (Scapa Flow,
    Methil), ciano pieno (Wilhelmshaven, Kiel), nero pieno (Bergen, Narvik,
    Trondheim) e cerchio vuoto col bordo scuro (tutti gli altri).

    I cerchi vuoti sono la parte difficile, perche' le lettere 'o' ed 'e'
    delle etichette hanno la stessa forma e la stessa taglia. Il discriminante
    misurato e' il CUORE: quello di un porto e' bianco pieno (luminosita' oltre
    245), quello di una lettera non arriva mai a 170.
    """
    lum = a.mean(2)
    red, green, blue = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    x0, y0, x1, y1 = FRAME
    frame = np.zeros(a.shape[:2], bool)
    frame[y0:y1, x0:x1] = True
    out = []

    def filled(mask, kind):
        lab, n = ndimage.label(mask)
        for sl, idx in zip(ndimage.find_objects(lab), range(1, n + 1)):
            h = sl[0].stop - sl[0].start
            w = sl[1].stop - sl[1].start
            area = int((lab[sl] == idx).sum())
            if not (40 <= area <= 300) or max(h, w) == 0:
                continue
            if min(h, w) / max(h, w) < 0.65 or area / float(h * w) < 0.55:
                continue
            cy, cx = ndimage.center_of_mass(lab == idx)
            out.append((float(cx), float(cy), kind))

    filled((red > 170) & (green < 90) & (blue < 100) & frame, "rosso")
    filled((blue > 200) & (green > 130) & (red < 110) & frame, "ciano")
    filled((red < 70) & (green < 70) & (blue < 70) & frame, "nero")

    dark = (lum < 105) & frame
    lab, n = ndimage.label(dark)
    for sl, idx in zip(ndimage.find_objects(lab), range(1, n + 1)):
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        if not (8 <= h <= 18 and 8 <= w <= 18):
            continue
        if min(h, w) / max(h, w) < 0.7:
            continue
        fill = int((lab[sl] == idx).sum()) / float(h * w)
        if not (0.20 <= fill <= 0.80):
            continue
        cy = (sl[0].start + sl[0].stop) // 2
        cx = (sl[1].start + sl[1].stop) // 2
        if lum[cy - 1:cy + 2, cx - 1:cx + 2].mean() < 245:
            continue
        out.append((float(cx), float(cy), "cerchio"))
    return out


def name_dots(key, dots):
    """Accoppia i pallini rilevati ai nomi letti sulla mappa, e si ferma se
    l'accoppiamento non e' uno a uno."""
    wanted = list(PORT_NAMES[key])
    named = []
    for cx, cy, kind in dots:
        hit = None
        for i, ((nx, ny), nm) in enumerate(wanted):
            if math.hypot(cx - nx, cy - ny) <= NAME_TOLERANCE_PX:
                hit = i
                break
        if hit is None:
            raise SystemExit("%s: pallino a (%.0f, %.0f) senza nome; "
                             "aggiungilo a PORT_NAMES dopo averlo letto sulla mappa"
                             % (key, cx, cy))
        named.append({"name": wanted.pop(hit)[1], "kind": kind,
                      "dot_px": [round(cx, 1), round(cy, 1)]})
    if wanted:
        raise SystemExit("%s: nomi senza pallino: %s"
                         % (key, ", ".join(nm for _p, nm in wanted)))
    return sorted(named, key=lambda d: d["name"])


def classify_pixels(a):
    """Maschere per mare, terra e caselle fuori mappa."""
    red, green, blue = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    sea = (blue > red + 8) & (blue > 120) & (red > 100)
    land = (red > 110) & (green > 110) & (blue < green + 6) & (~sea)
    # Le bande e i riquadri fuori mappa sono gli unici colori saturi: viola
    # (Murmansk, Kiel, Mare di Norvegia), rosso mattone (Scapa Flow,
    # Portsmouth). Il mare e la terra sono entrambi slavati.
    mx = a.max(2)
    mn = a.min(2)
    box = ((mx - mn) > 55) & (~sea)
    land = land & (~box)
    return sea, land, box


def hex_points(circumradius, th, n=9):
    """Griglia di campionamento dentro un esagono unitario, in coordinate locali."""
    pts = []
    inradius = circumradius * math.sqrt(3.0) / 2.0
    for u in np.linspace(-circumradius, circumradius, n * 2):
        for v in np.linspace(-inradius, inradius, n * 2):
            # test di appartenenza all'esagono, nel suo sistema non ruotato
            x, y = abs(u), abs(v)
            if y > inradius:
                continue
            if x > circumradius:
                continue
            if y > math.sqrt(3.0) * (circumradius - x):
                continue
            pts.append((u * math.cos(th) - v * math.sin(th),
                        u * math.sin(th) + v * math.cos(th)))
    return np.array(pts)


def build(key, meta, rgb, overlay_dir=None):
    lat = meta["lattice"]
    circumradius = lat["circumradius_px"]
    th = math.radians(lat["theta_deg"])
    e1 = np.array(lat["basis_e1"])
    e2 = np.array(lat["basis_e2"])
    origin = np.array(lat["origin_px"])
    height, width = rgb.shape[:2]
    sea, land, box = classify_pixels(rgb)
    samples = hex_points(circumradius, th)

    x0, y0, x1, y1 = FRAME

    # L'origine dei nomi: la cella piu' vicina all'angolo in alto a sinistra
    # della cornice. Si ricava da (e1, e2) invertendo la base.
    basis = np.array([[e1[0], e2[0]], [e1[1], e2[1]]])
    ij = np.linalg.solve(basis, np.array([x0, y0]) - origin)
    i0, j0 = int(round(ij[0])), int(round(ij[1]))

    cells = {}
    span = 12
    for i in range(i0 - span, i0 + span + 1):
        for j in range(j0 - span, j0 + span + 1):
            c = origin + i * e1 + j * e2
            if not (x0 - circumradius < c[0] < x1 + circumradius
                    and y0 - circumradius < c[1] < y1 + circumradius):
                continue
            p = samples + c
            xi = np.clip(p[:, 0].astype(int), 0, width - 1)
            yi = np.clip(p[:, 1].astype(int), 0, height - 1)
            inside_frame = (p[:, 0] >= x0) & (p[:, 0] < x1) \
                & (p[:, 1] >= y0) & (p[:, 1] < y1)
            total = len(p)
            outside_frac = float((~inside_frame).sum()) / total
            if outside_frac > 0.98:
                continue
            m = inside_frame
            sea_frac = float(sea[yi[m], xi[m]].sum()) / total
            land_frac = float(land[yi[m], xi[m]].sum()) / total
            box_frac = float(box[yi[m], xi[m]].sum()) / total
            cells[(i - i0, j - j0)] = {
                "q": i - i0,
                "r": j - j0,
                "cx": round(float(c[0]), 2),
                "cy": round(float(c[1]), 2),
                "sea_frac": round(sea_frac, 3),
                "land_frac": round(land_frac, 3),
                "box_frac": round(box_frac, 3),
                "outside_frac": round(outside_frac, 3),
            }

    for h in cells.values():
        h["playable"] = h["sea_frac"] >= SEA_MIN
        h["reason"] = "mare" if h["playable"] else "poco mare"

    # Un esagono che contiene un porto stampato e' giocabile, punto: una Task
    # Force ci deve poter Completare. E' la stessa regola che la mappa grande
    # applica con `force_playable` in map_annotations.json, e serve anche qui -
    # senza, il colore buttava via Methil, Wilhelmshaven, Kiel, Kristiansand,
    # Trondheim, Namsos, Andalsnes e Tromso, che sono meta' terraferma.
    ports = name_dots(key, find_port_dots(rgb))
    inv = np.linalg.inv(np.array([[e1[0], e2[0]], [e1[1], e2[1]]]))
    for port in ports:
        px, py = port["dot_px"]
        approx = inv.dot(np.array([px, py]) - origin)
        best = None
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                i = int(round(approx[0])) + di
                j = int(round(approx[1])) + dj
                c = origin + i * e1 + j * e2
                d = math.hypot(px - c[0], py - c[1])
                if best is None or d < best[0]:
                    best = (d, i - i0, j - j0)
        _d, q, r = best
        port["q"], port["r"] = q, r
        if (q, r) in cells:
            cells[(q, r)]["playable"] = True
            cells[(q, r)]["reason"] = "contiene il porto di %s" % port["name"]
        else:
            raise SystemExit("%s: il porto di %s cade in (%d,%d), fuori dal "
                             "reticolo enumerato" % (key, port["name"], q, r))

    # ---- 1. componente connessa principale ----
    comps = []
    seen = set()
    for k, h in cells.items():
        if not h["playable"] or k in seen:
            continue
        comp = []
        dq = deque([k])
        seen.add(k)
        while dq:
            cur = dq.popleft()
            comp.append(cur)
            for dqr in DIRS:
                nb = (cur[0] + dqr[0], cur[1] + dqr[1])
                if nb in cells and cells[nb]["playable"] and nb not in seen:
                    seen.add(nb)
                    dq.append(nb)
        comps.append(comp)
    if comps:
        comps.sort(key=len, reverse=True)
        port_hexes = {(p["q"], p["r"]) for p in ports}
        for comp in comps[1:]:
            for k in comp:
                if k in port_hexes:
                    continue
                cells[k]["playable"] = False
                cells[k]["reason"] = "isolotto staccato dall'oceano principale"

    # ---- 2. riempimento buchi ----
    for k, h in cells.items():
        if h["playable"]:
            continue
        nbs = [(k[0] + d[0], k[1] + d[1]) for d in DIRS]
        present = [n for n in nbs if n in cells]
        if len(present) == 6 and all(cells[n]["playable"] for n in present):
            h["playable"] = True
            h["reason"] = "buco circondato da mare"

    # ---- adiacenze fra soli esagoni giocabili ----
    playable = {k: h for k, h in cells.items() if h["playable"]}
    for k, h in playable.items():
        h["neighbors"] = []
        for d_index, d in enumerate(DIRS):
            nb = (k[0] + d[0], k[1] + d[1])
            if nb in playable:
                h["neighbors"].append({"dir": d_index, "q": nb[0], "r": nb[1]})
        h["coastal"] = len(h["neighbors"]) < 6

    # Un esagono mezzo terra e mezzo mare il colore non lo sa decidere, e
    # fingere di si' sarebbe la solita regola indovinata. Viene marcato, e
    # l'arbitro sono le illustrazioni di schieramento del fascicolo.
    for h in cells.values():
        h["needs_check"] = h["land_frac"] >= 0.20 \
            and abs(h["sea_frac"] - SEA_MIN) < 0.25

    # ---- frecce "non adiacente" ----
    edges = []
    for (ax, ay), where in NOT_ADJACENT[key]:
        approx = inv.dot(np.array([ax, ay]) - origin)
        near = []
        for di in range(-2, 3):
            for dj in range(-2, 3):
                q = int(round(approx[0])) + di - i0
                r = int(round(approx[1])) + dj - j0
                c = origin + (q + i0) * e1 + (r + j0) * e2
                near.append((math.hypot(ax - c[0], ay - c[1]), q, r))
        near.sort()
        (_d1, q1, r1), (_d2, q2, r2) = near[0], near[1]
        if (q2 - q1, r2 - r1) not in DIRS:
            raise SystemExit("%s: la freccia a (%d,%d) cade fra (%d,%d) e "
                             "(%d,%d), che non sono adiacenti"
                             % (key, ax, ay, q1, r1, q2, r2))
        edges.append({
            "aq": q1, "ar": r1, "bq": q2, "br": r2,
            "arrow_px": [ax, ay],
            "where": where,
            # p.4: la freccia nega la Traiettoria, non il Supporto Aereo.
            "blocks": "trajectory",
            "air_support_allowed": True,
        })

    # Una freccia che tocca un esagono NON giocabile e' una contraddizione da
    # guardare, non da correggere di nascosto: il fascicolo stampa la freccia
    # per negare un'adiacenza, e negarla ha senso solo fra esagoni in gioco.
    # Puo' voler dire che la classificazione per colore ha sbagliato, oppure
    # che la freccia e' solo un avviso cartografico. Si segna e si va avanti.
    for e in edges:
        missing = [(q, r) for q, r in ((e["aq"], e["ar"]), (e["bq"], e["br"]))
                   if (q, r) not in playable]
        if missing:
            e["disputed"] = ["%d,%d" % qr for qr in missing]

    ordered = [playable[k] for k in sorted(playable)]
    for h in ordered:
        h.pop("playable", None)

    # Gli esagoni scartati non spariscono in silenzio: quelli che ci sono
    # andati vicino restano scritti, con il motivo.
    dropped = [h for k, h in sorted(cells.items())
               if k not in playable and h["sea_frac"] >= 0.20]
    for h in dropped:
        h.pop("playable", None)
        h.pop("neighbors", None)

    if overlay_dir:
        img = Image.fromarray(rgb.astype(np.uint8)).convert("RGB")
        draw = ImageDraw.Draw(img)
        for k, h in cells.items():
            c = np.array([h["cx"], h["cy"]])
            poly = [(c[0] + circumradius * math.cos(th + n * math.pi / 3.0),
                     c[1] + circumradius * math.sin(th + n * math.pi / 3.0))
                    for n in range(6)]
            live = k in playable
            draw.polygon(poly, outline=(0, 170, 0) if live else (200, 0, 0))
            if live:
                draw.text((c[0] - 22, c[1] - 6), "%d,%d" % (h["q"], h["r"]),
                          fill=(0, 90, 0))
        for e in edges:
            ca = np.array([cells[(e["aq"], e["ar"])]["cx"],
                           cells[(e["aq"], e["ar"])]["cy"]]) \
                if (e["aq"], e["ar"]) in cells \
                else origin + (e["aq"] + i0) * e1 + (e["ar"] + j0) * e2
            cb = np.array([cells[(e["bq"], e["br"])]["cx"],
                           cells[(e["bq"], e["br"])]["cy"]]) \
                if (e["bq"], e["br"]) in cells \
                else origin + (e["bq"] + i0) * e1 + (e["br"] + j0) * e2
            draw.line([tuple(ca), tuple(cb)], fill=(0, 0, 255), width=5)
            mid = (ca + cb) / 2.0
            draw.text((mid[0] - 30, mid[1] - 6), "%d,%d | %d,%d"
                      % (e["aq"], e["ar"], e["bq"], e["br"]), fill=(0, 0, 255))
        for port in ports:
            px, py = port["dot_px"]
            draw.ellipse([px - 9, py - 9, px + 9, py + 9], outline=(255, 0, 255))
            draw.text((px + 11, py - 5), "%s (%d,%d)"
                      % (port["name"], port["q"], port["r"]), fill=(180, 0, 180))
        img.save(os.path.join(overlay_dir, "hexes_%s.png" % key))

    return {
        "name": meta["name"],
        "image": meta["image"],
        "image_size": meta["image_size"],
        "scenarios": meta["scenarios"],
        "frame_px": list(FRAME),
        "origin_hex": ("(0,0) e' la cella il cui centro e' piu' vicino "
                       "all'angolo in alto a sinistra della cornice stampata"),
        "sea_min": SEA_MIN,
        "hex_count": len(ordered),
        "needs_check_count": sum(1 for h in ordered if h["needs_check"]),
        "hexes": ordered,
        "ports": ports,
        "not_adjacent_edges": edges,
        "excluded_near_miss": dropped,
        "still_missing": ("caselle fuori mappa e loro connessioni, basi aeree, "
                          "un secondo MapGraph nel motore e il disegno "
                          "dell'inserto nella GUI"),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--overlay-dir", default=None)
    args = ap.parse_args()
    with open(LATTICE) as f:
        lattice = json.load(f)
    out = {}
    for key, meta in lattice["insets"].items():
        rgb = np.asarray(Image.open(os.path.join(ROOT, meta["image"]))
                         .convert("RGB")).astype(int)
        g = build(key, meta, rgb, args.overlay_dir)
        out[key] = g
        coastal = sum(1 for h in g["hexes"] if h["coastal"])
        print("%-38s %3d esagoni giocabili, %d costieri, %d porti, "
              "%d frecce non adiacente, %d da verificare, %d scartati per un soffio"
              % (g["name"], g["hex_count"], coastal, len(g["ports"]),
                 len(g["not_adjacent_edges"]), g["needs_check_count"],
                 len(g["excluded_near_miss"])))
        for p_ in g["ports"]:
            print("      porto %-14s (%2d,%2d)  pallino %s"
                  % (p_["name"], p_["q"], p_["r"], p_["kind"]))
        for e_ in g["not_adjacent_edges"]:
            print("      non adiacente (%2d,%2d)|(%2d,%2d)  %s%s"
                  % (e_["aq"], e_["ar"], e_["bq"], e_["br"], e_["where"],
                     "" if "disputed" not in e_
                     else "  [DISCUSSO: %s non giocabile]"
                     % " e ".join(e_["disputed"])))
        for h in g["hexes"]:
            if h["needs_check"]:
                print("      DA VERIFICARE (%d,%d): mare %.2f, terra %.2f"
                      % (h["q"], h["r"], h["sea_frac"], h["land_frac"]))
        for h in g["excluded_near_miss"]:
            print("      scartato     (%d,%d): mare %.2f, terra %.2f, "
                  "casella %.2f, fuori %.2f - %s"
                  % (h["q"], h["r"], h["sea_frac"], h["land_frac"],
                     h["box_frac"], h["outside_frac"], h["reason"]))
    doc = {
        "generated_by": "tools/build_inset_graph.py",
        "lattice_from": "core/data/map_insets.json",
        "naming": ("Coordinate assiali (q, r) con le sei direzioni di "
                   "core/data/map_graph.json. (0,0) e' la cella piu' vicina "
                   "all'angolo in alto a sinistra della cornice stampata: e' "
                   "una convenzione interna riproducibile, non una numerazione "
                   "GMT - sugli inserti non ce n'e' nessuna stampata."),
        "insets": out,
    }
    with open(OUT, "w") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("scritto %s" % os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
