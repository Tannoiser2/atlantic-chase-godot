# TODO della revisione

Baseline: **3676 verifiche su 21 suite**, tutte verdi. Replay solitario:
**quindici `OK`** su quindici scenari, nessuno saltato. `audit_solo.gd`:
**93 caselle azione, zero procedure segnaposto, ZERO buchi dichiarati, zero
blocchi.**

Questo e' il backlog autorevole. `STATO.md` contiene anche una lunga cronologia:
utile per capire le decisioni, ma le sue vecchie sezioni "Cosa manca" non devono
riaprire lavori gia' chiusi.

## Come leggere lo stato

- 🟢 **fatto**: implementato, con la fonte citata e i test che lo difendono.
  Non va rifatto.
- 🟡 **da rifinire**: funziona e regge la baseline, ma e' incompleto in un modo
  DICHIARATO - nel dato, nel log o in un commento. Si puo' giocare sopra.
- 🔴 **mancante**: non c'e'. Dove serve, il codice lo dichiara invece di
  arrangiarsi.

La regola che tiene insieme tutto: **un dato assente resta un buco dichiarato**.
Un 🟡 o un 🔴 non nascosto vale piu' di un 🟢 finto.

## Quadro d'insieme

| Area | Stato | In una riga |
|---|---|---|
| Reticolo e grafo Mappa Operazionale | 🟢 | 129 esagoni, validati su 238 pedine VASSAL |
| Reticolo e grafo mappe inserto | 🟢 | misurati, verificati sulle illustrazioni, caricati dal motore |
| Regole operative base | 🟢 | Traiettorie, Iniziativa, Scorrere del Tempo, Completamento |
| Battaglia base | 🟢 | completa e testata |
| Salvataggio, undo, ricarica | 🟢 | ogni stato persistente ha il suo test |
| **Tabelle Azione solitarie** | 🟢 | **93 caselle su 93 trascritte e implementate; zero segnaposto** |
| 15 scenari solitari, end-to-end | 🟢 | tutti giocabili, tutti chiudono su una fine STAMPATA |
| Attacco Furtivo dalla forza Furtiva | 🟢 | bot e giocatore: l'attacco lo esegue la forza, mai una Task Force |
| Forze Furtive (Mine, Sub, U-Boat) | 🟡 | nucleo, posa Mine e attacco fatti; U-Boat di A2 e disegno GUI no |
| Basi Aeree | 🟢 | lanciano Attacchi Aerei (RB p.27); stampate e piazzate in partita |
| Reazione Norvegese | 🟡 | quattro tabelle collegate ai due cicli; restano i risultati b/g |
| Battaglia avanzata | 🟢 | quattro scelte interattive e MS12 in tre Parti, motore e vista |
| Comandanti | 🟡 | testi trascritti; Forbes e Marschall non automatizzati |
| Basi aeree sulla Mappa Operazionale | 🟡 | diciassette trascritte; le sette con un anno aspettano l'anno dello scenario |
| Linea Artica | 🔴 | non e' un dato di mappa: i vincoli di RB p.27 non sono controllabili |
| Mappa a due giocatori | 🟡 | 22 scenari importati, mai auditati end-to-end |
| GUI operativa | 🟡 | il flusso solitario duplica `SoloRunner` |
| iPad / web | 🔴 | esportabile, mai provato su dispositivo |

## Che cosa e' FATTO 🟢

- **Le 93 caselle delle Tabelle Azione solitarie.** Erano 42 segnaposto: in
  quelle caselle il bot applicava una policy generica invece della procedura
  stampata. Adesso `audit_solo.gd` stampa zero. Ogni procedura e' trascritta
  dalla pagina renderizzata, con la pagina citata nel dato, e il bot sceglie
  davvero TF, rotta, bersaglio e continuazioni prescritte.
  La rilettura ha trovato difetti che nessun test poteva prendere, perche'
  stavano nel DATO: **tre tabelle scalate di una colonna** (Identificazione di
  N1 e N2, riga '1' di N5 - il fascicolo unisce due facce del dado in una
  colonna sola e chi trascrive ne legge sei dove ce ne sono cinque), **tre
  tabelle stampate dentro i risultati e assenti dal dato** (Nuova TF Britannica
  e esagono delle Mine di N2, X-Identificazione di N1), **una cella vuota** dove
  N3 stampa il simbolo del CONTATTO, **un modificatore attribuito alla tabella
  sbagliata** in N2, e **tre fini stampate** che non scattavano mai (C di N3, X
  di N5, I di N1).
- **Le due mappe inserto, per intero.** Reticolo misurato sull'immagine
  (`fit_inset_lattice.py`): e' lo stesso della Mappa Operazionale, passo 213.9 px
  contro 213.5. Esagoni, terreno, adiacenze, porti, Punti di Interesse, caselle
  fuori mappa, frecce "non adiacente" e basi aeree (`build_inset_graph.py`),
  verificati contro le illustrazioni del fascicolo
  (`validate_inset_setups.py`): 46 forme da segmento, tutte dentro esagoni del
  grafo. Il motore le carica e l'interfaccia le disegna come superficie di gioco.
- **Le caselle fuori mappa che il fascicolo usa come porti SONO porti.** Kiel,
  Murmansk, Scapa Flow e Portsmouth sugli inserti sono bande stampate ai bordi,
  non pallini, e `Completion.port_options` non li trovava: il tedesco di N1 non
  poteva Completare da nessuna parte. `MapGraph.load_inset` li promuove ora a
  porti prendendo la NAZIONE dal loro omonimo sulla Mappa Operazionale, che e'
  un dato stampato.
- **Tutti e quindici gli scenari solitari si giocano** e chiudono su una
  condizione di fine STAMPATA, con la pagina citata nel dato. Nessun `SALTATO`
  nel replay.
- **Gli schieramenti dei cinque scenari inserto**, letti dalle illustrazioni:
  BL3, N1, N2, N3 dai segmenti disegnati, N5 dal testo ("all TFs start in Scapa
  Flow"). Il **Sommergibile britannico di N3** e' fra questi: la pedina porta la
  Union Jack, e il suo esagono - (6,-1), Kristiansand - e' MISURATO con la
  registrazione di `validate_inset_setups.py`, 7.1 px dal centro contro un
  inraggio di circa 107.
- **`SoloRunner`**: gioca uno scenario solitario per intero senza GUI, con semi
  fissi, e `test_replay.gd` ne difende determinismo, terminazione, legalita' dei
  Completamenti e salvataggio.
- **Nucleo delle forze Furtive** (RB p.41): tipi, Ricognizione come
  piazzamento, restrizioni, Informazioni generate, e la restrizione all'attacco
  che da' senso al segnalino Contatto. **La posa delle Mine e' collegata**: N1
  posa le sue tre, N2 le posa sull'esagono tirato sul dado stampato.
- **Lo storico degli sbarchi in Norvegia** (`Norway.landings_of`). Il
  Completamento in Norvegia non scrive `completed_port`, perche' la Task Force
  del giocatore resta in gioco: quello storico non esisteva, e serve ai
  modificatori che guardano indietro (il -1 del dado del Convoglio di N5).

## Che cosa e' DA RIFINIRE 🟡

- **Forze Furtive**: restano i due marker U-Boat di A2, di cui il motore tiene
  solo il conteggio, e il disegno della pedina nella GUI.
- **Basi Aeree: restano i risultati `b`/`g` della Reazione Norvegese.** Tutto
  il resto e' fatto - la pedina, il salvataggio, le Informazioni innescate, e
  soprattutto l'Attacco Aereo lanciato dalla base (RB p.27) - ma i due risultati
  della Reazione che SPOSTANO un marcatore continuano a dichiarare la lacuna,
  perche' scritti quando la pedina non esisteva. Adesso si possono scrivere.
- **Reazione Norvegese**: le quattro tabelle (pp.19, 24, 27, 34) sono trascritte
  in `core/data/solo/norwegian_reaction.json` con innesco, colonne, righe,
  modificatori e legenda, e **il tiro e l'applicazione sono collegati a tutti e
  due i cicli** - `SoloRunner` e `ui/main.gd` chiamano `Norway.roll_reaction`
  sul Completamento in Norvegia del giocatore. La riga giusta viene scelta sullo
  stato, i Colpi vanno al Convoglio o allo Squadrone DD, il risultato `!`
  annulla il Completamento e passa l'Iniziativa. **Restano dichiarati** i
  risultati `b`/`g` che spostano marker Base Aerea e il modificatore che dipende
  dalle Basi Aeree tedesche.
- **Basi aeree sulla Mappa Operazionale: trascritte, ma sette aspettano un
  dato che non c'e'.** Le diciassette coccarde RAF sono lette sull'immagine a
  risoluzione nativa e stanno in `core/data/map_annotations.json`, col loro
  esagono, la posizione in pixel e l'anno stampato accanto quando c'e'. **Zero
  tedesche**, ed e' un dato: il regolamento le fa piazzare come marcatori.
  RB p.8 dice "prima dell'anno indicato, ignorate la base aerea", e **l'anno
  dello scenario non e' trascritto** - i file di scenario non lo hanno, la data
  compare solo nel testo del briefing. Finche' non lo e', le **sette basi con un
  anno restano fuori**: senza sapere l'anno non si puo' affermare che siano in
  gioco. Le dieci senza anno funzionano gia'.
  Restano fuori dal grafo giocabile due esagoni, (17,-4) e (4,6), su cui la
  coccarda e' stampata: segnato nel dato con `hex_outside_graph`, non corretto a
  mano.
- **Comandanti**: gli undici testi sono trascritti da RB p.10 letta a 300 dpi e
  Gensoul e' implementato; Forbes e Marschall no, e la voce Forbes ha un refuso
  di traduzione dichiarato.
- ~~Il layout non regge un viewport piu' basso di quanto chiede~~ - **NON ERA
  VERO, ed era la prova di fumo a sbagliare.** `smoke_map_workspace.gd`
  confrontava il fondo della fascia inferiore con `root.size.y`, cioe' l'altezza
  della FINESTRA in pixel, mentre quel rettangolo vive nelle coordinate LOGICHE
  della HUD. Con `window/stretch/mode="canvas_items"` e `aspect="expand"` i due
  spazi non coincidono: una finestra da 948 px porta un viewport logico da 1000,
  e la fascia a quota 988 risultava tagliata pur essendo tutta visibile - lo
  screenshot a 1600x948 mostra la fascia intera, col suo margine sotto. Il
  controllo passava o falliva a seconda di dove stavano barra e Dock, ed e' cosi'
  che si e' notato. Adesso confronta il viewport logico.
  **La verifica e' stata fatta**: 1280x720, 1600x900 e 1920x1080 passano tutte
  e tre, prova di fumo e screenshot. Resta il viewport stretto.
- **Battaglia avanzata**: le quattro scelte interattive e MS12 sono complete,
  motore e vista. Resta l'**audit visivo** di attitudini, rotazione navi,
  Acquiring, Closing, Fog, Confusion, siluri, inseguimento e Disingaggio in
  tutti i Round: e' l'unica voce del capitolo che chiede di guardare, non di
  scrivere.
- **I 22 scenari a due giocatori** hanno dati, setup e vittoria, ma nessun
  audit end-to-end.

## Che cosa MANCA 🔴

- **Il rilevatore della banda sui segmenti** funziona solo dove sono marroni e
  la banda e' bianca (BL3, N1). Su N2 e N3 - segmenti bianchi, banda blu - esce
  INVERTITO, e il tentativo di sistemarlo cercando il contrasto e' fallito:
  ogni segmento risulta bandato, perche' e' disegnato in piu' pezzi di colore
  diverso. Il dato lo dichiara con `band_reliable`; N2 e N3 sono stati letti a
  occhio.
- **I due marker U-Boat di A2**: il motore ne tiene solo il CONTEGGIO, perche'
  e' quello che la fine stampata consuma. La pedina sulla mappa non c'e'.
- **Il disegno delle forze Furtive e dei marcatori Base Aerea nella GUI**:
  esistono nel motore e nel salvataggio, non si vedono sulla mappa.
- **Il Denmark Strait come porto.** La 'D' di N1 manda a Completare "in nearest
  Denmark Strait port hex", ma il Denmark Strait non e' un porto su nessuna
  mappa del gioco - e' un tratto di mare - e non ha un controllo stampato. La
  procedura lo dichiara invece di inventarlo.
- **I Punti Rinforzo di N5** (una nave = 1 RP), che influenzano l'Esito di p.35.
- **I due CA "any" di N5** e, in generale, le scelte di schieramento che l'app
  risolve con un ripiego dichiarato invece di chiederle: BL2 (quattro navi
  "any"), A2 (acquisto in VP), N5 (organizzazione delle TF).
- **Tre esagoni inserto restano incerti** - (1,1) e (2,4) del Mare del Nord,
  (5,-3) del Mare di Norvegia - piu' tre lati "non adiacente" marcati
  `disputed`. Sono segnati nel dato, non risolti.
- **Prova su iPad o browser reale.**

## P0 - Integrita' del progetto

- [ ] Mantenere sempre verdi i comandi della baseline in `CLAUDE.md`.
- [ ] Non consentire che il totale scenda sotto 3676 senza rimozione esplicita.
- [x] Replay deterministici completi di BL1 e BL2: `core/rules/solo_runner.gd`
  (ciclo headless), `tools/replay_solo.gd` (semi fissi, tre esiti distinti) e
  `tests/unit/test_replay.gd` (83 verifiche). `tools/simulate_flow.gd` ne
  stampa il riepilogo in coda.
- [x] Verificare che nessuna callback differita continui dopo `solo_ended`:
  `test_nothing_acts_after_scenario_end` legge la trascrizione e pretende zero
  turni, tiri della Tabella e azioni dopo la riga `FINE SCENARIO`.
- [x] **Le REGOLE di sequenza sono in un posto solo**: `core/rules/solo_sequence.gd`
  tiene ramo del risultato, costruzione della dichiarazione (con la regola
  della Coordinatrice), esito sull'Iniziativa dopo l'azione, innesco della
  tabella Tardi e il vincolo "una decisione senza effetto cede l'Iniziativa".
  Sia `SoloRunner` sia `ui/main.gd` le chiamano. Ha gia' ripagato: le due copie
  erano divergute su `initiative_changes` e sulla Coordinatrice.
- [ ] **Resta duplicato l'ORDINE dei passi** (~12 righe di rami speculari in
  ciascun ciclo). Unificarlo richiede un iteratore di passi nel core e
  trasformare il ciclo della vista in coroutine, perche' i suoi passi
  attendono dialoghi, animazioni e la Mappa di Battaglia. Da fare quando serve
  toccare l'ordine, non prima: oggi le due copie non contengono piu' regole.
- [x] Smoke test GUI del ciclo solitario: `tools/smoke_solo_flow.gd` apre il
  gioco vero, passa l'Iniziativa all'avversario immaginario, risponde alle
  scelte del pannello e della mappa e pretende tiro della Tabella, mossa
  annunciata, Registro cresciuto, Iniziativa tornata e tasti ancora vivi.
  Verificato che fallisca davvero rompendo di proposito `_apply_solo_ai_result`.
- [ ] Estenderlo al flusso a due giocatori: dichiarazione Azione del giocatore,
  scelta su mappa, Scorrere del Tempo e Battaglia aperta da un risultato.

## P0 - Solitario completo

### Definition of Done per scenario

Uno scenario puo' essere marcato completo solo quando:

- [ ] setup, traiettorie, stazioni, rinforzi, comandanti e marker coincidono
  con la mappa stampata della seconda edizione;
- [ ] ogni tabella e ogni modificatore sono trascritti dalla pagina nativa;
- [ ] ogni codice della Tabella Azioni ha una policy specifica e testata;
- [ ] identificazione, reazioni, eventi, passaggi Presto/Tardi e condizioni di
  fine sono applicati automaticamente;
- [ ] il bot sceglie TF, rotta, bersaglio e continuazioni senza intervento
  umano per le decisioni dell'avversario immaginario;
- [ ] le rotte evitano Informazioni, basi aeree, acque neutrali o altri rischi
  quando la procedura lo prescrive;
- [ ] ogni ramo ha test con dadi forzati e almeno un replay completo termina;
- [ ] log e pannello di stato mostrano decisione finale e motivazione;
- [ ] salvataggio e ricarica riprendono lo stesso stato e lo stesso RNG;
- [ ] `audit_solo.gd` non conta piu' segnaposto per lo scenario.

### Scenari

Tutti e quindici si giocano e chiudono su una fine stampata: quello che
distingue un 🟢 da un 🟡 e' quante caselle della Tabella Azioni applicano
davvero la procedura del fascicolo invece di una policy generica.

| Scenario | Mappa | Stato | Che cosa manca |
|---|---|---|---|
| BL1 Raiders of the North Atlantic | Operazionale | 🟢 | audit visivo a mano |
| BL2 Contain and Destroy | Operazionale | 🟡 | Forbes non automatizzato |
| BL3 Raiders of the North Sea | Inserto Nord | 🟡 | Limiti di Classe |
| N1 Operazione Wilfred | Inserto Norvegia | 🟢 | sette procedure e cinque tabelle trascritte e implementate |
| N2 Operazione Weser (nord) | Inserto Norvegia | 🟢 | procedure e tabelle trascritte e implementate; Mine posate |
| N3 Operazione Weser (sud) | Inserto Nord | 🟢 | undici procedure implementate; Sommergibile britannico schierato in (6,-1) |
| N4 Operazione Weser (nord & sud) | Operazionale | 🟡 | il solo buco dichiarato che resta: Mine britanniche e Base Aerea come fonte; "Urgenza" |
| N5 Meglio Tardi che Mai | Inserto Norvegia | 🟡 | procedure implementate; restano Punti Rinforzo, due CA "any", Base Aerea come fonte di Attacco Aereo |
| N6 Il Dilemma delle Operazioni | Operazionale | 🟡 | Basi Aeree tedesche, Invasione della Norvegia, T-Seconda Azione |
| B1 Operazione Berlino | Operazionale | 🟡 | Tabella del Rifornimento di B1, Verifica della Scorta, basi aeree |
| B2 La Battaglia dell'Atlantico | Operazionale | 🟡 | -3 VP dei rinforzi |
| B3 Operazione Reno | Operazionale | 🟡 | Tabella del Rifornimento di B3, Tabella di Scelta della X, limiti di classe |
| B4 Decisione sui Mari | Operazionale | 🟡 | composizione TF iniziale DA VERIFICARE |
| A1 Convogli PQ | Operazionale | 🟡 | U-Boat, basi aeree, Limiti di Classe, clausola -1 VP |
| A2 L'Ultima Battaglia | Operazionale | 🟡 | acquisto forze in VP; pedina U-Boat (solo il conteggio) |


- [ ] **BL1 Raiders of the North Atlantic**: audit finale pagina per pagina.
  Il replay completo c'e' e arriva al Debriefing. Corretti in R0: la riga della
  Tabella Azioni (conta i Convogli britannici Completati **e distrutti**, non i
  Completamenti tedeschi), la condizione di fine di p.5, il ramo Meteo Cattivo
  della 'A' (con CA -> 'X', senza CA -> 'B'), i Limiti di Carburante di F e X e
  la chiusura di South America, la procedura CONVOGLIO per intero (prima
  cadeva nel ripiego generico: niente dado di rimando, niente nuova TF con
  Convoglio e CL) e la clausola "4 o piu' CA" della 'A', che vale come 'A' *e*
  'F' insieme con la francese Attiva e la britannica Coordinatrice.
  La Tabella Murmansk era trascritta scalata di una colonna (con un 1 le navi
  venivano confiscate invece di causare un incidente) e non la tirava nessuno:
  ora si legge come a p.8 e scatta da sola prima del Debriefing, sia nel replay
  sia nel pannello Punteggio. Il B-Dienst c'e': dal menu Solitario il giocatore
  attacca un segnalino Informazioni a un segmento di Traiettoria britannica,
  con l'Iniziativa tedesca e una volta sola per scenario.
  **Resta**: un audit visivo della partita giocata a mano, e la lacuna di fine
  scenario qui sotto.
- [ ] **BL1: la fine stampata non copre la posizione "nessuna TF tedesca con
  piu' di due marker RV".** Un RV si rimuove solo con un Controllo
  Rifornimento, che richiede una Stazione tedesca: perse tutte le navi e i
  Rinforzi, la partita non puo' piu' finire. Il replay lo dichiara (`STALLO`,
  9 semi su 40) invece di inventare una condizione. Va chiesto o cercato un
  chiarimento GMT prima di scrivere una regola.
- [ ] **BL2 Contain and Destroy**: audit finale pagina per pagina. Home Fleet,
  Convogli, Acque Neutrali, Pound/Forbes, Identificazione e procedure
  A/C/Convoglio/E/T/X sono implementate; il replay arriva a una condizione di
  fine stampata su tutti i 40 semi provati. **Gensoul e' implementato**: quando
  la sua TF e' designata Attiva puo' togliere un segnalino Informazioni da una
  TF designata nell'Azione corrente, una volta per scenario, e l'offerta arriva
  PRIMA della risoluzione perche' l'Interruzione si tira proprio su quei
  segnalini. **Resta Forbes.**
- [ ] **CINQUE scenari solitari si giocano su una MAPPA INSERTO**, non sulla
  Mappa Operazionale: BL3 e N3 sul Mare del Nord, N1, N2 e N5 sul Mare di
  Norvegia (fascicolo pp.12, 17, 21, 25, 32). Solo BL3 lo dichiarava; gli altri
  quattro piazzavano le Task Force su porti della mappa grande usati come
  sostituti - Narvik per Vestfjorden, Trondheim per Bud, Bergen per Andalsnes -
  cioe' su posizioni inventate. Ora lo dichiarano tutti e cinque e il replay si
  rifiuta di giocarli; lo schieramento trascritto resta in `unplaced_forces`,
  pronto per quando l'inserto sara' calibrato.
  **I due reticoli sono ora MISURATI** (`tools/fit_inset_lattice.py`,
  `core/data/map_insets.json`): fit sull'immagine stampata, con verifica
  visiva e un `--check` che rifa' la misura e la confronta col dato salvato.
  Il risultato e' che i due inserti condividono un solo reticolo, e quel
  reticolo e' lo stesso della Mappa Operazionale: passo 213.9 px contro 213.5,
  circumraggio 123.50 contro 123.26, direzione di base 44.25 gradi contro
  44.28. GMT stampa gli inserti alla stessa scala esagonale della mappa grande,
  e non c'era modo di saperlo senza misurarlo.
  **La nomenclatura degli esagoni e' fatta** (`tools/build_inset_graph.py`,
  `core/data/inset_graphs.json`): coordinate assiali `(q, r)` con le stesse sei
  direzioni della mappa grande, origine in `(0,0)` sulla cella piu' vicina
  all'angolo in alto a sinistra della cornice stampata - misurata
  sull'immagine, non decisa. Terreno classificato per colore in mare, terra,
  casella fuori mappa e fuori cornice, poi le due pulizie topologiche che
  `build_map_graph.py` gia' fa sulla mappa grande. **29 esagoni** sul Mare del
  Nord, **27** sul Mare di Norvegia, con adiacenze.
  **Anche i 16 punti stampati sono trovati e collocati**: il rilevatore cerca
  i pallini pieni rossi, ciano e neri e i cerchi vuoti, e distingue i cerchi
  dalle lettere 'o' ed 'e' delle etichette col cuore bianco (oltre 245 di
  luminosita' contro meno di 170). I nomi sono letti sulla mappa e accoppiati
  ai pallini uno a uno: se un pallino resta senza nome o un nome senza
  pallino, il programma si ferma.
  **CORREZIONE**: i pallini PIENI sono porti, i cerchi VUOTI sono **Punti di
  Interesse**, e al primo giro li avevo messi tutti insieme come porti.
  Fascicolo p.16: "POINTS OF INTEREST - These points have no effect on game
  play, except to orient the player". Sono 5 porti e 3 punti sul Mare del Nord,
  2 porti e 6 punti sul Mare di Norvegia. Il loro ESAGONO conta lo stesso,
  perche' la stessa pagina permette il Completamento in un esagono di Norvegia
  con un Convoglio o uno Squadrone DD nella TF, e N1 chiede di posare le Mine
  "in the hexes with Bud and Andalsnes".
  **Le sette caselle fuori mappa sono trascritte**: Norwegian Sea, Kiel e
  Portsmouth sul Mare del Nord; Murmansk, Denmark Strait, Scapa Flow e Kiel sul
  Mare di Norvegia. Il fascicolo le usa davvero - p.18 manda a Completare "in
  nearest Denmark Strait port hex" e mette Murmansk e Kiel nella Tabella dei
  Porti, p.17 fa Completare a Scapa Flow i Convogli britannici di N1 e ci fa
  partire i Gruppi Rinforzo. Quali esagoni una banda designi non e' scritto da
  nessuna parte: si prendono quelli che la banda tocca, unica lettura
  compatibile col "nearest ... port hex", e la percentuale di contatto resta
  nel dato.
  **CORREZIONE alla classificazione del terreno**: le frazioni si misurano
  sull'area DI MAPPA, dentro la cornice, non sull'area intera dell'esagono. La
  parte oltre la cornice non e' terra, non e' mappa, e contarla contro
  l'esagono bocciava mezzo bordo. Gli esagoni passano da 29 a **34** sul Mare
  del Nord e da 27 a **33** sul Mare di Norvegia, e (7,1) - Kiel Bay, chiamato
  in causa da due frecce "non adiacente" - passa dal 39% all'88% di mare.
  Un esagono che contiene un porto e' giocabile per forza, come la mappa
  grande fa con `force_playable`: senza quella regola il colore buttava via
  Methil, Wilhelmshaven, Kiel, Kristiansand, Trondheim, Namsos, Andalsnes e
  Tromso, che sono meta' terraferma.
  **Anche le nove frecce "non adiacente" sono trascritte**: sei sul Mare del
  Nord, tre sul Mare di Norvegia. RB p.4 e FAQ p.44: negano la Traiettoria fra
  i due esagoni che collegano, ma **il Supporto Aereo resta permesso**. Le
  posizioni sono lette sulle immagini ingrandite col reticolo etichettato
  sopra; il lato lo ricava il programma dai due esagoni piu' vicini e si ferma
  se non sono adiacenti.
  **Tre lati restano marcati `disputed`** (erano quattro): (2,4)|(2,5) sul Mare
  del Nord, (6,-1)|(6,0) e (6,1)|(6,2) sul Mare di Norvegia. I due che
  toccavano (7,1) si sono risolti da soli quando la classificazione ha smesso
  di contare il fuori-cornice come terra - il che e' anche la conferma che
  quelle frecce erano un indizio buono. I tre che restano toccano esagoni
  davvero di terra o coperti dal riquadro di Portsmouth: lo decideranno le
  illustrazioni del fascicolo.
  **Le basi aeree sono trovate e collocate**: sette sul Mare del Nord, cinque
  britanniche lungo la costa inglese e scozzese (2,0) (2,2) (2,3) (2,4) (3,4) e
  due tedesche a (6,0) Skagerrak e (5,2) Horns Reef; **zero sul Mare di
  Norvegia**, e l'elenco vuoto e' un dato, non una dimenticanza. Il rilevatore
  le isola col bianco puro del disco - sulla mappa non c'e' quasi nient'altro
  sopra 248 su tutti e tre i canali - e la parte viene dal colore della lettera
  e dell'aereo, rossi britannici e viola tedeschi. Posizione e parte sono anche
  trascritte a mano: se il rilevato e il trascritto non combaciano, il
  programma si ferma.
  La regola sta in RB p.27: una base aerea e' la **fonte** di un Attacco Aereo,
  che parte dal suo esagono, si fa **solo col Meteo Buono** e non puo' colpire
  oltre **due esagoni** dal Punto di Lancio; una base aerea **non puo' essere
  il bersaglio**.
  **Il grafo e' verificato contro le illustrazioni del fascicolo**
  (`tools/validate_inset_setups.py`, `core/data/inset_setups.json`). La verita'
  indipendente che sembrava non esistere c'era: le illustrazioni di
  schieramento dei cinque scenari disegnano i segmenti di Traiettoria iniziali
  SULLA mappa, e nel PDF quei segmenti sono grafica vettoriale con coordinate
  esatte. L'illustrazione riusa la stessa immagine dell'inserto, quindi la sua
  collocazione sulla pagina da' la registrazione. **46 forme da segmento su
  cinque pagine, tutte in esagoni che il grafo dichiara giocabili, zero fuori.**
  **Sette incertezze su dieci si chiudono**: gli esagoni `needs_check` (1,2),
  (5,3), (6,-1), (6,0), (6,1), (6,2) del Mare del Nord e (6,0) del Mare di
  Norvegia hanno un segmento stampato dentro, e un esagono in cui il fascicolo
  disegna una Traiettoria e' giocabile - e' un dato stampato, e batte una
  soglia di colore. Restano aperti (1,1) e (2,4) del Mare del Nord, (5,-3) del
  Mare di Norvegia, e i tre lati `disputed`.
  **Il motore carica le due mappe inserto.** Non e' una classe nuova:
  `MapGraph` era gia' generico, e ora ha `load_inset(chiave)` che traduce la
  forma del dato inserto in quella che sa gia' leggere. Geometria, adiacenze e
  porti restano un solo pezzo di codice, perche' il reticolo dell'inserto e'
  quello della mappa grande. Le frecce "non adiacente" diventano
  `blocked_edges`: sono la stessa regola con un altro nome. Basi aeree, Punti
  di Interesse e caselle fuori mappa sono esposti come DATO, non come regole
  implementate.
  Due trappole prese e chiuse, nessuna delle quali si vedeva nei numeri perche'
  i centri degli esagoni vengono dal JSON: il dato inserto salva `theta_deg`
  come angolo dei VERTICI mentre `hex_corners()` lo vuole come direzione di
  BASE (30 gradi di differenza), e le sue `(q,r)` sono ribasate sull'angolo
  della cornice, quindi serviva scrivere nel dato l'origine ribasata o
  `hex_to_pixel` sbagliava di una cella e mezzo. Cinque test nuovi in
  `test_hex_and_graph.gd` li inchiodano misurando circumraggio, inraggio e
  l'allineamento dei vertici rispetto ai vicini.
  **L'interfaccia disegna l'inserto.** Aprendo uno dei cinque scenari, la mappa
  inserto diventa la superficie di gioco: `MapBoard` carica una texture sola
  invece dei tile della mappa grande, e il disegno del reticolo non cambia di
  una riga perche' e' tutto guidato dal `MapGraph`. Il grafo pero' e' condiviso
  da stato, tabellone, Traiettorie e camera, e vanno ripuntati tutti insieme:
  `tools/smoke_inset_map.gd` apre l'interfaccia vera, carica uno scenario per
  inserto e controlla che nessuno resti indietro, poi che tornare a uno
  scenario normale rimetta la Mappa Operazionale coi suoi tile.
  Corretto anche un difetto vecchio riemerso: `TrajectoryRenderer.setup()`
  riconnetteva il segnale ogni volta, e adesso che si puo' chiamare due volte
  Godot protestava.
  **BL3 e' schierato e si gioca.** E' il primo dei cinque: l'illustrazione di
  p.12 disegna cinque segmenti in fila - (1,2) (2,1) (3,0) (4,-1) (5,-2), da
  Methil verso Bergen - che sono la Traiettoria della TF britannica non
  identificata, e un cilindro Stazione in (5,2) che il pannello Task Force
  identifica come la TF tedesca (Scharnhorst, Gneisenau, Hipper: stesso set
  colore bianco a riga blu). `SoloRunner` sceglie la mappa dallo scenario, e il
  replay porta BL3 alla sua fine stampata di p.12, aggiunta come condizione:
  "no Task Forces in play, or two Convoys and/or Unidentified TFs Completed or
  destroyed". Il marker Sommergibile britannico e' in (5,1) - posizione letta,
  ma le forze Furtive non sono ancora modellate, quindi resta lacuna dichiarata.
  **N1 e' schierato e si gioca.** Il nodo era il testo: "Enemy: No German TFs at
  start" e insieme un riquadro sui Convogli tedeschi. p.19 lo scioglie - i
  Convogli tedeschi li crea a Kiel la Tabella delle Azioni, risultati M e N -
  quindi tutti i 18 segmenti disegnati sono BRITANNICI. La striscia bianca
  stampata sul segmento separa chi porta un Convoglio da chi no: otto lisci in
  fila, (2,5) (2,4) (2,3) (3,2) (3,1) (3,0) (4,-1) (5,-2) da Scapa Flow a
  Vestfjorden, sono Renown e Squadrone DD; gli otto striati sono due Traiettorie
  parallele di quattro, e il terzo Convoglio e' il cilindro Stazione in (2,5).
  I richiami di p.17 mandano Valiant, Repulse, Rodney e Sheffield con Forbes nel
  Gruppo A e Birmingham nel Gruppo B. Fine stampata: "the British have no
  Convoys in play".
  Lacuna dichiarata: le Mine sono l'OBIETTIVO di N1 - una in Vestfjorden, una a
  Bud, una ad Andalsnes - ma le forze Furtive non sono modellate, quindi la posa
  non e' automatizzata.
  **N2 e' schierato e si gioca.** Dieci segmenti in due Traiettorie che salgono
  da Kiel: (5,3) (5,2) (5,1) (5,0) (5,-1) (5,-2) fino a Narvik e (5,3) (5,2)
  (5,1) (6,0) fino a Trondheim. L'assegnazione viene dal pannello Task Force di
  p.21 - lo slot con la BANDA BLU tiene Hipper e lo Squadrone DD, l'altro
  Scharnhorst, Gneisenau e il Convoglio - e combacia con l'obiettivo stampato,
  che manda il Convoglio a Narvik e lo Squadrone DD a Trondheim.
  **Il rilevatore automatico della banda resta rotto su N2 e N3**, e ho provato
  a sistemarlo: cercare il CONTRASTO col segmento invece del bianco assoluto
  fa risultare bandati TUTTI i segmenti, perche' ognuno e' disegnato in piu'
  pezzi di colore diverso, e filtrare per lunghezza non separa l'ombra dalla
  banda. Ho annullato il tentativo e lasciato il flag dichiarato inaffidabile:
  l'assegnazione di N2 e' letta a occhio sull'illustrazione, che e' il metodo
  che questo progetto usa per le tabelle e che qui funziona.
  **N3 e' schierato e si gioca**, gemello di N2 sull'altro inserto. Dodici
  segmenti in due Traiettorie che salgono dai porti tedeschi e condividono la
  coda: (5,3) (6,2) (6,1) (6,0) (5,0) (5,-1) (5,-2) fino a Bergen e (5,3) (6,2)
  (6,1) (6,0) (6,-1) fino a Kristiansand. Il Pannello Task Force Tedesco di
  p.25 mette Konigsberg, Koln e il Convoglio nello slot LISCIO e Karlsruhe con
  lo Squadrone DD in quello con la BANDA BLU - e l'obiettivo stampato manda il
  Convoglio a Bergen e lo Squadrone DD a Kristiansand. Il segnalino Informazioni
  prescritto "in Kristiansand" e' nel campo `info` del segmento (6,-1), non in
  una nota. Anche qui la banda e' stata letta a occhio: il rilevatore automatico
  su questa pagina esce invertito.
  **N5 e' schierato e si gioca, e con lui TUTTI E QUINDICI i solitari chiudono
  su una condizione stampata.** La sua illustrazione non disegna segmenti, e non
  era una dimenticanza: la pagina dice "all TFs start in Scapa Flow", quindi
  all'inizio sulla mappa non c'e' niente da leggere. La composizione delle Task
  Force e' una SCELTA DEL GIOCATORE, con un vincolo solo - "a Convoy may share a
  TF with only one other ship, a CA or a CL" - e l'app parte da
  un'organizzazione di ripiego dichiarata, lo stesso criterio di BL2 e A2.
  **Restano lacune DENTRO gli scenari**, non piu' scenari fermi: Mine e forze
  Furtive (che sono l'obiettivo di N1), Reazione Norvegese, Completamenti in
  Norvegia, i due CA 'any' di N5 e i suoi Punti Rinforzo.
  mappa e' solo sfondo dei riquadri di regola, quindi va ricavato dal testo).
  Tre test hanno cambiato premessa insieme al fatto, e vale la pena saperlo:
  controllavano che gli scenari inserto NON avessero schieramento, e adesso
  controllano che le loro TF stiano sulla PROPRIA mappa - che e' il difetto
  vero da cui quei test erano nati, le posizioni inventate su porti sostitutivi.
  **Otto esagoni sono marcati `needs_check`**: hanno terra e mare quasi in
  parti uguali, e il colore non basta a decidere. Gli esagoni scartati per un
  soffio restano scritti in `excluded_near_miss`, col motivo: nessuno sparisce
  in silenzio.
  **La verita' indipendente esiste**: le illustrazioni di schieramento del
  fascicolo (BL3 a p.12, e le pagine corrispondenti di N1, N2, N3, N5) mostrano
  i segmenti di Traiettoria iniziali disegnati SULL'INSERTO. Sono per l'inserto
  quello che le 238 pedine del modulo VASSAL sono state per la mappa grande: un
  campione contro cui validare, e va usato invece di posizioni scelte a mano.
- [x] **N1 Operazione Wilfred**: le procedure sono trascritte dalle pagine
  renderizzate (pp.17-20) **e implementate**, con le tabelle di contorno -
  Porto, Nuova TF Tedesca, Identificazione, Reazione Norvegese - piu' la
  **X - Identificazione della TF Tedesca**, che era stampata dentro il risultato
  'X' e nel dato non c'era affatto. Tre difetti veri:
  la tabella di **Identificazione era scalata di una colonna** - le colonne
  stampate sono `1 | 2-3 | 4 | 5 | 6` - quindi con un 3 usciva CL/Convoglio
  invece di BC/BC/Convoglio;
  i **rimandi di testa della 'M'** non c'erano: se una TF non identificata o con
  un Convoglio e' gia' IN Murmansk il risultato diventa 'N', e con un BC integro
  senza Convoglio diventa 'D';
  la **fine stampata dentro la 'I'** - "if no TF to target, the scenario ends" -
  non scattava mai.
  **E il tedesco non poteva Completare da nessuna parte**: la sua Tabella dei
  Porti elenca Murmansk e Kiel, che sul Mare di Norvegia sono caselle fuori
  mappa e non pallini, quindi `Completion.port_options` non li trovava. Adesso
  `MapGraph.load_inset` promuove a porti le caselle fuori mappa il cui nome e'
  un porto della Mappa Operazionale - Kiel, Murmansk, Scapa Flow, Portsmouth -
  prendendo da li' la NAZIONE, che e' un dato stampato.
  **RESTA DICHIARATO** il Denmark Strait della 'D': il fascicolo lo chiama
  "port hex", ma non e' un porto su nessuna mappa del gioco e non ha un
  controllo stampato, quindi il Completamento li' non e' risolvibile e la
  procedura lo dice invece di inventarlo.
- [x] **N2 Operazione Weser (nord)**: le procedure sono trascritte dalle pagine
  renderizzate (pp.21-24) **e implementate**, comprese le due sotto-tabelle
  stampate DENTRO i risultati che nel dato non c'erano affatto - Nuova TF
  Britannica e l'esagono delle Mine. Tre difetti veri:
  la tabella di **Identificazione era scalata di una colonna** - le colonne
  stampate sono `1 | 2 | 3-4 | 5 | 6` e la trascrizione le aveva lette come sei
  colonne distinte, quindi da un 4 in poi tutto slittava: con un 4 la riga
  Iniziale dava DD/Convoglio invece di CL/Convoglio. E' lo stesso difetto della
  Tabella Murmansk di BL1;
  la **tabella Iniziale aveva un modificatore che non le appartiene** - la
  pagina stampa "Modifiers (Late table only)" e il dato ne aveva uno, un -1 per
  nave britannica Danneggiata o affondata, che spostava tutti i tiri Iniziali;
  **'AA' e 'Bd' puntavano a Bergen e Trondheim**, cioe' ai porti della Mappa
  Operazionale usati come sostituti quando l'inserto non era calibrato, e non ad
  **Andalsnes** e **Bud**. Andalsnes e Bud non sono porti ma Punti di Interesse,
  quindi il loro Completamento e' quello IN NORVEGIA di p.16, che vuole un
  Convoglio o uno Squadrone DD a bordo: senza quel ramo la procedura dichiarava
  "porto non calibrato" e passava, cioe' non completava mai.
  **Le Mine sono posate davvero** (`Stealth.place`, con l'esagono tirato sul
  dado stampato), e la procedura rispetta il "this is not Recon": non assegna
  segnalini Informazioni. **Resta** la Reazione Norvegese di p.24, la cui
  tabella e' trascritta ma il cui tiro non e' ancora nel ciclo di N2.
- [x] **N3 Operazione Weser (sud)**: le undici procedure sono trascritte dalle
  pagine renderizzate (pp.25-27) **e implementate**, non piu' approssimate. Le
  sei della Tabella di Azione Britannica girano tutte attorno al Sommergibile
  britannico: 'SA' lo fa attaccare col +3 stampato, 'SR' lo piazza (ed e' la
  strada per cui rientra dopo un 'SA'), 'X' misura la distanza dei bersagli DA
  LUI. Quattro difetti veri trovati per strada:
  la cella della colonna 5 della prima riga era **vuota** nel dato, mentre la
  pagina ci stampa il simbolo dell'occhio, cioe' il risultato CONTATTO - quel
  risultato non si e' mai potuto verificare;
  il marker Sommergibile dell'illustrazione e' **britannico**, non tedesco come
  diceva la nota di schieramento (la pedina porta la Union Jack, e la Tabella
  parla sempre di "the British Submarine stealth force"), e il suo esagono non
  era ignoto: e' **(6,-1)**, misurato con la registrazione di
  `validate_inset_setups.py` - 7.1 px dal centro, contro un inraggio di ~107;
  la 'C' porta una **fine stampata** che non sta nel riquadro "The End" (senza
  TF britanniche e senza Attacco Aereo possibile, se il Convoglio e lo Squadrone
  DD tedeschi hanno consegnato in Norvegia lo scenario finisce);
  `Stealth.placement_error` leggeva `port_control` con `int()`, che su una
  stringa torna 0 senza protestare, quindi **ogni porto "BOTH" o "NONE"
  risultava tedesco** e a una forza Furtiva britannica veniva rifiutato Bergen -
  proprio l'esagono che la 'SR' dice di preferire.
  **RESTA DICHIARATO** un refuso del fascicolo: le cinque colonne della tabella
  di Identificazione sono intestate `1 | 2 | 4 | 5 | 5-6`, cioe' manca la 3 e il
  5 compare due volte. Su 1d6 l'unica lettura che copre tutte e sei le facce e'
  `1 / 2 / 3 / 4 / 5-6`, ed e' quella usata; la faccia 3 resta l'unica non
  verificabile sullo stampato. **Restano** la Reazione Norvegese di p.27 - la
  tabella e' trascritta, il tiro dentro il ciclo di N3 no - e i Completamenti in
  Norvegia.
- [ ] **N4 Operazione Weser (nord & sud)**: tabella e modificatori gia'
  coincidevano col fascicolo; le sei procedure sono ora trascritte per esteso e
  la **Tabella della Reazione Norvegese (p.30) e' stata aggiunta**, prima
  mancava del tutto. Implementate: primo R4 contro R4 successivi, il CL
  francese e la TF6 a Methil che mancavano dal primo R4, il rimando
  Convoglio -> R4, il dado PARI/DISPARI della X e soprattutto "If no target,
  the scenario ends", cioe' il "(or possibly by Action Table result 'X')" del
  riquadro The End. La X sceglie ora la TF con Forbes, come stampato.
  **Restano**: i risultati Mine e SA, che richiedono Mine, basi aeree e forze
  furtive Sottomarino - i tre sistemi non modellati; l'applicazione automatica
  della Reazione Norvegese (la tabella c'e', la procedura che la tira no); la
  regola "Urgency", per cui il britannico tenta SEMPRE di Sottrarre e non
  prende mai Manovre Evasive; e "the British use Forbes' leader benefit only
  during an Engage action".
- [x] **N5 Meglio Tardi che Mai**: le dieci procedure sono trascritte dalle
  pagine renderizzate (pp.32-35) **e implementate**. N5 non aveva nessuna policy
  propria: cadeva nel ripiego generico in fondo a `execute_code`, quindi la 'A'
  non piazzava nessuna Base Aerea, la 'Conv' non tirava il dado del porto
  norvegese, e la fine stampata DENTRO la 'X' - "se l'unico bersaglio e' una
  Stazione a Scapa Flow, l'azione e' annullata e lo scenario finisce" - non
  scattava mai.
  **I marcatori Base Aerea esistono** (`core/rules/air_base.gd`,
  `GameState.placed_air_bases`): li mettono e li tolgono quattro procedure
  stampate - BL2 p.11, N4 p.30, N5 p.33, N6 p.37 - e finora tutte e quattro
  dichiaravano la lacuna perche' la pedina non esisteva da nessuna parte. Il
  marcatore si salva e, come qualunque base aerea nemica (RB p.21), innesca
  Informazioni nel suo esagono.
  **Gli sbarchi in Norvegia lasciano una traccia** (`Norway.landings_of`): il
  Completamento in Norvegia non scrive `completed_port`, perche' la Task Force
  del giocatore resta in gioco, quindi lo storico non esisteva. Serviva al -1
  del dado del Convoglio di N5, ed era una lacuna dichiarata.
  **Corretta una cella sbagliata**: la riga '1', colonna 4, della tabella di
  Identificazione stampa `CL/CL` - DUE incrociatori leggeri - e il dato ne aveva
  uno solo. Stessa classe di difetto della colonna 3 di B3.
  **RESTA DICHIARATO** un refuso: la 'A' dice "roll again on the British Action
  Table", ma in N5 il giocatore E' il britannico e l'unica Tabella stampata e'
  quella tedesca.
  **Restano**: una Base Aerea come FONTE di un Attacco Aereo (RB p.27) - il
  motore pretende una TF con una CV integra e non sa partire da un esagono, e il
  passo Bersaglio della 'A' col Meteo Buono lo dichiara -, i Punti Rinforzo e i
  due CA 'any'.
- [ ] **N6 Il Dilemma delle Operazioni**: le quattro tabelle - Azioni Tedesche,
  Traiettoria Tedesca, T-Seconda Azione, Identificazione - e i modificatori
  coincidevano gia' col fascicolo; le 25 procedure sono ora trascritte. N6 non
  aveva **nessuna policy propria** e cadeva nel ripiego generico, quindi le due
  condizioni di fine stampate DENTRO i risultati non venivano mai verificate:
  la 'T' finisce lo scenario con due Convogli tedeschi Completati in Norvegia,
  la 'X' con tre o piu' navi tedesche perse. Sono il "It may also end by the
  German Action Table" del riquadro The End. Implementati anche i rimandi di
  meteo, il Passare a 15 segmenti e i tiri di destinazione della Traiettoria.
  **Restano**: le Basi Aeree tedesche (risultato 'A' col Meteo Buono e clausola
  finale della 'C'), l'Invasione della Norvegia, la tabella T-Seconda Azione
  applicata automaticamente dopo la Traiettoria, e le sostituzioni stampate
  della tabella di Identificazione. Jan Mayen e le Azzorre non sono esagoni
  calibrati: la policy punta al porto calibrato piu' vicino e lo dichiara.
- [ ] **B1 Operazione Berlino**: celle e modificatori delle quattro tabelle -
  Rifornimento, Azioni Britanniche, Identificazione, Verifica della Scorta -
  coincidevano gia' col fascicolo; le 22 procedure sono ora trascritte. Nel
  codice **mancava tutto il risultato 'E'**: non esisteva un ramo per lui e
  finiva nel ripiego, che lo trattava come un Convoglio. E' l'unico modo in cui
  il BRITANNICO toglie marker Rendezvous dalla mappa, e porta due condizioni di
  fine stampate ("se non ce n'e' nessuno in gioco, lo scenario finisce");
  mancava anche la fine della 'X' a tre Convogli britannici Completati.
  **Restano**: la Tabella del Rifornimento di B1 non e' applicata (i suoi
  risultati sono diversi da quelli di BL1 - il Nuovo Obiettivo manda a Narvik,
  non in South America - e `apply_table_result` conosce solo BL1 e BL2); la
  Verifica della Scorta; le basi aeree e la portata del supporto aereo, che
  compaiono in quasi tutte le procedure.
- [ ] **B2 La Battaglia dell'Atlantico**: 10 procedure trascritte. **Mancava
  meta' dello schieramento**: il Gruppo di Rinforzo A - un Convoglio e la
  Ramilles, a New York - non era nei dati, e al Gruppo B mancava lo Sheffield.
  Il Gruppo A porta il TERZO Convoglio, e senza di lui la condizione di fine
  stampata non poteva avverarsi: lo scenario schiera due Convogli e ne chiede
  tre. Aggiunti anche i porti dei Gruppi e Somerville sul B. **Restano**: la
  penalita' di -3 VP per il Gruppo B (trascritta, non applicata: nessuno
  scenario fa ancora pagare un Gruppo), la regola Rationing, e i rami delle
  procedure che dipendono dalle basi aeree tedesche.
- [ ] **B3 Operazione Reno**: 24 procedure ora trascritte. **Corretta una cella
  sbagliata**: la colonna 3 della tabella di Identificazione stampa CV/CA/CA,
  tre navi, e il dato ne aveva due - una TF non identificata entrava in
  Battaglia con un incrociatore in meno. Come N6, B3 non aveva nessuna policy
  propria: ora ce l'ha, con la condizione di fine stampata dentro la 'X'
  (Bismarck affondata o Completata, oppure tre Convogli Completati), il dado
  che sceglie il bersaglio tedesco (1-4 la TF con una BB, 5-6 la piu' vicina) e
  i rimandi di meteo della 'A'. **Restano**: la Tabella del Rifornimento di B3
  non e' applicata (ha otto risultati a-h, diversi da BL1 e da B1), la Tabella
  di Scelta della X con i suoi risultati stellati e la TF Coordinatrice, i
  limiti di classe della tabella di Identificazione, e le basi aeree.
- [ ] **B4 Decisione sui Mari**: 12 procedure trascritte. Stessa lacuna di B2:
  dei tre Gruppi di Rinforzo stampati - **A a St. John's** con un Convoglio,
  **B a Gibilterra** con Renown, Ark Royal e Sheffield, **C a Scapa Flow** con
  la Victorious - nei dati c'era solo il B, senza lo Sheffield e senza porto.
  Il Gruppo A porta il terzo Convoglio, e senza di lui la fine stampata era
  irraggiungibile. **DA VERIFICARE**: la composizione delle Task Force
  INIZIALI non coincide con quella illustrata a p.54-55, dove il britannico
  schiera piu' gruppi (Hood e Prince of Wales, King George V con Tovey,
  Manchester e Arethusa, Birmingham e Suffolk, Norfolk, Ramilles col Convoglio,
  Rodney col Convoglio di Gibilterra). La mappa da' i conti per classe e il
  Display i nomi: serve una lettura incrociata. **Restano** anche i -3 VP del
  Gruppo B, la regola Rationing, i limiti di classe e le basi aeree.
- [ ] **A1 Convogli PQ**: 3 procedure trascritte. Il suo Gruppo di Rinforzo A
  **non ha un porto fisso**: partenza e destinazione si tirano sul dado (1-2
  Clyde/Liverpool verso Murmansk, 3-5 Hvalfiord verso Murmansk, 6 Hvalfiord
  verso Archangel). E' l'unico scenario in cui succede, ed e' il motivo per cui
  il Gruppo non compariva fra i porti: ora e' in `reinforcement_routes` e il
  replay lo tira. Implementata anche la fine stampata nella 'X' (una BB tedesca
  affondata o Completata). **Restano**: la forza U-Boat iniziale (manca una
  pedina nave operazionale verificata), le basi aeree, i limiti di classe, i
  -3 VP del Gruppo B e la clausola che sottrae 1 VP quando la 'X' non trova
  Convogli bersagliabili. **Bletchley Park e' fatto**: era il B-Dienst con le
  parti scambiate, e ora i due condividono lo stesso meccanismo
  (`intel_marker_once` nel dato di scenario).
- [ ] **A2 L'Ultima Battaglia**: le venti procedure sono trascritte (pp.63-68,
  lette sulle pagine renderizzate) e le due fini stampate DENTRO la Tabella di
  Azione Britannica sono implementate: il risultato 'E' consuma un marker
  Rendezvous col Meteo Cattivo e un marker U-Boat col Meteo Buono, e finisce lo
  scenario quando non ce n'e' piu'; il risultato 'X' finisce lo scenario se una
  BB tedesca e' affondata, o se tre navi tedesche sono affondate, o se quattro
  Convogli hanno Completato. Il replay chiude su tutti i semi provati.
  **Restano**: l'acquisto delle forze coi VP (p.65: il motore usa un acquisto
  di ripiego dichiarato, Tirpitz + Prinz Eugen a Kiel piu' lo Squadrone DD,
  -3 VP), la pedina U-Boat sulla mappa (ne e' modellato solo il CONTEGGIO, che
  serve alla fine stampata), il marker Contatto e le Manovre Evasive dei
  risultati del Rifornimento, e la TF Coordinatrice dei risultati con la stella.

I numeri sopra contano tutte le stringhe `senza automatismi del motore` nei
rispettivi JSON. L'audit automatico conta solo quelle nelle Tabelle Azioni e
per questo riporta 82, non la somma dell'elenco.

### Che cosa dice oggi il replay, scenario per scenario

`godot --headless --path . --script res://tools/replay_solo.gd` gioca tutti e
quindici e distingue tre esiti. Non e' piu' "120 turni" per tutti: adesso ogni
riga dice che cosa manca.

| esito | scenari | che cosa serve |
|---|---|---|
| finisce per condizione stampata | tutti e quindici | niente: il ciclo e' completo |

**Tutti e quindici chiudono su una condizione stampata**, i dieci della Mappa
Operazionale e i cinque degli inserti. Non c'e' piu' uno scenario da far
partire, e non c'e' piu' una casella della Tabella Azioni che applichi una
policy generica: quello che resta e' DENTRO gli scenari, ed e' elencato qui
sopra scenario per scenario.

## P0 - Sistemi mancanti al solitario

- [ ] **Forze Furtive: il NUCLEO c'e', mancano il piazzamento da scenario e la
  GUI.** `core/rules/stealth.gd` (puro `RefCounted`) e `GameState.stealth_forces`
  implementano da RB p.41: i tre tipi, la Ricognizione come PIAZZAMENTO - "non
  fa differenza dove la forza Furtiva e' al momento in cui viene annunciata
  l'azione" - le restrizioni al piazzamento (mai su porto o Base Aerea nemici,
  ammesso su una TF nemica con un CV), l'assegnazione di Informazioni a ogni TF
  nemica nell'esagono, e soprattutto la RESTRIZIONE ALL'ATTACCO: una Traiettoria
  e' immune finche' il segmento bersaglio non ha un Contatto o delle
  Informazioni, una Stazione no. Salvataggio compreso. 43 verifiche in
  `tests/unit/test_stealth.gd`.
  Chiusa anche una promessa vecchia: il commento di `GameState.triggers_info`
  elencava da sempre quattro cause di RB p.21 e ne implementava tre, perche' la
  quarta - "forza Furtiva" - non aveva una pedina. Adesso ce l'ha.
  **Il piazzamento dallo schieramento c'e'**: `Scenario.stealth_forces` passa
  nello stato come ogni altra pedina, e BL3 schiera il suo Sommergibile
  britannico in (5,1), letto sull'illustrazione di p.12.
  **La procedura Mine di N1 c'e'** (`Stealth.lay_mines`, fascicolo p.17): i tre
  bersagli sono nel dato dello scenario - Narvik/Vestfjorden (5,-2), Bud (5,2),
  Andalsnes (6,1) - e la regola impone una TF CON UN CONVOGLIO, un solo marker
  per esagono, lo Scorrere del Tempo con la TF che NON viene rimossa, e la
  Reazione Norvegese sul solo Narvik.
  **FATTI da allora**: il Completamento in un esagono di Norvegia (p.16) che
  innesca la posa; le quattro Tabelle di Reazione Norvegese (pp.19, 24, 27, 34),
  collegate a tutti e due i cicli; il Sommergibile di N3, che si e' rivelato
  **britannico** e sta in (6,-1), misurato sull'illustrazione; e il collegamento
  all'azione `STEALTH_ATTACK`, che ora una forza Furtiva puo' eseguire davvero.
  **Restano**: i due marker U-Boat di A2, di cui il motore tiene solo il
  conteggio; il percorso del GIOCATORE per l'Attacco Furtivo in `ui/main.gd`,
  che passa ancora una Task Force; e il disegno della pedina nella GUI.
  Una lacuna dichiarata dentro il nucleo: le Informazioni stanno sui SEGMENTI,
  quindi una Ricognizione su una TF nemica che e' Stazione le dichiara invece
  di assegnarle.

- [ ] Trascrivere e modellare le Basi Aeree: posizione, controllo, periodo di
  attivita', raggio e interazione con Attacco Aereo/Informazioni.
- [ ] Modellare le forze Furtive permanenti che causano Informazioni, solo
  dopo averne trascritto posizione e condizioni.
- [ ] Calibrare separatamente i reticoli degli inserti Mare del Nord e Mare di
  Norvegia. Le immagini oggi sono riferimenti visivi, non superfici giocabili.
- [x] Testo stampato di tutti gli 11 Comandanti trascritto da RB p.10 a 300 dpi
  in `LeaderRules.EFFECTS`: la scheda TF mostra la condizione vera e non un
  riassunto. Trovato un refuso nella traduzione italiana - la voce Forbes
  ripete "la TF di Marschall" - dichiarato in `FORBES_TRANSLATION_NOTE` invece
  di essere ricopiato nel codice. Corretto anche il nome dell'azione: il
  regolamento stampa **Passare Tutto**, l'app diceva "Passare Tutti".
- [ ] **Forbes e Marschall**: "dopo aver tirato uno o piu' dadi durante
  un'Azione o Battaglia potete sostituire uno dei numeri con un 6". E' un
  beneficio REATTIVO e per questo non e' ancora offerto: `ActionEngine.resolve`
  tira e legge la tabella in un colpo solo, quindi va spezzato in tiro +
  lettura (oppure ricalcolata la riga con `lookup`) e va aggiunta l'offerta fra
  la risoluzione e l'applicazione dei risultati. La variante su Meteo e
  Iniziativa tocca anche `Initiative`, e vincola la TF del Comandante a essere
  designata nell'Azione successiva.
- [ ] Completare la schermata di Debriefing per condizioni oggi elencate ma da
  spuntare a mano; non assegnare automaticamente dati non modellati.
- [x] **Come finisce e come si vince, scritto nell'app**: il briefing rimandava
  al fascicolo ("Vedi le istruzioni Fine dello scenario nel file solo e nel
  fascicolo"), cioe' diceva al giocatore di andare a leggere altrove proprio la
  cosa che stava chiedendo. Adesso `Scenario.printed_rules_text()` costruisce le
  due sezioni dal dato di vittoria: la condizione di fine STAMPATA in inglese,
  come l'app la applica, la pagina da cui viene, e la Tabella dell'Esito con
  tutte le righe e i loro punteggi. Le voci a punti si stampano una per una,
  marcate `[spunta a mano]` quando il motore non le valuta, cosi' il giocatore
  sa in anticipo che cosa dovra' spuntare con `Shift+V`.
  Nel percorso c'era un difetto di stampa: `str()` su un numero JSON dava
  `10.0`, e la soglia di una tabella di Esito e' un punteggio, non una misura.
- [x] **Elenco degli scenari raggruppato**: la schermata iniziale era una lista
  unica di 36 voci in cui un solitario e uno scenario a due giocatori si
  distinguevano solo dal nome. Adesso ci sono quattro gruppi con l'intestazione
  non selezionabile e il conteggio: SOLITARIO (15), DUE GIOCATORI - Operazioni
  (9), DUE GIOCATORI - Battaglie (12), ALTRO. `_ids` tiene una stringa vuota
  sulle righe di intestazione, cosi' l'indice della lista e quello dello
  scenario non possono divergere - era il modo naturale di sbagliare qui.
- [x] **Le Tabelle dell'Esito di tutti e quindici i solitari sono trascritte.**
  Erano dodici file con righe segnaposto (`"Testo completo della riga nel campo
  raw_victory_text"`) e un unico premio finto (`"Calcolare i VP dalle tabelle
  stampate..."`); adesso sono zero. Ogni tabella e' stata letta sulla PAGINA
  RENDERIZZATA a 200-260 dpi, mai sul testo estratto.
  Due tabelle su quindici non sono una colonna di soglie, e il motore adesso
  sa leggerle:
  - **N1** e' DUE tabelle affiancate, scelte non dal punteggio ma dalla
    Reazione Norvegese: 8+/1-7/-4..0/-5 senza reazione adirata, 6+/1-5/0 con.
    La reazione si tirava gia' e poi si dimenticava; `Norway.apply_reaction`
    ora scrive `debriefing_norwegian_reaction` in `solo_counters`.
  - **N5** e' a DUE assi: dentro la riga di VP si cerca la banda di Punti
    Rinforzo spesi. Gli RP li conta `Reorganize.attempt_reinforcement` (una
    nave = 1 RP, fascicolo p.33), e stanno nel salvataggio.
  Il meccanismo generale sta in `Victory.debriefing_row(score, flags)`: una
  riga puo' portare un `when`, o un valore da uguagliare o una banda `{min,max}`.
  Trascritto anche il costo in VP delle navi di A2 (sette navi per sei colonne,
  p.65) e stampato nel briefing: e' la scelta piu' importante di quello
  scenario e si faceva alla cieca.
- [ ] Le voci a punti dei quindici Esiti restano tutte `manual: true`. Il
  motore vede Colpi, danni e affondamenti, ma non sa dov'e' un marker Mine ne'
  quale nave e' "ogni" nave della riga; assegnarne meta' in automatico darebbe
  un totale che sembra completo e non lo e'. Automatizzare le righe che il
  motore SA valutare e' un lavoro a se', e va fatto tutto o niente per riga.

## P1 - Battaglia avanzata

- [x] **Scelta Plancia**: chi ha la Plancia sceglie ogni Round fra rinunciare
  al Fuoco e restare Ferma, e la scelta si fa nella fase dell'Attitudine perche'
  viene prima del Fuoco. `P` rinuncia, `M` ferma; finche' resta da fare, il
  Round non prosegue. Chi resta Fermo e' Fermo DAVVERO - bersaglio con +3 - e la
  scelta vale un Round solo, se no la Plancia sarebbe un affondamento lento.
- [x] **Controllo avversario per Timone Fuori Uso**: si tira a ogni Attitudine
  e a ogni Manovra, e con DISPARI la nave la comanda l'avversario
  (`Battle.controller_side`). Il tiro si fa quando la fase si APRE, una volta
  sola: il giocatore deve sapere chi comanda che cosa mentre sceglie, e rifarlo
  a ogni disegno darebbe una nave che cambia padrone ogni fotogramma.
  Nel solitario il vincolo si fa rispettare; a due giocatori allo stesso tavolo
  resta scritto nel registro, perche' li' comandano tutti e due.
- [x] **I tre usi del segnalino Confusione**: nel Fuoco sposta un Colpo o un
  Effetto fra due navi PROPRIE, nella Manovra e nell'Attitudine comanda una nave
  NEMICA. Non sono tre pulsanti ma una voce sola (`K`) che cambia etichetta con
  la fase, perche' e' lo stesso jolly in tre momenti. Il motore ricorda ora
  QUALE nave nemica il segnalino lascia comandare: prima il permesso valeva per
  tutte.
- [x] **Divisione del fuoco in Acquisizione**: `Battle.set_split_fire()`
  distribuisce il Valore dei Cannoni fra due bersagli DIVERSI, le parti devono
  sommare al valore intero, e chi divide **perde la colonna Acquisizione** -
  e' il prezzo stampato. **Si dichiara dalla vista**: `D` apre la divisione
  sulla nave selezionata, si cliccano i due bersagli, `D` cicla la ripartizione
  dei cannoni e `Z` conferma. Il ciclo va da 1 a gv-1, quindi non offre mai zero
  cannoni a un bersaglio - il motore una parte nulla la accetterebbe, perche' il
  fascicolo non la vieta, ma l'interfaccia non la propone.
- [x] **MS12 come struttura in tre parti**: `core/rules/ms12.gd` e
  `core/data/ms12.json` trascrivono p.51 - tre Parti di due Round, il tiro 2d6
  delle Forze coi suoi due modificatori, le tre composizioni, l'attitudine
  imposta alla Forza C, e la regola di chi puo' restare fuori (solo se
  AZZOPPATO, mai il Convoglio ne' lo Squadrone DD). Le navi che tornano da una
  Parte sono le STESSE, col loro danno addosso.
  **E' collegato alla vista**: aprendo MS12 il tedesco sceglie l'attitudine
  dello Scharnhorst PRIMA del tiro delle Forze - la sola informazione nascosta
  dello scenario - poi si tira, si gioca la Parte di due Round, e alla sua fine
  la successiva si apre da sola portandosi dietro le navi col loro danno. MS12
  usa le Regole Avanzate anche se la partita e' cominciata con le base, perche'
  la sua pagina le prescrive, e il registro lo dice.
  La prova di fumo `tools/smoke_ms12.gd` apre il gioco vero e pretende tre
  Parti di due Round: **verificata rompendola di proposito**, togliendo il
  passaggio alla Parte successiva.
- [x] **Audit visivo della Battaglia avanzata**: `tools/audit_battle_visual.gd`
  percorre una Battaglia intera, fotografa ogni fase di ogni Round e stampa
  accanto a ogni scatto lo stato che il motore aveva in quel momento - se
  immagine e stato divergono, si vede subito quale dei due sbaglia. Guardando i
  31 scatti sono usciti **cinque difetti veri, tutti corretti**: il quarto
  pulsante finiva fuori dallo schermo (regressione dei comandi avanzati appena
  aggiunti), le etichette del raggio si sovrapponevano sulle linee di fuoco che
  si incrociano, il badge dei Colpi copriva il Valore dei Cannoni, lo sfondo
  della Battaglia lasciava trasparire la mappa nonostante il suo commento
  dicesse il contrario, e i numeri sui segnalini del Round erano bianchi su una
  pedina gia' scritta in bianco.
  Una cosa che SEMBRAVA un difetto e non lo era, verificata nel codice prima di
  segnalarla: le pedine britanniche appaiono ruotate e quelle tedesche no, ma e'
  la convenzione dell'attitudine - chi e' in Acquisizione resta dritto.
  **Sesto difetto, segnalato dall'utente**: il bordo giallo di selezione restava
  ORIZZONTALE attorno a una pedina ruotata, perche' veniva disegnato dopo che la
  trasformazione era stata annullata. Adesso e' dentro la stessa rotazione della
  pedina.
  **Resta** l'audit delle situazioni che una partita automatica non produce:
  Fumo, Inseguimento, Disingaggio e i tre usi della Confusione vanno guardati
  giocando a mano.
- [ ] Verificare in solitario che il bot controlli soltanto le proprie navi e
  prenda ogni decisione di battaglia senza input umano.

## P1 - Revisione a due giocatori

- [ ] Giocare il Tutorial dall'inizio alla fine confrontando ogni passo con
  `(3) Atlantic Chase Tutorial ITA.pdf`.
- [ ] Simulare almeno una Operazione completa a due giocatori.
- [ ] Verificare che ogni parte possa selezionare e agire solo quando ha
  l'Iniziativa, senza restrizioni introdotte dal bot solitario.
- [ ] Verificare tutte e nove le Azioni, incluse Coordinatrice, Supporto Aereo,
  Segnalazione, Riorganizzazione e Completamento.
- [ ] Verificare la sequenza completa dopo Battaglia: Stazioni, Contatto,
  Manovre Evasive, perdite, Iniziativa e Meteo.
- [ ] Verificare i 22 setup e i quattro modelli di vittoria con uno script di
  audit, non soltanto caricandoli.

## P2 - GUI, accessibilita' e diagnostica

- [ ] Mantenere mappa, azioni, stato, scheda TF e Registro in regioni che non
  si sovrappongono.
- [ ] Rendere ogni procedura bot collassabile singolarmente e mantenere
  selezionabili/copiabili Registro e stato.
- [ ] Mostrare sempre l'azione effettiva del bot in evidenza, separata dai
  calcoli tecnici.
- [x] Verificare layout a 1280x720, 1600x900, 1920x1080: **fatto**, con
  `godot --resolution WxH --path . --script res://tools/screenshot.gd` e la
  prova di fumo del workspace a ciascuna delle tre. Verdi tutte e tre, e gli
  screenshot mostrano barra, mappa, Registro, stato e scheda TF interi. Resta
  da provare un **viewport stretto** (finestra molto piu' alta che larga), che
  e' il caso che il rapporto d'aspetto puo' rompere davvero.
  **HA GIA' UNA MISURA, e oggi fa fallire `smoke_map_workspace.gd`**:
  `project.godot` chiede 1600x1000, ma se lo schermo concede meno - qui un
  rettangolo utilizzabile di 1920x980 - Godot riduce la finestra a 1600x947 e la
  fascia inferiore sfora di circa 53 px. **Non e' una regressione**: si riproduce
  identico al commit 4aa1ee6, cioe' prima del lavoro sulle procedure solitarie.
  Il layout della fascia inferiore assume di ricevere l'altezza richiesta.
- [ ] Verificare che i marker GMT siano uno per traccia dove previsto e che
  seguano valore, lato, inclinazione e salvataggio.
- [x] **Debriefing con le condizioni manuali spuntabili**: `V` mostra le righe
  che il motore non puo' valutare da solo con la loro spunta e il loro
  sottototale, `Shift+V` le spunta. Una riga spuntata entra DAVVERO nel
  punteggio (`Victory.manual_claimed_points`) e la spunta sta nel salvataggio,
  se no il Debriefing di una partita ripresa darebbe un numero diverso. La
  distinzione che il TODO chiedeva e' mantenuta: una riga non spuntata non e'
  una riga falsa, e il pannello scrive quante ne restano da guardare - un
  punteggio incompleto si vede invece di sembrare finito.

- [x] **Lo spazio di lavoro ha due disposizioni, scelte dalla forma della mappa.**
  Segnalato dall'utente su tre punti insieme: la fascia inferiore era alta 328
  px e quasi vuota; la colonna di sinistra offriva SEMPRE due mappe inserto in
  due linguette, comprese quelle che lo scenario non tocca; e le mappe inserto
  sono verticali, quindi stavano male in un riquadro orizzontale.
  - **Mappa Operazionale**: mappa al centro, registro a destra, pannelli in una
    fascia sotto. La fascia adesso e' 232 px invece di 328, e la colonna delle
    mappe inserto non c'e' piu': la mappa parte da x=12 e guadagna 298 px.
  - **Mappa inserto** (BL3, N1, N2, N3, N5): la superficie di gioco prende la
    colonna di sinistra, alta quanto la finestra e larga quanto vuole la sua
    proporzione; i pannelli si prendono il centro liberato, IMPILATI. La mappa
    di N2 passa da 430x600 con due fasce nere ai lati a 684x886 piena.
  - I bordi si trascinano: tre maniglie, quali esistono dipende dalla
    disposizione. `_apply_layout()` e' l'unico posto che decide dov'e' un bordo
    - prima erano cinque controlli con i loro offset scritti a mano.
  Tre difetti pagati per strada, tutti e tre adesso sorvegliati da
  `smoke_inset_map.gd`: la fascia sbordava sotto la finestra (un contenitore
  non scende sotto il minimo dei suoi contenuti, e chiederglielo non lo
  rimpicciolisce); la scheda della Task Force finiva SOPRA il registro (che in
  quella disposizione e' alto quanto la finestra); e la camera inquadrava il
  riquadro di PRIMA, lasciando la mappa piccola proprio dove spostarla doveva
  ingrandirla.
- [x] **Le maniglie dei bordi non devono coprire la mappa.** Difetto mio,
  segnalato dall'utente subito dopo: con la mappa non si poteva piu' fare
  niente - niente selezione delle Task Force, niente zoom, niente
  trascinamento, e la freccetta di ridimensionamento dappertutto - mentre i
  menu rispondevano. Le tre maniglie erano ancorate con `PRESET_FULL_RECT`,
  dove le ancore sono (0,0,1,1): li' `offset_left = -410` non vuol dire "410
  dal bordo destro", vuol dire x = -410. `GrabLog` risultava un pannello
  1608x644 steso sopra la mappa, e siccome sono `MOUSE_FILTER_STOP` si
  mangiava ogni clic. Adesso ogni maniglia e' ancorata al bordo che segue, e
  sono tre strisce da 8 px.
  La prova di fumo non lo vedeva, e adesso lo vede: il clic che gia' c'era
  entra nel SubViewport per via diretta, saltando la HUD, quindi non poteva
  accorgersi di un pannello che copriva la mappa. Il controllo nuovo e'
  geometrico - nessuna maniglia visibile puo' essere piu' grande di un bordo
  ne' contenere il centro della mappa - ed e' stato verificato rimettendo
  l'ancora sbagliata: fallisce con "la maniglia GrabLog e' un pannello
  1608x644, non un bordo".
- [x] **La Reazione Aggressiva Norvegese si conta.** Trovata leggendo il
  registro di una partita a N3 mandato dall'utente: a OGNI tiro della Tabella
  delle Azioni - dodici volte in trentacinque mosse - stampava "Dato non
  modellato, modificatore non applicato: ogni Reazione Aggressiva Norvegese".
  Il fascicolo la chiede in due posti: e' il -1 della Tabella di Azione
  Britannica di N2/N3/N4 ("each Aggressive Reaction") ed e' la condizione della
  riga 'Operazione a sud secondo i piani' dell'Esito di N3 ("se non c'e' stata
  nessuna Reazione Aggressiva... sali di una riga"). Quali risultati siano
  Aggressivi non si indovina: la legenda del dato li marca uno per uno, e
  `Norway.apply_reaction` li somma in `solo_counters` - quindi nel salvataggio.
  Il conto e' UNO solo, letto da tutti e due: contarlo due volte in due posti
  vuol dire vederlo divergere.
- [x] **Portare in Battaglia punta all'esagono piu' VICINO, non alla testa.**
  Segnalato dall'utente su una partita a BL2, guardando la mappa: una TF
  tedesca nel Mare di Norvegia ha aggiunto UNDICI segmenti per attraversare
  l'Atlantico e raggiungere il capo occidentale di un Convoglio britannico che
  le passava accanto a est. `_route_toward_tf` puntava a `_anchor_hex()`, cioe'
  `end_hex(0)`: la testa della Traiettoria bersaglio, sempre, comunque fosse
  orientata. Il fascicolo lo scrive a lettere: "The selected TF will target the
  NEAREST hex while avoiding intel triggers if possible" (BL2, p.11), e tutte e
  ventiquattro le procedure che passano di li' dicono "intercetta / porta in
  Battaglia la piu' VICINA" - nessuna chiede un capo in particolare.
  La distanza si misura dai due capi della TF Attiva, che sono i punti da cui
  puo' allungarsi; a parita' vince (q, r) minore, perche' senza un criterio
  stabile la stessa partita con lo stesso seme puo' scegliere un bersaglio
  diverso. I quindici replay non cambiano di una riga.
- [x] **Il registro dice che cosa e' successo; il resto sta chiuso.** Chiesto
  dall'utente: "nel log devono rimanere le cose importanti, quelle di servizio
  oppure ovvie rimangono collassate e al bisogno posso ispezionarle".
  - **Le procedure del bot** mostravano "AZIONE EFFETTIVA - Procedura conclusa;
    consulta i dettagli" quando la riga di riassunto non c'era: si diceva al
    giocatore di aprire un pannello per sapere una cosa che il pannello aveva
    gia' sotto gli occhi. Adesso, in mancanza del riassunto, si stampa
    l'ultima riga che racconta un'AZIONE - scartando tiro, lettura della
    tabella e testo della procedura, che dicono come ci si e' arrivati.
  - **Le righe di servizio** - "clicca un segmento terminale", "selezionata la
    tale TF", "trascina dalla Task Force" - sono richieste all'utente e
    conferme di quello che ha appena fatto lui. Ripetute a ogni clic
    seppellivano le righe che contano. Adesso le consecutive si raccolgono in
    una riga sola, "N righe di servizio (clicca per vederle)", e si aprono
    cliccandola. Nessuna riga viene buttata via, e `Copia tutto` continua a
    copiare il registro intero.
  Il criterio editoriale sta in un elenco unico (`SERVICE_MARKERS`) invece che
  sparso nei chiamanti: e' una decisione su che cosa merita una riga, e si
  legge tutta insieme. `smoke_solo_flow.gd` pretende che nessuna riga di
  servizio si veda senza averla aperta - verificato rendendole visibili di
  proposito, e la prova fallisce.
- [x] **BL3 identifica la TF britannica.** Segnalato dall'utente su una
  partita a BL3: una Schermaglia vinta dava diritto a una Battaglia Limitata e
  la Battaglia non si apriva. La tabella "Identify British TF" (p.14) era
  trascritta nel dato, ma `apply_table_result` smistava solo BL1 e BL2: per
  BL3 rispondeva "trascritta ma non ha ancora effetti automatici", la TF
  restava ignota e senza navi da portare sulla Mappa di Battaglia.
  Tre cose che quella pagina dice e le altre due non dicono:
  - le celle col Convoglio usano " + " invece di "/" ("CL + Convoglio"), e
    contarne uno solo lasciava la cella senza nessuna nave;
  - "A BB result must be either the Nelson or Rodney. If already in play, or if
    they were in play, select any slow BB": e' l'OPPOSTO di N2 e N3, che quelle
    due le escludono. Stessa sigla, due scenari, due regole;
  - serviva la CV, che c'e' nel ruolino ma non era in nessun elenco di tipo.
  La clausola "if the British TF is instructed by the Action Table result to
  Bring to Battle, replace 'Convoy' with a BB" si applica solo col
  contrassegno `bl3_bring_to_battle`, e quando non c'e' il registro lo dice:
  aprendo la Battaglia il giocatore tedesco, quell'istruzione non c'e' stata.
- [ ] **La suite si blocca se un test del solitario e' troppo grosso.** Mi e'
  successo due volte scrivendo i test di questa sessione: un metodo con un
  ciclo su dieci casi, ognuno con `GameState` e grafo, e `run_tests.gd` resta
  fermo senza stampare niente - nemmeno la prima suite. Lo stesso codice in
  uno script a se' gira in due secondi, e il test ridotto passa. Non l'ho
  capito, e finche' non lo si capisce e' una trappola che costa mezz'ora ogni
  volta: chi la incontra tenga i test del solitario corti e verifichi il resto
  con uno script usa-e-getta.
- [ ] **Uno scenario che usa DUE mappe insieme non e' supportato.** L'utente lo
  ha chiesto ("se lo scenario ne usa due allora si devono vedere entrambe") e
  oggi non serve a nessuno: dei ventidue scenari, cinque usano un inserto e
  ognuno ne usa uno solo. Servirebbero due superfici di gioco vive - due
  SubViewport, due tabelloni, due camere - e il grafo e' uno. Non e' un
  ritocco di layout: e' una modifica al motore, e va decisa quando esistera'
  uno scenario che la chiede.

## P2 - Distribuzione e manutenzione

- [ ] Provare davvero gesti e layout su iPad; l'export web da solo non basta.
- [ ] Decidere con il proprietario come gestire il repository pubblico che
  contiene materiale GMT e traduzioni per solo uso personale.
- [ ] Prima di ogni release macOS: test, smoke base/avanzato, build, firma,
  quarantena, installazione manuale e avvio della copia in `/Applications`.
- [ ] Aggiornare i conteggi in README, STATO, PASSAGGIO e CLAUDE quando cambia
  la baseline.

## Milestone di consegna

| Milestone | Obiettivo | Criterio di uscita |
|---|---|---|
| ~~R0 Baseline~~ | ~~harness e replay affidabili~~ | **fatta**: test + smoke + replay BL1/BL2 ripetibili |
| R1 BL | chiudere BL1, BL2, BL3 | tre scenari end-to-end, inserto BL3 calibrato |
| R2 Norvegia | chiudere N1-N6 | zero segnaposto N, Mine e Basi modellate e testate |
| R3 Atlantico | chiudere B1-B4 | zero segnaposto B, replay per ogni scenario |
| R4 Artico | chiudere A1-A2 | zero segnaposto A, U-Boat e regole artiche verificate (fini stampate: fatte) |
| R5 Battaglia | chiudere Avanzate e MS12 | tutte le scelte GUI e bot testate |
| R6 Due giocatori | audit Tutorial + Operazione | replay completi senza regressioni solo |
| R7 Prodotto | Debriefing, layout, iPad | release candidate usabile e documentata |

## Comandi utili

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tools/audit_solo.gd
godot --headless --path . --script res://tools/simulate_flow.gd
godot --headless --path . --script res://tools/replay_solo.gd
godot --headless --path . --script res://tools/replay_solo.gd -- BL1 42
godot --path . --script res://tools/smoke_map_workspace.gd
godot --path . --script res://tools/smoke_ui.gd
godot --path . --script res://tools/smoke_ui.gd -- adv
sh tools/build_macos.sh
```
