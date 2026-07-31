# Stato del lavoro — sessione notturna

Riferimento: `PIANO_GODOT.md` nella cartella superiore.
Tutti i test passano: **442 verifiche, 5 suite, headless.**

---

## Riepilogo per milestone

| Milestone | Stato | Note |
|---|---|---|
| **M0** Fondamenta | ✅ **completo** | Progetto Godot 4.7, mappa in 15 tile, camera, pipeline asset, runner di test |
| **M1a** Calibrazione reticolo | ✅ **completo** | Validato al 100% contro le pedine ufficiali |
| **M1b** Estrazione dati | ✅ **completo** | 22 `.vsav` decodificati, 70 zone, terreno classificato |
| **M1c** Grafo + editor | 🟡 **quasi completo** | Grafo generato e funzionante; editor operativo; mancano i lati "not adjacent" e i porti |
| **M2** Core regole | ✅ **completo** | Traiettoria, Tempo, Totale, Interruzione, undo, RNG — tutto testato |
| **M3** Mappa interattiva | ✅ **completo** | Selezione, costruzione traiettoria, anteprima, undo, HUD, log |
| **M4** Motore azioni | 🟡 **parziale** | Pipeline completa; 1 tabella su 4 verificata, 1 parziale, 2 da trascrivere |
| **M5** Battaglia | ❌ **non iniziato** | Regole studiate e documentate, nessun codice |
| **M6** Scenari | 🟡 **parziale** | 22 scenari importati e caricabili; mancano obiettivi, navi, condizioni di vittoria |

---

## Cosa puoi provare subito

```bash
cd atlantic_chase && godot --path .
```

**F1** apre l'elenco dei comandi. Cose che funzionano davvero:

- La mappa si naviga (trascinamento col tasto centrale, WASD, rotella con zoom
  verso il cursore).
- `[` e `]` cambiano scenario fra i 22 importati dal modulo VASSAL. Le
  traiettorie e le stazioni sono quelle vere dei setup ufficiali.
- **Tab** cicla fra le Task Force, **clic sinistro** su un esagono adiacente a un
  capo estende la Traiettoria, **clic destro** rimuove un segmento. Le mosse
  illegali vengono rifiutate *con il motivo scritto* nel log.
- Il pannello mostra il **Totale Traiettoria** sempre aggiornato: è la
  contabilità che nel gioco fisico si sbaglia di continuo.
- **T** applica lo Scorrere del Tempo con la velocità della TF e il meteo
  correnti; **Ctrl+W** cambia il meteo.
- **1** dichiara un'azione Ingaggiare completa: Totale Traiettoria → verifica di
  Interruzione → tiro 2d6 → lettura tabella → applicazione del risultato, con
  tutti i passaggi scritti nel log.
- **Ctrl+Z / Ctrl+Shift+Z** annullano e ripristinano qualunque mossa.
- **E** entra nell'editor del grafo, **Ctrl+S** salva.

---

## Il risultato tecnico più importante

Il modulo VASSAL **non contiene la griglia esagonale** — verificato: nessuna
`HexGrid` nel `buildFile.xml`, solo 81 `Zone` per box e tracce. Era il rischio
numero uno del piano. È risolto:

| parametro | valore |
|---|---|
| passo centro-centro | 213.50 px |
| rotazione | 44.28° |
| origine | (1745.00, 1692.00) |
| esagoni giocabili | 171 |

Il reticolo è **ruotato di ~44°**: GMT ha inclinato la griglia per adattarla
alla geografia, quindi le formule standard non si applicano.

**Come è stato validato** — e questo è il punto che conta: i 22 salvataggi
ufficiali contengono 238 pedine Traiettoria e Stazione piazzate a mano da chi ha
costruito il modulo. Agganciandole al reticolo calcolato, **il 100% cade
nell'esagono giusto** (residuo mediano 33 px per le traiettorie, 15 px per le
stazioni, contro un apotema di 106.75 px). È una verifica del tutto indipendente
dal metodo con cui il reticolo è stato ricavato.

---

## Decisioni prese in autonomia

1. **Undo per istantanee, non per comandi invertibili.** Uno stato serializzato
   pesa pochi KB, quindi il costo è irrilevante e sparisce l'intera classe di
   bug da undo scritto male.

2. **Traiettorie disegnate a codice, non con le pedine `Trajectory_*.png`.**
   Restano nitide a ogni zoom, non c'è nulla da ruotare o allineare, e si può
   evidenziare la traiettoria selezionata.

3. **Tabelle lette dall'immagine della mappa, non dai PDF.** L'estrazione
   testuale perde le celle: la tabella dell'Interruzione estratta dal PDF ha
   bande di righe sbagliate (`5-6, 7, 8-9` invece di `5-7, 8, 9`). Ho usato la
   mappa a risoluzione nativa come fonte autorevole.

4. **I simboli sono stati guardati, non dedotti.** Ho renderizzato il
   regolamento a 150 dpi per identificare le icone: occhio bianco = Contatto,
   occhio rosso = Schermaglia, cilindro = Avvistato. La deduzione "per logica"
   mi stava portando all'accoppiamento sbagliato.

5. **Il motore rifiuta le azioni non verificate** invece di indovinare. Premendo
   **3** (Attacco Aereo) ottieni un errore esplicito, non un risultato inventato.

6. **Asset esclusi dal repository.** Mappa e pedine sono © GMT. Il `.gitignore`
   li esclude e il README spiega come rigenerarli da `tools/prepare_assets.py`.
   Se domani pubblichi su GitHub, questo evita di distribuire materiale GMT.
   *Il repository è inizializzato con un commit locale; non ho fatto push.*

7. **Ordinamento dei segmenti per cammino hamiltoniano.** I `.vsav` non dicono
   in che ordine stanno i segmenti di una traiettoria. Il primo algoritmo
   (cercare i capi di grado 1) falliva su 4 scenari, perché tre esagoni
   consecutivi in curva sono mutuamente adiacenti e formano un triangolo. Ora
   cerca il cammino che copre tutti i segmenti preferendo il più diritto: 22
   scenari su 22 senza avvisi.

---

## Cosa manca, in ordine di importanza

### 1. Le tabelle azione mancanti — *blocca M4*
`Attacco Aereo` e `Attacco Furtivo` non sono trascritte; della `Ricerca Navale`
è certa solo la colonna 0-4. Il problema sono i simboli a barre
(In Anticipo/In Ritardo contro Seguire), che a 120 dpi non sempre si contano con
sicurezza. **Serve la mappa fisica o una scansione migliore.** Le celle dubbie
sono elencate una per una in `actions.json → NAVAL_SEARCH.unverified_cells`, e
il motore le segnala quando le usa.

### 2. I lati "not adjacent" — *correttezza del grafo*
La mappa stampa frecce "not adjacent" che negano il passaggio attraverso la
terraferma (Firth of Forth, Irlanda, Galles, Bristol Channel, e altre). Senza di
esse una Task Force può attraversare la Gran Bretagna. `blocked_edges` è
**vuoto**. L'editor c'è ed è pronto: premi **E**, clic destro su un esagono,
Shift+clic sul vicino, **Ctrl+S**. Stimo 20-30 minuti guardando la mappa.

### 3. I porti — *blocca M6*
I 20 box porto sono estratti con i loro poligoni esatti dal modulo, ma manca il
collegamento box → esagono di sbocco. Senza, le regole "un segmento non può
stare in una Casella Porto" e il Completamento non sono verificabili.

### 4. Le navi
`ships.json` non esiste. Le statistiche (velocità, cannoni, colpi) sono stampate
sulle pedine e non sono estraibili in modo affidabile via OCR. Vanno trascritte
a mano dal fascicolo Scenari, oppure lette dai libretti. Per ora ogni TF ha
velocità "media" di default.

### 5. M5 Battaglia
Nessun codice. Le regole però sono già studiate e annotate in `actions.json`:
5 zone (Lontano/Vicino/Close/Vicino/Lontano), 3 round con meteo buono e 2 con
avverso, 1 round per la Battaglia Limitata, e le regole di piazzamento per
Battaglia e Sorpresa.

---

## Una nota sull'ambito

Ieri sera avevi chiesto M1–M3, poi M4–M6. M1–M3 sono sostanzialmente fatti e
testati. M4 ha l'impalcatura completa ma è alimentato da dati incompleti, e il
collo di bottiglia non è il codice: è la **leggibilità delle tabelle stampate**.
Con una scansione decente della mappa, o con la mappa fisica davanti, si
completa in un paio d'ore. M5 e M6 restano lavoro vero, nell'ordine di grandezza
già indicato dal piano.

Preferisco dirtelo così, piuttosto che consegnarti quattro tabelle indovinate
che sembrano funzionare e falsano ogni partita.
