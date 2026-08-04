class_name AirBase
extends RefCounted

## I marcatori Base Aerea PIAZZATI IN PARTITA.
##
## Sono cosa diversa dalle basi aeree STAMPATE sulla mappa, che stanno in
## `MapGraph.air_bases`, appartengono al tabellone e non si spostano mai.
## Questi invece li mettono e li tolgono le procedure delle Tabelle Azioni:
## BL2 p.11 ("place a German Airbase marker in Trondheim"), N4 p.30, N5 p.33 e
## N6 p.37. Finora tutte e quattro dichiaravano la lacuna e passavano, perche'
## la pedina non esisteva da nessuna parte nello stato.
##
## Che cosa questa classe fa e che cosa NON fa, perche' la differenza conta:
## il marcatore esiste, si salva, occupa un esagono e - come qualunque base
## aerea nemica, RB p.21 - vi innesca Informazioni. Ma una base aerea e' anche
## la FONTE di un Attacco Aereo (RB p.27), e quello non e' modellato:
## `ActionEngine` pretende una TF Attiva con una CV integra, e non sa partire
## da un esagono. Le procedure che ne avrebbero bisogno lo dichiarano invece di
## fingere un attacco.

## RB p.27: un Attacco Aereo non arriva oltre due esagoni dal Punto di Lancio.
const STRIKE_RANGE := 2


static func place(state: GameState, side: int, h: Vector2i,
		note: String = "") -> Dictionary:
	var marker := {
		"side": side,
		"q": h.x,
		"r": h.y,
		"note": note,
	}
	state.placed_air_bases.append(marker)
	state.changed.emit()
	return marker


## Toglie il marcatore di una parte da un esagono. `side` negativo = qualunque
## parte. Ritorna true se qualcosa e' stato tolto.
static func remove_at(state: GameState, h: Vector2i, side: int = -1) -> bool:
	for i in range(state.placed_air_bases.size() - 1, -1, -1):
		var m: Dictionary = state.placed_air_bases[i]
		if hex_of(m) != h:
			continue
		if side >= 0 and int(m.get("side", -1)) != side:
			continue
		state.placed_air_bases.remove_at(i)
		state.changed.emit()
		return true
	return false


static func of_side(state: GameState, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in state.placed_air_bases:
		if int(m.get("side", -1)) == side:
			out.append(m)
	return out


static func count_of(state: GameState, side: int) -> int:
	return of_side(state, side).size()


static func at(state: GameState, h: Vector2i, side: int = -1) -> bool:
	for m in state.placed_air_bases:
		if hex_of(m) != h:
			continue
		if side < 0 or int(m.get("side", -1)) == side:
			return true
	return false


## Il marcatore di una parte piu' VICINO a un esagono, o {} se non ne ha.
## Serve alle procedure che dicono "remove the nearest to the Completion hex".
static func nearest_of(state: GameState, side: int, h: Vector2i) -> Dictionary:
	var best := {}
	var best_distance := 1 << 30
	for m in of_side(state, side):
		var d := Hex.distance(hex_of(m), h)
		if d < best_distance:
			best_distance = d
			best = m
	return best


## La Task Force di `side` a portata di una delle sue basi aeree piazzate, o
## null. "A portata" e' il raggio di RB p.27 misurato dall'esagono della base.
static func target_in_range(state: GameState, base_side: int,
		target_side: int) -> TaskForce:
	var best: TaskForce = null
	for m in of_side(state, base_side):
		var h := hex_of(m)
		for tf in state.forces_of(target_side):
			if tf.completed:
				continue
			var hexes := tf.trajectory.hexes()
			if tf.trajectory.is_station():
				hexes = [tf.trajectory.station_hex] as Array[Vector2i]
			for th in hexes:
				if Hex.distance(h, th) > STRIKE_RANGE:
					continue
				# "if more than one target, choose the shortest Trajectory"
				if best == null or tf.length() < best.length():
					best = tf
				break
	return best


static func hex_of(marker: Dictionary) -> Vector2i:
	return Vector2i(int(marker.get("q", 0)), int(marker.get("r", 0)))


## Le basi aeree STAMPATE sulla mappa, nella stessa forma di quelle piazzate.
##
## `MapGraph.air_bases` scrive la parte come sigla - "UK", "GE" - perche' viene
## dal colore della lettera sulla mappa; qui diventa la parte del gioco, cosi'
## chi lancia un Attacco Aereo non deve sapere da dove viene il marcatore.
static func printed_of(graph: MapGraph, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in graph.air_bases:
		if _side_from_tag(String(b.get("side", ""))) != side:
			continue
		out.append({
			"side": side,
			"q": int(b.get("q", 0)),
			"r": int(b.get("r", 0)),
			"note": "base aerea stampata sulla mappa",
			"printed": true,
		})
	return out


static func _side_from_tag(tag: String) -> int:
	return TaskForce.Side.ROYAL_NAVY if tag == "UK" else TaskForce.Side.KRIEGSMARINE


## Tutte le basi aeree da cui una parte puo' lanciare: quelle stampate sulla
## mappa piu' quelle piazzate in partita.
static func sources_for(state: GameState, graph: MapGraph,
		side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(printed_of(graph, side))
	out.append_array(of_side(state, side))
	return out


## L'Attacco Aereo migliore che una base aerea di `side` puo' dichiarare, come
## coppia { "base", "launch_hex", "target", "target_hex" }, o {} se non ce n'e'
## nessuno legale. Le regole restano di `ActionEngine`: qui si enumerano solo i
## candidati, perche' la legalita' la decide una sola funzione.
static func best_strike(state: GameState, graph: MapGraph, engine: ActionEngine,
		side: int) -> Dictionary:
	var best := {}
	var best_length := 1 << 30
	for base in sources_for(state, graph, side):
		var h := hex_of(base)
		for target in state.forces_of(1 - side):
			if target.completed:
				continue
			var hexes := target.trajectory.hexes()
			if target.trajectory.is_station():
				hexes = [target.trajectory.station_hex] as Array[Vector2i]
			for th in hexes:
				var dec := ActionEngine.Declaration.new()
				dec.action_key = "AIR_STRIKE"
				dec.active_air_base = base
				dec.target = target
				dec.launch_hex = h
				dec.target_hex = th
				if engine.legality_error(dec, state) != "":
					continue
				# "if more than one target, choose the shortest Trajectory"
				# e' la formula che le procedure solitarie usano piu' spesso.
				if target.length() < best_length:
					best_length = target.length()
					best = {"base": base, "launch_hex": h, "target": target,
						"target_hex": th}
	return best
