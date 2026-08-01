#!/usr/bin/env python3
"""
Unisce le due facce di ogni pedina in una sola scheda nave.

L'OCR produce una riga per PEDINA (lato integro e lato Danneggiato sono due
immagini distinte). Il gioco vuole una riga per NAVE, con i valori di entrambi
i lati, perche' girando la pedina cambiano cannoni, Difesa E velocita':

    Bismarck   integra   4/2  Difesa 2  media
               danneg.   3/1  Difesa 4  lenta

Applica anche core/data/ships_overrides.json, cioe' le pedine lette a occhio
perche' l'OCR non ce l'ha fatta.

Output: core/data/ships.json nel formato che carica il gioco.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DATA = os.path.join(ROOT, "core", "data")
RAW = os.path.join(DATA, "ships_ocr.json")
OVERRIDES = os.path.join(DATA, "ships_overrides.json")
OUT = os.path.join(DATA, "ships.json")

KINDS = {"convoy": "CONVOY", "dd_squadron": "DD_SQUADRON",
         "shore_battery": "SHORE_BATTERY"}


def kind_of(fn, type_code):
    for frag, k in KINDS.items():
        if frag in fn:
            return k
    return "WARSHIP"


def display_name(rec):
    """
    Per Convogli, Squadroni DD e Batterie Costiere il nome del file mette la
    parola di tipo dove di solito c'e' il tipo della nave (ship_uk_convoy_x3),
    quindi il parser la scambia per un codice e lascia il nome a 'X3'.
    Qui si ricompone un nome leggibile.
    """
    fn = os.path.splitext(rec["file"])[0]
    for frag, label in (("convoy", "Convoy"), ("dd_squadron", "DD Squadron"),
                        ("shore_battery", "Shore Battery")):
        if frag in fn:
            suffix = rec["name"].strip()
            if frag == "convoy" and suffix:
                return "%s %s" % (label, suffix.lower())
            return label
    return rec["name"]


def key_of(rec):
    """Chiave che unisce lato integro e lato danneggiato della stessa nave."""
    return (rec["nation"], rec["type"], rec["name"])


def main():
    raw = json.load(open(RAW))["ships"]
    ovdoc = json.load(open(OVERRIDES))
    ov = ovdoc["overrides"]
    excluded = ovdoc.get("exclude", {})

    raw = [r for r in raw if r["file"] not in excluded]
    for r in raw:
        if r["file"] in ov:
            r.update(ov[r["file"]])
            r["_manual"] = True

    for r in raw:
        r["name"] = display_name(r)

    ships, problems = {}, []
    for r in raw:
        k = key_of(r)
        if k not in ships:
            ships[k] = {
                "name": r["name"], "nation": r["nation"], "type": r["type"],
                "kind": kind_of(r["file"], r["type"]),
                "gun_close": None, "gun_far": None,
                "gun_close_damaged": None, "gun_far_damaged": None,
                "defense": 0, "defense_damaged": 0,
                "speed": "", "speed_damaged": "",
                "has_damaged_side": False,
                "files": [], "manual": False,
            }
        s = ships[k]
        s["files"].append(r["file"])
        if r.get("_manual"):
            s["manual"] = True
        if r["damaged_side"]:
            s["has_damaged_side"] = True
            s["gun_close_damaged"] = r["gun_close"]
            s["gun_far_damaged"] = r["gun_far"]
            s["defense_damaged"] = r["defense"]
            s["speed_damaged"] = r["speed"]
        else:
            s["gun_close"] = r["gun_close"]
            s["gun_far"] = r["gun_far"]
            s["defense"] = r["defense"]
            s["speed"] = r["speed"]

    out = []
    for k in sorted(ships):
        s = ships[k]
        # una nave senza lato Danneggiato usa gli stessi valori (Convogli,
        # Squadroni DD, Batterie Costiere: non si girano mai)
        if not s["has_damaged_side"]:
            s["speed_damaged"] = s["speed"]
            s["defense_damaged"] = s["defense"]
            s["gun_close_damaged"] = s["gun_close"]
            s["gun_far_damaged"] = s["gun_far"]
        if s["speed"] == "" and s["kind"] != "SHORE_BATTERY":
            problems.append("%s: velocita' mancante" % s["name"])
        if s["kind"] == "WARSHIP" and s["defense"] == 0:
            problems.append("%s: Difesa mancante" % s["name"])
        out.append(s)

    json.dump({
        "_source": "tools/extract_ships.py (OCR delle pedine) + "
                   "core/data/ships_overrides.json (letture a occhio).",
        "_schema": "Una voce per NAVE, non per pedina: i campi *_damaged sono "
                   "quelli del lato Danneggiato. gun_* a null significa 'na' "
                   "sulla pedina, cioe' la nave non puo' sparare a quel raggio "
                   "(tipico delle portaerei integre, che al posto dei valori "
                   "stampano l'icona dell'aereo).",
        "count": len(out),
        "ships": out,
    }, open(OUT, "w"), indent=1)

    manual = sum(1 for s in out if s["manual"])
    print("%d navi (da %d pedine), %d con almeno un valore corretto a mano"
          % (len(out), len(raw), manual))
    print("navi con lato Danneggiato: %d"
          % sum(1 for s in out if s["has_damaged_side"]))
    if excluded:
        print("pedine escluse: %s" % ", ".join(excluded))
    if problems:
        print("\nDA CONTROLLARE (%d):" % len(problems))
        for p in problems[:20]:
            print("   " + p)
        return 1
    print("nessun campo mancante")
    return 0


if __name__ == "__main__":
    sys.exit(main())
