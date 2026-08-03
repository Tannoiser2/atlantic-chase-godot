# TODO della revisione

Aggiornato dopo la chiusura di **R0** (3 agosto 2026). Baseline: **2806
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
- [ ] Non consentire che il totale scenda sotto 2806 senza rimozione esplicita.
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
  pronto per quando l'inserto sara' calibrato. **Il lavoro vero e' uno solo:
  calibrare i due reticoli inserto**, e sblocca cinque scenari insieme.
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
- [ ] **B1 Operazione Berlino**: 22 procedure testuali.
- [ ] **B2 La Battaglia dell'Atlantico**: 10 procedure testuali.
- [ ] **B3 Operazione Reno**: 24 procedure testuali.
- [ ] **B4 Decisione sui Mari**: 12 procedure testuali.
- [ ] **A1 Convogli PQ**: 3 procedure testuali; la forza U-Boat iniziale e'
  ancora una nota perche' manca una pedina nave operazionale verificata.
- [ ] **A2 L'Ultima Battaglia**: 20 procedure testuali.

I numeri sopra contano tutte le stringhe `senza automatismi del motore` nei
rispettivi JSON. L'audit automatico conta solo quelle nelle Tabelle Azioni e
per questo riporta 82, non la somma dell'elenco.

### Che cosa dice oggi il replay, scenario per scenario

`godot --headless --path . --script res://tools/replay_solo.gd` gioca tutti e
quindici e distingue tre esiti. Non e' piu' "120 turni" per tutti: adesso ogni
riga dice che cosa manca.

| esito | scenari | che cosa serve |
|---|---|---|
| finisce per condizione stampata | BL1, BL2, N4, N6, B1, B3 | niente: chiudere le procedure segnaposto |
| non giocabile, mappa inserto | BL3, N1, N2, N3, N5 | calibrare i reticoli inserto |
| stallo dichiarato | B2, B4, A1 | il terzo Convoglio non entra mai: servono le procedure di rinforzo, oggi segnaposto |
| stallo dichiarato | A2 | lo schieramento si compra coi VP prima della prima azione (p.63): passaggio non modellato |

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
| R4 Artico | chiudere A1-A2 | zero segnaposto A, U-Boat e regole artiche verificate |
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
