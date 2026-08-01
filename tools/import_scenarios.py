#!/usr/bin/env python3
"""
Conversione dei salvataggi VASSAL in scenari del gioco.

I .vsav contengono le pedine Traiettoria e Stazione con coordinate in pixel, ma
NON dicono in che ordine stanno i segmenti di una Traiettoria: in VASSAL sono
solo pedine sciolte. L'ordine va ricostruito.

Ricostruzione: i segmenti di una stessa TF formano per regola una catena
lineare (RB p.15: "una singola linea con due capi, niente buchi ne'
biforcazioni"). Quindi basta costruire il grafo di adiacenza fra i segmenti
della TF, trovare i due capi (grado 1) e percorrerlo. Se la forma non e' una
catena valida lo segnaliamo invece di indovinare.

Output: core/data/scenarios/<nome>.json
"""
import csv
import json
import math
import os
import re
from collections import defaultdict

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REP = os.path.join(ROOT, "reports")
OUT = os.path.join(ROOT, "core", "data", "scenarios")
os.makedirs(OUT, exist_ok=True)

DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

TRAJ_RE = re.compile(r"^Trajectory_([A-Za-z]+)-(\d+)\.png$")
STAT_RE = re.compile(r"^Station_([A-Za-z]+)-(\d+)\.png$")
SHIP_RE = re.compile(r"^Ship_", re.I)
LEADER_RE = re.compile(r"^Leader_[A-Z]{2}-(.+?)b?\.png$")

# Le caselle dei Task Force Display hanno gli stessi nomi di colore e indice
# delle pedine Traiettoria/Stazione, quindi il collegamento e' diretto.
TF_ZONE_RE = re.compile(r"^(?:KM )?TF(?:-(\d+))?$|^TF (Brown|Tan|Red)(?:-(\d+))?$")


def zone_to_color_slot(zone_name):
    """'KM TF-2' -> ('GE', 2);  'TF Tan-1' -> ('Tan', 1);  'TF Red' -> ('Red', 0)"""
    n = zone_name.strip()
    if n.startswith("KM TF"):
        rest = n[len("KM TF"):]
        return "GE", int(rest[1:]) if rest.startswith("-") else 0
    if n.startswith("TF "):
        rest = n[3:]
        if "-" in rest:
            color, idx = rest.split("-", 1)
            return color, int(idx)
        return rest, 0
    return None, None


def point_in_poly(x, y, poly):
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            if x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                inside = not inside
    return inside


def load_display_zones():
    zones = json.load(open(os.path.join(REP, "zones.json")))
    return [z for z in zones if "Task Force Display" in z["map"]]


def load_ship_index():
    """immagine originale della pedina -> nome della nave nel ruolino."""
    idx_path = os.path.join(ROOT, "assets", "counters", "index.json")
    ships_path = os.path.join(ROOT, "core", "data", "ships.json")
    if not (os.path.exists(idx_path) and os.path.exists(ships_path)):
        return {}
    index = json.load(open(idx_path))          # "Ship_GE_BB-Bismarck.png" -> "ship_ge_bb_bismarck.png"
    by_file = {}
    for s in json.load(open(ships_path))["ships"]:
        for f in s["files"]:
            by_file[f] = s["name"]
    out = {}
    for orig, norm in index.items():
        if norm in by_file:
            out[orig] = by_file[norm]
    return out

SIDE_OF_COLOR = {"GE": 0, "Brown": 1, "Tan": 1, "Red": 1}


def load_lattice():
    lat = json.load(open(os.path.join(ROOT, "core", "data", "map_graph.json")))
    l = lat["lattice"]
    e1 = np.array(l["basis_e1"])
    e2 = np.array(l["basis_e2"])
    o = np.array(l["origin_px"])
    M = np.array([e1, e2]).T
    playable = {(h["q"], h["r"]) for h in lat["hexes"]}
    blocked = set()
    for b in lat.get("blocked_edges", []):
        a, c = (b["aq"], b["ar"]), (b["bq"], b["br"])
        blocked.add((a, c))
        blocked.add((c, a))
    return o, e1, e2, np.linalg.inv(M), playable, blocked


def snap(x, y, o, e1, e2, Minv):
    qr = (np.array([x, y], dtype=float) - o) @ Minv.T
    best, bestd = None, 1e18
    for dq in (math.floor(qr[0]), math.ceil(qr[0])):
        for dr in (math.floor(qr[1]), math.ceil(qr[1])):
            c = o + dq * e1 + dr * e2
            d = math.hypot(c[0] - x, c[1] - y)
            if d < bestd:
                best, bestd = (int(dq), int(dr)), d
    return best, bestd


def order_chain(hexes):
    """
    Riordina un insieme di esagoni in una catena. Ritorna (catena, problema).

    Non basta cercare i nodi di grado 1: tre esagoni consecutivi in curva sono
    mutuamente adiacenti (formano un triangolo), quindi una Traiettoria
    perfettamente legale produce nodi di grado 3 e sembrerebbe biforcata.

    Cerchiamo quindi un cammino hamiltoniano sul grafo di adiacenza. Fra i
    cammini possibili teniamo il piu' "diritto": e' il criterio che riproduce
    come un giocatore traccia davvero una rotta, e in pratica il risultato e'
    unico.
    """
    s = list(dict.fromkeys(hexes))
    if len(s) != len(hexes):
        return hexes, "segmenti duplicati"
    if len(s) <= 2:
        return s, None

    sset = set(s)
    adj = {h: [n for n in ((h[0] + d[0], h[1] + d[1]) for d in DIRS) if n in sset]
           for h in s}
    if any(not v for v in adj.values()):
        return s, "segmento isolato (catena spezzata)"

    n = len(s)
    best = [None, -1.0]

    def straightness(path):
        """Somma dei coseni fra passi consecutivi: piu' alto = piu' diritto."""
        if len(path) < 3:
            return 0.0
        tot = 0.0
        for i in range(len(path) - 2):
            a = np.array(path[i + 1]) - np.array(path[i])
            b = np.array(path[i + 2]) - np.array(path[i + 1])
            na, nb = np.linalg.norm(a), np.linalg.norm(b)
            if na and nb:
                tot += float(np.dot(a, b) / (na * nb))
        return tot

    def dfs(path, used):
        if len(path) == n:
            sc = straightness(path)
            if sc > best[1]:
                best[0], best[1] = list(path), sc
            return
        for nxt in adj[path[-1]]:
            if nxt in used:
                continue
            used.add(nxt)
            path.append(nxt)
            dfs(path, used)
            path.pop()
            used.remove(nxt)

    for start in s:
        dfs([start], {start})

    if best[0] is None:
        return s, "nessuna catena lineare copre tutti i segmenti"
    return best[0], None


def main():
    o, e1, e2, Minv, playable, blocked = load_lattice()
    display_zones = load_display_zones()
    ship_names = load_ship_index()
    files = sorted(f for f in os.listdir(os.path.join(REP, "vsav")) if f.endswith(".csv"))
    summary = []

    for fn in files:
        stem = os.path.splitext(fn)[0]
        segs = defaultdict(list)      # (color, slot) -> [hex]
        stations = {}                 # (color, slot) -> hex
        tf_ships = defaultdict(list)  # (color, slot) -> [nome nave]
        tf_leaders = {}               # (color, slot) -> comandante
        reinforcements = defaultdict(list)
        unknown_ships = []
        off_map = 0
        with open(os.path.join(REP, "vsav", fn)) as fh:
            for row in csv.DictReader(fh):
                if row["map"] != "Main Map" or row["kind"] != "piece":
                    continue
                img = row["image"]
                mt = TRAJ_RE.match(img)
                ms = STAT_RE.match(img)
                if not (mt or ms):
                    continue
                h, dist = snap(int(row["x"]), int(row["y"]), o, e1, e2, Minv)
                if h not in playable:
                    off_map += 1
                if mt:
                    segs[(mt.group(1), int(mt.group(2)))].append(h)
                else:
                    stations[(ms.group(1), int(ms.group(2)))] = h

        # --- navi e comandanti sui Task Force Display ---
        with open(os.path.join(REP, "vsav", fn)) as fh:
            for row in csv.DictReader(fh):
                if "Task Force Display" not in row["map"] or row["kind"] != "piece":
                    continue
                x, y = int(row["x"]), int(row["y"])
                zname = None
                for z in display_zones:
                    if z["map"] != row["map"]:
                        continue
                    b = z["bbox"]
                    if b[0] <= x <= b[2] and b[1] <= y <= b[3] \
                            and point_in_poly(x, y, z["polygon"]):
                        zname = z["name"]
                        break
                if zname is None:
                    continue
                img = row["image"]
                if "Reinforcement" in zname:
                    if SHIP_RE.match(img):
                        reinforcements[zname].append(
                            ship_names.get(img, img.replace(".png", "")))
                    continue
                color, slot = zone_to_color_slot(zname)
                if color is None:
                    continue
                if SHIP_RE.match(img):
                    nm = ship_names.get(img)
                    if nm is None:
                        unknown_ships.append(img)
                    else:
                        tf_ships[(color, slot)].append(nm)
                elif img.startswith("Leader_"):
                    m = LEADER_RE.match(img)
                    if m:
                        tf_leaders[(color, slot)] = m.group(1)

        tfs, problems = [], []
        keys = sorted(set(list(segs.keys()) + list(stations.keys())
                          + list(tf_ships.keys())))
        for i, (color, slot) in enumerate(keys):
            chain, problem = order_chain(segs.get((color, slot), []))
            if problem:
                problems.append(f"{color}-{slot}: {problem}")
            # Le pedine del modulo sono piazzate a mano su una mappa senza
            # griglia, quindi capita che una rotta ricostruita attraversi un
            # lato negato dalle frecce "not adjacent". Va segnalato, non
            # accettato in silenzio: la freccia e' stampata sulla mappa e
            # verificata, il piazzamento della pedina no.
            for i in range(len(chain) - 1):
                if (chain[i], chain[i + 1]) in blocked:
                    problems.append(
                        f"{color}-{slot}: la rotta attraversa il lato negato "
                        f"{chain[i]}-{chain[i+1]} (piazzamento impreciso nel .vsav)")
            tf = {
                "id": i + 1,
                "side": SIDE_OF_COLOR.get(color, 1),
                "color": color,
                "slot": slot,
                "name": f"{'KM' if color == 'GE' else 'RN'} {color}-{slot}",
                "ships": sorted(tf_ships.get((color, slot), [])),
                "leader": tf_leaders.get((color, slot), ""),
                "speed": 2,
                "trajectory": {
                    "segments": [{"q": h[0], "r": h[1], "info": False,
                                  "contact": False} for h in chain],
                    "station_q": stations.get((color, slot), chain[0] if chain
                                              else (0, 0))[0],
                    "station_r": stations.get((color, slot), chain[0] if chain
                                              else (0, 0))[1],
                    "station_contact": False,
                    "station_port": "",
                },
            }
            tfs.append(tf)

        if unknown_ships:
            problems.append("pedine nave non riconosciute: %s"
                            % ", ".join(sorted(set(unknown_ships))))

        doc = {
            "name": stem,
            "reinforcements": {k: sorted(v) for k, v in reinforcements.items()},
            "source": f"{stem}.vsav (modulo VASSAL Atlantic Chase v2.1)",
            "weather": 0,
            "initiative": 0,
            "round": 1,
            "task_forces": tfs,
            "info_triggers": [],
            "import_warnings": problems,
        }
        json.dump(doc, open(os.path.join(OUT, stem + ".json"), "w"), indent=1)
        n_seg = sum(len(v) for v in segs.values())
        n_ships = sum(len(v) for v in tf_ships.values())
        summary.append({"scenario": stem, "task_forces": len(tfs),
                        "segments": n_seg, "ships": n_ships, "off_map": off_map,
                        "warnings": problems})
        flag = "" if not problems else f"  ATTENZIONE: {'; '.join(problems)}"
        print(f"  {stem:36s} {len(tfs):2d} TF, {n_seg:3d} segmenti, "
              f"{n_ships:3d} navi{flag}")

    json.dump(summary, open(os.path.join(REP, "scenario_import.json"), "w"), indent=1)
    ok = sum(1 for s in summary if not s["warnings"])
    print(f"\n{len(summary)} scenari, {ok} senza avvisi -> core/data/scenarios/")


if __name__ == "__main__":
    main()
