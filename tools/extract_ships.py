#!/usr/bin/env python3
"""
Estrazione delle statistiche delle navi dalle pedine.

Le statistiche non stanno in nessun testo del gioco: sono stampate sulle
pedine. Il tracciato pero' e' identico su tutte:

    alto a sinistra  tipo        (ignorato: piu' affidabile dal nome del file)
    alto a destra    cannoni     "X/Y" = bruciapelo&corto / lungo&estremo
    basso a sinistra Difesa      cifra chiara dentro un riquadro scuro
    basso a destra   velocita'   vs | s | m | f

Tre accorgimenti fanno la differenza fra il 5% e il 95% di letture corrette:

  - soglia di OTSU invece della media: le pedine hanno fondi molto diversi
    (blu-grigio tedesco, khaki britannico) e una soglia sulla media legge la
    Bismarck ma non la Hood;
  - il riquadro della Difesa viene LOCALIZZATO (componente scura connessa)
    invece che ritagliato a coordinate fisse, e poi invertito, perche' la cifra
    e' chiara su fondo scuro mentre tesseract vuole il contrario;
  - il PSM conta: la Difesa e' un singolo carattere e vuole --psm 10, con
    --psm 7 tesseract non restituisce nulla.

Tipo, nome e nazione vengono dal nome del file, fonte piu' sicura
dell'immagine. Le letture dubbie finiscono in reports/ships_review.txt: meglio
una lista corta da controllare a occhio che un numero sbagliato nelle regole.

    python tools/extract_ships.py [--debug]
"""
import json
import os
import re
import subprocess
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
COUNTERS = os.path.join(ROOT, "assets", "counters")
REP = os.path.join(ROOT, "reports")
OUT = os.path.join(ROOT, "core", "data", "ships_ocr.json")

GUNS_REGION = (0.60, 0.00, 0.99, 0.38)
SPEED_REGION = (0.82, 0.66, 1.00, 1.00)
DEFENSE_REGION = (0.00, 0.35, 0.28, 0.92)

SPEED_MAP = {"vs": "VERY_SLOW", "s": "SLOW", "m": "MEDIUM", "f": "FAST"}
NATIONS = {"ge": "GE", "uk": "UK", "fr": "FR", "us": "US"}


def otsu(a):
    hist, _ = np.histogram(a, bins=256, range=(0, 256))
    total = a.size
    sum_all = float(np.dot(np.arange(256), hist))
    sum_b, w_b, best, thr = 0.0, 0.0, -1.0, 128
    for i in range(256):
        w_b += hist[i]
        if w_b == 0:
            continue
        w_f = total - w_b
        if w_f == 0:
            break
        sum_b += i * hist[i]
        m_b = sum_b / w_b
        m_f = (sum_all - sum_b) / w_f
        v = w_b * w_f * (m_b - m_f) ** 2
        if v > best:
            best, thr = v, i
    return thr


def to_bw(img, invert=False, pad=40, scale=8):
    im = img.convert("L").resize((img.width * scale, img.height * scale),
                                 Image.LANCZOS)
    a = np.asarray(im).astype(np.uint8)
    dark = a < otsu(a)
    if invert:
        dark = ~dark
    out = np.where(dark, 0, 255).astype(np.uint8)
    canvas = np.full((out.shape[0] + 2 * pad, out.shape[1] + 2 * pad), 255, np.uint8)
    canvas[pad:pad + out.shape[0], pad:pad + out.shape[1]] = out
    return Image.fromarray(canvas)


def find_defense_box(img):
    """Trova il riquadro scuro della Difesa e ritaglia la sola cifra."""
    W, H = img.size
    x0, y0, x1, y1 = DEFENSE_REGION
    box = img.crop((int(W * x0), int(H * y0), int(W * x1), int(H * y1)))
    a = np.asarray(box.convert("L")).astype(np.uint8)
    dark = a < max(70, otsu(a) - 20)
    dark = ndimage.binary_closing(dark, structure=np.ones((3, 3)))
    lbl, n = ndimage.label(dark)
    best, best_area = None, 0
    for i in range(1, n + 1):
        ys, xs = np.where(lbl == i)
        h = int(ys.max() - ys.min() + 1)
        w = int(xs.max() - xs.min() + 1)
        if h < 8 or w < 8:
            continue
        area = len(ys)
        if area > best_area and area > 0.45 * h * w:
            best, best_area = (int(xs.min()), int(ys.min()),
                               int(xs.max()), int(ys.max())), area
    if best is None:
        return None
    bx0, by0, bx1, by1 = best
    inset = 2
    crop = box.crop((bx0 + inset, by0 + inset, bx1 + 1 - inset, by1 + 1 - inset))
    return crop if crop.width >= 5 and crop.height >= 5 else None


def vote(readings):
    """Voto di maggioranza fra letture non vuote."""
    from collections import Counter
    c = Counter([r for r in readings if r])
    return c.most_common(1)[0][0] if c else ""


def dedup_letters(t):
    """'ff' -> 'f', 'mm' -> 'm'. Tesseract raddoppia spesso i glifi singoli."""
    if len(t) >= 2 and len(set(t)) == 1:
        return t[0]
    return t


def ocr(img, charset, psm):
    tmp = os.path.join(REP, "_ocr_tmp.png")
    img.save(tmp)
    cmd = ["tesseract", tmp, "stdout", "--psm", psm,
           "-c", "tessedit_char_whitelist=" + charset,
           "-c", "debug_file=/dev/null"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
        return r.stdout.strip().replace("\n", "")
    except Exception:                                            # noqa: BLE001
        return ""


def parse_name(fn):
    stem = os.path.splitext(fn)[0]
    parts = stem.split("_")
    if len(parts) < 3 or parts[0] != "ship":
        return None
    nation = NATIONS.get(parts[1], parts[1].upper())
    type_code = parts[2].upper()
    rest = "_".join(parts[3:]) if len(parts) > 3 else ""
    damaged = False
    if rest.endswith("_b"):
        damaged, rest = True, rest[:-2]
    elif rest.endswith("b") and not rest.endswith("bb"):
        damaged, rest = True, rest[:-1]
    name = rest.replace("_", " ").strip().title()
    if type_code == "--":
        type_code = ""
    return {"nation": nation, "type": type_code, "name": name, "damaged": damaged}


def clean_guns(t):
    """
    Normalizza il campo cannoni.

    Due particolarita' della grafica delle pedine:
      - lo ZERO e' disegnato come una 'o' minuscola ("o/-1"), quindi va
        accettata la lettera e convertita in cifra;
      - portaerei, petroliere e mercantili stampano un solo "na" invece di
        "na/na", e vale per entrambe le bande di raggio.
    """
    t = t.replace(" ", "").replace("|", "/").replace("\\", "/").lower()
    t = t.replace("o", "0")
    t = re.sub(r"[^0-9na/\-]", "", t)
    if t == "na":
        return "na", "na", True
    m = re.match(r"^(-?\d+|na)/(-?\d+|na)$", t)
    return (m.group(1), m.group(2), True) if m else (t, "", False)


def as_gun(v):
    if v == "na":
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def main():
    debug = "--debug" in sys.argv
    os.makedirs(REP, exist_ok=True)
    files = sorted(f for f in os.listdir(COUNTERS)
                   if f.startswith("ship_") and f.endswith(".png"))
    ships, review = [], []

    for fn in files:
        meta = parse_name(fn)
        if meta is None:
            continue
        im = Image.open(os.path.join(COUNTERS, fn)).convert("RGB")
        W, H = im.size

        # --- cannoni: voto su piu' ingrandimenti, poi lettura a meta' ---
        g = GUNS_REGION
        gbox = im.crop((int(W * g[0]), int(H * g[1]), int(W * g[2]), int(H * g[3])))
        cands = [ocr(to_bw(gbox, scale=sc), "0123456789oO/na-", "7")
                 for sc in (6, 8, 10)]
        guns_raw = vote([c for c in cands if clean_guns(c)[2]]) or vote(cands)
        if not clean_guns(guns_raw)[2]:
            # una delle due meta' si perde spesso: leggile separate
            half = gbox.width // 2
            left = gbox.crop((0, 0, half + 2, gbox.height))
            right = gbox.crop((half - 2, 0, gbox.width, gbox.height))
            lv = vote([dedup_letters(ocr(to_bw(left, scale=sc), "0123456789oOna-", "7"))
                       for sc in (8, 10)])
            rv = vote([dedup_letters(ocr(to_bw(right, scale=sc), "0123456789oOna-", "7"))
                       for sc in (8, 10)])
            lv = re.sub(r"[^0-9na\-]", "", lv.lower().replace("o", "0"))
            rv = re.sub(r"[^0-9na\-]", "", rv.lower().replace("o", "0"))
            if lv and rv:
                guns_raw = "%s/%s" % (lv, rv)

        # --- velocita': voto, e i glifi doppi si collassano ---
        sr = SPEED_REGION
        sbox = im.crop((int(W * sr[0]), int(H * sr[1]),
                        int(W * sr[2]), int(H * sr[3])))
        sc_reads = []
        for scale in (6, 8, 12):
            img = to_bw(sbox, scale=scale)
            for psm in ("7", "8", "10"):
                sc_reads.append(dedup_letters(ocr(img, "vsmf", psm).lower()))
        speed_raw = vote([r for r in sc_reads if r in SPEED_MAP]) or vote(sc_reads)

        # --- Difesa: voto su piu' ingrandimenti e su entrambe le polarita' ---
        dbox = find_defense_box(im)
        def_raw = ""
        if dbox is not None:
            reads = []
            for scale in (8, 12, 16):
                for inv in (True, False):
                    reads.append(ocr(to_bw(dbox, invert=inv, scale=scale),
                                     "0123456789", "10"))
            def_raw = vote([r for r in reads if r.isdigit() and len(r) == 1]) \
                or vote(reads)
            if debug:
                to_bw(dbox, invert=True).save(
                    os.path.join(REP, "ocr_%s_def.png" % os.path.splitext(fn)[0]))

        gc, gf, guns_ok = clean_guns(guns_raw)
        speed = SPEED_MAP.get(speed_raw.strip().lower(), "")
        defense = re.sub(r"\D", "", def_raw)

        ships.append({
            "file": fn, "name": meta["name"], "nation": meta["nation"],
            "type": meta["type"], "damaged_side": meta["damaged"],
            "gun_close": as_gun(gc) if guns_ok else None,
            "gun_far": as_gun(gf) if guns_ok else None,
            "gun_close_na": bool(guns_ok and gc == "na"),
            "gun_far_na": bool(guns_ok and gf == "na"),
            "defense": int(defense) if defense else 0,
            "speed": speed,
            "_raw": {"guns": guns_raw, "speed": speed_raw, "defense": def_raw},
        })

        problems = []
        if not guns_ok:
            problems.append("cannoni %r" % guns_raw)
        # la Batteria Costiera non si muove: non ha velocita' stampata
        if speed == "" and "shore_battery" not in fn:
            problems.append("velocita' %r" % speed_raw)
        # Convogli, Squadroni DD, ausiliarie e petroliere non hanno il riquadro
        # Difesa: per loro l'assenza e' normale, non un errore di lettura.
        if meta["type"] not in ("", "DD", "AC") and "shore_battery" not in fn \
                and "convoy" not in fn and not defense:
            problems.append("Difesa %r" % def_raw)
        if problems:
            review.append("%-42s %s" % (fn, "; ".join(problems)))

    json.dump({
        "_source": "OCR delle pedine (tesseract, soglia di Otsu); tipo, nome e "
                   "nazione dal nome del file. gun_*_na = la pedina riporta 'na', "
                   "cioe' la nave non puo' sparare a quel raggio.",
        "_review": "reports/ships_review.txt elenca le pedine da controllare a occhio.",
        "ships": ships,
    }, open(OUT, "w"), indent=1)

    with open(os.path.join(REP, "ships_review.txt"), "w") as f:
        f.write("\n".join(review) + "\n")

    print("%d pedine, %d complete, %d da verificare"
          % (len(ships), len(ships) - len(review), len(review)))
    for line in review[:25]:
        print("   " + line)


if __name__ == "__main__":
    main()
