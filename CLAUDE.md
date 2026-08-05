# Atlantic Chase - istruzioni per Claude

Questo repository implementa Atlantic Chase in Godot 4.7 / GDScript. La
revisione deve continuare dal commit `bf65a2b` o successivo.

## Ordine di lettura obbligatorio

1. `PASSAGGIO_DI_CONSEGNE.md`, per intero: principi e trappole gia' pagate.
2. `TODO_REVISIONE.md`: backlog e milestone autorevoli da questo passaggio.
3. `STATO.md`: dettaglio storico e stato delle funzionalita'. Le sezioni in
   fondo sono cronologia e possono descrivere lacune gia' chiuse; in caso di
   conflitto prevalgono `TODO_REVISIONE.md` e la parte iniziale di `STATO.md`.
4. Il regolamento pertinente prima di modificare una regola. Per il solitario
   usare `docs/regolamento/AC_Solo_scenarios_2022.pdf`, seconda edizione.

## Vincoli non negoziabili

- Non indovinare una regola. Un dato assente resta un buco dichiarato nel dato,
  nel log e nei test.
- Tutto `core/` resta GDScript puro `RefCounted`, senza `Node` e senza
  dipendenze dalla GUI.
- Leggere le tabelle dalle pagine renderizzate a risoluzione nativa, non dal
  testo estratto dal PDF.
- Non modificare o rigenerare dati non collegati al compito corrente.
- Non cancellare modifiche locali non proprie.
- Quando si aggiunge una verifica, aggiornare `EXPECTED` in
  `tests/run_tests.gd`. Un errore runtime GDScript puo' troncare un test senza
  far fallire da solo la suite.

## Baseline obbligatoria

Prima di una modifica e prima di ogni commit eseguire:

```bash
godot --headless --path . --script res://tests/run_tests.gd
godot --path . --script res://tools/smoke_map_workspace.gd
godot --path . --script res://tools/smoke_ui.gd
godot --path . --script res://tools/smoke_ui.gd -- adv
godot --path . --script res://tools/smoke_solo_flow.gd
godot --path . --script res://tools/smoke_solo_flow.gd -- BL1
godot --path . --script res://tools/smoke_inset_map.gd
godot --path . --script res://tools/smoke_ms12.gd
```

Per guardare la Battaglia invece che misurarla:

```bash
godot --path . --script res://tools/audit_battle_visual.gd -- reports/battaglia
```

Percorre una Battaglia avanzata intera, salva un PNG per fase e stampa accanto
a ogni scatto lo stato del motore. Non giudica: serve a mettere l'immagine e lo
stato uno accanto all'altro. Cinque difetti visivi sono usciti cosi'.

Baseline corrente: **3697 verifiche, 21 suite** (era 2570 su 17 prima della
suite `test_replay.gd`). Il totale non puo' scendere senza una rimozione
intenzionale di test spiegata nel commit.

Per il solitario eseguire anche:

```bash
godot --headless --path . --script res://tools/audit_solo.gd
godot --headless --path . --script res://tools/simulate_flow.gd
godot --headless --path . --script res://tools/replay_solo.gd
```

`replay_solo.gd` gioca tutti e quindici gli scenari solitari dall'inizio alla
fine con `SoloRunner` e distingue tre esiti: `OK` (fine stampata), `STALLO`
(lacuna dichiarata del fascicolo) e `FALLITO` (il ciclo non converge: un
difetto). Al passaggio: **quindici `OK`: tutti** - i dieci sulla Mappa Operazionale piu'
i dieci sulla Mappa Operazionale e i cinque sugli inserti - e nessun `SALTATO`, gli scenari inserto a cui manca lo
schieramento trascritto.

`audit_solo.gd` verde non significa completo: al passaggio stampa 93 caselle
uniche, 0 procedure Azione segnaposto, 0 buchi dichiarati e 0 blocchi.

Per le mappe inserto:

```bash
tools/.venv/bin/python tools/fit_inset_lattice.py --check
```

Rifa' la misura del reticolo dei due inserti e la confronta con
`core/data/map_insets.json`. Per rigenerare esagoni e porti:

```bash
tools/.venv/bin/python tools/build_inset_graph.py --overlay-dir reports
```

Scrive `core/data/inset_graphs.json` e un overlay per mappa da guardare: il
verde e' giocabile, il rosso no, il magenta sono i porti e il verde acqua i
Punti di Interesse, l'arancione le caselle fuori mappa con la riga verso i loro
esagoni, il blu le frecce "non adiacente" con la coppia scritta sopra, il
cerchio rosso o viola le basi aeree.
Per verificare il grafo contro il fascicolo:

```bash
tools/.venv/bin/python tools/validate_inset_setups.py
```

Legge i segmenti di Traiettoria disegnati sulle illustrazioni di schieramento
dei cinque scenari e controlla che cadano tutti in esagoni del grafo. Esce con
codice 1 se qualcuno cade fuori: sarebbe un difetto del grafo, non
dell'illustrazione.

**Il dato di mappa degli inserti e' completo e verificato, il motore lo carica e
l'interfaccia lo disegna**: aprendo uno dei cinque scenari inserto, la mappa
inserto diventa la superficie di gioco al posto della Mappa Operazionale.
`smoke_inset_map.gd` verifica che tabellone, stato, Traiettorie e camera
cambino tutti insieme - se uno solo restasse indietro non si vedrebbe un
errore, si vedrebbe una partita sulle coordinate sbagliate.
In codice: `MapGraph.load_inset("map_north_sea")` o `"map_norwegian_sea"`.
Attenzione a due convenzioni del dato inserto, che il caricatore traduce e i
test sorvegliano: `theta_deg` e' l'angolo dei VERTICI (la mappa grande usa la
direzione di BASE, 30 gradi piu' avanti) e le `(q,r)` sono ribasate
sull'angolo della cornice, non sulla cella (0,0) del fit.
**Tutti e cinque gli scenari inserto si giocano**, e con loro tutti e quindici
i solitari chiudono su una condizione stampata. Restano lacune DENTRO gli
scenari, dichiarate nei loro `setup_notes`: Mine e altre forze Furtive, Reazione
Norvegese, Completamenti in Norvegia, Punti Rinforzo di N5.

## Metodo di revisione

Per ogni regola o scenario:

1. citare fascicolo e pagina nel dato, codice o test;
2. trascrivere setup e tabelle senza deduzioni;
3. separare la regola GMT dalla policy decisionale del bot;
4. forzare nei test ogni tiro e ogni ramo della tabella;
5. simulare almeno una sequenza completa, inclusi Iniziativa, Scorrere del
   Tempo, Completamento, Battaglia e fine scenario quando pertinenti;
6. verificare anche salvataggio/ricarica per ogni nuovo stato persistente;
7. aggiornare `TODO_REVISIONE.md`, `STATO.md` e i conteggi dei test.

Una procedura non e' completa se il JSON contiene il testo ma `SoloAI` applica
solo una policy generica o un Passare. Il bot deve scegliere realmente TF,
rotta, bersaglio, reazione e continuazioni prescritte.

## Build macOS

Dopo ogni commit che modifica il gioco:

```bash
sh tools/build_macos.sh
```

L'app installata non si aggiorna da sola. La build e' in
`build/macos/Atlantic Chase.app`; per la copia di prova va sostituita
manualmente in `/Applications/Atlantic Chase.app`.

## Primo lavoro consigliato

**Tutti e quindici gli scenari solitari si giocano** e chiudono su una
condizione di fine STAMPATA, con la pagina citata nel dato. Il replay stampa
quindici `OK` e nessun `SALTATO`. Non c'e' piu' uno scenario da far partire.

Il prossimo lavoro e' uno dei due, e sono mestieri diversi che conviene NON
mescolare:

**A. ~~Le procedure segnaposto delle Tabelle Azione~~ - CHIUSE.** Erano 42 su
93 caselle uniche; adesso `audit_solo.gd` stampa zero. L'unico buco che resta e'
il risultato Mine/Base Aerea di N4, che chiede una forza Furtiva Mine britannica
e una Base Aerea come FONTE di un Attacco Aereo (RB p.27): `ActionEngine`
pretende una TF Attiva con una CV integra e non sa partire da un esagono.
Quello e' il prossimo pezzo di regola, se si vuole chiudere anche quel buco.

**B. ~~Chiudere la duplicazione GUI/SoloRunner~~ - in gran parte CHIUSA.** Le
regole di sequenza stanno in `SoloSequence`, e adesso anche l'ORDINE dei passi:
`SoloSequence.steps_for` lo descrive come dato e i due cicli lo camminano,
sincrono il runner e con gli `await` la vista. Restano rispecchiati due punti
soli, e di proposito: il tiro della Tabella, che diverge su come si chiedono i
modificatori, e la risoluzione dell'azione, che nella vista apre la Mappa di
Battaglia. Chi ci mette mano legga prima i due commenti "Mirror headless" in
`solo_runner.gd`.

Finche' B non e' chiusa, una modifica alla sequenza del turno del bot va fatta
in tutti e due i posti: `solo_runner.gd` porta tre commenti "Mirror headless di
`ui/main.gd::...`" che dicono esattamente quali funzioni si rispecchiano.
Leggerli PRIMA di cominciare un refactor: in questa sessione li ho letti dopo, e
quattro passi sono finiti sulla meta' sbagliata.

Il paracadute di entrambi i lavori e' `tests/unit/test_replay.gd`, che confronta
la TRASCRIZIONE dei replay riga per riga a parita' di seme. Se dopo una modifica
un seme da' una partita diversa, la modifica ha cambiato il gioco - e va deciso
di proposito, non scoperto dopo.
