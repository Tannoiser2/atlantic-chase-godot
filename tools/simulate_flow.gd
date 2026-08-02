extends SceneTree

## Simulazione headless del flusso operativo e solitario. Non verifica tabelle
## nuove: serve a vedere la sequenza azione -> Scorrere del Tempo ->
## Iniziativa/Meteo -> Battaglia -> ritorno alla mappa.


func _init() -> void:
	print("")
	print("SIMULAZIONE FLUSSO - DUE GIOCATORI")
	_sim_two_player()
	print("")
	print("SIMULAZIONE FLUSSO - SOLITARIO")
	_sim_solo()
	quit()


func _chain(tf: TaskForce, graph: MapGraph, n: int) -> void:
	var cur := tf.trajectory.station_hex
	for i in n:
		for h in graph.adjacent_hexes(cur):
			if not tf.trajectory.occupies(h):
				tf.trajectory.extend(h, 1, graph)
				cur = h
				break


func _tf(id: int, side: int, at: Vector2i, ships: Array[String]) -> TaskForce:
	var tf := TaskForce.new(id, side)
	tf.trajectory.become_station(at)
	for n in ships:
		var s := ShipRoster.shared().make(n)
		tf.ships.append(s if s != null else Ship.new(n))
	tf.recompute_speed()
	return tf


func _time_lapse_first_option(tf: TaskForce, state: GameState) -> void:
	if tf.trajectory.is_station():
		print("  Scorrere del Tempo: %s e' gia' Stazione" % tf.display_name())
		return
	var amount := TimeLapse.required_removal(tf.speed, state.weather, state.rng)
	var opts := TimeLapse.removal_options(tf.trajectory, tf.speed, amount)
	if opts.is_empty():
		print("  Scorrere del Tempo: nessuna rimozione legale")
		return
	var freed := TimeLapse.apply(tf.trajectory, opts[0])
	if tf.trajectory.length() == 0 and not freed.is_empty():
		tf.trajectory.become_station(freed[0])
	print("  Scorrere del Tempo: %s -> %d segmenti"
		% [tf.display_name(), tf.length()])


func _sim_two_player() -> void:
	var graph := MapGraph.load_default()
	var st := GameState.new(graph, 20260802)
	st.weather = TimeLapse.Weather.GOOD
	st.initiative = TaskForce.Side.KRIEGSMARINE
	var origin := Vector2i(15, -5)
	var km := st.add_task_force(_tf(1, TaskForce.Side.KRIEGSMARINE, origin,
		["Hipper"] as Array[String]))
	var rn := st.add_task_force(_tf(2, TaskForce.Side.ROYAL_NAVY, origin,
		["Hood"] as Array[String]))
	_chain(km, graph, 3)
	_chain(rn, graph, 4)
	print("1. Iniziativa iniziale: %s, meteo %s"
		% [Initiative.side_name(st.initiative), Initiative.weather_label(st.weather)])
	print("2. Ricerca Navale: KM Traiettoria %d contro RN Traiettoria %d"
		% [km.length(), rn.length()])
	var eng := ActionEngine.load_default()
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "NAVAL_SEARCH"
	dec.active = km
	dec.target = rn
	dec.target_hex = origin
	st.rng.push_forced([4, 4])
	var res := eng.resolve(dec, st)
	print("  %s" % eng.describe(res))
	for c_v in res["results"]:
		var a := Results.apply(String(c_v), km, rn, origin, st)
		print("  risultato %s: %s" % [String(c_v), String(a["text"])])
	_time_lapse_first_option(km, st)
	st.rng.push_forced([5, 4, 2])
	var steal := Initiative.steal(st)
	for l in steal["log"]:
		print("  " + String(l))

	print("3. Battaglia di controllo e ritorno alla mappa")
	var bs := BattleState.new(BattleState.Kind.LIMITED, st.weather)
	bs.active_tf = km
	bs.target_tf = rn
	bs.hex = origin
	var battle := Battle.new(bs, st.rng)
	battle.start()
	battle.break_away_phase(false, false)
	battle.end_round()
	battle.finish()
	for l in bs.log:
		print("  " + String(l))
	st.rng.push_forced([3, 6, 1])
	var seek := Initiative.seek(st)
	for l in seek["log"]:
		print("  " + String(l))


func _sim_solo() -> void:
	var sc := Scenario.load_by_id("BL2 Contain and Destroy")
	var victory: Victory = Victory.from_scenario(sc)
	var graph := MapGraph.load_default()
	var st := GameState.new(graph, 99)
	st.apply_dict(sc.to_state_dict())
	var solo := SoloOpponent.load_for(sc.id)
	print("1. Scenario: %s; fase %s" % [sc.title,
		"Presto" if st.solo_phase == SoloOpponent.Phase.EARLY else "Tardi"])
	st.rng.push_forced([2])
	var action := solo.act(st.rng, st.convoys_completed)
	print("  Tabella Azioni: %s" % String(action.get("code", "")))
	print("  %s" % String(action.get("text", "")).replace("\n", " "))

	var player_side: int = victory.solo_side if victory != null else TaskForce.Side.KRIEGSMARINE
	var enemy := TaskForce.new(10, 1 - player_side)
	enemy.unidentified = true
	enemy.trajectory.become_station(graph.port_hex("Kiel"))
	st.add_task_force(enemy)
	st.rng.push_forced([4])
	var ident := solo.identify(st.rng, enemy)
	print("2. Identificazione TF immaginaria: %s" % String(ident.get("text", "")))

	var bstate := BattleState.new(BattleState.Kind.BATTLE, st.weather)
	var km := _tf(20, TaskForce.Side.KRIEGSMARINE, Vector2i(15, -5),
		["Hipper"] as Array[String])
	var rn := _tf(21, TaskForce.Side.ROYAL_NAVY, Vector2i(15, -5),
		["Convoy x3", "Hood"] as Array[String])
	bstate.active_tf = km
	bstate.target_tf = rn
	for s in bstate.all_ships():
		s.battle_zone = BattleState.Zone.NEAR
	var imaginary: int = 1 - player_side
	var targeting := SoloBattle.targeting(bstate, imaginary)
	print("3. Dottrina Battaglia solitaria (%s immaginaria): %d bersagli assegnati"
		% [Initiative.side_name(imaginary), targeting.size()])
	for f_v in targeting.keys():
		print("  %s -> %s" % [(f_v as Ship).name, (targeting[f_v] as Ship).name])
	var moves := SoloBattle.maneuver_moves(bstate, imaginary)
	print("  Manovre automatiche: %d" % moves.size())
	print("  Tenta Fuga: %s" % str(SoloBattle.wants_break_away(bstate, imaginary)))
