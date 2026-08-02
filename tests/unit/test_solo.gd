extends TestCase

## Il modo solitario: l'avversario immaginario e le sue tabelle.

var graph: MapGraph

const SOLO_SCENARIOS := [
	"BL1 Raiders of the North Atlantic",
	"BL2 Contain and Destroy",
	"BL3 Raiders of the North Sea",
	"N1 Operazione Wilfred",
	"N2 Operazione Weser (nord)",
	"N3 Operazione Weser (sud)",
	"N4 Operazione Weser (nord & sud)",
	"N5 Meglio Tardi che Mai",
	"N6 Il Dilemma delle Operazioni",
	"B1 Operazione Berlino",
	"B2 La Battaglia dell'Atlantico",
	"B3 Operazione Reno",
	"B4 Decisione sui Mari",
	"A1 Convogli PQ",
	"A2 L'Ultima Battaglia",
]


func name() -> String:
	return "Solitario"


func run() -> void:
	graph = MapGraph.load_default()
	test_tables_load()
	test_all_solo_transcriptions_load()
	test_all_solo_action_tables_are_reachable()
	test_action_table_rows()
	test_phase_switch()
	test_phase_sync()
	test_modifiers()
	test_identify()
	test_a1_identify_from_second_edition()
	test_unidentified_speed()
	test_solo_ai_routes_around_information()
	test_solo_ai_executes_trajectory_code()
	test_solo_ai_declares_legal_attack()
	test_solo_ai_bl2_t_creates_unknown()
	test_solo_ai_bl3_completion_port_by_phase()
	test_solo_ai_bl1_x_creates_unknown_hunter()
	test_solo_ai_b1_convoy_creates_and_routes()
	test_solo_ai_b1_x_creates_unknown_interceptor()
	test_solo_ai_x_suffix_prefers_ship_type()
	test_solo_ai_xu_prefers_unidentified()
	test_solo_ai_a1_x_creates_german_raider()
	test_solo_ai_a1_c_routes_to_named_port()
	test_solo_ai_has_policy_for_action_codes()
	test_solo_norwegian_completion_ports()
	test_fueling()
	test_solo_battle_behavior()
	test_solo_battle_view_preassigns_both_sides()


func _rng(forced: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(forced)
	return r


func test_tables_load() -> void:
	_begin("le tabelle si caricano")
	for id in ["BL1 Raiders of the North Atlantic", "BL2 Contain and Destroy"]:
		var o := SoloOpponent.load_for(id)
		ne(o, null, "%s ha le sue tabelle" % id)
		eq(o.scenario_id, id, "e sa di chi sono")
		true_(o.has("identify"), "%s: tabella di Identificazione" % id)
	# uno scenario senza tabelle non esplode, ritorna null
	eq(SoloOpponent.load_for("Op5 Rheinubung"), null,
		"le Operazioni non hanno un avversario immaginario")


func test_all_solo_transcriptions_load() -> void:
	_begin("tutti gli scenari solitari trascritti si caricano")
	for id in SOLO_SCENARIOS:
		var o := SoloOpponent.load_for(id)
		ne(o, null, "%s ha il file solo" % id)
		eq(o.scenario_id, id, "%s: id scenario" % id)
		true_(o.tables.size() >= 1, "%s: almeno una tabella" % id)
		var sc := Scenario.load_by_id(id)
		eq(sc.load_error, "", "%s: scenario manuale caricato" % id)
		if id == "BL3 Raiders of the North Sea":
			true_(str(sc.raw_setup_notes()).contains("Mappa Inserto"),
				"%s: dichiara perche' non piazza TF sulla mappa principale" % id)
		else:
			true_(sc.task_forces.size() > 0, "%s: schieramento iniziale piazzato" % id)
		true_(sc.has_victory_table(), "%s: tabella Esito/Debriefing" % id)
		var v := Victory.from_scenario(sc)
		eq(v.mode, Victory.Mode.DEBRIEFING, "%s: modo Debriefing" % id)
		true_(v.debriefing.size() >= 3, "%s: soglie di Esito" % id)
		true_(String(sc.briefing.get("victory", "")).contains("solitario")
			or String(sc.briefing.get("victory", "")).contains("Modo"),
			"%s: briefing dichiara il modo solitario" % id)


func test_all_solo_action_tables_are_reachable() -> void:
	_begin("tutti gli scenari solitari hanno una tabella azione raggiungibile")
	for id in SOLO_SCENARIOS:
		var o := SoloOpponent.load_for(id)
		ne(o.action_table_id(), "", "%s: Tabella delle Azioni scelta dal motore" % id)
	eq(SoloOpponent.load_for("BL1 Raiders of the North Atlantic").action_table_id(),
		"british_actions", "BL1 usa la Tabella delle Azioni Britanniche")
	eq(SoloOpponent.load_for("B1 Operazione Berlino").action_table_id(),
		"british_actions", "B1 usa la Tabella di Azione Britannica")
	eq(SoloOpponent.load_for("A1 Convogli PQ").action_table_id(),
		"actions", "A1 usa la tabella azioni generica")
	eq(SoloOpponent.load_for("BL2 Contain and Destroy").action_table_id(),
		"actions_early", "BL2 parte dalla tabella Presto")


## La riga si sceglie contando i Completamenti riusciti dell'altra parte: piu'
## l'avversario e' avanti, piu' la tabella diventa aggressiva.
func test_action_table_rows() -> void:
	_begin("BL2: righe della Tabella delle Azioni")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	var t: SoloTable = o.table("actions_early")
	ne(t, null, "la tabella Presto c'e'")
	eq(t.rows.size(), 3, "tre righe")

	eq(t.row_for(0), 0, "zero Completamenti: prima riga")
	eq(t.row_for(1), 1, "uno: seconda")
	eq(t.row_for(2), 2, "due: terza")
	eq(t.row_for(7), 2, "e sette resta la terza")

	# le caselle agli estremi, lette come le stampa il fascicolo
	eq(String(t.read(0, 1)["code"]), "A", "riga 0, dado 1")
	eq(String(t.read(0, 6)["code"]), "C", "riga 0, dado 6")
	eq(String(t.read(2, 1)["code"]), "E", "riga 2+, dado 1")
	eq(String(t.read(2, 6)["code"]), "C", "riga 2+, dado 6")

	# un dado fuori scala non deve uscire dalla tabella
	eq(String(t.read(0, 9)["code"]), "C", "un tiro troppo alto resta sull'ultima")
	eq(String(t.read(0, -3)["code"]), "A", "e uno troppo basso sulla prima")

	# ogni casella ha la sua procedura per esteso
	for code in ["A", "C", "E", "T", "X", "convoy"]:
		true_(String(t.legend.get(code, "")).length() > 40,
			"la procedura '%s' e' trascritta" % code)


## Si comincia con la tabella Presto e si passa alla Tardi dopo una Battaglia,
## un Convoglio distrutto o un Attacco Aereo.
func test_phase_switch() -> void:
	_begin("BL2: da Presto a Tardi")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	eq(o.phase, SoloOpponent.Phase.EARLY, "si comincia Presto")

	var r := o.act(_rng([1]), 0)
	true_(r["ok"], "la tabella si legge")
	eq(String(r["table"]), "actions_early", "ed e' quella Presto")

	true_(o.go_late("c'e' stata una Battaglia"), "si passa a Tardi")
	false_(o.go_late("di nuovo"), "ma una volta sola")
	eq(String(o.phase_reason), "c'e' stata una Battaglia", "e si sa perche'")

	var r2 := o.act(_rng([1]), 0)
	eq(String(r2["table"]), "actions_late", "ora si legge la Tardi")
	# nella Tardi la riga e' il METEO, non i Completamenti
	eq(String(r2["code"]), "E", "meteo buono, dado 1")
	eq(String(o.act(_rng([1]), 1)["code"]), "E", "meteo cattivo, dado 1")
	eq(String(o.act(_rng([3]), 0)["code"]), "A", "meteo buono, dado 3")
	eq(String(o.act(_rng([3]), 1)["code"]), "T", "meteo cattivo, dado 3")


func test_phase_sync() -> void:
	_begin("stato solitario sincronizzato")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	o.set_phase(SoloOpponent.Phase.LATE, "un Convoglio e' stato distrutto")
	eq(o.phase, SoloOpponent.Phase.LATE, "fase Tardi impostata")
	eq(o.phase_reason, "un Convoglio e' stato distrutto", "ragione conservata")
	o.set_phase(SoloOpponent.Phase.EARLY, "ignorata")
	eq(o.phase, SoloOpponent.Phase.EARLY, "si puo' rimettere Presto caricando uno scenario")
	eq(o.phase_reason, "", "la ragione Presto resta vuota")


## Il modificatore c'e' ma non si applica da solo: il motore non sa se una nave
## tedesca e' danneggiata finche' non glielo si dice.
func test_modifiers() -> void:
	_begin("BL2: il modificatore -1")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	o.go_late("prova")
	var t: SoloTable = o.table("actions_late")
	eq(t.modifiers.size(), 1, "un solo modificatore")
	var label := String((t.modifiers[0] as Dictionary)["label"])
	eq(int((t.modifiers[0] as Dictionary)["value"]), -1, "e vale -1")

	eq(t.modifier_total([]), 0, "senza condizioni non si applica")
	eq(t.modifier_total([label]), -1, "con la condizione si applica")

	# con il -1 il tiro scivola di una colonna
	var senza := o.act(_rng([3]), 0)
	var con := o.act(_rng([3]), 0, [label])
	eq(int(senza["roll"]), 3, "3 senza modificatore")
	eq(int(con["roll"]), 2, "2 con il modificatore")
	eq(String(senza["code"]), "A", "colonna 3")
	eq(String(con["code"]), "A", "colonna 2")
	# e il registro mostra il conto
	true_(SoloTable.describe(con).contains("-1"), "il conto e' scritto: "
		+ SoloTable.describe(con).substr(0, 40))


func test_identify() -> void:
	_begin("identificare una Task Force")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.name = "TF ignota"
	tf.unidentified = true

	var r := o.identify(_rng([1]), tf)
	true_(r["ok"], "l'identificazione si esegue")
	eq(String(r["code"]), "PB", "dado 1: corazzata tascabile")
	eq(String(o.identify(_rng([3]), tf)["code"]), "CA", "dado 3")
	eq(String(o.identify(_rng([5]), tf)["code"]), "Convoglio", "dado 5")

	# una TF gia' identificata non si ri-identifica
	tf.unidentified = false
	var r2 := o.identify(_rng([1]), tf)
	false_(r2["ok"], "una TF nota non si identifica di nuovo")
	true_(String(r2["error"]).contains("gia' identificata"), "e lo dice")

	# le sostituzioni ("se ci sono gia' due CA...") restano scritte, perche'
	# le fa il giocatore
	var t: SoloTable = o.table("identify")
	true_(t.note.contains("sostituisci"), "le sostituzioni sono riportate")


func test_a1_identify_from_second_edition() -> void:
	_begin("A1: identificazione tedesca dalla seconda edizione")
	var o := SoloOpponent.load_for("A1 Convogli PQ")
	var t: SoloTable = o.table("identify")
	ne(t, null, "la tabella c'e'")
	eq(String(t.read(0, 1)["code"]), "BC", "1: BC")
	eq(String(t.read(0, 2)["code"]), "BC/DD", "2: BC e DD")
	eq(String(t.read(0, 3)["code"]), "BB", "3: BB")
	eq(String(t.read(0, 4)["code"]), "BB", "4: BB")
	eq(String(t.read(0, 5)["code"]), "CA", "5: CA")
	eq(String(t.read(0, 6)["code"]), "PB", "6: PB")
	true_(t.note.contains("1 BB"), "i limiti della seconda edizione sono scritti")


## Una TF non identificata e' "molto lenta" per definizione.
func test_unidentified_speed() -> void:
	_begin("velocita' di una TF non identificata")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.ships.append(ShipRoster.shared().make("Bismarck"))
	tf.recompute_speed()
	ne(tf.speed, TimeLapse.Speed.VERY_SLOW, "con il Bismarck non e' lentissima")

	tf.unidentified = true
	tf.recompute_speed()
	eq(tf.speed, TimeLapse.Speed.VERY_SLOW,
		"ma se non e' identificata si', qualunque cosa contenga")

	# e la cosa sopravvive a un salvataggio
	var back := TaskForce.from_dict(tf.to_dict())
	true_(back.unidentified, "resta non identificata dopo il salvataggio")
	eq(back.speed, TimeLapse.Speed.VERY_SLOW, "e resta lentissima")


func test_solo_ai_routes_around_information() -> void:
	_begin("AI solitaria: rotta evitando Informazioni")
	var st := GameState.new(graph, 1)
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.trajectory.become_station(Vector2i(6, 0))
	st.add_task_force(tf)
	st.add_info_trigger(Vector2i(7, 0), "base aerea")

	var plan := SoloAI.best_route(st, graph, tf, Vector2i(8, 0))
	ne(plan, {}, "trova una rotta alternativa")
	false_((plan["steps"] as Array).has(Vector2i(7, 0)),
		"non passa dall'esagono con Informazioni")
	true_(bool(plan["avoids_info"]), "la rotta dichiara che evita Informazioni")


func test_solo_ai_executes_trajectory_code() -> void:
	_begin("AI solitaria: codice T diventa Traiettoria")
	var st := GameState.new(graph, 1)
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.unidentified = true
	km.trajectory.become_station(Vector2i(6, 0))
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn.trajectory.become_station(Vector2i(8, 0))
	st.add_task_force(km)
	st.add_task_force(rn)

	var r := SoloAI.execute_code("T", st, graph, ActionEngine.load_default(), {}, km.side)
	true_(bool(r["ok"]), "la policy esegue una mossa")
	true_(km.length() > 0, "la TF del bot non resta ferma")
	true_(bool(r["pass_initiative"]), "dopo la mossa restituisce il turno")


func test_solo_ai_declares_legal_attack() -> void:
	_begin("AI solitaria: dichiara un attacco legale")
	var st := GameState.new(graph, 1)
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Bismarck"))
	km.trajectory.become_station(Vector2i(6, 0))
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn.trajectory.become_station(Vector2i(8, 0))
	rn.trajectory.extend(Vector2i(7, 0), 0, graph, {}, false, rn.side)
	rn.trajectory.extend(Vector2i(6, 0), 0, graph, {}, false, rn.side)
	st.add_task_force(km)
	st.add_task_force(rn)

	var r := SoloAI.execute_code("X", st, graph, ActionEngine.load_default(), {}, km.side)
	true_(["NAVAL_SEARCH", "STEALTH_ATTACK"].has(String(r["action_key"])),
		"sceglie un'azione offensiva legale")
	eq(r["active"], km, "la TF tedesca e' Attiva")
	eq(r["target"], rn, "il Convoglio e' il bersaglio")


func test_solo_ai_bl2_t_creates_unknown() -> void:
	_begin("AI solitaria BL2: T crea una TF ignota")
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL2 Contain and Destroy"
	st.rng.push_forced([4])
	var rn := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	rn.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn.trajectory.become_station(Vector2i(15, -4))
	st.add_task_force(rn)

	var r := SoloAI.execute_code("T", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.KRIEGSMARINE)
	true_(bool(r["ok"]), "la procedura produce una mossa")
	eq(st.forces_of(TaskForce.Side.KRIEGSMARINE).size(), 1, "crea una TF tedesca")
	true_(st.forces_of(TaskForce.Side.KRIEGSMARINE)[0].unidentified, "la TF e' ignota")
	true_(st.forces_of(TaskForce.Side.KRIEGSMARINE)[0].length() > 0, "e traccia una rotta")


func test_solo_ai_bl3_completion_port_by_phase() -> void:
	_begin("AI solitaria BL3: C sceglie il porto della fase")
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL3 Raiders of the North Sea"
	var rn := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	rn.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn.trajectory.become_station(Vector2i(15, -5))
	st.add_task_force(rn)

	var early := SoloAI.execute_code("C", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.ROYAL_NAVY)
	true_(bool(early["completion"]), "in Presto completa subito")
	eq(String((early["completion_port"] as Dictionary)["name"]), "Methil",
		"la tabella Presto usa Methil")

	var st2 := GameState.new(graph, 1)
	st2.scenario_name = "BL3 Raiders of the North Sea"
	st2.solo_phase = SoloOpponent.Phase.LATE
	var rn2 := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	rn2.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn2.trajectory.become_station(Vector2i(15, -5))
	st2.add_task_force(rn2)
	var late := SoloAI.execute_code("C", st2, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.ROYAL_NAVY)
	eq(String((late["completion_port"] as Dictionary)["name"]), "Scapa Flow",
		"la tabella Tardi usa Scapa Flow")


func test_solo_ai_bl1_x_creates_unknown_hunter() -> void:
	_begin("AI solitaria BL1: X crea un cacciatore ignoto")
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL1 Raiders of the North Atlantic"
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Lutzow"))
	km.trajectory.become_station(Vector2i(17, -5))
	st.add_task_force(km)

	var r := SoloAI.execute_code("X", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.ROYAL_NAVY)
	true_(bool(r["ok"]), "la policy crea e muove una TF")
	eq(st.forces_of(TaskForce.Side.ROYAL_NAVY).size(), 1, "crea una TF britannica")
	true_(st.forces_of(TaskForce.Side.ROYAL_NAVY)[0].unidentified, "la TF creata e' ignota")


func test_solo_ai_b1_convoy_creates_and_routes() -> void:
	_begin("AI solitaria B1: Convoy crea una TF e la muove")
	var st := GameState.new(graph, 1)
	st.scenario_name = "B1 Operazione Berlino"
	st.rng.push_forced([2])
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Scharnhorst"))
	km.trajectory.become_station(Vector2i(17, -5))
	st.add_task_force(km)

	var r := SoloAI.execute_code("Conv", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.ROYAL_NAVY)
	true_(bool(r["ok"]), "crea e muove il Convoglio")
	eq(st.forces_of(TaskForce.Side.ROYAL_NAVY).size(), 1, "una TF britannica creata")
	true_(SoloAI._has_convoy(st.forces_of(TaskForce.Side.ROYAL_NAVY)[0]), "contiene un Convoglio")
	true_(st.forces_of(TaskForce.Side.ROYAL_NAVY)[0].length() > 0, "traccia rotta verso Clyde/Liverpool")


func test_solo_ai_b1_x_creates_unknown_interceptor() -> void:
	_begin("AI solitaria B1: X crea intercettore ignoto")
	var st := GameState.new(graph, 1)
	st.scenario_name = "B1 Operazione Berlino"
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Gneisenau"))
	km.trajectory.become_station(Vector2i(17, -5))
	st.add_task_force(km)

	var r := SoloAI.execute_code("X", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.ROYAL_NAVY)
	true_(bool(r["ok"]), "la policy muove o attacca")
	eq(st.forces_of(TaskForce.Side.ROYAL_NAVY).size(), 1, "crea una TF britannica")
	true_(st.forces_of(TaskForce.Side.ROYAL_NAVY)[0].unidentified, "la TF e' ignota")


func test_solo_ai_x_suffix_prefers_ship_type() -> void:
	_begin("AI solitaria: XCA preferisce una CA")
	var st := GameState.new(graph, 1)
	st.scenario_name = "B2 La Battaglia dell'Atlantico"
	var ca := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	ca.ships.append(ShipRoster.shared().make("Hipper"))
	ca.trajectory.become_station(Vector2i(6, 0))
	var bc := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	bc.ships.append(ShipRoster.shared().make("Scharnhorst"))
	bc.trajectory.become_station(Vector2i(10, 0))
	var convoy := TaskForce.new(3, TaskForce.Side.ROYAL_NAVY)
	convoy.ships.append(ShipRoster.shared().make("Convoy x3"))
	convoy.trajectory.become_station(Vector2i(8, 0))
	st.add_task_force(ca)
	st.add_task_force(bc)
	st.add_task_force(convoy)

	var r := SoloAI.execute_code("XCA", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.KRIEGSMARINE)
	eq(r["active"], ca, "sceglie la TF col CA indicato dal codice")
	true_(bool(r["ok"]), "e produce una mossa")


func test_solo_ai_xu_prefers_unidentified() -> void:
	_begin("AI solitaria: Xu preferisce una TF ignota")
	var st := GameState.new(graph, 1)
	st.scenario_name = "B4 Decisione sui Mari"
	var known := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	known.ships.append(ShipRoster.shared().make("Bismarck"))
	known.trajectory.become_station(Vector2i(6, 0))
	var unk := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	unk.unidentified = true
	unk.recompute_speed()
	unk.trajectory.become_station(Vector2i(10, 0))
	var convoy := TaskForce.new(3, TaskForce.Side.ROYAL_NAVY)
	convoy.ships.append(ShipRoster.shared().make("Convoy x3"))
	convoy.trajectory.become_station(Vector2i(8, 0))
	st.add_task_force(known)
	st.add_task_force(unk)
	st.add_task_force(convoy)

	var r := SoloAI.execute_code("Xu", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.KRIEGSMARINE)
	eq(r["active"], unk, "sceglie la TF ignota indicata dal codice")
	true_(bool(r["ok"]), "e produce una mossa")


func test_solo_ai_a1_x_creates_german_raider() -> void:
	_begin("AI solitaria A1: X crea una TF tedesca")
	var st := GameState.new(graph, 1)
	st.scenario_name = "A1 Convogli PQ"
	st.rng.push_forced([2])
	var convoy := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	convoy.ships.append(ShipRoster.shared().make("Convoy x3"))
	convoy.trajectory.become_station(Vector2i(15, -5))
	st.add_task_force(convoy)

	var r := SoloAI.execute_code("X", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.KRIEGSMARINE)
	true_(bool(r["ok"]), "crea e muove verso il Convoglio")
	eq(st.forces_of(TaskForce.Side.KRIEGSMARINE).size(), 1, "una TF tedesca creata")
	true_(st.forces_of(TaskForce.Side.KRIEGSMARINE)[0].unidentified, "la TF e' ignota")


func test_solo_ai_a1_c_routes_to_named_port() -> void:
	_begin("AI solitaria A1: C rientra a Narvik/St. Nazaire")
	var st := GameState.new(graph, 1)
	st.scenario_name = "A1 Convogli PQ"
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Hipper"))
	km.trajectory.become_station(Vector2i(17, -9))
	st.add_task_force(km)

	var r := SoloAI.execute_code("C", st, graph, ActionEngine.load_default(),
		{"NO": "KRIEGSMARINE", "FR": "KRIEGSMARINE"}, TaskForce.Side.KRIEGSMARINE)
	true_(bool(r["completion"]), "a Narvik puo' completare subito")
	eq(String((r["completion_port"] as Dictionary)["name"]), "Narvik",
		"sceglie il porto previsto piu' vicino")


func test_solo_ai_has_policy_for_action_codes() -> void:
	_begin("ogni codice azione solitario ha una policy AI")
	var action_tables := ["actions", "actions_early", "actions_late", "british_actions"]
	for id in SOLO_SCENARIOS:
		var sc := Scenario.load_by_id(id)
		var o := SoloOpponent.load_for(id)
		var v := Victory.from_scenario(sc)
		var imaginary := 1 - v.solo_side
		for tid in action_tables:
			if not o.has(tid):
				continue
			var t: SoloTable = o.table(tid)
			var seen := {}
			for r in t.rows:
				for code_v: Variant in r["cells"]:
					var code := String(code_v)
					if seen.has(code):
						continue
					seen[code] = true
					var st := GameState.new(graph, 17)
					st.apply_dict(sc.to_state_dict())
					var res := SoloAI.execute_code(code, st, graph,
						ActionEngine.load_default(), sc.port_control(), imaginary)
					false_(_solo_ai_log_contains(res, "non ha ancora una policy"),
						"%s %s: codice %s coperto" % [id, tid, code])


func test_solo_norwegian_completion_ports() -> void:
	_begin("N2-N4: Completamenti norvegesi speciali dichiarati nei dati")
	for id in ["N2 Operazione Weser (nord)", "N3 Operazione Weser (sud)",
			"N4 Operazione Weser (nord & sud)"]:
		var sc := Scenario.load_by_id(id)
		var control := sc.port_control()
		true_(not control.is_empty(), "%s: controllo porti speciale presente" % id)
	eq(String(Scenario.load_by_id("N2 Operazione Weser (nord)")
		.port_control()["Narvik"]), "BOTH", "N2: Narvik accetta entrambi")
	eq(String(Scenario.load_by_id("N3 Operazione Weser (sud)")
		.port_control()["Bergen"]), "BOTH", "N3: Bergen accetta entrambi")
	eq(String(Scenario.load_by_id("N4 Operazione Weser (nord & sud)")
		.port_control()["Trondheim"]), "BOTH", "N4: Trondheim accetta entrambi")


func _solo_ai_log_contains(res: Dictionary, needle: String) -> bool:
	for line_v: Variant in res.get("log", []):
		if String(line_v).contains(needle):
			return true
	return false


## In BL1 il giocatore e' il tedesco, e la tabella che conta e' quella del
## Rifornimento: e' il caso, non un avversario.
func test_fueling() -> void:
	_begin("BL1: Tabella del Rifornimento")
	var o := SoloOpponent.load_for("BL1 Raiders of the North Atlantic")
	var t: SoloTable = o.table("fueling")
	ne(t, null, "la tabella c'e'")
	eq(t.rows.size(), 2, "due righe: meteo buono e cattivo")

	eq(String(t.read(0, 1)["code"]), "a", "buono, dado 1")
	eq(String(t.read(0, 6)["code"]), "e", "buono, dado 6")
	eq(String(t.read(1, 1)["code"]), "a", "cattivo, dado 1")
	eq(String(t.read(1, 6)["code"]), "g", "cattivo, dado 6")
	# il maltempo peggiora le cose: con 3 il buono da' 'b', il cattivo 'e'
	eq(String(t.read(0, 3)["code"]), "b", "buono, dado 3")
	eq(String(t.read(1, 3)["code"]), "e", "cattivo, dado 3")

	for code in ["a", "b", "c", "d", "e", "f", "g"]:
		ne(String(t.legend.get(code, "")), "",
			"la procedura '%s' e' trascritta" % code)

	# la tabella Murmansk ha un modificatore che il giocatore attiva
	var m: SoloTable = o.table("murmansk")
	ne(m, null, "e c'e' anche la tabella Murmansk")
	eq(m.modifier_total(["due o piu' Convogli distrutti"]), -1,
		"che peggiora se hai distrutto molti Convogli")
	eq(String(m.read(0, 1)["code"]), "confisca", "con 1 le navi sono confiscate")
	eq(String(m.read(0, 6)["code"]), "salvi", "con 6 rientrano a Kiel")


func test_solo_battle_behavior() -> void:
	_begin("comportamento in Battaglia dell'avversario immaginario")
	var st := BattleState.new()
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	var hipper := ShipRoster.shared().make("Hipper")
	var convoy := ShipRoster.shared().make("Convoy x3")
	var hood := ShipRoster.shared().make("Hood")
	hipper.battle_zone = BattleState.Zone.NEAR
	convoy.battle_zone = BattleState.Zone.NEAR
	hood.battle_zone = BattleState.Zone.NEAR
	km.ships = [hipper]
	rn.ships = [convoy, hood]
	st.active_tf = km
	st.target_tf = rn

	var tgt := SoloBattle.targeting(st, TaskForce.Side.KRIEGSMARINE)
	eq(tgt[hipper], convoy, "il bersaglio prioritario e' il Convoglio")

	var moves_rn := SoloBattle.maneuver_moves(st, TaskForce.Side.ROYAL_NAVY)
	eq(int((moves_rn[hood] as Dictionary)["zone"]), BattleState.Zone.CLOSE,
		"la Royal Navy immaginaria chiude la distanza")
	eq(int((moves_rn[convoy] as Dictionary)["zone"]), BattleState.Zone.FAR,
		"ma i Convogli si allontanano")

	true_(SoloBattle.wants_break_away(st, TaskForce.Side.KRIEGSMARINE),
		"i tedeschi tentano la Fuga davanti a una BB/BC britannica integra")


func test_solo_battle_view_preassigns_both_sides() -> void:
	_begin("Battaglia solitaria: bersagli proposti per entrambi i lati")
	var st := BattleState.new()
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	var hipper := ShipRoster.shared().make("Hipper")
	var hood := ShipRoster.shared().make("Hood")
	hipper.battle_zone = BattleState.Zone.NEAR
	hood.battle_zone = BattleState.Zone.NEAR
	km.ships = [hipper]
	rn.ships = [hood]
	st.active_tf = km
	st.target_tf = rn
	st.phase = BattleState.Phase.GUNNERY

	var battle := Battle.new(st, DiceRNG.new(0))
	var view := BattleView.new()
	view.battle = battle
	view.state = st
	view.solo_player_side = TaskForce.Side.ROYAL_NAVY
	var auto: Dictionary = view._auto_targeting_for_phase()
	eq(auto[hipper], hood, "l'avversario immaginario ha un bersaglio")
	eq(auto[hood], hipper, "anche il giocatore riceve un bersaglio proposto")
	view.free()
