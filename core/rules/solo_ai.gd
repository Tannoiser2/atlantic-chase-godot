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

const UK_TYPE_POOLS := {
	"BC": ["Hood", "Renown", "Repulse"],
	"CA": ["Belfast", "Berwick", "Birmingham", "Cornwall", "Cumberland",
		"Devonshire", "Dorsetshire", "Exeter", "London", "Norfolk", "Sheffield",
		"Suffolk"],
	"CL": ["Achilles", "Ajax", "Arethusa", "Aurora", "Galatea", "Hermione",
		"Naiad", "Neptune"],
	"DD": ["DD Squadron"],
}

const GE_TYPE_POOLS := {
	"BC": ["Scharnhorst", "Gneisenau"],
	"PB": ["Graf Spee", "Lutzow", "Scheer"],
	"CA": ["Hipper", "Preugen"],
	"AC": ["Orion", "Widder"],
	"CL": ["Karlsruhe", "Koln", "Konigsberg", "Leipzig", "Nurnburg"],
	"CONVOY": ["Convoy x2"],
}


static func execute_code(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	var out := _empty("Solitario AI: nessuna decisione.")
	var raw := code.strip_edges()
	var normalized := _normalize_code(code)
	if state.scenario_name.begins_with("N1"):
		return _n1(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("N2"):
		return _n2(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("N3"):
		return _n3(normalized, state, graph, engine, port_control, side)
	if state.scenario_name.begins_with("N4"):
		return _n4(normalized, state, graph, engine, port_control, side)
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
		"CONV":
			out = _completion_or_route(state, graph, engine, port_control, side)
		"T":
			out = _trajectory_move(state, graph, side)
		"X":
			out = _decisive_attack(state, graph, engine, side, raw)
		"E":
			out = _empty("Solitario AI: risultato Fine; verifica le condizioni di fine scenario e torna al giocatore.")
			out["pass_initiative"] = true
		_:
			out["log"].append("Solitario AI: il codice '%s' non ha ancora una policy automatica." % code)
			out["pass_initiative"] = true
	return out


## Condizioni di fine stampate, verificate dopo qualunque cambiamento di stato.
## I risultati delle Tabelle Azioni aggiungono condizioni proprie, ma non
## sostituiscono quelle scritte nel riquadro "The End" di ciascuno scenario.
static func enforce_scenario_end(state: GameState) -> bool:
	if state.solo_ended:
		return false
	var reason := ""
	if state.scenario_name.begins_with("BL1"):
		reason = _bl1_end_reason(state)
	elif state.scenario_name.begins_with("BL2"):
		reason = _bl2_end_reason(state)
	if reason == "":
		return false
	state.solo_ended = true
	state.solo_end_reason = reason
	return true


## AC Solo scenarios 2022 p.5: "The scenario ends when there are two or fewer
## Rendezvous markers remaining and the Germans have no Task Forces in play."
## Le due condizioni valgono insieme, non in alternativa.
static func _bl1_end_reason(state: GameState) -> String:
	var remaining := state.active_rendezvous_count()
	if remaining > 2:
		return ""
	if not state.forces_of(TaskForce.Side.KRIEGSMARINE).is_empty():
		return ""
	return ("Restano %d marker Rendezvous (due o meno) e il tedesco non ha "
		+ "piu' Task Force in gioco.") % remaining


## AC Solo scenarios 2022 p.9: due Convogli Completati (britannici e/o
## tedeschi), oppure quattro navi affondate contando i Convogli distrutti.
static func _bl2_end_reason(state: GameState) -> String:
	if state.convoys_completed >= 2:
		return "Due Convogli britannici e/o tedeschi hanno Completato."
	if state.sunk_count(TaskForce.Side.KRIEGSMARINE) \
			+ state.sunk_count(TaskForce.Side.ROYAL_NAVY) >= 4:
		return "Quattro navi, contando i Convogli distrutti, sono state affondate."
	return ""


## Continua una sequenza stampata che richiede piu' azioni senza tirare di
## nuovo la Tabella. Ogni singola azione passa comunque dal normale flusso di
## Iniziativa nella UI prima che questa funzione venga richiamata.
static func continue_follow_up(previous: Dictionary, state: GameState,
		graph: MapGraph, engine: ActionEngine, port_control: Dictionary,
		side: int) -> Dictionary:
	var follow: Dictionary = previous.get("follow_up", {})
	var active: TaskForce = previous.get("active", null)
	if follow.is_empty() or active == null or active.completed:
		return _empty("Solitario AI: nessuna continuazione disponibile.")
	match String(follow.get("kind", "")):
		"attack":
			var target: TaskForce = state.task_force(int(follow.get("target_id", -1)))
			return _attack_or_route_selected(state, graph, engine, active, target,
				String(follow.get("note", "Solitario AI: continua la caccia")))
		"completion":
			return _attempt_completion_at_port(graph, port_control, active,
				String(follow.get("port_name", "")),
				String(follow.get("note", "Solitario AI: continua verso il porto")))
		_:
			return _empty("Solitario AI: continuazione non riconosciuta.")


static func apply_table_result(table_id: String, result: Dictionary,
		state: GameState, graph: MapGraph, engine: ActionEngine,
		port_control: Dictionary, side: int, subject: TaskForce = null) -> Dictionary:
	if state.scenario_name.begins_with("BL1"):
		return _bl1_table_result(table_id, result, state, graph, engine,
			port_control, side, subject)
	if state.scenario_name.begins_with("BL2"):
		return _bl2_table_result(table_id, result, state, subject)
	var out := _empty("Solitario AI: la tabella '%s' e' trascritta ma non ha ancora effetti automatici." % table_id)
	out["pass_initiative"] = false
	return out


## BL1 p.6: il Controllo Rifornimento e' obbligatorio quando il tedesco ha
## l'Iniziativa e una sua Stazione occupa un esagono con un RV attivo.
static func bl1_fueling_candidates(state: GameState) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	if not state.scenario_name.begins_with("BL1") \
			or state.initiative != TaskForce.Side.KRIEGSMARINE:
		return out
	for tf in state.forces_of(TaskForce.Side.KRIEGSMARINE):
		if tf.trajectory.is_station() \
				and not bool(tf.solo_flags.get("bl1_no_more_fueling", false)) \
				and not state.rendezvous_at(tf.trajectory.station_hex).is_empty():
			out.append(tf)
	return out


## Condizioni che lo stato digitale puo' provare senza chiedere al giocatore.
## Ritorna anche le condizioni non modellate: il registro deve distinguere
## chiaramente "non applicabile" da "l'app non possiede ancora quel dato".
static func automatic_modifiers(table: SoloTable, state: GameState,
		imaginary_side: int) -> Dictionary:
	var active: Array[String] = []
	var explanations: Array[String] = []
	var unresolved: Array[String] = []
	for modifier in table.modifiers:
		var label := String(modifier["label"])
		var lower := label.to_lower()
		var side := TaskForce.Side.ROYAL_NAVY if lower.contains("britann") \
			else TaskForce.Side.KRIEGSMARINE
		var count := 0
		if lower.contains("danneggiat"):
			for tf in state.forces_of(side):
				for ship in tf.afloat_ships():
					if ship.damaged and (not lower.contains("non convoglio o dd") \
						or (ship.kind != Ship.Kind.CONVOY and ship.type_code != "DD")):
						count += 1
		if lower.contains("affondat") or lower.contains("distrutt"):
			var sunk := state.sunk_count(side, lower.contains("convogli distrutti") \
				or lower.contains("convoglio distrutto"))
			count = maxi(count, sunk)
		if lower.contains("nessun convoglio ha completato"):
			count = 1 if state.convoys_completed == 0 else 0
		if lower.contains("convoglio in gioco") and lower.contains("disperso"):
			for tf in state.task_forces:
				for ship in tf.afloat_ships():
					if ship.kind == Ship.Kind.CONVOY and ship.dispersed:
						count += 1
		if lower.contains("due o piu' convogli distrutti"):
			count = 1 if state.sunk_count(1 - imaginary_side, true) >= 2 else 0
		# BL2 stampa una sola condizione OR: il -1 si applica una volta, non
		# una volta per ciascuna nave che rende vera la condizione.
		if state.scenario_name.begins_with("BL2") \
				and table.id == "actions_late" and count > 0:
			count = 1
		if lower.contains("base aerea") or lower.contains("mine") \
				or lower.contains("reazione aggressiva") \
				or lower.contains("puo' essere intercettata"):
			unresolved.append(label)
			continue
		for i in count:
			active.append(label)
		if count > 0:
			explanations.append("%s x%d (%+d)" % [label, count,
				int(modifier["value"]) * count])
	return {"active": active, "explanations": explanations,
		"unresolved": unresolved}


static func _bl1_table_result(table_id: String, result: Dictionary,
		state: GameState, graph: MapGraph, engine: ActionEngine,
		port_control: Dictionary, side: int, subject: TaskForce) -> Dictionary:
	var code := String(result.get("code", ""))
	match table_id:
		"identify":
			return _identify_unidentified_tf(state, subject, code,
				"Solitario AI BL1: Identificazione britannica")
		"murmansk":
			return _bl1_murmansk(code, state)
		"fueling":
			return _bl1_fueling(code, state, graph, engine, port_control, subject)
	return _empty("Solitario AI BL1: tabella '%s' non applicabile automaticamente." % table_id)


static func _bl2_table_result(table_id: String, result: Dictionary,
		state: GameState, subject: TaskForce) -> Dictionary:
	var code := String(result.get("code", ""))
	match table_id:
		"identify":
			return _bl2_identify(state, subject, code)
		"incident":
			var out := _empty("")
			out["ok"] = true
			match code:
				"backlash":
					state.add_vp(TaskForce.Side.ROYAL_NAVY, -2.0,
						"BL2 Contraccolpo Politico")
					out["log"].append("Solitario AI BL2: Contraccolpo Politico, -2 VP britannici.")
				"airbase":
					out["log"].append("Solitario AI BL2: la tabella piazza una Base Aerea tedesca a Trondheim; la pedina Base Aerea non e' ancora modellata e l'effetto resta dichiarato.")
				_:
					out["log"].append("Solitario AI BL2: Incidente Internazionale senza effetto negativo.")
			return out
	return _empty("Solitario AI BL2: tabella '%s' non applicabile automaticamente." % table_id)


## Le regole solitarie impongono di identificare immediatamente una TF ignota
## quando le sue navi devono passare alla Mappa di Battaglia. Il tiro e la sua
## applicazione restano qui, nel core, cosi' il flusso non dipende dalla UI.
static func identify_for_battle(opponent: SoloOpponent, state: GameState,
		graph: MapGraph, engine: ActionEngine, port_control: Dictionary,
		tf: TaskForce) -> Dictionary:
	if tf == null or not tf.unidentified:
		return {"ok": true, "needed": false, "roll": {},
			"log": [] as Array[String]}
	if opponent == null:
		return _empty("Identificazione automatica impossibile: modo solitario non caricato.")
	var roll := opponent.identify(state.rng, tf)
	if not bool(roll.get("ok", false)):
		var failed := _empty("Identificazione automatica impossibile: %s"
			% String(roll.get("error", "tabella non disponibile")))
		failed["needed"] = true
		failed["roll"] = roll
		return failed
	var applied := apply_table_result("identify", roll, state, graph, engine,
		port_control, tf.side, tf)
	applied["needed"] = true
	applied["roll"] = roll
	return applied


## BL2 p.9: la Home Fleet parte adiacente a qualunque porto controllato dal
## britannico eccetto Scapa Flow e Methil. Le acque norvegesi sono neutrali,
## quindi i loro porti non entrano nell'elenco tramite port_control.
static func bl2_home_fleet_station_hexes(graph: MapGraph,
		port_control: Dictionary) -> Array[Vector2i]:
	var port_hexes := {}
	for port_v: Variant in graph.ports.values():
		for h_v: Variant in (port_v as Dictionary).get("hexes", []):
			port_hexes[h_v] = true
	var legal: Array[Vector2i] = []
	for pname_v: Variant in graph.ports.keys():
		var pname := String(pname_v)
		if pname == "Scapa Flow" or pname == "Methil":
			continue
		var port: Dictionary = graph.ports[pname]
		if Completion.control_of(port, port_control) != "ROYAL_NAVY":
			continue
		for port_hex_v: Variant in port.get("hexes", []):
			for h in graph.adjacent_hexes(port_hex_v as Vector2i):
				if not port_hexes.has(h) and not legal.has(h):
					legal.append(h)
	legal.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	return legal


static func bl2_is_neutral_water(rules: Dictionary, h: Vector2i) -> bool:
	for h_v: Variant in rules.get("neutral_waters", []):
		var entry: Dictionary = h_v
		if h == Vector2i(int(entry.get("q", 0)), int(entry.get("r", 0))):
			return true
	return false


static func _bl2_identify(state: GameState, tf: TaskForce, code: String) -> Dictionary:
	if tf == null or not tf.unidentified:
		return _empty("Solitario AI BL2: nessuna TF tedesca non identificata selezionata.")
	var specs: Array[String] = []
	if code == "Convoglio" and bool(tf.solo_flags.get("bl2_bring_to_battle", false)):
		specs.assign(["PB", "CA"])
	else:
		specs.append("CONVOY" if code == "Convoglio" else code.to_upper())
	var ships: Array[Ship] = []
	var used := _ship_names_in_play(state)
	for raw_spec in specs:
		var spec := _bl2_identification_replacement(state, raw_spec)
		var ship := _make_available_ship_from_pool(spec, GE_TYPE_POOLS, used)
		if ship == null:
			return _empty("Solitario AI BL2: nessuna nave tedesca disponibile per il tipo %s; composizione non inventata." % spec)
		ships.append(ship)
		used[ship.name] = true
		_bl2_record_type(state, spec)
	tf.ships = ships
	tf.unidentified = false
	tf.recompute_speed()
	var out := _empty("Solitario AI BL2: %s identificata come %s."
		% [tf.display_name(), ", ".join(_ship_names(ships))])
	out["ok"] = true
	out["active"] = tf
	return out


static func _identify_unidentified_tf(state: GameState, tf: TaskForce,
		code: String, note: String) -> Dictionary:
	if tf == null:
		return _empty("%s: nessuna TF selezionata." % note)
	if not tf.unidentified:
		return _empty("%s: %s e' gia' identificata." % [note, tf.display_name()])
	var specs := code.split("/", false)
	var ships: Array[Ship] = []
	var used := _ship_names_in_play(state)
	for spec_v in specs:
		var spec := String(spec_v).strip_edges().to_upper()
		var sh := _make_available_ship(spec, used)
		if sh != null:
			ships.append(sh)
			used[sh.name] = true
	if ships.is_empty():
		return _empty("%s: codice '%s' senza nave disponibile nel ruolino." % [note, code])
	tf.ships = ships
	tf.unidentified = false
	tf.recompute_speed()
	var out := _empty("%s: %s rivela %s." % [note, tf.display_name(),
		", ".join(_ship_names(ships))])
	out["ok"] = true
	out["active"] = tf
	return out


static func _make_available_ship(type_code: String, used: Dictionary) -> Ship:
	var pool: Array = UK_TYPE_POOLS.get(type_code, [])
	for name_v: Variant in pool:
		var name := String(name_v)
		if used.has(name):
			continue
		var sh := ShipRoster.shared().make(name)
		if sh != null:
			return sh
	return null


static func _ship_names_in_play(state: GameState) -> Dictionary:
	var used := {}
	for tf in state.task_forces:
		for s in tf.ships:
			used[s.name] = true
	return used


static func _ship_names(ships: Array[Ship]) -> Array[String]:
	var out: Array[String] = []
	for s in ships:
		out.append(s.display())
	return out


static func _bl1_murmansk(code: String, state: GameState) -> Dictionary:
	var out := _empty("")
	match code:
		"confisca":
			state.add_vp(TaskForce.Side.KRIEGSMARINE, -3.0, "BL1 Murmansk: confisca")
			out["log"].append("Solitario AI BL1 Murmansk: confisca, -3 VP tedeschi.")
		"incidente":
			state.add_vp(TaskForce.Side.KRIEGSMARINE, -1.0, "BL1 Murmansk: incidente")
			out["log"].append("Solitario AI BL1 Murmansk: Incidente Internazionale, -1 VP tedesco.")
		"salvi":
			out["log"].append("Solitario AI BL1 Murmansk: rifornimento riuscito senza perdita di VP.")
		_:
			out["log"].append("Solitario AI BL1 Murmansk: codice '%s' non riconosciuto." % code)
			return out
	out["ok"] = true
	return out


static func _bl1_fueling(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, tf: TaskForce) -> Dictionary:
	if tf == null:
		return _empty("Solitario AI BL1 Rifornimento: seleziona una TF tedesca.")
	if tf.side != TaskForce.Side.KRIEGSMARINE:
		return _empty("Solitario AI BL1 Rifornimento: %s non e' tedesca." % tf.display_name())
	if not tf.trajectory.is_station():
		return _empty("Solitario AI BL1 Rifornimento: %s non e' una Stazione." % tf.display_name())
	var h := tf.trajectory.station_hex
	if bool(tf.solo_flags.get("bl1_no_more_fueling", false)):
		return _empty("Solitario AI BL1 Rifornimento: %s non puo' effettuare altri Controlli." % tf.display_name())
	if state.rendezvous_at(h).is_empty():
		return _empty("Solitario AI BL1 Rifornimento: nessun marker RV attivo in %s." % str(h))
	var out := _empty("Solitario AI BL1 Rifornimento %s su %s." % [code, tf.display_name()])
	var rv_removed := false
	match code:
		"a":
			rv_removed = state.remove_rendezvous_at(h)
			_repair_one_hit(tf, out)
			tf.solo_flags["bl1_completion_port"] = "South America"
			tf.solo_flags["bl1_no_reorganize"] = true
			tf.solo_flags["bl1_no_more_fueling"] = true
			out["log"].append("Nuovo obiettivo: %s potra' Completare solo in South America." % tf.display_name())
			_bl1_british_in_hex_effect(state, h, tf, out)
		"b":
			rv_removed = state.remove_rendezvous_at(h)
			if _count_convoys_in_play(state, TaskForce.Side.ROYAL_NAVY) < 3:
				var conv := _create_force_at(state, graph, TaskForce.Side.ROYAL_NAVY,
					"Bordeaux", ["Convoy x3"], false)
				var cl := _make_available_ship("CL", _ship_names_in_play(state))
				if cl != null:
					conv.ships.append(cl)
					conv.recompute_speed()
				out["log"].append("News: creata TF Convoglio britannica Bordeaux-Africa.")
				var r := _complete_or_route_to_port(state, graph, port_control, conv,
					"Africa", "Solitario AI BL1 Rifornimento b")
				out["log"].append_array(r.get("log", []))
		"c":
			_move_rv_by_policy(state, graph, h, tf, out)
			if _enemy_in_same_hex(state, tf.side, tf) == null:
				out["initiative"] = "vie"
				out["log"].append("Policy digitale BL1: va tentato Cercare l'Iniziativa.")
			else:
				out["international_incident"] = true
				out["log"].append("Incidente Internazionale: TF britannica nell'esagono.")
		"d":
			rv_removed = state.remove_rendezvous_at(h)
			tf.evasive = false
			tf.solo_flags["bl1_mechanical_problems"] = true
			tf.solo_flags["bl1_actions_only"] = ["TRAJECTORY", "COMPLETION", "PASS"]
			tf.solo_flags["bl1_no_evasive"] = true
			out["log"].append("Guasti meccanici: consentite solo Traiettoria, Completamento e Passare.")
			if _enemy_in_same_hex(state, tf.side, tf) != null:
				out["initiative"] = "vie"
		"e":
			rv_removed = state.remove_rendezvous_at(h)
			if state.weather == TimeLapse.Weather.GOOD:
				tf.evasive = false
				out["log"].append("Meteo buono: rimosse Manovre Evasive, se presenti.")
		"f":
			rv_removed = state.remove_rendezvous_at(h)
			out["log"].append("Nessun altro effetto.")
		"g":
			_move_rv_by_policy(state, graph, h, tf, out)
			if _enemy_in_same_hex(state, tf.side, tf) != null:
				out["initiative"] = "vie"
		_:
			out["log"].append("Codice Rifornimento non riconosciuto: %s." % code)
			return out
	if rv_removed:
		out["log"].append("Marker RV rimosso dall'esagono %s." % str(h))
	elif ["a", "b", "d", "e", "f"].has(code):
		out["log"].append("Nessun marker RV calibrato in %s: effetto applicato alla TF, marker non rimosso." % str(h))
	out["ok"] = true
	return out


static func _repair_one_hit(tf: TaskForce, out: Dictionary) -> void:
	for s in tf.ships:
		if s.hits > 0:
			s.hits -= 1
			out["log"].append("Riparato 1 Colpo da %s." % s.name)
			return
	out["log"].append("Nessun Colpo da riparare.")


static func _count_convoys_in_play(state: GameState, side: int) -> int:
	var n := 0
	for tf in state.forces_of(side):
		if _has_convoy(tf):
			n += 1
	return n


static func _bl1_british_in_hex_effect(state: GameState, h: Vector2i,
		tf: TaskForce, out: Dictionary) -> void:
	if _enemy_in_same_hex(state, tf.side, tf) == null:
		return
	if tf.trajectory.station_contact:
		state.add_info_trigger(h, "side:1")
		out["log"].append("TF britannica presente: Contatto gia' presente, aggiunta base aerea britannica.")
	else:
		tf.trajectory.station_contact = true
		out["log"].append("TF britannica presente: assegnato Contatto alla TF tedesca.")


static func _move_rv_by_policy(state: GameState, graph: MapGraph, from: Vector2i,
		tf: TaskForce, out: Dictionary) -> void:
	var best := Vector2i.MAX
	var bestd := 999999
	var target := _enemy_center(state, tf.side)
	for h in graph.adjacent_hexes(from):
		if not graph.is_playable(h) or state.port_hexes().has(h):
			continue
		var d := Hex.distance(h, target)
		if d < bestd:
			bestd = d
			best = h
	if best == Vector2i.MAX:
		out["log"].append("Policy digitale BL1: nessun esagono adiacente valido per spostare l'RV.")
		return
	if state.move_rendezvous_at(from, best):
		out["log"].append("Policy digitale BL1: RV spostato da %s a %s." % [str(from), str(best)])
	else:
		out["log"].append("Nessun marker RV calibrato in %s: spostamento registrato solo nel log." % str(from))


static func _n1(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"C":
			var tf := _first_damaged_force(state, side)
			if tf == null:
				tf = _shortest_force_with_convoy(state, side)
			if tf == null:
				tf = _shortest_force(state, side)
			if tf == null:
				return _n1("M", state, graph, engine, port_control, side)
			var port := "Kiel" if _has_damaged(tf) or _has_convoy(tf) \
				else _n1_port_table(state)
			return _complete_or_route_to_port(state, graph, port_control, tf, port,
				"Solitario AI N1: Completamento tedesco")
		"D":
			var tf_d := _nearest_eligible_denmark_strait_force(state, side)
			if tf_d == null:
				tf_d = _create_force_at(state, graph, side, "Kiel", ["Scheer"], false)
			return _route_toward_hex(state, graph, tf_d, _denmark_strait_reference(graph),
				"Solitario AI N1: D verso il riferimento calibrato del Denmark Strait")
		"I":
			var tf_i := _nearest_force_to_port(state, side, graph, "Narvik")
			if tf_i == null:
				tf_i = _create_unidentified_at(state, graph, side, "Kiel")
			return _attack_or_route_selected(state, graph, engine, tf_i,
				_n1_interception_target(state, graph, side),
				"Solitario AI N1: Intercettazione tedesca")
		"M":
			return _n_complete_with_priority(state, graph, port_control, side,
				"Murmansk", "Solitario AI N1: rotta/Completamento a Murmansk")
		"N":
			return _n_complete_with_priority(state, graph, port_control, side,
				"Narvik", "Solitario AI N1: rotta/Completamento a Narvik")
		"T":
			return _n_complete_with_priority(state, graph, port_control, side,
				"Trondheim", "Solitario AI N1: rotta/Completamento a Trondheim")
		"X":
			_remove_damaged_ships(state, side)
			var tf_x := _best_type_priority(state, side, ["BC", "PB", "CA"])
			if tf_x == null or _has_convoy(tf_x):
				tf_x = _create_unidentified_at(state, graph, side, "Kiel")
			return _attack_or_route_selected(state, graph, engine, tf_x,
				_n1_battle_target(state, graph, side),
				"Solitario AI N1: Bring on Battle")
	return _completion_or_route(state, graph, engine, port_control, side)


static func _n2(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"AA":
			return _n_british_port_action(state, graph, engine, port_control, side,
				"Bergen", "Andalsnes", "Solitario AI N2: AA")
		"BD":
			return _n_british_port_action(state, graph, engine, port_control, side,
				"Trondheim", "Bud", "Solitario AI N2: Bd")
		"C":
			var tf_c := _first_damaged_force(state, side)
			if tf_c == null:
				tf_c = _longest_force(state, side)
			return _complete_or_route_to_port(state, graph, port_control, tf_c,
				"Scapa Flow", "Solitario AI N2: Completamento a Scapa Flow")
		"N":
			return _n_british_port_action(state, graph, engine, port_control, side,
				"Narvik", "Narvik", "Solitario AI N2: N")
		"P":
			var out := _empty("Solitario AI N2: Passare.")
			out["pass_initiative"] = true
			return out
		"R4":
			return _n2_r4(state, graph, engine, side)
		"T":
			return _n_british_port_action(state, graph, engine, port_control, side,
				"Trondheim", "Trondheim", "Solitario AI N2: T")
		"X":
			var bb := _shortest_force_with_type(state, side, "BB")
			if bb == null:
				bb = _create_force_at(state, graph, side, "Scapa Flow",
					["Nelson", "Rodney", "Belfast"], false)
			return _attack_or_route_selected(state, graph, engine, bb,
				_best_contact_or_port_target(state, graph, side, "Narvik"),
				"Solitario AI N2: Bring to Battle")
		"MINE":
			return _marker_not_modeled("Solitario AI N2: posa Mine britanniche")
	return _air_or_attack(state, graph, engine, side)


static func _n3(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"B":
			return _n_british_port_action(state, graph, engine, port_control, side,
				"Bergen", "Bergen", "Solitario AI N3: B")
		"C":
			var tf_c := _first_damaged_force(state, side)
			if tf_c == null:
				tf_c = _longest_force(state, side)
			if tf_c == null:
				var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
				if bool(air["ok"]):
					return air
				var no := _empty("Solitario AI N3: nessuna TF britannica; Passare.")
				no["pass_initiative"] = true
				return no
			return _complete_or_route_to_port(state, graph, port_control, tf_c,
				"Scapa Flow", "Solitario AI N3: Completamento a Scapa Flow")
		"SA":
			var stealth := _best_legal_action(state, engine, side, "STEALTH_ATTACK")
			if bool(stealth["ok"]):
				stealth["log"].append("Solitario AI N3: Attacco Furtivo.")
				return stealth
			return _n3_sr(state, graph, side)
		"SR":
			return _n3_sr(state, graph, side)
		"X":
			var bb := _shortest_force_with_type(state, side, "BB")
			if bb == null:
				bb = _create_force_at(state, graph, side, "Scapa Flow",
					["Nelson", "Rodney", "Renown", "Sheffield", "Birmingham"], false)
			_remove_damaged_ships(state, side)
			return _attack_or_route_selected(state, graph, engine, bb,
				_best_enemy_target(state, side, bb),
				"Solitario AI N3: Bring on Battle")
	return _air_or_attack(state, graph, engine, side)


static func _n4(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"C":
			var tf_c := _shortest_force_with_convoy(state, side)
			if tf_c == null:
				tf_c = _first_damaged_force(state, side)
			if tf_c == null:
				var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
				if bool(air["ok"]):
					return air
				tf_c = _longest_force(state, side)
			var port := "Methil" if _has_convoy(tf_c) else "Scapa Flow"
			return _complete_or_route_to_port(state, graph, port_control, tf_c, port,
				"Solitario AI N4: Completamento britannico")
		"CONV":
			var convoy := _shortest_force_with_convoy(state, side)
			if convoy == null:
				convoy = _create_force_at(state, graph, side, "Bergen",
					["Convoy x3"], false)
			return _complete_or_route_to_port(state, graph, port_control, convoy,
				"Methil", "Solitario AI N4: Convoglio britannico")
		"MINE":
			return _marker_not_modeled("Solitario AI N4: Mine/Base Aerea britannica")
		"R4":
			return _n4_r4(state, graph, engine, port_control, side)
		"SA":
			var stealth := _best_legal_action(state, engine, side, "STEALTH_ATTACK")
			if bool(stealth["ok"]):
				stealth["log"].append("Solitario AI N4: Attacco Furtivo.")
				return stealth
			var no := _empty("Solitario AI N4: nessun bersaglio furtivo; All Pass.")
			no["pass_initiative"] = true
			return no
		"X":
			return _n4_x(state, graph, engine, side)
	return _air_or_attack(state, graph, engine, side)


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


## Quanti Convogli britannici hanno Completato in BL1. E' il conto che regola
## sia la riga della Tabella Azioni sia le due soglie dei Limiti di Carburante.
static func bl1_british_convoy_completions(state: GameState) -> int:
	return state.convoys_completed_for(TaskForce.Side.ROYAL_NAVY)


## Limiti di Carburante (AC Solo scenarios 2022 p.8): li invoca la Tabella
## delle Azioni Britanniche, con la riga "End?" dei risultati F e X. Da quel
## momento le uniche azioni permesse al tedesco sono Completamento, Passare e
## Traiettoria. Non e' la fine dello scenario: e' un cambio di regime.
static func _bl1_fuel_limits(state: GameState, threshold: int,
		out: Dictionary) -> void:
	if bool(state.solo_counters.get("bl1_fuel_limits", false)):
		return
	if bl1_british_convoy_completions(state) < threshold:
		return
	state.solo_counters["bl1_fuel_limits"] = true
	out["log"].append(("Fine? %d Convogli britannici hanno Completato: da ora "
		+ "valgono i Limiti di Carburante. Il tedesco puo' solo Completamento, "
		+ "Passare e Traiettoria.") % threshold)


## Il fascicolo p.7 fa dipendere il ramo di Meteo Cattivo dalla presenza di un
## CA britannico: con un CA in gioco e' una 'X' (e la TF con il CA e' quella
## scelta), senza CA e' una 'B'. La versione precedente andava sempre su 'X',
## e con nessun CA in gioco il Blocco non veniva mai creato.
static func _bl1_has_british_ca(state: GameState, side: int) -> TaskForce:
	for tf in state.forces_of(side):
		if _has_type(tf, "CA"):
			return tf
	return null


static func _bl1(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"A":
			if state.weather == TimeLapse.Weather.BAD:
				var with_ca := _bl1_has_british_ca(state, side)
				if with_ca == null:
					var blockade := _bl1("B", state, graph, engine, port_control, side)
					blockade["log"].append("Solitario AI BL1: Meteo Cattivo senza "
						+ "nessun CA britannico in gioco: la 'A' diventa una 'B'.")
					return blockade
				var decisive := _attack_or_route_selected(state, graph, engine,
					with_ca, _best_enemy_target(state, side, with_ca),
					"Solitario AI BL1: Meteo Cattivo, la 'A' diventa una 'X' con la TF che ha il CA")
				_bl1_fuel_limits(state, 2, decisive)
				return decisive
			var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
			if bool(air["ok"]):
				air["log"].append("Solitario AI BL1: col meteo buono prova l'Attacco Aereo.")
				return air
			# "4+ CAs? If there are four or more British CAs in play, and there
			# is no target for an Air Strike, treat this as BOTH an 'A' and an
			# 'F' result. The French TF will be the Active TF and the British
			# TF the Coordinating TF." (p.7)
			var french_tf := _force_with_ship_name(state, side, "Dunkerque")
			if _count_ships_of_type(state, side, "CA") >= 4 and french_tf != null:
				var coordinating := _nearest_force_with_type(state, side, "CA",
					_enemy_center(state, side))
				var german_target := _best_enemy_target(state, side, french_tf)
				if german_target != null:
					var both := _attack_or_route_selected(state, graph, engine,
						french_tf, german_target,
						"Solitario AI BL1: quattro o piu' CA e nessun bersaglio aereo, 'A' e 'F' insieme")
					if coordinating != null and coordinating != french_tf:
						both["coordinating"] = coordinating
						both["log"].append(("La TF francese e' l'Attiva, %s e' la "
							+ "Coordinatrice.") % coordinating.display_name())
					_bl1_fuel_limits(state, 3, both)
					return both
			var ca := _nearest_force_with_type(state, side, "CA", _enemy_center(state, side))
			if ca == null:
				ca = _create_unidentified_at(state, graph, side, "Portsmouth")
			return _attack_or_route_selected(state, graph, engine, ca,
				_best_enemy_target(state, side, ca), "Solitario AI BL1: caccia con CA/TF Portsmouth")
		"C":
			var removed := _remove_damaged_ships_of_side(state, side, "BL1",
				"bl1_removed_ships")
			var convoy := _shortest_force_with_convoy(state, side)
			if convoy == null:
				var as_convoy := _bl1("CONV", state, graph, engine, port_control, side)
				(as_convoy["log"] as Array).append_array(removed)
				as_convoy["log"].append("Solitario AI BL1: nessun Convoglio in gioco: la 'C' diventa un risultato Convoglio.")
				return as_convoy
			var port := _nearest_named_port(graph, _anchor_hex(convoy),
				["Clyde", "Liverpool", "Portsmouth"])
			var completion := _complete_or_route_to_port(state, graph, port_control,
				convoy, port,
				"Solitario AI BL1: Convoglio verso il porto britannico piu' vicino")
			(completion["log"] as Array).append_array(removed)
			if bool(completion.get("completion", false)):
				_bl1_international_incident(state, completion)
			return completion
		"CONV":
			# CONVOGLIO (p.7). Il fascicolo stampa due rami distinti, e finora
			# nessuno dei due era implementato: il codice cadeva nel ripiego
			# generico `_completion_or_route`, che non tira il dado e non crea
			# la nuova TF.
			var convoy_removed := _remove_damaged_ships_of_side(state, side,
				"BL1", "bl1_removed_ships")
			var existing := _shortest_force_with_convoy(state, side)
			if existing != null:
				var branch := state.rng.d6("Solitario BL1 Convoglio")
				var redirect := "A" if branch <= 2 else ("C" if branch <= 5 else "F")
				var result := _bl1(redirect, state, graph, engine, port_control, side)
				(result["log"] as Array).append_array(convoy_removed)
				result["log"].append(("Solitario AI BL1 Convoglio: c'e' gia' una TF "
					+ "con un Convoglio; 1d6=%d -> risultato '%s'.")
					% [branch, redirect])
				return result
			var where := state.rng.d6("Solitario BL1 nuovo Convoglio")
			var origin := "Africa" if where % 2 == 0 else "Halifax"
			if not graph.ports.has(origin):
				var gap := _empty(("Solitario AI BL1 Convoglio: il porto %s non e' "
					+ "nel grafo calibrato; nessuna TF creata.") % origin)
				gap["pass_initiative"] = true
				(gap["log"] as Array).append_array(convoy_removed)
				return gap
			var new_tf := _create_force_at(state, graph, side, origin,
				["Convoy x3"], false)
			var escort := _make_available_ship("CL", _ship_names_in_play(state))
			if escort != null:
				new_tf.ships.append(escort)
				new_tf.recompute_speed()
			var destination := _nearest_named_port(graph, _anchor_hex(new_tf),
				["Portsmouth", "Clyde", "Liverpool"])
			var route := _complete_or_route_to_port(state, graph, port_control,
				new_tf, destination,
				"Solitario AI BL1 Convoglio: nuova TF verso il porto britannico piu' vicino")
			(route["log"] as Array).append_array(convoy_removed)
			route["log"].append(("Solitario AI BL1 Convoglio: 1d6=%d (%s) -> nuova TF "
				+ "in %s con Convoglio%s.") % [where,
				"PARI" if where % 2 == 0 else "DISPARI", origin,
				" e " + escort.name if escort != null else ""])
			_bl1_international_incident(state, route)
			return route
		"B":
			# AC Solo scenarios 2022 p.7: il cilindro rosso e' nel primo
			# esagono a NE di Scapa Flow. La griglia calibrata lo identifica
			# come (16,-6); non e' una posizione dedotta dalla geografia.
			var blockade_hex := Vector2i(16, -6)
			for tf in state.forces_of(side):
				if tf.trajectory.is_station() \
						and tf.trajectory.station_hex == blockade_hex:
					return _bl1("X", state, graph, engine, port_control, side)
			var ships: Array[String] = []
			var used := _ship_names_in_play(state)
			for i in 3:
				var ca := _make_available_ship("CA", used)
				if ca != null:
					ships.append(ca.name)
					used[ca.name] = true
			var block := _create_force_in_hex(state, side, blockade_hex, ships,
				"Blocco britannico")
			var out := _empty("Solitario AI BL1 - B: creata %s con tre CA in %s; "
				% [block.display_name(), str(blockade_hex)]
				+ "la procedura ordina un altro tiro immediato sulla Tabella Azioni.")
			out["ok"] = true
			out["active"] = block
			out["target_hex"] = blockade_hex
			out["turn_kind"] = "setup"
			out["roll_again"] = true
			return out
		"F":
			# "End? If three British Convoys have successfully Completed, Fuel
			# Limits are now in effect" (p.8): la verifica viene prima
			# dell'azione, e vale anche se poi la procedura ripiega su 'C'.
			var french_out := _empty("")
			_bl1_fuel_limits(state, 3, french_out)
			var french := _force_with_ship_name(state, side, "Dunkerque")
			var german := _best_enemy_target(state, side, french) if french != null \
				else null
			var french_result := _bl1("C", state, graph, engine, port_control, side) \
				if french == null or german == null \
				else _attack_or_route_selected(state, graph, engine, french, german,
					"Solitario AI BL1: Azione francese verso la TF tedesca piu' vicina a un Convoglio")
			(french_result["log"] as Array).append_array(french_out["log"])
			return french_result
		"X":
			var decisive_out := _empty("")
			_bl1_fuel_limits(state, 2, decisive_out)
			var bc := _shortest_force_with_type(state, side, "BC", true)
			if bc == null:
				bc = _best_unidentified(state, side)
			if bc == null:
				bc = _create_unidentified_at(state, graph, side,
					_closer_port_to_enemy(graph, state, side, ["Scapa Flow", "Gibilterra"]))
			var decisive_result := _attack_or_route_selected(state, graph, engine, bc,
				_best_enemy_target(state, side, bc),
				"Solitario AI BL1: azione decisiva con BC/TF ignota")
			(decisive_result["log"] as Array).append_array(decisive_out["log"])
			return decisive_result
		_:
			return _completion_or_route(state, graph, engine, port_control, side)


static func _bl2(code: String, state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	match code:
		"A":
			var removed_log := _bl2_remove_damaged_ships(state, side)
			if state.weather == TimeLapse.Weather.BAD:
				var bad := _bl2("T", state, graph, engine, port_control, side)
				bad["log"].append_array(removed_log)
				return bad
			var air := _best_legal_action(state, engine, side, "AIR_STRIKE")
			if bool(air["ok"]):
				air["log"].append("Solitario AI BL2: col meteo buono prova l'Attacco Aereo.")
				air["log"].append_array(removed_log)
				return air
			var no_target_roll := state.rng.d6("Solitario BL2 A senza bersaglio")
			if no_target_roll <= 2:
				var convoy := _create_force_at(state, graph, side, "South America",
					["Convoy x2"], false)
				var gap := _empty("Solitario AI BL2: A senza bersaglio, 1d6=%d: creato un Convoglio in South America. La rotta stampata Azzorre-Faroe non ha esagoni calibrati nel grafo; il bot non inventa la posizione e non tira di nuovo la Tabella." % no_target_roll)
				gap["ok"] = true
				gap["active"] = convoy
				gap["turn_kind"] = "declared_gap"
				gap["pass_initiative"] = true
				gap["log"].append_array(removed_log)
				return gap
			var x := _bl2("X", state, graph, engine, port_control, side)
			x["log"].append("Solitario AI BL2: A senza bersaglio, 1d6=%d: tratta come X." % no_target_roll)
			x["log"].append_array(removed_log)
			return x
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
		"CONV":
			var convoy_tf := _shortest_force_with_convoy(state, side)
			if convoy_tf == null:
				convoy_tf = _create_force_at(state, graph, side, "Narvik",
					["Convoy x2"], false)
			return _complete_or_route_to_port(state, graph, port_control, convoy_tf,
				"Kiel", "Solitario AI BL2: risultato Convoglio verso Kiel")
		"T":
			var tf_t := _best_unidentified(state, side)
			if tf_t == null:
				tf_t = _create_unidentified_at(state, graph, side, "Murmansk")
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
		"E":
			return _bl2_end_action(state, graph, engine, port_control, side)
		"X":
			var tf_x := _shortest_force_with_type(state, side, "BC")
			if tf_x == null:
				tf_x = _best_non_convoy(state, side)
			if tf_x == null:
				var r := state.rng.d6("Solitario BL2 nuova TF X")
				tf_x = _create_unidentified_at(state, graph, side,
					"Kiel" if r <= 4 else ("Narvik" if r == 5 else "South America"))
				tf_x.solo_flags["bl2_bring_to_battle"] = true
			if _has_damaged(tf_x):
				var damaged_port := "South America" if _has_undamaged_type(tf_x, "PB") else "Kiel"
				return _complete_or_route_to_port(state, graph, port_control, tf_x,
					damaged_port, "Solitario AI BL2: X danneggiata trattata come C con la stessa TF")
			var convoy_target := _best_convoy_target(state, side, tf_x)
			if convoy_target == null:
				return _bl2("E", state, graph, engine, port_control, side)
			return _attack_or_route_selected(state, graph, engine, tf_x, convoy_target,
				"Solitario AI BL2: X punta al Convoglio britannico")
		_:
			return _completion_or_route(state, graph, engine, port_control, side)


static func _bl2_end_action(state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	var count := int(state.solo_counters.get("bl2_e_results", 0)) + 1
	state.solo_counters["bl2_e_results"] = count
	if state.weather == TimeLapse.Weather.BAD:
		var german_convoy := _shortest_force_with_convoy(state, side)
		if german_convoy != null:
			_bl2_automatic_convoy_completion(state, german_convoy)
			return _bl2_end(state, "Meteo Cattivo: un Convoglio tedesco Completa automaticamente.")
		if state.sunk_count(TaskForce.Side.KRIEGSMARINE) \
				+ state.sunk_count(TaskForce.Side.ROYAL_NAVY) >= 2:
			return _bl2_end(state, "Meteo Cattivo: almeno due navi o Convogli sono stati distrutti.")
	var target := _shortest_force_with_convoy(state, 1 - side)
	if target == null:
		return _bl2_end(state, "Non ci sono Convogli britannici in gioco.")
	var bc_tf := _shortest_force_with_type(state, side, "BC")
	if bc_tf == null:
		bc_tf = _create_force_at(state, graph, side, "Wilhelmshaven",
			["Scharnhorst"], false)
		_bl2_record_type(state, "BC")
	elif _count_type(bc_tf, "BC") < 2:
		var used := _ship_names_in_play(state)
		var second := _make_available_ship_from_pool("BC", GE_TYPE_POOLS, used)
		if second != null:
			bc_tf.ships.append(second)
			bc_tf.recompute_speed()
			_bl2_record_type(state, "BC")
	else:
		var remove_index := -1
		for i in bc_tf.ships.size():
			var ship: Ship = bc_tf.ships[i]
			if ship.type_code == "BC" and ship.damaged:
				remove_index = i
				break
		if remove_index < 0:
			for i in bc_tf.ships.size():
				if (bc_tf.ships[i] as Ship).type_code == "BC":
					remove_index = i
					break
		if remove_index >= 0:
			bc_tf.ships.remove_at(remove_index)
			bc_tf.recompute_speed()
	bc_tf.solo_flags["bl2_bring_to_battle"] = true
	var action := _attack_or_route_selected(state, graph, engine, bc_tf, target,
		"Solitario AI BL2: E porta il BC contro il Convoglio britannico piu' vicino")
	action["log"].append("Solitario AI BL2: risultato E numero %d." % count)
	return action


static func _bl2_end(state: GameState, reason: String) -> Dictionary:
	state.solo_ended = true
	state.solo_end_reason = reason
	var out := _empty("Solitario AI BL2 - FINE SCENARIO: %s Vai al Debriefing." % reason)
	out["ok"] = true
	out["turn_kind"] = "end"
	out["end_scenario"] = true
	return out


static func _bl2_automatic_convoy_completion(state: GameState, tf: TaskForce) -> void:
	var names: Array[String] = []
	for ship in tf.ships:
		names.append(ship.name)
	tf.completed_ships = names
	tf.ships.clear()
	tf.completed = true
	tf.completed_port = "automatico BL2-E"
	state.count_convoy_completed(tf.side)
	state.add_vp(TaskForce.Side.ROYAL_NAVY, -2.0,
		"BL2 Convoglio tedesco Completato automaticamente")


static func _bl2_remove_damaged_ships(state: GameState, side: int) -> Array[String]:
	return _remove_damaged_ships_of_side(state, side, "BL2", "bl2_removed_ships")


## "Remove Damaged British ships. If this empties a TF, remove it." Compare
## identica in BL1 (risultati C e Convoglio, p.7) e in BL2 (risultato A, p.10).
##
## La nave rimossa NON e' affondata: le tabelle degli Esiti la contano fra le
## Danneggiate ("damaged, includes removed ships"), e il registro deve dirlo,
## se no il conto dei VP a fine partita sembra sbagliato.
static func _remove_damaged_ships_of_side(state: GameState, side: int,
		label: String, counter_key: String) -> Array[String]:
	var lines: Array[String] = []
	var removed := 0
	for tf in state.forces_of(side).duplicate():
		var keep: Array[Ship] = []
		for ship in tf.ships:
			if ship.damaged and not ship.sunk:
				removed += 1
				lines.append(("Solitario AI %s: rimossa %s Danneggiata da %s; "
					+ "conta come Danneggiata, non affondata, per i VP.")
					% [label, ship.name, tf.display_name()])
			else:
				keep.append(ship)
		tf.ships = keep
		tf.recompute_speed()
		if tf.ships.is_empty() and not tf.unidentified:
			state.remove_task_force(tf)
	state.solo_counters[counter_key] = \
		int(state.solo_counters.get(counter_key, 0)) + removed
	return lines


## Incidente Internazionale in BL1 (p.4): "There is no immediate effect ... but
## it may have an effect on the Action Table and on Debriefing". Non c'e' una
## tabella da tirare come in BL2: si tiene il conto, e basta.
static func _bl1_international_incident(state: GameState,
		out: Dictionary) -> void:
	var n := int(state.solo_counters.get("bl1_international_incidents", 0)) + 1
	state.solo_counters["bl1_international_incidents"] = n
	out["log"].append(("Incidente Internazionale numero %d. In BL1 non ha "
		+ "effetto immediato: pesa sul Debriefing.") % n)


static func _bl2_identification_replacement(state: GameState, spec: String) -> String:
	var out := spec
	var threshold := 999
	if spec == "AC":
		threshold = 1
	elif spec == "PB" or spec == "CA":
		threshold = 2
	if _bl2_type_history(state, spec) >= threshold:
		out = "BC"
	if out == "BC" and _bl2_type_history(state, "BC") >= 2:
		out = "CL"
	return out


static func _bl2_type_history(state: GameState, type_code: String) -> int:
	var current := 0
	for tf in state.task_forces:
		current += _count_type(tf, type_code)
	return maxi(current, int(state.solo_counters.get("bl2_type_%s" % type_code, 0)))


static func _bl2_record_type(state: GameState, type_code: String) -> void:
	var key := "bl2_type_%s" % type_code
	state.solo_counters[key] = int(state.solo_counters.get(key, 0)) + 1


static func _count_type(tf: TaskForce, type_code: String) -> int:
	var count := 0
	if tf != null:
		for ship in tf.ships:
			if ship.type_code == type_code and not ship.sunk:
				count += 1
	return count


## Quante navi di un tipo ha una parte su TUTTA la mappa. Serve alla clausola
## "4+ CAs" di BL1, che conta i CA in gioco, non quelli di una singola TF.
static func _count_ships_of_type(state: GameState, side: int,
		type_code: String) -> int:
	var total := 0
	for tf in state.forces_of(side):
		total += _count_type(tf, type_code)
	return total


static func _make_available_ship_from_pool(type_code: String, pools: Dictionary,
		used: Dictionary) -> Ship:
	for name_v: Variant in pools.get(type_code, []):
		var name := String(name_v)
		if used.has(name):
			continue
		var ship := ShipRoster.shared().make(name)
		if ship != null:
			return ship
	return null


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
		"launch_hex": Vector2i.MAX,
		"target_hex": Vector2i.MAX,
		"completion": false,
		"completion_port": {},
		"turn_kind": "",
		"pass_initiative": false,
		"follow_up": {},
		"log": [] as Array[String],
	}
	if note != "":
		out["log"].append(note)
	return out


static func _normalize_code(code: String) -> String:
	var c := code.strip_edges().to_upper()
	if c.begins_with("CONV"):
		return "CONV"
	if c.begins_with("X"):
		return "X"
	return c


static func _n1_port_table(state: GameState) -> String:
	var r := state.rng.d6("Solitario N1 Port Table")
	if r == 1:
		return "Murmansk"
	if r == 2:
		return "Kiel"
	if r <= 4:
		return "Trondheim"
	return "Narvik"


static func _n_complete_with_priority(state: GameState, graph: MapGraph,
		port_control: Dictionary, side: int, port_name: String,
		note: String) -> Dictionary:
	var tf := _best_unidentified(state, side)
	if tf == null:
		tf = _shortest_force_with_convoy(state, side)
	if tf == null:
		tf = _create_unidentified_at(state, graph, side, "Kiel")
	return _complete_or_route_to_port(state, graph, port_control, tf, port_name, note)


static func _n_british_port_action(state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int,
		port_name: String, printed_name: String, note: String) -> Dictionary:
	var tf := _force_at_port(state, side, graph, port_name)
	if tf == null:
		tf = _longest_force(state, side)
	if tf == null:
		tf = _create_unidentified_at(state, graph, side, "Scapa Flow")
	var same_hex := _enemy_in_same_hex(state, side, tf)
	if same_hex != null:
		return _attack_or_route_selected(state, graph, engine, tf, same_hex,
			"%s: nemico nello stesso esagono di %s" % [note, printed_name])
	return _complete_or_route_to_port(state, graph, port_control, tf, port_name,
		"%s: Completamento a %s" % [note, printed_name])


static func _n2_r4(state: GameState, graph: MapGraph,
		engine: ActionEngine, side: int) -> Dictionary:
	var tf1 := _create_force_at(state, graph, side, "Scapa Flow",
		["Sheffield", "Birmingham", "Belfast", "Suffolk"], false)
	var tf2 := _create_force_at(state, graph, side, "Scapa Flow",
		["Nelson", "Rodney", "Berwick"], false)
	var r1 := _route_toward_hex(state, graph, tf1, _port_hex(graph, "Trondheim"),
		"Solitario AI N2: R4 TF1 verso Trondheim")
	var r2 := _route_toward_hex(state, graph, tf2, _port_hex(graph, "Narvik"),
		"Solitario AI N2: R4 TF2 verso Narvik")
	var out := _empty("Solitario AI N2: Operazione R4 crea due TF britanniche.")
	out["ok"] = bool(r1.get("ok", false)) or bool(r2.get("ok", false))
	out["pass_initiative"] = true
	out["log"].append_array(r1.get("log", []))
	out["log"].append_array(r2.get("log", []))
	return out


static func _n3_sr(state: GameState, graph: MapGraph, side: int) -> Dictionary:
	var target := _best_enemy_target(state, side, null)
	if target == null:
		var no := _empty("Solitario AI N3: Ricognizione Furtiva senza bersaglio; Passare.")
		no["pass_initiative"] = true
		return no
	var h := _anchor_hex(target)
	if target.trajectory.is_station():
		target.trajectory.set_contact_at(h, true)
	else:
		var idx := target.trajectory.index_of_hex(h)
		if idx >= 0:
			target.trajectory.set_info(idx, true)
	var out := _empty("Solitario AI N3: Submarine piazza Informazioni su %s in %s."
		% [target.display_name(), str(h)])
	out["ok"] = true
	out["pass_initiative"] = true
	return out


static func _n4_r4(state: GameState, graph: MapGraph,
		engine: ActionEngine, port_control: Dictionary, side: int) -> Dictionary:
	var tf4 := _create_force_at(state, graph, side, "Liverpool",
		["Convoy x3", "Sheffield"], false)
	var tf5 := _create_force_at(state, graph, side, "Scapa Flow",
		["Furious", "Belfast", "Birmingham"], false)
	var r4 := _route_toward_hex(state, graph, tf4, _port_hex(graph, "Narvik"),
		"Solitario AI N4: R4 TF4 verso Narvik")
	var r5 := _route_toward_hex(state, graph, tf5, _port_hex(graph, "Narvik"),
		"Solitario AI N4: R4 TF5 verso Narvik")
	var out := _empty("Solitario AI N4: primo R4 crea le TF britanniche previste.")
	out["ok"] = bool(r4.get("ok", false)) or bool(r5.get("ok", false))
	out["pass_initiative"] = true
	out["log"].append_array(r4.get("log", []))
	out["log"].append_array(r5.get("log", []))
	return out


static func _n4_x(state: GameState, graph: MapGraph,
		engine: ActionEngine, side: int) -> Dictionary:
	_remove_damaged_ships(state, side)
	var tf := _force_with_ship_name(state, side, "Renown")
	if tf == null:
		tf = _best_type_priority(state, side, ["BB", "BC", "CA"])
	if tf == null:
		tf = _create_force_at(state, graph, side, "Scapa Flow",
			["Nelson", "Rodney"], false)
	return _attack_or_route_selected(state, graph, engine, tf,
		_best_contact_or_port_target(state, graph, side, "Narvik"),
		"Solitario AI N4: Bring on Battle")


static func _marker_not_modeled(note: String) -> Dictionary:
	var out := _empty(note + ": Mine, basi aeree e forze furtive permanenti non sono ancora pedine modellate; il bot registra l'effetto e passa senza inventare pezzi.")
	out["pass_initiative"] = true
	return out


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
	for key in ["ENGAGE", "NAVAL_SEARCH"]:
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
			done["turn_kind"] = "completion"
			done["active"] = tf
			done["completion_port"] = opts[0]
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
	var note := "Solitario AI: rotta di rientro verso %s." % String(port["name"])
	var route := _route_toward_hex(state, graph, active,
		port["hex"] as Vector2i, note)
	if bool(route.get("ok", false)):
		route["follow_up"] = {"kind": "completion",
			"port_name": String(port["name"]), "note": note}
	return route


static func _complete_or_route_to_port(state: GameState, graph: MapGraph,
		port_control: Dictionary, tf: TaskForce, port_name: String,
		note: String) -> Dictionary:
	if tf == null:
		var no_tf := _empty("%s: nessuna TF selezionabile; passa." % note)
		no_tf["pass_initiative"] = true
		return no_tf
	var option := _completion_port_option(tf, graph, port_control, port_name)
	if not option.is_empty():
		return _attempt_completion_at_port(graph, port_control, tf, port_name, note)
	if not graph.ports.has(port_name):
		var unknown := _empty("%s: porto '%s' non calibrato; passa." % [note, port_name])
		unknown["pass_initiative"] = true
		return unknown
	var p2: Dictionary = graph.ports[port_name]
	var route := _route_toward_hex(state, graph, tf,
		p2["hex"] as Vector2i, note)
	if bool(route.get("ok", false)):
		route["follow_up"] = {"kind": "completion",
			"port_name": port_name, "note": note}
	return route


## Seconda meta' di una procedura Traiettoria -> Completamento. A questo punto
## non e' piu' permesso pianificare un'altra Traiettoria: la tabella ordina di
## tentare il Completamento sulla rotta appena costruita oppure Passare.
static func _attempt_completion_at_port(graph: MapGraph, port_control: Dictionary,
		tf: TaskForce, port_name: String, note: String) -> Dictionary:
	if tf == null:
		var missing := _empty("%s: manca la TF; Passare." % note)
		missing["pass_initiative"] = true
		return missing
	var reason := ""
	var option := _completion_port_option(tf, graph, port_control, port_name)
	if option.is_empty():
		reason = "la Traiettoria non raggiunge %s" % port_name
	elif not tf.can_complete():
		reason = "la TF ha un segnalino Informazioni"
	elif not tf.trajectory.is_station() \
			and tf.trajectory.length() > Completion.MAX_SEGMENTS:
		reason = "la Traiettoria ha %d segmenti, oltre il massimo di %d" \
			% [tf.trajectory.length(), Completion.MAX_SEGMENTS]
	elif tf.ships.is_empty() and not tf.unidentified:
		reason = "la TF non ha navi"
	if reason != "":
		var passed := _empty("%s: Completamento impossibile (%s); %s Passa."
			% [note, reason, tf.display_name()])
		passed["ok"] = true
		passed["active"] = tf
		passed["turn_kind"] = "pass"
		passed["pass_initiative"] = true
		passed["time_lapse_before_pass"] = true
		return passed
	var done := _empty("")
	done["ok"] = true
	done["completion"] = true
	done["turn_kind"] = "completion"
	done["active"] = tf
	done["completion_port"] = option
	done["log"].append("%s: %s puo' tentare il Completamento a %s."
		% [note, tf.display_name(), String(option["name"])])
	return done


static func _completion_port_option(tf: TaskForce, graph: MapGraph,
		port_control: Dictionary, port_name: String) -> Dictionary:
	for p in Completion.port_options(tf, graph, port_control):
		var found := String(p["name"])
		if found == port_name or (port_name == "Clyde" and found == "Liverpool"):
			return p
	return {}


static func _attack_or_route_selected(state: GameState, graph: MapGraph,
		engine: ActionEngine, active: TaskForce, target: TaskForce,
		note: String) -> Dictionary:
	if active == null or target == null:
		var no := _empty("%s: manca una TF o un bersaglio; passa." % note)
		no["pass_initiative"] = true
		return no
	for key in ["ENGAGE", "NAVAL_SEARCH"]:
		var d := _legal_action_for(state, engine, key, active, target)
		if bool(d["ok"]):
			d["log"].append("%s: azione legale immediata." % note)
			return d
	var route := _route_toward_tf(state, graph, active, target, note)
	if bool(route.get("ok", false)):
		route["follow_up"] = {"kind": "attack", "target_id": target.id,
			"note": note}
	return route


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
			var launches: Array[Vector2i] = [Vector2i.MAX] as Array[Vector2i]
			if key == "AIR_STRIKE":
				launches = ActionEngine.air_launch_hexes(active)
			for launch in launches:
				var targets: Array[Vector2i] = []
				if key == "AIR_STRIKE":
					targets = ActionEngine.air_target_hexes(launch, target)
				else:
					var at := _shared_hex(active, target)
					targets.append(at if at != Vector2i.MAX else _anchor_hex(target))
				for target_hex in targets:
					var dec := ActionEngine.Declaration.new()
					dec.action_key = key
					dec.active = active
					dec.target = target
					dec.launch_hex = launch
					dec.target_hex = target_hex
					if engine.legality_error(dec, state) != "":
						continue
					var score := _target_score(target) - float(active.info_count()) * 4.0
					if score > best_score:
						best_score = score
						best["ok"] = true
						best["action_key"] = key
						best["active"] = active
						best["target"] = target
						best["launch_hex"] = launch
						best["target_hex"] = target_hex
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
	var was_station := active.trajectory.is_station()
	for h_v: Variant in steps:
		if active.length() >= Trajectory.MAX_SEGMENTS:
			break
		var h: Vector2i = h_v
		var info := state.triggers_info(h, active.side)
		if active.trajectory.extend(h, end, graph, state.port_hexes(), info, active.side):
			added += 1
			# La prima estensione di una Stazione accoda il nuovo segmento.
			# Le tappe successive devono quindi proseguire da quel capo.
			if was_station:
				end = 1
				was_station = false
		else:
			break
	out["ok"] = added > 0
	out["turn_kind"] = "trajectory"
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


static func _port_hex(graph: MapGraph, port_name: String) -> Vector2i:
	if not graph.ports.has(port_name):
		return Vector2i.MAX
	return (graph.ports[port_name] as Dictionary)["hex"] as Vector2i


static func _force_at_port(state: GameState, side: int,
		graph: MapGraph, port_name: String) -> TaskForce:
	var h := _port_hex(graph, port_name)
	if h == Vector2i.MAX:
		return null
	for tf in state.forces_of(side):
		if tf.trajectory.occupies(h):
			return tf
	return null


static func _nearest_force_to_port(state: GameState, side: int,
		graph: MapGraph, port_name: String) -> TaskForce:
	var h := _port_hex(graph, port_name)
	if h == Vector2i.MAX:
		return null
	var best: TaskForce = null
	var bestd := 999999
	for tf in state.forces_of(side):
		var d := Hex.distance(_anchor_hex(tf), h)
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _longest_force(state: GameState, side: int) -> TaskForce:
	var best: TaskForce = null
	for tf in state.forces_of(side):
		if best == null or tf.length() > best.length():
			best = tf
	return best


static func _best_type_priority(state: GameState, side: int,
		types: Array[String]) -> TaskForce:
	for type_code in types:
		var tf := _shortest_force_with_type(state, side, type_code)
		if tf != null:
			return tf
	return null


static func _force_with_ship_name(state: GameState, side: int,
		ship_name: String) -> TaskForce:
	for tf in state.forces_of(side):
		for s in tf.ships:
			if s.name == ship_name and not s.sunk:
				return tf
	return null


static func _enemy_in_same_hex(state: GameState, side: int,
		tf: TaskForce) -> TaskForce:
	if tf == null:
		return null
	for enemy in state.forces_of(1 - side):
		if _shared_hex(tf, enemy) != Vector2i.MAX:
			return enemy
	return null


static func _best_contact_or_port_target(state: GameState, graph: MapGraph,
		side: int, port_name: String) -> TaskForce:
	var best_contact: TaskForce = null
	var bestd := 999999
	var port := _port_hex(graph, port_name)
	for tf in state.forces_of(1 - side):
		if tf.trajectory.contact_count() <= 0:
			continue
		var d := Hex.distance(_anchor_hex(tf), port) if port != Vector2i.MAX else 0
		if d < bestd:
			bestd = d
			best_contact = tf
	if best_contact != null:
		return best_contact
	return _nearest_enemy_to_hex(state, side, port)


static func _nearest_enemy_to_hex(state: GameState, side: int,
		h: Vector2i) -> TaskForce:
	var best: TaskForce = null
	var bestd := 999999
	for tf in state.forces_of(1 - side):
		var d := Hex.distance(_anchor_hex(tf), h)
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _nearest_eligible_denmark_strait_force(state: GameState,
		side: int) -> TaskForce:
	var best: TaskForce = null
	var ref := Vector2i(13, -6)
	var bestd := 999999
	for tf in state.forces_of(side):
		if _has_convoy(tf) or _has_damaged(tf):
			continue
		var d := Hex.distance(_anchor_hex(tf), ref)
		if d < bestd:
			bestd = d
			best = tf
	return best


static func _denmark_strait_reference(graph: MapGraph) -> Vector2i:
	return _port_hex(graph, "Hvalfjordur")


static func _n1_interception_target(state: GameState, graph: MapGraph,
		side: int) -> TaskForce:
	for tf in state.forces_of(1 - side):
		if tf.trajectory.is_station() and tf.trajectory.station_port != "Scapa Flow":
			return tf
	var trondheim := _port_hex(graph, "Trondheim")
	return _nearest_enemy_to_hex(state, side, trondheim)


static func _n1_battle_target(state: GameState, graph: MapGraph,
		side: int) -> TaskForce:
	var port := _n1_port_table(state)
	return _nearest_enemy_to_hex(state, side, _port_hex(graph, port))


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


static func _create_force_in_hex(state: GameState, side: int, h: Vector2i,
		ships: Array[String], force_name: String) -> TaskForce:
	var tf := TaskForce.new(0, side)
	tf.color = _color_for(side)
	tf.slot = _next_slot(state, tf.color)
	tf.name = force_name
	for ship_name in ships:
		var ship := ShipRoster.shared().make(ship_name)
		if ship != null:
			tf.ships.append(ship)
	tf.recompute_speed()
	tf.trajectory.become_station(h)
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
