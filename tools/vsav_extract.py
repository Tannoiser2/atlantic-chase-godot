#!/usr/bin/env python3
"""
M1b (1) - Decodifica dei salvataggi VASSAL (.vsav) di Atlantic Chase.

Formato scoperto:
  - lo zip contiene un solo file "savedGame"
  - contenuto = "!VCSK" + chiave a 1 byte in hex + payload in hex, XOR con la chiave
  - i record sono separati da ESC + "+/"
  - record utili:
      stack/<mappa>;<x>;<y>;@@<n>
      piece;;;<immagine>;<nome>/... <TAB> ... <mappa>;<x>;<y>;<layer>;<n>;UniqueID;<id>

Output: reports/vsav/<scenario>.csv  e  reports/vsav_summary.json
"""
import csv
import json
import os
import re
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.dirname(ROOT)
OUT = os.path.join(ROOT, "reports", "vsav")
os.makedirs(OUT, exist_ok=True)

MAPS = ["Main Map", "North Sea", "Norwegian Sea",
        "Kriegsmarine Task Force Display", "Royal Navy Task Force Display",
        "Allied Task Force Display",
        "Kriegsmarine Campaign Display", "Royal Navy Campaign Display",
        "Royal Navy Campaign", "Royal Navy Campaign Aid",
        "Kriegsmarine Campaign", "Kriegsmarine Campaign Aid"]
MAP_RE = "|".join(re.escape(m) for m in sorted(MAPS, key=len, reverse=True))

PIECE_TAIL = re.compile(r"(" + MAP_RE + r");(-?\d+);(-?\d+);(-?\d+);")
PIECE_HEAD = re.compile(r"piece;[^;]*;[^;]*;([^;]*);([^;/\t]*)")
STACK_RE = re.compile(r"^stack/(" + MAP_RE + r");(-?\d+);(-?\d+);")


def decode(path):
    raw = zipfile.ZipFile(path).read("savedGame").decode("ascii", "replace")
    if not raw.startswith("!VCSK"):
        raise ValueError(f"{path}: header inatteso")
    key = int(raw[5:7], 16)
    body = raw[7:]
    return bytes(int(body[i:i + 2], 16) ^ key
                 for i in range(0, len(body), 2)).decode("utf-8", "replace")


def parse(text):
    rows = []
    for rec in text.split("\x1b+/"):
        m = STACK_RE.match(rec)
        if m:
            rows.append({"kind": "stack", "image": "", "name": "",
                         "map": m.group(1), "x": int(m.group(2)), "y": int(m.group(3))})
            continue
        if "piece;" not in rec:
            continue
        h = PIECE_HEAD.search(rec)
        t = PIECE_TAIL.search(rec)
        if not t:
            continue
        img = h.group(1) if h else ""
        nm = h.group(2) if h else ""
        rows.append({"kind": "piece", "image": img, "name": nm,
                     "map": t.group(1), "x": int(t.group(2)), "y": int(t.group(3))})
    return rows


def main():
    files = sorted(f for f in os.listdir(SRC) if f.endswith(".vsav"))
    summary = []
    for f in files:
        try:
            rows = parse(decode(os.path.join(SRC, f)))
        except Exception as e:                                  # noqa: BLE001
            print(f"  !! {f}: {e}")
            continue
        stem = os.path.splitext(f)[0]
        with open(os.path.join(OUT, stem + ".csv"), "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=["kind", "image", "name", "map", "x", "y"])
            w.writeheader()
            w.writerows(rows)
        by_map = {}
        for r in rows:
            by_map[r["map"]] = by_map.get(r["map"], 0) + 1
        pieces = sum(1 for r in rows if r["kind"] == "piece")
        summary.append({"scenario": stem, "records": len(rows),
                        "pieces": pieces, "by_map": by_map})
        print(f"  {stem:38s} {len(rows):4d} record ({pieces} pedine)  {by_map}")

    with open(os.path.join(ROOT, "reports", "vsav_summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
    print(f"\n{len(summary)} scenari estratti in reports/vsav/")


if __name__ == "__main__":
    main()
