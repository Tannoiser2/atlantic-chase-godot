#!/usr/bin/env python3
"""
Applica core/data/map_annotations.json a core/data/map_graph.json.

Il grafo e' rigenerabile (build_map_graph.py + refine_playable.py); le
annotazioni no, perche' sono state lette a occhio dalla mappa stampata. Questo
script le riapplica dopo ogni rigenerazione, verificando che si riferiscano
ancora a esagoni esistenti e realmente adiacenti.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "core", "data")
GRAPH = os.path.join(DATA, "map_graph.json")
ANN = os.path.join(DATA, "map_annotations.json")

DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]


def main():
    g = json.load(open(GRAPH))
    a = json.load(open(ANN))
    play = {(h["q"], h["r"]) for h in g["hexes"]}
    problems = []

    def check(aq, ar, bq, br, what):
        A, B = (aq, ar), (bq, br)
        if A not in play:
            problems.append("%s: esagono %s non e' nell'area di gioco" % (what, A))
            return False
        if B not in play:
            problems.append("%s: esagono %s non e' nell'area di gioco" % (what, B))
            return False
        if (bq - aq, br - ar) not in DIRS:
            problems.append("%s: %s e %s non sono geometricamente adiacenti"
                            % (what, A, B))
            return False
        return True

    blocked = []
    for e in a["blocked_edges"]["edges"]:
        if check(e["aq"], e["ar"], e["bq"], e["br"], "lato negato " + e.get("where", "")):
            blocked.append({"aq": e["aq"], "ar": e["ar"], "bq": e["bq"], "br": e["br"],
                            "where": e.get("where", "")})
    g["blocked_edges"] = blocked

    restricted = []
    for e in a.get("restricted_edges", {}).get("edges", []):
        if check(e["aq"], e["ar"], e["bq"], e["br"], "lato ristretto " + e.get("label", "")):
            restricted.append(e)
    g["restricted_edges"] = restricted

    zones = None
    zpath = os.path.join(ROOT, "reports", "zones.json")
    if os.path.exists(zpath):
        zones = {z["name"] for z in json.load(open(zpath)) if z["map"] == "Main Map"}

    ports = []
    for p in a.get("ports", {}).get("entries", []):
        key = (p["q"], p["r"])
        if key not in play:
            problems.append("porto %s: esagono %s non e' nell'area di gioco"
                            % (p["name"], key))
            continue
        if zones is not None and p.get("box") and p["box"] not in zones:
            problems.append("porto %s: la Casella '%s' non esiste fra le Zone del modulo"
                            % (p["name"], p["box"]))
        # una striscia porto rende porto OGNI esagono che tocca (legenda della mappa)
        bad_extra = False
        for e in p.get("extra_hexes", []):
            if (e["q"], e["r"]) not in play:
                problems.append("porto %s: l'esagono aggiuntivo %s non e' nell'area di gioco"
                                % (p["name"], (e["q"], e["r"])))
                bad_extra = True
        if not bad_extra:
            ports.append(p)
    g["ports"] = ports

    json.dump(g, open(GRAPH, "w"), indent=1)

    print("[annot] lati negati applicati: %d" % len(blocked))
    for e in blocked:
        print("    (%d,%d) <-> (%d,%d)   %s"
              % (e["aq"], e["ar"], e["bq"], e["br"], e["where"]))
    print("[annot] lati ristretti: %d" % len(restricted))
    for e in restricted:
        print("    (%d,%d) <-> (%d,%d)   %s [%s]"
              % (e["aq"], e["ar"], e["bq"], e["br"], e["label"], e["side"]))
    print("[annot] porti collegati: %d" % len(g["ports"]))

    if problems:
        print("\n[annot] PROBLEMI (%d):" % len(problems))
        for p in problems:
            print("    " + p)
        return 1
    print("\n[annot] tutte le annotazioni sono coerenti col grafo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
