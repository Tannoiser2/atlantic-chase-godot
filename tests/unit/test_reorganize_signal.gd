extends TestCase

## Riorganizzazione (RB p.37), Segnalazione (RB p.39) e le regole speciali
## dei Convogli (RB p.11).

var graph: MapGraph


func name() -> String:
	return "Riorganizzazione / Segnalazione / Convogli"


func run() -> void:
	graph = MapGraph.load_default()
	test_split()
	test_split_refusals()
	test_merge()
	test_reinforcement()
	test_signal_targets()
	test_signal_resolve()
	test_convoy_rules()
	test_convoy_dispersal()
	test_scenario_rules()
	test_endgame()
	test_convoy_counter()
	test_savegame()
	test_campaign_pool()


func _state() -> GameState:
	return GameState.new(graph, 77)


func _tf(state: GameState, side: int, ships: Array[String],
		h: Vector2i) -> TaskForce:
	var tf := TaskForce.new(0, side)
	tf.color = "GE" if side == TaskForce.Side.KRIEGSMARINE else "Brown"
	tf.slot = Reorganize.in_play(state, side).size()
	tf.name = "TF%d" % (state.task_forces.size() + 1)
	tf.trajectory = Trajectory.new()
	tf.trajectory.become_station(h)
	for n in ships:
		var s := ShipRoster.shared().make(n)
		tf.ships.append(s if s != null else Ship.new(n))
	tf.recompute_speed()
	return state.add_task_force(tf)


# ------------------------------------------------------------------ dividere --

func test_split() -> void:
	_begin("dividere una Task Force")
	var st := _state()
	var h := Vector2i(15, -5)
	var tf := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck", "Preugen", "Hipper"] as Array[String], h)
	tf.trajectory.station_contact = true
	tf.evasive = true

	var moving: Array[Ship] = [tf.ships[1], tf.ships[2]]
	var r := Reorganize.split(st, tf, moving, true, false)
	true_(r["ok"], "la divisione riesce")
	var nt: TaskForce = r["new_tf"]
	eq(tf.ships.size(), 1, "una nave resta")
	eq(nt.ships.size(), 2, "due passano alla nuova")
	eq(nt.trajectory.station_hex, h, "nello stesso esagono")
	eq(nt.side, tf.side, "e dalla stessa parte")

	# i segnalini si SPOSTANO, non si moltiplicano: la divisione non ne crea
	false_(tf.trajectory.station_contact, "il Contatto lascia la vecchia")
	true_(nt.trajectory.station_contact, "e passa alla nuova")
	true_(tf.evasive, "le Manovre Evasive restano dov'erano")
	false_(nt.evasive, "e non si duplicano")

	eq(st.forces_of(TaskForce.Side.KRIEGSMARINE).size(), 2, "ora sono due")


func test_split_refusals() -> void:
	_begin("quando non si puo' dividere")
	var st := _state()
	var h := Vector2i(15, -5)

	# una nave sola non si divide
	var solo := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck"] as Array[String], h)
	true_(Reorganize.split_refusal(st, solo).contains("due navi"),
		"serve piu' di una nave")

	# una Traiettoria non si divide: solo le Stazioni
	var moving := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Scharnhorst", "Gneisenau"] as Array[String], h)
	moving.trajectory.extend(Vector2i(16, -5), 1, graph)
	true_(Reorganize.split_refusal(st, moving).contains("Stazione"),
		"solo una Stazione puo' dividersi")

	# con tutte le caselle occupate la divisione e' proibita
	var st2 := _state()
	for i in Reorganize.max_task_forces(TaskForce.Side.KRIEGSMARINE):
		_tf(st2, TaskForce.Side.KRIEGSMARINE,
			["Bismarck", "Tirpitz"] as Array[String], h)
	eq(Reorganize.free_slots(st2, TaskForce.Side.KRIEGSMARINE), 0,
		"cinque Task Force tedesche, nessuna casella libera")
	true_(Reorganize.split_refusal(st2, st2.task_forces[0]).contains("gia' in gioco"),
		"e la divisione e' proibita")
	# quelle britanniche sono dieci, e sono un conto separato
	eq(Reorganize.max_task_forces(TaskForce.Side.ROYAL_NAVY), 10,
		"dieci caselle britanniche")


# --------------------------------------------------------------------- unire --

func test_merge() -> void:
	_begin("unire due Task Force")
	var st := _state()
	var h := Vector2i(15, -5)
	var a := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck"] as Array[String], h)
	var b := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Preugen", "Hipper"] as Array[String], h)
	b.trajectory.station_contact = true
	b.evasive = true

	eq(Reorganize.merge_refusal(a, b), "", "si possono unire")
	var r := Reorganize.merge(a, b)
	true_(r["ok"], "l'unione riesce")
	eq(a.ships.size(), 3, "tutte le navi in una sola Task Force")
	eq(b.ships.size(), 0, "l'altra resta vuota")
	true_(a.trajectory.station_contact, "il Contatto passa a quella che resta")
	true_(a.evasive, "e cosi' le Manovre Evasive")
	false_(b.evasive, "che non restano anche sull'altra")

	# la pedina svuotata torna disponibile
	eq(Reorganize.in_play(st, TaskForce.Side.KRIEGSMARINE).size(), 1,
		"in gioco ne resta una")
	true_(Reorganize.free_slots(st, TaskForce.Side.KRIEGSMARINE) >= 4,
		"e le caselle libere sono tornate")

	# esagoni diversi: non si uniscono
	var c := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Tirpitz"] as Array[String], Vector2i(16, -5))
	true_(Reorganize.merge_refusal(a, c).contains("stesso esagono"),
		"servono nello stesso esagono")
	# parti diverse: nemmeno
	var d := _tf(st, TaskForce.Side.ROYAL_NAVY, ["Hood"] as Array[String], h)
	true_(Reorganize.merge_refusal(a, d).contains("parti diverse"),
		"e dalla stessa parte")
	# una Traiettoria non si unisce
	c.trajectory.become_station(h)
	c.trajectory.extend(Vector2i(16, -5), 1, graph)
	true_(Reorganize.merge_refusal(a, c).contains("Stazioni"),
		"solo Stazioni, non Traiettorie")


# ----------------------------------------------------------------- rinforzi --

func test_reinforcement() -> void:
	_begin("tentativo di Rinforzo")
	var kiel := graph.port_hex("Kiel")
	var group: Array = ["Koln", "Konigsberg"]

	# 2d6 >= 7 riesce. Con i tiri imposti si controlla il confine esatto.
	var st := _state()
	_tf(st, TaskForce.Side.KRIEGSMARINE, ["Bismarck"] as Array[String], kiel)
	st.rng.push_forced([3, 4])          # somma 7: il minimo che riesce
	var r := Reorganize.attempt_reinforcement(st, TaskForce.Side.KRIEGSMARINE,
		kiel, group, "A")
	true_(r["ok"], "il tentativo si esegue")
	eq(int(r["roll"]), 7, "2d6 = 7")
	true_(r["success"], "e 7 basta")
	false_(r["initiative_passes"], "l'Iniziativa resta")
	eq((r["tf"] as TaskForce).ships.size(), 3,
		"le navi entrano nella Stazione gia' in porto")

	# 6 fallisce, e il fallimento costa l'Iniziativa
	var st2 := _state()
	_tf(st2, TaskForce.Side.KRIEGSMARINE, ["Bismarck"] as Array[String], kiel)
	st2.rng.push_forced([3, 3])
	var r2 := Reorganize.attempt_reinforcement(st2, TaskForce.Side.KRIEGSMARINE,
		kiel, group, "A")
	eq(int(r2["roll"]), 6, "2d6 = 6")
	false_(r2["success"], "e 6 non basta")
	true_(r2["initiative_passes"], "l'Iniziativa passa all'avversario")
	eq(st2.task_forces[0].ships.size(), 1, "nessuna nave entra in gioco")

	# senza Stazione in porto si crea una Task Force nuova
	var st3 := _state()
	st3.rng.push_forced([5, 5])
	var r3 := Reorganize.attempt_reinforcement(st3, TaskForce.Side.KRIEGSMARINE,
		kiel, group, "A")
	true_(r3["success"], "riuscito")
	var nt: TaskForce = r3["tf"]
	eq(nt.trajectory.station_hex, kiel, "la nuova Task Force nasce in porto")
	eq(nt.ships.size(), 2, "con le navi del Gruppo")

	# senza Stazione in porto E senza caselle libere, e' proibito
	var st4 := _state()
	for i in Reorganize.max_task_forces(TaskForce.Side.KRIEGSMARINE):
		_tf(st4, TaskForce.Side.KRIEGSMARINE, ["Tirpitz"] as Array[String],
			Vector2i(10, 0))
	var r4 := Reorganize.attempt_reinforcement(st4,
		TaskForce.Side.KRIEGSMARINE, kiel, group, "A")
	false_(r4["ok"], "il tentativo e' proibito")
	true_(String(r4["error"]).contains("proibito"), "e lo dice")
	eq(int(r4["roll"]), 0, "senza nemmeno tirare i dadi")


# ---------------------------------------------------------------- segnalare --

## Task Force con una Traiettoria che passa per `seg`.
## Attenzione: la Stazione di partenza NON resta come segmento - una volta che
## ci sono segmenti, la Traiettoria e' fatta solo di quelli.
func _traj_tf(st: GameState, side: int, seg: Array[Vector2i]) -> TaskForce:
	var tf := _tf(st, side, ["Bismarck", "Preugen"] as Array[String],
		Vector2i(15, -5))
	for h in seg:
		tf.trajectory.extend(h, 1, graph)
	return tf


func test_signal_targets() -> void:
	_begin("chi si puo' segnalare")
	var st := _state()
	# catena davvero adiacente sulla mappa: fra 15,-5 e 15,-4 c'e' una delle
	# frecce "not adjacent", quindi quel lato non si puo' percorrere
	var path: Array[Vector2i] = [Vector2i(16, -5), Vector2i(17, -5),
		Vector2i(18, -6)]
	var km := _traj_tf(st, TaskForce.Side.KRIEGSMARINE, path)
	eq(km.trajectory.length(), 3, "la Traiettoria ha tre segmenti")

	# senza segnalini Informazioni non c'e' niente da segnalare
	true_(SignalAction.refusal(km).contains("Informazioni"),
		"senza segnalini la Segnalazione e' rifiutata")
	eq(SignalAction.target_hexes(km).size(), 0, "e nessun esagono bersaglio")

	km.trajectory.set_info(1, true)
	eq(SignalAction.refusal(km), "", "con un segnalino si puo'")
	var hs := SignalAction.target_hexes(km)
	eq(hs.size(), 1, "un solo esagono bersaglio")
	eq(hs[0], path[1], "quello del segnalino")

	# una Stazione non si segnala: e' gia' localizzata
	var station := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Tirpitz"] as Array[String], Vector2i(18, -6))
	true_(SignalAction.refusal(station).contains("gia' una Stazione"),
		"una Stazione non si segnala")

	# i candidati sono solo gli avversari con almeno un segnalino
	var cands := SignalAction.candidates(st, TaskForce.Side.ROYAL_NAVY)
	eq(cands.size(), 1, "un solo bersaglio legale")
	eq(cands[0], km, "ed e' la Traiettoria con il segnalino")
	eq(SignalAction.candidates(st, TaskForce.Side.KRIEGSMARINE).size(), 0,
		"il tedesco non puo' segnalare se stesso")


func test_signal_resolve() -> void:
	_begin("risolvere la Segnalazione")
	var st := _state()
	# catena davvero adiacente sulla mappa: fra 15,-5 e 15,-4 c'e' una delle
	# frecce "not adjacent", quindi quel lato non si puo' percorrere
	var path: Array[Vector2i] = [Vector2i(16, -5), Vector2i(17, -5),
		Vector2i(18, -6)]
	var km := _traj_tf(st, TaskForce.Side.KRIEGSMARINE, path)
	km.trajectory.set_info(0, true)
	km.trajectory.set_info(2, true)
	km.trajectory.set_contact_at(path[2], true)

	# un esagono senza segnalino non e' un bersaglio legale
	var bad := SignalAction.resolve(km, path[1])
	false_(bad["ok"], "in un esagono senza segnalino non si segnala")

	var r := SignalAction.resolve(km, path[2])
	true_(r["ok"], "la Segnalazione riesce")
	true_(km.trajectory.is_station(), "la Traiettoria diventa una Stazione")
	eq(km.trajectory.station_hex, path[2], "nell'esagono scelto")
	eq(int(r["removed_segments"]), 3, "i tre segmenti sono rimossi")
	true_(r["contact"], "il Contatto del segmento bersaglio si trasferisce")
	true_(km.trajectory.station_contact, "e la Stazione ce l'ha")
	eq(km.trajectory.info_count(), 0,
		"gli altri segnalini Informazioni spariscono con i segmenti")

	# il Contatto su un ALTRO segmento invece si perde: sapere dove una flotta
	# e' passata non e' sapere dove si trova
	var st2 := _state()
	var km2 := _traj_tf(st2, TaskForce.Side.KRIEGSMARINE, path)
	km2.trajectory.set_info(2, true)
	km2.trajectory.set_contact_at(path[0], true)
	var r2 := SignalAction.resolve(km2, path[2])
	true_(r2["ok"], "riesce lo stesso")
	false_(r2["contact"], "ma il Contatto altrove si perde")
	false_(km2.trajectory.station_contact, "e la Stazione non ce l'ha")


# ----------------------------------------------------------------- convogli --

func _convoy(nation: String = "UK") -> Ship:
	var c := ShipRoster.shared().make(
		"Convoy x3" if nation == "UK" else "Convoy x2")
	if c == null:
		c = Ship.new("Convoglio", TimeLapse.Speed.SLOW, Ship.Kind.CONVOY)
		c.nation = nation
	return c


func test_convoy_rules() -> void:
	_begin("le quattro regole speciali dei Convogli")
	var c := _convoy()
	eq(c.kind, Ship.Kind.CONVOY, "il Convoglio e' di tipo CONVOY")
	true_(Convoy.is_convoy(c), "e lo si riconosce")

	# 1. carico prezioso: non si danneggia
	false_(c.can_be_damaged(), "un Convoglio non puo' essere Danneggiato")
	# 2. niente Fumo, ma ne beneficia
	false_(Maneuver.can_make_smoke(c), "e non puo' produrre Fumo")

	# 4. azioni limitate
	var st := _state()
	var tf := _tf(st, TaskForce.Side.ROYAL_NAVY, [] as Array[String],
		Vector2i(15, -5))
	tf.ships.append(_convoy())
	tf.ships.append(ShipRoster.shared().make("Hood"))
	for k in ["AIR_STRIKE", "ENGAGE", "NAVAL_SEARCH"]:
		ne(Convoy.action_refusal(tf, k), "",
			"%s vietata a una TF con un Convoglio" % k)
	for k in ["COMPLETION", "PASS", "TRAJECTORY", "REORGANIZE", "SIGNAL"]:
		eq(Convoy.action_refusal(tf, k), "", "%s resta permessa" % k)
	# una Task Force senza Convoglio non e' toccata
	var plain := _tf(st, TaskForce.Side.ROYAL_NAVY,
		["Renown"] as Array[String], Vector2i(15, -5))
	eq(Convoy.action_refusal(plain, "ENGAGE"), "",
		"senza Convoglio si Ingaggia normalmente")


func test_convoy_dispersal() -> void:
	_begin("dispersione dei Convogli")
	var c := _convoy()
	false_(c.dispersed, "si comincia sempre non dispersi")

	# senza il permesso dello scenario non si disperde
	true_(Convoy.disperse_refusal(c, false).contains("non consentono"),
		"la dispersione e' un permesso, non un diritto")
	eq(Convoy.disperse_refusal(c, true), "", "con il permesso si puo'")

	var r := Convoy.disperse(c, true)
	true_(r["ok"], "la dispersione riesce")
	true_(c.dispersed, "il Convoglio e' disperso")
	# e non si torna indietro
	true_(Convoy.disperse_refusal(c, true).contains("non puo' tornare indietro"),
		"una volta disperso, per sempre")

	# i convogli tedeschi non si disperdono: sul retro hanno una petroliera
	var ge := Ship.new("Convoglio tedesco", TimeLapse.Speed.SLOW,
		Ship.Kind.CONVOY)
	ge.nation = "GE"
	true_(Convoy.disperse_refusal(ge, true).contains("tedeschi"),
		"i Convogli tedeschi non hanno un lato disperso")

	# una nave da guerra non si disperde
	true_(Convoy.disperse_refusal(ShipRoster.shared().make("Hood"), true)
		.contains("solo un Convoglio"), "e nemmeno una corazzata")

	# il limite di un Colpo per attacco
	var intact := _convoy()
	eq(Convoy.hits_taken(intact, 3), 3, "integro incassa tutti i Colpi")
	eq(Convoy.hits_taken(c, 3), 1, "disperso ne incassa uno solo")
	eq(Convoy.hits_taken(c, 0), 0, "e zero resta zero")
	# vale per attacco, non per Round: due attacchi da due Colpi fanno due
	eq(Convoy.hits_taken(c, 2) + Convoy.hits_taken(c, 2), 2,
		"due attacchi da due Colpi fanno due Colpi, non quattro")
	# le navi da guerra non hanno nessun limite
	eq(Convoy.hits_taken(ShipRoster.shared().make("Hood"), 3), 3,
		"una nave da guerra li incassa tutti")


## Le istruzioni di scenario che il fascicolo scrive a parole.
func test_scenario_rules() -> void:
	_begin("regole lette dal fascicolo")
	var op2 := Scenario.load_by_id("Op2 First Test")
	true_(op2.convoy_dispersal_allowed(), "in Op2 i Convogli possono disperdersi")
	true_(op2.completion_is_mandatory(),
		"e se una TF puo' Completare, deve farlo")

	var op5 := Scenario.load_by_id("Op5 Rheinubung")
	true_(op5.completion_is_mandatory(), "anche nella Rheinubung")

	# Una voce assente vuol dire "non trascritta", non "no". La differenza
	# conta: il gioco deve poterlo dire invece di decidere da solo.
	var ms1 := Scenario.load_by_id("MS1 Cornered")
	eq(ms1.rules().size(), 0, "i mini-scenari non hanno ancora queste voci")
	false_(ms1.convoy_dispersal_allowed(),
		"e in mancanza il motore non concede nulla")


## Il finale di partita: "quando tre Convogli hanno Completato...".
func test_endgame() -> void:
	_begin("finale di partita")
	var rules := {"completion_mandatory": true}
	var st := _state()

	false_(Endgame.restricted(st, rules), "a zero Convogli non c'e' restrizione")
	st.convoys_completed = 2
	false_(Endgame.restricted(st, rules), "nemmeno a due")
	st.convoys_completed = 3
	true_(Endgame.restricted(st, rules), "a tre scatta")

	# le quattro azioni che restano, e quelle che spariscono
	var km := TaskForce.Side.KRIEGSMARINE
	for k in ["AIR_STRIKE", "COMPLETION", "PASS", "TRAJECTORY"]:
		eq(Endgame.action_refusal(st, rules, km, k), "", "%s resta" % k)
	for k in ["ENGAGE", "NAVAL_SEARCH", "STEALTH_ATTACK", "REORGANIZE",
			"SIGNAL"]:
		ne(Endgame.action_refusal(st, rules, km, k), "", "%s sparisce" % k)

	# la restrizione colpisce un lato solo
	eq(Endgame.action_refusal(st, rules, TaskForce.Side.ROYAL_NAVY, "ENGAGE"),
		"", "il britannico non e' limitato")

	# senza la clausola nello scenario non succede niente
	st.convoys_completed = 9
	eq(Endgame.action_refusal(st, {}, km, "ENGAGE"), "",
		"uno scenario senza quella clausola non limita nessuno")

	# "se puo', DEVE": serve che il Completamento sia davvero eseguibile
	var st2 := _state()
	st2.convoys_completed = 3
	var far := _tf(st2, km, ["Bismarck"] as Array[String], Vector2i(10, 0))
	eq(Endgame.must_complete(st2, rules, graph).size(), 0,
		"in mezzo all'oceano non e' obbligata a niente")
	far.trajectory.become_station(graph.port_hex("Kiel"))
	var forced := Endgame.must_complete(st2, rules, graph)
	eq(forced.size(), 1, "in porto invece deve rientrare")
	eq(forced[0], far, "ed e' proprio quella")
	true_(Endgame.notice(st2, rules, graph).contains("DEVE"),
		"e il gioco lo dice a chiare lettere")


## Il conteggio dei Convogli arrivati si tiene anche senza tabella VP.
func test_convoy_counter() -> void:
	_begin("contare i Convogli arrivati")
	var st := _state()
	var kiel := graph.port_hex("Kiel")
	var tf := _tf(st, TaskForce.Side.ROYAL_NAVY, [] as Array[String], kiel)
	tf.ships.append(_convoy())
	eq(st.convoys_completed, 0, "si parte da zero")

	# tracciatore SENZA tabella VP: non segna punti ma conta lo stesso
	var mute := VictoryTracker.new(Victory.new(), st)
	false_(mute.active(), "questo tracciatore non ha tabella")
	Completion.resolve(tf, {"name": "Kiel", "country": "Germany", "hex": kiel},
		mute)
	eq(st.convoys_completed, 1,
		"il Convoglio arrivato si conta comunque: e' la condizione di fine")
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 0.0, "ma nessun punto")

	# e sopravvive a un salvataggio
	var st2 := _state()
	st2.apply_dict(st.to_dict())
	eq(st2.convoys_completed, 1, "il conteggio si salva")


## Salvare e riprendere una partita.
func test_savegame() -> void:
	_begin("salvataggio")
	var st := _state()
	var tf := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck", "Preugen"] as Array[String], Vector2i(15, -5))
	tf.trajectory.extend(Vector2i(16, -5), 1, graph)
	st.add_vp(TaskForce.Side.ROYAL_NAVY, 3.5)
	st.convoys_completed = 2
	st.round_number = 4
	st.weather = TimeLapse.Weather.BAD
	st.vp_once.append("primo Completamento a Bergen")
	# si consumano alcuni tiri, cosi' il RNG non e' piu' all'inizio
	st.rng.d6x2("prova")
	st.rng.d6("prova")

	var r := SaveGame.save(st, "Op5 Rheinubung", "Rheinubung", "_prova")
	true_(r["ok"], "il salvataggio riesce: " + String(r["error"]))

	var doc := SaveGame.read(String(r["path"]))
	true_(doc["ok"], "e si rilegge")
	eq(String(doc["scenario"]), "Op5 Rheinubung", "con il suo scenario")

	var st2 := _state()
	st2.apply_dict(doc["state"])
	eq(st2.round_number, 4, "il round torna")
	eq(st2.weather, TimeLapse.Weather.BAD, "e il meteo")
	eq(st2.vp_of(TaskForce.Side.ROYAL_NAVY), 3.5, "e i mezzi punti")
	eq(st2.convoys_completed, 2, "e i Convogli arrivati")
	eq(st2.vp_once.size(), 1, "e i premi una tantum gia' scattati")
	eq(st2.task_forces.size(), 1, "e la Task Force")
	eq(st2.task_forces[0].trajectory.length(), 1, "con la sua Traiettoria")
	eq(st2.task_forces[0].ships.size(), 2, "e le sue navi")

	# Il RNG va dentro il salvataggio: senza, si potrebbe salvare prima di una
	# Battaglia e ripeterla finche' non va bene. Ricaricare deve restituire la
	# stessa partita, non una simile.
	var a := st.rng.d6x2("dopo")
	var b := st2.rng.d6x2("dopo")
	eq(b, a, "lo stesso tiro dopo il ricaricamento")

	# un salvataggio di un'altra versione viene rifiutato, non interpretato
	var bad := FileAccess.open(SaveGame.path_for("_rotto"), FileAccess.WRITE)
	bad.store_string('{"format": 999, "state": {}}')
	bad.close()
	var doc2 := SaveGame.read(SaveGame.path_for("_rotto"))
	false_(doc2["ok"], "formato sconosciuto rifiutato")
	true_(String(doc2["error"]).contains("altra versione"), "e lo dice")

	SaveGame.erase(String(r["path"]))
	SaveGame.erase(SaveGame.path_for("_rotto"))


## La Campagna non e' uno scenario: e' la riserva navi delle nove Operazioni.
func test_campaign_pool() -> void:
	_begin("riserva navi della Campagna")
	var sc := Scenario.load_by_id("Campaign")
	eq(sc.task_forces.size(), 0, "nessuno schieramento, ed e' corretto")
	false_(sc.is_battle_scenario(), "e non e' nemmeno una Battaglia")
	var pool := sc.ship_pool()
	eq(pool.size(), 2, "due riserve, una per parte")
	eq((pool.get("KRIEGSMARINE", []) as Array).size(), 15, "quindici navi tedesche")
	eq((pool.get("ROYAL_NAVY", []) as Array).size(), 59, "e cinquantanove alleate")
	true_((pool["KRIEGSMARINE"] as Array).has("Bismarck"), "col Bismarck")
	true_((pool["ROYAL_NAVY"] as Array).has("Hood"), "e con l'Hood")
