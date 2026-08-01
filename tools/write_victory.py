#!/usr/bin/env python3
"""
Trascrizione a mano delle tabelle di Vittoria delle nove Operazioni.

Le tabelle sono state lette dall'edizione INGLESE del fascicolo per 2 giocatori
(AC_TwoPlayer_Book_May_9_2021), pagina per pagina, a piena risoluzione. La
traduzione italiana perde le intestazioni di colonna di alcune tabelle (nella
Rheinubung sparivano Francia / Norvegia / Germania, e senza quelle la tabella
tedesca e' illeggibile), quindi la fonte e' l'inglese.

Perche' uno script e non nove file scritti a mano: le nove tabelle ripetono le
stesse righe con numeri diversi (convogli, corazzate affondate, Colpi sui
convogli). Scritte a mano nove volte, una svista in una riga non si nota;
scritte una volta come funzione, o sono giuste tutte o e' sbagliata la funzione.

Rigenera core/data/victory/*.json:  tools/.venv/bin/python tools/write_victory.py
"""

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "core", "data", "victory")

KM = "KRIEGSMARINE"
RN = "ROYAL_NAVY"

# "British" nelle tabelle vuol dire il giocatore britannico, che comanda anche
# le navi francesi e (in Op7/Op8) quelle americane. Dove una tabella distingue
# davvero i francesi - Op2, "French BC sunk" - il premio filtra FR da solo.
BRIT = ["UK", "FR", "US"]


def award(side, event, points, label, match=None, manual=False, once=False):
    a = {"side": side, "event": event, "points": points, "label": label}
    if match:
        a["match"] = match
    if manual:
        a["manual"] = True
    if once:
        a["once"] = True
    return a


def ship_rows(side, event_pairs, match, label):
    """Una riga 'X danneggiata / affondata' vale due premi distinti."""
    out = []
    for event, pts, suffix in event_pairs:
        if pts is None:
            continue
        out.append(award(side, event, pts, "%s %s" % (label, suffix), match))
    return out


def dmg_sunk(side, damaged, sunk, match, label, hit=None):
    pairs = [("SHIP_DAMAGED", damaged, "danneggiata"),
             ("SHIP_SUNK", sunk, "affondata")]
    if hit is not None:
        pairs.insert(0, ("SHIP_HIT", hit, "colpita"))
    return ship_rows(side, pairs, match, label)


def convoy(side, points, label, dispersed=None, destinations=None,
           other_than=None, owner=None):
    """Convoglio che Completa. `dispersed` None = vale in entrambi i casi."""
    m = {}
    if dispersed is not None:
        m["dispersed"] = dispersed
    if destinations:
        m["destinations"] = destinations
    if other_than:
        m["exclude_destinations"] = other_than
    if owner:
        m["owner"] = owner
    return award(side, "CONVOY_COMPLETED", points, label, m or None)


GE_BC = {"types": ["BC"], "nations": ["GE"]}
GE_CRUISERS_PB = {"types": ["CA", "CL", "PB"], "nations": ["GE"]}
BRIT_CAPITAL = {"types": ["BB", "BC", "CV"], "nations": BRIT}
BRIT_CRUISER = {"types": ["CA", "CL"], "nations": BRIT}

ARCTIC = ["Murmansk", "Archangel"]

SOURCE = ("Fascicolo Scenari per 2 Giocatori, edizione INGLESE "
          "(AC_TwoPlayer_Book_May_9_2021), %s. Trascritta a mano da "
          "tools/write_victory.py.")

TABLES = {}

# Chi controlla i porti, quando lo scenario cambia la situazione di partenza.
# Vale "il nome del porto ha la precedenza sulla sua nazione": gli scenari
# chiudono singoli porti senza toccare gli altri dello stesso paese.
# Valori: KRIEGSMARINE, ROYAL_NAVY, BOTH, NONE.
GERMAN_WEST = {"FR": KM, "NO": KM}   # "All French and Norwegian ports are
                                     # German controlled", da Op4 in poi

# In quale porto entra ciascun Gruppo di Rinforzi.
#
# Il salvataggio VASSAL non lo dice: i Gruppi stanno in caselle del Display
# Task Force, che non sono esagoni della mappa. Il porto e' stampato sulla
# mappa dello scenario nel fascicolo, e va letto da li'.
#
# Trascritto solo dove l'ho visto davvero sulla pagina. Dove manca, il gioco
# lo dice invece di scegliere un porto a caso: un Gruppo che entra nel porto
# sbagliato e' peggio di un Gruppo che non entra.
REINFORCEMENT_PORTS = {
    "Op1 Homecoming":       {"KM Reinforcement A": "Kiel"},
    "Op2 First Test":       {"KM Reinforcement A": "Kiel",
                             "RN Reinforcement A": "Clyde"},
    "Op3 Norway":           {"RN Reinforcement A": "Scapa Flow",
                             "RN Reinforcement B": "Clyde",
                             "RN Reinforcement C": "Africa",
                             "RN Reinforcement D": "Gibilterra"},
    "Op4 Berlin":           {"RN Reinforcement A": "Clyde",
                             "RN Reinforcement B": "Scapa Flow",
                             "RN Reinforcement C": "Clyde",
                             "RN Reinforcement D": "Gibilterra"},
    "Op5 Rheinubung":       {"RN Reinforcement A": "Gibilterra",
                             "RN Reinforcement B": "Scapa Flow",
                             "RN Reinforcement C": "Clyde"},
    "Op6 New Friends":      {"RN Reinforcement A": "Clyde",
                             "RN Reinforcement B": "Gibilterra",
                             "KM Reinforcement A": "Kiel",
                             "KM Reinforcement B": "Brest"},
    "Op7 Non Compos Mentis": {"RN Reinforcement A": "Clyde",
                              "RN Reinforcement B": "Clyde"},
    "Op8 Cat and Mouse":    {"RN Reinforcement A": "Clyde",
                             "RN Reinforcement B": "Gibilterra"},
    "Op9 Actic Calamity":   {"RN Reinforcement A": "Scapa Flow",
                             "RN Reinforcement B": "Gibilterra",
                             "KM Reinforcement A": "Kiel"},
}

# --------------------------------------------------------------------------
# Op1 Homecoming - nessuna tabella VP: si vince per condizioni.
# --------------------------------------------------------------------------
TABLES["Op1 Homecoming"] = {
    "port_control": {"FR": "NONE", "NO": "NONE", "Murmansk": "BOTH",
                     "New York": "NONE"},
    "mode": "CONDITIONS",
    "_source": SOURCE % "pp.3-4",
    "awards": [],
    "conditions": [
        {"winner": RN,
         "text": ("Una nave tedesca e' Danneggiata o affondata (possibile solo "
                  "dopo la dichiarazione di guerra). Vale comunque, "
                  "qualunque sia la sorte del Bremen")},
        {"winner": KM,
         "text": ("Il Bremen Completa a Kiel, Wilhelmshaven o Murmansk, e a "
                  "Murmansk non viene confiscato")},
        {"winner": RN, "text": "I britannici catturano il Bremen"},
        {"winner": RN, "text": "Provocazione, Caso 1: i britannici provocano la guerra"},
        {"winner": KM, "text": "Provocazione, Caso 2: i britannici provocano la guerra"},
    ],
    "notes": [
        "Le condizioni vanno lette DALL'ALTO IN BASSO: vince la prima che si "
        "verifica. Nel fascicolo l'ultima riga e' quella sulle navi tedesche "
        "danneggiate, introdotta da 'Finally... regardless of the Bremen's "
        "fate': ha la precedenza su tutte, quindi qui e' messa per prima.",
        "I due Casi di Provocazione portano allo stesso evento - i britannici "
        "fanno scoppiare la guerra - ma a vincitori opposti: dipende da come "
        "e' successo (Caso 1, tiro di '1' su un'azione Ingaggio; Caso 2, "
        "incidente diplomatico in un esagono con Murmansk, Kiel o "
        "Wilhelmshaven). Il fascicolo commenta il Caso 2 cosi': 'vince il "
        "governo nazista, e perde il popolo tedesco insieme al resto "
        "d'Europa'.",
        "Nessun punto vittoria in questo scenario: il segnapunti resta a zero.",
    ],
}

# --------------------------------------------------------------------------
# Op2 First Test
# --------------------------------------------------------------------------
TABLES["Op2 First Test"] = {
    "_source": SOURCE % "pp.7-8",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato", dispersed=False),
        convoy(RN, 2, "Convoglio disperso che ha Completato", dispersed=True),
        *dmg_sunk(RN, 2, 4, GE_BC, "incrociatore da battaglia tedesco"),
        *dmg_sunk(RN, 1, 2,
                  {"nations": ["GE"], "exclude_types": ["BC"]},
                  "altra nave tedesca"),

        award(KM, "SHIP_COMPLETED", 5, "Graf Spee Completa a Kiel o Wilhelmshaven",
              {"names": ["Graf Spee"], "destinations": ["Kiel", "Wilhelmshaven"],
               "damaged": False}),
        award(KM, "SHIP_COMPLETED", 3,
              "Graf Spee Completa a Kiel o Wilhelmshaven (danneggiata)",
              {"names": ["Graf Spee"], "destinations": ["Kiel", "Wilhelmshaven"],
               "damaged": True}),
        *dmg_sunk(KM, 1, 2, {"types": ["BB", "BC", "CV"], "nations": ["UK"]},
                  "BB, BC o CV britannica"),
        *dmg_sunk(KM, 0, 2, {"types": ["BC"], "nations": ["FR"]},
                  "BC francese"),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),

        award(RN, "CUSTOM", 1,
              "Zona di Sicurezza USA (regola opzionale): ogni azione Ingaggio "
              "di una TF tedesca in un esagono a ovest della Linea di "
              "Sicurezza USA", manual=True),
    ],
    "tiebreak": {
        "side": KM, "auto": False,
        "condition": ("In caso di parita' vince il tedesco se il Graf Spee e' a "
                      "Kiel o a Wilhelmshaven, altrimenti vince il britannico."),
    },
    "notes": [
        "'Altra nave tedesca' e' la riga complementare a quella degli "
        "incrociatori da battaglia: vale per tutto TRANNE i BC, che hanno gia' "
        "la loro riga da 2/4.",
        "Il BC francese affondato vale 2 al tedesco, ma danneggiato vale ZERO: "
        "la tabella scrive esplicitamente (0), non e' una casella vuota.",
        "La Zona di Sicurezza USA e' una regola OPZIONALE, che i giocatori "
        "adottano di comune accordo; ed e' un premio che si ripete. Il motore "
        "non la assegna da solo: resta nell'elenco da spuntare a mano.",
    ],
}

# --------------------------------------------------------------------------
# Op3 Norway
# --------------------------------------------------------------------------
TABLES["Op3 Norway"] = {
    "_source": SOURCE % "pp.11-12",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato"),
        *dmg_sunk(RN, 1, 2, GE_BC, "incrociatore da battaglia tedesco"),
        *dmg_sunk(RN, 0, 1, {"names": ["Hipper"]}, "Hipper"),
        *dmg_sunk(RN, 0, 1, {"types": ["CL"], "nations": ["GE"]},
                  "incrociatore leggero tedesco"),
        award(RN, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio tedesco",
              {"owner": KM}),
        award(RN, "SHIP_HIT", 1, "ogni Colpo su uno Squadrone DD tedesco",
              {"names": ["DD Squadron"], "nations": ["GE"]}),
        award(RN, "CUSTOM", 3,
              "Campo minato a Narvik o Trondheim, posato PRIMA che una base "
              "aerea tedesca fosse in Norvegia", manual=True),
        award(RN, "CUSTOM", 1,
              "Campo minato a Narvik o Trondheim, posato DOPO che una base "
              "aerea tedesca era in Norvegia", manual=True),
        award(RN, "CUSTOM", -1,
              "Nessun campo minato a Narvik ne' a Trondheim", manual=True),
        award(RN, "CUSTOM", 1,
              "Marcatore Base Aerea britannica in Norvegia", manual=True),

        award(KM, "SHIP_COMPLETED", 3,
              "primo Completamento tedesco riuscito a Bergen",
              {"destination": "Bergen"}, once=True),
        award(KM, "SHIP_COMPLETED", 2,
              "primo Completamento tedesco riuscito a Trondheim",
              {"destination": "Trondheim"}, once=True),
        award(KM, "SHIP_COMPLETED", 1,
              "primo Completamento tedesco riuscito a Narvik",
              {"destination": "Narvik"}, once=True),
        *dmg_sunk(KM, 1, 2, BRIT_CAPITAL, "BB, BC o CV britannica"),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio britannico",
              {"owner": RN}),
        award(KM, "CUSTOM", 2,
              "Marcatore Base Aerea tedesca in Norvegia", manual=True),
        award(KM, "CUSTOM", -1,
              "Nessun marcatore Base Aerea tedesca", manual=True),
    ],
    "tiebreak": {
        "side": RN, "auto": True,
        "condition": "In caso di parita' vince il britannico.",
    },
    "notes": [
        "I tre premi per il Completamento in Norvegia valgono UNA VOLTA SOLA "
        "ciascuno: la tabella dice 'first successful German Completion'. Il "
        "secondo Completamento nello stesso porto non porta niente.",
        "Le mine sono tre righe che si escludono a vicenda (3, 1 oppure -1) e "
        "il -1 e' un punto TOLTO al britannico: non aver minato costa. Il "
        "motore non sa dove sono i campi minati ne' quando sono stati posati, "
        "quindi le tre righe restano da spuntare a mano - una sola delle tre.",
        "I Colpi sui convogli filtrano il proprietario: qui il britannico "
        "guadagna colpendo convogli TEDESCHI (il traffico del ferro) e il "
        "tedesco colpendo quelli britannici.",
        "Il fascicolo aggiunge una nota amara sul 'vincere che cosa': se una "
        "parte ha eseguito piu' Completamenti riusciti in Norvegia "
        "dell'avversario, quella parte ha vinto la Norvegia.",
    ],
}

# --------------------------------------------------------------------------
# Op4 Berlin
# --------------------------------------------------------------------------
TABLES["Op4 Berlin"] = {
    "port_control": dict(GERMAN_WEST),
    "_source": SOURCE % "pp.15-16",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato", dispersed=False),
        convoy(RN, 2, "Convoglio disperso che ha Completato", dispersed=True),
        *dmg_sunk(RN, 2, 4, GE_BC, "incrociatore da battaglia tedesco"),
        *dmg_sunk(RN, 1, 2, {"names": ["Hipper"]}, "Hipper"),
        *dmg_sunk(RN, 0, 1, {"names": ["Scheer"]}, "Scheer"),
        award(RN, "CUSTOM", 1,
              "La TF dell'Hipper ha eseguito un'azione Traiettoria",
              manual=True),

        award(KM, "SHIP_COMPLETED", 2,
              "incrociatore da battaglia tedesco che Completa in un porto francese",
              {"types": ["BC"], "nations": ["GE"], "destination": "France",
               "damaged": False}),
        award(KM, "SHIP_COMPLETED", 1,
              "incrociatore da battaglia tedesco che Completa in un porto "
              "francese (danneggiato)",
              {"types": ["BC"], "nations": ["GE"], "destination": "France",
               "damaged": True}),
        award(KM, "SHIP_COMPLETED", 2, "Scheer Completa a Kiel",
              {"names": ["Scheer"], "destination": "Kiel", "damaged": False}),
        award(KM, "SHIP_COMPLETED", 1, "Scheer Completa a Kiel (danneggiata)",
              {"names": ["Scheer"], "destination": "Kiel", "damaged": True}),
        *dmg_sunk(KM, 1, 2, BRIT_CAPITAL, "BB, BC o CV britannica"),
        award(KM, "SHIP_SUNK", 0.5, "incrociatore britannico affondato",
              BRIT_CRUISER),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),
    ],
    "tiebreak": {
        "side": RN, "auto": True,
        "condition": "In caso di parita' vince il britannico.",
    },
    "notes": [
        "'La TF dell'Hipper ha eseguito un'azione Traiettoria' vale 1 punto al "
        "britannico: e' il premio per aver costretto l'Hipper a muoversi "
        "invece di restare in agguato. Il motore non tiene un registro di "
        "quali TF hanno eseguito quali azioni, quindi resta da spuntare.",
        "Mezzo punto per l'incrociatore britannico affondato: il conteggio dei "
        "VP e' in virgola mobile apposta.",
        "Pool Scorte: il britannico puo' cambiare il risultato della Tabella "
        "delle Scorte assegnando 1 VP al tedesco.",
    ],
}

# --------------------------------------------------------------------------
# Op5 Rheinubung
#
# L'unica tabella che il fascicolo ITALIANO rende inservibile: la tabella
# tedesca ha tre colonne di numeri senza intestazione. Nell'inglese le
# intestazioni ci sono, e sono le destinazioni: France / Norway / Germany.
# --------------------------------------------------------------------------
GE_CONTROLLED = {"owner": KM}
RN_CONTROLLED = {"owner": RN}


def completes(side, names, label, france, norway, germany,
              france_d, norway_d, germany_d):
    """Riga 'X Completa in...' con le tre destinazioni e le due condizioni."""
    out = []
    for dest, it, pts, pts_d in (("France", "Francia", france, france_d),
                                 ("Norway", "Norvegia", norway, norway_d),
                                 ("Germany", "Germania", germany, germany_d)):
        if pts:
            out.append(award(side, "SHIP_COMPLETED", pts,
                             "%s Completa in %s" % (label, it),
                             {"names": names, "destination": dest,
                              "damaged": False}))
        if pts_d:
            out.append(award(side, "SHIP_COMPLETED", pts_d,
                             "%s Completa in %s (danneggiato)" % (label, it),
                             {"names": names, "destination": dest,
                              "damaged": True}))
    return out


TABLES["Op5 Rheinubung"] = {
    "port_control": dict(GERMAN_WEST),
    "_source": SOURCE % "pp.19-20",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato", dispersed=False),
        convoy(RN, 2, "Convoglio disperso che ha Completato", dispersed=True),
        *dmg_sunk(RN, 3, 7, {"names": ["Bismarck"]}, "Bismarck"),
        *dmg_sunk(RN, 1, 2,
                  dict(GE_CONTROLLED, types=["CA", "CL"],
                       exclude_names=["Bismarck"]),
                  "incrociatore controllato dal tedesco"),
        *dmg_sunk(RN, 1, 4,
                  dict(GE_CONTROLLED, types=["BB", "BC", "PB"],
                       exclude_names=["Bismarck"]),
                  "BB, BC o PB controllata dal tedesco"),

        *completes(KM, ["Bismarck"], "Bismarck", 3, 0, 0, 2, 2, 3),
        *completes(KM, ["Preugen"], "Prinz Eugen", 2, 0, 0, 1, 1, 2),
        *dmg_sunk(KM, 1, 2, dict(RN_CONTROLLED, types=["BB", "BC"]),
                  "BB o BC controllata dal britannico"),
        *dmg_sunk(KM, 2, 3, dict(RN_CONTROLLED, types=["CV"]),
                  "portaerei controllata dal britannico"),
        award(KM, "SHIP_SUNK", 0.5, "incrociatore controllato dal britannico affondato",
              dict(RN_CONTROLLED, types=["CA", "CL"])),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),

        award(KM, "CUSTOM", -1,
              "Variante 'Jutland': -1 VP per ogni Gruppo di Rinforzi tedesco "
              "che entra in gioco", manual=True),
        award(KM, "CUSTOM", -1,
              "Variante Francese: -1 VP al giocatore il cui Gruppo di Rinforzi "
              "francese entra in gioco (-2 se comprende un BC francese)",
              manual=True),
    ],
    "tiebreak": {
        "side": KM, "auto": False,
        "condition": ("In caso di parita' vince il tedesco se il Bismarck e' in "
                      "un porto francese (ha Completato). Altrimenti vince il "
                      "britannico."),
    },
    "notes": [
        "Il Completamento vale secondo il paese del porto: Francia / Norvegia "
        "/ Germania. Un Bismarck INTEGRO vale 3 solo in Francia; DANNEGGIATO "
        "vale 2 in Francia e Norvegia ma 3 in Germania, perche' riportarlo a "
        "casa conciato vale piu' che perderlo.",
        "Le righe generiche filtrano per CONTROLLO, non per bandiera: la "
        "tabella dice 'navi tedesche o francesi controllate dal tedesco' e "
        "'britanniche o francesi controllate dal britannico'. Con la Variante "
        "Francese le navi francesi sono in gioco su entrambi i lati, quindi "
        "filtrare per nazione assegnerebbe i punti alla parte sbagliata.",
        "Le righe generiche del britannico escludono il Bismarck: la tabella "
        "lo scrive esplicitamente ('not the Bismarck'). Senza l'esclusione il "
        "Bismarck affondato pagherebbe due volte, 7 dalla sua riga piu' 4 da "
        "quella delle corazzate.",
        "Le due varianti tolgono punti e si applicano a mano perche' dipendono "
        "da un accordo fra i giocatori prima della partita.",
        "Pool Scorte: il britannico puo' cambiare il risultato della Tabella "
        "delle Scorte assegnando 1 VP al tedesco.",
    ],
}

# --------------------------------------------------------------------------
# Op6 New Friends
# --------------------------------------------------------------------------
TABLES["Op6 New Friends"] = {
    "port_control": dict(GERMAN_WEST, **{"South America": "NONE"}),
    "_source": SOURCE % "pp.23-24",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato a Murmansk o Archangel",
               dispersed=False, destinations=ARCTIC),
        convoy(RN, 2,
               "Convoglio disperso che ha Completato a Murmansk o Archangel",
               dispersed=True, destinations=ARCTIC),
        convoy(RN, 2, "Convoglio che ha Completato in un altro porto",
               dispersed=False, other_than=ARCTIC),
        convoy(RN, 1, "Convoglio disperso che ha Completato in un altro porto",
               dispersed=True, other_than=ARCTIC),
        *dmg_sunk(RN, 3, 7, {"names": ["Tirpitz"]}, "Tirpitz"),
        *dmg_sunk(RN, 0, 3, GE_BC, "incrociatore da battaglia tedesco"),
        *dmg_sunk(RN, 0, 1, GE_CRUISERS_PB, "incrociatore o corazzata tascabile tedesca"),

        *dmg_sunk(KM, 1, 2, {"types": ["BB", "BC"], "nations": BRIT},
                  "BB o BC britannica"),
        *dmg_sunk(KM, 1, 2, {"types": ["CV"], "nations": BRIT},
                  "portaerei britannica"),
        award(KM, "SHIP_SUNK", 0.5, "incrociatore britannico affondato",
              BRIT_CRUISER),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),
    ],
    "tiebreak": {
        "side": KM, "auto": False,
        "condition": ("In caso di parita' vince il tedesco se il Tirpitz e' in "
                      "un porto (ha Completato) e quel porto NON e' Kiel ne' "
                      "Wilhelmshaven. Altrimenti vince il britannico."),
    },
    "notes": [
        "Il convoglio vale in base al porto in cui arriva: 3 a Murmansk o "
        "Archangel (i convogli artici, quelli che contano), 2 altrove; un "
        "punto in meno se e' disperso.",
        "L'affondamento del Tirpitz vale 7 punti, quanto due convogli artici e "
        "mezzo: e' lo scenario in cui la sua sola esistenza vale piu' di quel "
        "che fa.",
    ],
}

# --------------------------------------------------------------------------
# Op7 Non Compos Mentis
# --------------------------------------------------------------------------
TABLES["Op7 Non Compos Mentis"] = {
    "port_control": dict(GERMAN_WEST),
    "_source": SOURCE % "pp.27-28",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato a Murmansk o Archangel",
               dispersed=False, destinations=ARCTIC),
        convoy(RN, 2,
               "Convoglio disperso che ha Completato a Murmansk o Archangel",
               dispersed=True, destinations=ARCTIC),
        convoy(RN, 2, "Convoglio che ha Completato in un altro porto",
               dispersed=False, other_than=ARCTIC),
        convoy(RN, 1, "Convoglio disperso che ha Completato in un altro porto",
               dispersed=True, other_than=ARCTIC),
        *dmg_sunk(RN, 3, 7, {"names": ["Tirpitz"]}, "Tirpitz"),
        *dmg_sunk(RN, 1, 3, GE_BC, "incrociatore da battaglia tedesco"),
        *dmg_sunk(RN, 0, 1, GE_CRUISERS_PB, "incrociatore o corazzata tascabile tedesca"),

        award(KM, "SHIP_COMPLETED", 2,
              "incrociatore da battaglia tedesco che Completa in Norvegia",
              {"types": ["BC"], "nations": ["GE"], "destination": "Norway"}),
        award(KM, "SHIP_COMPLETED", 1,
              "incrociatore da battaglia tedesco che Completa a Kiel",
              {"types": ["BC"], "nations": ["GE"], "destination": "Kiel"}),
        award(KM, "SHIP_COMPLETED", 1,
              "Prinz Eugen Completa in Norvegia",
              {"names": ["Preugen"], "destination": "Norway"}),
        award(KM, "SHIP_SUNK", 1, "BB, BC o CV britannica affondata",
              BRIT_CAPITAL),
        award(KM, "SHIP_SUNK", 0.5, "incrociatore britannico affondato",
              BRIT_CRUISER),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),
    ],
    "tiebreak": {
        "side": RN, "auto": True,
        "condition": "In caso di parita' vince il britannico.",
    },
    "notes": [
        "Il Prinz Eugen che Completa a Kiel vale ZERO: la tabella scrive 0, "
        "non lascia la casella vuota. Riportarlo in Germania non e' un "
        "risultato, e' una ritirata - il senso dell'intera operazione era "
        "portare le navi in Norvegia.",
        "Nessun premio per le navi britanniche DANNEGGIATE in questo scenario: "
        "la tabella tedesca ha solo la colonna 'sunk'.",
        "Il fascicolo aggiunge un giudizio che il punteggio non esprime: se "
        "nessun Colpo e' andato a segno sui convogli e il tedesco ha vinto per "
        "5 VP o meno, e' una vittoria davvero molto marginale.",
    ],
}

# --------------------------------------------------------------------------
# Op8 Cat and Mouse
# --------------------------------------------------------------------------
TABLES["Op8 Cat and Mouse"] = {
    "port_control": dict(GERMAN_WEST, **{"South America": "NONE"}),
    "_source": SOURCE % "pp.31-32",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato a Murmansk",
               dispersed=False, destinations=["Murmansk"]),
        convoy(RN, 2, "Convoglio disperso che ha Completato a Murmansk",
               dispersed=True, destinations=["Murmansk"]),
        convoy(RN, 2, "Convoglio che ha Completato in un altro porto",
               dispersed=False, other_than=["Murmansk"]),
        convoy(RN, 1, "Convoglio disperso che ha Completato in un altro porto",
               dispersed=True, other_than=["Murmansk"]),
        *dmg_sunk(RN, 3, 7, {"names": ["Tirpitz"]}, "Tirpitz", hit=1),
        *dmg_sunk(RN, 0, 3, GE_BC, "incrociatore da battaglia tedesco"),
        *dmg_sunk(RN, 0, 1, GE_CRUISERS_PB, "incrociatore o corazzata tascabile tedesca"),

        award(KM, "SHIP_SUNK", 2, "BB, BC o CV britannica affondata",
              BRIT_CAPITAL),
        award(KM, "SHIP_SUNK", 0.5, "incrociatore britannico affondato",
              BRIT_CRUISER),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),
    ],
    "tiebreak": {
        "side": KM, "auto": False,
        "condition": ("In caso di parita' vince il tedesco se il Tirpitz e' in "
                      "un porto (ha Completato), quel porto NON e' Kiel ne' "
                      "Wilhelmshaven, E almeno un Colpo e' andato a segno su "
                      "un Convoglio. Altrimenti vince il britannico."),
    },
    "notes": [
        "Unico scenario in cui un semplice COLPO su una nave da' punti: 1 al "
        "britannico per ogni Colpo sul Tirpitz, prima ancora di danneggiarlo. "
        "Le altre navi tedesche hanno 0 in quella colonna.",
        "La clausola di parita' e' la piu' severa delle nove: al tedesco non "
        "basta portare a casa il Tirpitz in un porto avanzato, deve anche aver "
        "colpito almeno una volta un convoglio. Sopravvivere non basta.",
    ],
}

# --------------------------------------------------------------------------
# Op9 Arctic Calamity
# --------------------------------------------------------------------------
TABLES["Op9 Actic Calamity"] = {
    "port_control": dict(GERMAN_WEST, **{"Murmansk": "NONE",
                                        "South America": "NONE"}),
    "_source": SOURCE % "pp.35-36",
    "awards": [
        convoy(RN, 3, "Convoglio che ha Completato ad Archangel",
               dispersed=False, destinations=["Archangel"]),
        convoy(RN, 2, "Convoglio disperso che ha Completato ad Archangel",
               dispersed=True, destinations=["Archangel"]),
        convoy(RN, 2, "Convoglio che ha Completato in un altro porto",
               dispersed=False, other_than=["Archangel"]),
        convoy(RN, 1, "Convoglio disperso che ha Completato in un altro porto",
               dispersed=True, other_than=["Archangel"]),
        *dmg_sunk(RN, 3, 7, {"names": ["Tirpitz"]}, "Tirpitz"),
        *dmg_sunk(RN, 1, 3, {"types": ["CA", "PB"], "nations": ["GE"]},
                  "incrociatore pesante o corazzata tascabile tedesca"),
        *dmg_sunk(RN, 0, 1, {"types": ["CL"], "nations": ["GE"]},
                  "incrociatore leggero tedesco"),

        award(KM, "SHIP_SUNK", 1, "BB, BC o CV britannica affondata",
              BRIT_CAPITAL),
        award(KM, "SHIP_SUNK", 0.5, "incrociatore britannico affondato",
              BRIT_CRUISER),
        award(KM, "HIT_ON_CONVOY", 1, "ogni Colpo su un Convoglio"),
    ],
    "tiebreak": {
        "side": RN, "auto": True,
        "condition": "In caso di parita' vince il britannico.",
    },
    "notes": [
        "Murmansk e' chiuso in questo scenario: nessuna TF puo' eseguire un "
        "Completamento li'. Il porto artico che paga 3 punti e' Archangel.",
        "Il Tirpitz e' l'unica nave tedesca che vale davvero: 3 danneggiata, 7 "
        "affondata, contro 1/3 di un incrociatore pesante.",
    ],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    written = 0
    for name in sorted(TABLES):
        d = dict(TABLES[name])
        doc = {"_scenario": name, "_source": d.pop("_source"),
               "mode": d.pop("mode", "VP")}
        if name in REINFORCEMENT_PORTS:
            doc["reinforcement_ports"] = REINFORCEMENT_PORTS[name]
        doc.update(d)
        path = os.path.join(OUT, name + ".json")
        json.dump(doc, open(path, "w"), indent=1, ensure_ascii=False)
        n = len(doc.get("awards", []))
        manual = sum(1 for a in doc.get("awards", []) if a.get("manual"))
        print("  %-24s %-11s %2d premi%s"
              % (name, doc["mode"], n,
                 ("  (%d da spuntare a mano)" % manual) if manual else ""))
        written += 1
    print("%d tabelle -> core/data/victory/" % written)


if __name__ == "__main__":
    main()
