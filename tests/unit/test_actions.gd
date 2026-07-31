extends TestCase

## Motore delle Azioni e Risultati Comuni.

var graph: MapGraph
var eng: ActionEngine
var origin: Vector2i


func name() -> String:
	return "Azioni + Risultati"


func run() -> void:
	graph = MapGraph.load_default()
	eng = ActionEngine.load_default()
	for h_v: Variant in graph.all_hexes():
		if graph.adjacent_hexes(h_v).size() == 6:
			origin = h_v
			break
	test_data_loads()
	test_engage_table()
	test_columns()
	test_legality()
	test_resolution_pipeline()
	test_interruption_cancels_action()
	test_unverified_actions_refused()
	test_result_contact_and_sighted()
	test_result_shadow()
	test_result_early_late()
	test_result_speed_dependent()


func _tf(side: int, n: int, speed: int = TimeLapse.Speed.MEDIUM) -> TaskForce:
	var tf := TaskForce.new(0, side)
	tf.speed = speed
	tf.trajectory.station_hex = origin
	var cur := origin
	for i in n:
		for cand in graph.adjacent_hexes(cur):
			if not tf.trajectory.occupies(cand):
				tf.trajectory.extend(cand, 1, graph)
				cur = cand
				break
	return tf


func test_data_loads() -> void:
	_begin("caricamento actions.json")
	eq(eng.load_error, "", "nessun errore")
	true_(eng.actions().size() >= 8, "tutte le azioni sono elencate")
	true_(eng.result_info("CONTACT").has("label"), "i risultati hanno un'etichetta")


func test_engage_table() -> void:
	_begin("tabella Ingaggiare (letta dalla mappa)")
	eq(eng.lookup("ENGAGE", 6, 0), ["SKIRMISH"] as Array[String], "6 o meno / TT 0")
	eq(eng.lookup("ENGAGE", 7, 0), ["CLOSING"] as Array[String], "7 / TT 0")
	eq(eng.lookup("ENGAGE", 8, 0), ["BATTLE"] as Array[String], "8 / TT 0")
	eq(eng.lookup("ENGAGE", 9, 0), ["BATTLE"] as Array[String], "9 / TT 0")
	eq(eng.lookup("ENGAGE", 11, 0), ["SURPRISE"] as Array[String], "10-11 / TT 0")
	eq(eng.lookup("ENGAGE", 13, 0), ["SURPRISE"] as Array[String], "13+ / TT 0")
	eq(eng.lookup("ENGAGE", 6, 3), ["MISS"] as Array[String], "6 / TT 3")
	eq(eng.lookup("ENGAGE", 8, 3), ["SKIRMISH"] as Array[String], "8 / TT 3")
	eq(eng.lookup("ENGAGE", 9, 4), ["CLOSING"] as Array[String], "9 / TT 4")
	eq(eng.lookup("ENGAGE", 12, 1), ["BATTLE"] as Array[String], "12 / TT 1")
	eq(eng.lookup("ENGAGE", 11, 12), ["CONTACT"] as Array[String], "10-11 / TT 10-13")
	eq(eng.lookup("ENGAGE", 13, 20), ["SKIRMISH"] as Array[String], "13+ / TT 14+")
	eq(eng.lookup("ENGAGE", 9, 20), ["MISS"] as Array[String], "9 / TT 14+")
	eq(eng.lookup("ENGAGE", 2, 0), ["SKIRMISH"] as Array[String], "2 rientra in '6 o meno'")


func test_columns() -> void:
	_begin("colonne")
	eq(eng.column_for("ENGAGE", 0), 0, "TT 0")
	eq(eng.column_for("ENGAGE", 4), 1, "TT 4 -> 1-4")
	eq(eng.column_for("ENGAGE", 5), 2, "TT 5 -> 5-9")
	eq(eng.column_for("ENGAGE", 13), 3, "TT 13 -> 10-13")
	eq(eng.column_for("ENGAGE", 99), 4, "TT alto -> 14+")
	eq(eng.column_label("ENGAGE", 4), "14+", "etichetta")
	eq(eng.column_for("NAVAL_SEARCH", 4), 0, "Ricerca Navale: TT 4 -> 0-4")
	eq(eng.column_for("NAVAL_SEARCH", 16), 3, "Ricerca Navale: TT 16 -> 16+")


func test_legality() -> void:
	_begin("legalita' della dichiarazione")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 3))
	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 2))

	var dec := ActionEngine.Declaration.new()
	dec.action_key = "ENGAGE"
	dec.active = a
	dec.target = b
	ne(eng.legality_error(dec, st), "", "bersaglio Traiettoria: rifiutato")
	true_(eng.legality_error(dec, st).contains("Stazione"), "il motivo cita la Stazione")

	b.trajectory.become_station(origin)
	eq(eng.legality_error(dec, st), "", "bersaglio Stazione: accettato")

	var dec2 := ActionEngine.Declaration.new()
	dec2.action_key = "COMPLETION"
	dec2.active = a
	a.trajectory.set_info(0, true)
	ne(eng.legality_error(dec2, st), "", "Completamento con Informazioni: rifiutato")
	a.trajectory.set_info(0, false)
	eq(eng.legality_error(dec2, st), "", "Completamento senza Informazioni: accettato")


func test_resolution_pipeline() -> void:
	_begin("pipeline completa")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 4))
	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 5))
	b.trajectory.become_station(origin)

	var dec := ActionEngine.Declaration.new()
	dec.action_key = "ENGAGE"
	dec.active = a
	dec.target = b
	dec.target_hex = origin

	st.rng.push_forced([4, 4])
	var res := eng.resolve(dec, st)
	true_(res["ok"], "risolta")
	eq(res["error"], "", "nessun errore")
	eq(res["trajectory_total"], 4, "Totale Traiettoria 4")
	eq(res["column"], "1-4", "colonna 1-4")
	eq(res["sum"], 8, "somma 8")
	eq(res["results"], ["SKIRMISH"] as Array[String], "8 / colonna 1-4 = Schermaglia")
	true_(eng.describe(res).length() > 10, "la descrizione e' leggibile")


func test_interruption_cancels_action() -> void:
	_begin("l'Interruzione annulla l'Azione")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 4))
	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 2))
	b.trajectory.become_station(origin)
	a.trajectory.set_info(0, true)

	var dec := ActionEngine.Declaration.new()
	dec.action_key = "ENGAGE"
	dec.active = a
	dec.target = b

	st.rng.push_forced([5, 5])
	var res := eng.resolve(dec, st)
	true_(res["ok"], "risolta")
	true_((res["interruption"] as Dictionary)["triggered"], "Interruzione innescata")
	eq((res["interruption"] as Dictionary)["code"], "VIE_FOR_INITIATIVE", "risultato")
	eq((res["results"] as Array).size(), 0, "nessun risultato: l'azione e' annullata")
	eq(res["dice"], 0, "non si e' tirato per l'azione")

	var st2 := GameState.new(graph, 5)
	var a2 := st2.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 0))
	var b2 := st2.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 2))
	a2.trajectory.extend(graph.adjacent_hexes(origin)[0], 1, graph)
	a2.trajectory.set_info(0, true)
	b2.trajectory.become_station(origin)
	var dec2 := ActionEngine.Declaration.new()
	dec2.action_key = "ENGAGE"
	dec2.active = a2
	dec2.target = b2
	st2.rng.push_forced([2, 2, 5, 4])
	var res2 := eng.resolve(dec2, st2)
	eq((res2["interruption"] as Dictionary)["code"], "ALERT_0", "Allerta -0")
	eq(res2["modifier"], 0, "nessun modificatore")
	eq(res2["sum"], 9, "l'azione prosegue e tira")
	true_((res2["results"] as Array).size() > 0, "c'e' un risultato")


func test_unverified_actions_refused() -> void:
	_begin("le azioni non verificate vengono rifiutate, non indovinate")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 2))
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "AIR_STRIKE"
	dec.active = a
	var res := eng.resolve(dec, st)
	false_(res["ok"], "non risolta")
	true_(String(res["error"]).contains("non ancora trascritta"),
		"il motivo e' esplicito: " + String(res["error"]))
	false_(eng.is_verified("AIR_STRIKE"), "Attacco Aereo non verificato")
	true_(eng.is_verified("ENGAGE"), "Ingaggiare verificato")
	true_(eng.is_verified("NAVAL_SEARCH"), "Ricerca Navale utilizzabile")
	true_(eng.is_cell_unverified("NAVAL_SEARCH", 4, 7), "cella segnalata da riverificare")
	false_(eng.is_cell_unverified("NAVAL_SEARCH", 4, 0), "colonna 0-4 verificata")


func test_result_contact_and_sighted() -> void:
	_begin("risultati Contatto e Avvistato")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 2))
	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 4))
	var h: Vector2i = b.trajectory.segments[1]["hex"]

	var r := Results.apply("CONTACT", a, b, h, st)
	eq(b.trajectory.contact_count(), 1, "Contatto assegnato")
	true_(String(r["text"]).contains("Contatto"), "descritto")

	Results.apply("SIGHTED", a, b, h, st)
	true_(b.trajectory.is_station(), "il bersaglio e' ora una Stazione")
	eq(b.trajectory.station_hex, h, "posta nell'esagono bersaglio")
	eq(b.trajectory.contact_count(), 1, "il Contatto nell'esagono bersaglio sopravvive")
	eq(b.trajectory.info_count(), 0, "i segnalini Informazioni sono rimossi")


func test_result_shadow() -> void:
	_begin("risultato Seguire (lascia 3)")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 2))
	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 8))
	var h: Vector2i = b.trajectory.segments[4]["hex"]
	Results.apply("SHADOW", a, b, h, st)
	eq(b.trajectory.length(), 3, "restano 3 segmenti")
	true_(b.trajectory.index_of_hex(h) >= 0, "il segmento bersaglio non e' stato rimosso")

	var c := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 3))
	var hc: Vector2i = c.trajectory.segments[0]["hex"]
	Results.apply("SHADOW", a, c, hc, st)
	eq(c.trajectory.length(), 3, "nessun segmento rimosso")
	true_(c.evasive, "riceve Manovre Evasive")


func test_result_early_late() -> void:
	_begin("risultato In Anticipo o In Ritardo")
	var st := GameState.new(graph, 5)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, 2))

	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 7))
	var mid: Vector2i = b.trajectory.segments[3]["hex"]
	Results.apply("EARLY_LATE", a, b, mid, st)
	true_(b.trajectory.length() < 6, "la Traiettoria si accorcia oltre il singolo segmento")
	eq(b.trajectory.index_of_hex(mid), -1, "il segmento bersaglio e' sparito")

	var c := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 5))
	var endh: Vector2i = c.trajectory.end_hex(0)
	Results.apply("EARLY_LATE", a, c, endh, st)
	eq(c.trajectory.length(), 4, "perde solo un segmento")
	true_(c.evasive, "riceve Manovre Evasive")

	var d := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, 1))
	var only: Vector2i = d.trajectory.segments[0]["hex"]
	Results.apply("EARLY_LATE", a, d, only, st)
	true_(d.trajectory.is_station(), "diventa Stazione")
	true_(d.evasive, "riceve Manovre Evasive")


func test_result_speed_dependent() -> void:
	_begin("risultati che dipendono dalla velocita'")
	var st := GameState.new(graph, 5)
	var fast := _tf(TaskForce.Side.KRIEGSMARINE, 2, TimeLapse.Speed.FAST)
	var slow := _tf(TaskForce.Side.ROYAL_NAVY, 2, TimeLapse.Speed.SLOW)
	st.add_task_force(fast)
	st.add_task_force(slow)
	var h: Vector2i = slow.trajectory.segments[0]["hex"]

	var r := Results.apply("CLOSING", fast, slow, h, st)
	eq(r["battle"], Results.Battle.FULL, "Ridurre le Distanze con TF piu' veloce = Battaglia")

	var r2 := Results.apply("CLOSING", slow, fast, h, st)
	eq(r2["battle"], Results.Battle.NONE, "altrimenti nessuna battaglia")

	var r3 := Results.apply("SKIRMISH", fast, slow, h, st)
	eq(r3["battle"], Results.Battle.LIMITED,
		"Schermaglia con TF piu' veloce = Battaglia Limitata")
	var r4 := Results.apply("SKIRMISH", slow, fast, h, st)
	eq(r4["battle"], Results.Battle.NONE, "altrimenti vale come Contatto")

	fast.trajectory.set_info(0, true)
	var r5 := Results.apply("MISS", fast, slow, h, st)
	true_(r5["initiative_changes"], "Mancato + Informazioni -> cambio di Iniziativa")
