extends TestCase

## GameState, segnalini Informazioni contestuali, e undo/redo.

var graph: MapGraph
var origin: Vector2i


func name() -> String:
	return "GameState + undo"


func run() -> void:
	graph = MapGraph.load_default()
	for h_v: Variant in graph.all_hexes():
		if graph.adjacent_hexes(h_v).size() == 6:
			origin = h_v
			break
	test_add_and_find()
	test_info_trigger_enemy_station()
	test_info_trigger_not_by_enemy_segment()
	test_serialization_roundtrip()
	test_undo_redo()


func _tf(side: int, at: Vector2i) -> TaskForce:
	var tf := TaskForce.new(0, side)
	tf.trajectory.station_hex = at
	return tf


func test_add_and_find() -> void:
	_begin("registro delle Task Force")
	var st := GameState.new(graph, 7)
	var a := st.add_task_force(_tf(TaskForce.Side.KRIEGSMARINE, origin))
	var nb := graph.adjacent_hexes(origin)[0]
	var b := st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, nb))
	ne(a.id, b.id, "identificatori distinti")
	eq(st.task_force(a.id), a, "recupero per id")
	eq(st.forces_of(TaskForce.Side.KRIEGSMARINE).size(), 1, "una TF tedesca")
	eq(st.forces_of(TaskForce.Side.ROYAL_NAVY).size(), 1, "una TF britannica")
	eq(st.forces_in(origin).size(), 1, "una TF nell'esagono di partenza")
	# RB p.14: piu' TF possono condividere lo stesso esagono
	st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, origin))
	eq(st.forces_in(origin).size(), 2, "due TF condividono l'esagono")


func test_info_trigger_enemy_station() -> void:
	_begin("Informazioni: Stazione TF nemica (RB p.21)")
	var st := GameState.new(graph, 7)
	st.add_task_force(_tf(TaskForce.Side.ROYAL_NAVY, origin))
	true_(st.triggers_info(origin, TaskForce.Side.KRIEGSMARINE),
		"un tedesco che entra nell'esagono di una Stazione britannica prende Informazioni")
	false_(st.triggers_info(origin, TaskForce.Side.ROYAL_NAVY),
		"la propria Stazione non innesca Informazioni")

	# un porto nemico registrato esplicitamente
	var h := graph.adjacent_hexes(origin)[0]
	st.add_info_trigger(h, "porto nemico (Brest)")
	true_(st.triggers_info(h, TaskForce.Side.KRIEGSMARINE), "porto nemico innesca")
	true_(st.info_reasons(h, TaskForce.Side.KRIEGSMARINE).size() > 0, "il motivo e' riportato")


func test_info_trigger_not_by_enemy_segment() -> void:
	_begin("Informazioni: un segmento nemico NON innesca (chiarimento RB p.21)")
	var st := GameState.new(graph, 7)
	var enemy := _tf(TaskForce.Side.ROYAL_NAVY, origin)
	var nb := graph.adjacent_hexes(origin)[0]
	enemy.trajectory.extend(nb, 1, graph)
	st.add_task_force(enemy)
	false_(enemy.trajectory.is_station(), "la TF nemica e' una Traiettoria, non una Stazione")
	false_(st.triggers_info(nb, TaskForce.Side.KRIEGSMARINE),
		"un esagono con solo un segmento nemico non da' Informazioni")


func test_serialization_roundtrip() -> void:
	_begin("serializzazione dello stato")
	var st := GameState.new(graph, 42)
	st.scenario_name = "prova"
	st.weather = TimeLapse.Weather.BAD
	st.round_number = 3
	var tf := _tf(TaskForce.Side.KRIEGSMARINE, origin)
	tf.name = "Bismarck TF"
	tf.speed = TimeLapse.Speed.FAST
	var cur := origin
	for i in 3:
		for cand in graph.adjacent_hexes(cur):
			if not tf.trajectory.occupies(cand):
				tf.trajectory.extend(cand, 1, graph)
				cur = cand
				break
	tf.trajectory.set_info(0, true)
	st.add_task_force(tf)
	st.add_info_trigger(origin, "base aerea tedesca")

	var d := st.to_dict()
	var st2 := GameState.new(graph, 0)
	st2.apply_dict(d)
	eq(st2.scenario_name, "prova", "nome scenario")
	eq(st2.weather, TimeLapse.Weather.BAD, "meteo")
	eq(st2.round_number, 3, "round")
	eq(st2.task_forces.size(), 1, "una TF")
	eq(st2.task_forces[0].name, "Bismarck TF", "nome TF")
	eq(st2.task_forces[0].speed, TimeLapse.Speed.FAST, "velocita'")
	eq(st2.task_forces[0].length(), tf.length(), "lunghezza traiettoria")
	eq(st2.task_forces[0].info_count(), 1, "segnalini Informazioni")
	true_(st2.info_triggers.has(origin), "inneschi Informazioni conservati")


func test_undo_redo() -> void:
	_begin("undo / redo")
	var st := GameState.new(graph, 1)
	var tf := _tf(TaskForce.Side.KRIEGSMARINE, origin)
	st.add_task_force(tf)
	var log := CommandLog.new(st)

	false_(log.can_undo(), "niente da annullare all'inizio")

	var cur := origin
	var added: Array[Vector2i] = []
	for i in 3:
		for cand in graph.adjacent_hexes(cur):
			if not st.task_forces[0].trajectory.occupies(cand):
				st.task_forces[0].trajectory.extend(cand, 1, graph)
				added.append(cand)
				cur = cand
				break
		log.record("segmento %d" % (i + 1))

	eq(st.task_forces[0].length(), 3, "tre segmenti aggiunti")
	eq(log.applied_count(), 3, "tre mosse registrate")

	true_(log.undo(), "annulla")
	eq(st.task_forces[0].length(), 2, "torna a due segmenti")
	true_(log.undo(), "annulla ancora")
	eq(st.task_forces[0].length(), 1, "un segmento")
	true_(log.undo(), "annulla fino all'inizio")
	eq(st.task_forces[0].length(), 0, "torna Stazione")
	false_(log.can_undo(), "niente altro da annullare")

	true_(log.redo(), "ripristina")
	eq(st.task_forces[0].length(), 1, "un segmento di nuovo")
	true_(log.redo(), "ripristina ancora")
	eq(st.task_forces[0].length(), 2, "due segmenti")
	eq(log.labels().size(), 2, "due mosse applicate")

	# una nuova mossa dopo un undo taglia il ramo di redo
	log.record("mossa alternativa")
	false_(log.can_redo(), "il ramo di redo e' stato tagliato")
