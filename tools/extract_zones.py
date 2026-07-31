#!/usr/bin/env python3
"""
M1b (2) - Estrae le Zone poligonali dal buildFile.xml di VASSAL.

Il modulo definisce gia' i poligoni esatti di: box porto, tracce (VP, meteo,
round), caselle Operazione della campagna, zone della mappa di Battaglia
(Far/Near/Close), slot dei Task Force Display e dei rinforzi.

Li estraiamo associandoli alla mappa e alla board di appartenenza, cosi' non
vanno ridisegnati a mano.

Output: reports/zones.json
"""
import json
import os
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
BUILD = os.path.join(SRC, "buildFile.xml")
OUT = os.path.join(ROOT, "reports")
os.makedirs(OUT, exist_ok=True)

MAP_TAG = "VASSAL.build.module.Map"
BOARD_TAG = "VASSAL.build.module.map.boardPicker.Board"
ZONE_TAG = "VASSAL.build.module.map.boardPicker.board.mapgrid.Zone"


def parse_path(p):
    pts = []
    for chunk in p.split(";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        x, y = chunk.split(",")
        pts.append([int(float(x)), int(float(y))])
    return pts


def main():
    tree = ET.parse(BUILD)
    root = tree.getroot()
    out = []
    for mp in root.iter(MAP_TAG):
        map_name = mp.get("mapName", "?")
        for board in mp.iter(BOARD_TAG):
            board_name = board.get("name", "?")
            board_img = board.get("image", "")
            for z in board.iter(ZONE_TAG):
                path = z.get("path", "")
                if not path:
                    continue
                pts = parse_path(path)
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                out.append({
                    "map": map_name,
                    "board": board_name,
                    "board_image": board_img,
                    "name": z.get("name", ""),
                    "polygon": pts,
                    "bbox": [min(xs), min(ys), max(xs), max(ys)],
                    "centroid": [round(sum(xs) / len(xs), 1), round(sum(ys) / len(ys), 1)],
                })

    with open(os.path.join(OUT, "zones.json"), "w") as f:
        json.dump(out, f, indent=2)

    by_map = {}
    for z in out:
        by_map.setdefault(z["map"], []).append(z["name"])
    print(f"{len(out)} zone estratte\n")
    for m, names in by_map.items():
        named = [n for n in names if n]
        print(f"  {m}  ({len(names)} zone, {len(named)} con nome)")
        print(f"      {', '.join(named[:28])}{' ...' if len(named) > 28 else ''}")
    print("\nScritto reports/zones.json")


if __name__ == "__main__":
    main()
