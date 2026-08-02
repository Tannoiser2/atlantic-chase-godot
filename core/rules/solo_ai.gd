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
	var normalized := _normalize_code(code)
	match normalized:
		"A":
			out = _air_or_attack(state, graph, engine, side)
		"C":
			out = _completion_or_route(state, graph, engine, port_control, side)
		"T":
			out = _trajectory_move(state, graph, side)
		"X":
			out = _decisive_attack(state, graph, engine, side)
		_:
			out["log"].append("Solitario AI: il codice '%s' non ha ancora una policy automatica." % code)
			out["pass_initiative"] = true
	return out


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
	return c


static func _air_or_attack(state: GameState, graph: MapGraph,
		engine: ActionEngine, side: int) -> Dictionary:
	var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
	if bool(air["ok"]):
		air["log"].append("Solitario AI: Attacco Aereo col bersaglio piu' vulnerabile disponibile.")
		return air
	return _decisive_attack(state, graph, engine, side)


static func _decisive_attack(state: GameState, graph: MapGraph,
		engine: ActionEngine, side: int) -> Dictionary:
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


static func _best_unidentified(state: GameState, side: int) -> TaskForce:
	for tf in state.forces_of(side):
		if tf.unidentified:
			return tf
	return null


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


static func _has_damaged(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s in tf.ships:
		if s.damaged and not s.sunk:
			return true
	return false


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
