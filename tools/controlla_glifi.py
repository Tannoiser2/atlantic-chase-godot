#!/usr/bin/env python3
"""Controlla che ogni carattere mostrato dall'interfaccia esista nei font.

Un carattere che il font non contiene esce come un quadratino, e si vede solo
guardando lo schermo: nessun test se ne accorge. Questo strumento legge tutte
le stringhe che possono finire a video - il codice di `ui/` e `core/` e i dati
JSON di `core/data/` - e confronta ogni carattere non ASCII con la tabella dei
glifi dei font in `assets/fonts/`.

    tools/.venv/bin/python tools/controlla_glifi.py

Esce con codice 1 se manca anche un solo glifo, e dice in quale file e riga.
Serve `fonttools` (pip install fonttools).
"""
import glob
import os
import sys

from fontTools.ttLib import TTFont

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# I font di testo: una stringa qualunque puo' finire in uno qualsiasi di
# questi. Lo Stardos Stencil e' usato solo per il titolo, scritto nel codice,
# e si controlla a parte.
TESTO = ["Barlow-Medium.ttf", "Barlow-Bold.ttf", "Barlow-Italic.ttf",
         "Barlow-SemiBoldItalic.ttf", "BarlowCondensed-SemiBold.ttf",
         "BarlowCondensed-Medium.ttf"]
TITOLI = {"StardosStencil-Bold.ttf": ["ATLANTIC CHASE"]}


def glifi(nome):
    return set(TTFont(os.path.join(RADICE, "assets", "fonts", nome)).getBestCmap())


def main():
    comuni = None
    for nome in TESTO:
        g = glifi(nome)
        comuni = g if comuni is None else comuni & g
    file = []
    for motivo in ("ui/**/*.gd", "core/**/*.gd", "core/data/**/*.json"):
        file += glob.glob(os.path.join(RADICE, motivo), recursive=True)
    mancanti = {}
    for percorso in sorted(file):
        with open(percorso, encoding="utf-8") as fh:
            for n, riga in enumerate(fh, 1):
                # nel codice i commenti non finiscono a video
                if percorso.endswith(".gd"):
                    riga = riga.split("##")[0]
                    if riga.lstrip().startswith("#"):
                        continue
                for c in riga:
                    if ord(c) < 128 or c in "﻿":
                        continue
                    if ord(c) not in comuni:
                        mancanti.setdefault(c, []).append(
                            "%s:%d" % (os.path.relpath(percorso, RADICE), n))
    for nome, testi in TITOLI.items():
        g = glifi(nome)
        for t in testi:
            for c in t:
                if ord(c) not in g:
                    mancanti.setdefault(c, []).append("%s (titolo)" % nome)
    if not mancanti:
        print("GLIFI: OK - %d file, nessun carattere fuori dai font." % len(file))
        return 0
    print("GLIFI: MANCANO %d caratteri" % len(mancanti))
    for c, dove in sorted(mancanti.items()):
        print("  U+%04X %r  %d volte, per esempio %s"
              % (ord(c), c, len(dove), ", ".join(dove[:3])))
    return 1


if __name__ == "__main__":
    sys.exit(main())
