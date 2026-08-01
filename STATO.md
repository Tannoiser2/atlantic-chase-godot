# Stato del lavoro

Riferimento: `PIANO_GODOT.md` nella cartella superiore.
Tutti i test passano: **556 verifiche, 5 suite, headless.**

---

## Riepilogo per milestone

| Milestone | Stato | Note |
|---|---|---|
| **M0** Fondamenta | ✅ **completo** | Progetto Godot 4.7, mappa in 15 tile, camera, pipeline asset, runner di test |
| **M1a** Calibrazione reticolo | ✅ **completo** | Validato al 100% contro le pedine ufficiali |
| **M1b** Estrazione dati | ✅ **completo** | 22 `.vsav` decodificati, 70 zone, terreno classificato |
| **M1c** Grafo + editor | ✅ **completo** | 156 esagoni, 9 lati "not adjacent", Canale di Kiel; editor operativo |
| **M2** Core regole | ✅ **completo** | Traiettoria, Tempo, Totale, Interruzione, undo, RNG — tutto testato |
| **M3** Mappa interattiva | ✅ **completo** | Selezione, costruzione traiettoria, anteprima, undo, HUD, log |
| **M4** Motore azioni | ✅ **completo** | Tutte e 4 le tabelle trascritte e verificate; danno alle navi |
| **M5** Battaglia | ❌ **non iniziato** | Regole studiate e documentate, nessun codice |
| **M6** Scenari | 🟡 **parziale** | 22 scenari importati e caricabili; mancano obiettivi, navi, condizioni di vittoria |

### Cosa è cambiato nell'ultima sessione

- **M4 chiuso.** Le quattro tabelle azione (Ingaggiare, Ricerca Navale, Attacco
  Aereo, Attacco Furtivo) sono state lette dalla mappa a ingrandimento 5–6× e
  trascritte per intero: 128 celle. Le 21 celle della Ricerca Navale che avevo
  lasciato dubbie sono confermate — a quell'ingrandimento la barra centrale
  bianca di *In Anticipo o In Ritardo* si distingue nettamente dalle tre barre
  rosse di *Seguire*.
- **Modello nave** (`core/state/ship.gd`): *Danneggiato* gira la pedina e
  affonda alla seconda volta, i Colpi restano, Convogli e Squadroni DD non si
  danneggiano (un Danno = 2 Colpi) e sono distrutti a 4 Colpi.
- **9 frecce "not adjacent"** trascritte (Isole Britanniche, Irlanda, Bretagna,
  Islanda) più il **Canale di Kiel** riservato alla Kriegsmarine. Ora una Task
  Force non può più attraversare la Gran Bretagna.
- **Area giocabile corretta**: rimossi 15 esagoni oltre la cornice stampata,
  incluso il caso che il criterio automatico sbagliava (a est di Kiel, sul
  pannello della Battaglia). Da 171 a **156 esagoni**.
- **7 porti** collegati al loro esagono, con i nomi delle Caselle verificati
  contro le Zone del modulo VASSAL.

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

### 1. I porti rimanenti — *blocca M6*
7 porti su ~20 sono collegati al loro esagono. Mancano Kiel, Brest,
St Nazaire/Bordeaux, Bergen, Narvik, Hvalfjordur, St John's, Halifax, New York,
Gibilterra, Murmansk, Archangel, Africa, South America.

Il metodo è già pronto e richiede solo di ripeterlo per regione:

```bash
tools/.venv/bin/python tools/label_hexes.py <x0> <y0> <x1> <y1> out.png 2.4
```

produce un ritaglio della mappa con le coordinate `q,r` stampate sui centri;
si legge in quale esagono cade il pallino del porto e si aggiunge la voce a
`core/data/map_annotations.json`, poi `tools/apply_annotations.py` valida e
applica. Attenzione ai pallini vicini a un lato: va guardato da che parte del
confine cadono, non solo la distanza dal centro (è il caso di Methil).

### 2. Le navi
Il modello `Ship` esiste e le regole di danno sono implementate e testate, ma
non c'è un `ships.json`: le statistiche (velocità, cannoni) sono stampate sulle
pedine e non sono estraibili in modo affidabile via OCR. Vanno trascritte a mano
dai fascicoli Scenari. Finché mancano, ogni TF ha velocità "media" di default e
i risultati di Colpo dicono esplicitamente "la TF non ha ancora un elenco navi"
invece di fingere un effetto.

### 3. M5 Battaglia
Nessun codice. Le regole però sono già studiate e annotate in `actions.json`:
5 zone (Lontano/Vicino/Close/Vicino/Lontano), 3 round con meteo buono e 2 con
avverso, 1 round per la Battaglia Limitata, e le regole di piazzamento per
Battaglia e Sorpresa.

---

## Una nota sull'ambito

M0–M4 sono chiusi e testati. Il timore della sessione precedente — che le
tabelle stampate non fossero leggibili a 120 dpi — si è rivelato infondato:
bastava ingrandire di 5–6× e ritagliare cella per cella invece di leggere la
tabella intera. Nessuna cella è stata indovinata.

Restano M5 (Battaglia) e il completamento di M6, che sono lavoro vero
nell'ordine di grandezza già indicato dal piano, più le due liste di dati da
trascrivere a mano (porti rimanenti, statistiche delle navi).
