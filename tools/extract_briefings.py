#!/usr/bin/env python3
"""
Estrae il briefing di ogni scenario dal fascicolo Scenari per 2 Giocatori.

Dal fascicolo si ricavano i dati strutturati che i .vsav non contengono:

    INIZIATIVA           quale giocatore comincia
    CONDIZIONI METEO     stato iniziale del tempo
    FINE DELLO SCENARIO  quando finisce
    VITTORIA             come si contano i VP
    ESITO STORICO        cosa accadde davvero

Iniziativa e meteo diventano campi del gioco; il resto resta testo, mostrato
nel briefing. Le condizioni di vittoria di Atlantic Chase sono discorsive e
piene di eccezioni per scenario: trascriverle come regole eseguibili
richiederebbe una lettura riga per riga di 64 pagine. Mostrarle al giocatore e'
onesto e utile subito; automatizzarle e' un lavoro a parte.

Output: aggiorna core/data/scenarios/*.json con la chiave "briefing".
"""
import json
import os
import re
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCEN = os.path.join(ROOT, "core", "data", "scenarios")
PDF2P = os.path.join(ROOT, "docs", "regolamento",
                     "(4) Atlantic Chase 2 Players Scenarios ITA.pdf")

# titolo nel fascicolo -> nome del file scenario (dal .vsav)
SCENARIO_MAP = {
    "OP1": "Op1 Homecoming", "OP2": "Op2 First Test", "OP3": "Op3 Norway",
    "OP4": "Op4 Berlin", "OP5": "Op5 Rheinubung", "OP6": "Op6 New Friends",
    "OP7": "Op7 Non Compos Mentis", "OP8": "Op8 Cat and Mouse",
    "OP9": "Op9 Actic Calamity",
    "MS1": "MS1 Cornered", "MS2": "MS2 Escape", "MS3": "MS3 Norwegian Patrol",
    "MS4": "MS4 Chance Encounter", "MS5": "MS5 With Friends Like These",
    "MS6": "MS6 Hard Lesson", "MS7": "MS7 Clash on the High Sea",
    "MS8": "MS8 Another Opportunity", "MS9": "MS9 Sink the Bismarck",
    "MS10": "MS10 Three Days Later",
    "MS11": "MS11 Skirmish on the Barents Sea", "MS12": "MS12 Finale",
}

HEAD_RE = re.compile(r"^\s*(OP|MS)\s?(\d+)[.:]\s*(.+)$", re.M)
SECTIONS = [
    ("initiative", r"INIZIATIVA\s*:?\s*(.+?)(?:\n|$)"),
    ("weather", r"CONDIZIONI METEO\s*:?\s*(.+?)(?:\n|$)"),
    ("end", r"FINE DELLO SCENARIO\s*:?\s*(.*?)(?=\n\s*[A-ZÀ-Ù][A-ZÀ-Ù ‘’'&]{4,}\s*:?\s*\n|\Z)"),
    ("victory", r"VITTORIA\s*:?\s*(.*?)(?=\n\s*[A-ZÀ-Ù][A-ZÀ-Ù ‘’'&]{4,}\s*:?\s*\n|\Z)"),
    ("historical", r"ESITO STORICO\s*:?\s*(.*?)(?=\n\s*[A-ZÀ-Ù][A-ZÀ-Ù ‘’'&]{4,}\s*:?\s*\n|\Z)"),
]

SIDE_WORDS = {"germania": "KRIEGSMARINE", "tedesco": "KRIEGSMARINE",
              "tedesca": "KRIEGSMARINE", "gran bretagna": "ROYAL_NAVY",
              "britannico": "ROYAL_NAVY", "britannica": "ROYAL_NAVY",
              "inglese": "ROYAL_NAVY"}
WEATHER_WORDS = {"buone": "GOOD", "buono": "GOOD",
                 "avverse": "BAD", "cattive": "BAD", "brutte": "BAD"}


def clean(t):
    t = re.sub(r"Traduzione a cura.*", "", t)
    t = re.sub(r"Caccia nell.*GMT GAMES LLC", "", t)
    t = re.sub(r"[ \t]{2,}", " ", t)
    t = re.sub(r"\n{3,}", "\n\n", t)
    return t.strip()


def parse_side(t):
    low = t.lower()
    for w, v in SIDE_WORDS.items():
        if w in low:
            return v
    return ""


def parse_weather(t):
    low = t.lower()
    for w, v in WEATHER_WORDS.items():
        if w in low:
            return v
    return ""


def main():
    if not os.path.exists(PDF2P):
        print("fascicolo non trovato: %s" % PDF2P)
        return 1
    text = subprocess.run(["pdftotext", "-layout", PDF2P, "-"],
                          capture_output=True, text=True).stdout

    heads = list(HEAD_RE.finditer(text))
    # tiene solo i titoli veri di scenario (quelli dell'indice hanno il numero
    # di pagina davanti e non sono a inizio riga)
    blocks = {}
    for i, m in enumerate(heads):
        key = "%s%s" % (m.group(1), m.group(2))
        if key not in SCENARIO_MAP:
            continue
        start = m.end()
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        body = text[start:end]
        # tiene il blocco piu' lungo per scenario: l'indice produce brandelli
        if key not in blocks or len(body) > len(blocks[key][1]):
            blocks[key] = (m.group(3).strip(), body)

    updated, missing = 0, []
    for key, target in SCENARIO_MAP.items():
        path = os.path.join(SCEN, target + ".json")
        if not os.path.exists(path):
            missing.append(target)
            continue
        if key not in blocks:
            missing.append("%s (nessun blocco nel fascicolo)" % target)
            continue
        title, body = blocks[key]
        brief = {"title": clean(title)}
        for name, pattern in SECTIONS:
            m = re.search(pattern, body, re.S | re.I)
            brief[name] = clean(m.group(1)) if m else ""

        doc = json.load(open(path))
        doc["briefing"] = brief
        side = parse_side(brief["initiative"])
        weather = parse_weather(brief["weather"])
        if side:
            doc["initiative"] = 0 if side == "KRIEGSMARINE" else 1
            doc["initiative_label"] = side
        if weather:
            doc["weather"] = 0 if weather == "GOOD" else 1
            doc["weather_label"] = weather
        json.dump(doc, open(path, "w"), indent=1, ensure_ascii=False)
        updated += 1
        print("  %-34s %-28s iniz=%-12s meteo=%s"
              % (target, brief["title"][:28], side or "?", weather or "?"))

    print("\n%d scenari aggiornati" % updated)
    if missing:
        print("senza briefing (%d): %s" % (len(missing), ", ".join(missing)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
