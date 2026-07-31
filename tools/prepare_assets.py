#!/usr/bin/env python3
"""
M0 - Pipeline degli asset.

  1. taglia la mappa 4203x2763 in tile da 1024 (46 MB in RGBA sono troppi per
     l'export web come texture unica)
  2. copia le pedine che servono a M1-M3 con nomi normalizzati

Gli originali non vengono mai modificati.
"""
import json
import os
import re
import shutil

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
IMG = os.path.join(SRC, "images")
ASSETS = os.path.join(ROOT, "assets")

TILE = 1024


def tile_map():
    out = os.path.join(ASSETS, "map")
    os.makedirs(out, exist_ok=True)
    im = Image.open(os.path.join(IMG, "Atlantic Chase Map120.jpg")).convert("RGB")
    W, H = im.size
    cols = (W + TILE - 1) // TILE
    rows = (H + TILE - 1) // TILE
    tiles = []
    for ty in range(rows):
        for tx in range(cols):
            x0, y0 = tx * TILE, ty * TILE
            x1, y1 = min(x0 + TILE, W), min(y0 + TILE, H)
            name = f"tile_{tx}_{ty}.jpg"
            im.crop((x0, y0, x1, y1)).save(os.path.join(out, name), quality=92,
                                           subsampling=0)
            tiles.append({"file": name, "x": x0, "y": y0,
                          "w": x1 - x0, "h": y1 - y0})
    manifest = {"source": "Atlantic Chase Map120.jpg", "size": [W, H],
                "tile": TILE, "cols": cols, "rows": rows, "tiles": tiles}
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    total = sum(os.path.getsize(os.path.join(out, t["file"])) for t in tiles)
    print(f"[assets] mappa: {len(tiles)} tile ({cols}x{rows}), {total/1e6:.1f} MB")


def norm(name):
    s = name.replace(".png", "").replace(".jpg", "")
    s = s.replace("&", "and")
    s = re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_").lower()
    return s


def copy_counters():
    out = os.path.join(ASSETS, "counters")
    os.makedirs(out, exist_ok=True)
    keep = ("Ship_", "Leader_", "Markers_", "Station_", "Trajectory_",
            "Reinforcement_", "SNAFU_", "Special Effect_", "Intel_",
            "ULTRA", "B-Dienst", "D6_")
    index = {}
    n = 0
    for f in sorted(os.listdir(IMG)):
        if not f.lower().endswith((".png", ".jpg")):
            continue
        if not f.startswith(keep):
            continue
        dst = norm(f) + os.path.splitext(f)[1].lower()
        shutil.copy2(os.path.join(IMG, f), os.path.join(out, dst))
        index[f] = dst
        n += 1
    json.dump(index, open(os.path.join(out, "index.json"), "w"), indent=1)
    print(f"[assets] pedine: {n} file copiati in assets/counters/")


def copy_boards():
    out = os.path.join(ASSETS, "boards")
    os.makedirs(out, exist_ok=True)
    boards = ["Map_North Sea.jpg", "Map_Norwegian Sea.jpg",
              "TF Display German.jpg", "TF Display British.jpg",
              "Campaign Display British 1.jpg", "Campaign Display British 2.jpg",
              "Campaign Display German 1.jpg", "Campaign Display German 2.jpg"]
    for b in boards:
        p = os.path.join(IMG, b)
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(out, norm(b) + ".jpg"))
    print(f"[assets] tavole: {len(boards)} copiate in assets/boards/")


if __name__ == "__main__":
    tile_map()
    copy_counters()
    copy_boards()
