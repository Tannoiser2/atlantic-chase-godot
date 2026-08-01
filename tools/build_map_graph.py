#!/usr/bin/env python3
"""
M1c (1) - Costruzione del grafo della mappa.

Parte dalla classificazione automatica (playable.json) e la ripulisce con
criteri topologici, che sono molto piu' affidabili dei criteri locali:

  1. terra piena     -> non giocabile  (molta terra E poco mare)
  2. componente principale: l'oceano giocabile e' connesso; le isole di
     esagoni staccate sono artefatti
  3. riempimento buchi: un esagono circondato da esagoni giocabili e' giocabile
  4. gli esagoni usati dai 22 scenari ufficiali sono giocabili per definizione

Poi calcola l'adiacenza e scrive core/data/map_graph.json, che e' il file che
il gioco carica davvero.

Le correzioni residue si fanno nell'editor visuale (tools/map_editor).
"""
import json
import math
import os
from collections import deque

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
MAP = os.path.join(SRC, "images", "Atlantic Chase Map120.jpg")
REP = os.path.join(ROOT, "reports")
DATA = os.path.join(ROOT, "core", "data")
os.makedirs(DATA, exist_ok=True)

# direzioni assiali, nell'ordine che usa anche il codice Godot
DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def main():
    lat = json.load(open(os.path.join(REP, "lattice.json")))
    # esagoni di sola terraferma che devono comunque restare giocabili perche'
    # contengono un porto (vedi core/data/map_annotations.json)
    forced = set()
    ann_path = os.path.join(DATA, "map_annotations.json")
    if os.path.exists(ann_path):
        for h in json.load(open(ann_path)).get("force_playable", {}).get("hexes", []):
            forced.add((h["q"], h["r"]))
    pl = json.load(open(os.path.join(REP, "playable.json")))
    hexes = {(h["q"], h["r"]): h for h in pl["hexes"]}

    # ---- 1. terra piena ----
    for h in hexes.values():
        h["auto"] = h["playable"]
        if (h["q"], h["r"]) in forced:
            h["playable"] = True
            h["reason"] = "forzato: contiene un porto"
            continue
        if h["land"] >= 0.55 and h["sea"] <= 0.25:
            h["playable"] = False
            h["reason"] = "terra piena"

    # ---- 4. gli scenari ufficiali hanno sempre ragione ----
    for h in hexes.values():
        if h["used"]:
            h["playable"] = True
            h["reason"] = "usato dagli scenari ufficiali"

    # ---- 3. riempimento buchi (iterato) ----
    for _ in range(4):
        changed = 0
        for (q, r), h in hexes.items():
            if h["playable"]:
                continue
            if h["zone"] is not None or h["land"] >= 0.55:
                continue
            nb = sum(1 for dq, dr in DIRS
                     if hexes.get((q + dq, r + dr), {}).get("playable"))
            if nb >= 4 and h["sea"] >= 0.35:
                h["playable"] = True
                h["reason"] = "buco riempito"
                changed += 1
        if not changed:
            break

    # ---- 2. componente connessa principale ----
    play = {k for k, h in hexes.items() if h["playable"]}
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
                n = (c[0] + d[0], c[1] + d[1])
                if n in play and n not in seen:
                    seen.add(n)
                    dq.append(n)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    main_comp = comps[0] if comps else set()
    print(f"[graph] componenti: {[len(c) for c in comps]}")
    for c in comps[1:]:
        for k in c:
            hexes[k]["playable"] = False
            hexes[k]["reason"] = "componente isolata"

    play = {k for k, h in hexes.items() if h["playable"]}
    print(f"[graph] esagoni giocabili finali: {len(play)}")

    # ---- adiacenza ----
    nodes = []
    for (q, r) in sorted(play):
        h = hexes[(q, r)]
        nbrs = []
        for i, (dq, dr) in enumerate(DIRS):
            n = (q + dq, r + dr)
            if n in play:
                nbrs.append({"dir": i, "q": n[0], "r": n[1]})
        nodes.append({
            "q": q, "r": r,
            "cx": h["cx"], "cy": h["cy"],
            "land_frac": h["land"],
            "coastal": bool(h["land"] > 0.05),
            "neighbors": nbrs,
        })
    deg = [len(n["neighbors"]) for n in nodes]
    print(f"[graph] grado medio {sum(deg)/len(deg):.2f}, "
          f"min {min(deg)}, max {max(deg)}")

    graph = {
        "generated_by": "tools/build_map_graph.py",
        "map_image": lat["map_image"],
        "map_size": lat["map_size"],
        "lattice": {
            "spacing_px": lat["spacing_px"],
            "theta_deg": lat["theta_deg"],
            "origin_px": lat["origin_px"],
            "circumradius_px": lat["circumradius_px"],
            "inradius_px": lat["inradius_px"],
            "basis_e1": lat["basis_e1"],
            "basis_e2": lat["basis_e2"],
        },
        "directions": [{"dir": i, "dq": d[0], "dr": d[1]} for i, d in enumerate(DIRS)],
        "hex_count": len(nodes),
        "hexes": nodes,
        # da completare nell'editor: lati negati dalle frecce "not adjacent"
        "blocked_edges": [],
        # da completare nell'editor: box porto -> esagono di sbocco
        "ports": [],
        "notes": [
            "blocked_edges e ports sono vuoti: vanno completati con tools/map_editor",
            "le frecce 'not adjacent' sulla mappa negano l'adiacenza attraverso la terra",
        ],
    }
    with open(os.path.join(DATA, "map_graph.json"), "w") as f:
        json.dump(graph, f, indent=1)
    print(f"[graph] scritto core/data/map_graph.json")

    # overlay finale
    im = Image.open(MAP).convert("RGB")
    W, H = im.size
    R = lat["circumradius_px"]
    th = lat["theta_deg"]
    d = ImageDraw.Draw(im, "RGBA")
    for (q, r) in play:
        h = hexes[(q, r)]
        cs = [(h["cx"] + R * math.cos(math.radians(th + 30 + 60 * k)),
               h["cy"] + R * math.sin(math.radians(th + 30 + 60 * k))) for k in range(6)]
        c = (255, 200, 0, 80) if h["land"] > 0.35 else (0, 220, 255, 55)
        d.polygon(cs, fill=c, outline=(255, 255, 255, 160))
    im.resize((W // 3, H // 3), Image.LANCZOS).save(os.path.join(REP, "graph_overlay.png"))
    print("[graph] scritto reports/graph_overlay.png")


if __name__ == "__main__":
    main()
