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
	test_bl1_setup_has_printed_routes_and_stations()
	test_all_solo_action_tables_are_reachable()
	test_action_table_rows()
	test_phase_switch()
	test_phase_sync()
	test_automatic_late_phase_triggers()
	test_modifiers()
	test_identify()
	test_a1_identify_from_second_edition()
	test_unidentified_speed()
	test_solo_ai_routes_around_information()
	test_solo_ai_executes_trajectory_code()
	test_solo_trajectory_does_not_pass_initiative()
	test_eliminated_force_leaves_map_and_is_remembered()
	test_automatic_modifiers_count_each_ship()
	test_solo_ai_declares_legal_attack()
	test_bl1_air_fallback_routes_then_engages()
	test_bl1_completion_route_keeps_completion()
	test_solo_ai_bl2_t_creates_unknown()
	test_bl2_late_table_has_modified_zero_column()
	test_bl2_trajectory_and_convoy_procedures()
	test_bl2_air_strike_fallbacks_and_removals()
	test_bl2_end_procedure()
	test_bl2_identification_and_incident()
	test_bl2_completion_destinations()
	test_bl2_complete_setup_and_neutral_waters()
	test_bl2_battle_identifies_unknown_tf()
	test_bl2_x_keeps_damaged_selection()
	test_solo_ai_bl3_completion_port_by_phase()
	test_bl3_declares_inset_setup_gaps()
	test_solo_ai_bl1_x_creates_unknown_hunter()
	test_solo_ai_bl1_blockade_and_french_action()
	test_solo_ai_bl1_murmansk_before_debriefing()
	test_solo_ai_bl1_convoy_procedure()
	test_solo_ai_bl1_four_cruisers_add_the_french_action()
	test_solo_ai_b1_convoy_creates_and_routes()
	test_solo_ai_b1_x_creates_unknown_interceptor()
	test_solo_ai_x_suffix_prefers_ship_type()
	test_solo_ai_xu_prefers_unidentified()
	test_solo_ai_a1_x_creates_german_raider()
	test_solo_ai_a1_c_routes_to_named_port()
	test_solo_ai_has_policy_for_action_codes()
	test_solo_norwegian_completion_ports()
	test_fueling()
	test_bl1_fueling_trigger_conditions()
	test_solo_ai_bl1_aux_tables_apply()
	test_solo_battle_behavior()
	test_solo_battle_view_preassigns_both_sides()


func _rng(forced: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(forced)
	return r


func _tf_has_type(tf: TaskForce, type_code: String) -> bool:
	if tf == null:
		return false
	for ship in tf.ships:
		if ship.type_code == type_code and not ship.sunk:
			return true
	return false


func _count_tf_type(tf: TaskForce, type_code: String) -> int:
	var count := 0
	if tf != null:
		for ship in tf.ships:
			if ship.type_code == type_code and not ship.sunk:
				count += 1
	return count


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


func test_bl1_setup_has_printed_routes_and_stations() -> void:
	_begin("BL1: setup stampato sul fascicolo")
	var sc := Scenario.load_by_id("BL1 Raiders of the North Atlantic")
	eq(sc.load_error, "", "scenario BL1 caricato")
	var st := GameState.new(graph, 1)
	st.apply_dict(sc.to_state_dict())

	var halifax := _tf_named(st, "Convoglio Halifax-Clyde")
	ne(halifax, null, "convoglio Halifax-Clyde piazzato")
	eq(halifax.trajectory.length(), 11, "Halifax-Clyde ha 11 segmenti")
	eq(halifax.trajectory.end_hex(0), Vector2i(5, 4), "Halifax-Clyde parte da Halifax")
	eq(halifax.trajectory.end_hex(1), Vector2i(15, -4),
		"Halifax-Clyde arriva a Clyde/Liverpool")
	true_(_trajectory_is_contiguous(halifax), "Halifax-Clyde e' continua")

	var africa := _tf_named(st, "Convoglio Africa-Portsmouth")
	ne(africa, null, "convoglio Africa-Portsmouth piazzato")
	eq(africa.trajectory.length(), 8, "Africa-Portsmouth ha 8 segmenti")
	eq(africa.trajectory.end_hex(0), Vector2i(12, 4),
		"Africa-Portsmouth parte dalla striscia Africa")
	eq(africa.trajectory.end_hex(1), Vector2i(16, -3),
		"Africa-Portsmouth arriva a Portsmouth")
	true_(_trajectory_is_contiguous(africa), "Africa-Portsmouth e' continua")
	true_(graph.ports_in(africa.trajectory.end_hex(0)).has("Africa"),
		"il capo iniziale tocca il porto Africa")
	true_(graph.ports_in(africa.trajectory.end_hex(1)).has("Portsmouth"),
		"il capo finale tocca Portsmouth")

	var brest := _forces_at(st, Vector2i(15, -2))
	eq(brest.size(), 2, "a Brest ci sono due Stazioni")
	true_(_forces_include_ship(brest, "Widder"), "Brest contiene la Stazione tedesca")
	true_(_forces_include_ship(brest, "Dunkerque"), "Brest contiene la Forza francese")

	eq(st.rendezvous_markers.size(), 3, "tre marker RV piazzati")
	true_(not st.rendezvous_at(Vector2i(11, -5)).is_empty(), "RV nord piazzato")
	true_(not st.rendezvous_at(Vector2i(9, -2)).is_empty(), "RV centrale piazzato")
	true_(not st.rendezvous_at(Vector2i(10, 3)).is_empty(), "RV sud piazzato")

	var lutzow := _tf_with_ship(st, "Lutzow")
	ne(lutzow, null, "Lutzow e' in una TF iniziale")
	eq(lutzow.leader, "Raeder", "Lutzow parte con Raeder")
	true_(lutzow.trajectory.is_station(), "Lutzow parte come Stazione")
	true_(_station_adjacent_to_any_rv(st, lutzow), "Lutzow parte adiacente a un RV")
	true_(st.rendezvous_at(lutzow.trajectory.station_hex).is_empty(),
		"Lutzow non parte sopra l'RV, ma accanto")

	var group_a: Array = sc.reinforcements.get("KM Reinforcement A", [])
	true_(group_a.has("Graf Spee"), "Graf Spee e' nel Gruppo Rinforzi A")
	eq(String(sc.reinforcement_ports().get("KM Reinforcement A", "")), "Kiel",
		"il Gruppo Rinforzi A e' a Kiel")


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
	eq(String(r2["code"]), "A", "meteo buono, dado 1")
	eq(String(o.act(_rng([1]), 1)["code"]), "E", "meteo cattivo, dado 1")
	eq(String(o.act(_rng([3]), 0)["code"]), "X", "meteo buono, dado 3")
	eq(String(o.act(_rng([3]), 1)["code"]), "X", "meteo cattivo, dado 3")


func test_phase_sync() -> void:
	_begin("stato solitario sincronizzato")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	o.set_phase(SoloOpponent.Phase.LATE, "un Convoglio e' stato distrutto")
	eq(o.phase, SoloOpponent.Phase.LATE, "fase Tardi impostata")
	eq(o.phase_reason, "un Convoglio e' stato distrutto", "ragione conservata")
	o.set_phase(SoloOpponent.Phase.EARLY, "ignorata")
	eq(o.phase, SoloOpponent.Phase.EARLY, "si puo' rimettere Presto caricando uno scenario")
	eq(o.phase_reason, "", "la ragione Presto resta vuota")


func test_automatic_late_phase_triggers() -> void:
	_begin("inneschi automatici delle tabelle Tardi")
	var bl2 := SoloOpponent.load_for("BL2 Contain and Destroy")
	true_(bl2.goes_late_after("battle"), "BL2: Battaglia")
	true_(bl2.goes_late_after("convoy_destroyed"), "BL2: Convoglio distrutto")
	true_(bl2.goes_late_after("air_strike"), "BL2: Attacco Aereo")
	false_(bl2.goes_late_after("stealth_attack"), "BL2: non Attacco Furtivo")
	var bl3 := SoloOpponent.load_for("BL3 Raiders of the North Sea")
	true_(bl3.goes_late_after("battle"), "BL3: Battaglia")
	true_(bl3.goes_late_after("air_strike"), "BL3: Attacco Aereo")
	false_(bl3.goes_late_after("convoy_destroyed"), "BL3: non Convoglio distrutto")
	var n1 := SoloOpponent.load_for("N1 Operazione Wilfred")
	true_(n1.goes_late_after("battle"), "N1: Battaglia")
	true_(n1.goes_late_after("result_i"), "N1: risultato I")
	false_(n1.goes_late_after("air_strike"), "N1: non Attacco Aereo")
	var n2 := SoloOpponent.load_for("N2 Operazione Weser (nord)")
	true_(n2.goes_late_after("battle"), "N2: Battaglia")
	true_(n2.goes_late_after("stealth_attack"), "N2: Attacco Furtivo")
	true_(n2.goes_late_after("aggressive_reaction"), "N2: Reazione Aggressiva")
	false_(n2.goes_late_after("air_strike"), "N2: non Attacco Aereo")


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
	eq(String(senza["code"]), "X", "colonna 3")
	eq(String(con["code"]), "A", "colonna 2")
	# e il registro mostra il conto
	true_(SoloTable.describe(con).contains("-1"), "il conto e' scritto: "
		+ SoloTable.describe(con).substr(0, 40))
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL2 Contain and Destroy"
	var damaged_tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	for name in ["Hipper", "Lutzow"]:
		var ship := ShipRoster.shared().make(name)
		ship.damaged = true
		damaged_tf.ships.append(ship)
	st.add_task_force(damaged_tf)
	var inferred := SoloAI.automatic_modifiers(t, st, TaskForce.Side.KRIEGSMARINE)
	eq((inferred["active"] as Array).size(), 1, "due navi rendono vera una sola condizione OR")
	eq(t.modifier_total(inferred["active"]), -1, "il modificatore BL2 resta -1")


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
	tf.trajectory.become_station(Vector2i(10, 0))
	st.add_task_force(tf)
	st.add_info_trigger(Vector2i(11, 0), "base aerea")

	var plan := SoloAI.best_route(st, graph, tf, Vector2i(12, 0))
	ne(plan, {}, "trova una rotta alternativa")
	if plan.is_empty():
		return
	false_((plan["steps"] as Array).has(Vector2i(11, 0)),
		"non passa dall'esagono con Informazioni")
	true_(bool(plan["avoids_info"]), "la rotta dichiara che evita Informazioni")


func test_solo_ai_executes_trajectory_code() -> void:
	_begin("AI solitaria: codice T diventa Traiettoria")
	var st := GameState.new(graph, 1)
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.unidentified = true
	km.trajectory.become_station(Vector2i(10, 0))
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn.trajectory.become_station(Vector2i(12, 0))
	st.add_task_force(km)
	st.add_task_force(rn)

	var r := SoloAI.execute_code("T", st, graph, ActionEngine.load_default(), {}, km.side)
	true_(bool(r["ok"]), "la policy esegue una mossa")
	true_(km.length() > 0, "la TF del bot non resta ferma")
	false_(bool(r["pass_initiative"]), "Traiettoria non viene trasformata in Passare")


func test_solo_trajectory_does_not_pass_initiative() -> void:
	_begin("AI solitaria: Traiettoria conserva le normali regole d'Iniziativa")
	var st := GameState.new(graph, 1)
	var bot := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	bot.unidentified = true
	bot.trajectory.become_station(Vector2i(10, 0))
	var enemy := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	enemy.ships.append(ShipRoster.shared().make("Convoy x3"))
	enemy.trajectory.become_station(Vector2i(13, 0))
	st.add_task_force(bot)
	st.add_task_force(enemy)
	var decision := SoloAI.execute_code("T", st, graph,
		ActionEngine.load_default(), {}, bot.side)
	eq(String(decision["turn_kind"]), "trajectory", "la UI sa quale flusso applicare")
	false_(bool(decision["pass_initiative"]), "il bot non cede automaticamente il turno")


func test_eliminated_force_leaves_map_and_is_remembered() -> void:
	_begin("TF eliminata: sparisce dalla mappa, perdita salvata")
	var st := GameState.new(graph, 1)
	var tf := TaskForce.new(7, TaskForce.Side.KRIEGSMARINE)
	var ship := ShipRoster.shared().make("Lutzow")
	ship.sunk = true
	tf.ships.append(ship)
	tf.trajectory.become_station(Vector2i(8, 0))
	st.add_task_force(tf)
	var removed := st.remove_eliminated_forces("prova")
	eq(removed.size(), 1, "una TF rimossa")
	eq(st.task_force(7), null, "non e' piu' selezionabile")
	eq(st.forces_in(Vector2i(8, 0)).size(), 0, "non occupa piu' l'esagono")
	eq(st.sunk_count(TaskForce.Side.KRIEGSMARINE), 1, "la perdita resta contata")
	var restored := GameState.new(graph, 2)
	restored.apply_dict(st.to_dict())
	eq(restored.sunk_count(TaskForce.Side.KRIEGSMARINE), 1,
		"la perdita sopravvive al salvataggio")


func test_automatic_modifiers_count_each_ship() -> void:
	_begin("tabelle solo: modificatore applicato per ogni nave")
	var st := GameState.new(graph, 1)
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	for name in ["Lutzow", "Hipper"]:
		var ship := ShipRoster.shared().make(name)
		ship.damaged = true
		tf.ships.append(ship)
	st.add_task_force(tf)
	var table := SoloOpponent.load_for("N6 Il Dilemma delle Operazioni").table("actions")
	var inferred := SoloAI.automatic_modifiers(table, st, TaskForce.Side.KRIEGSMARINE)
	eq((inferred["active"] as Array).size(), 2, "due condizioni attive, una per nave")
	eq(table.modifier_total(inferred["active"]), 2, "+1 applicato due volte")


func test_solo_ai_declares_legal_attack() -> void:
	_begin("AI solitaria: dichiara un attacco legale")
	var st := GameState.new(graph, 1)
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Bismarck"))
	km.trajectory.become_station(Vector2i(10, 0))
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.ships.append(ShipRoster.shared().make("Convoy x3"))
	rn.trajectory.become_station(Vector2i(10, 0))
	st.add_task_force(km)
	st.add_task_force(rn)

	var r := SoloAI.execute_code("X", st, graph, ActionEngine.load_default(), {}, km.side)
	eq(String(r["action_key"]), "ENGAGE",
		"Ingaggia la Stazione senza inventare un Attacco Furtivo")
	eq(r["active"], km, "la TF tedesca e' Attiva")
	eq(r["target"], rn, "il Convoglio e' il bersaglio")


func test_bl1_air_fallback_routes_then_engages() -> void:
	_begin("BL1 A: senza attacco aereo, Traiettoria poi Ingaggio")
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL1 Raiders of the North Atlantic"
	st.weather = TimeLapse.Weather.GOOD
	var target := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	target.ships.append(ShipRoster.shared().make("Lutzow"))
	target.trajectory.become_station(Vector2i(9, 3))
	var hunter := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	hunter.ships.append(ShipRoster.shared().make("Birmingham"))
	hunter.trajectory.become_station(Vector2i(11, 3))
	st.add_task_force(target)
	st.add_task_force(hunter)
	var engine := ActionEngine.load_default()

	var route := SoloAI.execute_code("A", st, graph, engine, {}, hunter.side)
	eq(String(route["turn_kind"]), "trajectory", "prima esegue la Traiettoria")
	eq(String(route["action_key"]), "", "non dichiara un attacco durante la rotta")
	eq(String((route["follow_up"] as Dictionary).get("kind", "")), "attack",
		"conserva la seconda azione prescritta")
	var attack := SoloAI.continue_follow_up(route, st, graph, engine, {}, hunter.side)
	eq(String(attack["action_key"]), "ENGAGE", "poi Ingaggia la Stazione tedesca")
	eq(attack["active"], hunter, "la TF con CA resta Attiva")
	eq(attack["target"], target, "la Stazione tedesca resta il bersaglio")


func test_bl1_completion_route_keeps_completion() -> void:
	_begin("BL1 C: Traiettoria poi Completamento senza nuovo tiro")
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL1 Raiders of the North Atlantic"
	var convoy := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	convoy.ships.append(ShipRoster.shared().make("Convoy x3"))
	convoy.trajectory.become_station(Vector2i(15, -3))
	st.add_task_force(convoy)
	var engine := ActionEngine.load_default()

	var route := SoloAI.execute_code("C", st, graph, engine, {}, convoy.side)
	eq(String(route["turn_kind"]), "trajectory", "prima raggiunge il porto scelto")
	eq(String((route["follow_up"] as Dictionary).get("kind", "")), "completion",
		"conserva il Completamento come seconda azione")
	var chosen_port := String((route["follow_up"] as Dictionary).get("port_name", ""))
	var completion := SoloAI.continue_follow_up(route, st, graph, engine, {}, convoy.side)
	true_(bool(completion["completion"]), "poi dichiara Completamento")
	eq(String((completion["completion_port"] as Dictionary).get("name", "")),
		chosen_port, "usa il porto scelto prima della Traiettoria")
	eq(completion["active"], convoy, "il Convoglio resta la TF Attiva")


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


func test_bl2_late_table_has_modified_zero_column() -> void:
	_begin("BL2 Tardi: conserva la colonna zero stampata")
	var t := SoloOpponent.load_for("BL2 Contain and Destroy").table("actions_late")
	var good := ["E", "A", "A", "X", "X", "C", "C"]
	var bad := ["E", "E", "T", "X", "X", "C", "C"]
	for roll in 7:
		eq(String(t.read(0, roll)["code"]), good[roll], "Buono, colonna %d" % roll)
		eq(String(t.read(1, roll)["code"]), bad[roll], "Cattivo, colonna %d" % roll)


func test_bl2_trajectory_and_convoy_procedures() -> void:
	_begin("BL2: T nasce a Murmansk e Convoglio nasce a Narvik")
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL2 Contain and Destroy"
	st.rng.push_forced([4])
	var t_result := SoloAI.execute_code("T", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.KRIEGSMARINE)
	var unknown := t_result["active"] as TaskForce
	ne(unknown, null, "T crea la TF selezionata")
	true_(unknown.unidentified, "la TF di T e' non identificata")
	true_(unknown.trajectory.occupies((graph.ports["Murmansk"] as Dictionary)["hex"]),
		"la rotta parte da Murmansk")
	eq(String((t_result["follow_up"] as Dictionary).get("kind", "")), "completion",
		"dopo la rotta conserva il Completamento")
	var kiel := (graph.ports["Kiel"] as Dictionary)["hex"] as Vector2i
	true_(unknown.trajectory.occupies(kiel), "la prima Traiettoria raggiunge Kiel")
	true_(unknown.length() > Completion.MAX_SEGMENTS,
		"prima dello Scorrere del Tempo la rotta e' troppo lunga per Completare")
	var before_follow := unknown.length()
	var refused := SoloAI.continue_follow_up(t_result, st, graph,
		ActionEngine.load_default(), {}, unknown.side)
	eq(String(refused["turn_kind"]), "pass",
		"la continuazione troppo lunga diventa Passare")
	false_(bool(refused["completion"]), "non dichiara un Completamento illegale")
	eq(unknown.length(), before_follow, "non costruisce una seconda Traiettoria")
	true_(bool(refused["time_lapse_before_pass"]),
		"il Passare sostitutivo conserva il proprio Scorrere del Tempo")
	while unknown.length() > Completion.MAX_SEGMENTS:
		unknown.trajectory.remove_end(0)
	var completion := SoloAI.continue_follow_up(t_result, st, graph,
		ActionEngine.load_default(), {}, unknown.side)
	true_(bool(completion["completion"]),
		"dopo lo Scorrere del Tempo la TF ignota puo' tentare il Completamento")
	true_(String((completion["log"] as Array)[0]).contains("puo' tentare"),
		"il log non annuncia il successo prima del tiro d'Iniziativa")
	var south_state := GameState.new(graph, 12)
	south_state.scenario_name = "BL2 Contain and Destroy"
	south_state.rng.push_forced([1])
	var south_route := SoloAI.execute_code("T", south_state, graph,
		ActionEngine.load_default(), {}, TaskForce.Side.KRIEGSMARINE)
	var south_tf := south_route["active"] as TaskForce
	var south_america := (graph.ports["South America"] as Dictionary)["hex"] as Vector2i
	false_(south_tf.trajectory.occupies(south_america),
		"la rotta massima da Murmansk non finge di aver raggiunto South America")
	var south_length := south_tf.length()
	var south_follow := SoloAI.continue_follow_up(south_route, south_state, graph,
		ActionEngine.load_default(), {}, south_tf.side)
	eq(String(south_follow["turn_kind"]), "pass",
		"se il porto non e' raggiunto la continuazione Passa")
	eq(south_tf.length(), south_length,
		"anche in questo caso non apre una seconda Traiettoria")

	var st2 := GameState.new(graph, 2)
	st2.scenario_name = "BL2 Contain and Destroy"
	var convoy_result := SoloAI.execute_code("convoy", st2, graph,
		ActionEngine.load_default(), {}, TaskForce.Side.KRIEGSMARINE)
	var convoy := convoy_result["active"] as TaskForce
	ne(convoy, null, "Convoglio crea la TF selezionata")
	true_(_tf_has_type(convoy, "CONVOY"), "contiene il Convoglio tedesco")
	true_(convoy.trajectory.occupies((graph.ports["Narvik"] as Dictionary)["hex"]),
		"parte da Narvik")
	eq(String((convoy_result["follow_up"] as Dictionary).get("port_name", "")),
		"Kiel", "prosegue verso il Completamento a Kiel")


func test_bl2_air_strike_fallbacks_and_removals() -> void:
	_begin("BL2 A: rimuove le danneggiate e applica il tiro senza bersaglio")
	var st := GameState.new(graph, 3)
	st.scenario_name = "BL2 Contain and Destroy"
	st.weather = TimeLapse.Weather.GOOD
	st.rng.push_forced([1])
	var damaged := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var hipper := ShipRoster.shared().make("Hipper")
	hipper.damaged = true
	damaged.ships.append(hipper)
	damaged.trajectory.become_station(Vector2i(10, 3))
	st.add_task_force(damaged)
	var result := SoloAI.execute_code("A", st, graph, ActionEngine.load_default(),
		{}, TaskForce.Side.KRIEGSMARINE)
	eq(st.task_force(1), null, "la TF svuotata viene rimossa")
	eq(int(st.solo_counters.get("bl2_removed_ships", 0)), 1,
		"la nave rimossa resta contabilizzata")
	var created := result["active"] as TaskForce
	true_(_tf_has_type(created, "CONVOY"), "con 1-2 crea il Convoglio in South America")
	eq(String(result["turn_kind"]), "declared_gap",
		"dichiara la rotta Azzorre-Faroe non calibrata")
	true_(String((result["log"] as Array)[0]).contains("Azzorre-Faroe"),
		"il limite e' spiegato nel risultato")


func test_bl2_end_procedure() -> void:
	_begin("BL2 E: attacco col BC e condizioni di fine")
	var engine := ActionEngine.load_default()
	var st := GameState.new(graph, 4)
	st.scenario_name = "BL2 Contain and Destroy"
	var british := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	british.ships.append(ShipRoster.shared().make("Convoy x3"))
	british.trajectory.become_station(Vector2i(10, 3))
	st.add_task_force(british)
	var hunt := SoloAI.execute_code("E", st, graph, engine, {},
		TaskForce.Side.KRIEGSMARINE)
	true_(_tf_has_type(hunt["active"], "BC"), "Meteo Buono crea un BC")
	eq(int(st.solo_counters["bl2_e_results"]), 1, "conta il primo risultato E")
	false_(st.solo_ended, "con un Convoglio britannico la caccia continua")
	SoloAI.execute_code("E", st, graph, engine, {}, TaskForce.Side.KRIEGSMARINE)
	eq(_count_tf_type(hunt["active"], "BC"), 2, "il secondo E aggiunge il secondo BC")
	SoloAI.execute_code("E", st, graph, engine, {}, TaskForce.Side.KRIEGSMARINE)
	eq(int(st.solo_counters["bl2_e_results"]), 3, "il terzo E viene ricordato")
	eq(_count_tf_type(hunt["active"], "BC"), 1, "con due BC il terzo E ne rimuove uno")

	var empty := GameState.new(graph, 5)
	empty.scenario_name = "BL2 Contain and Destroy"
	var ended := SoloAI.execute_code("E", empty, graph, engine, {},
		TaskForce.Side.KRIEGSMARINE)
	true_(bool(ended["end_scenario"]), "senza Convogli britannici termina")
	true_(empty.solo_ended, "lo stato ricorda la fine")

	var bad := GameState.new(graph, 6)
	bad.scenario_name = "BL2 Contain and Destroy"
	bad.weather = TimeLapse.Weather.BAD
	var ge_convoy := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	ge_convoy.ships.append(ShipRoster.shared().make("Convoy x2"))
	ge_convoy.trajectory.become_station(Vector2i(9, 3))
	bad.add_task_force(ge_convoy)
	SoloAI.execute_code("E", bad, graph, engine, {}, TaskForce.Side.KRIEGSMARINE)
	true_(ge_convoy.completed, "col Cattivo il Convoglio tedesco completa automaticamente")
	eq(bad.convoys_completed_for(TaskForce.Side.KRIEGSMARINE), 1,
		"il Completamento e' attribuito alla parte tedesca")
	eq(float(bad.vp[TaskForce.Side.ROYAL_NAVY]), -2.0, "applica i VP del Convoglio tedesco")
	var restored := GameState.new(graph, 9)
	restored.apply_dict(bad.to_dict())
	true_(restored.solo_ended, "la fine BL2 sopravvive al salvataggio")
	eq(restored.convoys_completed_for(TaskForce.Side.KRIEGSMARINE), 1,
		"anche il conteggio per parte viene salvato")
	eq(int(restored.solo_counters.get("bl2_e_results", 0)), 1,
		"i contatori della procedura vengono salvati")
	var limits := GameState.new(graph, 10)
	limits.scenario_name = "BL2 Contain and Destroy"
	limits.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	eq(limits.convoys_completed_for(TaskForce.Side.KRIEGSMARINE), 0,
		"una parte senza arrivi non eredita il totale dell'altra parte")
	limits.count_convoy_completed(TaskForce.Side.KRIEGSMARINE)
	eq(limits.convoys_completed_for(TaskForce.Side.ROYAL_NAVY), 1,
		"il conteggio per parte non eredita il totale dell'altra parte")
	true_(SoloAI.enforce_scenario_end(limits),
		"due Convogli complessivi terminano BL2 anche senza un risultato E")
	true_(limits.solo_ended, "la condizione generale marca lo scenario concluso")
	true_(limits.solo_end_reason.contains("Due Convogli"),
		"la causa della fine resta leggibile")
	false_(SoloAI.enforce_scenario_end(limits),
		"dopo la fine non si riapre un altro ciclo della Tabella Azioni")
	var losses := GameState.new(graph, 11)
	losses.scenario_name = "BL2 Contain and Destroy"
	losses.casualties.append({"side": TaskForce.Side.KRIEGSMARINE,
		"ships": ["uno", "due", "tre", "Convoglio"], "convoys": 1})
	true_(SoloAI.enforce_scenario_end(losses), "quattro navi affondate terminano BL2")
	true_(losses.solo_end_reason.contains("Quattro navi"),
		"anche questa causa della fine resta leggibile")


func test_bl2_identification_and_incident() -> void:
	_begin("BL2: Identificazione e Incidente Internazionale applicati")
	var st := GameState.new(graph, 7)
	st.scenario_name = "BL2 Contain and Destroy"
	var unknown := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	unknown.unidentified = true
	unknown.solo_flags["bl2_bring_to_battle"] = true
	unknown.trajectory.become_station(Vector2i(9, 3))
	st.add_task_force(unknown)
	var identified := SoloAI.apply_table_result("identify", {"code": "Convoglio"},
		st, graph, ActionEngine.load_default(), {}, unknown.side, unknown)
	true_(bool(identified["ok"]), "l'identificazione viene applicata")
	false_(unknown.unidentified, "la composizione diventa nota")
	true_(_tf_has_type(unknown, "PB"), "Convoglio in caccia diventa PB")
	true_(_tf_has_type(unknown, "CA"), "e anche CA, come stampato")
	var replacement := GameState.new(graph, 8)
	replacement.scenario_name = "BL2 Contain and Destroy"
	var pb_force := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	for name in ["Graf Spee", "Lutzow"]:
		pb_force.ships.append(ShipRoster.shared().make(name))
	replacement.add_task_force(pb_force)
	var unknown_pb := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	unknown_pb.unidentified = true
	replacement.add_task_force(unknown_pb)
	SoloAI.apply_table_result("identify", {"code": "PB"}, replacement, graph,
		ActionEngine.load_default(), {}, unknown_pb.side, unknown_pb)
	true_(_tf_has_type(unknown_pb, "BC"), "il terzo PB viene sostituito da un BC")
	false_(_tf_has_type(unknown_pb, "PB"), "non aggiunge un PB oltre il limite")

	var incident := SoloAI.apply_table_result("incident", {"code": "backlash"},
		st, graph, ActionEngine.load_default(), {}, unknown.side)
	true_(bool(incident["ok"]), "il Contraccolpo viene applicato")
	eq(float(st.vp[TaskForce.Side.ROYAL_NAVY]), -2.0, "Contraccolpo: -2 VP")
	var airbase := SoloAI.apply_table_result("incident", {"code": "airbase"},
		st, graph, ActionEngine.load_default(), {}, unknown.side)
	true_(String((airbase["log"] as Array)[0]).contains("non e' ancora modellata"),
		"la Base Aerea mancante resta un buco dichiarato")


func test_bl2_completion_destinations() -> void:
	_begin("BL2: i Convogli completano solo alla destinazione stampata")
	var sc := Scenario.load_by_id("BL2 Contain and Destroy")
	var st := GameState.new(graph, 71)
	st.apply_dict(sc.to_state_dict())
	var africa := _tf_named(st, "Convoglio Africa-Portsmouth")
	var halifax := _tf_named(st, "Convoglio Halifax-Clyde")
	ne(africa, null, "Convoglio Africa-Portsmouth caricato")
	ne(halifax, null, "Convoglio Halifax-Clyde caricato")
	var africa_ports := Completion.port_options(africa, graph, sc.port_control())
	eq(africa_ports.size(), 1,
		"la rotta completa offre una sola destinazione valida")
	eq(String(africa_ports[0]["name"]), "Portsmouth",
		"Africa e' il porto di partenza, Portsmouth la destinazione")
	false_(Completion.port_options(halifax, graph, sc.port_control())
		.any(func(p: Dictionary) -> bool: return String(p["name"]) == "Halifax"),
		"Halifax e' il porto di partenza, non una destinazione valida")
	eq(africa.solo_flags.get("completion_ports", []), ["Portsmouth"],
		"la destinazione Africa-Portsmouth resta esplicita nei dati")
	eq(halifax.solo_flags.get("completion_ports", []), ["Clyde", "Liverpool"],
		"entrambe le destinazioni stampate Halifax-Clyde/Liverpool sono ammesse")


func test_bl2_complete_setup_and_neutral_waters() -> void:
	_begin("BL2: setup completo e Acque Neutrali calibrate")
	var sc := Scenario.load_by_id("BL2 Contain and Destroy")
	var st := GameState.new(graph, 73)
	st.apply_dict(sc.to_state_dict())
	var home := _tf_named(st, "Home Fleet")
	var africa := _tf_named(st, "Convoglio Africa-Portsmouth")
	ne(home, null, "Home Fleet piazzata")
	eq(home.afloat_ships().size(), 5, "Repulse, tre CA e un CL")
	eq(home.ships.filter(func(ship: Ship) -> bool:
		return ship.type_code == "CA").size(), 3,
		"le tre CA indicate come any sono presenti")
	eq(home.ships.filter(func(ship: Ship) -> bool:
		return ship.type_code == "CL").size(), 1,
		"il CL indicato come any e' presente")
	eq(home.leader, "Forbes", "Forbes e' assegnato alla Home Fleet")
	eq(africa.trajectory.length(), 8, "Africa-Portsmouth ha gli 8 segmenti stampati")
	eq(africa.trajectory.end_hex(0), Vector2i(12, 4), "la rotta parte da Africa")
	eq(africa.trajectory.end_hex(1), Vector2i(16, -3), "la rotta arriva a Portsmouth")
	true_(_trajectory_is_contiguous(africa), "Africa-Portsmouth e' continua")
	true_(st.commanders.has("Pound"), "Pound e' disponibile senza essere assegnato")
	true_(LeaderRules.has_commander(st, "Pound", TaskForce.Side.ROYAL_NAVY),
		"Pound abilita Passare Tutti")
	eq(String(sc.reinforcement_ports().get("RN Reinforcement A", "")),
		"Scapa Flow", "Rodney e Valiant sono nella casella Scapa Flow")
	eq(String(sc.reinforcement_ports().get("RN Reinforcement B", "")),
		"Brest", "il Gruppo Rinforzi B e' nella casella Brest")
	eq(String(sc.reinforcement_leaders().get("RN Reinforcement B", "")),
		"Gensoul", "Gensoul entra col Gruppo francese")
	eq(Completion.control_of(graph.ports["Bergen"], sc.port_control()), "NONE",
		"Bergen e' neutrale, non un porto controllato britannico")
	var legal := SoloAI.bl2_home_fleet_station_hexes(graph, sc.port_control())
	true_(not legal.is_empty(), "esistono esagoni legali per la Home Fleet")
	for norwegian in ["Bergen", "Trondheim", "Narvik"]:
		for h in graph.adjacent_hexes(graph.port_hex(norwegian)):
			false_(legal.has(h), "%s non offre esagoni alla Home Fleet" % norwegian)
	true_(SoloAI.bl2_is_neutral_water(sc.rules(), Vector2i(17, -9)),
		"il Mare di Norvegia entro il bordo rosa e' Acqua Neutrale")
	false_(SoloAI.bl2_is_neutral_water(sc.rules(), Vector2i(15, -5)),
		"Scapa Flow resta fuori dalle Acque Neutrali")


func test_bl2_battle_identifies_unknown_tf() -> void:
	_begin("BL2: una TF ignota viene identificata prima della Battaglia")
	var sc := Scenario.load_by_id("BL2 Contain and Destroy")
	var st := GameState.new(graph, 72)
	st.scenario_name = sc.id
	var unknown := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	unknown.unidentified = true
	unknown.trajectory.become_station(Vector2i(11, -3))
	st.add_task_force(unknown)
	var opponent := SoloOpponent.load_for(sc.id)
	var result := SoloAI.identify_for_battle(opponent, st, graph,
		ActionEngine.load_default(), sc.port_control(), unknown)
	true_(bool(result.get("ok", false)), "tiro e applicazione riescono nel core")
	true_(bool(result.get("needed", false)), "l'identificazione era necessaria")
	false_(unknown.unidentified, "la TF non resta ignota")
	true_(unknown.afloat_ships().size() > 0,
		"la TF ha navi prima di essere trasferita alla Battaglia")
	true_((result.get("roll", {}) as Dictionary).has("code"),
		"il risultato del tiro resta disponibile per il registro")


func test_bl2_x_keeps_damaged_selection() -> void:
	_begin("BL2 X: una TF danneggiata resta la scelta del risultato C")
	var st := GameState.new(graph, 8)
	st.scenario_name = "BL2 Contain and Destroy"
	var hunter := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var hipper := ShipRoster.shared().make("Hipper")
	hipper.damaged = true
	hunter.ships.append(hipper)
	hunter.trajectory.become_station(Vector2i(9, 3))
	st.add_task_force(hunter)
	var result := SoloAI.execute_code("X", st, graph, ActionEngine.load_default(),
		{}, hunter.side)
	eq(result["active"], hunter, "C usa la stessa TF scelta da X")
	eq(String((result["follow_up"] as Dictionary).get("kind", "")), "completion",
		"la manda verso il Completamento")
	eq(String((result["follow_up"] as Dictionary).get("port_name", "")), "Kiel",
		"senza PB integra rientra a Kiel")


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


func test_bl3_declares_inset_setup_gaps() -> void:
	_begin("BL3: audit dello setup sulla Mappa Inserto")
	var sc := Scenario.load_by_id("BL3 Raiders of the North Sea")
	eq(String(sc.map_info.get("name", "")), "Mappa Inserto del Mare del Nord",
		"BL3 dichiara la plancia corretta")
	true_(String(sc.map_info.get("status", "")).contains("non calibrati"),
		"il reticolo mancante e' dichiarato")
	eq(sc.task_forces.size(), 0,
		"non inventa coordinate sulla Mappa Operazionale")
	true_(sc.commanders.has("Raeder"), "Raeder e' trascritto come comandante strategico")
	var group: Array = sc.reinforcements.get("KM Reinforcement A", [])
	eq(group.size(), 2, "il Gruppo Rinforzi A contiene due CL")
	true_(group.has("Karlsruhe"), "Karlsruhe e' nel Gruppo A")
	true_(group.has("Koln"), "Koln e' nel Gruppo A")
	var notes := " ".join(sc.raw_setup_notes())
	true_(notes.contains("Marschall") and notes.contains("Sottomarino"),
		"Marschall e la forza Sottomarino restano nell'audit dello setup")


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


func test_solo_ai_bl1_blockade_and_french_action() -> void:
	_begin("AI solitaria BL1: Blocco e Azione francese")
	var scenario := Scenario.load_by_id("BL1 Raiders of the North Atlantic")
	var st := GameState.new(graph, 1)
	st.apply_dict(scenario.to_state_dict())
	var block := SoloAI.execute_code("B", st, graph, ActionEngine.load_default(),
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(bool(block["ok"]), "B crea la TF di Blocco")
	eq(block["target_hex"], Vector2i(16, -6), "la Stazione usa l'esagono stampato")
	eq((block["active"] as TaskForce).afloat_ships().size(), 3, "il Blocco contiene tre CA")
	true_(bool(block["roll_again"]), "B ordina un altro tiro immediato")
	var french := SoloAI.execute_code("F", st, graph, ActionEngine.load_default(),
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_((french.get("active", null) as TaskForce).ships.any(
		func(ship: Ship) -> bool: return ship.name == "Dunkerque"),
		"F seleziona davvero la Forza francese")


## AC Solo scenarios 2022 p.7, risultato CONVOGLIO. Prima di questa revisione
## il codice cadeva nel ripiego generico: non tirava il dado di rimando e non
## creava mai la nuova TF con Convoglio e CL.
## p.8: "Before Debriefing, if a German TF Completed in Murmansk, roll a die
## and apply the result." Il tiro non lo faceva nessuno: la tabella c'era ma
## restava da leggere a mano, e i VP del Debriefing uscivano incompleti.
func test_solo_ai_bl1_murmansk_before_debriefing() -> void:
	_begin("AI solitaria BL1: Murmansk prima del Debriefing")
	var opponent := SoloOpponent.load_for("BL1 Raiders of the North Atlantic")
	var st := GameState.new(graph, 5)
	st.scenario_name = "BL1 Raiders of the North Atlantic"
	false_(SoloAI.bl1_murmansk_pending(st),
		"senza Completamenti a Murmansk non si tira niente")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.ships.append(ShipRoster.shared().make("Lutzow"))
	tf.trajectory.become_station(graph.port_hex("Kiel"))
	st.add_task_force(tf)
	tf.completed = true
	tf.completed_port = "Murmansk"
	true_(SoloAI.bl1_murmansk_pending(st),
		"una TF tedesca Completata a Murmansk fa scattare il controllo")
	st.rng.push_forced([1])
	var applied := SoloAI.bl1_murmansk_check(st, opponent.table("murmansk"))
	true_(bool(applied.get("ok", false)), "il controllo viene applicato")
	eq(String((applied.get("roll", {}) as Dictionary).get("code", "")),
		"incidente", "con 1 e nessun modificatore e' un incidente, non la confisca")
	almost(st.vp_of(TaskForce.Side.KRIEGSMARINE), -1.0, 0.001,
		"l'incidente costa 1 VP")
	false_(SoloAI.bl1_murmansk_pending(st), "e si tira una volta sola")

	# Con due Convogli distrutti il modificatore -1 porta l'1 sulla colonna 0.
	var st2 := GameState.new(graph, 5)
	st2.scenario_name = "BL1 Raiders of the North Atlantic"
	var tf2 := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf2.ships.append(ShipRoster.shared().make("Lutzow"))
	tf2.trajectory.become_station(graph.port_hex("Kiel"))
	st2.add_task_force(tf2)
	tf2.completed = true
	tf2.completed_port = "Murmansk"
	st2.casualties.append({"side": TaskForce.Side.ROYAL_NAVY, "convoys": 2,
		"ships": ["Convoy x3", "Convoy x3"]})
	st2.rng.push_forced([1])
	var confiscated := SoloAI.bl1_murmansk_check(st2, opponent.table("murmansk"))
	eq(String((confiscated.get("roll", {}) as Dictionary).get("code", "")),
		"confisca", "con due Convogli distrutti l'1 diventa 0: confisca")
	almost(st2.vp_of(TaskForce.Side.KRIEGSMARINE), -3.0, 0.001,
		"la confisca costa 3 VP")


func test_solo_ai_bl1_convoy_procedure() -> void:
	_begin("AI solitaria BL1: procedura Convoglio")
	var scenario := Scenario.load_by_id("BL1 Raiders of the North Atlantic")
	var engine := ActionEngine.load_default()

	# Ramo 1: c'e' gia' una TF con un Convoglio -> si tira e si rimanda.
	var st := GameState.new(graph, 1)
	st.apply_dict(scenario.to_state_dict())
	var convoys_before := 0
	for tf in st.forces_of(TaskForce.Side.ROYAL_NAVY):
		if SoloAI._has_convoy(tf):
			convoys_before += 1
	true_(convoys_before > 0, "BL1 parte con Convogli britannici in gioco")
	st.rng.push_forced([3])
	var redirected := SoloAI.execute_code("convoy", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(_solo_ai_log_contains(redirected, "1d6=3 -> risultato 'C'"),
		"con 3 il fascicolo rimanda al risultato C")

	# Ramo 2: nessun Convoglio in gioco -> nuova TF con Convoglio e un CL.
	var st2 := GameState.new(graph, 2)
	st2.scenario_name = "BL1 Raiders of the North Atlantic"
	var german := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	german.ships.append(ShipRoster.shared().make("Lutzow"))
	german.trajectory.become_station(Vector2i(15, -2))
	st2.add_task_force(german)
	st2.rng.push_forced([2])            # PARI -> Africa
	var created := SoloAI.execute_code("convoy", st2, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	var british := st2.forces_of(TaskForce.Side.ROYAL_NAVY)
	eq(british.size(), 1, "viene creata una sola TF britannica")
	true_(SoloAI._has_convoy(british[0]) if british.size() == 1 else false,
		"la nuova TF contiene un Convoglio")
	true_(_tf_has_type(british[0] if british.size() == 1 else null, "CL"),
		"e anche un CL, come stampato")
	true_(_solo_ai_log_contains(created, "PARI"),
		"il dado PARI/DISPARI sceglie il porto di partenza")
	eq(int(st2.solo_counters.get("bl1_international_incidents", 0)), 1,
		"la procedura chiude con un Incidente Internazionale")


## p.7: "4+ CAs? If there are four or more British CAs in play, and there is no
## target for an Air Strike, treat this as BOTH an 'A' and an 'F' result. The
## French TF will be the Active TF and the British TF the Coordinating TF."
func test_solo_ai_bl1_four_cruisers_add_the_french_action() -> void:
	_begin("AI solitaria BL1: quattro CA fanno agire la francese")
	var scenario := Scenario.load_by_id("BL1 Raiders of the North Atlantic")
	var st := GameState.new(graph, 3)
	st.apply_dict(scenario.to_state_dict())
	st.weather = TimeLapse.Weather.GOOD
	# Con meno di quattro CA agisce la TF con il CA, non la francese.
	var few := SoloAI.execute_code("A", st, graph, ActionEngine.load_default(),
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	var few_active: TaskForce = few.get("active", null)
	false_(few_active != null and _forces_include_ship([few_active], "Dunkerque"),
		"con pochi CA la francese non e' l'Attiva")

	var st2 := GameState.new(graph, 3)
	st2.apply_dict(scenario.to_state_dict())
	st2.weather = TimeLapse.Weather.GOOD
	var cruisers := TaskForce.new(0, TaskForce.Side.ROYAL_NAVY)
	cruisers.trajectory.become_station(Vector2i(15, -3))
	for cruiser_name in ["Norfolk", "Suffolk", "Devonshire", "Dorsetshire"]:
		cruisers.ships.append(ShipRoster.shared().make(cruiser_name))
	cruisers.recompute_speed()
	st2.add_task_force(cruisers)
	var many := SoloAI.execute_code("A", st2, graph, ActionEngine.load_default(),
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	var active: TaskForce = many.get("active", null)
	true_(active != null and _forces_include_ship([active], "Dunkerque"),
		"con quattro CA l'Attiva e' la TF francese")
	ne(many.get("coordinating", null), null,
		"e la TF britannica con i CA e' designata Coordinatrice")


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
	ca.trajectory.become_station(Vector2i(11, 0))
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
	known.trajectory.become_station(Vector2i(11, 0))
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


func _tf_named(st: GameState, tf_name: String) -> TaskForce:
	for tf in st.task_forces:
		if tf.name == tf_name:
			return tf
	return null


func _tf_with_ship(st: GameState, ship_name: String) -> TaskForce:
	for tf in st.task_forces:
		for ship in tf.ships:
			if ship.name == ship_name:
				return tf
	return null


func _trajectory_is_contiguous(tf: TaskForce) -> bool:
	var hexes := tf.trajectory.hexes()
	for i in range(1, hexes.size()):
		if not graph.is_adjacent(hexes[i - 1], hexes[i]):
			return false
	return true


func _forces_at(st: GameState, h: Vector2i) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in st.task_forces:
		if tf.trajectory.is_station() and tf.trajectory.station_hex == h:
			out.append(tf)
	return out


func _station_adjacent_to_any_rv(st: GameState, tf: TaskForce) -> bool:
	if tf == null or not tf.trajectory.is_station():
		return false
	var h := tf.trajectory.station_hex
	for rv in st.rendezvous_markers:
		var rv_h := Vector2i(int(rv.get("q", 0)), int(rv.get("r", 0)))
		if graph.is_adjacent(h, rv_h):
			return true
	return false


func _forces_include_ship(tfs: Array[TaskForce], ship_name: String) -> bool:
	for tf in tfs:
		for ship in tf.ships:
			if ship.name == ship_name:
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
		# p.8: 0 o meno = confisca, 1-2 = incidente, 3-6 = salvi. La
		# trascrizione era scalata di una colonna e faceva confiscare le navi
		# con un 1, cioe' nel caso piu' comune invece che in quello estremo.
		eq(String(m.read(0, 0)["code"]), "confisca",
			"con 0 o meno le navi sono confiscate")
		eq(String(m.read(0, 1)["code"]), "incidente", "con 1 scoppia un incidente")
		eq(String(m.read(0, 2)["code"]), "incidente", "e anche con 2")
		eq(String(m.read(0, 3)["code"]), "salvi", "da 3 in su rientrano a Kiel")
		eq(String(m.read(0, 6)["code"]), "salvi", "con 6 rientrano a Kiel")
		var sc := Scenario.load_by_id("BL1 Raiders of the North Atlantic")
		eq(String(sc.port_control().get("Murmansk", "")), "KRIEGSMARINE",
			"BL1 consente Murmansk ai tedeschi")
		# p.5: gli unici porti tedeschi sono Kiel, Wilhelmshaven e Murmansk,
		# "unless allowed by a Fueling Check". South America resta quindi
		# chiuso, e lo apre solo il flag messo dal risultato a.
		eq(String(sc.port_control().get("South America", "")), "NONE",
			"BL1 tiene chiuso South America finche' il Rifornimento non lo apre")


func test_bl1_fueling_trigger_conditions() -> void:
	_begin("BL1: innesco obbligatorio del Rifornimento")
	var sc := Scenario.load_by_id("BL1 Raiders of the North Atlantic")
	var st := GameState.new(graph, 1)
	st.apply_dict(sc.to_state_dict())
	var lutzow := _tf_with_ship(st, "Lutzow")
	eq(SoloAI.bl1_fueling_candidates(st).size(), 0,
		"adiacente all'RV non basta: la Stazione deve essere nello stesso esagono")
	lutzow.trajectory.become_station(Vector2i(10, 3))
	var candidates := SoloAI.bl1_fueling_candidates(st)
	eq(candidates.size(), 1, "Stazione tedesca sul marker con Iniziativa: controllo dovuto")
	eq(candidates[0], lutzow, "il controllo riguarda la TF che occupa il marker")
	st.initiative = TaskForce.Side.ROYAL_NAVY
	eq(SoloAI.bl1_fueling_candidates(st).size(), 0,
		"senza Iniziativa tedesca il controllo non scatta")
	st.initiative = TaskForce.Side.KRIEGSMARINE
	var applied := SoloAI.apply_table_result("fueling", {"code": "f"}, st, graph,
		ActionEngine.load_default(), sc.port_control(), TaskForce.Side.ROYAL_NAVY, lutzow)
	true_(bool(applied["ok"]), "il risultato della tabella viene applicato")
	true_(st.rendezvous_at(Vector2i(10, 3)).is_empty(), "il risultato f rimuove l'RV")
	eq(SoloAI.bl1_fueling_candidates(st).size(), 0, "un RV rimosso non si innesca di nuovo")

	var no_rv := GameState.new(graph, 2)
	no_rv.scenario_name = "BL1 Raiders of the North Atlantic"
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.trajectory.become_station(Vector2i(10, 3))
	no_rv.add_task_force(tf)
	var refused := SoloAI.apply_table_result("fueling", {"code": "f"}, no_rv, graph,
		ActionEngine.load_default(), sc.port_control(), TaskForce.Side.ROYAL_NAVY, tf)
	false_(bool(refused["ok"]), "senza marker il Rifornimento viene rifiutato")
	true_(String((refused["log"] as Array)[0]).contains("nessun marker RV"),
		"il rifiuto dichiara il dato mancante")
	tf.solo_flags["bl1_no_more_fueling"] = true
	no_rv.rendezvous_markers.append({"id": "rv", "q": 10, "r": 3})
	eq(SoloAI.bl1_fueling_candidates(no_rv).size(), 0,
		"l'esito a impedisce davvero ulteriori Controlli")


func test_solo_ai_bl1_aux_tables_apply() -> void:
	_begin("AI solitaria BL1: tabelle ausiliarie applicate")
	var control := Scenario.load_by_id("BL1 Raiders of the North Atlantic").port_control()
	var st := GameState.new(graph, 1)
	st.scenario_name = "BL1 Raiders of the North Atlantic"
	var unk := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	unk.name = "TF ignota"
	unk.unidentified = true
	st.add_task_force(unk)
	var id_res := SoloAI.apply_table_result("identify", {"code": "BC/CA/CL"},
		st, graph, ActionEngine.load_default(), control, TaskForce.Side.ROYAL_NAVY, unk)
	true_(bool(id_res["ok"]), "Identificazione applicata")
	false_(unk.unidentified, "la TF non resta ignota")
	eq(unk.ships.size(), 3, "assegna tre navi")
	eq(unk.ships[0].name, "Hood", "sceglie una BC disponibile")

	var mur := SoloAI.apply_table_result("murmansk", {"code": "confisca"},
		st, graph, ActionEngine.load_default(), control, TaskForce.Side.ROYAL_NAVY)
	true_(bool(mur["ok"]), "Murmansk confisca applicata")
	eq(float(st.vp[TaskForce.Side.KRIEGSMARINE]), -3.0, "confisca: -3 VP")
	var inc := SoloAI.apply_table_result("murmansk", {"code": "incidente"},
		st, graph, ActionEngine.load_default(), control, TaskForce.Side.ROYAL_NAVY)
	true_(bool(inc["ok"]), "Murmansk incidente applicato")
	eq(float(st.vp[TaskForce.Side.KRIEGSMARINE]), -4.0, "incidente: altro -1 VP")

	var south := Vector2i(6, 7)
	var km := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	km.ships.append(ShipRoster.shared().make("Lutzow"))
	km.ships[0].hits = 1
	km.trajectory.become_station(south)
	st.add_task_force(km)
	st.rendezvous_markers.append({"id": "rv-south", "q": south.x, "r": south.y})
	var fuel_a := SoloAI.apply_table_result("fueling", {"code": "a"},
		st, graph, ActionEngine.load_default(), control, TaskForce.Side.ROYAL_NAVY, km)
	true_(bool(fuel_a["ok"]), "Rifornimento a applicato")
	true_(st.rendezvous_at(south).is_empty(), "Rifornimento a rimuove l'RV")
	eq(km.ships[0].hits, 0, "ripara un Colpo")
	eq(String(km.solo_flags.get("bl1_completion_port", "")), "South America",
		"imposta South America come unico porto")
	true_(bool(km.solo_flags.get("bl1_no_reorganize", false)), "vieta Riorganizzazione")
	eq(String(Completion.port_options(km, graph, control)[0]["name"]), "South America",
		"il filtro di Completamento accetta solo South America")

	var st2 := GameState.new(graph, 1)
	st2.scenario_name = "BL1 Raiders of the North Atlantic"
	var km2 := TaskForce.new(3, TaskForce.Side.KRIEGSMARINE)
	km2.ships.append(ShipRoster.shared().make("Lutzow"))
	km2.evasive = true
	km2.trajectory.become_station(Vector2i(10, 0))
	st2.add_task_force(km2)
	st2.rendezvous_markers.append({"id": "rv-mech", "q": 10, "r": 0})
	var rn2 := TaskForce.new(4, TaskForce.Side.ROYAL_NAVY)
	rn2.ships.append(ShipRoster.shared().make("Hood"))
	rn2.trajectory.become_station(Vector2i(10, 0))
	st2.add_task_force(rn2)
	var fuel_d := SoloAI.apply_table_result("fueling", {"code": "d"},
		st2, graph, ActionEngine.load_default(), control, TaskForce.Side.ROYAL_NAVY, km2)
	true_(bool(fuel_d["ok"]), "Rifornimento d applicato")
	false_(km2.evasive, "rimuove Manovre Evasive")
	true_((km2.solo_flags.get("bl1_actions_only", []) as Array).has("TRAJECTORY"),
		"limita le azioni della TF")
	eq(String(fuel_d.get("initiative", "")), "vie", "con britannici nell'esagono chiede VforI")
	true_(st2.rendezvous_at(Vector2i(10, 0)).is_empty(), "Rifornimento d rimuove l'RV")


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

	st.advanced = true
	var attitudes := SoloBattle.attitude_choices(st, TaskForce.Side.ROYAL_NAVY)
	eq(int(attitudes[convoy]), Attitude.Kind.RUNNING,
		"il bot mette il Convoglio in Corsa")
	eq(int(attitudes[hood]), Attitude.Kind.ACQUIRING,
		"una nave britannica senza siluri gia' Vicina acquisisce il bersaglio")
	hipper.attitude = Attitude.Kind.CLOSING
	var hipper_move := SoloBattle.maneuver_for_ship(st, hipper,
		TaskForce.Side.KRIEGSMARINE)
	eq(int(hipper_move["zone"]), BattleState.Zone.CLOSE,
		"la Manovra automatica avanza di una sola zona")
	convoy.attitude = Attitude.Kind.RUNNING
	convoy.battle_zone = BattleState.Zone.FAR
	hipper.attitude = Attitude.Kind.CLOSING
	eq(SoloBattle.pursuit_target(st, hipper, TaskForce.Side.KRIEGSMARINE), convoy,
		"il bot Insegue una nave in Corsa prima del passo Fuga")


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
	true_(view._can_control_ship(hood), "il giocatore controlla la propria nave")
	false_(view._can_control_ship(hipper), "ma non puo' comandare quella del bot")

	st.advanced = true
	st.phase = BattleState.Phase.TORPEDO
	hipper.has_torpedo = true
	hipper.attitude = Attitude.Kind.CLOSING
	var torpedoes := view._auto_targeting_for_phase()
	eq(torpedoes.get(hipper), hood,
		"i siluri legali del bot vengono assegnati nella fase Siluri")

	st.phase = BattleState.Phase.MANEUVER
	hipper.attitude = Attitude.Kind.CLOSING
	hipper.battle_zone = BattleState.Zone.NEAR
	view._maneuvered = [hood] as Array[Ship]
	view._run_bot_maneuvers_until_player()
	eq(hipper.battle_zone, BattleState.Zone.CLOSE,
		"quando arriva il suo turno il bot muove immediatamente")
	true_(view._maneuvered.has(hipper), "e non puo' muovere la stessa nave due volte")
	view.free()
