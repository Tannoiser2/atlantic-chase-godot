# Stato del lavoro

Riferimento: `PIANO_GODOT.md` nella cartella superiore.
Tutti i test passano: **1113 verifiche, 9 suite, headless.**

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
| **M6** Scenari | ✅ **completo** | 22 scenari con navi, comandanti, rinforzi e briefing |
| **M7** Vittoria | 🟡 **quasi completo** | Le 9 Operazioni hanno la tabella eseguibile e i punti arrivano al segnapunti; mancano i 12 mini-scenari e i 15 solitari |

### Cosa è cambiato nell'ultima sessione

- **I dodici mini-scenari non erano vuoti: erano Battaglie.** Sembravano tutti
  *"0 TF, 0 navi"*, e la spiegazione comoda era che il modulo VASSAL non li
  avesse schierati. Falso: le navi ci sono, ma piazzate **dentro il pannello
  della Mappa di Battaglia** stampato sulla mappa. Non sono partite sulla mappa
  operazionale, sono battaglie già schierate — non hanno Traiettorie né
  Stazioni perché non ne hanno bisogno, e l'importatore cercava rotte che non
  esistono. Le coppie che ne escono sono quelle storiche: Graf Spee contro
  Achilles, Ajax ed Exeter; Bismarck e Prinz Eugen contro Hood e Prince of
  Wales; Scharnhorst contro Duke of York.
- **Tutte e nove le azioni nella barra.** Se ne vedevano quattro: le altre
  cinque non erano nascoste di proposito, non erano state messe. Ora ci sono
  tutte, e quelle non ancora dichiarabili restano **visibili e disabilitate**
  con il motivo nel tooltip. *Completamento* e *Passare* funzionano;
  *Riorganizza* e *Segnali* aspettano che le loro regole siano trascritte.
- **Il tracciatore dei VP è collegato all'interfaccia**: fino a ieri i punti si
  segnavano solo nei test.
- **App nativa per macOS** (`tools/build_macos.sh`), universale e firmata, con
  la quarantena tolta automaticamente.
- **Illustrazioni generate in locale** con ComfyUI/SDXL: una miniatura per
  scenario nel briefing, un'icona per azione sui pulsanti. Seme fisso per
  nome, così rigenerare non ridisegna quello che non è cambiato.

### Cosa era cambiato nella sessione precedente

- **Tutte e nove le tabelle di Vittoria delle Operazioni**, trascritte
  dall'edizione **inglese** del fascicolo per 2 giocatori. L'italiana perde le
  intestazioni di colonna della tabella tedesca della Rheinübung, e senza
  *Francia / Norvegia / Germania* quei numeri non vogliono dire niente.
- **Tre modelli di vittoria, non uno.** Leggendo tutti e tre i fascicoli:
  *VP* (otto Operazioni), *CONDITIONS* (Op1 Homecoming non ha nessuna tabella
  VP, è un elenco di condizioni) e *DEBRIEFING* (il solitario non si vince: si
  conta un punteggio solo e si legge una tabella di Esiti a soglie). Il motore
  li tiene distinti invece di forzarli in uno.
- **I VP ora sono in virgola mobile.** Cinque tabelle su nove pagano **mezzo
  punto** per un incrociatore britannico affondato: arrotondare cambiava il
  vincitore. Si stampano `3½`.
- **Punti negativi, Colpi e premi una tantum.** In Op3 il britannico *perde* 1
  punto se non ha minato Narvik o Trondheim; in Op8 un semplice Colpo sul
  Tirpitz vale 1 punto; *"il primo Completamento tedesco riuscito a Bergen"*
  paga una volta sola, e il fatto che sia scattato sta nello stato salvato.
- **L'azione Completamento** (RB p.29) era dichiarabile ma non faceva niente.
  Ora applica la regola: una sola TF, non più di 6 segmenti, almeno un segmento
  in un esagono di porto **amico**, vietata con un segnalino Informazioni.
- **Chi controlla i porti** è un dato di scenario: dalla quarta Operazione in
  poi i porti francesi e norvegesi sono tedeschi, e singoli scenari chiudono
  singoli porti (Murmansk in Op9, South America in Op6 e Op8).
- **Dieci righe restano da spuntare a mano** — mine posate, marcatore Base
  Aerea, *"la TF dell'Hipper ha eseguito un'azione Traiettoria"*, zona di
  sicurezza USA. Il motore non le assegna da solo: le elenca. E un premio che
  non scatta perché **manca un dato** viene distinto da uno che non scatta
  perché la nave non corrisponde, e scritto nel registro.
- **Corretto il Bremen nel ruolino.** Il nome è stampato in corsivo, l'OCR non
  l'aveva letto e il parser aveva preso `bremen` e `bremenb` per codici di
  *tipo*: due navi anonime invece di una a due facce. Op1 è tutta costruita su
  quella nave e senza nome nessuna regola poteva nominarla. Da 86 navi a 85.
- **Un bug preso dai test**: leggevo il proprietario di una nave *dopo* averle
  applicato i Colpi, ma una nave affondata non figura più fra quelle a galla
  della sua Task Force — così il Bismarck affondato veniva contato come nave
  britannica, con 3 punti al giocatore sbagliato.

### Cosa era cambiato nella sessione precedente

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

### 1. Le tabelle di Vittoria che mancano

Le **9 Operazioni** sono fatte. Restano:

- i **12 mini-scenari** (`MS1`–`MS12`), le cui tabelle stanno nel fascicolo per
  2 giocatori dopo le Operazioni;
- i **15 scenari in solitario** (`BL1`–`BL3`, `N1`–`N6`, `B1`–`B4`, `A1`–`A2`).
  Di `BL1` la tabella degli Esiti è già trascritta e verificata, come modello.

Il formato è pronto e testato: si aggiungono file in `core/data/victory/`, o si
estende `tools/write_victory.py`.

### 2. Il modo solitario vero e proprio

Gli scenari in solitario **non stanno nel modulo VASSAL**: non c'è nessun
`.vsav` da cui ricavare lo schieramento, va trascritto a mano dalle mappe del
fascicolo. E ognuno usa sistemi che il motore non ha: marcatori *Rendezvous* e
Tabella del Rifornimento, **Tabella delle Azioni** dell'avversario immaginario,
Tabella per Identificare la TF nemica, TF *non identificate*. È il cuore del
modo solitario ed è una milestone a sé, non una trascrizione.

### 3. Le dieci righe da spuntare a mano

Il motore le elenca ma nessuna schermata le mostra ancora: serve un pannello di
fine partita che le presenti come una lista da spuntare, e sommi il risultato.

### 4. Export per iPad

I gesti touch ci sono (pinch, due dita, tocco prolungato) ma non sono mai stati
provati su un dispositivo vero: mancano i template di export di Godot 4.7
(~1 GB da scaricare) e una prova sul campo.

---

## Una nota sull'ambito

**M0–M5 sono chiusi e testati.** Rispetto al piano iniziale è un mese e mezzo
di lavoro stimato, con oltre mille verifiche automatiche a copertura.

Quello che resta non è più ricerca ma trascrizione e interfaccia: le statistiche
delle navi, gli obiettivi degli scenari, la vista della Mappa di Battaglia, i
controlli touch. Le due paure iniziali — che il modulo VASSAL non contenesse la
griglia, e che le tabelle stampate fossero illeggibili a 120 dpi — si sono
rivelate entrambe superabili, la prima ricostruendo il reticolo e validandolo
contro le pedine ufficiali, la seconda ingrandendo cella per cella.

Nessuna tabella è stata indovinata. Dove un dato manca, il codice lo dichiara.
