# TODO della revisione

Aggiornato dopo la chiusura di **R0** (3 agosto 2026). Baseline: **2957
verifiche su 18 suite**.

Questo e' il backlog autorevole per continuare la revisione. `STATO.md`
contiene anche una lunga cronologia: e' utile per capire le decisioni, ma le
vecchie sezioni "Cosa manca" non devono riaprire lavori gia' completati.

## Stato sintetico

| Area | Stato reale | Prossima verifica |
|---|---|---|
| Regole operative base | completa, testata | replay GUI a due giocatori |
| 22 scenari base/avanzati | dati, setup e vittoria presenti | audit end-to-end |
| Battaglia base | completa | regressioni GUI e bot solo |
| Battaglia avanzata | quasi completa | quattro scelte interattive e MS12 |
| Salvataggio/undo | completo | includere ogni nuovo stato solo |
| Solitario BL1 | procedure stampate tutte implementate | audit visivo a mano |
| Solitario BL2 | giocabile, replay end-to-end verde | automatizzare Forbes e Gensoul |
| Solitario BL3 | tabelle trascritte, non giocabile | calibrare Mappa Inserto Mare del Nord |
| Altri 12 solitari | setup e testo presenti, automazione parziale | sostituire i segnaposto scenario per scenario |
| GUI operativa | molto rielaborata | smoke test dei flussi mappa ancora insufficiente |
| iPad/web | esportabile | prova su dispositivo reale |

## P0 - Integrita' del progetto

- [ ] Mantenere sempre verdi i comandi della baseline in `CLAUDE.md`.
- [ ] Non consentire che il totale scenda sotto 2957 senza rimozione esplicita.
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
  **Resta, ed e' l'ultima cosa che blocca i cinque scenari**: un secondo
  `MapGraph` nel motore e il disegno dell'inserto come superficie di gioco
  nella GUI. Tutto il dato di mappa c'e'.
  **Otto esagoni sono marcati `needs_check`**: hanno terra e mare quasi in
  parti uguali, e il colore non basta a decidere. Gli esagoni scartati per un
  soffio restano scritti in `excluded_near_miss`, col motivo: nessuno sparisce
  in silenzio.
  **La verita' indipendente esiste**: le illustrazioni di schieramento del
  fascicolo (BL3 a p.12, e le pagine corrispondenti di N1, N2, N3, N5) mostrano
  i segmenti di Traiettoria iniziali disegnati SULL'INSERTO. Sono per l'inserto
  quello che le 238 pedine del modulo VASSAL sono state per la mappa grande: un
  campione contro cui validare, e va usato invece di posizioni scelte a mano.
- [ ] **N1 Operazione Wilfred**: 30 procedure testuali nel JSON; completare
  Azioni, Identificazione, porti, reazioni e setup.
- [ ] **N2 Operazione Weser (nord)**: 26 procedure testuali; modellare Mine o
  mantenere il buco esplicito finche' dati e pedine non sono verificati.
- [ ] **N3 Operazione Weser (sud)**: 11 procedure testuali.
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
- [ ] **N5 Meglio Tardi che Mai**: 11 procedure testuali, incluse Reazioni
  norvegesi e modificatori di completamento.
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
| finisce per condizione stampata | BL1, BL2, N4, N6, B1, B2, B3, B4, A1, A2 | niente: chiudere le procedure segnaposto |
| non giocabile, mappa inserto | BL3, N1, N2, N3, N5 | calibrare i reticoli inserto |

**Tutti e dieci gli scenari sulla Mappa Operazionale chiudono su una
condizione stampata.** Gli unici cinque che non si giocano sono i cinque
dell'inserto, e il lavoro che li sblocca e' uno solo: calibrare i due
reticoli.

## P0 - Sistemi mancanti al solitario

- [ ] Modellare Mine come stato puro in `core/`, con posizione, parte,
  piazzamento/rimozione, rendering, salvataggio e test.
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

## P1 - Battaglia avanzata

- [ ] Implementare la scelta Plancia: rinuncia al Fuoco oppure nave Ferma.
- [ ] Implementare il controllo avversario per Timone Fuori Uso.
- [ ] Esporre correttamente i tre usi del segnalino Confusione.
- [ ] Implementare la divisione del fuoco in Acquisizione.
- [ ] Implementare MS12 come struttura speciale in tre parti; non trattarlo
  come una singola Battaglia ordinaria.
- [ ] Audit visivo di attitudini, rotazione navi, Acquiring, Closing, Fog,
  Confusion, siluri, inseguimento e Disingaggio in tutti i Round.
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
- [ ] Verificare layout a 1280x720, 1600x900, 1920x1080 e viewport stretto;
  nessun pannello o pedina deve essere tagliato.
- [ ] Verificare che i marker GMT siano uno per traccia dove previsto e che
  seguano valore, lato, inclinazione e salvataggio.
- [ ] Migliorare il Debriefing con lista delle condizioni manuali e totale,
  mantenendo distinta una condizione falsa da un dato non disponibile.

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
