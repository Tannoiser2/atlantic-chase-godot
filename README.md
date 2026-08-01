# Atlantic Chase — versione digitale (Godot 4.7)

Implementazione digitale di *Atlantic Chase* (GMT Games, 2020), a partire dal
modulo VASSAL v2.1 e dai regolamenti in italiano.

---

## ⚠️ Attribuzione e limiti d'uso — leggere prima di tutto

**Atlantic Chase è un gioco di GMT Games LLC. Design: Jeremy White.
Copyright © 2020 GMT Games LLC. Tutti i diritti riservati.**

Questo repository non è affiliato a GMT Games, non è autorizzato da GMT Games,
e **non sostituisce l'acquisto del gioco**. È un progetto amatoriale e senza
scopo di lucro, nato come strumento personale per giocare a una copia del gioco
posseduta.

Cosa **non** è contenuto qui:

- nessuna immagine della mappa, delle pedine o delle tavole (© GMT Games) —
  vanno rigenerate in locale dal proprio modulo VASSAL, vedi sotto;
- nessun regolamento, né in inglese né la traduzione italiana di G. Sorio, che
  riporta *"PER SOLO USO PERSONALE – vietata la vendita"*.

Cosa **è** contenuto qui: codice sorgente, e i valori delle tabelle di gioco
trascritti perché il codice possa funzionare. Quei valori restano proprietà
intellettuale di GMT Games e sono riprodotti a fini di interoperabilità con una
copia legittima del gioco.

**Se GMT Games chiede la rimozione di questo repository o di parte del suo
contenuto, va rimosso senza discutere.** Per giocare ad Atlantic Chase,
comprate il gioco: <https://www.gmtgames.com>

---

> **Uso strettamente personale.** Questo progetto è uno strumento privato, come
> un modulo VASSAL personale, e non è pensato per la distribuzione come
> prodotto. Il repository **non contiene alcun asset grafico**: si rigenerano
> in locale dal proprio modulo (vedi sotto).

---

## Avvio rapido

```bash
godot --path . --import          # una volta, per costruire la cache
godot --path .                   # avvia
```

Premi **F1** in gioco per l'elenco dei comandi.

### Rigenerare gli asset (obbligatorio al primo avvio)

Gli asset non sono versionati. Servono la cartella `images/` del modulo VASSAL
e i file `.vsav`, che devono trovarsi nella directory **superiore** a questa.

```bash
python3 -m venv tools/.venv && tools/.venv/bin/pip install numpy scipy pillow pymupdf
tools/.venv/bin/python tools/prepare_assets.py     # taglia la mappa in tile, copia le pedine
tools/.venv/bin/python tools/vsav_extract.py       # decodifica i 22 salvataggi
tools/.venv/bin/python tools/import_scenarios.py   # li converte in scenari
```

### Test

```bash
godot --headless --path . --script res://tests/run_tests.gd
```

442 verifiche su 5 suite. Esce con codice 1 al primo fallimento, quindi è
usabile direttamente in CI.

---

## Come è fatto

Il principio è uno solo: **il motore di gioco non sa che Godot esiste**. Tutto
ciò che sta in `core/` è GDScript puro (`RefCounted`, nessun `Node`), quindi
gira headless, si testa in millisecondi e potrà essere riusato per un bot o per
un server senza toccarlo.

```
core/           logica pura, zero dipendenze da Node
  map/          coordinate esagonali, grafo della mappa
  state/        Traiettoria, Task Force, GameState serializzabile
  rules/        Scorrere del Tempo, Totale Traiettoria, Interruzione,
                motore delle Azioni, Risultati Comuni
  engine/       RNG con seme, registro comandi con undo/redo
  data/         map_graph.json, tables.json, actions.json, scenarios/
ui/             rendering e input (Godot)
tools/          pipeline Python: calibrazione, estrazione, import
tests/          runner headless senza dipendenze esterne
reports/        diagnostica generata (non versionata)
```

### Il reticolo esagonale

Il modulo VASSAL **non contiene la griglia**: nel `buildFile.xml` non c'è
nessuna `HexGrid`, solo 81 `Zone` per box porto e tracce. In VASSAL le pedine si
trascinano a occhio. Il reticolo è stato quindi ricostruito dall'immagine della
mappa:

| parametro | valore |
|---|---|
| passo centro-centro | 213.50 px |
| rotazione | 44.28° |
| origine | (1745.00, 1692.00) |
| circumraggio / apotema | 123.27 / 106.75 px |
| esagoni giocabili | 171 |

Il reticolo è **ruotato**: GMT ha inclinato la griglia per adattarla alla
geografia dell'Atlantico, quindi le formule standard pointy-top / flat-top non
si applicano e `Hex` usa direttamente i due vettori di base misurati.

**Validazione indipendente:** i 22 salvataggi ufficiali contengono 238 pedine
Traiettoria e Stazione piazzate a mano. Agganciandole al reticolo, **il 100%
cade nell'esagono corretto** (residuo mediano 33 px per le traiettorie e 15 px
per le stazioni, contro un apotema di 106.75). È una verifica che non dipende
da come il reticolo è stato ricavato.

### Le tabelle

Tutte le tabelle sono state lette **dall'immagine della mappa a risoluzione
nativa**, non dall'estrazione testuale dei PDF, che perde le celle e sposta le
righe (verificato: la tabella dell'Interruzione estratta dal PDF ha bande di
righe sbagliate). I simboli dei Risultati Comuni sono stati identificati
renderizzando il regolamento a 150 dpi e guardandoli, non deducendoli:

| icona | risultato |
|---|---|
| occhio con pupilla bianca | Contatto |
| occhio con pupilla rossa | Schermaglia |
| cilindro dorato | Avvistato |
| tessera "Clos" | Ridurre le Distanze |
| barre rosso-bianco-rosso | In Anticipo o In Ritardo |
| barre tutte rosse | Seguire |

Ogni azione in `actions.json` ha un campo `verified`. **Il motore rifiuta di
risolvere un'azione non verificata** invece di inventarsi un risultato: meglio
un errore esplicito che una regola sbagliata applicata in silenzio.

---

## Stato

Vedi `STATO.md` per il dettaglio di cosa è completo, parziale o assente.
