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
	test_solo_ai_bl1_bdienst()
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
	test_solo_ai_n4_r4_first_then_second()
	test_solo_ai_n4_convoy_becomes_r4_after_r4()
	test_solo_ai_n4_x_ends_the_scenario_without_a_target()
	test_n4_norwegian_reaction_table_is_transcribed()
	test_solo_ai_n6_trajectory_ends_after_two_norwegian_convoys()
	test_solo_ai_n6_intercept_ends_after_three_german_losses()
	test_solo_ai_n6_weather_redirects()
	test_solo_ai_n6_passes_at_fifteen_segments()
	test_n6_procedures_are_transcribed()
	test_solo_ai_b1_end_result_removes_rendezvous()
	test_solo_ai_b1_end_result_good_weather_branches()
	test_solo_ai_b1_intercept_ends_after_three_convoys()
	test_b1_procedures_are_transcribed()
	test_solo_ai_b3_intercept_end_conditions()
	test_b3_identify_third_column_has_three_ships()
	test_b3_procedures_are_transcribed()
	test_n3_procedures_are_transcribed()
	test_n3_contact_cell_is_not_empty()
	test_n3_contact_marks_bergen_and_kristiansand()
	test_n3_stealth_recon_places_the_submarine_nearest_bergen()
	test_n3_stealth_recon_in_bergen_becomes_contact()
	test_n3_stealth_attack_uses_the_submarine_with_the_printed_bonus()
	test_n3_stealth_attack_falls_back_to_recon()
	test_n3_bring_on_battle_measures_from_the_submarine()
	test_n3_trajectory_to_bergen_has_a_second_step()
	test_n3_convoy_is_replaced_by_a_cruiser_before_battle()
	test_n5_procedures_are_transcribed()
	test_n5_identify_fourth_column_has_two_light_cruisers()
	test_n5_air_strike_places_air_base_markers()
	test_n5_air_strike_removes_a_british_marker_instead()
	test_n5_convoy_rolls_for_its_norwegian_port()
	test_n5_bring_on_battle_ends_on_scapa_flow_only()
	test_n5_bring_on_battle_time_lapse_is_nearest_to_kiel()
	test_norway_landings_survive_a_save()
	test_placed_air_bases_survive_a_save()
	test_n2_procedures_are_transcribed()
	test_n2_early_table_has_no_modifiers()
	test_n2_identify_columns_are_not_shifted()
	test_n2_port_actions_use_the_inset_places()
	test_n2_mines_roll_their_hex_and_are_not_recon()
	test_n2_r4_becomes_x_the_second_time()
	test_n2_trondheim_falls_back_to_x_and_n()
	test_n2_new_british_tf_uses_only_slow_battleships()
	test_b2_reinforcement_groups_match_the_printed_display()
	test_b2_replay_reaches_three_convoys()
	test_b2_procedures_are_transcribed()
	test_b4_reinforcement_groups_match_the_printed_display()
	test_b4_replay_reaches_three_convoys()
	test_b4_procedures_are_transcribed()
	test_a1_reinforcement_group_a_rolls_its_route()
	test_solo_ai_a1_intercept_ends_when_a_german_bb_is_gone()
	test_a1_replay_reaches_three_convoys()
	test_intel_marker_once_works_for_both_sides()
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
		# Cinque scenari solitari si giocano su una MAPPA INSERTO, non sulla
		# Mappa Operazionale. Prima ci piazzavano le TF su porti della mappa
		# grande usati come sostituti, cioe' su posizioni inventate: il
		# controllo non e' "nessuna TF" - BL3 adesso ce le ha, sull'inserto - ma
		# "nessuna TF fuori dalla propria mappa".
		if not sc.map_info.is_empty():
			true_(str(sc.raw_setup_notes()).contains("Mappa Inserto"),
				"%s: dichiara su quale mappa si gioca" % id)
			var inset := MapGraph.load_inset(sc.inset_key())
			eq(inset.load_error, "", "%s: l'inserto dichiarato si carica" % id)
			var stray := 0
			var st_i := GameState.new(inset, 1)
			st_i.apply_dict(sc.to_state_dict())
			for tf in st_i.task_forces:
				for h in tf.trajectory.hexes():
					if not inset.has_hex(h):
						stray += 1
			eq(stray, 0, "%s: nessuna TF fuori dalla propria mappa" % id)
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
	# Le condizioni di fine non sono piu' scritte nel codice: stanno nel dato
	# di scenario e arrivano nello stato con `to_state_dict`. Un GameState
	# costruito a mano deve quindi caricarle, come fa una partita vera.
	limits.solo_end_conditions = Scenario.load_by_id(
		"BL2 Contain and Destroy").end_conditions()
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
	losses.solo_end_conditions = Scenario.load_by_id(
		"BL2 Contain and Destroy").end_conditions()
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
		"Pound abilita Passare Tutto")
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
	# Questa asserzione controllava che lo scenario dichiarasse "reticolo non
	# calibrato". Adesso il reticolo E' calibrato, la mappa e' misurata e
	# verificata, e il motore la carica: quel testo era diventato falso. Cio'
	# che ancora manca e' lo SCHIERAMENTO, e ora e' quello che va dichiarato.
	eq(sc.inset_key(), "map_north_sea", "BL3 dice su quale inserto si gioca")
	var status := String(sc.map_info.get("status", ""))
	true_(status.to_lower().contains("schieramento"),
		"lo schieramento mancante e' dichiarato: %s" % status)
	false_(status.contains("non calibrat"),
		"e non si dichiara piu' un reticolo non calibrato, perche' lo e'")
	var inset := MapGraph.load_inset(sc.inset_key())
	eq(inset.load_error, "", "e l'inserto dichiarato si carica davvero")
	true_(inset.hex_count() > 0, "con i suoi esagoni")
	# Questa asserzione pretendeva che BL3 non avesse schieramento. Adesso ce
	# l'ha, letto dall'illustrazione di p.12, e quello che conta e' che stia
	# sull'inserto: la Traiettoria britannica e' una fila di cinque segmenti.
	eq(sc.task_forces.size(), 2, "BL3 schiera due Task Force")
	var st_bl3 := GameState.new(inset, 1)
	st_bl3.apply_dict(sc.to_state_dict())
	var off := 0
	for tf in st_bl3.task_forces:
		for h in tf.trajectory.hexes():
			if not inset.has_hex(h):
				off += 1
	eq(off, 0, "e tutte le posizioni stanno sull'inserto, non su coordinate inventate")
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
## B-Dienst (p.5): "When the Germans have Initiative, you may attach an Intel
## marker to a British Trajectory segment ... only once during the scenario."
func test_solo_ai_bl1_bdienst() -> void:
	_begin("AI solitaria BL1: B-Dienst")
	var st := GameState.new(graph, 9)
	st.scenario_name = "BL1 Raiders of the North Atlantic"
	st.solo_intel_marker_once = Scenario.load_by_id(
		"BL1 Raiders of the North Atlantic").intel_marker_once()
	st.initiative = TaskForce.Side.ROYAL_NAVY
	false_(SoloAI.intel_marker_available(st),
		"senza Iniziativa tedesca il B-Dienst non e' disponibile")
	st.initiative = TaskForce.Side.KRIEGSMARINE
	true_(SoloAI.intel_marker_available(st), "con l'Iniziativa tedesca lo e'")

	var station := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	station.ships.append(ShipRoster.shared().make("Hood"))
	station.trajectory.become_station(Vector2i(15, -3))
	st.add_task_force(station)
	eq(SoloAI.intel_marker_targets(st).size(), 0,
		"una Stazione non e' una Traiettoria: non e' un bersaglio")

	var moving := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	moving.ships.append(ShipRoster.shared().make("Norfolk"))
	moving.trajectory.become_station(Vector2i(14, -3))
	for h in graph.adjacent_hexes(Vector2i(14, -3)):
		if moving.trajectory.extend(h, 1, graph):
			break
	eq(SoloAI.intel_marker_targets(st).size(), 0,
		"la TF non e' ancora nello stato: non compare fra i bersagli")
	st.add_task_force(moving)
	eq(SoloAI.intel_marker_targets(st).size(), 1,
		"una Traiettoria britannica senza Informazioni e' un bersaglio")

	var target_hex: Vector2i = (moving.trajectory.segments[0] as Dictionary)["hex"]
	var applied := SoloAI.intel_marker_apply(st, moving, target_hex)
	true_(bool(applied.get("ok", false)), "il segnalino viene attaccato")
	eq(moving.info_count(), 1, "la Traiettoria ha ora un segnalino Informazioni")
	false_(moving.can_complete(),
		"e con Informazioni la TF non puo' piu' Completare (RB p.21)")
	false_(SoloAI.intel_marker_available(st),
		"il B-Dienst vale una volta sola per scenario")
	var again := SoloAI.intel_marker_apply(st, moving, target_hex)
	false_(bool(again.get("ok", false)), "un secondo uso viene rifiutato")


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


## N4, AC Solo scenarios 2022 pp.29-30, lette sulle pagine renderizzate.
## Il fascicolo stampa DUE procedure sotto la lettera R4 e le fa dipendere da
## quante volte R4 e' gia' uscito; altre due procedure - Convoglio e X -
## guardano lo stesso conto. Prima si eseguiva sempre la prima, quindi al
## secondo R4 il britannico ricreava TF4 e TF5 invece di far Completare a
## Narvik quelle che aveva gia' mandato li'.
func test_solo_ai_n4_r4_first_then_second() -> void:
	_begin("AI solitaria N4: primo R4 e successivi")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N4 Operazione Weser (nord & sud)")
	var st := GameState.new(graph, 3)
	st.apply_dict(scenario.to_state_dict())
	var british_before := st.forces_of(TaskForce.Side.ROYAL_NAVY).size()

	var first := SoloAI.execute_code("R4", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	eq(int(st.solo_counters.get("n4_r4_results", 0)), 1, "il primo R4 e' contato")
	var after_first := st.forces_of(TaskForce.Side.ROYAL_NAVY)
	true_(after_first.size() >= british_before + 3,
		"il primo R4 crea TF4, TF5 e TF6 (nessun DD tedesco ha Completato a Trondheim)")
	true_(_forces_include_ship(after_first, "Furious"),
		"TF5 contiene la portaerei Furious, come stampato")
	# p.30: TF5 e' "Furious (CV), French CL, and a British CA". Il CL francese
	# non c'era: al suo posto c'era un secondo incrociatore britannico.
	var has_french := false
	for tf in after_first:
		for ship in tf.ships:
			if ship.nation == "FR":
				has_french = true
	true_(has_french, "TF5 imbarca il CL francese previsto dal fascicolo")
	true_(_solo_ai_log_contains(first, "TF4 verso Narvik"), "TF4 punta a Narvik")
	true_(_solo_ai_log_contains(first, "TF6 verso Trondheim"), "TF6 punta a Trondheim")

	# Secondo R4: nessuna nuova Task Force, si Completa con quella che c'e'.
	var count_before := st.forces_of(TaskForce.Side.ROYAL_NAVY).size()
	var second := SoloAI.execute_code("R4", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	eq(int(st.solo_counters.get("n4_r4_results", 0)), 2, "anche il secondo e' contato")
	eq(st.forces_of(TaskForce.Side.ROYAL_NAVY).size(), count_before,
		"il secondo R4 non crea altre Task Force")
	true_(_solo_ai_log_contains(second, "R4 numero 2"),
		"e il registro dice che e' il secondo")


## p.29: "If the R4 Action Table result was garnered previously, treat this as
## 'R4' instead." Il risultato Convoglio non lo faceva.
func test_solo_ai_n4_convoy_becomes_r4_after_r4() -> void:
	_begin("AI solitaria N4: Convoglio diventa R4 dopo un R4")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N4 Operazione Weser (nord & sud)")
	var st := GameState.new(graph, 4)
	st.apply_dict(scenario.to_state_dict())
	var plain := SoloAI.execute_code("Conv", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	false_(_solo_ai_log_contains(plain, "diventa un R4"),
		"senza R4 precedenti il Convoglio resta un Convoglio")
	st.solo_counters["n4_r4_results"] = 1
	var redirected := SoloAI.execute_code("Conv", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(_solo_ai_log_contains(redirected, "diventa un R4"),
		"dopo un R4 il risultato Convoglio diventa un R4")


## p.30, PORTARE IN BATTAGLIA: due clausole stampate mancavano. Il rimando a R4
## col dado PARI, e "If no target, the scenario ends" - che e' poi il
## "(or possibly by Action Table result 'X')" del riquadro The End.
func test_solo_ai_n4_x_ends_the_scenario_without_a_target() -> void:
	_begin("AI solitaria N4: la X senza bersaglio chiude lo scenario")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N4 Operazione Weser (nord & sud)")
	var st := GameState.new(graph, 5)
	st.apply_dict(scenario.to_state_dict())
	# Tolgo ogni TF tedesca: e' la condizione stampata.
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		st.remove_task_force(tf)
	var out := SoloAI.execute_code("X", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(bool(out.get("end_scenario", false)), "la X dichiara la fine")
	true_(st.solo_ended, "e lo stato risulta concluso")
	true_(st.solo_end_reason.contains("Battaglia"),
		"il motivo cita la mancanza di bersagli: %s" % st.solo_end_reason)

	# Con R4 gia' uscito la X tira un dado: PARI la trasforma in R4.
	var st2 := GameState.new(graph, 6)
	st2.apply_dict(scenario.to_state_dict())
	st2.solo_counters["n4_r4_results"] = 1
	st2.rng.push_forced([2])
	var even := SoloAI.execute_code("X", st2, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(_solo_ai_log_contains(even, "PARI: la X diventa un R4"),
		"col dado PARI la X diventa un R4")
	var st3 := GameState.new(graph, 7)
	st3.apply_dict(scenario.to_state_dict())
	st3.solo_counters["n4_r4_results"] = 1
	st3.rng.push_forced([3])
	var odd := SoloAI.execute_code("X", st3, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	false_(_solo_ai_log_contains(odd, "PARI: la X diventa un R4"),
		"col dado DISPARI resta una X")


## La Reazione Norvegese di N4 (p.30) non era trascritta affatto: la tabella
## c'era nel fascicolo e non nei dati.
func test_n4_norwegian_reaction_table_is_transcribed() -> void:
	_begin("N4: Reazione Norvegese trascritta")
	var o := SoloOpponent.load_for("N4 Operazione Weser (nord & sud)")
	var t: SoloTable = o.table("norwegian_reaction")
	ne(t, null, "la tabella della Reazione Norvegese esiste")
	eq(t.rows.size(), 2, "due righe: TF britannica nell'esagono si' e no")
	# Le colonne stampate vanno da "1 o meno" a "7-8": la prima e l'ultima si
	# raggiungono solo coi modificatori, quindi la riga parte da zero.
	eq(String(t.read(1, 1)["code"]), "annullato",
		"con TF britannica e 1 il Completamento e' annullato")
	eq(String(t.read(1, 3)["code"]), "due_colpi", "con 3-4 sono due Colpi")
	eq(String(t.read(1, 5)["code"]), "un_colpo", "con 5-6 e' un Colpo")
	eq(String(t.read(1, 7)["code"]), "nessuno", "con 7-8 nessun effetto")
	eq(String(t.read(0, 2)["code"]), "un_colpo",
		"senza TF britannica il 2 e' gia' un Colpo")
	eq(String(t.read(0, 7)["code"]), "base_aerea",
		"senza TF britannica il 7-8 piazza una base aerea tedesca")
	eq(t.modifier_total(["uno o piu' BC, CA o CL tedeschi sono nell'esagono"]), 1,
		"il modificatore delle navi da guerra nell'esagono vale +1")
	eq(t.modifier_total(["il marcatore di base aerea britannica e' nell'esagono di Completamento"]),
		-2, "la base aerea britannica nell'esagono vale -2")
	for code in ["nessuno", "un_colpo", "due_colpi", "annullato", "base_aerea"]:
		ne(String(t.legend.get(code, "")), "",
			"la procedura '%s' e' trascritta" % code)


## N6, AC Solo scenarios 2022 pp.36-38. Le quattro tabelle e i modificatori
## coincidevano gia' col fascicolo; erano le 25 procedure a essere segnaposto,
## e N6 non aveva nessuna policy propria: cadeva nel ripiego generico, quindi
## le due condizioni di fine stampate DENTRO i risultati non si verificavano
## mai. Sono il "It may also end by the German Action Table" del riquadro
## The End.
func test_solo_ai_n6_trajectory_ends_after_two_norwegian_convoys() -> void:
	_begin("AI solitaria N6: due Convogli tedeschi in Norvegia chiudono lo scenario")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N6 Il Dilemma delle Operazioni")
	var st := GameState.new(graph, 3)
	st.apply_dict(scenario.to_state_dict())
	var running := SoloAI.execute_code("T", st, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	false_(st.solo_ended, "senza Completamenti norvegesi la 'T' non chiude niente")
	false_(bool(running.get("end_scenario", false)), "e non lo dichiara")

	# Due Convogli tedeschi Completati in porti norvegesi.
	for port in ["Bergen", "Trondheim"]:
		var done := TaskForce.new(0, TaskForce.Side.KRIEGSMARINE)
		done.completed = true
		done.completed_port = port
		done.completed_ships = ["Convoy x2"] as Array[String]
		st.add_task_force(done)
	var over := SoloAI.execute_code("T", st, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	true_(bool(over.get("end_scenario", false)), "la 'T' dichiara la fine")
	true_(st.solo_ended, "e lo stato risulta concluso")
	true_(st.solo_end_reason.contains("Norvegia"),
		"il motivo cita i Convogli in Norvegia: %s" % st.solo_end_reason)


func test_solo_ai_n6_intercept_ends_after_three_german_losses() -> void:
	_begin("AI solitaria N6: tre navi tedesche perse chiudono lo scenario")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N6 Il Dilemma delle Operazioni")
	var st := GameState.new(graph, 4)
	st.apply_dict(scenario.to_state_dict())
	SoloAI.execute_code("X", st, graph, engine, scenario.port_control(),
		TaskForce.Side.KRIEGSMARINE)
	false_(st.solo_ended, "senza perdite la 'X' non chiude niente")
	st.casualties.append({"side": TaskForce.Side.KRIEGSMARINE,
		"ships": ["uno", "due", "tre"], "convoys": 1})
	var over := SoloAI.execute_code("X", st, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	true_(bool(over.get("end_scenario", false)), "la 'X' dichiara la fine")
	true_(st.solo_ended, "e lo stato risulta concluso")
	true_(st.solo_end_reason.contains("affondate"),
		"il motivo cita le navi perse: %s" % st.solo_end_reason)


## p.37: col Meteo Cattivo la 'A' diventa una 'X'; senza TF tedesche la 'C'
## diventa una 'A', ma col Meteo Cattivo crea invece una TF a Wilhelmshaven con
## un Convoglio e la scorta tirata sul dado (1-2 CA, 3-4 CL, 5-6 due CL).
func test_solo_ai_n6_weather_redirects() -> void:
	_begin("AI solitaria N6: i rimandi che dipendono dal meteo")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N6 Il Dilemma delle Operazioni")
	var st := GameState.new(graph, 5)
	st.apply_dict(scenario.to_state_dict())
	st.weather = TimeLapse.Weather.BAD
	var as_x := SoloAI.execute_code("A", st, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	true_(_solo_ai_log_contains(as_x, "la 'A' diventa una 'X'"),
		"col Meteo Cattivo la 'A' diventa una 'X'")

	# 'C' senza TF tedesche, Meteo Cattivo: nasce la TF di Wilhelmshaven.
	var st2 := GameState.new(graph, 6)
	st2.apply_dict(scenario.to_state_dict())
	st2.weather = TimeLapse.Weather.BAD
	for tf in st2.forces_of(TaskForce.Side.KRIEGSMARINE):
		st2.remove_task_force(tf)
	st2.rng.push_forced([5, 3])   # 5-6 = due CL; poi il porto del Convoglio
	SoloAI.execute_code("C", st2, graph, engine, scenario.port_control(),
		TaskForce.Side.KRIEGSMARINE)
	var germans := st2.forces_of(TaskForce.Side.KRIEGSMARINE)
	eq(germans.size(), 1, "nasce una sola TF tedesca")
	true_(SoloAI._has_convoy(germans[0]) if germans.size() == 1 else false,
		"con dentro il Convoglio previsto")
	eq(_count_tf_type(germans[0] if germans.size() == 1 else null, "CL"), 2,
		"e col 5 sul dado la scorta e' di due CL")

	# 'C' senza TF tedesche ma con Meteo Buono: diventa una 'A'.
	var st3 := GameState.new(graph, 7)
	st3.apply_dict(scenario.to_state_dict())
	st3.weather = TimeLapse.Weather.GOOD
	for tf in st3.forces_of(TaskForce.Side.KRIEGSMARINE):
		st3.remove_task_force(tf)
	var as_a := SoloAI.execute_code("C", st3, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	true_(_solo_ai_log_contains(as_a, "la 'C' diventa una 'A'"),
		"col Meteo Buono e senza TF la 'C' diventa una 'A'")


## p.38: "15 Segments already? If the selected TF already has 15 segments, the
## Germans Pass instead."
func test_solo_ai_n6_passes_at_fifteen_segments() -> void:
	_begin("AI solitaria N6: con 15 segmenti il tedesco Passa")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N6 Il Dilemma delle Operazioni")
	var st := GameState.new(graph, 8)
	st.apply_dict(scenario.to_state_dict())
	var tf := TaskForce.new(0, TaskForce.Side.KRIEGSMARINE)
	tf.ships.append(ShipRoster.shared().make("Scharnhorst"))
	tf.trajectory.become_station(Vector2i(17, -5))
	st.add_task_force(tf)
	var cur := Vector2i(17, -5)
	while tf.length() < 15:
		var grew := false
		for h in graph.adjacent_hexes(cur):
			if tf.trajectory.extend(h, 1, graph, st.port_hexes(), false, tf.side):
				cur = h
				grew = true
				break
		if not grew:
			break
	eq(tf.length(), 15, "la Traiettoria di prova arriva a 15 segmenti")
	var out := SoloAI.execute_code("T", st, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	eq(String(out.get("turn_kind", "")), "pass", "con 15 segmenti si Passa")
	true_(_solo_ai_log_contains(out, "15 segmenti"),
		"e il registro dice perche'")


## Le 25 procedure di N6 erano segnaposto: rimandavano a un dump grezzo invece
## di riportare il testo del fascicolo.
func test_n6_procedures_are_transcribed() -> void:
	_begin("N6: le 25 procedure sono trascritte")
	var o := SoloOpponent.load_for("N6 Il Dilemma delle Operazioni")
	var placeholders := 0
	var total := 0
	for tid in ["actions", "trajectory", "t_second_action", "identify"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(total, 25, "le procedure trascritte sono venticinque")
	eq(placeholders, 0, "e nessuna e' rimasta un segnaposto")
	# Le due condizioni di fine stampate dentro i risultati devono restare
	# leggibili nel testo: sono il "It may also end by the German Action Table".
	var actions: SoloTable = o.table("actions")
	true_(String(actions.legend.get("T", "")).contains("LO SCENARIO FINISCE"),
		"la 'T' dichiara la propria condizione di fine")
	true_(String(actions.legend.get("X", "")).contains("LO SCENARIO FINISCE"),
		"e anche la 'X'")


## B1, AC Solo scenarios 2022 pp.41-44. Le celle e i modificatori coincidevano
## gia' col fascicolo; mancavano le 22 procedure e, nel codice, tutto il
## risultato 'E': non esisteva un ramo per lui, quindi finiva nel ripiego che
## lo trattava come un Convoglio. E' l'unico modo in cui il BRITANNICO toglie
## marker Rendezvous dalla mappa.
func test_solo_ai_b1_end_result_removes_rendezvous() -> void:
	_begin("AI solitaria B1: il risultato E toglie i marker Rendezvous")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("B1 Operazione Berlino")
	var st := GameState.new(graph, 3)
	st.apply_dict(scenario.to_state_dict())
	st.solo_end_conditions = scenario.end_conditions()
	st.rendezvous_markers = [
		{"q": 10, "r": 3, "active": true},
		{"q": 9, "r": -2, "active": true},
	] as Array[Dictionary]
	st.weather = TimeLapse.Weather.BAD
	var before := st.active_rendezvous_count()
	var out := SoloAI.execute_code("E", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	eq(st.active_rendezvous_count(), before - 1,
		"col Meteo Cattivo la 'E' toglie un marker Rendezvous")
	false_(st.solo_ended, "finche' ce ne sono, lo scenario continua")
	true_(_solo_ai_log_contains(out, "Marker Rendezvous rimosso"),
		"e il registro lo dice")

	# Tolto l'ultimo, la 'E' successiva chiude lo scenario.
	SoloAI.execute_code("E", st, graph, engine, scenario.port_control(),
		TaskForce.Side.ROYAL_NAVY)
	eq(st.active_rendezvous_count(), 0, "il secondo marker se ne va")
	var over := SoloAI.execute_code("E", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(bool(over.get("end_scenario", false)),
		"senza piu' marker la 'E' dichiara la fine")
	true_(st.solo_ended, "e lo stato risulta concluso")
	true_(st.solo_end_reason.contains("Rendezvous"),
		"il motivo cita i marker: %s" % st.solo_end_reason)


## p.43, Meteo Buono: 1 toglie un marker e fa ritirare la Tabella, 2-4 diventa
## una 'X', 5-6 una 'A'.
func test_solo_ai_b1_end_result_good_weather_branches() -> void:
	_begin("AI solitaria B1: i tre rami della 'E' col Meteo Buono")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("B1 Operazione Berlino")

	var st := GameState.new(graph, 4)
	st.apply_dict(scenario.to_state_dict())
	st.rendezvous_markers = [{"q": 10, "r": 3, "active": true}] as Array[Dictionary]
	st.weather = TimeLapse.Weather.GOOD
	st.rng.push_forced([1])
	var one := SoloAI.execute_code("E", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	eq(st.active_rendezvous_count(), 0, "con 1 il marker se ne va")
	true_(bool(one.get("roll_again", false)),
		"e la Tabella si ritira subito, come stampato")

	var st2 := GameState.new(graph, 5)
	st2.apply_dict(scenario.to_state_dict())
	st2.weather = TimeLapse.Weather.GOOD
	st2.rng.push_forced([3])
	var as_x := SoloAI.execute_code("E", st2, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(_solo_ai_log_contains(as_x, "trattato come una 'X'"),
		"con 2-4 la 'E' diventa una 'X'")

	var st3 := GameState.new(graph, 6)
	st3.apply_dict(scenario.to_state_dict())
	st3.weather = TimeLapse.Weather.GOOD
	st3.rng.push_forced([6])
	var as_a := SoloAI.execute_code("E", st3, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(_solo_ai_log_contains(as_a, "trattato come una 'A'"),
		"con 5-6 la 'E' diventa una 'A'")


## p.43: "End? If three British Convoys have successfully Completed, the
## scenario ends." Il ramo 'X' non lo verificava.
func test_solo_ai_b1_intercept_ends_after_three_convoys() -> void:
	_begin("AI solitaria B1: tre Convogli britannici chiudono lo scenario")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("B1 Operazione Berlino")
	var st := GameState.new(graph, 7)
	st.apply_dict(scenario.to_state_dict())
	SoloAI.execute_code("X", st, graph, engine, scenario.port_control(),
		TaskForce.Side.ROYAL_NAVY)
	false_(st.solo_ended, "senza Completamenti la 'X' non chiude niente")
	for i in 3:
		st.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	var over := SoloAI.execute_code("X", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(bool(over.get("end_scenario", false)), "la 'X' dichiara la fine")
	true_(st.solo_end_reason.contains("Convogli britannici"),
		"il motivo cita i Convogli: %s" % st.solo_end_reason)


func test_b1_procedures_are_transcribed() -> void:
	_begin("B1: le 22 procedure sono trascritte")
	var o := SoloOpponent.load_for("B1 Operazione Berlino")
	var placeholders := 0
	var total := 0
	for tid in ["fueling", "british_actions", "identify", "escort"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(total, 22, "le procedure trascritte sono ventidue")
	eq(placeholders, 0, "e nessuna e' rimasta un segnaposto")
	# Il risultato a. di B1 manda a NARVIK, non in South America come in BL1:
	# le due Tabelle del Rifornimento si somigliano ma non coincidono.
	var fueling: SoloTable = o.table("fueling")
	true_(String(fueling.legend.get("a", "")).contains("NARVIK"),
		"il Nuovo Obiettivo di B1 e' Narvik, non South America")
	true_(String(o.table("british_actions").legend.get("E", "")).contains("LO SCENARIO FINISCE"),
		"la 'E' dichiara la propria condizione di fine")


## B3, AC Solo scenarios 2022 pp.49-53. Come N6, B3 non aveva nessuna policy
## propria e cadeva nel ripiego generico, quindi la condizione di fine stampata
## dentro il risultato 'X' non veniva mai verificata.
func test_solo_ai_b3_intercept_end_conditions() -> void:
	_begin("AI solitaria B3: le due fini del risultato X")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("B3 Operazione Reno")
	var st := GameState.new(graph, 3)
	st.apply_dict(scenario.to_state_dict())
	SoloAI.execute_code("X", st, graph, engine, scenario.port_control(),
		TaskForce.Side.ROYAL_NAVY)
	false_(st.solo_ended, "all'inizio la 'X' non chiude niente")

	# Tre Convogli Completati.
	for i in 3:
		st.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	var by_convoys := SoloAI.execute_code("X", st, graph, engine,
		scenario.port_control(), TaskForce.Side.ROYAL_NAVY)
	true_(bool(by_convoys.get("end_scenario", false)),
		"tre Convogli Completati chiudono lo scenario")
	true_(st.solo_end_reason.contains("Convogli"),
		"e il motivo li cita: %s" % st.solo_end_reason)

	# La Bismarck affondata chiude lo scenario per l'altra via stampata.
	var st2 := GameState.new(graph, 4)
	st2.apply_dict(scenario.to_state_dict())
	st2.casualties.append({"side": TaskForce.Side.KRIEGSMARINE,
		"ships": ["Bismarck"], "convoys": 0})
	var by_bismarck := SoloAI.execute_code("X", st2, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	true_(bool(by_bismarck.get("end_scenario", false)),
		"la Bismarck perduta chiude lo scenario")
	true_(st2.solo_end_reason.contains("Bismarck"),
		"e il motivo la nomina: %s" % st2.solo_end_reason)


## La colonna 3 della tabella di Identificazione di B3 stampa CV/CA/CA, tre
## navi. Il dato ne aveva due: una TF non identificata entrava in Battaglia con
## un incrociatore in meno.
func test_b3_identify_third_column_has_three_ships() -> void:
	_begin("B3: la colonna 3 dell'Identificazione stampa tre navi")
	var o := SoloOpponent.load_for("B3 Operazione Reno")
	var t: SoloTable = o.table("identify")
	ne(t, null, "la tabella di Identificazione esiste")
	eq(String(t.read(0, 3)["code"]), "CV/CA/CA",
		"con 3 la TF ha una CV e DUE CA, non una sola")
	eq(String(t.read(0, 1)["code"]), "BB/CA/CA", "con 1 una BB e due CA")
	eq(String(t.read(0, 4)["code"]), "CA/CA/CA", "con 4 tre CA")
	eq(String(t.read(0, 5)["code"]), "CA/CA", "con 5 due CA")
	eq(String(t.read(0, 6)["code"]), "CA", "con 6 un CA solo")
	# Il fascicolo stampa i limiti di classe accanto alla tabella: vanno
	# conservati nel dato, perche' cambiano il risultato quando si e' al limite.
	true_(String(t.note).contains("3 BC, 7 BB, 10 CA, 6 CL, 3 CV"),
		"i limiti massimi di classe restano nel dato")


func test_b3_procedures_are_transcribed() -> void:
	_begin("B3: le 24 procedure sono trascritte")
	var o := SoloOpponent.load_for("B3 Operazione Reno")
	var placeholders := 0
	var total := 0
	for tid in ["fueling", "british_actions", "identify", "x_choice"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(total, 24, "le procedure trascritte sono ventiquattro")
	eq(placeholders, 0, "e nessuna e' rimasta un segnaposto")
	true_(String(o.table("british_actions").legend.get("X", "")).contains("LO SCENARIO FINISCE"),
		"la 'X' dichiara la propria condizione di fine")
	# B3 obbliga ad almeno un Controllo Rifornimento, cosa che BL1 e B1 non
	# fanno: e' scritto in cima alla pagina della tabella.
	true_(String(o.table("fueling").note).contains("almeno un Controllo"),
		"la nota ricorda l'obbligo di almeno un Controllo Rifornimento")


## B2, AC Solo scenarios 2022 pp.45-48. La Tabella delle Azioni Tedesche e il
## suo modificatore coincidevano gia'; a mancare erano le 10 procedure e, cosa
## piu' grave, meta' dello schieramento.
func test_b2_reinforcement_groups_match_the_printed_display() -> void:
	_begin("B2: i Gruppi di Rinforzo letti dal Display stampato")
	var sc := Scenario.load_by_id("B2 La Battaglia dell'Atlantico")
	var groups := sc.reinforcements
	# Il Gruppo A mancava del tutto: e' quello che porta il TERZO Convoglio,
	# senza il quale la fine stampata - tre Convogli Completati - non poteva
	# avverarsi, perche' in gioco ce ne sono due.
	true_(groups.has("RN Reinforcement A"),
		"il Gruppo A esiste: e' il terzo Convoglio")
	var a: Array = groups.get("RN Reinforcement A", [])
	true_(a.has("Convoy x3"), "il Gruppo A contiene un Convoglio")
	true_(a.has("Ramilles"), "e la Ramilles, come sul Display di p.46")
	var b: Array = groups.get("RN Reinforcement B", [])
	eq(b.size(), 3, "il Gruppo B ha tre navi")
	for ship_name in ["Renown", "Sheffield", "Ark Royal"]:
		true_(b.has(ship_name), "il Gruppo B contiene %s" % ship_name)
	# Senza porto trascritto un Gruppo non entra: il motore dichiara il buco
	# invece di scegliere un porto a caso.
	var ports := sc.reinforcement_ports()
	eq(String(ports.get("RN Reinforcement A", "")), "New York",
		"il Gruppo A e' a New York")
	eq(String(ports.get("RN Reinforcement B", "")), "Gibilterra",
		"il Gruppo B e' a Gibilterra")
	eq(String(sc.reinforcement_leaders().get("RN Reinforcement B", "")),
		"Somerville", "Somerville entra col Gruppo B")


## La condizione di fine di B2 chiede tre Convogli Completati e lo scenario ne
## schiera due: il terzo deve arrivare da un Gruppo di Rinforzo, o la partita
## non finisce. Il replay lo dimostra invece di darlo per scontato.
func test_b2_replay_reaches_three_convoys() -> void:
	_begin("B2: il replay arriva ai tre Convogli")
	var runner := SoloRunner.new()
	true_(runner.load_scenario("B2 La Battaglia dell'Atlantico", 20260803),
		"B2 caricato: %s" % runner.load_error)
	var out := runner.run()
	true_(bool(out.get("ended", false)),
		"il replay di B2 si chiude per una condizione stampata")
	true_(String(out.get("reason", "")).contains("Convogli"),
		"e la condizione e' quella dei tre Convogli: %s" % String(out.get("reason", "")))
	true_(runner.state.convoys_completed >= 3,
		"tre Convogli hanno davvero Completato")


func test_b2_procedures_are_transcribed() -> void:
	_begin("B2: le 10 procedure sono trascritte")
	var o := SoloOpponent.load_for("B2 La Battaglia dell'Atlantico")
	var placeholders := 0
	var total := 0
	for tid in ["actions", "identify"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(total, 10, "le procedure trascritte sono dieci")
	eq(placeholders, 0, "e nessuna e' rimasta un segnaposto")
	var actions: SoloTable = o.table("actions")
	# I quattro suffissi della X scelgono TF diverse: e' la meta' della
	# procedura che un riassunto perderebbe.
	for code in ["XBC", "XCA", "XPB", "XU"]:
		ne(String(actions.legend.get(code, "")), "",
			"il suffisso '%s' della X e' trascritto" % code)
	eq(actions.modifier_total(["nessun Convoglio ha Completato"]), 1,
		"il modificatore stampato vale +1")


## B4, AC Solo scenarios 2022 pp.54-57. Stessa lacuna di B2: la fine stampata
## chiede tre Convogli Completati e lo scenario ne schiera due, quindi il terzo
## deve arrivare da un Gruppo di Rinforzo - che nei dati non c'era.
func test_b4_reinforcement_groups_match_the_printed_display() -> void:
	_begin("B4: i tre Gruppi di Rinforzo del Display stampato")
	var sc := Scenario.load_by_id("B4 Decisione sui Mari")
	var groups := sc.reinforcements
	for name in ["RN Reinforcement A", "RN Reinforcement B", "RN Reinforcement C"]:
		true_(groups.has(name), "il Gruppo %s esiste" % name.right(1))
	true_((groups.get("RN Reinforcement A", []) as Array).has("Convoy x3"),
		"il Gruppo A e' il terzo Convoglio")
	var b: Array = groups.get("RN Reinforcement B", [])
	for ship_name in ["Renown", "Ark Royal", "Sheffield"]:
		true_(b.has(ship_name), "il Gruppo B contiene %s" % ship_name)
	true_((groups.get("RN Reinforcement C", []) as Array).has("Victorious"),
		"il Gruppo C e' la Victorious")
	var ports := sc.reinforcement_ports()
	eq(String(ports.get("RN Reinforcement A", "")), "St. John's",
		"il Gruppo A e' a St. John's")
	eq(String(ports.get("RN Reinforcement B", "")), "Gibilterra",
		"il Gruppo B e' a Gibilterra")
	eq(String(ports.get("RN Reinforcement C", "")), "Scapa Flow",
		"il Gruppo C e' a Scapa Flow")


func test_b4_replay_reaches_three_convoys() -> void:
	_begin("B4: il replay arriva ai tre Convogli")
	var runner := SoloRunner.new()
	true_(runner.load_scenario("B4 Decisione sui Mari", 20260803),
		"B4 caricato: %s" % runner.load_error)
	var out := runner.run()
	true_(bool(out.get("ended", false)),
		"il replay di B4 si chiude per una condizione stampata")
	true_(String(out.get("reason", "")).contains("Convogli"),
		"e la condizione e' quella dei tre Convogli")
	true_(runner.state.convoys_completed >= 3,
		"tre Convogli hanno davvero Completato")


func test_b4_procedures_are_transcribed() -> void:
	_begin("B4: le 12 procedure sono trascritte")
	var o := SoloOpponent.load_for("B4 Decisione sui Mari")
	var placeholders := 0
	var total := 0
	for tid in ["actions", "identify"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(total, 12, "le procedure trascritte sono dodici")
	eq(placeholders, 0, "e nessuna e' rimasta un segnaposto")
	var actions: SoloTable = o.table("actions")
	# I suffissi di B4 non sono quelli di B2: qui c'e' 'Xa', la TF piu' vicina,
	# che in B2 non esiste, e non c'e' 'XCA'.
	for code in ["Xa", "XBB", "XBC", "Xu"]:
		ne(String(actions.legend.get(code, "")), "",
			"il suffisso '%s' della X e' trascritto" % code)
	true_(String(actions.legend.get("XBC", "")).contains("Brest"),
		"la 'XBC' di B4 crea la nuova TF a Brest")
	true_(String(actions.legend.get("Xu", "")).contains("Narvik"),
		"la 'Xu' tira dove creare la TF non identificata")


## A1, AC Solo scenarios 2022 pp.59-62. Il suo Gruppo di Rinforzo A non ha un
## porto FISSO: partenza e destinazione si tirano sul dado. E' l'unico scenario
## in cui succede, e per questo il Gruppo non compariva in reinforcement_ports.
func test_a1_reinforcement_group_a_rolls_its_route() -> void:
	_begin("A1: la rotta del Gruppo A si tira")
	var sc := Scenario.load_by_id("A1 Convogli PQ")
	var routes := sc.reinforcement_routes()
	true_(routes.has("RN Reinforcement A"),
		"il Gruppo A ha una rotta da tirare invece di un porto fisso")
	var table: Array = routes.get("RN Reinforcement A", [])
	eq(table.size(), 3, "la tabella stampata ha tre righe")
	eq(String((table[0] as Dictionary).get("to", "")), "Murmansk",
		"con 1-2 si va a Murmansk")
	eq(String((table[2] as Dictionary).get("to", "")), "Archangel",
		"con 6 si va ad Archangel")
	eq(String((table[2] as Dictionary).get("from", "")), "Hvalfjordur",
		"e si parte da Hvalfiord")
	# Il Gruppo B ha invece un porto fisso, e costa -3 VP.
	eq(String(sc.reinforcement_ports().get("RN Reinforcement B", "")), "Gibilterra",
		"il Gruppo B parte da Gibilterra")
	false_(sc.reinforcement_ports().has("RN Reinforcement A"),
		"il Gruppo A non ha - e non deve avere - un porto fisso")


## p.62: "End? If a German BB has Completed or was sunk, the scenario ends."
func test_solo_ai_a1_intercept_ends_when_a_german_bb_is_gone() -> void:
	_begin("A1: una BB tedesca perduta chiude lo scenario")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("A1 Convogli PQ")
	var st := GameState.new(graph, 5)
	st.apply_dict(scenario.to_state_dict())
	SoloAI.execute_code("X", st, graph, engine, scenario.port_control(),
		TaskForce.Side.KRIEGSMARINE)
	false_(st.solo_ended, "senza perdite la 'X' non chiude niente")
	st.casualties.append({"side": TaskForce.Side.KRIEGSMARINE,
		"ships": ["Tirpitz"], "convoys": 0})
	var over := SoloAI.execute_code("X", st, graph, engine,
		scenario.port_control(), TaskForce.Side.KRIEGSMARINE)
	true_(bool(over.get("end_scenario", false)), "la 'X' dichiara la fine")
	true_(st.solo_end_reason.contains("BB"),
		"e il motivo cita la corazzata: %s" % st.solo_end_reason)


func test_a1_replay_reaches_three_convoys() -> void:
	_begin("A1: il replay arriva ai tre Convogli")
	var runner := SoloRunner.new()
	true_(runner.load_scenario("A1 Convogli PQ", 20260803),
		"A1 caricato: %s" % runner.load_error)
	var out := runner.run()
	true_(bool(out.get("ended", false)),
		"il replay di A1 si chiude per una condizione stampata")
	true_(runner.state.convoys_completed >= 3,
		"tre Convogli hanno davvero Completato")


## B-Dienst (BL1 p.5) e Bletchley Park (A1 p.59) sono la STESSA facolta' con le
## parti scambiate: un segnalino Informazioni su una Traiettoria avversaria,
## quando la propria parte ha l'Iniziativa, una volta sola per scenario. Erano
## due regole da scrivere due volte; ora la parte variabile sta nel dato.
func test_intel_marker_once_works_for_both_sides() -> void:
	_begin("Segnalino Informazioni una volta per scenario, per entrambe le parti")
	for spec_v: Variant in [
			["BL1 Raiders of the North Atlantic", TaskForce.Side.KRIEGSMARINE, "B-Dienst"],
			["A1 Convogli PQ", TaskForce.Side.ROYAL_NAVY, "Bletchley Park"]]:
		var spec: Array = spec_v
		var scenario := Scenario.load_by_id(String(spec[0]))
		var owner := int(spec[1])
		var declared := scenario.intel_marker_once()
		false_(declared.is_empty(), "%s dichiara la facolta'" % String(spec[0]))
		var st := GameState.new(graph, 11)
		st.scenario_name = String(spec[0])
		st.solo_intel_marker_once = declared
		eq(SoloAI.intel_marker_label(st), String(spec[2]),
			"%s: il nome stampato e' quello del fascicolo" % String(spec[0]))
		eq(SoloAI.intel_marker_side(st), owner,
			"%s: la facolta' e' della parte giusta" % String(spec[0]))
		# Con l'Iniziativa avversaria non e' disponibile.
		st.initiative = 1 - owner
		false_(SoloAI.intel_marker_available(st),
			"%s: serve l'Iniziativa della propria parte" % String(spec[0]))
		st.initiative = owner
		true_(SoloAI.intel_marker_available(st),
			"%s: con l'Iniziativa giusta e' disponibile" % String(spec[0]))
		# Una Traiettoria AVVERSARIA e' il bersaglio; una propria non lo e'.
		var enemy := TaskForce.new(1, 1 - owner)
		enemy.trajectory.become_station(Vector2i(15, -3))
		_extend_one_segment(enemy, st)
		st.add_task_force(enemy)
		var own := TaskForce.new(2, owner)
		own.trajectory.become_station(Vector2i(13, -2))
		_extend_one_segment(own, st)
		st.add_task_force(own)
		eq(SoloAI.intel_marker_targets(st).size(), 1,
			"%s: solo la Traiettoria avversaria e' un bersaglio" % String(spec[0]))
		var target_hex: Vector2i = (enemy.trajectory.segments[0] as Dictionary)["hex"]
		var applied := SoloAI.intel_marker_apply(st, enemy, target_hex)
		true_(bool(applied["ok"]), "%s: il segnalino viene attaccato" % String(spec[0]))
		eq(enemy.info_count(), 1, "%s: la Traiettoria ha un segnalino" % String(spec[0]))
		false_(SoloAI.intel_marker_available(st),
			"%s: e vale una volta sola" % String(spec[0]))


func _extend_one_segment(tf: TaskForce, st: GameState) -> void:
	var from := tf.trajectory.station_hex
	for h in graph.adjacent_hexes(from):
		if tf.trajectory.extend(h, 1, graph, st.port_hexes(), false, tf.side):
			return


# ------------------------------------------------------------------------ N3 --
#
# N3 Operazione Weser (sud), fascicolo pp.25-27 lette sulle pagine renderizzate.
# Il giocatore e' il TEDESCO; la Tabella e' quella britannica. Le sei procedure
# girano attorno al Sommergibile britannico, ed erano tutte approssimate: la
# 'SA' in particolare finiva su un Attacco Furtivo dichiarato da una Task
# Force, che RB p.41 non ammette.


func _n3_state(seed: int) -> GameState:
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var g := MapGraph.load_inset("map_north_sea")
	var st := GameState.new(g, seed)
	st.apply_dict(scenario.to_state_dict())
	st.solo_end_conditions = scenario.end_conditions()
	return st


func test_n3_procedures_are_transcribed() -> void:
	_begin("N3: le undici procedure sono trascritte")
	var o := SoloOpponent.load_for("N3 Operazione Weser (sud)")
	var placeholders := 0
	var total := 0
	for tid in ["actions", "identify"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(total, 11, "le procedure trascritte sono undici")
	eq(placeholders, 0, "e nessuna e' rimasta un segnaposto")
	# La fine stampata DENTRO la 'C', che non sta nel riquadro "The End".
	var actions: SoloTable = o.table("actions")
	true_(String(actions.legend.get("C", "")).contains("LO SCENARIO FINISCE"),
		"la 'C' dichiara la propria condizione di fine")
	# Il refuso delle colonne della tabella di Identificazione resta dichiarato.
	var identify: SoloTable = o.table("identify")
	true_(identify.note.contains("REFUSO DEL FASCICOLO"),
		"il refuso delle colonne '1 | 2 | 4 | 5 | 5-6' e' dichiarato, non nascosto")


## La colonna 5 della prima riga stampa il simbolo dell'occhio, cioe' CONTATTO.
## Nel dato era una cella VUOTA, e un codice vuoto non arriva a nessuna
## procedura: quel risultato non si e' mai potuto verificare.
func test_n3_contact_cell_is_not_empty() -> void:
	_begin("N3: la cella dell'occhio e' il risultato CONTATTO, non una cella vuota")
	var o := SoloOpponent.load_for("N3 Operazione Weser (sud)")
	var t: SoloTable = o.table("actions")
	var first: Dictionary = t.rows[0]
	eq(String((first["cells"] as Array)[4]), "CONTATTO",
		"riga '0 Completamenti', colonna 5: il risultato e' CONTATTO")
	true_(t.legend.has("CONTATTO"), "e la procedura corrispondente esiste")


## "Each German TF in Bergen and Kristiansand gets a Contact marker attached
## (attach to station or segment in the port hex). Then: IC. If a German TF
## already has a Contact marker attached: IC." (p.26)
func test_n3_contact_marks_bergen_and_kristiansand() -> void:
	_begin("N3 CONTATTO: i segnalini vanno in Bergen e Kristiansand")
	var st := _n3_state(11)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY
	var bergen := g.place_hex("Bergen")
	var kristiansand := g.place_hex("Kristiansand")
	ne(bergen, Vector2i.MAX, "Bergen e' un porto dell'inserto")
	ne(kristiansand, Vector2i.MAX,
		"Kristiansand e' un Punto di Interesse, e il suo esagono si trova lo stesso")

	var marked := 0
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		if tf.trajectory.occupies(bergen) or tf.trajectory.occupies(kristiansand):
			marked += 1
	true_(marked > 0, "lo schieramento mette almeno una TF tedesca nei due esagoni")

	var out := SoloAI.execute_code("CONTATTO", st, g, engine,
		scenario.port_control(), uk)
	true_(bool(out.get("ok", false)), "il risultato applica qualcosa")
	var with_contact := 0
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		if tf.trajectory.has_contact_at(bergen) \
				or tf.trajectory.has_contact_at(kristiansand):
			with_contact += 1
	eq(with_contact, marked, "ogni TF tedesca nei due esagoni ha ora il Contatto")
	eq(int(st.solo_counters.get("n3_international_incidents", 0)), 1,
		"e il risultato porta un Incidente Internazionale")

	# Ripetuto, ogni TF che ne aveva gia' uno ne aggiunge un altro.
	SoloAI.execute_code("CONTATTO", st, g, engine, scenario.port_control(), uk)
	eq(int(st.solo_counters.get("n3_international_incidents", 0)), 2 + marked,
		"la seconda volta l'Incidente e' quello del risultato piu' uno per "
		+ "ciascuna TF che aveva gia' il Contatto")


## "Place the Submarine stealth force in a hex with a German TF... If more than
## one option for placement, choose the hex nearest Bergen." (p.26)
func test_n3_stealth_recon_places_the_submarine_nearest_bergen() -> void:
	_begin("N3 SR: il Sommergibile si piazza nell'esagono piu' vicino a Bergen")
	var st := _n3_state(12)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY
	var bergen := g.place_hex("Bergen")

	# Lo schieramento di p.25 mette il Sommergibile britannico in (6,-1).
	var subs := Stealth.forces_of(st, uk)
	eq(subs.size(), 1, "lo scenario schiera una forza Furtiva britannica")
	eq(int(subs[0].get("kind", -1)), Stealth.Kind.SUBMARINE, "ed e' un Sommergibile")
	eq(Vector2i(int(subs[0]["q"]), int(subs[0]["r"])), Vector2i(6, -1),
		"nell'esagono di Kristiansand, misurato sull'illustrazione")

	var out := SoloAI.execute_code("SR", st, g, engine, scenario.port_control(), uk)
	true_(bool(out.get("ok", false)), "la Ricognizione si esegue")
	var after := Stealth.forces_of(st, uk)[0]
	var landed := Vector2i(int(after["q"]), int(after["r"]))
	# Deve essere finito su una TF tedesca, e fra quelle la piu' vicina a Bergen.
	var best := 1 << 30
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		for h in tf.trajectory.hexes():
			best = mini(best, Hex.distance(h, bergen))
	eq(Hex.distance(landed, bergen), best,
		"e finisce nell'esagono tedesco piu' vicino a Bergen")


## "If the Sub force is already in Bergen, treat as CONTACT instead." (p.26)
func test_n3_stealth_recon_in_bergen_becomes_contact() -> void:
	_begin("N3 SR: col Sommergibile gia' in Bergen il risultato diventa CONTATTO")
	var st := _n3_state(13)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY
	var bergen := g.place_hex("Bergen")
	var force := Stealth.forces_of(st, uk)[0]
	force["q"] = bergen.x
	force["r"] = bergen.y

	var out := SoloAI.execute_code("SR", st, g, engine, scenario.port_control(), uk)
	true_(_solo_ai_log_contains(out, "vale come CONTATTO"),
		"il rimando stampato e' applicato e dichiarato")
	true_(int(st.solo_counters.get("n3_international_incidents", 0)) >= 1,
		"e con lui arriva l'Incidente Internazionale del CONTATTO")


## "Select the British Submarine stealth force. If not in play, treat as 'SR'
## result instead." + "gets a +3 modifier on the Stealth Attack Table" (p.26)
func test_n3_stealth_attack_uses_the_submarine_with_the_printed_bonus() -> void:
	_begin("N3 SA: attacca il Sommergibile, col +3 stampato")
	var st := _n3_state(14)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY
	var force := Stealth.forces_of(st, uk)[0]
	var h := Vector2i(int(force["q"]), int(force["r"]))

	# Il segmento tedesco in Kristiansand ha il segnalino Informazioni previsto
	# dalla pagina, quindi e' un bersaglio legale (RB p.41).
	var targets := Stealth.targets_for(st, force)
	true_(targets.size() > 0,
		"il Sommergibile ha un bersaglio: il segmento con le Informazioni di p.25")

	var out := SoloAI.execute_code("SA", st, g, engine, scenario.port_control(), uk)
	eq(String(out.get("action_key", "")), "STEALTH_ATTACK", "dichiara l'Attacco Furtivo")
	true_(out.get("active", null) == null,
		"e non ha nessuna TF Attiva: l'attaccante e' la forza Furtiva")
	eq(int(out.get("modifier", 0)), 3, "col +3 stampato dalla procedura")
	eq(Vector2i(int((out["active_stealth"] as Dictionary)["q"]),
		int((out["active_stealth"] as Dictionary)["r"])), h,
		"e la forza designata e' proprio il Sommergibile")
	true_(bool(out.get("stealth_removed_after", false)),
		"dopo l'attacco il segnalino lascia il gioco, come prescritto")

	# La dichiarazione che ne esce dev'essere legale per il motore.
	var dec := SoloSequence.declaration_for(out)
	ne(dec, null, "la dichiarazione si costruisce")
	eq(engine.legality_error(dec, st), "", "ed e' legale")
	eq(dec.modifier, 3, "col modificatore che arriva fino al tiro")


## "If not in play, treat as 'SR' result instead." e "If it does not have a
## target in its hex... treat as 'SR' result instead." (p.26)
func test_n3_stealth_attack_falls_back_to_recon() -> void:
	_begin("N3 SA: senza Sommergibile o senza bersaglio diventa 'SR'")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY

	var st := _n3_state(15)
	st.stealth_forces.clear()
	var out := SoloAI.execute_code("SA", st, st.graph, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(out, "non e' in gioco, quindi il risultato vale come 'SR'"),
		"senza Sommergibile in gioco si applica la 'SR'")
	eq(Stealth.forces_of(st, uk).size(), 1,
		"e la 'SR' lo rimette in gioco, che e' la strada stampata per farlo tornare")

	# Senza bersaglio: si sposta il Sommergibile in un esagono vuoto.
	var st2 := _n3_state(16)
	var force: Dictionary = Stealth.forces_of(st2, uk)[0]
	force["q"] = 1
	force["r"] = 0
	eq(Stealth.targets_for(st2, force).size(), 0, "li' non ha bersagli")
	var out2 := SoloAI.execute_code("SA", st2, st2.graph, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(out2, "non ha bersagli nel suo esagono"),
		"e il rimando alla 'SR' e' dichiarato col motivo stampato")


## "targeting a German TF nearest to the Submarine force (if the Submarine
## force is not on the map, nearest to Bergen instead)" e "Time Lapse: Remove
## segments nearest to Scapa Flow." (p.26)
func test_n3_bring_on_battle_measures_from_the_submarine() -> void:
	_begin("N3 X: il bersaglio si misura dal Sommergibile, non dalla TF che attacca")
	var st := _n3_state(17)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY

	var out := SoloAI.execute_code("X", st, g, engine, scenario.port_control(), uk)
	true_(_solo_ai_log_contains(out, "il Sommergibile in"),
		"col Sommergibile sulla mappa, la distanza si misura da lui")
	eq(out.get("time_lapse_goal", Vector2i.MAX), g.place_hex("Scapa Flow"),
		"e lo Scorrere del Tempo guarda Scapa Flow")
	true_(bool(out.get("time_lapse_prefer_near", false)),
		"togliendo i segmenti piu' VICINI, che e' la frase al contrario di tutte le altre")

	# Senza Sommergibile la procedura misura da Bergen.
	var st2 := _n3_state(18)
	st2.stealth_forces.clear()
	var out2 := SoloAI.execute_code("X", st2, st2.graph, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(out2, "Bergen, perche' il Sommergibile non e' sulla mappa"),
		"senza Sommergibile si misura da Bergen, come stampato")


## 'B' passo 2 (p.26): dopo la Traiettoria la procedura NON puo' tracciarne
## un'altra. E' la trappola gia' pagata su BL2, dove la stessa TF disegnava due
## rotte consecutive.
func test_n3_trajectory_to_bergen_has_a_second_step() -> void:
	_begin("N3 B: il passo 2 continua la procedura senza una seconda Traiettoria")
	var st := _n3_state(19)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY

	var out := SoloAI.execute_code("B", st, g, engine, scenario.port_control(), uk)
	# Senza TF britanniche in gioco ne entra una non identificata a Methil.
	true_(_solo_ai_log_contains(out, "Methil"),
		"senza TF britanniche ne entra una non identificata a Methil")
	eq(String((out.get("follow_up", {}) as Dictionary).get("kind", "")), "n3_b_step2",
		"e la procedura prescrive il proprio passo 2")

	var next := SoloAI.continue_follow_up(out, st, g, engine,
		scenario.port_control(), uk)
	ne(String(next.get("turn_kind", "")), "trajectory",
		"il passo 2 non e' una seconda azione Traiettoria")


## "if the selected TF has a Convoy or damaged ship, replace Convoy/damaged
## ship with a CA" (p.26). E' una sostituzione vera: se restasse una nota, il
## Convoglio finirebbe in Battaglia proprio dove la procedura dice che non c'e'.
func test_n3_convoy_is_replaced_by_a_cruiser_before_battle() -> void:
	_begin("N3 B: il Convoglio esce dalla TF e al suo posto entra un CA")
	var st := _n3_state(20)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N3 Operazione Weser (sud)")
	var uk := TaskForce.Side.ROYAL_NAVY
	var german := st.forces_of(TaskForce.Side.KRIEGSMARINE)[0]
	var h := german.trajectory.end_hex(0)

	# Una TF britannica con un Convoglio, nello stesso esagono di una tedesca.
	var tf := TaskForce.new(90, uk)
	tf.ships.append(ShipRoster.shared().make("Convoy x3"))
	tf.trajectory.become_station(h)
	st.add_task_force(tf)
	true_(tf.ships.any(func(s: Ship) -> bool: return s.kind == Ship.Kind.CONVOY),
		"la TF parte con un Convoglio")

	SoloAI.continue_follow_up({"follow_up": {"kind": "n3_b_step2"}, "active": tf},
		st, g, engine, scenario.port_control(), uk)
	false_(tf.ships.any(func(s: Ship) -> bool: return s.kind == Ship.Kind.CONVOY),
		"dopo il passo 2 il Convoglio non c'e' piu'")
	true_(tf.ships.any(func(s: Ship) -> bool: return s.type_code == "CA"),
		"e al suo posto c'e' un CA, come stampato")


# ------------------------------------------------------------------------ N5 --
#
# N5 Meglio Tardi che Mai, fascicolo pp.32-35 lette sulle pagine renderizzate.
# Il giocatore e' il BRITANNICO; la Tabella e' quella tedesca. Prima N5 non
# aveva nessuna policy propria e cadeva nel ripiego generico in fondo a
# `execute_code`: la 'A' non piazzava nessuna Base Aerea, la 'Conv' non tirava
# per il porto norvegese, e la fine stampata dentro la 'X' non scattava mai.


func _n5_state(seed: int) -> GameState:
	var scenario := Scenario.load_by_id("N5 Meglio Tardi che Mai")
	var g := MapGraph.load_inset("map_norwegian_sea")
	var st := GameState.new(g, seed)
	st.apply_dict(scenario.to_state_dict())
	st.solo_end_conditions = scenario.end_conditions()
	return st


func test_n5_procedures_are_transcribed() -> void:
	_begin("N5: le dieci procedure sono trascritte")
	var o := SoloOpponent.load_for("N5 Meglio Tardi che Mai")
	var placeholders := 0
	var total := 0
	for tid in ["actions", "identify"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			total += 1
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(placeholders, 0, "nessuna e' rimasta un segnaposto")
	eq(total, 10, "sono dieci voci: quattro azioni e sei composizioni")
	var actions: SoloTable = o.table("actions")
	true_(String(actions.legend.get("X", "")).contains("LO SCENARIO FINISCE"),
		"la 'X' dichiara la propria condizione di fine")
	true_(String(actions.legend.get("A", "")).contains("REFUSO DEL FASCICOLO"),
		"e il refuso della 'A' - 'roll again on the British Action Table' in uno "
		+ "scenario che non ne ha una - resta dichiarato")


## p.34, riga '1', colonna 4: la pagina stampa CL/CL, cioe' DUE incrociatori
## leggeri. Il dato ne aveva uno solo, quindi una TF tedesca non identificata
## entrava in Battaglia con un incrociatore in meno. Stessa classe di difetto
## della colonna 3 di B3.
func test_n5_identify_fourth_column_has_two_light_cruisers() -> void:
	_begin("N5: la colonna 4 della riga '1' stampa due CL, non uno")
	var o := SoloOpponent.load_for("N5 Meglio Tardi che Mai")
	var t: SoloTable = o.table("identify")
	eq(String((t.rows[1]["cells"] as Array)[3]), "CL/CL",
		"riga '1 Completamento', colonna 4: CL/CL")
	eq(String((t.rows[2]["cells"] as Array)[3]), "CL/CL",
		"e la riga '2+' la stampa uguale")
	true_(t.legend.has("CL/CL"), "la composizione corrispondente e' trascritta")
	false_(t.legend.has("CL"), "e il vecchio 'CL' singolo non c'e' piu'")


## 'A' col Meteo Cattivo (p.33): "Place a German Airbase marker in Trondheim.
## If one is already there, place one in Narvik."
func test_n5_air_strike_places_air_base_markers() -> void:
	_begin("N5 A: col Meteo Cattivo si posano i marcatori Base Aerea")
	var st := _n5_state(31)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N5 Meglio Tardi che Mai")
	var ge := TaskForce.Side.KRIEGSMARINE
	st.weather = TimeLapse.Weather.BAD
	eq(AirBase.count_of(st, ge), 0, "si parte senza marcatori piazzati")

	SoloAI.execute_code("A", st, g, engine, scenario.port_control(), ge)
	true_(AirBase.at(st, g.place_hex("Trondheim"), ge),
		"il primo marcatore va a Trondheim")
	eq(AirBase.count_of(st, ge), 1, "ed e' uno solo")

	SoloAI.execute_code("A", st, g, engine, scenario.port_control(), ge)
	true_(AirBase.at(st, g.place_hex("Narvik"), ge),
		"il secondo va a Narvik, perche' Trondheim e' occupata")
	eq(AirBase.count_of(st, ge), 2, "e adesso sono due")

	# RB p.21: una Base Aerea nemica innesca Informazioni nel suo esagono.
	true_(st.triggers_info(g.place_hex("Trondheim"), TaskForce.Side.ROYAL_NAVY),
		"un marcatore nemico innesca Informazioni, come i porti nemici")
	true_(st.info_reasons(g.place_hex("Trondheim"),
		TaskForce.Side.ROYAL_NAVY).any(func(x: String) -> bool:
			return x.contains("Base Aerea")),
		"e il motivo lo dice")


## "However, if a British Airbase marker is in the placement hex, remove the
## British marker and do not place a German marker there." (p.33)
func test_n5_air_strike_removes_a_british_marker_instead() -> void:
	_begin("N5 A: su un marcatore britannico si toglie quello, non se ne posa uno")
	var st := _n5_state(32)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N5 Meglio Tardi che Mai")
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	st.weather = TimeLapse.Weather.BAD
	AirBase.place(st, uk, g.place_hex("Trondheim"), "marcatore britannico di prova")

	SoloAI.execute_code("A", st, g, engine, scenario.port_control(), ge)
	false_(AirBase.at(st, g.place_hex("Trondheim"), uk),
		"il marcatore britannico e' stato tolto")
	false_(AirBase.at(st, g.place_hex("Trondheim"), ge),
		"e al suo posto NON e' entrato uno tedesco")


## 'Convoglio' (p.33): il porto lo sceglie un dado, con un modificatore che
## dipende dai Completamenti britannici gia' avvenuti.
func test_n5_convoy_rolls_for_its_norwegian_port() -> void:
	_begin("N5 Convoglio: 0-3 Trondheim, 4-6 Narvik, con il -1 stampato")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N5 Meglio Tardi che Mai")
	var ge := TaskForce.Side.KRIEGSMARINE

	var st := _n5_state(33)
	st.rng.push_forced([5])
	var narvik := SoloAI.execute_code("CONV", st, st.graph, engine,
		scenario.port_control(), ge)
	true_(_solo_ai_log_contains(narvik, "il porto e' Narvik"),
		"un 5 senza modificatori manda a Narvik")

	var st2 := _n5_state(34)
	st2.rng.push_forced([3])
	var trondheim := SoloAI.execute_code("CONV", st2, st2.graph, engine,
		scenario.port_control(), ge)
	true_(_solo_ai_log_contains(trondheim, "il porto e' Trondheim"),
		"un 3 manda a Trondheim")

	# Col -1 stampato, un 4 scende a 3 e cambia porto. Lo sbarco britannico
	# accanto a Trondheim e' la traccia che il motore ora conserva.
	var st3 := _n5_state(35)
	st3.solo_counters["norway_landings"] = [{
		"side": TaskForce.Side.ROYAL_NAVY,
		"q": st3.graph.place_hex("Trondheim").x,
		"r": st3.graph.place_hex("Trondheim").y,
	}]
	st3.rng.push_forced([4])
	var shifted := SoloAI.execute_code("CONV", st3, st3.graph, engine,
		scenario.port_control(), ge)
	true_(_solo_ai_log_contains(shifted, "-1"),
		"il modificatore stampato e' applicato")
	true_(_solo_ai_log_contains(shifted, "il porto e' Trondheim"),
		"e un 4 diventa 3, cioe' Trondheim")


## "If the only target is a Station in Scapa Flow... this action is cancelled
## and the scenario ends." (p.33) E' una fine stampata DENTRO la Tabella.
func test_n5_bring_on_battle_ends_on_scapa_flow_only() -> void:
	_begin("N5 X: col solo bersaglio a Scapa Flow lo scenario finisce")
	var st := _n5_state(36)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N5 Meglio Tardi che Mai")
	var ge := TaskForce.Side.KRIEGSMARINE
	var scapa := g.place_hex("Scapa Flow")

	# Tutte le TF britanniche diventano Stazioni a Scapa Flow, che e' anche la
	# posizione di partenza stampata ("all TFs start in Scapa Flow").
	for tf in st.forces_of(TaskForce.Side.ROYAL_NAVY):
		tf.trajectory.become_station(scapa)
	var over := SoloAI.execute_code("X", st, g, engine, scenario.port_control(), ge)
	true_(bool(over.get("end_scenario", false)), "la 'X' dichiara la fine")
	true_(st.solo_ended, "e lo stato risulta concluso")
	true_(st.solo_end_reason.contains("Scapa Flow"),
		"col motivo stampato: %s" % st.solo_end_reason)


## Lo Scorrere del Tempo della 'X' e' "nearest to Kiel", non "farthest": e' la
## frase al contrario, ed e' il caso che prima non esisteva.
func test_n5_bring_on_battle_time_lapse_is_nearest_to_kiel() -> void:
	_begin("N5 X: lo Scorrere del Tempo toglie i segmenti piu' VICINI a Kiel")
	var st := _n5_state(37)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N5 Meglio Tardi che Mai")
	var ge := TaskForce.Side.KRIEGSMARINE
	# N5 schiera TUTTE le TF britanniche a Scapa Flow ("all TFs start in Scapa
	# Flow"), e li' la 'X' finisce lo scenario per regola stampata. Per arrivare
	# al Portare in Battaglia serve una TF uscita dal porto, che e' anche la
	# situazione in cui quella clausola non si applica.
	var runner := st.forces_of(TaskForce.Side.ROYAL_NAVY)[0]
	runner.trajectory.become_station(g.place_hex("Trondheim"))
	# Un dado DISPARI evita il ramo del Denmark Strait e va al Portare in
	# Battaglia, che e' quello con lo Scorrere del Tempo prescritto.
	st.rng.push_forced([3])
	var out := SoloAI.execute_code("X", st, g, engine, scenario.port_control(), ge)
	false_(st.solo_ended,
		"con una TF britannica fuori da Scapa Flow lo scenario non finisce")
	eq(out.get("time_lapse_goal", Vector2i.MAX), g.place_hex("Kiel"),
		"l'obiettivo dello Scorrere del Tempo e' Kiel")
	true_(bool(out.get("time_lapse_prefer_near", false)),
		"e si tolgono i segmenti piu' VICINI, non i piu' lontani")


## Gli sbarchi in Norvegia lasciano una traccia, e la traccia sopravvive al
## salvataggio: piu' di una procedura stampata guarda indietro.
func test_norway_landings_survive_a_save() -> void:
	_begin("gli sbarchi in Norvegia restano nel salvataggio")
	var st := _n5_state(38)
	var uk := TaskForce.Side.ROYAL_NAVY
	var trondheim := st.graph.place_hex("Trondheim")
	eq(Norway.landings_of(st, uk).size(), 0, "si parte senza sbarchi")
	st.solo_counters["norway_landings"] = [
		{"side": uk, "q": trondheim.x, "r": trondheim.y}]
	true_(Norway.landed_in_or_next_to(st, uk, trondheim),
		"lo sbarco e' registrato nel suo esagono")
	true_(Norway.landed_in_or_next_to(st, uk,
		st.graph.adjacent_hexes(trondheim)[0]),
		"e vale anche per un esagono adiacente, come dice p.32")

	var reloaded := GameState.new(st.graph, 1)
	reloaded.apply_dict(st.to_dict())
	eq(Norway.landings_of(reloaded, uk).size(), 1,
		"e sopravvive a salvataggio e ricarica")


## I marcatori Base Aerea sono stato persistente come ogni altra pedina.
func test_placed_air_bases_survive_a_save() -> void:
	_begin("i marcatori Base Aerea entrano nel salvataggio")
	var st := _n5_state(39)
	var ge := TaskForce.Side.KRIEGSMARINE
	var h := st.graph.place_hex("Narvik")
	AirBase.place(st, ge, h, "prova")
	eq(AirBase.count_of(st, ge), 1, "il marcatore c'e'")
	var reloaded := GameState.new(st.graph, 1)
	reloaded.apply_dict(st.to_dict())
	true_(AirBase.at(reloaded, h, ge), "e c'e' ancora dopo la ricarica")
	true_(AirBase.remove_at(reloaded, h, ge), "si toglie")
	eq(AirBase.count_of(reloaded, ge), 0, "e non ne resta nessuno")


# ------------------------------------------------------------------------ N2 --
#
# N2 Operazione Weser (nord), fascicolo pp.21-24 lette sulle pagine
# renderizzate. Il giocatore e' il TEDESCO. N2 e' il gemello di N3 sull'altro
# inserto, e le sue procedure erano tutte approssimate: 'AA' e 'Bd' puntavano a
# Bergen e Trondheim, cioe' ai porti della Mappa Operazionale usati come
# sostituti quando l'inserto non era calibrato, non ad Andalsnes e Bud.


func _n2_state(seed: int) -> GameState:
	var scenario := Scenario.load_by_id("N2 Operazione Weser (nord)")
	var g := MapGraph.load_inset("map_norwegian_sea")
	var st := GameState.new(g, seed)
	st.apply_dict(scenario.to_state_dict())
	st.solo_end_conditions = scenario.end_conditions()
	return st


func test_n2_procedures_are_transcribed() -> void:
	_begin("N2: le procedure sono trascritte")
	var o := SoloOpponent.load_for("N2 Operazione Weser (nord)")
	var placeholders := 0
	for tid in ["actions_early", "actions_late", "identify", "new_british_tf",
			"mine_hex"]:
		var t: SoloTable = o.table(tid)
		ne(t, null, "la tabella '%s' esiste" % tid)
		for code_v: Variant in t.legend.keys():
			if String(t.legend[code_v]).contains("senza automatismi del motore"):
				placeholders += 1
	eq(placeholders, 0, "nessuna e' rimasta un segnaposto")
	# Le due sotto-tabelle stampate DENTRO i risultati non c'erano affatto.
	var newtf: SoloTable = o.table("new_british_tf")
	eq((newtf.rows[0]["cells"] as Array).size(), 6,
		"la tabella Nuova TF Britannica copre tutte e sei le facce")
	var mines: SoloTable = o.table("mine_hex")
	eq(String((mines.rows[0]["cells"] as Array)[0]), "Bud",
		"e la tabella dell'esagono delle Mine parte da Bud")


## p.22: "Modifiers (Late table only)". La tabella Iniziale non ne ha nessuno,
## e il dato ne aveva uno che spostava TUTTI i tiri Iniziali.
func test_n2_early_table_has_no_modifiers() -> void:
	_begin("N2: la tabella Iniziale non ha modificatori")
	var o := SoloOpponent.load_for("N2 Operazione Weser (nord)")
	eq((o.table("actions_early").modifiers as Array).size(), 0,
		"la Iniziale non ne ha, come stampa la pagina")
	eq((o.table("actions_late").modifiers as Array).size(), 4,
		"i quattro modificatori valgono solo per la Seguente")


## p.23: le colonne sono 1 | 2 | 3-4 | 5 | 6, e la trascrizione le aveva lette
## come sei colonne distinte, cioe' scalate di una da un 4 in poi. E' lo stesso
## difetto della Tabella Murmansk di BL1.
func test_n2_identify_columns_are_not_shifted() -> void:
	_begin("N2: la tabella di Identificazione non e' piu' scalata di una colonna")
	var o := SoloOpponent.load_for("N2 Operazione Weser (nord)")
	var t: SoloTable = o.table("identify")
	var early: Array = t.rows[0]["cells"]
	var late: Array = t.rows[1]["cells"]
	eq(String(early[2]), "CL/Convoglio", "con un 3 la riga Iniziale da' CL/Convoglio")
	eq(String(early[3]), "CL/Convoglio",
		"e con un 4 pure, perche' la colonna stampata e' '3-4'")
	eq(String(early[4]), "DD/Convoglio", "il DD/Convoglio sta nella colonna 5")
	eq(String(early[5]), "Convoglio", "e il Convoglio solo nella 6")
	eq(String(late[3]), "CA/CA",
		"nella riga Seguente un 4 da' due CA, non uno")


## 'AA', 'Bd' e 'N' (pp.22-23): il porto e' quello dell'inserto, non il
## sostituto della Mappa Operazionale.
func test_n2_port_actions_use_the_inset_places() -> void:
	_begin("N2: AA va ad Andalsnes e Bd a Bud, non a Bergen e Trondheim")
	var st := _n2_state(41)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N2 Operazione Weser (nord)")
	var uk := TaskForce.Side.ROYAL_NAVY
	ne(g.place_hex("Andalsnes"), Vector2i.MAX,
		"Andalsnes e' un luogo dell'inserto del Mare di Norvegia")
	ne(g.place_hex("Bud"), Vector2i.MAX, "e anche Bud")

	var aa := SoloAI.execute_code("AA", st, g, engine, scenario.port_control(), uk)
	true_(_solo_ai_log_contains(aa, "Andalsnes"),
		"la procedura AA nomina Andalsnes")
	false_(_solo_ai_log_contains(aa, "Bergen"),
		"e non nomina piu' Bergen, che era il porto sostituto")
	eq(aa.get("time_lapse_goal", Vector2i.MAX), g.place_hex("Andalsnes"),
		"lo Scorrere del Tempo guarda Andalsnes")

	var st2 := _n2_state(42)
	var bd := SoloAI.execute_code("Bd", st2, st2.graph, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(bd, "Bud"), "la procedura Bd nomina Bud")


## 'mine' (p.22): l'esagono lo sceglie un dado, e la posa NON e' una
## Ricognizione - non si attaccano segnalini Informazioni.
func test_n2_mines_roll_their_hex_and_are_not_recon() -> void:
	_begin("N2 mine: l'esagono si tira, e la posa non assegna Informazioni")
	var st := _n2_state(43)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N2 Operazione Weser (nord)")
	var uk := TaskForce.Side.ROYAL_NAVY
	var german_info_before := 0
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		german_info_before += tf.info_count()

	st.rng.push_forced([1])
	var out := SoloAI.execute_code("mine", st, g, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(out, "l'esagono e' Bud"),
		"con un 1 le Mine vanno a Bud")
	var mines := 0
	for f in Stealth.forces_of(st, uk):
		if int(f.get("kind", -1)) == Stealth.Kind.MINES:
			mines += 1
	eq(mines, 1, "e la forza Furtiva Mine c'e' davvero")
	var german_info_after := 0
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		german_info_after += tf.info_count()
	eq(german_info_after, german_info_before,
		"ma nessun segnalino Informazioni e' stato assegnato: non e' Ricognizione")

	# Posata due volte nello stesso esagono, la seconda attacca un Contatto.
	st.rng.push_forced([1])
	SoloAI.execute_code("mine", st, g, engine, scenario.port_control(), uk)
	var contacts := 0
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		contacts += tf.trajectory.contact_count()
	true_(contacts > 0,
		"con le Mine gia' li', il risultato attacca un segnalino Contatto")


## 'R4' (p.23): la seconda volta diventa una 'X'.
func test_n2_r4_becomes_x_the_second_time() -> void:
	_begin("N2 R4: la seconda uscita vale come una 'X'")
	var st := _n2_state(44)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N2 Operazione Weser (nord)")
	var uk := TaskForce.Side.ROYAL_NAVY

	var first := SoloAI.execute_code("R4", st, g, engine, scenario.port_control(), uk)
	true_(_solo_ai_log_contains(first, "due nuove TF britanniche"),
		"la prima volta entrano TF1 e TF2")
	eq(int(st.solo_counters.get("n2_r4_results", 0)), 1, "e il conto sale")

	var second := SoloAI.execute_code("R4", st, g, engine, scenario.port_control(), uk)
	true_(_solo_ai_log_contains(second, "vale come una 'X'"),
		"la seconda volta il rimando stampato e' applicato")


## 'T' (p.23): senza Convoglio ne' TF non identificata la procedura rimanda a
## una 'X'; senza nessuna TF britannica rimanda a una 'N'.
func test_n2_trondheim_falls_back_to_x_and_n() -> void:
	_begin("N2 T: i due rimandi stampati sono applicati davvero")
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N2 Operazione Weser (nord)")
	var uk := TaskForce.Side.ROYAL_NAVY

	var st := _n2_state(45)
	# Una sola TF britannica, senza Convoglio e identificata: si va alla 'X'.
	var only := TaskForce.new(90, uk)
	only.ships.append(ShipRoster.shared().make("Sheffield"))
	only.trajectory.become_station(st.graph.place_hex("Trondheim"))
	st.add_task_force(only)
	var as_x := SoloAI.execute_code("T", st, st.graph, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(as_x, "si applica un risultato 'X'"),
		"senza Convoglio ne' incognita si applica una 'X'")

	# Nessuna TF britannica: si va alla 'N'.
	var st2 := _n2_state(46)
	for tf in st2.forces_of(uk):
		st2.remove_task_force(tf)
	var as_n := SoloAI.execute_code("T", st2, st2.graph, engine,
		scenario.port_control(), uk)
	true_(_solo_ai_log_contains(as_n, "si applica un risultato 'N'"),
		"senza nessuna TF britannica si applica una 'N'")


## 'X' (p.23): la nuova TF si tira sulla tabella stampata, e una BB deve essere
## LENTA - mai la Nelson ne' la Rodney.
func test_n2_new_british_tf_uses_only_slow_battleships() -> void:
	_begin("N2 X: la nuova TF non prende mai Nelson ne' Rodney")
	var st := _n2_state(47)
	var g := st.graph
	var engine := ActionEngine.load_default()
	var scenario := Scenario.load_by_id("N2 Operazione Weser (nord)")
	var uk := TaskForce.Side.ROYAL_NAVY
	# Nessuna TF britannica con una BB: la 'X' ne crea una nuova.
	for tf in st.forces_of(uk):
		st.remove_task_force(tf)
	st.rng.push_forced([1])
	SoloAI.execute_code("X", st, g, engine, scenario.port_control(), uk)
	var found := false
	for tf in st.forces_of(uk):
		for ship in tf.ships:
			ne(ship.name, "Nelson", "la Nelson non entra: non e' lenta abbastanza")
			ne(ship.name, "Rodney", "e nemmeno la Rodney")
			if ship.type_code == "BB":
				found = true
	true_(found, "ma una BB nella nuova TF c'e'")
