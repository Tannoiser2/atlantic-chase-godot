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
```

Baseline corrente: **2957 verifiche, 18 suite** (era 2570 su 17 prima della
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
difetto). Al passaggio: dieci `OK` - tutti gli scenari sulla Mappa Operazionale
- e cinque `SALTATO`, i cinque della mappa inserto non calibrata.

`audit_solo.gd` verde non significa completo: al passaggio stampa 93 caselle
uniche, 42 procedure Azione segnaposto, 2 buchi dichiarati e 0 blocchi.

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
**Il dato di mappa degli inserti e' completo.** I cinque scenari inserto
restano dichiarati non giocabili per un motivo solo, ed e' codice: manca un
secondo `MapGraph` nel motore e il disegno dell'inserto nella GUI.

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

**R0 e' chiusa**: `core/rules/solo_runner.gd` gioca uno scenario solitario per
intero senza GUI, `tools/replay_solo.gd` lo esegue con semi fissi e
`tests/unit/test_replay.gd` verifica determinismo, terminazione, legalita' dei
Completamenti e salvataggio/ricarica.

Continuare da **R1**: audit pagina per pagina di BL1 e BL2, poi BL3.
Non lavorare in parallelo su tutti i JSON: rende impossibile capire quale
tabella abbia introdotto una regressione.

Attenzione a una duplicazione nota: `ui/main.gd` implementa la stessa sequenza
del ciclo solitario con le sue attese asincrone. Finche' non sara' riscritta
sopra `SoloRunner` (voce aperta in `TODO_REVISIONE.md`), una modifica alla
sequenza va fatta in tutti e due i posti.
