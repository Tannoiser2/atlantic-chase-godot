#!/usr/bin/env python3
"""
Validazione del grafo degli inserti contro le illustrazioni del fascicolo.

    tools/.venv/bin/python tools/validate_inset_setups.py
    tools/.venv/bin/python tools/validate_inset_setups.py --overlay-dir reports

Per la mappa grande la verita' indipendente erano le 238 pedine ufficiali del
modulo VASSAL. Per gli inserti non esiste nessun `.vsav`, e per un po' e'
sembrato che verita' indipendente non ce ne fosse. C'e': le illustrazioni di
schieramento dei cinque scenari inserto disegnano i segmenti di Traiettoria
iniziali SULLA mappa, e nel PDF quei segmenti non sono pixel, sono grafica
vettoriale con coordinate esatte.

Il resto e' registrazione. L'illustrazione riusa la stessa immagine dell'inserto
(1200x1553, identico rapporto a 1020x1320), quindi la sua collocazione sulla
pagina da' la trasformazione da coordinate di pagina a coordinate di mappa; da
li' il reticolo di `core/data/map_insets.json` da' l'esagono.

Un segmento che cade in un esagono che il grafo dichiara non giocabile e' un
difetto del grafo, non dell'illustrazione: GMT non disegna una Traiettoria in
un esagono che non esiste. E' il controllo che questo programma fa, ed e'
l'unica cosa che afferma.

Di proposito NON si prova a separare i segmenti veri dalle pedine disegnate
dentro i riquadri di regola incollati sopra la mappa. Provarci significava
mascherare per rettangolo, e il rettangolo di un riquadro copre anche segmenti
veri che gli passano accanto: si perdevano tre controlli su quarantasei per
guadagnare un conteggio piu' bello. Il conteggio non serve a niente, il
controllo si'. Le forme dentro un riquadro sono marcate `inside_callout` e
vengono controllate come le altre.

I segmenti si riconoscono dalla FORMA, non dal colore: ogni scenario usa il
colore della sua Task Force - marroni in N1, oro in BL3, bianchi in N2 e N3 -
ma il pezzo e' sempre lo stesso, una barretta la cui diagonale sta fra 95 e 140
px di mappa. Faccia superiore e ombra sono due tracciati sovrapposti, quindi si
raggruppa per posizione.
"""
import argparse
import json
import math
import os

import fitz
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PDF = os.path.join(ROOT, "docs", "regolamento", "AC_Solo_scenarios_2022.pdf")
GRAPHS = os.path.join(ROOT, "core", "data", "inset_graphs.json")
LATTICE = os.path.join(ROOT, "core", "data", "map_insets.json")
OUT = os.path.join(ROOT, "core", "data", "inset_setups.json")

# Pagina del fascicolo, xref dell'immagine di mappa, inserto, id di scenario.
# Le pagine sono quelle indicizzate da zero, che qui coincidono con quelle
# stampate.
PAGES = [
    (12, 2823, "map_north_sea", "BL3 Raiders of the North Sea"),
    (17, 2828, "map_norwegian_sea", "N1 Operazione Wilfred"),
    (21, 2828, "map_norwegian_sea", "N2 Operazione Weser (nord)"),
    (25, 2823, "map_north_sea", "N3 Operazione Weser (sud)"),
    (32, 2828, "map_norwegian_sea", "N5 Meglio Tardi che Mai"),
]

MAP_W, MAP_H = 1020, 1320

# Su quali pagine la banda dei segmenti e' BIANCA, cioe' rilevabile col metodo
# di sotto. Altrove i segmenti sono chiari e la banda e' scura: il flag
# `convoy_stripe` non va usato.
WHITE_STRIPE_PAGES = {12, 17}
SEG_DIAG = (95.0, 140.0)
SEG_MIN_SIDE = 15.0
SEG_MAX_SIDE = 130.0
CLUSTER_PX = 30.0

# Il verde pallido dei riquadri di regola stampati sopra la mappa.
CALLOUT_FILL = (0.7748, 0.8614, 0.8414)
# Area minima, in px di mappa, perche' un'immagine incollata sopra la mappa
# conti come pannello da escludere (il riquadro di Scapa Flow, i gruppi di
# pedine). Sotto, e' un segnalino che fa parte dello schieramento.
PANEL_MIN_AREA = 20000.0



def segments_on_page(doc, page_no, base_xref):
    """I segmenti di Traiettoria disegnati sopra la mappa, in coordinate di mappa."""
    page = doc[page_no]
    rects = page.get_image_rects(base_xref)
    if not rects:
        raise SystemExit("pagina %d: immagine di mappa %d non trovata"
                         % (page_no, base_xref))
    box = rects[0]
    # L'immagine e' piazzata senza deformarla: se il rapporto non torna, la
    # registrazione sarebbe sbagliata e tutto il resto con lei.
    ratio = (box.width / box.height) / (float(MAP_W) / MAP_H)
    if abs(ratio - 1.0) > 0.01:
        raise SystemExit("pagina %d: l'immagine e' deformata (rapporto %.3f)"
                         % (page_no, ratio))
    scale = MAP_W / box.width

    # I riquadri di regola e i pannelli incollati sopra la mappa contengono
    # pedine disegnate che hanno la stessa taglia di un segmento. Quelle non
    # sono schieramento: sono figure. Si escludono le zone che coprono.
    masks = []
    for drawing in page.get_drawings():
        fill = drawing.get("fill")
        if not fill:
            continue
        if all(abs(a - b) < 0.02 for a, b in zip(fill, CALLOUT_FILL)):
            masks.append(drawing["rect"])
    for xref in {img[0] for img in page.get_images(full=True)}:
        if xref == base_xref:
            continue
        for r in page.get_image_rects(xref):
            c = ((r.x0 + r.x1) / 2.0, (r.y0 + r.y1) / 2.0)
            if not (box.x0 <= c[0] <= box.x1 and box.y0 <= c[1] <= box.y1):
                continue
            if r.width * scale * r.height * scale > PANEL_MIN_AREA:
                masks.append(r)

    # La banda in mezzo a un segmento distingue due Task Force diverse sulla
    # stessa illustrazione. Qui si cerca una banda BIANCA, che e' quella dei
    # segmenti marroni di BL3 e N1.
    #
    # ATTENZIONE, verificato e sbagliato una volta: NON vale su N2 e N3, dove i
    # segmenti sono bianchi e la banda e' BLU. Li' questa ricerca trova le due
    # meta' chiare del segmento invece della banda, e il flag esce invertito -
    # il segmento a Namsos (6,0) di N2 ha la banda e risultava liscio. Il flag
    # e' quindi attendibile solo dove `stripe_reliable` e' vero, e altrove va
    # letto a occhio sull'illustrazione.
    stripes = []
    for drawing in page.get_drawings():
        fill = drawing.get("fill")
        if not fill or tuple(round(v, 2) for v in fill) != (1.0, 1.0, 1.0):
            continue
        r = drawing["rect"]
        w, h = r.width * scale, r.height * scale
        if not (4.0 <= min(w, h) <= 26.0 and 8.0 <= max(w, h) <= 60.0):
            continue
        stripes.append(((r.x0 + r.x1) / 2.0, (r.y0 + r.y1) / 2.0))

    raw = []
    for drawing in page.get_drawings():
        if not drawing.get("fill"):
            continue
        r = drawing["rect"]
        cx, cy = (r.x0 + r.x1) / 2.0, (r.y0 + r.y1) / 2.0
        if not (box.x0 - 3 <= cx <= box.x1 + 3 and box.y0 - 3 <= cy <= box.y1 + 3):
            continue
        w, h = r.width * scale, r.height * scale
        if not (SEG_DIAG[0] <= math.hypot(w, h) <= SEG_DIAG[1]):
            continue
        if min(w, h) < SEG_MIN_SIDE or max(w, h) > SEG_MAX_SIDE:
            continue
        covered = any(m.x0 <= cx <= m.x1 and m.y0 <= cy <= m.y1 for m in masks)
        striped = any(math.hypot(sx - cx, sy - cy) * scale <= 34.0
                      for sx, sy in stripes)
        raw.append(((cx - box.x0) * scale, (cy - box.y0) * scale, covered, striped))
    # Faccia superiore e ombra sono due tracciati quasi sovrapposti: uno solo.
    clusters = []
    for px, py, covered, striped in sorted(raw):
        for c in clusters:
            if math.hypot(px - c[0][0], py - c[0][1]) <= CLUSTER_PX:
                c.append((px, py, covered, striped))
                break
        else:
            clusters.append([(px, py, covered, striped)])
    return [(sum(p[0] for p in c) / len(c), sum(p[1] for p in c) / len(c),
             all(p[2] for p in c), any(p[3] for p in c)) for c in clusters]


def hex_of(lattice, origin_hex, px, py):
    e1 = np.array(lattice["basis_e1"])
    e2 = np.array(lattice["basis_e2"])
    org = np.array(lattice["origin_px"])
    inv = np.linalg.inv(np.array([[e1[0], e2[0]], [e1[1], e2[1]]]))
    i0, j0 = origin_hex
    approx = inv.dot(np.array([px, py]) - org)
    best = None
    for di in (-1, 0, 1):
        for dj in (-1, 0, 1):
            i = int(round(approx[0])) + di
            j = int(round(approx[1])) + dj
            c = org + i * e1 + j * e2
            d = math.hypot(px - c[0], py - c[1])
            if best is None or d < best[0]:
                best = (d, i - i0, j - j0)
    return best[1], best[2], best[0]


def origin_hex_of(lattice, frame):
    e1 = np.array(lattice["basis_e1"])
    e2 = np.array(lattice["basis_e2"])
    org = np.array(lattice["origin_px"])
    inv = np.linalg.inv(np.array([[e1[0], e2[0]], [e1[1], e2[1]]]))
    ij = inv.dot(np.array([frame[0], frame[1]]) - org)
    return int(round(ij[0])), int(round(ij[1]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--overlay-dir", default=None)
    args = ap.parse_args()

    graphs = json.load(open(GRAPHS))["insets"]
    lattices = json.load(open(LATTICE))["insets"]
    doc = fitz.open(PDF)

    out = {}
    bad = 0
    for page_no, base_xref, key, scenario in PAGES:
        g = graphs[key]
        lattice = lattices[key]["lattice"]
        i0j0 = origin_hex_of(lattice, g["frame_px"])
        live = {(h["q"], h["r"]) for h in g["hexes"]}
        segs = segments_on_page(doc, page_no, base_xref)
        placed, outside = [], []
        for px, py, covered, striped in segs:
            q, r, dist = hex_of(lattice, i0j0, px, py)
            entry = {"q": q, "r": r, "map_px": [round(px, 1), round(py, 1)],
                     "inside_callout": covered,
                     "band": striped if page_no in WHITE_STRIPE_PAGES else None,
                     "band_reliable": page_no in WHITE_STRIPE_PAGES}
            if (q, r) in live:
                placed.append(entry)
            else:
                entry["problem"] = "l'esagono non e' nel grafo"
                outside.append(entry)
        in_callout = sum(1 for e in placed + outside if e["inside_callout"])
        reliable = page_no in WHITE_STRIPE_PAGES
        striped_n = sum(1 for e in placed + outside if e["band"])
        print("%-34s p%-3d  %2d candidati (%d dentro un riquadro%s), "
              "%2d in esagoni del grafo, %2d fuori"
              % (scenario, page_no, len(segs), in_callout,
                 ", %d con la banda" % striped_n if reliable
                 else ", banda non rilevabile: segmenti chiari",
                 len(placed), len(outside)))
        for e in outside:
            print("      FUORI: segmento a (%s) -> (%d,%d)"
                  % (", ".join(str(v) for v in e["map_px"]), e["q"], e["r"]))
            bad += 1
        counts = {}
        for e in placed:
            counts[(e["q"], e["r"])] = counts.get((e["q"], e["r"]), 0) + 1
        out[scenario] = {
            "inset": key,
            "source": "AC_Solo_scenarios_2022 p.%d, illustrazione di schieramento" % page_no,
            "candidate_count": len(segs),
            "candidates": placed + outside,
            "hexes_used": [{"q": q, "r": r, "segments": n}
                           for (q, r), n in sorted(counts.items())],
        }
        if args.overlay_dir:
            _overlay(args.overlay_dir, key, scenario, lattice, g, segs, live, i0j0)

    # Cosa questa verifica CHIUDE. Un esagono in cui il fascicolo disegna un
    # segmento di Traiettoria e' giocabile, punto: e' un dato stampato, e batte
    # una soglia di colore. Qui si guarda quali degli esagoni che il grafo
    # aveva marcato incerti - `needs_check`, o citati da un lato "non
    # adiacente" `disputed` - siano confermati cosi'.
    per_inset = {}
    for scenario, rec in out.items():
        per_inset.setdefault(rec["inset"], set()).update(
            (e["q"], e["r"]) for e in rec["candidates"] if "problem" not in e)
    settled = {}
    for key, hexes in sorted(per_inset.items()):
        g = graphs[key]
        uncertain = {(h["q"], h["r"]) for h in g["hexes"] if h.get("needs_check")}
        disputed = set()
        for e in g["not_adjacent_edges"]:
            for tag in e.get("disputed", []):
                q, r = tag.split(",")
                disputed.add((int(q), int(r)))
        settled[key] = {
            "hexes_with_a_printed_segment": ["%d,%d" % qr for qr in sorted(hexes)],
            "needs_check_confirmed": ["%d,%d" % qr for qr in sorted(uncertain & hexes)],
            "needs_check_still_open": ["%d,%d" % qr for qr in sorted(uncertain - hexes)],
            "disputed_confirmed": ["%d,%d" % qr for qr in sorted(disputed & hexes)],
            "disputed_still_open": ["%d,%d" % qr for qr in sorted(disputed - hexes)],
        }
        print("%-38s esagoni con un segmento stampato: %d" % (g["name"], len(hexes)))
        for label, field in (("da verificare, ora CONFERMATI", "needs_check_confirmed"),
                             ("da verificare, ancora aperti", "needs_check_still_open"),
                             ("discussi, ora CONFERMATI", "disputed_confirmed"),
                             ("discussi, ancora aperti", "disputed_still_open")):
            v = settled[key][field]
            if v:
                print("      %-30s %s" % (label, ", ".join(v)))

    doc_out = {
        "generated_by": "tools/validate_inset_setups.py",
        "what": ("Segmenti di Traiettoria iniziali letti dalle illustrazioni di "
                 "schieramento del fascicolo e riportati sul reticolo degli "
                 "inserti. Servono da verita' indipendente per il grafo: un "
                 "segmento in un esagono che il grafo non ha e' un difetto del "
                 "grafo."),
        "caveat": ("Il conteggio e' un LIMITE SUPERIORE, non lo schieramento. "
                   "Ogni forma delle dimensioni di un segmento disegnata sopra "
                   "la mappa entra nell'elenco, comprese le pedine dei riquadri "
                   "di regola incollati sopra: quelle sono marcate "
                   "inside_callout. E' voluto - la domanda a cui questo "
                   "programma risponde e' 'qualche segmento cade fuori dal "
                   "grafo?', e per rispondere bisogna controllarli tutti, non "
                   "sceglierne un sottoinsieme. Quali segmenti siano di quale "
                   "Task Force, e in che ordine formino la Traiettoria, questo "
                   "non lo dice: per quello serve leggere la pagina."),
        "scenarios": out,
        "settles": settled,
    }
    with open(OUT, "w") as f:
        json.dump(doc_out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("scritto %s" % os.path.relpath(OUT, ROOT))
    print("VERIFICA: %s" % ("OK, ogni forma da segmento cade in un esagono del grafo"
                            if bad == 0 else "%d forme fuori dal grafo" % bad))
    raise SystemExit(1 if bad else 0)


def _overlay(dest, key, scenario, lattice, g, segs, live, i0j0):
    from PIL import Image, ImageDraw
    circumradius = lattice["circumradius_px"]
    th = math.radians(lattice["theta_deg"])
    img = Image.open(os.path.join(ROOT, g["image"])).convert("RGB")
    draw = ImageDraw.Draw(img)
    for h in g["hexes"]:
        c = (h["cx"], h["cy"])
        draw.polygon([(c[0] + circumradius * math.cos(th + n * math.pi / 3.0),
                       c[1] + circumradius * math.sin(th + n * math.pi / 3.0))
                      for n in range(6)], outline=(0, 160, 0))
        draw.text((c[0] - 16, c[1] - 6), "%d,%d" % (h["q"], h["r"]), fill=(0, 110, 0))
    for px, py, covered, _striped in segs:
        q, r, _d = hex_of(lattice, i0j0, px, py)
        col = (255, 0, 0) if (q, r) not in live else ((150, 150, 150) if covered
                                                      else (0, 0, 255))
        draw.ellipse([px - 12, py - 12, px + 12, py + 12], fill=col)
    safe = scenario.split()[0]
    img.save(os.path.join(dest, "setup_%s.png" % safe))


if __name__ == "__main__":
    main()
