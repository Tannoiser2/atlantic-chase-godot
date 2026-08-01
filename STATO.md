# Stato del lavoro

Riferimento: `PIANO_GODOT.md` nella cartella superiore.
Tutti i test passano: **873 verifiche, 8 suite, headless.**

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
| **M5** Battaglia | ✅ **completo** | motore + vista: 5 zone, cannoni, siluri, manovra, fumo, fuga, uscita |
| **M6** Scenari | 🟡 **quasi completo** | 22 scenari con navi, comandanti, rinforzi e briefing; le condizioni di vittoria sono testo, non regole |

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
- **22 porti** collegati al loro esagono, con i nomi delle Caselle verificati
  contro le Zone del modulo VASSAL.
- **Ruolino navi completo**: 86 navi con cannoni, Difesa e velocità per
  entrambi i lati della pedina, estratte via OCR e **verificate tutte a occhio**
  una per una.
- **Vista della Battaglia**: sei bande, pedine vere, fasi guidate. Un risultato
  BATTAGLIA da un'azione la apre davvero; il tasto **0** ne apre una di prova.
- **Interfaccia rifatta**: schermata iniziale con copertina e scelta dello
  scenario (con briefing prima di cominciare), barra dei comandi con pulsanti
  che si disabilitano da soli spiegando il perché nel tooltip, e
  **drag-and-drop**: si trascina per disegnare una rotta in un gesto solo, e si
  trascinano le navi fra le zone in Battaglia.
- **Le scelte tornano al giocatore**: designazioni delle azioni (Bersaglio,
  Coordinatrice, Supporto Aereo), opzione di rimozione dello Scorrere del Tempo,
  quale nave subisce il Colpo, dove porre la Stazione. Il core le chiede con una
  `Callable`, quindi non conosce l'interfaccia e i test restano automatici.
- **Touch**: due dita per spostare e zoomare, tocco prolungato al posto del
  clic destro.
- **Corretta una freccia che avevo attribuito al lato sbagliato.** L'esagono
  16,-2 (St. Nazaire e Bordeaux) era stato scartato come "terra piena"; non
  essendo nel grafo, lo strumento di etichettatura non ne mostrava i lati e la
  freccia della Bretagna era finita sul lato etichettato più vicino. Ora
  `label_hexes.py --all` etichetta tutto il reticolo, e la freccia è sul lato
  giusto: `16,-3 | 16,-2`, che impedisce di tagliare la Bretagna obbligando a
  girare al largo di Brest.

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
| esagoni giocabili | 157 |

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

5. **Il motore rifiuta le azioni non verificate** invece di indovinare. Ogni
   azione in `actions.json` ha un campo `verified`; le quattro tabelle d'azione
   ora lo hanno a `true`, ma Segnalazione e Riorganizzazione no, e premendo il
   loro tasto si ottiene un errore esplicito invece di un risultato inventato.

6. **Annotazioni manuali separate dai dati generati.** Il grafo si rigenera con
   `tools/rebuild_all.sh`; i lati "not adjacent", il Canale di Kiel e i porti
   stanno in `core/data/map_annotations.json` e vengono riapplicati e validati
   in coda. Sono coperti da test proprio perché una rigenerazione non li possa
   perdere in silenzio.

7. **Esclusione manuale di due esagoni oltre la cornice.** Ho provato tre
   criteri automatici (presenza delle linee, connessione del mare, riempimento
   dall'esterno della cornice): nessuno separa correttamente il pannello della
   Battaglia dall'oceano, perché la cornice stampata non è una curva chiusa
   ovunque e il riempimento tracima. Due esagoni verificati a occhio ed esclusi
   esplicitamente valgono più di un'euristica che sbaglia in silenzio.

8. **Asset esclusi dal repository.** Mappa e pedine sono © GMT. Il `.gitignore`
   li esclude e il README spiega come rigenerarli da `tools/prepare_assets.py`.
   Se domani pubblichi su GitHub, questo evita di distribuire materiale GMT.
   *Il repository è inizializzato con un commit locale; non ho fatto push.*

9. **Ordinamento dei segmenti per cammino hamiltoniano.** I `.vsav` non dicono
   in che ordine stanno i segmenti di una traiettoria. Il primo algoritmo
   (cercare i capi di grado 1) falliva su 4 scenari, perché tre esagoni
   consecutivi in curva sono mutuamente adiacenti e formano un triangolo. Ora
   cerca il cammino che copre tutti i segmenti preferendo il più diritto: 22
   scenari su 22 senza avvisi.

---

## Cosa manca, in ordine di importanza

### 1. Condizioni di vittoria eseguibili

Gli scenari hanno ora navi, comandanti, rinforzi, iniziativa, meteo e il testo
completo di fine partita e vittoria, e i Punti Vittoria si contano.

Quello che manca è renderle **automatiche**. In Atlantic Chase sono discorsive e
piene di eccezioni per scenario — *"il tedesco vince se il Bismarck è in un porto
francese; altrimenti vince il britannico"* — quindi ogni scenario è quasi un
caso a sé. Oggi il testo è mostrato nel briefing (tasto **B**) e i giocatori lo
applicano; automatizzarlo è un lavoro scenario per scenario.

### 2. Export per iPad

I gesti touch ci sono (pinch, due dita, tocco prolungato) ma non sono mai stati
provati su un dispositivo vero: mancano i template di export di Godot 4.7
(~1 GB da scaricare) e una prova sul campo.

---

## Una nota sull'ambito

**M0–M5 sono chiusi e testati.** Rispetto al piano iniziale è un mese e mezzo
di lavoro stimato, con 726 verifiche automatiche a copertura.

Quello che resta non è più ricerca ma trascrizione e interfaccia: le statistiche
delle navi, gli obiettivi degli scenari, la vista della Mappa di Battaglia, i
controlli touch. Le due paure iniziali — che il modulo VASSAL non contenesse la
griglia, e che le tabelle stampate fossero illeggibili a 120 dpi — si sono
rivelate entrambe superabili, la prima ricostruendo il reticolo e validandolo
contro le pedine ufficiali, la seconda ingrandendo cella per cella.

Nessuna tabella è stata indovinata. Dove un dato manca, il codice lo dichiara.
