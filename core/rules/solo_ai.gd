class_name SoloAI
extends RefCounted

## Policy digitale per l'avversario immaginario.
##
## Le tabelle del fascicolo restano la fonte delle regole: scelgono il codice
## dell'azione. Questa classe decide invece le scelte che, nel gioco fisico,
## toccherebbero al giocatore che muove l'avversario immaginario: quale TF
## usare, verso quale obiettivo tracciare, e quando dichiarare un'azione gia'
## legalmente disponibile. Non pretende di essere una regola GMT: e' una policy
## esplicita, deterministica e testabile.

const ROUTE_STEP_LIMIT := Trajectory.MAX_SEGMENTS


static func execute_code(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	var out := _empty("Solitario AI: nessuna decisione.")
	var raw := code.strip_edges()
	var normalized := _normalize_code(code)
	if state.scenario_name.begins_with("B1"):
		return _b1(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("A1"):
		return _a1(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("BL1"):
		return _bl1(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("BL2"):
		return _bl2(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("BL3"):
		return _bl3(normalized, state, graph, engine, port_control, side)
	match normalized:
		"A":
			out = _air_or_attack(state, graph, engine, side)
		"C":
			out = _completion_or_route(state, graph, engine, port_control, side)
		"T":
			out = _trajectory_move(state, graph, side)
		"X":
			out = _decisive_attack(state, graph, engine, side, raw)
		_:
			out["log"].append("Solitario AI: il codice '%s' non ha ancora una policy automatica." % code)
			out["pass_initiative"] = true
	return out


static func _a1(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"C":
			var tf := _first_damaged_force(state, side)
			if tf == null:
				tf = _best_unidentified(state, side)
			if tf == null:
				tf = _shortest_force(state, side)
			if tf == null:
				return _air_or_attack(state, graph, engine, side)
			var port_name := ""
			if _has_damaged(tf):
				var p := _nearest_friendly_port(graph, port_control, side, _anchor_hex(tf))
				port_name = String(p.get("name", ""))
			else:
				port_name = _nearest_named_port(graph, _anchor_hex(tf), ["Narvik", "St. Nazaire"])
			return _complete_or_route_to_port(state, graph, port_control, tf, port_name,
				"Solitario AI A1: Completamento tedesco")
		"X":
			var active := _nearest_force_to_convoy(state, side)
			if active == null:
				var r := state.rng.d6("Solitario A1 nuova TF X")
				active = _create_unidentified_at(state, graph, side,
					"Narvik" if r <= 3 else ("Trondheim" if r <= 5 else "St. Nazaire"))
			if _has_damaged(active):
				return _a1("C", state, graph, engine, port_control, side)
			var convoy := _best_convoy_target(state, side, active)
			if convoy == null:
				var no := _empty("Solitario AI A1: nessun Convoglio bersagliabile; tratta come C e sottrae 1 VP al giocatore.")
				state.add_vp(1 - side, -1.0, "A1: nessun Convoglio bersagliabile")
				no["pass_initiative"] = true
				return no
			return _attack_or_route_selected(state, graph, engine, active, convoy,
				"Solitario AI A1: X intercetta il Convoglio piu' vicino")
		_:
			return _air_or_attack(state, graph, engine, side)


static func _b1(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"A":
			if state.weather == TimeLapse.Weather.BAD:
				_remove_damaged_ships(state, side)
				return _b1("X" if state.rng.d6("Solitario B1 meteo cattivo A") % 2 == 0
					else "convoy", state, graph, engine, port_control, side)
			var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
			if bool(air["ok"]):
				air["log"].append("Solitario AI B1: Attacco Aereo britannico col meteo buono.")
				return air
			var roll := state.rng.d6("Solitario B1 nessun bersaglio A")
			var hunter: TaskForce = null
			if roll % 2 == 0:
				hunter = _nearest_force_with_type(state, side, "CA", _enemy_center(state, side))
				if hunter == null:
					hunter = _create_force_at(state, graph, side, "Scapa Flow",
						["Birmingham", "Sheffield", "Berwick", "London"], false)
			else:
				hunter = _create_force_at(state, graph, side, "Gibilterra",
					["Malaya", "London", "Suffolk", "Victorious"], false)
			return _attack_or_route_selected(state, graph, engine, hunter,
				_best_enemy_target(state, side, hunter), "Solitario AI B1: A caccia la TF tedesca piu' vicina")
		"C":
			_remove_damaged_ships(state, side)
			var convoy := _shortest_force_with_convoy(state, side)
			if convoy == null:
				return _b1("convoy" if state.rng.d6("Solitario B1 C senza Convoglio") % 2 == 0
					else "A", state, graph, engine, port_control, side)
			return _complete_or_route_to_port(state, graph, port_control, convoy,
				_b1_convoy_destination(graph, convoy),
				"Solitario AI B1: Completamento Convoglio britannico")
		"X":
			_remove_damaged_ships(state, side)
			var hunter_x := _nearest_heavy_without_convoy(state, side, _enemy_center(state, side))
			if hunter_x == null:
				hunter_x = _best_unidentified(state, side)
			if hunter_x == null:
				hunter_x = _create_unidentified_at(state, graph, side, "Scapa Flow")
			var target := _best_enemy_target(state, side, hunter_x)
			if target == null:
				return _b1("convoy", state, graph, engine, port_control, side)
			return _attack_or_route_selected(state, graph, engine, hunter_x, target,
				"Solitario AI B1: X intercetta la TF tedesca piu' vicina")
		_:
			var existing := _shortest_force_with_convoy(state, side)
			if existing != null:
				return _b1("C", state, graph, engine, port_control, side)
			var port := "New York" if state.rng.d6("Solitario B1 nuovo Convoglio") % 2 == 0 \
				else "Africa"
			var tf := _create_force_at(state, graph, side, port, ["Convoy x3"], false)
			return _complete_or_route_to_port(state, graph, port_control, tf,
				"Clyde", "Solitario AI B1: nuovo Convoglio verso Clyde/Liverpool")


static func _bl1(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"A":
			if state.weather == TimeLapse.Weather.BAD:
				return _decisive_attack(state, graph, engine, side)
			var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
			if bool(air["ok"]):
				air["log"].append("Solitario AI BL1: col meteo buono prova l'Attacco Aereo.")
				return air
			var ca := _nearest_force_with_type(state, side, "CA", _enemy_center(state, side))
			if ca == null:
				ca = _create_unidentified_at(state, graph, side, "Portsmouth")
			return _attack_or_route_selected(state, graph, engine, ca,
				_best_enemy_target(state, side, ca), "Solitario AI BL1: caccia con CA/TF Portsmouth")
		"C":
			var convoy := _shortest_force_with_convoy(state, side)
			if convoy == null:
				return _bl1("convoy", state, graph, engine, port_control, side)
			var port := _nearest_named_port(graph, _anchor_hex(convoy),
				["Clyde", "Liverpool", "Portsmouth"])
			return _complete_or_route_to_port(state, graph, port_control, convoy, port,
				"Solitario AI BL1: Convoglio verso il porto britannico piu' vicino")
		"X":
			var bc := _shortest_force_with_type(state, side, "BC", true)
			if bc == null:
				bc = _best_unidentified(state, side)
			if bc == null:
				bc = _create_unidentified_at(state, graph, side,
					_closer_port_to_enemy(graph, state, side, ["Scapa Flow", "Gibilterra"]))
			return _attack_or_route_selected(state, graph, engine, bc,
				_best_enemy_target(state, side, bc), "Solitario AI BL1: azione decisiva con BC/TF ignota")
		_:
			return _completion_or_route(state, graph, engine, port_control, side)


static func _bl2(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"A":
			if state.weather == TimeLapse.Weather.BAD:
				return _bl2("T", state, graph, engine, port_control, side)
			var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
			if bool(air["ok"]):
				air["log"].append("Solitario AI BL2: col meteo buono prova l'Attacco Aereo.")
				return air
			return _bl2("X", state, graph, engine, port_control, side)
		"C":
			var damaged := _first_damaged_force(state, side)
			var tf := _shortest_force_with_convoy(state, side)
			if tf == null:
				tf = damaged
			if tf == null:
				tf = _shortest_force(state, side)
			if tf == null:
				return _bl2("A", state, graph, engine, port_control, side)
			var port_name := "South America" if _has_undamaged_type(tf, "PB") else "Kiel"
			return _complete_or_route_to_port(state, graph, port_control, tf, port_name,
				"Solitario AI BL2: Completamento secondo priorita' Convoglio/Danneggiata/corta")
		"T":
			var tf_t := _best_unidentified(state, side)
			if tf_t == null:
				tf_t = _create_unidentified_at(state, graph, side, "Narvik")
			var roll := state.rng.d6("Solitario BL2 destinazione T")
			if roll <= 3:
				return _complete_or_route_to_port(state, graph, port_control, tf_t,
					"South America", "Solitario AI BL2: T verso South America")
			if roll <= 5:
				return _complete_or_route_to_port(state, graph, port_control, tf_t,
					"Kiel", "Solitario AI BL2: T verso Kiel")
			var out := _empty("Solitario AI BL2: T porta alle Azzorre, ma l'esagono non e' calibrato nella mappa dati; passa senza inventare coordinate.")
			out["pass_initiative"] = true
			return out
		"X":
			var tf_x := _shortest_force_with_type(state, side, "BC")
			if tf_x == null:
				tf_x = _best_non_convoy(state, side)
			if tf_x == null:
				var r := state.rng.d6("Solitario BL2 nuova TF X")
				tf_x = _create_unidentified_at(state, graph, side,
					"Kiel" if r <= 4 else ("Narvik" if r == 5 else "South America"))
			if _has_damaged(tf_x):
				return _bl2("C", state, graph, engine, port_control, side)
			var convoy_target := _best_convoy_target(state, side, tf_x)
			if convoy_target == null:
				var no_convoy := _empty("Solitario AI BL2: X richiede un Convoglio britannico; nessuno in gioco, tratta come E/fine non automatizzata.")
				no_convoy["pass_initiative"] = true
				return no_convoy
			return _attack_or_route_selected(state, graph, engine, tf_x, convoy_target,
				"Solitario AI BL2: X punta al Convoglio britannico")
		_:
			return _completion_or_route(state, graph, engine, port_control, side)


static func _bl3(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"A":
			if state.weather == TimeLapse.Weather.BAD:
				if _nearest_force_with_type(state, side, "CA", _enemy_center(state, side)) != null:
					return _bl3("X", state, graph, engine, port_control, side)
				var ca_tf := _create_force_at(state, graph, side, "Portsmouth",
					["Birmingham", "Sheffield"], false)
				return _complete_or_route_to_port(state, graph, port_control, ca_tf,
					"Scapa Flow", "Solitario AI BL3: crea 2 CA a Portsmouth e rotta verso Scapa Flow")
			return _air_or_attack(state, graph, engine, side)
		"C":
			var tf_c := _shortest_force_with_convoy(state, side)
			if tf_c == null:
				tf_c = _best_unidentified(state, side)
			if tf_c == null:
				tf_c = _shortest_force(state, side)
			if tf_c == null:
				return _bl3("A", state, graph, engine, port_control, side)
			var port_name := "Scapa Flow" if state.solo_phase == SoloOpponent.Phase.LATE else "Methil"
			return _complete_or_route_to_port(state, graph, port_control, tf_c, port_name,
				"Solitario AI BL3: Completamento al porto previsto dalla fase")
		"X":
			_remove_damaged_ships(state, side)
			var tf_x := _shortest_force_with_type(state, side, "BC")
			if tf_x == null:
				tf_x = _shortest_force_with_type(state, side, "BB")
			if tf_x == null:
				tf_x = _best_unidentified(state, side)
			if tf_x == null:
				tf_x = _create_unidentified_at(state, graph, side, "Scapa Flow")
			return _attack_or_route_selected(state, graph, engine, tf_x,
				_best_enemy_target(state, side, tf_x), "Solitario AI BL3: azione decisiva")
		_:
			return _completion_or_route(state, graph, engine, port_control, side)


static func _empty(note: String = "") -> Dictionary:
	var out := {
		"ok": false,
		"action_key": "",
		"active": null,
		"target": null,
		"target_hex": Vector2i.MAX,
		"completion": false,
		"completion_port": {},
		"pass_initiative": false,
		"log": [] as Array[String],
	}
	if note != "":
		out["log"].append(note)
	return out


static func _normalize_code(code: String) -> String:
	var c := code.strip_edges()
	if c.begins_with("Conv"):
		return "C"
	if c.begins_with("X"):
		return "X"
	return c


static func _air_or_attack(state: GameState, graph: MapGraph,
		engine: ActionEngine, side: int) -> Dictionary:
	var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
	if bool(air["ok"]):
		air["log"].append("Solitario AI: Attacco Aereo col bersaglio piu' vulnerabile disponibile.")
		return air
	return _decisive_attack(state, graph, engine, side)


static func _decisive_attack(state: GameState, graph: MapGraph,
		engine: ActionEngine, side: int, code_hint: String = "") -> Dictionary:
	var preferred := _preferred_hunter_for_code(state, side, code_hint)
	if preferred != null:
		return _attack_or_route_selected(state, graph, engine, preferred,
			_best_enemy_target(state, side, preferred),
			"Solitario AI: %s usa la TF indicata dal codice" % code_hint)
	for key in ["ENGAGE", "NAVAL_SEARCH", "STEALTH_ATTACK"]:
		var action := _best_legal_action(state, engine, side, key)
		if bool(action["ok"]):
			action["log"].append("Solitario AI: dichiara %s contro il bersaglio migliore."
				% String(engine.action(key).get("label", key)))
			return action
	var active := _best_hunter(state, side)
	var target := _best_enemy_target(state, side, active)
	if active == null or target == null:
		var no := _empty("Solitario AI: nessuna TF o nessun bersaglio utile; passa.")
		no["pass_initiative"] = true
		return no
	return _route_toward_tf(state, graph, active, target,
		"Solitario AI: rotta di caccia verso %s." % target.display_name())


static func _trajectory_move(state: GameState, graph: MapGraph, side: int) -> Dictionary:
	var active := _best_unidentified(state, side)
	if active == null:
		active = _best_hunter(state, side)
	var target := _best_enemy_target(state, side, active)
	if active == null or target == null:
		var no := _empty("Solitario AI: nessuna rotta utile; passa.")
		no["pass_initiative"] = true
		return no
	return _route_toward_tf(state, graph, active, target,
		"Solitario AI: azione Traiettoria verso %s." % target.display_name())


static func _completion_or_route(state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	var cands := state.forces_of(side)
	cands.sort_custom(func(a: TaskForce, b: TaskForce) -> bool:
		var ac := _has_convoy(a)
		var bc := _has_convoy(b)
		if ac != bc:
			return ac
		var ad := _has_damaged(a)
		var bd := _has_damaged(b)
		if ad != bd:
			return ad
		return a.length() < b.length())
	for tf in cands:
		var opts := Completion.port_options(tf, graph, port_control)
		if Completion.refusal(tf, graph, port_control) == "" and not opts.is_empty():
			var done := _empty("")
			done["ok"] = true
			done["completion"] = true
			done["active"] = tf
			done["completion_port"] = opts[0]
			done["pass_initiative"] = true
			done["log"].append("Solitario AI: %s completa a %s."
				% [tf.display_name(), String(opts[0]["name"])])
			return done
	var active := cands[0] if not cands.is_empty() else null
	if active == null:
		var no := _empty("Solitario AI: nessuna TF da completare; passa.")
		no["pass_initiative"] = true
		return no
	var port := _nearest_friendly_port(graph, port_control, side, _anchor_hex(active))
	if port.is_empty():
		var fallback := _decisive_attack(state, graph, engine, side)
		fallback["log"].append("Solitario AI: nessun porto amico raggiungibile noto, passa alla caccia.")
		return fallback
	return _route_toward_hex(state, graph, active, port["hex"] as Vector2i,
		"Solitario AI: rotta di rientro verso %s." % String(port["name"]))


static func _complete_or_route_to_port(state: GameState, graph: MapGraph,
		port_control: Dictionary, tf: TaskForce, port_name: String,
		note: String) -> Dictionary:
	if tf == null:
		var no_tf := _empty("%s: nessuna TF selezionabile; passa." % note)
		no_tf["pass_initiative"] = true
		return no_tf
	var opts := Completion.port_options(tf, graph, port_control)
	for p in opts:
		if String(p["name"]) == port_name or (port_name == "Clyde" and String(p["name"]) == "Liverpool"):
			var done := _empty("")
			done["ok"] = true
			done["completion"] = true
			done["active"] = tf
			done["completion_port"] = p
			done["pass_initiative"] = true
			done["log"].append("%s: %s completa a %s."
				% [note, tf.display_name(), String(p["name"])])
			return done
	if not graph.ports.has(port_name):
		var unknown := _empty("%s: porto '%s' non calibrato; passa." % [note, port_name])
		unknown["pass_initiative"] = true
		return unknown
	var p2: Dictionary = graph.ports[port_name]
	return _route_toward_hex(state, graph, tf, p2["hex"] as Vector2i, note)


static func _attack_or_route_selected(state: GameState, graph: MapGraph,
		engine: ActionEngine, active: TaskForce, target: TaskForce,
		note: String) -> Dictionary:
	if active == null or target == null:
		var no := _empty("%s: manca una TF o un bersaglio; passa." % note)
		no["pass_initiative"] = true
		return no
	for key in ["ENGAGE", "NAVAL_SEARCH", "STEALTH_ATTACK"]:
		var d := _legal_action_for(state, engine, key, active, target)
		if bool(d["ok"]):
			d["log"].append("%s: azione legale immediata." % note)
			return d
	return _route_toward_tf(state, graph, active, target, note)


static func _legal_action_for(state: GameState, engine: ActionEngine,
		key: String, active: TaskForce, target: TaskForce) -> Dictionary:
	var out := _empty("")
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = active
	dec.target = target
	dec.target_hex = _shared_hex(active, target)
	if dec.target_hex == Vector2i.MAX:
		dec.target_hex = _anchor_hex(target)
	if engine.legality_error(dec, state) != "":
		return out
	out["ok"] = true
	out["action_key"] = key
	out["active"] = active
	out["target"] = target
	out["target_hex"] = dec.target_hex
	return out


static func _best_legal_action(state: GameState, engine: ActionEngine,
		side: int, key: String) -> Dictionary:
	var best := _empty("")
	var best_score := -INF
	for active in state.forces_of(side):
		for target in state.forces_of(1 - side):
			var dec := ActionEngine.Declaration.new()
			dec.action_key = key
			dec.active = active
			dec.target = target
			dec.target_hex = _shared_hex(active, target)
			if dec.target_hex == Vector2i.MAX:
				dec.target_hex = _anchor_hex(target)
			if engine.legality_error(dec, state) != "":
				continue
			var score := _target_score(target) - float(active.info_count()) * 4.0
			if score > best_score:
				best_score = score
				best["ok"] = true
				best["action_key"] = key
				best["active"] = active
				best["target"] = target
				best["target_hex"] = dec.target_hex
				best["pass_initiative"] = false
	if not bool(best["ok"]):
		best["log"].append("Solitario AI: %s non ha bersagli legali." % key)
	return best


static func _route_toward_tf(state: GameState, graph: MapGraph,
		active: TaskForce, target: TaskForce, note: String) -> Dictionary:
	return _route_toward_hex(state, graph, active, _anchor_hex(target), note)


static func _route_toward_hex(state: GameState, graph: MapGraph,
		active: TaskForce, goal: Vector2i, note: String) -> Dictionary:
	var out := _empty("")
	var plan := best_route(state, graph, active, goal)
	out["active"] = active
	out["target_hex"] = goal
	if plan.is_empty():
		out["log"].append("%s Nessuna rotta legale: passa." % note)
		out["pass_initiative"] = true
		return out
	var end := int(plan["end"])
	var steps: Array = plan["steps"]
	var added := 0
	for h_v: Variant in steps:
		if active.length() >= Trajectory.MAX_SEGMENTS:
			break
		var h: Vector2i = h_v
		var info := state.triggers_info(h, active.side)
		if active.trajectory.extend(h, end, graph, state.port_hexes(), info, active.side):
			added += 1
		else:
			break
	out["ok"] = added > 0
	out["pass_initiative"] = true
	out["log"].append("%s %s aggiunge %d segmenti verso %s%s."
		% [note, active.display_name(), added, str(goal),
			" evitando Informazioni quando possibile" if bool(plan["avoids_info"]) else ""])
	return out


static func best_route(state: GameState, graph: MapGraph,
		tf: TaskForce, goal: Vector2i) -> Dictionary:
	if tf == null or not graph.is_playable(goal):
		return {}
	var best := {}
	var best_len := 9999
	for end in [0, 1]:
		var start := tf.trajectory.end_hex(end)
		var r := _path(state, graph, tf, start, goal, true)
		var avoids := true
		if r.is_empty():
			r = _path(state, graph, tf, start, goal, false)
			avoids = false
		if r.is_empty():
			continue
		if r.size() < best_len:
			best_len = r.size()
			best = {"end": end, "steps": r, "avoids_info": avoids}
	return best


static func _path(state: GameState, graph: MapGraph, tf: TaskForce,
		start: Vector2i, goal: Vector2i, avoid_info: bool) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var prev := {start: Vector2i.MAX}
	while not queue.is_empty():
		var cur := queue.pop_front() as Vector2i
		if cur == goal:
			break
		for n in graph.adjacent_hexes(cur):
			if prev.has(n):
				continue
			if not graph.is_adjacent_for(tf.side, cur, n):
				continue
			if state.port_hexes().has(n) and n != goal:
				continue
			if tf.trajectory.occupies(n):
				continue
			if avoid_info and n != goal and state.triggers_info(n, tf.side):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(goal):
		return [] as Array[Vector2i]
	var out: Array[Vector2i] = []
	var h := goal
	while h != start:
		out.push_front(h)
		h = prev[h] as Vector2i
	return out


static func _nearest_friendly_port(graph: MapGraph, port_control: Dictionary,
		side: int, from: Vector2i) -> Dictionary:
	var best := {}
	var bestd := 999999
	for name_v: Variant in graph.ports.keys():
		var p: Dictionary = graph.ports[name_v]
		if not Completion._side_can(Completion.control_of(p, port_control), side):
			continue
		var h := p["hex"] as Vector2i
		var d := Hex.distance(from, h)
		if d < bestd:
			bestd = d
			best = p.duplicate()
			best["name"] = String(name_v)
	return best


static func _nearest_named_port(graph: MapGraph, from: Vector2i,
		names: Array[String]) -> String:
	var best := ""
	var bestd := 999999
	for name in names:
		if not graph.ports.has(name):
			continue
		var h := (graph.ports[name] as Dictionary)["hex"] as Vector2i
		var d := Hex.distance(from, h)
		if d < bestd:
			bestd = d
			best = name
	return best


static func _b1_convoy_destination(graph: MapGraph, tf: TaskForce) -> String:
	var current := _anchor_hex(tf)
	if graph.ports.has("Gibilterra") and current == (graph.ports["Gibilterra"] as Dictionary)["hex"]:
		return "Gibilterra"
	if graph.ports.has("Africa") and current == (graph.ports["Africa"] as Dictionary)["hex"]:
		return "Gibilterra"
	return _nearest_named_port(graph, current, ["Clyde", "Liverpool", "Gibilterra"])


static func _closer_port_to_enemy(graph: MapGraph, state: GameState,
		side: int, names: Array[String]) -> String:
	return _nearest_named_port(graph, _enemy_center(state, side), names)


static func _enemy_center(state: GameState, side: int) -> Vector2i:
	var enemies := state.forces_of(1 - side)
	if enemies.is_empty():
		return Vector2i.ZERO
	return _anchor_hex(enemies[0])


static func _create_unidentified_at(state: GameState, graph: MapGraph,
		side: int, port_name: String) -> TaskForce:
	return _create_force_at(state, graph, side, port_name, [], true)


static func _create_force_at(state: GameState, graph: MapGraph, side: int,
		port_name: String, ships: Array[String], unidentified: bool) -> TaskForce:
	var tf := TaskForce.new(0, side)
	tf.color = _color_for(side)
	tf.slot = _next_slot(state, tf.color)
	tf.name = "%s %s" % ["TF ignota" if unidentified else "TF solitaria", port_name]
	tf.unidentified = unidentified
	for s_name in ships:
		var sh := ShipRoster.shared().make(s_name)
		if sh != null:
			tf.ships.append(sh)
	if not tf.ships.is_empty() or tf.unidentified:
		tf.recompute_speed()
	if graph.ports.has(port_name):
		var p: Dictionary = graph.ports[port_name]
		tf.trajectory.become_station(p["hex"] as Vector2i)
		tf.trajectory.station_port = port_name
	state.add_task_force(tf)
	return tf


static func _color_for(side: int) -> String:
	return "GE" if side == TaskForce.Side.KRIEGSMARINE else "Brown"


static func _next_slot(state: GameState, color: String) -> int:
	var out := 0
	for tf in state.task_forces:
		if tf.color == color:
			out = maxi(out, tf.slot + 1)
	return out


static func _best_hunter(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	var best_score := -9999.0
	for tf in state.forces_of(side):
		var score := _force_score(tf)
		if _has_convoy(tf):
			score -= 8.0
		if score > best_score:
			best_score = score
			best = tf
	return best


static func _preferred_hunter_for_code(state: GameState, side: int,
		code_hint: String) -> TaskForce:
	var h := code_hint.to_upper()
	if h.contains("XU"):
		return _best_unidentified(state, side)
	for type_code in ["BC", "PB", "CA", "BB", "CV"]:
		if h.contains(type_code):
			return _shortest_force_with_type(state, side, type_code)
	return null


static func _shortest_force(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	for tf in state.forces_of(side):
		if best == null or tf.length() < best.length():
			best = tf
	return best


static func _best_non_convoy(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	var best_score := -9999.0
	for tf in state.forces_of(side):
		if _has_convoy(tf):
			continue
		var score := _force_score(tf)
		if score > best_score:
			best_score = score
			best = tf
	return best


static func _best_unidentified(state: GameState, side: int) -> TaskForce:
	for tf in state.forces_of(side):
		if tf.unidentified:
			return tf
	return null


static func _shortest_force_with_convoy(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	for tf in state.forces_of(side):
		if not _has_convoy(tf):
			continue
		if best == null or tf.length() < best.length():
			best = tf
	return best


static func _shortest_force_with_type(state: GameState, side: int,
		type_code: String, exclude_red: bool = false) -> TaskForce:
	var best: TaskForce = null
	for tf in state.forces_of(side):
		if exclude_red and tf.color == "Red":
			continue
		if not _has_type(tf, type_code):
			continue
		if best == null or tf.length() < best.length():
			best = tf
	return best


static func _nearest_force_with_type(state: GameState, side: int,
		type_code: String, from: Vector2i) -> TaskForce:
	var best: TaskForce = null
	var bestd := 999999
	for tf in state.forces_of(side):
		if not _has_type(tf, type_code):
			continue
		var d := Hex.distance(from, _anchor_hex(tf))
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _nearest_heavy_without_convoy(state: GameState, side: int,
		from: Vector2i) -> TaskForce:
	var best: TaskForce = null
	var bestd := 999999
	for tf in state.forces_of(side):
		if _has_convoy(tf):
			continue
		if not (_has_type(tf, "BB") or _has_type(tf, "BC")):
			continue
		var d := Hex.distance(from, _anchor_hex(tf))
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _best_enemy_target(state: GameState, side: int, active: TaskForce) -> TaskForce:
	var best: TaskForce = null
	var best_score := -INF
	var from := _anchor_hex(active) if active != null else Vector2i.ZERO
	for tf in state.forces_of(1 - side):
		var score := _target_score(tf) - float(Hex.distance(from, _anchor_hex(tf))) * 0.25
		if score > best_score:
			best_score = score
			best = tf
	return best


static func _best_convoy_target(state: GameState, side: int, active: TaskForce) -> TaskForce:
	var best: TaskForce = null
	var bestd := 999999
	var from := _anchor_hex(active) if active != null else Vector2i.ZERO
	for tf in state.forces_of(1 - side):
		if not _has_convoy(tf):
			continue
		var d := Hex.distance(from, _anchor_hex(tf))
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _nearest_force_to_convoy(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	var bestd := 999999
	for tf in state.forces_of(side):
		var target := _best_convoy_target(state, side, tf)
		if target == null:
			continue
		var d := Hex.distance(_anchor_hex(tf), _anchor_hex(target))
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _target_score(tf: TaskForce) -> float:
	return _force_score(tf) + (10.0 if _has_convoy(tf) else 0.0) \
		+ (3.0 if tf.unidentified else 0.0)


static func _force_score(tf: TaskForce) -> float:
	if tf == null:
		return -9999.0
	var score := 0.0
	for s in tf.afloat_ships():
		match s.type_code:
			"BB":
				score += 8.0
			"BC":
				score += 7.0
			"PB":
				score += 6.0
			"CA":
				score += 4.0
			"CL":
				score += 3.0
			"CV":
				score += 5.0
			_:
				score += 1.0
		if s.kind == Ship.Kind.CONVOY:
			score += 6.0
		if s.damaged:
			score -= 1.0
	if tf.unidentified:
		score += 2.0
	return score


static func _has_convoy(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s in tf.ships:
		if s.kind == Ship.Kind.CONVOY:
			return true
	return false


static func _has_type(tf: TaskForce, type_code: String) -> bool:
	if tf == null:
		return false
	for s in tf.afloat_ships():
		if s.type_code == type_code:
			return true
	return false


static func _has_undamaged_type(tf: TaskForce, type_code: String) -> bool:
	if tf == null:
		return false
	for s in tf.afloat_ships():
		if s.type_code == type_code and not s.damaged:
			return true
	return false


static func _has_damaged(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s in tf.ships:
		if s.damaged and not s.sunk:
			return true
	return false


static func _first_damaged_force(state: GameState, side: int) -> TaskForce:
	for tf in state.forces_of(side):
		if _has_damaged(tf):
			return tf
	return null


static func _remove_damaged_ships(state: GameState, side: int) -> void:
	for tf in state.forces_of(side):
		var keep: Array[Ship] = []
		for s in tf.ships:
			if not (s.damaged and not s.sunk):
				keep.append(s)
		tf.ships = keep
		tf.recompute_speed()


static func _anchor_hex(tf: TaskForce) -> Vector2i:
	if tf == null:
		return Vector2i.ZERO
	var t := tf.trajectory
	return t.station_hex if t.is_station() else t.end_hex(0)


static func _shared_hex(a: TaskForce, b: TaskForce) -> Vector2i:
	if a == null or b == null:
		return Vector2i.MAX
	var ah := a.trajectory.hexes()
	if a.trajectory.is_station():
		ah.append(a.trajectory.station_hex)
	for h in ah:
		if b.trajectory.occupies(h):
			return h
	return Vector2i.MAX
