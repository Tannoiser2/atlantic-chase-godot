# TODO della revisione

Aggiornato al commit `bf65a2b` del 3 agosto 2026.

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
| Solitario BL1 | giocabile, policy dedicate | replay completo e confronto pagina per pagina |
| Solitario BL2 | giocabile, policy dedicate | replay completo; fine scenario appena corretta |
| Solitario BL3 | tabelle trascritte, non giocabile | calibrare Mappa Inserto Mare del Nord |
| Altri 12 solitari | setup e testo presenti, automazione parziale | sostituire i segnaposto scenario per scenario |
| GUI operativa | molto rielaborata | smoke test dei flussi mappa ancora insufficiente |
| iPad/web | esportabile | prova su dispositivo reale |

## P0 - Integrita' del progetto

- [ ] Mantenere sempre verdi i quattro comandi in `CLAUDE.md`.
- [ ] Non consentire che il totale scenda sotto 2570 senza rimozione esplicita.
- [ ] Estendere `tools/simulate_flow.gd` a replay deterministici completi di
  BL1 e BL2, non soltanto a una singola estrazione dalla Tabella Azioni.
- [ ] Aggiungere uno smoke test GUI del flusso operativo: selezione TF,
  dichiarazione Azione, scelta su mappa, Scorrere del Tempo, cambio
  Iniziativa, azione bot e ritorno al giocatore.
- [ ] Verificare che nessuna callback differita continui dopo `solo_ended`.
  Il bug BL2 corretto in `bf65a2b` e' il caso di regressione iniziale.

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
  Setup RV, Rifornimento, rotte, Raeder e policy B/F sono implementati; serve
  un replay deterministico completo fino al Debriefing.
- [ ] **BL2 Contain and Destroy**: audit finale pagina per pagina. Home Fleet,
  Convogli, Acque Neutrali, Pound/Forbes, Identificazione e procedure
  A/C/Convoglio/E/T/X sono implementate. Verificare che dopo la fine nessuna
  procedura resti accodata. Forbes e Gensoul hanno ancora effetti manuali.
- [ ] **BL3 Raiders of the North Sea**: calibrare il reticolo della Mappa
  Inserto del Mare del Nord e applicare lo setup. Le tabelle sono trascritte;
  non fingere coordinate sulla Mappa Operazionale.
- [ ] **N1 Operazione Wilfred**: 30 procedure testuali nel JSON; completare
  Azioni, Identificazione, porti, reazioni e setup.
- [ ] **N2 Operazione Weser (nord)**: 26 procedure testuali; modellare Mine o
  mantenere il buco esplicito finche' dati e pedine non sono verificati.
- [ ] **N3 Operazione Weser (sud)**: 11 procedure testuali.
- [ ] **N4 Operazione Weser (nord & sud)**: 6 procedure testuali; Mine/Base
  Aerea e' un buco dichiarato dall'audit.
- [ ] **N5 Meglio Tardi che Mai**: 11 procedure testuali, incluse Reazioni
  norvegesi e modificatori di completamento.
- [ ] **N6 Il Dilemma delle Operazioni**: 25 procedure testuali.
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

## P0 - Sistemi mancanti al solitario

- [ ] Modellare Mine come stato puro in `core/`, con posizione, parte,
  piazzamento/rimozione, rendering, salvataggio e test.
- [ ] Trascrivere e modellare le Basi Aeree: posizione, controllo, periodo di
  attivita', raggio e interazione con Attacco Aereo/Informazioni.
- [ ] Modellare le forze Furtive permanenti che causano Informazioni, solo
  dopo averne trascritto posizione e condizioni.
- [ ] Calibrare separatamente i reticoli degli inserti Mare del Nord e Mare di
  Norvegia. Le immagini oggi sono riferimenti visivi, non superfici giocabili.
- [ ] Automatizzare gli effetti dei comandanti ancora marcati manuali,
  iniziando da Forbes e Gensoul. Verificare il testo stampato prima del codice.
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
| R0 Baseline | harness e replay affidabili | test + smoke + replay BL1/BL2 ripetibili |
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
godot --path . --script res://tools/smoke_map_workspace.gd
godot --path . --script res://tools/smoke_ui.gd
godot --path . --script res://tools/smoke_ui.gd -- adv
sh tools/build_macos.sh
```
