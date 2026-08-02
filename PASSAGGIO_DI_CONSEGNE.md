# Passaggio di consegne

Documento per chi riprende il lavoro su questo progetto (Codex o altri).
Scritto il 2 agosto 2026. **Aggiornato all'ultimo commit della sessione.**

Leggi anche `README.md` (come è fatto) e `STATO.md` (stato per milestone).
Questo file dice **da dove ripartire e cosa non rifare**.

---

## 1. In una riga

Versione digitale di *Atlantic Chase* (GMT Games, 2020) in **Godot 4.7**,
GDScript. Motore di regole puro e testabile headless, interfaccia sopra.
**1756 verifiche su 16 suite, tutte verdi.** Repository `Tannoiser2/atlantic-chase-godot`, branch `master`.

```bash
godot --headless --path . --script res://tests/run_tests.gd   # 1756 verifiche
godot --path . --script res://tools/smoke_ui.gd               # prova di fumo GUI
sh tools/build_macos.sh                                       # app per macOS
```

---

## 2. I quattro principi da non rompere

Sono la ragione per cui il progetto è arrivato fin qui senza bug silenziosi.
Vale la pena rispettarli anche quando sembrano scomodi.

**1. Il motore di gioco non sa che Godot esiste.** Tutto in `core/` è
`RefCounted`, nessun `Node`. Gira headless, si testa in millisecondi, e potrà
servire a un bot o a un server senza toccarlo. Se ti viene voglia di mettere un
`Node` in `core/`, stai sbagliando strada.

**2. Non si indovina mai una regola.** Dove un dato manca, il codice **lo
dichiara** invece di inventare. Esempi vivi nel codice:
`ActionEngine.is_verified()` rifiuta di risolvere un'azione la cui tabella non
è stata letta; `_reinforcement_port()` dice "questo Gruppo non ha un porto
trascritto" invece di sceglierne uno; `Victory.unevaluated()` distingue un
premio che non scatta *perché la nave non corrisponde* da uno che non scatta
*perché manca un dato*. Una voce assente in `Scenario.rules()` significa "non
trascritta", **non** "no".

**3. I commenti spiegano il PERCHÉ, non il cosa.** Il codice dice già cosa fa.
I commenti dicono perché quella scelta e non un'altra, e soprattutto **quali
strade sono state provate e non funzionano** — così nessuno le ripercorre.

**4. Le tabelle si leggono dalle immagini a risoluzione nativa**, non
dall'estrazione testuale dei PDF, che perde le celle e sposta le righe
(verificato: la tabella dell'Interruzione estratta dal PDF ha bande sbagliate).
Il fascicolo **inglese** è la fonte per le tabelle di vittoria: la traduzione
italiana perde le intestazioni di colonna.

---

## 3. Trappole già pagate — non ripagarle

Ognuna di queste è costata tempo. Sono tutte reali e riproducibili.

### GDScript si blocca in silenzio se un `class_name` ombreggia un tipo Godot
`enum Range` dentro `Gunnery` e una classe chiamata `Signal` fanno **fallire il
parser senza nessun messaggio**: i test escono con zero output e il processo si
pianta. Per questo esistono `Gunnery.FireRange` e `SignalAction`.
**Diagnosi:** carica gli script uno per uno con un piccolo `SceneTree` e guarda
dove si ferma (`tools/smoke_ui.gd` è nato così).

### Un `const` che alias-a una classe globale fa lo stesso
`const SE := SpecialEffects` in cima a un file pianta il parser senza nessun
messaggio. Scrivi il nome per esteso.

### Un metodo statico che nomina la propria classe fa lo stesso
`ChoiceDialog.new()` dentro `ChoiceDialog` → "Identifier not found" → blocco
silenzioso. Per questo `Choice.ask()` sta in una classe separata.

### Dopo aver aggiunto un `class_name` serve `--import`
I nuovi `class_name` non sono nel registro globale finché non giri
`godot --headless --path . --import`. Senza, ottieni "Could not find type X" su
file che sono corretti.

### JSON non ha interi
Lo stato del RNG è un `uint64`; salvato come numero diventa un float e perde i
bit bassi. Ricaricare dava una partita *simile*, non la stessa. Va salvato come
**stringa** (vedi `DiceRNG.to_dict`). Stessa attenzione ovunque tu serializzi
interi grandi.

### La cwd della shell si azzera fra un comando e l'altro
Ogni comando Bash riparte dalla home del progetto padre. Usa percorsi assoluti
o `cd` esplicito in ogni invocazione.

### `Control` figlio di `CanvasLayer` non eredita il rettangolo del viewport
Va dimensionato a mano (`size = get_viewport_rect().size`). E **non** mettere
anche un preset di ancoraggio: i due meccanismi litigano e Godot avvisa.

### `draw_texture_rect()` in `_draw()` disegna rettangoli bianchi
Su questo renderer (`gl_compatibility`). Le pedine sono nodi `TextureRect`, non
disegni. Verificato che i dati della texture erano corretti campionando i pixel.

### L'export macOS richiede ETC2 ASTC
`rendering/textures/vram_compression/import_etc2_astc=true` in `project.godot`,
altrimenti Godot rifiuta l'export con un errore generico. E i preset di export
vanno tenuti **minimali**: una sola chiave che Godot 4.7 non riconosce fa
fallire tutto l'export con "errori di configurazione" e nessun dettaglio.

### Un errore a runtime dentro un test non fa fallire la suite
GDScript non ha eccezioni: un errore interrompe la funzione e l'esecuzione
riprende dalla successiva. Un test a metà smette di verificare e nessuno se ne
accorge. Per questo `tests/run_tests.gd` ha `EXPECTED`, il conto atteso per
suite: **se aggiungi test, alza quei numeri**.

E quando una suite fallisce, cerca `SCRIPT ERROR` nell'output completo: il
messaggio vero (`Parse Error` in un file di `core/`) è quasi sempre lì, e
l'errore che vedi nel test è solo una conseguenza — `Nonexistent function
'new' in base 'GDScript'` vuol dire che quella classe **non ha compilato**.

### Le lambda GDScript catturano i locali per valore
Un test che verificava un valore passato a un `Callable` era impossibile da
scrivere così; serve un contenitore (Array) per farlo uscire.

### SDXL sotto i ~700 px smette di comporre
Le prime icone, generate a 256, erano macchie astratte. Si genera a 1024 e si
rimpicciolisce (`tools/make_art.py`).

---

## 4. Mappa del codice

```
core/                    logica pura, nessun Node
  map/hex.gd             coordinate assiali su reticolo RUOTATO (44.28°)
  map/map_graph.gd       157 esagoni, lati negati, Canale di Kiel, 22 porti
  state/                 trajectory, ship, ship_roster, task_force,
                         game_state (serializzabile), scenario
  rules/                 time_lapse, trajectory_total, interruption,
                         action_engine, results, completion, convoy,
                         endgame, reorganize, signal_action,
                         victory, victory_tracker,
                         solo_table, solo_opponent
  battle/                battle_state, gunnery, torpedo, maneuver,
                         break_away, battle
  engine/                rng (con seme e tiri imposti), command_log (undo),
                         savegame, session
  data/                  map_graph.json, tables.json, actions.json,
                         ships.json (+ ships_overrides.json), battle_tables.json
                         scenarios/  22 scenari generati dai .vsav
                         victory/    condizioni di vittoria, scritte a mano
                         solo/       tabelle dell'avversario immaginario
ui/                      splash, main (mappa+editor), hud, map_view,
                         battle_view
tools/                   pipeline Python + strumenti Godot (vedi §8)
tests/                   11 suite, runner headless
```

### Il reticolo esagonale
Il modulo VASSAL **non contiene la griglia**. È stata ricostruita
dall'immagine: passo 213.50 px, rotazione 44.28°, origine (1745, 1692), 156
esagoni giocabili. **Validata al 100%** agganciando le 238 pedine dei 22
salvataggi ufficiali. Non rimetterla in discussione senza una ragione forte.

### I quattro modelli di vittoria
`core/rules/victory.gd`, enum `Mode`:

| modo | dove | come funziona |
|---|---|---|
| `VP` | Op2–Op9 | si contano i punti, clausola di parità per scenario |
| `CONDITIONS` | Op1 | elenco ordinato di condizioni, la prima che si verifica vince |
| `OBJECTIVES` | i 12 mini-scenari | quattro caselle Decisiva/Marginale, testo |
| `DEBRIEFING` | il solitario | **un** punteggio, letto su una tabella a soglie |

Ogni volta che ne è saltato fuori uno nuovo la tentazione era piegarlo al
modello già esistente. Sarebbe stata una regola inventata ogni volta.

---

## 4.bis Che cosa è finito e che cosa no

**Finito e testato:**
- tutte e **9 le azioni** del gioco base, Battaglia base compresa
- le regole dei **Convogli**, il **finale di partita**, **salvataggio/ricarica**
- le **condizioni di vittoria di tutti e 22 gli scenari**, in quattro modelli
- il **combattimento avanzato** dall'inizio alla fine: attitudine → colonne →
  Risultato Speciale → dove ha colpito → effetto → la nave cambia davvero
- il **motore** del solitario (tabelle a dado, TF non identificate) con BL1,
  BL2 e BL3 trascritte

**Non finito, e perché:**
- la **Confusione**: la regola è letta e scritta per esteso in
  `Snafu.EXPLAIN`, ma il segnalino non esiste come oggetto di gioco. Serve
  ricordare chi ce l'ha e permettergli di usarlo una volta.
- gli effetti Snafu che **assegnano una scelta a un giocatore** (Confusione,
  Niente Radar, Rotta Inaspettata, Arco Aperto, Problemi Meccanici, Sala
  Caldaie) sono spiegati per esteso nel registro, ma vanno applicati a mano:
  richiedono una decisione, e il motore la mostra invece di prenderla.
- la **fase dell'Attitudine** esiste nel motore ma non nell'interfaccia: oggi
  le attitudini si impostano solo dallo schieramento dello scenario, e non si
  possono cambiare a ogni Round come vuole la regola.
- gli **schieramenti dei 15 scenari solitari** vanno letti dalle mappe del
  fascicolo: non sono nel modulo VASSAL.
- **effetti visivi e sonori** in Battaglia: non c'è niente.

---

## 5. Da dove ripartire — in ordine

### 5.0 FATTO dopo la prima stesura di questo documento

- **§5.1 chiusa**: la Battaglia non decide più da sola. Il giocatore assegna i
  bersagli (clic su chi spara, poi sul bersaglio), le linee di fuoco si
  disegnano con raggio e valore dei cannoni, e i bersagli si **pre-assegnano**
  con la scelta del motore perché il giocatore li cambi.
- **§5.2 iniziata**: implementata l'**Attitudine** (`core/battle/attitude.gd`),
  con le attitudini di partenza dei 12 mini-scenari trascritte dalle mappe del
  fascicolo. `Ship` ha ora `attitude` e `special_effects`.
- **Il fascicolo avanzato INGLESE è disponibile**:
  `docs/regolamento/AC_Adv_Battle_Rules_May_4_2021.pdf`. Usare quello come
  fonte: l'italiano è una traduzione amatoriale, e sulle tabelle di vittoria
  aveva già perso delle intestazioni di colonna.

- **Tabella del Fuoco avanzata** (`core/battle/advanced_gunnery.gd`): due
  colonne, Risultati Gravi e Catastrofici, "azzoppata", divisione del fuoco.
- **Velocità FERMA** aggiunta a `TimeLapse.Speed` — con valore **-1**, non 0:
  metterla in testa avrebbe rinumerato l'enum, e gli scenari salvano la
  velocità come intero (`"speed": 2` sarebbe passato da media a lenta in tutti
  e 22 i file, in silenzio). Usare `TimeLapse.speed_label()`, non
  `SPEED_LABELS[...]`, perché un indice negativo prende l'ultimo elemento.

- **Interruttore** `BattleState.advanced`: da spento nulla cambia, le regole
  base restano quelle di sempre. `Gunnery.attack(..., advanced)` legge la
  tabella avanzata quando è acceso.
- **Tabella dei Siluri avanzata** (`core/battle/advanced_torpedo.gd`) con la
  **Linea di Galleggiamento** (colonna Grave). La colonna **Catastrofica** sta
  sul *player aid* avanzato e **non è stata letta**: il codice lo dichiara nel
  campo `effect` invece di inventarla.

- **Effetti Speciali** (`core/battle/special_effects.gd`): tutti e dieci i
  tipi, con la regola di aggravamento (un effetto che si ripete non si
  accumula: aggrava o diventa un Colpo).

- **Effetti collegati alla Battaglia**: `Battle._apply_hits()` applica gli
  effetti, `Ship.current_speed()` rispetta il rallentamento/arresto,
  `Gunnery.attack()` somma le penalità e rifiuta di sparare con Incendio o
  Allagamento gravi, `torpedo_phase()` usa la tavola avanzata quando serve.

- **Tabelle dei Risultati Speciali** (`core/battle/result_tables.gd`): Cintura,
  Sovrastruttura, Linea di Galleggiamento, colonne Grave e Catastrofica. Erano
  sul *player aid*, che è **l'ultima pagina di
  `AC_Adv_Battle_Rules_May_4_2021.pdf`** — non un foglio separato. La catena del
  Fuoco avanzato è ora completa.

- **Effetti Duraturi e Disingaggio** (`core/battle/lingering.gd`): procedure,
  Controllo Danni (3 dadi, i due più alti, ma la nave non spara il Round dopo),
  vulnerabilità tedesca opzionale (3 dadi, i due più **bassi**), Niente Radar
  completo. **Le due griglie non ci sono**: stanno su una carta player aid che
  non è dentro il PDF. `roll()` prepara il tiro, il giocatore legge la tabella,
  `apply()` esegue il risultato — divisione onesta, non un'invenzione.

- **Le due griglie mancanti sono arrivate.** L'utente ha fornito le due facce
  della carta di aiuto, ora in `docs/regolamento/AC_Adv_PlayerAid_A.pdf` e
  `_B.pdf`. Tabella degli Effetti Duraturi e del Disingaggio **trascritte**.
  E la carta ha corretto una regola che avevo scritto male: due effetti dello
  stesso tipo fanno tenere il **peggiore** *e* prendere **un Colpo** — non è un
  aggravamento gratis.

- **Verifica Snafu** (`core/battle/snafu.gd`): entrambe le colonne, con la
  regola che sopra la **Linea Artica** si legge la colonna Cattivo anche col
  bel tempo.
- **La sequenza avanzata del Round** è collegata: fase dell'**Attitudine**
  prima del Fuoco, fase degli **Effetti Duraturi** fra Manovra e Fuga.
  `BattleState.next_phase()` / `first_phase()` conoscono le due sequenze.
- **Battaglia Estesa**: +1 Round con Buona Visibilità, +1 se alla fine
  dell'Ultimo Round nessuna nave è in Corsa (una volta sola, se no due flotte
  decise a restare combatterebbero all'infinito).

- **Disingaggio** collegato a `Battle.finish()` e **Inseguimento**
  (`Attitude.pursue()`), l'ultima regola di Manovra che mancava.
- **Il runner dei test aveva un buco serio**, ora chiuso: un errore a runtime
  dentro un test lo interrompeva e basta, la suite proseguiva e il totale
  scendeva **in silenzio** (56 verifiche diventate 23, e stampava `TUTTO OK`).
  Ora `run_tests.gd` ha un conto atteso per suite: una verifica che non gira è
  un test fallito. **Quando aggiungi test, alza i numeri in `EXPECTED`.**

**1756 verifiche su 16 suite.**

#### Nota importante sui risultati avanzati
In avanzato il risultato **non è più "quanti Colpi"** ma una casella di
tabella, e le due cose non coincidono. Un *Risultato Grave* NON è "tre Colpi":
è un tiro in più su un'altra tabella, che può finire in un effetto speciale.
Per questo `hits` resta 0 su Grave e Catastrofico, e c'è un campo `special`
separato. Chi collega gli effetti speciali deve partire da lì.

**Restano delle Avanzate**, in ordine di utilità:

1. ~~**Gli Effetti Speciali**~~ e ~~**le Tabelle dei Risultati**~~ — **FATTI
   e collegati.** La catena del combattimento avanzato è completa: tiro →
   colonna per attitudine → Risultato Speciale → dove ha colpito (colonna per
   raggio) → effetto → la nave cambia davvero.
2. **Le due fasi nuove nella VISTA di Battaglia.** Nel motore ci sono e sono
   testate (`Battle.attitude_phase()`, `Battle.lingering_phase()`), ma
   `ui/battle_view/battle_view.gd` conosce ancora solo le quattro fasi base:
   `_advance_phase()` va esteso e servono i comandi per scegliere l'attitudine
   di ogni nave e per dichiarare il Controllo Danni.
3. ~~**Effetti Duraturi**~~ e ~~**Disingaggio**~~ — procedure **FATTE**,
   mancano solo le due griglie (vedi sopra). Da collegare al ciclo del Round in
   `Battle`: oggi nessuno chiama `Lingering.lingering_checks()`.
4. **Battaglia Estesa** — regola **completa e già letta**, va solo scritta:
   la Battaglia dura un Round in più se il Snafu dà "Buona Visibilità" con
   meteo Buono, **e** un altro Round in più se alla fine dell'Ultimo Round
   nessuna nave è in Corsa (le due condizioni si sommano). Il fascicolo dà
   anche la tabella riassuntiva delle durate, da 1 a 5 Round (p.13).
   La **Verifica Snafu** invece aspetta la griglia mancante.
5. **Inseguimento** (`Attitude.can_pursue` c'è già) e **Confusione**
6. L'**Attacco Furtivo opzionale** delle avanzate (un Colpo diventa S.R., una
   Battaglia diventa C.R.) e le **Manovre Evasive** in Battaglia, entrambe
   sull'ultima pagina del player aid.

### 5.1 ~~la Battaglia decide da sola~~ — FATTO

**Sintomo:** in Battaglia il giocatore preme SPAZIO e basta. Non sceglie chi
spara a chi, né chi silura chi.

**Causa:** il motore è progettato bene — il commento in `core/battle/battle.gd`
dice *"Le decisioni (chi spara a chi, chi manovra dove, chi tenta la Fuga) NON
sono prese qui: il chiamante le passa"* — ma
`ui/battle_view/battle_view.gd::_advance_phase()` chiama sempre
`battle.auto_targeting()` e `battle.auto_torpedoes()`, che sono pensati come
ripiego "per far girare la battaglia", non come modo di giocare.

**Cosa fare:** nella vista di Battaglia, fase Fuoco di Cannoni, far assegnare i
bersagli al giocatore (clic sulla nave che spara, poi clic sul bersaglio; linea
disegnata fra le due). Un pulsante *"Bersagli automatici"* riempie quelli non
assegnati con `auto_targeting()`. Stessa cosa per i siluri.
`Battle.gunnery_phase(targeting)` accetta già il Dictionary: **il motore non va
toccato**, è solo interfaccia.

RB p.57: gli effetti si applicano dopo che TUTTE le navi hanno attaccato
(eccezione: Round Uno dopo una SORPRESA con TF Attiva più veloce — già
implementata come `surprise_first_strike`).

### 5.2 PRIORITÀ ALTA — le Regole Avanzate di Battaglia (in corso)

`docs/regolamento/(2) Atlantic Chase ADV RB ITA.pdf`. **Niente di quel
fascicolo è nel codice.** Verificato: nessuna traccia di attitudini, Snafu,
Verifiche di Disimpegno, effetti speciali, Confusione.

Non è opzionale come sembra: gli schieramenti dei mini-scenari e degli scenari
solitari che ho già importato **contengono i marcatori di attitudine**
(`CLOSING`, `RUNNING`, `ACQUIRING`) e li sto ignorando. Vedi le immagini nel
fascicolo scenari alle pagine dei MS.

Da implementare, nell'ordine in cui il fascicolo li introduce:
- ~~**Attitudini** (Closing / Running / Acquiring)~~ — **FATTO**, vedi
  `core/battle/attitude.gd` e `tests/unit/test_attitude.gd`. Restano da
  collegare alla *vista* di Battaglia: la fase dell'Attitudine (nuova prima
  fase del Round) non esiste ancora nell'interfaccia, e `Gunnery` non usa
  ancora la colonna Acquisizione né la divisione del fuoco.
- **Tabella del Fuoco di Cannoni avanzata**: ha due colonne
  (Acquisizione / Avvicinamento-Corsa-Dividere) al posto di una. Sta nelle
  *Tabelle di Aiuto al Gioco Avanzato*, da leggere dal PDF inglese.
- **Fermo**, nuovo tipo di velocità
- **Inseguimento** durante la Manovra (`Attitude.can_pursue` già c'è)
- **Battaglia Estesa** (Round extra)
- **Snafu Check** a inizio Battaglia (molti MS hanno istruzioni speciali che lo
  modificano — sono già trascritte in `core/data/victory/MS*.json`, nelle note)
- **Verifica di Disimpegno** a fine Battaglia, con i risultati `port` / `scuttle` / `oil`
- **Effetti speciali** (una nave "azzoppata" con le regole avanzate è anche una
  che ha subito un effetto speciale — lo dicono le note dei MS)
- **Marcatore Confusione**, **Inseguire** per gli Squadroni DD

### 5.3 PRIORITÀ MEDIA — effetti visivi e sonori in Battaglia

Oggi la Battaglia è corretta ma muta: si preme un tasto e appare una riga di
testo nel registro. Da aggiungere (richiesta esplicita dell'utente):
- **salve di cannoni**: una traccia dalla nave che spara a quella colpita,
  colorata secondo il raggio (le sei zone hanno già i loro `Rect2` in
  `battle_view._bands`, quindi le posizioni ci sono già)
- **colonne d'acqua** per i mancati / *splash*, **fuoco e fumo** sulle navi
  danneggiate, **affondamento** (la pedina che scende e sparisce)
- **scie di siluri** dalla zona Ravvicinata
- **suoni**: cannonata, esplosione, siluro, allarme
- pausa fra l'attacco e l'applicazione dei Colpi, così si vede cosa succede
  invece di trovarsi il risultato già fatto

Nota di metodo: gli effetti vanno in `ui/battle_view/`, **non** nel motore. Il
motore restituisce già tutto quello che serve — `Gunnery.attack()` ritorna
`{ok, hits, target, firer, ...}` e `Battle.gunnery_phase()` l'elenco completo
dei risultati. Basta animarli.

Per generare eventuali immagini serve ComfyUI (vedi `tools/make_art.py`); per i
suoni non c'è ancora niente in progetto.

### 5.4 PRIORITÀ MEDIA — finire il modo solitario

Fatto: motore delle tabelle (`SoloTable`, `SoloOpponent`), Task Force **non
identificate**, e le tabelle di **BL1, BL2, BL3** trascritte per intero.

Restano:
- **le tabelle degli altri 12 scenari**: N1–N6 (pp. 17-40 del fascicolo solo),
  B1–B4 (pp. 41-58), A1–A2 (pp. 59-68). Il formato è pronto e testato: si
  aggiungono file in `core/data/solo/` e in `core/data/victory/`. Vedi
  `core/data/solo/BL2 Contain and Destroy.json` come modello completo.
- **gli schieramenti**: gli scenari solitari **non stanno nel modulo VASSAL**,
  quindi non c'è nessun `.vsav` da cui ricavarli. Vanno letti dalle mappe
  stampate nel fascicolo. Le posizioni sono date come nomi di porto e rotte di
  convoglio ("Halifax to Clyde/Liverpool, 11 segments"), non come esagoni: i
  porti si risolvono con `MapGraph.port_hex()`, le rotte le disegna il giocatore.
- **BL3 non è giocabile**: usa la **Mappa Inserto del Mare del Nord**, un'altra
  mappa con un'altra griglia, che questo progetto non ha calibrato. Il file
  `core/data/solo/BL3 ....json` lo dichiara nel campo `_map`. Calibrarla
  vorrebbe dire rifare per l'inserto quello che `tools/refine_lattice.py` ha
  fatto per la mappa grande.

### 5.5 PRIORITÀ BASSA

- **Le dieci righe da spuntare a mano** (mine, marcatore Base Aerea, zona di
  sicurezza USA, "la TF dell'Hipper ha eseguito un'azione Traiettoria") sono
  elencate dal tasto **V** (Esito), ma non c'è una schermata di fine partita che
  le presenti come lista spuntabile e sommi il risultato.
- **Gesti touch mai provati su un iPad vero.** Il codice c'è (pinch a due dita,
  tocco prolungato al posto del clic destro), l'export web funziona
  (`sh tools/serve_web.sh`), ma non li ha mai toccati un dito.
- **La prova di fumo copre solo la Battaglia.** Se un bug come quello dei tasti
  è passato inosservato per settimane, è probabile che altri percorsi
  dell'interfaccia siano rotti allo stesso modo, in silenzio. Estendere
  `tools/smoke_ui.gd` alle altre schermate è il modo più economico di scoprirlo.

---

## 6. Cosa NON è un problema (anche se sembra)

- **`Campaign.json` non ha Task Force.** Corretto: la Campagna non è uno
  scenario, è la riserva navi delle nove Operazioni (15 tedesche, 59 alleate),
  esposta da `Scenario.ship_pool()`.
- **I mini-scenari non hanno Traiettorie né Stazioni.** Corretto: sono
  **Battaglie già schierate**, e le navi partono nelle bande della Mappa di
  Battaglia. `Scenario.is_battle_scenario()` / `make_battle_state()`.
- **Tre scenari hanno un avviso di import** ("la rotta attraversa il lato
  negato 13,-6 | 13,-7"). È vero e va lasciato: nel modulo VASSAL le pedine
  sono piazzate a occhio su una mappa senza griglia, quindi ogni tanto una
  rotta ricostruita taglia dove non dovrebbe. Meglio l'avviso che il silenzio.
- **`Scheerb.png` è un doppione.** Refuso del modulo VASSAL: il vero lato
  danneggiato è `Sheerb.png`. Già gestito in `ships_overrides.json`.

---

## 7. Questioni aperte con l'utente

- **Il repository è PUBBLICO** e contiene materiale © GMT Games: mappa, pedine,
  i due fascicoli scenari inglesi integrali e sei traduzioni italiane marcate
  *"PER SOLO USO PERSONALE – vietata la vendita"*. Il `README.md` lo dichiara in
  cima e spiega come tornare a un repository di solo codice. **Non ho attivato
  GitHub Pages** e ho spiegato perché: servirebbe a pubblicare quel materiale a
  un indirizzo aperto. Se l'utente insiste, la strada pulita è un repository
  separato con solo il codice.
- Le immagini in `assets/art/` sono generate in locale con SDXL e **non** sono
  di GMT: quelle si possono pubblicare.

---

## 8. Strumenti

```bash
sh tools/rebuild_all.sh          # rifà tutta la catena dal modulo VASSAL
tools/.venv/bin/python tools/import_scenarios.py    # 22 scenari dai .vsav
tools/.venv/bin/python tools/extract_briefings.py   # SEMPRE dopo l'import!
tools/.venv/bin/python tools/write_victory.py       # le 9 tabelle VP
tools/.venv/bin/python tools/make_art.py            # illustrazioni (ComfyUI)
godot --path . --script res://tools/screenshot.gd -- out.png [0-3] "scen:<id>"
godot --path . --script res://tools/smoke_ui.gd     # prova di fumo GUI
sh tools/build_macos.sh          # app macOS firmata e senza quarantena
sh tools/serve_web.sh            # export web + server locale (iPad)
```

**`extract_briefings.py` va rilanciato dopo ogni `import_scenarios.py`**,
altrimenti i briefing spariscono: l'import rigenera i file e li sovrascrive.
È già successo.

Il venv Python è in `tools/.venv` (numpy, scipy, pillow, pymupdf).
ComfyUI è in `~/ComfyUI` con SDXL base 1.0.

---

## 9. Convenzioni di stile

- Codice e commenti **in italiano**, senza accenti nei commenti del codice
  (`perche'`, `piu'`) — le stringhe mostrate all'utente invece li usano.
- Messaggi di commit: titolo che dice **la cosa**, corpo che spiega **perché** e
  cosa si è scoperto. Guarda `git log` — sono lunghi di proposito, e sono la
  documentazione migliore del progetto.
- I test hanno messaggi che spiegano l'intento, non il meccanismo:
  `"due attacchi da due Colpi fanno due Colpi, non quattro"`, non
  `"hits_taken == 2"`.
- Ogni regola trascritta cita la sua pagina del regolamento (`RB p.29`).
