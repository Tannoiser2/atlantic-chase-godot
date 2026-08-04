# Stato del lavoro

Riferimento: `PIANO_GODOT.md` nella cartella superiore.
Tutti i test passano: **3393 verifiche, 20 suite, headless.**

---

## Riepilogo per milestone

| Milestone | Stato | Note |
|---|---|---|
| **M0** Fondamenta | ✅ **completo** | Progetto Godot 4.7, mappa in 15 tile, camera, pipeline asset, runner di test |
| **M1a** Calibrazione reticolo | ✅ **completo** | Validato al 100% contro le pedine ufficiali |
| **M1b** Estrazione dati | ✅ **completo** | 22 `.vsav` decodificati, 70 zone, terreno classificato |
| **M1c** Grafo + editor | ✅ **completo** | 129 esagoni, 9 lati "not adjacent", Canale di Kiel; editor operativo |
| **M2** Core regole | ✅ **completo** | Traiettoria, Tempo, Totale, Interruzione, undo, RNG — tutto testato |
| **M3** Mappa interattiva | ✅ **completo** | Selezione, costruzione traiettoria, anteprima, undo, HUD, log |
| **M4** Motore azioni | ✅ **completo** | Tutte e 4 le tabelle trascritte e verificate; danno alle navi |
| **M5** Battaglia | ✅ **completo** | motore + vista: 5 zone, cannoni, siluri, manovra, fumo, fuga, uscita |
| **M6** Scenari | ✅ **completo** | 22 scenari con navi, comandanti, rinforzi e briefing |
| **M7** Regole complete | ✅ **completo** | Tutte e 9 le azioni, Convogli, finale di partita, salvataggio; tutti e 22 gli scenari hanno le condizioni di vittoria |
| **M9** Battaglia decisa dal giocatore | ✅ **completo** | Bersagli scelti a mano, linee di fuoco con raggio e valore dei cannoni |
| **M10** Regole Avanzate | 🟡 **quasi completo** | Attitudini, Fuoco a due colonne, Siluri, Tabelle dei Risultati, Effetti Duraturi, Disingaggio, Snafu e Battaglia Estesa sono collegati. Restano le scelte interattive di Plancia/Timone/Confusione e la divisione del fuoco |
| **M8** Solitario | 🟡 **in corso** | 15 setup e tabelle presenti; bot attivo con Iniziativa, popup e audit. BL1 e BL2 hanno un replay end-to-end deterministico (`SoloRunner`). Restano 82 testi procedura segnaposto e Mine/Base Aerea di N2/N4 non modellate. |

### Ultima revisione del solitario

- le procedure composte delle Tabelle Azioni non perdono piu' la seconda
  azione: Traiettoria poi Ingaggio/Ricerca/Completamento prosegue senza un
  nuovo tiro, ma offre comunque ogni normale tentativo sull'Iniziativa;
- il risultato BL1-A senza bersaglio aereo usa la TF con CA per Traiettoria e
  poi Ricerca Navale, oppure Ingaggio contro una Stazione. Il bot non sceglie
  piu' Attacco Furtivo come ripiego generico quando la tabella non lo ordina;
- il pianificatore continua ora dal capo corretto quando una Stazione in mare
  diventa Traiettoria: non si ferma piu' dopo il primo segmento;
- durante una scelta nel pannello di stato la mappa non cambia selezione e non
  avvia trascinamenti: la TF mostrata non puo' divergere da quella gia'
  designata nell'azione;
- il Completamento del giocatore emette immediatamente il cambio di stato al
  renderer: Stazione e Traiettoria della TF uscita spariscono dalla mappa nello
  stesso momento in cui le navi entrano in porto;
- i porti nemici ora generano davvero segnalini Informazioni (RB p.8 e p.21):
  gli esagoni vengono ricavati dal grafo calibrato e il controllo usa le
  eccezioni di ciascuno scenario. Porti neutrali e amici non li generano;
- Stazioni nemiche gia' Completate o in Casella Porto non causano Informazioni.
  Basi aeree e forze Furtive restano dichiaratamente non modellate: mancano
  ancora pedine e dati calibrati, quindi non vengono inventati inneschi;
- il Registro conserva l'intera sessione, numera gli eventi, e' selezionabile
  e ha `Copia tutto`; anche il testo del pannello di stato e' selezionabile.
  Le procedure del bot sono raccolte per tiro e chiuse per impostazione
  predefinita; ogni procedura ha il proprio comando `Mostra/Nascondi`, senza
  aprire anche le altre. Gli eventi piu' recenti sono in alto;
- al termine di ogni tiro automatico, il risultato effettivamente applicato
  dal bot resta in evidenza, in grassetto e colore distinto, sia nel Registro
  sia nel pannello di stato;
- le scelte operative non aprono piu' il grande dialogo centrale: Coordinatrice,
  Supporto Aereo, Sottrarre l'Iniziativa, Manovre Evasive e le altre opzioni
  della mappa appaiono come pulsanti rialzati e stondati nel pannello di stato;
- lo Scorrere del Tempo del giocatore non presenta piu' combinazioni testuali:
  evidenzia sulla mappa i capi legalmente rimovibili e li fa cliccare uno alla
  volta. Quantita', Informazioni e Limite di Informazioni restano governati dal
  core; il bot continua a scegliere deterministicamente secondo la tabella.
  Non e' piu' un comando libero: pulsante e scorciatoia `T` sono stati rimossi,
  e la scelta compare soltanto quando un'Azione o un evento la innesca;
- le schede TF spiegano l'effetto stampato dei Comandanti. Raeder e Pound
  implementano Passare Tutto due volte per scenario, con utilizzi salvati;
- `(11,-7)` e `(11,-6)` sono stati esclusi dal grafo giocabile;
- 24 dei 25 esagoni esterni indicati restano esclusi; `(11,-5)` e' stato
  riammesso perche' lo schieramento BL1 vi colloca un marker RV. Le annotazioni
  manuali sopravvivono alla rigenerazione del grafo e sono protette dai test;
- BL1 piazza i tre marker RV in `(10,3)`, `(9,-2)` e `(11,-5)`. Quando il
  tedesco ha l'Iniziativa e una sua Stazione occupa un RV, l'app tira
  automaticamente la Tabella del Rifornimento, applica l'effetto `a-g`, mostra
  un popup sull'esagono e impedisce Controlli fuori dalle condizioni stampate;
- le pedine Modificatori, VP e Conto Iniziativa seguono l'inclinazione delle
  rispettive colonne; i punteggi negativi avanzano della loro grandezza sulla
  traccia e conservano il segno nel badge, invece di restare fermi sullo zero;
- `Punteggio (V)` apre un pannello con valori correnti, riga di Esito e
  condizioni manuali; `Scenario (B)` mostra obiettivo, fine, setup, rinforzi e
  tabelle del bot. I segnaposto di BL1-BL3 sono stati sostituiti col testo
  trascritto dalla seconda edizione 2022;
- la scheda della TF selezionata occupa una colonna dedicata a destra dello
  stato inferiore e non copre piu' la mappa; il segnalino Manovre Evasive usa
  la pedina GMT ed e' visibile accanto alla TF, oltre che dichiarato nella
  scheda;
- la Coordinatrice viene proposta solo se occupa l'esagono Bersaglio (RB
  p.47), invece di elencare tutte le TF amiche;
- Segnalazione e' disponibile solo se una Traiettoria nemica ha Informazioni;
  la guida chiarisce che l'azione sostituisce quel segnalino con la Stazione
  bersaglio e non crea un marcatore "Signal" separato (RB p.39). I segmenti
  con Informazioni mostrano ora le pedine GMT `Intel_GE`/`Intel_UK`, invece del
  vecchio quadratino procedurale quasi invisibile a mappa intera;
- Contatto usa le pedine GMT della parte che lo ha stabilito, e Manovre Evasive
  usa la propria pedina GMT in formato leggibile accanto alla TF. Gli Attacchi
  Aerei mostrano Launch e Strike nei due esagoni designati fino alla fine dello
  Scorrere del Tempo; il segmento Launch viene rimosso per ultimo e, se la TF
  diventa Stazione, questa resta nel Punto di Lancio (RB p.27). La fine di una
  Battaglia rimuove le Manovre Evasive da entrambe le TF (RB p.62);
- Attacco Aereo fa scegliere la TF con CV integra, il Punto di Lancio sulla
  mappa e l'esagono Bersaglio entro raggio 2 (RB p.27). Le basi aeree restano
  esplicitamente non modellate: posizione, parte e periodo di attivita' devono
  essere trascritti dalla mappa prima di poterle offrire come fonte;
- HUD della mappa ricostruita: nove azioni illuminate in alto, servizi nella
  seconda riga, guida operativa in basso e registro richiudibile a destra.
  Barra, mappe inserto, mappa principale, Registro e stato occupano regioni
  fisicamente separate: la mappa vive in un SubViewport centrale e non continua
  sotto i pannelli. A sinistra, due schede mostrano le immagini originali del
  Mare del Nord e del Mare di Norvegia come riferimenti visivi; i loro reticoli
  restano dichiaratamente non calibrati. Chiudendo il Registro, il suo spazio
  torna alla mappa;
- selezionando una TF compare nella fascia inferiore una scheda con stato e
  pedine nave GMT reali; cliccando sul mare la scheda sparisce. Le TF del bot si
  possono ispezionare ma restano non comandabili;
- in modalita' Editor ogni esagono giocabile mostra al centro le coordinate e
  quello scelto viene evidenziato;
- i segnalini originali KM/RN sono ora visibili sulle colonne Modificatori,
  Punti Vittoria e Conto Iniziativa della plancia stampata; seguono lo stato e
  sopravvivono al salvataggio;
- le TF che Completano lasciano correttamente la mappa ma restano elencate nel
  roster, con navi e porto di arrivo: non sembrano piu' sparite senza motivo;
- BL1 non raddoppia piu' i VP quando una destinazione vale sia come porto sia
  come paese: due Convogli britannici arrivati valgono -4, non -8;
- le TF senza navi a galla spariscono dalla mappa; la cronologia perdite resta
  nel salvataggio per modificatori e Debriefing;
- il bot non trasforma piu' ogni Traiettoria in un Passare: Scorrere del Tempo,
  Sottrarre/Cercare l'Iniziativa e successiva azione seguono il flusso normale;
- i passaggi Presto/Tardi di BL2, BL3, N1 e N2 sono automatici;
- BL2 e' stato ricontrollato riga per riga contro
  `AC_Solo_scenarios_2022.pdf`: la tabella Tardi conserva la colonna 0, il
  modificatore OR vale una sola volta e le procedure A, C, Convoglio, E, T e X
  hanno policy dedicate. Identificazione e Incidente Internazionale applicano
  i propri risultati; le condizioni di fine a 2 Convogli o 4 navi sono
  automatiche e persistono nel salvataggio;
- raggiunta una condizione di fine BL2, il ciclo automatico la applica prima
  di accodare il tiro successivo: il bot non puo' piu' iniziare una terza
  procedura dopo il secondo Completamento;
- i Convogli iniziali BL2 hanno destinazioni esplicite: Africa-Portsmouth non
  puo' Completare ad Africa e Halifax-Clyde/Liverpool non puo' Completare ad
  Halifax. Il porto di origine non assegna piu' VP ne' altera prematuramente la
  colonna della Tabella delle Azioni;
- quando un risultato porta in Battaglia una TF non identificata, il core tira
  e applica automaticamente la Tabella di Identificazione prima di aprire la
  Mappa di Battaglia. Tiro e composizione rivelata restano nel Registro; un
  dato o una nave indisponibile producono un blocco dichiarato, non una TF
  vuota che assorbe altri Ingaggi;
- nelle procedure composte BL2, la seconda azione non puo' piu' generare una
  seconda Traiettoria: dopo la rotta prescritta tenta il Completamento sulla
  posizione corrente oppure Passa se non raggiunge il porto, supera 6 segmenti
  o ha Informazioni. Il log dice `puo' tentare` finche' il normale tentativo
  sull'Iniziativa non ha stabilito che il Completamento riesce davvero;
- BL2 fa scegliere sulla mappa la Stazione iniziale della Home Fleet, adiacente
  a un porto controllato britannico eccetto Scapa Flow e Methil. La Home Fleet
  contiene Repulse, tre CA e un CL: i quattro `any` vengono scelti dal
  giocatore nel pannello di stato. I porti norvegesi sono neutrali e non
  compaiono fra gli esagoni legali;
- BL2 piazza entrambe le rotte Convoglio stampate, inclusi gli otto segmenti
  Africa-Portsmouth. Rodney e Valiant sono nel Gruppo Rinforzi A a Scapa Flow,
  non in una TF iniziale; il Gruppo B e' a Brest e porta Gensoul quando entra;
- Pound e' modellato correttamente come comandante non assegnato e abilita
  Passare Tutti. Forbes parte con la Home Fleet. Gli effetti una tantum di
  Forbes e Gensoul sono ancora descritti ma non automatizzati;
- il confine rosa delle Acque Neutrali BL2 e' calibrato sugli esagoni della
  Mappa Operazionale. Ingaggiare o Attacco Aereo britannico contro una TF al
  suo interno tira automaticamente l'Incidente Internazionale dopo la
  risoluzione, come stampato. Restano dichiarati la rotta Azzorre-Faroe e la
  pedina Base Aerea di Trondheim;
- BL3 e' stato verificato contro le pp.12-15 della seconda edizione: tabelle,
  rinforzi e audit dello setup sono trascritti, ma lo scenario non e' ancora
  giocabile. Usa la Mappa Inserto del Mare del Nord; immagine presente, reticolo
  e coordinate non calibrati. L'app lo dichiara invece di piazzare le TF sulla
  Mappa Operazionale sbagliata;
- riepilogo persistente nel pannello di stato e procedura espandibile nel log
  mostrano tabella, tiro, TF scelta, bersaglio, risultato e ragione della policy;
- `tools/audit_solo.gd`: 93 caselle azione, 0 blocchi, **0 testi segnaposto e
  0 buchi dichiarati**.
| **M11** Effetti di Battaglia | ✅ **completo** | Suoni sintetizzati, vampe, traccianti, schizzi, esplosioni, incendi, siluri, affondamenti |

### Cosa e' cambiato nell'ultima sessione (le procedure segnaposto, chiuse)

**Le 42 procedure segnaposto delle Tabelle Azioni sono zero.** Era il numero
che diceva quanto mancava al solitario "vero": in quelle caselle il bot
applicava una policy generica invece della procedura stampata. N3, N5, N2 e N1
sono stati ripresi uno per volta sulle pagine renderizzate, e ogni rilettura ha
trovato difetti che nessun test poteva prendere, perche' erano nel DATO.

- **Tre tabelle erano trascritte scalate di una colonna**, tutte per lo stesso
  motivo: il fascicolo unisce due facce del dado in una colonna sola - `2-3`,
  `3-4`, `5-6` - e chi trascrive legge sei colonne dove ce ne sono cinque. E'
  successo alla Identificazione di N2 (`1 | 2 | 3-4 | 5 | 6`), a quella di N1
  (`1 | 2-3 | 4 | 5 | 6`) e alla riga '1' di N5, dove un `CL/CL` era diventato
  un `CL` solo. E' lo stesso difetto della Tabella Murmansk di BL1, e si vede
  solo rimettendo l'occhio sulla pagina.
- **Tre tabelle stampate DENTRO i risultati non c'erano affatto nel dato**: la
  Nuova TF Britannica e l'esagono delle Mine di N2, la X - Identificazione della
  TF Tedesca di N1.
- **N3 aveva una cella vuota** dove la pagina stampa il simbolo dell'occhio,
  cioe' il risultato CONTATTO: quel risultato non si e' mai potuto verificare in
  nessuna partita di N3.
- **N2 aveva un modificatore che non le appartiene** sulla tabella Iniziale, che
  la pagina riserva esplicitamente alla Seguente.
- **Il tedesco di N1 non poteva Completare da nessuna parte.** La sua Tabella
  dei Porti elenca Murmansk e Kiel, che sul Mare di Norvegia sono bande
  stampate ai bordi e non pallini: `Completion.port_options` non li trovava.
  Ora `MapGraph.load_inset` promuove a porti le caselle fuori mappa il cui nome
  e' un porto della Mappa Operazionale, prendendo da li' la nazione. Il Denmark
  Strait resta fuori, perche' non e' un porto su nessuna mappa.
- **Tre fini stampate dentro i risultati** non scattavano mai: la 'C' di N3, la
  'X' di N5 e la 'I' di N1.

### Cosa e' cambiato nelle sessioni prima (procedure N2, N3 e N5)

- **N2 aveva la tabella di Identificazione scalata di una colonna.** Le colonne
  stampate a p.23 sono `1 | 2 | 3-4 | 5 | 6`, e la trascrizione le aveva lette
  come sei colonne distinte: da un 4 in poi tutto slittava, e con un 4 la riga
  Iniziale dava DD/Convoglio invece di CL/Convoglio. E' esattamente il difetto
  della Tabella Murmansk di BL1, e si vede solo rimettendo l'occhio sulla
  pagina.
- **E un modificatore che non le appartiene.** La pagina stampa "Modifiers
  (Late table only)"; il dato ne aveva uno anche sulla tabella Iniziale - un -1
  per nave britannica Danneggiata o affondata - che spostava tutti i tiri
  Iniziali di N2.
- **'AA' e 'Bd' puntavano ai porti sbagliati.** Andavano a Bergen e Trondheim,
  cioe' ai porti della Mappa Operazionale usati come sostituti quando l'inserto
  non era calibrato, invece che ad Andalsnes e Bud. E li' c'era il seguito del
  problema: Andalsnes e Bud non sono porti ma Punti di Interesse, quindi il loro
  Completamento e' quello IN NORVEGIA di p.16, che vuole un Convoglio o uno
  Squadrone DD a bordo. Senza quel ramo la procedura dichiarava "porto non
  calibrato" e passava: non completava mai.
- **Le due sotto-tabelle stampate dentro i risultati non c'erano.** La Nuova TF
  Britannica del risultato 'X' e l'esagono delle Mine del risultato 'mine' sono
  tabelle a dado stampate dentro il testo della procedura, e nel dato mancavano
  del tutto. Adesso ci sono, e le Mine vengono posate davvero - rispettando il
  "this is not Recon" della pagina: nessun segnalino Informazioni.

### Cosa e' cambiato nella sessione prima (procedure N3 e N5)

- **I marcatori Base Aerea esistono.** `core/rules/air_base.gd` e
  `GameState.placed_air_bases`. Quattro procedure stampate li mettono e li
  tolgono - BL2 p.11, N4 p.30, N5 p.33, N6 p.37 - e finora tutte e quattro
  dichiaravano la lacuna e passavano, perche' la pedina non esisteva da nessuna
  parte nello stato. Adesso c'e' il dato: si salva, occupa un esagono e - come
  qualunque base aerea nemica, RB p.21 - vi innesca Informazioni. Quello che
  NON c'e' e' la Base Aerea come FONTE di un Attacco Aereo (RB p.27):
  `ActionEngine` pretende una TF Attiva con una CV integra e non sa partire da
  un esagono, e le procedure che ne avrebbero bisogno lo dichiarano.
- **Gli sbarchi in Norvegia lasciano una traccia.** Il Completamento in Norvegia
  non scriveva `completed_port`, perche' la Task Force del giocatore resta in
  gioco: quello storico semplicemente non esisteva. Serve al -1 del dado del
  Convoglio di N5 (p.33) e ai modificatori della Reazione Norvegese, ed era una
  lacuna dichiarata nel TODO. Ora sta in `Norway.landings_of`, dentro
  `solo_counters`, quindi nel salvataggio.
- **Le dieci procedure di N5 sono trascritte e implementate.** N5 non aveva
  nessuna policy propria e cadeva nel ripiego generico in fondo a
  `execute_code`: la 'A' non piazzava nessuna Base Aerea, la 'Conv' non tirava
  il dado del porto norvegese (0-3 Trondheim, 4-6 Narvik, col -1 stampato), e la
  fine dentro la 'X' - "se l'unico bersaglio e' una Stazione a Scapa Flow,
  l'azione e' annullata e lo scenario finisce" - non scattava mai.
- **Un'altra cella sbagliata, come quella di B3.** La riga '1', colonna 4, della
  tabella di Identificazione di N5 stampa CL/CL, cioe' DUE incrociatori
  leggeri, e il dato ne aveva uno solo: una TF tedesca non identificata entrava
  in Battaglia con un incrociatore in meno. Si vede solo rileggendo la pagina.
- **`MapGraph.place_hex()` conosce anche le caselle fuori mappa.** Sugli
  inserti Scapa Flow, Kiel, Murmansk e il Denmark Strait non sono porti: sono
  bande stampate ai bordi. Il fascicolo pero' li nomina come qualunque porto -
  "Complete in Scapa Flow", "segments nearest to Kiel" - e senza questa lettura
  tre clausole di N5 non erano scrivibili. Quando la banda tocca piu' di un
  esagono si prende quello che tocca DI PIU', usando la percentuale gia'
  misurata nel dato.

### Cosa e' cambiato nella sessione prima (procedure N3)

- **L'Attacco Furtivo lo esegue la forza Furtiva, non una Task Force.** Il
  difetto stava scritto in un registro BL2 e nessuno lo aveva letto: "Attacco
  Furtivo -> Totale Traiettoria 2". RB p.41 da' alla forza Furtiva una
  Traiettoria di ZERO, quindi quel 2 diceva che l'azione la stava dichiarando
  una Task Force. Era anche l'unica strada possibile, perche' `ActionEngine`
  rifiutava qualunque dichiarazione senza TF Attiva. Ora `Declaration` ha
  `active_stealth`, la legalita' chiama `Stealth.attack_error` invece di
  riscriverla, e il Totale Traiettoria viene giusto da solo perche'
  `to_designations()` conta zero per un'Attiva assente.
- **Le undici procedure di N3 sono trascritte e implementate** dalle pagine
  renderizzate (pp.25-27). Girano tutte attorno al Sommergibile britannico:
  'SA' lo fa attaccare col +3 stampato, 'SR' lo piazza nell'esagono con una TF
  tedesca piu' vicino a Bergen (ed e' la strada per cui rientra dopo un 'SA'),
  'X' misura la distanza dei bersagli DA LUI. La 'B' e' in due passi, e il
  secondo non puo' tracciare una seconda Traiettoria: e' la trappola gia'
  pagata su BL2.
- **La cella dell'occhio era vuota.** La colonna 5 della prima riga della
  Tabella di Azione Britannica stampa il simbolo del CONTATTO; nel dato era una
  stringa vuota, e un codice vuoto non arriva a nessuna procedura. Quel
  risultato non si e' mai potuto verificare in nessuna partita di N3.
- **Il Sommergibile di N3 e' BRITANNICO, e il suo esagono si misura.** La nota
  di schieramento lo diceva tedesco e "senza esagono noto"; la pedina
  sull'illustrazione di p.25 porta la Union Jack, e la Tabella parla sempre e
  solo della "British Submarine stealth force". La posizione e' stata misurata
  con la registrazione che `validate_inset_setups.py` usa gia' per i segmenti:
  centro della pedina a 7.1 px dal centro di **(6,-1)**, l'esagono di
  Kristiansand, contro un inraggio di circa 107 px.
- **`Stealth.placement_error` leggeva `port_control` con `int()`.** Su una
  stringa `int()` non protesta: torna 0, cioe' KRIEGSMARINE. Ogni porto "BOTH"
  o "NONE" risultava quindi tedesco, e a una forza Furtiva britannica veniva
  rifiutato Bergen - proprio l'esagono che la procedura 'SR' di N3 dice di
  preferire. Il test che avrebbe dovuto prenderlo passava un intero, cioe'
  ripeteva l'errore del codice.
- **La preferenza dello Scorrere del Tempo e' una regola sola.** Il conto era
  scritto due volte, identico, in `SoloRunner` e in `ui/main.gd`, e conosceva
  solo "rimuovi i segmenti piu' LONTANI da X". La 'X' di N3 stampa "nearest to
  Scapa Flow", che e' la stessa frase al contrario: ora sta in
  `SoloSequence.time_lapse_preference` e le due copie non possono divergere.
- **Un refuso del fascicolo, dichiarato invece di tappato.** Le cinque colonne
  della tabella di Identificazione di N3 sono intestate `1 | 2 | 4 | 5 | 5-6`:
  manca la 3 e il 5 compare due volte. Su 1d6 l'unica lettura che copre tutte e
  sei le facce e' `1 / 2 / 3 / 4 / 5-6`, ed e' quella usata; la faccia 3 resta
  l'unica non verificabile sullo stampato, e il dato lo dice.

### Cosa e' cambiato nella sessione precedente (milestone R0)

- **Gli scenari solitari si giocano per intero senza interfaccia.**
  `core/rules/solo_runner.gd` e' `RefCounted` puro e percorre il ciclo
  completo: tiro della Tabella Azioni con modificatori automatici, decisione di
  `SoloAI`, continuazioni prescritte, Scorrere del Tempo, Iniziativa,
  Battaglia risolta da `SoloBattle` per entrambe le parti, Completamenti, fine
  scenario e Debriefing. `tools/replay_solo.gd` lo esegue con semi fissi.
  Il ciclo non introduce regole: mette in fila quelle che c'erano gia' e che
  finora vivevano solo dentro `ui/main.gd`.
- **La policy del giocatore simulato e' dichiarata come tale.** Il fascicolo
  non dice come deve giocare l'essere umano: ogni riga che ne deriva e'
  marcata `GIOCATORE (policy harness)` nella trascrizione. Segue comunque
  l'obiettivo stampato - caccia i Convogli, non i corazzati - perche' la prima
  versione perdeva l'incrociatore ausiliario al primo turno contro Dunkerque e
  Strasbourg, e la partita non arrivava mai a meta'.
- **Quattro difetti veri trovati dal replay:**
  - la riga della Tabella Azioni Britanniche di BL1 contava i Completamenti
    **tedeschi** invece dei Convogli britannici Completati e distrutti (p.7):
    la tabella restava inchiodata alla prima riga per tutta la partita. La
    regola e' passata nel core (`SoloOpponent.action_row_selector`), dove
    doveva stare;
  - BL1 non aveva nessuna condizione di fine automatica (p.5: due o meno
    marker Rendezvous **e** nessuna TF tedesca in gioco);
  - `remove_rendezvous_at` marca il marker `active = false` senza toglierlo
    dall'elenco, quindi contare l'Array dava sempre tre. Ora c'e'
    `GameState.active_rendezvous_count()`;
  - i risultati che fanno **cambiare** l'Iniziativa venivano trattati come una
    normale ricerca dell'Iniziativa: due meccaniche diverse, e il Conto si
    comporta in modo diverso.
- **La procedura CONVOGLIO di BL1 non esisteva.** Il codice cadeva nel ripiego
  generico: niente dado di rimando (1-2 'A', 3-5 'C', 6 'F'), niente nuova TF
  con Convoglio e CL, niente PARI Africa / DISPARI Halifax, niente Incidente
  Internazionale. Ora c'e' tutta, e con lei la rimozione delle navi britanniche
  Danneggiate che i risultati C e Convoglio prescrivono - navi che le tabelle
  degli Esiti contano fra le Danneggiate, non fra le affondate.
- **Il ciclo solitario ha una prova di fumo che lo percorre davvero**
  (`tools/smoke_solo_flow.gd`): apre il gioco, passa l'Iniziativa al bot,
  risponde alle scelte come farebbe una persona e pretende tiro della Tabella,
  mossa annunciata, Registro cresciuto e tasti ancora vivi. Il criterio di
  blocco non e' un tempo massimo ma l'assenza di **progresso**, cosi' una
  macchina lenta non fa fallire la prova e un ciclo fermo non la fa passare.
  Verificata rompendo di proposito `_apply_solo_ai_result`: esce con codice 1.
- **Le regole di sequenza del solitario stanno in un posto solo**
  (`core/rules/solo_sequence.gd`). Il ciclo resta in due esemplari - il core
  sincrono e la vista asincrona - ma le REGOLE no: ramo del risultato,
  costruzione della dichiarazione con la Coordinatrice, esito sull'Iniziativa
  dopo l'azione, innesco della tabella Tardi. Le due copie erano gia'
  divergute, e l'estrazione ha scoperto **due difetti veri nella vista**: il
  percorso del bot non applicava il cambio d'Iniziativa (RB p.53) e trattava
  come una ricerca quello che e' un passaggio; e una decisione senza effetto
  lasciava l'Iniziativa al bot senza accodare niente, cioe' fermava la partita
  in attesa di un giocatore che non doveva muovere.
- **A1 non aveva la stessa lacuna: ne aveva una diversa.** I suoi due Gruppi di
  Rinforzo contenevano gia' i Convogli, ma il Gruppo A **non ha un porto
  fisso**: il fascicolo (p.59) fa tirare un dado per determinare porto di
  partenza e destinazione insieme - 1-2 Clyde/Liverpool verso Murmansk, 3-5
  Hvalfiord verso Murmansk, 6 Hvalfiord verso Archangel. E' l'unico scenario in
  cui succede, e per questo il Gruppo non compariva fra i porti: la sua assenza
  era corretta, mancava il meccanismo. Ora la tabella e' nel dato
  (`reinforcement_routes`), il replay la tira e assegna al Convoglio anche il
  porto di destinazione, senza il quale non potrebbe Completare.
  Con la fine stampata nella 'X' - una BB tedesca affondata o Completata -
  **nove scenari su dieci giocabili chiudono ora per una condizione stampata**.
- **B4 aveva la stessa lacuna di B2, e una in piu' da verificare.** Dei tre
  Gruppi di Rinforzo stampati - A a St. John's con un Convoglio, B a Gibilterra
  con Renown, Ark Royal e Sheffield, C a Scapa Flow con la Victorious - nei
  dati c'era solo il B, senza lo Sheffield e senza porto. Aggiunti tutti e tre
  coi loro porti, B4 chiude sui tre Convogli. Leggendo il Display e' pero'
  emerso che anche la composizione delle Task Force INIZIALI non coincide col
  fascicolo: e' segnata come da verificare invece di essere riscritta in fretta.
- **A B2 mancava meta' dello schieramento.** Il Display delle Task Force
  stampato a p.46 mostra due Gruppi di Rinforzo: il **A** a New York con un
  Convoglio e la Ramilles, il **B** a Gibilterra con Renown, Sheffield e Ark
  Royal. Nei dati c'era solo il B, e senza lo Sheffield. Il Gruppo A e' quello
  che porta il **terzo Convoglio**, e la condizione di fine di B2 ne chiede tre
  mentre lo scenario ne schiera due: senza quel Gruppo la partita non poteva
  finire, e infatti il replay si fermava dichiarando lo stallo. Aggiunti anche
  i porti dei due Gruppi - un Gruppo senza porto trascritto non entra, per
  scelta - e Somerville sul B.
- **B3 aveva una cella sbagliata nella tabella di Identificazione.** La colonna
  3 stampa CV/CA/CA - tre navi - e il dato ne aveva due: una Task Force
  britannica non identificata entrava in Battaglia con un incrociatore in meno.
  E' il tipo di errore che il quarto principio esiste per prevenire, e si e'
  visto solo rileggendo la pagina a 500 dpi. Come N6, B3 non aveva nessuna
  policy propria: ora ce l'ha, con la condizione di fine stampata dentro la 'X'
  (Bismarck affondata o Completata, oppure tre Convogli Completati), il dado
  che sceglie il bersaglio tedesco e i rimandi di meteo della 'A'.
- **A B1 mancava tutto il risultato 'E'.** Le celle e i modificatori delle sue
  quattro tabelle coincidevano gia' col fascicolo e le 22 procedure erano
  segnaposto, ma il difetto vero era nel codice: `_b1` non aveva un ramo per
  la 'E', che finiva nel ripiego e veniva trattata come un Convoglio. La 'E' e'
  pero' **l'unico modo in cui il britannico toglie marker Rendezvous dalla
  mappa**, e la condizione di fine stampata di B1 chiede due o meno marker: la
  partita dipendeva quindi solo dai Controlli Rifornimento del giocatore. La
  'E' porta con se' due fini ("se non ce n'e' nessuno in gioco, lo scenario
  finisce") e la 'X' una terza, a tre Convogli britannici Completati; nessuna
  delle tre scattava.
- **N6 non aveva nessuna policy propria.** Le sue quattro tabelle - Azioni
  Tedesche, Traiettoria Tedesca, T-Seconda Azione, Identificazione - e i
  modificatori coincidevano gia' col fascicolo, e le 25 procedure erano tutte
  segnaposto. Ma il difetto peggiore era nel codice: N6 cadeva nel ripiego
  generico, quindi le **due condizioni di fine stampate dentro i risultati**
  non venivano mai verificate. Sono il "It may also end by the German Action
  Table" del riquadro The End: la 'T' chiude lo scenario quando due Convogli
  tedeschi hanno Completato in Norvegia, la 'X' quando tre o piu' navi tedesche
  sono state perse. Adesso ci sono, insieme ai rimandi di meteo (col Meteo
  Cattivo la 'A' diventa 'X'; senza TF tedesche la 'C' diventa 'A', ma col
  Meteo Cattivo crea una TF a Wilhelmshaven con la scorta tirata sul dado), al
  Passare obbligato a 15 segmenti e ai tiri di destinazione della Traiettoria.
  Jan Mayen e le Azzorre non sono esagoni calibrati: la policy punta al porto
  calibrato piu' vicino e lo dichiara invece di inventare coordinate.
- **N4 e' il primo dei dodici a essere ripreso in mano.** La sua Tabella delle
  Azioni e i modificatori coincidevano gia' col fascicolo; mancava tutto il
  resto. Le sei procedure erano segnaposto che rimandavano a un dump grezzo e
  sono ora trascritte per esteso, e **la Tabella della Reazione Norvegese
  (p.30) e' stata aggiunta**: c'era nel fascicolo e non nei dati. Nel codice
  sono entrate le clausole che il fascicolo stampa e il motore ignorava: il
  primo R4 e' diverso dai successivi (prima si rifacevano sempre TF4 e TF5,
  invece di far Completare a Narvik quelle gia' mandate li'), TF5 imbarca il CL
  francese previsto e non un secondo incrociatore britannico, TF6 entra a
  Methil se nessun DD tedesco ha Completato a Trondheim, il risultato Convoglio
  diventa un R4 quando R4 e' gia' uscito, la X tira PARI/DISPARI dopo un R4 e
  sceglie la TF con Forbes. E soprattutto la X **chiude lo scenario quando non
  c'e' bersaglio**: e' il "(or possibly by Action Table result 'X')" del
  riquadro The End, e senza restava una partita che non finiva.
- **Quattro scenari solitari si giocavano sulla mappa sbagliata.** N1, N2, N3
  e N5 usano una MAPPA INSERTO - Mare di Norvegia o Mare del Nord - come BL3,
  che lo dichiarava. Loro no: piazzavano le Task Force su porti della Mappa
  Operazionale usati come sostituti, Narvik per Vestfjorden, Trondheim per Bud,
  Bergen per Andalsnes. Sono posizioni inventate, ed erano scritte nelle note
  di schieramento senza che nessuno le trattasse come un problema. Ora tutti e
  cinque lo dichiarano e il replay si rifiuta di giocarli; lo schieramento
  trascritto resta in `unplaced_forces`, pronto per quando l'inserto sara'
  calibrato. Il progetto ha percio' **meno** scenari giocabili di ieri, e il
  numero di prima era falso.
- **Le condizioni di fine sono un dato, non quindici rami di codice.** Stavano
  in `SoloAI` per BL1 e BL2; gli altri tredici scenari non finivano mai, e nel
  replay questo si vedeva come "120 turni", cioe' un difetto travestito da
  partita lunga. Ora ogni scenario giocabile ha in `core/data/victory/` il
  riquadro "The End" trascritto dalla pagina renderizzata, col testo inglese e
  la pagina accanto, e `SoloAI` interpreta le poche forme che il fascicolo usa
  davvero. Una forma che l'interprete non conosce rende la regola NON
  soddisfatta: uno scenario che non finisce e' un difetto visibile, uno che
  finisce quando non deve e' una partita sbagliata in silenzio.
- **A2 finiva al turno zero.** La sua condizione e' "the Germans have no Task
  Forces in play (they are sunk or Completed)", e quella parentesi non e' un
  commento: distingue "non ne ha piu'" da "non ne ha ancora". In A2 il tedesco
  le proprie navi le compra coi VP prima della prima azione (p.63), passaggio
  non modellato, quindi la partita comincia senza Task Force tedesche. Senza la
  parentesi lo scenario si dichiarava concluso prima di cominciare.
- **Le due fini di A2 stanno dentro la Tabella di Azione Britannica**, non nel
  riquadro "The End" di p.63. Il risultato 'E' consuma un marker Rendezvous col
  Meteo Cattivo e un marker U-Boat col Meteo Buono, e chiude lo scenario quando
  non ce n'e' piu' da togliere; il risultato 'X' lo chiude se una BB tedesca e'
  affondata, oppure se tre navi tedesche sono affondate, oppure se quattro
  Convogli hanno Completato con successo (pp.67-68). Erano le uniche fini
  stampate rimaste non implementate fra i dieci scenari sulla Mappa
  Operazionale. Il fascicolo da' al tedesco **due marker U-Boat gratis** a
  p.65: il motore ne modella solo il CONTEGGIO, in `solo_counters`, perche' e'
  quello che la fine stampata consuma. La pedina U-Boat sulla mappa resta una
  lacuna dichiarata nel dato dello scenario, e i marker RV di A2 sono zero
  perche' p.63 li dichiara opzionali - con zero, la prima 'E' col Meteo Cattivo
  chiude subito, come stampato.
- **Tutti e dieci gli scenari sulla Mappa Operazionale chiudono ora su una
  condizione stampata**: BL1, BL2, N4, N6, B1, B2, B3, B4, A1, A2. I cinque che
  restano fuori sono i cinque della mappa inserto.
- **I reticoli dei due inserti sono misurati.** `tools/fit_inset_lattice.py`
  isola le linee chiare degli esagoni (luminosita' meno la sua sfocatura), le
  campiona in sola acqua aperta e cerca circumraggio, orientamento e origine
  che massimizzano la risposta lungo i sei lati; l'overlay rosso cade sulle
  linee stampate su tutta e due le mappe. Non c'e' nessun `.vsav` per gli
  inserti, quindi la verita' indipendente usata per la mappa grande qui non
  esiste e la misura si valida sull'immagine: `--check` la rifa' e la confronta
  col dato salvato. Il risultato interessante e' che **i due inserti usano un
  solo reticolo, e quel reticolo e' quello della Mappa Operazionale**: passo
  213.9 px contro 213.5, circumraggio 123.50 contro 123.26, direzione di base
  44.25 gradi contro 44.28. **Non basta a sbloccare i cinque scenari**: il
  reticolo e' la geometria, non la mappa.
- **Gli esagoni degli inserti hanno un nome, un terreno e le adiacenze.**
  `tools/build_inset_graph.py` scrive `core/data/inset_graphs.json`: coordinate
  assiali `(q, r)` come la mappa grande, con l'origine ancorata all'angolo
  della cornice stampata, che e' misurata e non scelta. 29 esagoni sul Mare del
  Nord, 27 sul Mare di Norvegia. Sono trovati anche i **16 porti stampati**, con
  i nomi letti sulla mappa e accoppiati ai pallini uno a uno: un pallino senza
  nome o un nome senza pallino fermano il programma. I cerchi vuoti dei porti si
  distinguono dalle lettere 'o' ed 'e' delle etichette perche' il loro cuore e'
  bianco pieno.
  Una cosa l'ha insegnata la verifica, non il progetto: la classificazione per
  colore da sola **buttava via otto esagoni che contengono un porto** - Methil,
  Wilhelmshaven, Kiel, Kristiansand, Trondheim, Namsos, Andalsnes e Tromso,
  meta' terraferma tutti. La mappa grande aveva gia' la regola giusta
  (`force_playable`) e serviva anche qui. Otto esagoni restano marcati
  `needs_check` perche' terra e mare sono quasi pari, e quelli scartati per un
  soffio restano scritti col motivo.
- **Le nove frecce "non adiacente" degli inserti sono trascritte.** RB p.4 e
  FAQ p.44: negano la Traiettoria fra i due esagoni che collegano, e lasciano
  passare il Supporto Aereo. Sei sul Mare del Nord, tre sul Mare di Norvegia.
  Le posizioni sono lette sulle immagini ingrandite col reticolo etichettato
  sopra; il lato lo ricava il programma dai due esagoni piu' vicini, e si ferma
  se non risultano adiacenti - il che e' anche il controllo che la lettura sia
  giusta. Quattro lati escono `disputed` perche' toccano esagoni che il colore
  aveva scartato: una freccia si stampa per negare un'adiacenza, e negarla ha
  senso solo fra esagoni in gioco. Non e' deciso di nascosto, e' segnato.
- **Le sette caselle fuori mappa degli inserti sono trascritte**, e per farlo
  sono venute fuori due cose che avevo sbagliato prima.
  La prima: i pallini PIENI sono porti, i cerchi VUOTI sono **Punti di
  Interesse** (p.16, "no effect on game play, except to orient the player"), e
  io li avevo messi tutti insieme come porti. Sono 5 porti e 3 punti sul Mare
  del Nord, 2 porti e 6 punti sul Mare di Norvegia. Il loro esagono conta lo
  stesso: p.16 permette il Completamento in un esagono di Norvegia con un
  Convoglio o uno Squadrone DD, e N1 chiede di posare le Mine "in the hexes
  with Bud and Andalsnes".
  La seconda, piu' grossa: **le frazioni di terreno si misurano sull'area di
  mappa**, dentro la cornice, non sull'area intera dell'esagono. La parte oltre
  la cornice non e' terra: non e' mappa. Contarla contro l'esagono bocciava
  mezzo bordo. Gli esagoni passano da 29 a 34 e da 27 a 33, e (7,1) del Mare
  del Nord - Kiel Bay - passa dal 39% all'88% di mare. Due dei quattro lati
  "non adiacente" marcati `disputed` si sono risolti da soli: erano un indizio
  buono, e la classificazione era sbagliata.
  Le caselle sono Norwegian Sea, Kiel e Portsmouth sul Mare del Nord; Murmansk,
  Denmark Strait, Scapa Flow e Kiel sul Mare di Norvegia. Il fascicolo le usa:
  p.18 manda a Completare "in nearest Denmark Strait port hex" e mette Murmansk
  e Kiel nella Tabella dei Porti; p.17 fa Completare a Scapa Flow i Convogli
  britannici di N1 e ci fa partire i Gruppi Rinforzo. Quali esagoni una banda
  designi non e' scritto: si prendono quelli che tocca, e la percentuale di
  contatto resta nel dato.
- **Le basi aeree degli inserti sono trovate e collocate.** Sette sul Mare del
  Nord: cinque britanniche lungo la costa inglese e scozzese, due tedesche allo
  Skagerrak e a Horns Reef. **Zero sul Mare di Norvegia**, e l'elenco vuoto e'
  un dato: non e' una dimenticanza. Il rilevatore le isola col bianco puro del
  disco, che sulla mappa stampata non ha quasi concorrenza, e legge la parte dal
  colore della lettera e dell'aereo - B rossa britannica, G viola tedesca.
  Posizione e parte sono anche trascritte a mano, e se le due letture non
  combaciano il programma si ferma.
  La regola e' RB p.27: la base aerea e' la fonte dell'Attacco Aereo, che parte
  dal suo esagono, si fa solo col Meteo Buono e non arriva oltre due esagoni dal
  Punto di Lancio; la base aerea non puo' essere il bersaglio.
  **Con questo il dato di mappa degli inserti e' completo**: reticolo, esagoni,
  terreno, adiacenze, porti, punti di interesse, caselle fuori mappa, frecce
  "non adiacente" e basi aeree.
- **Il grafo degli inserti e' verificato contro il fascicolo.** La verita'
  indipendente che per due passaggi era sembrata non esistere c'era: le
  illustrazioni di schieramento dei cinque scenari disegnano i segmenti di
  Traiettoria iniziali SULLA mappa, e nel PDF non sono pixel, sono grafica
  vettoriale con coordinate esatte. L'illustrazione riusa la stessa immagine
  dell'inserto, quindi la sua collocazione sulla pagina da' la registrazione, e
  il reticolo gia' misurato da' l'esagono. **46 forme da segmento su cinque
  pagine, tutte dentro esagoni che il grafo dichiara giocabili, zero fuori.**
  `tools/validate_inset_setups.py` non prova a distinguere i segmenti veri
  dalle pedine disegnate nei riquadri di regola incollati sopra la mappa: per
  farlo bisognava mascherare per rettangolo, e il rettangolo di un riquadro
  copre anche segmenti veri che gli passano accanto - si perdevano tre
  controlli su quarantasei per guadagnare un conteggio piu' bello. Il conteggio
  non serve, il controllo si'. Le forme dentro un riquadro sono marcate e
  controllate come le altre.
  **Sette incertezze su dieci si chiudono**: sei esagoni `needs_check` del Mare
  del Nord e uno del Mare di Norvegia hanno un segmento stampato dentro, e un
  esagono in cui il fascicolo disegna una Traiettoria e' giocabile - e' un dato
  stampato, e batte una soglia di colore.
- **Il motore carica le due mappe inserto.** Non e' servita una classe nuova:
  `MapGraph` era gia' generico e ora ha `load_inset(chiave)`, che traduce la
  forma del dato inserto in quella che sa gia' leggere. Geometria, adiacenze e
  porti restano un solo pezzo di codice, perche' il reticolo dell'inserto e'
  quello della mappa grande; le frecce "non adiacente" diventano
  `blocked_edges`, che e' la stessa regola con un altro nome. Basi aeree, Punti
  di Interesse e caselle fuori mappa sono esposti come dato: il motore non
  gioca ancora gli Attacchi Aerei da base aerea, e i Punti di Interesse per
  regola non fanno nulla.
  Scrivendo il caricatore ho preso due trappole, e vale la pena scriverle
  perche' **nessuna delle due si vedeva nei numeri**: i centri degli esagoni
  arrivano dal JSON e restavano giusti in entrambi i casi. La prima: il dato
  inserto salva `theta_deg` come angolo dei VERTICI, mentre `hex_corners()` lo
  intende come direzione di BASE - 30 gradi di differenza, esagoni ruotati, e
  si vede solo guardando la mappa. La seconda: le `(q,r)` dell'inserto sono
  ribasate sull'angolo della cornice, quindi senza scrivere nel dato l'origine
  ribasata `hex_to_pixel` sbagliava di una cella e mezzo. Adesso cinque test le
  inchiodano misurando circumraggio, inraggio e l'allineamento dei vertici
  rispetto ai vicini: se theta e' sbagliato di 30 gradi un vertice punta dritto
  su un vicino e il coseno passa da 0.866 a 1.
- **L'interfaccia disegna l'inserto come superficie di gioco.** Aprendo uno dei
  cinque scenari, la mappa inserto prende il posto della Mappa Operazionale:
  `MapBoard` carica una texture sola - 1020x1320, meno di un tile e mezzo -
  invece dei quindici tile della mappa grande, e il disegno del reticolo non
  cambia di una riga perche' e' tutto guidato dal `MapGraph`. Il grafo e' pero'
  condiviso da stato, tabellone, Traiettorie e camera: se uno solo restasse
  puntato sulla mappa di prima non si vedrebbe un errore, si vedrebbe una
  partita giocata sulle coordinate sbagliate. `tools/smoke_inset_map.gd` apre
  l'interfaccia vera e controlla che cambino tutti insieme, e che tornare a uno
  scenario normale rimetta la Mappa Operazionale coi suoi tile.
  Il testo che i cinque scenari mostravano - "reticolo e coordinate non
  calibrati" - era ormai falso ed e' stato corretto.
- **Il Completamento in Norvegia si gioca, nel ciclo headless e nella GUI.**
  `core/rules/norway.gd` ha le tre differenze stampate a p.16 - serve un
  Convoglio o uno Squadrone DD, la Task Force NON viene rimossa ma fa Scorrere
  del Tempo, e l'avversario immaginario invece la perde - piu' le quattro
  tabelle di Reazione Norvegese (pp.19, 24, 27, 34) col tiro e l'applicazione.
  N1 posa davvero le sue Mine, che erano l'obiettivo dello scenario.
  Nella GUI l'azione e' una SCELTA esplicita, non un automatismo: le due strade
  portano a esiti diversi - sbarcare tiene la Task Force in gioco, entrare in
  porto la toglie - e la scelta e' del giocatore.
  Due difetti li ha trovati il replay, non io: la regola vale solo per gli
  scenari 'N' (senza il vincolo, A1 e N5 sbarcavano a ogni turno perche' hanno
  Narvik e Trondheim sulla loro mappa), e siccome la TF non viene rimossa lo
  sbarco si poteva ripetere all'infinito. Il secondo divieto e' della policy,
  non della regola: il fascicolo non ne ha bisogno perche' un giocatore non lo
  farebbe.
- **Le forze Furtive esistono nel motore.** `core/rules/stealth.gd` e
  `GameState.stealth_forces` implementano RB p.41: i tre tipi (Mine,
  Sottomarini, U-Boat), la Ricognizione come PIAZZAMENTO e non movimento - il
  regolamento dice che "non fa differenza dove la forza Furtiva e' al momento in
  cui viene annunciata l'azione" - le restrizioni (mai su porto o Base Aerea
  nemici, ma PERMESSO su una Task Force nemica con un CV, che il regolamento
  specifica apposta), le Informazioni assegnate a ogni TF nemica nell'esagono,
  e la restrizione all'attacco: una Traiettoria e' immune finche' il segmento
  bersaglio non ha un Contatto o delle Informazioni, una Stazione no. E' quella
  che da' un senso al segnalino Contatto, ed e' la prima cosa che i test
  difendono. Salvataggio compreso.
  Chiusa per strada una promessa vecchia: il commento di `triggers_info`
  elencava le quattro cause di RB p.21 e il codice ne implementava tre, perche'
  la quarta - la forza Furtiva - non aveva una pedina.
  Lacuna dichiarata dentro il nucleo: le Informazioni stanno sui SEGMENTI,
  quindi una Ricognizione su una TF nemica che e' Stazione le dichiara invece di
  assegnarle. Restano fuori il piazzamento dallo schieramento degli scenari, la
  procedura Mine di N1, il collegamento alla tabella `STEALTH_ATTACK` (gia'
  trascritta e verificata) e il disegno nella GUI.
- **BL3 si gioca sul suo inserto: e' l'undicesimo scenario solitario che chiude
  su una condizione stampata**, e il primo fuori dalla Mappa Operazionale.
  Lo schieramento e' letto dall'illustrazione di p.12: cinque segmenti in fila,
  (1,2) (2,1) (3,0) (4,-1) (5,-2) da Methil verso Bergen, che sono la
  Traiettoria della TF britannica non identificata; e un cilindro Stazione in
  (5,2), vicino a Heligoland, che il pannello Task Force identifica come la TF
  tedesca - stesso set colore bianco a riga blu di Scharnhorst, Gneisenau e
  Hipper. `SoloRunner` sceglie la mappa dallo scenario, come gia' fa
  l'interfaccia. La fine stampata di p.12 e' stata aggiunta come condizione: "no
  Task Forces in play, or two Convoys and/or Unidentified TFs Completed or
  destroyed" - la seconda meta' e' una forma nuova, perche' conta due categorie
  insieme e conta sia i Completamenti sia le distruzioni.
  Il marker Sommergibile britannico e' in (5,1): la posizione e' letta, ma le
  forze Furtive permanenti non sono ancora una pedina modellata, quindi resta
  lacuna dichiarata.
  Tre test hanno cambiato premessa insieme al fatto: controllavano che gli
  scenari inserto NON avessero schieramento, e adesso controllano che le loro TF
  stiano sulla PROPRIA mappa. E' il difetto vero da cui erano nati - le
  posizioni inventate su porti sostitutivi - espresso in un modo che sopravvive
  al progresso.
  **Anche N1 si gioca.** Il nodo era nel testo, non nella geometria: la pagina
  dice "Enemy: No German TFs at start" e insieme stampa un riquadro sui Convogli
  tedeschi. p.19 lo scioglie - quei Convogli li crea a Kiel la Tabella delle
  Azioni tedesche - quindi tutti i 18 segmenti disegnati sono britannici. La
  striscia bianca sul segmento fa il resto: otto lisci in fila da Scapa Flow a
  Vestfjorden sono Renown e Squadrone DD, gli otto striati sono due Traiettorie
  parallele di Convogli posamine, e il terzo Convoglio e' il cilindro Stazione
  in (2,5). I richiami di p.17 mandano Valiant, Repulse, Rodney e Sheffield con
  Forbes nel Gruppo Rinforzo A e Birmingham nel B.
  Le Mine restano lacuna dichiarata, ed e' scomodo perche' sono l'obiettivo
  dello scenario: le forze Furtive permanenti non sono ancora una pedina.
  **Anche N2 si gioca.** Due Traiettorie che salgono da Kiel, una a Narvik e una
  a Trondheim, e l'assegnazione viene dal pannello Task Force di p.21: lo slot
  con la banda blu tiene Hipper e lo Squadrone DD, l'altro Scharnhorst,
  Gneisenau e il Convoglio - che e' anche quello che dice l'obiettivo stampato.
  Il rilevatore automatico della banda resta rotto su N2 e N3 e il tentativo di
  sistemarlo e' fallito: cercare il contrasto col segmento invece del bianco
  assoluto fa risultare bandati tutti i segmenti, perche' ognuno e' disegnato in
  piu' pezzi di colore diverso, e filtrare per lunghezza non separa l'ombra
  dalla banda. Tentativo annullato, flag lasciato dichiarato inaffidabile, e
  l'assegnazione letta a occhio sull'illustrazione - che e' il metodo che il
  progetto usa per le tabelle.
  **Anche N3 si gioca**, gemello di N2 sull'altro inserto: due Traiettorie che
  salgono dai porti tedeschi condividendo la coda, una a Bergen e una a
  Kristiansand, con Konigsberg/Koln/Convoglio nello slot liscio e
  Karlsruhe/Squadrone DD in quello con la banda blu. Il segnalino Informazioni
  che la pagina prescrive "in Kristiansand" e' nel campo info del segmento
  (6,-1). Anche qui la banda e' letta a occhio, perche' il rilevatore su questa
  pagina esce invertito.
  **Anche N5 si gioca, e con lui tutti e quindici i solitari chiudono su una
  condizione stampata.** La sua illustrazione non disegna segmenti perche' non
  c'e' niente da disegnare: "all TFs start in Scapa Flow". La composizione delle
  Task Force e' una scelta del giocatore - unico vincolo stampato, un Convoglio
  puo' condividere la TF con una sola altra nave, un CA o un CL - e l'app parte
  da un'organizzazione di ripiego dichiarata, come BL2 con le sue navi 'any' e
  A2 con l'acquisto in VP.
  **Le lacune che restano sono DENTRO gli scenari, non piu' scenari fermi**:
  Mine e forze Furtive permanenti (che sono l'obiettivo di N1), Reazione
  Norvegese, Completamenti in Norvegia, i due CA 'any' di N5 e i suoi Punti
  Rinforzo.
- **I Comandanti dicono la loro condizione stampata.** Gli undici testi sono
  trascritti da RB p.10 letta a 300 dpi: la scheda TF mostra la regola vera e
  non un riassunto, ed e' quella che decide se il beneficio si puo' usare
  adesso. Nella voce **Forbes** la traduzione italiana ripete "la TF di
  Marschall": le due voci sono identiche parola per parola e la clausola parla
  della TF del Comandante che usa il beneficio - preso alla lettera, un
  comandante britannico vincolerebbe una Task Force tedesca. Il refuso e'
  dichiarato in `FORBES_TRANSLATION_NOTE`, non ricopiato nel codice. E il nome
  dell'azione e' stato allineato allo stampato: **Passare Tutto**, non
  "Passare Tutti".
- **Gensoul e' implementato.** Quando la sua Task Force e' designata Attiva
  toglie un segnalino Informazioni da una TF designata nell'Azione corrente,
  una volta per scenario. L'offerta arriva PRIMA della risoluzione, e non e'
  un dettaglio: l'Interruzione (RB p.22) si tira proprio sui segnalini delle
  TF designate, quindi toglierne uno dopo non servirebbe a niente - ed e'
  esattamente a quello che serve il beneficio.
- **Il B-Dienst esiste.** Il servizio di decrittazione tedesco (p.5) attacca un
  segnalino Informazioni a un segmento di Traiettoria britannica, con
  l'Iniziativa tedesca e una volta sola per scenario. Sta nel menu Solitario:
  la regola e' nel core, la scelta del segmento resta al giocatore, com'e'
  giusto - non e' una procedura del bot, e' una facolta' sua.
- **La Tabella Murmansk era trascritta scalata di una colonna.** Il fascicolo
  (p.8) dice `0 o meno` = confisca, `1-2` = incidente, `3-6` = salvi; la
  trascrizione faceva confiscare le navi con un **1**, cioe' nel caso comune
  invece che in quello estremo raggiungibile solo col modificatore -1. Ora la
  riga parte da `roll_min: 0`, e il controllo si tira da solo prima del
  Debriefing - nel replay e nel pannello Punteggio - invece di restare una
  tabella da leggere a mano.
- **La clausola "4 o piu' CA" della 'A'** (p.7): con quattro CA britannici in
  gioco e nessun bersaglio aereo il risultato vale come 'A' *e* 'F' insieme,
  con la TF francese Attiva e quella britannica Coordinatrice. La Coordinatrice
  viene designata solo se occupa davvero l'esagono Bersaglio (RB p.47): fuori
  da li' renderebbe illegale l'intera azione invece di aiutarla.
- **Tre regole di BL1 allineate al fascicolo:** la 'A' con Meteo Cattivo
  diventa 'X' solo se una TF britannica ha un CA, altrimenti 'B' (p.7); i
  risultati F e X invocano i **Limiti di Carburante** a tre e a due Convogli
  britannici Completati (p.8); South America e' chiuso al tedesco finche' il
  risultato a. della Tabella del Rifornimento non lo apre (p.5-6).
- **Una lacuna del fascicolo, dichiarata invece di tappata.** Se il tedesco
  perde tutte le Task Force e i Rinforzi mentre restano tre marker Rendezvous,
  la condizione di fine stampata non puo' piu' avverarsi: un RV si rimuove solo
  con un Controllo Rifornimento, che richiede una Stazione tedesca. Il replay
  si ferma e lo dice (`STALLO`, 9 semi su 40 provati); non inventa una fine.

### Cosa e' cambiato nella sessione precedente

- **Le Regole Avanzate si possono finalmente accendere.** Erano complete e
  verdi nei test, ma `BattleState.advanced` restava a `false` e nessuno lo
  metteva mai a `true`: circa 240 verifiche coprivano codice che in partita non
  girava. Ora c'e' una casella nella schermata iniziale, la scelta viaggia
  Session -> GameState -> BattleState e finisce nel salvataggio. La prova di
  fumo gira due volte, base e avanzata (`-- adv`), ed e' la rete che impedisce
  a questo difetto di tornare.
- **L'attitudine e gli Effetti Speciali si vedono.** La vista chiedeva di
  cambiare l'attitudine di una nave senza mostrare quale fosse.
- **Le pedine erano sopra tutto il resto**: erano TextureRect figli del
  Control, e i figli disegnano sopra il `_draw()` del genitore, quindi il badge
  dei Colpi, il FUMO e il bordo di selezione finivano *sotto* la pedina.
- **Effetti visivi e sonori della Battaglia**, che prima non esistevano
  affatto. I suoni sono **sintetizzati** da `tools/make_sounds.py` con numpy:
  nessun campione di terzi, nessuna licenza, seme fisso.
- **Traiettorie**: corsie per non sovrapporsi, angoli curvi (Bezier col vertice
  come punto di controllo), linea piu' sottile, badge col nome.
- **Esagoni non giocabili esclusi manualmente** quando la classificazione
  automatica confondeva lo sfondo esterno o quello delle tabelle con il mare.
  Le esclusioni autorevoli stanno in `core/data/map_annotations.json`.
- **Pannello "ora tocca a"**, coi motivi per cui un'azione non e' dichiarabile
  raggruppati per motivo invece che elencati per azione.

#### (piu' vecchio)

### Cosa e' cambiato allora

- **Le ultime due azioni**: Riorganizzazione (dividere, unire, chiamare
  rinforzi) e Segnalazione. Tutte e nove le azioni del gioco sono ora
  trascritte e dichiarabili.
- **Le regole speciali dei Convogli**: dispersione (incassa un Colpo per
  attacco invece di tutti, ma vale un punto in meno all'arrivo — e non si
  torna indietro) e azioni vietate a chi scorta.
- **Il finale di partita**: dopo tre Convogli arrivati al tedesco restano
  quattro azioni e l'obbligo di rientrare se può.
- **Salvare e riprendere**, col generatore di dadi dentro il salvataggio — un
  bug preso dai test: lo stato del RNG è un intero a 64 bit e JSON lo
  degradava a float, quindi ricaricare dava una partita *simile*, non la
  stessa.
- **Le condizioni di vittoria di tutti e 22 gli scenari.** I mini-scenari
  hanno rivelato un **quarto** modello: non contano punti, hanno quattro
  caselle Decisiva/Marginale da riempire.
- **Il modo solitario è cominciato**: motore delle tabelle a dado, Task Force
  *non identificate*, e le tabelle di BL1 e BL2 trascritte per intero.
- **La Campagna non era rotta**: non è uno scenario, è la riserva navi delle
  nove Operazioni. Ora viene importata.

### Cosa era cambiato nella sessione precedente

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
- Lo Scorrere del Tempo compare soltanto quando lo innesca un'Azione o un
  evento; non ha comando autonomo. **Ctrl+W** cambia il meteo.
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
| esagoni giocabili | 129 |

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

### 0. Ultime scelte delle Regole Avanzate di Battaglia

L'audit del 3 agosto 2026 ha collegato la sequenza completa, i vincoli
direzionali delle Attitudini, i Siluri una volta per partita, Snafu, ingressi
ritardati e i segnalini GMT visibili. Restano quattro decisioni che il motore
conosce solo in parte ma che la GUI non fa ancora compiere correttamente:
Plancia (niente Fuoco oppure Ferma), il controllo avversario con Timone Fuori
Uso, i tre usi del segnalino Confusione e la divisione del fuoco in
Acquisizione. Anche MS12 richiede ancora la sua struttura speciale in tre
parti; non va giocato come una singola Battaglia ordinaria.

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
