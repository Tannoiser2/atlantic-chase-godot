class_name GameState
extends RefCounted

## Stato completo della partita, serializzabile in JSON.
##
## Non contiene nodi Godot: puo' essere costruito, mutato e verificato in un
## test headless senza aprire una finestra.

signal changed()

var graph: MapGraph = null
var rng: DiceRNG = null

var task_forces: Array[TaskForce] = []
var _by_id: Dictionary = {}
var _next_id: int = 1

var weather: int = TimeLapse.Weather.GOOD
var initiative: int = TaskForce.Side.KRIEGSMARINE
var initiative_count: int = 0
var round_number: int = 1

## Esagoni che innescano Informazioni quando ci si pone un segmento (RB p.21):
## porti nemici, basi aeree, Stazioni TF nemiche, forze Furtive.
## Chiave Vector2i -> Array[String] di motivi.
var info_triggers: Dictionary = {}

## Caselle Porto: nome -> Dictionary. I segmenti non possono starci (RB p.15).
var port_boxes: Dictionary = {}

var scenario_name: String = ""


func _init(p_graph: MapGraph = null, p_seed: int = 0) -> void:
	graph = p_graph if p_graph != null else MapGraph.load_default()
	rng = DiceRNG.new(p_seed)


# ------------------------------------------------------------ task forces --

func add_task_force(tf: TaskForce) -> TaskForce:
	if tf.id <= 0:
		tf.id = _next_id
	_next_id = maxi(_next_id, tf.id + 1)
	task_forces.append(tf)
	_by_id[tf.id] = tf
	changed.emit()
	return tf


func task_force(id: int) -> TaskForce:
	return _by_id.get(id, null)


func forces_of(side: int) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in task_forces:
		if tf.side == side:
			out.append(tf)
	return out


## Tutte le TF che hanno un segmento o una Stazione nell'esagono.
func forces_in(h: Vector2i) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in task_forces:
		if tf.trajectory.occupies(h):
			out.append(tf)
	return out


# ------------------------------------------------------- informazioni (21) --

## Un segmento posto qui riceve un segnalino Informazioni?
## RB p.21: porto nemico, base aerea nemica, Stazione TF nemica, forza Furtiva.
## NON lo innesca un semplice segmento Traiettoria nemico.
func triggers_info(h: Vector2i, mover_side: int) -> bool:
	if info_triggers.has(h):
		for reason_v: Variant in info_triggers[h]:
			var reason := String(reason_v)
			if reason.begins_with("side:"):
				if int(reason.substr(5)) != mover_side:
					return true
			else:
				return true
	for tf in task_forces:
		if tf.side == mover_side:
			continue
		if tf.trajectory.is_station() and tf.trajectory.station_hex == h:
			return true
	return false


func info_reasons(h: Vector2i, mover_side: int) -> Array[String]:
	var out: Array[String] = []
	if info_triggers.has(h):
		for reason_v: Variant in info_triggers[h]:
			out.append(String(reason_v))
	for tf in task_forces:
		if tf.side != mover_side and tf.trajectory.is_station() \
				and tf.trajectory.station_hex == h:
			out.append("Stazione TF nemica (%s)" % tf.display_name())
	return out


func add_info_trigger(h: Vector2i, reason: String) -> void:
	if not info_triggers.has(h):
		info_triggers[h] = []
	(info_triggers[h] as Array).append(reason)


# ------------------------------------------------------------------ porti --

func port_hexes() -> Dictionary:
	var out := {}
	for k_v: Variant in port_boxes.keys():
		var p: Dictionary = port_boxes[k_v]
		if p.has("hex"):
			out[p["hex"]] = k_v
	return out


# ---------------------------------------------------------- serializzazione --

func to_dict() -> Dictionary:
	var tfs: Array = []
	for tf in task_forces:
		tfs.append(tf.to_dict())
	var trig: Array = []
	for h_v: Variant in info_triggers.keys():
		var h: Vector2i = h_v
		trig.append({"q": h.x, "r": h.y, "reasons": info_triggers[h]})
	return {
		"scenario": scenario_name,
		"weather": weather,
		"initiative": initiative,
		"initiative_count": initiative_count,
		"round": round_number,
		"task_forces": tfs,
		"info_triggers": trig,
		"rng": rng.to_dict(),
	}


func apply_dict(d: Dictionary) -> void:
	scenario_name = String(d.get("scenario", ""))
	weather = int(d.get("weather", TimeLapse.Weather.GOOD))
	initiative = int(d.get("initiative", 0))
	initiative_count = int(d.get("initiative_count", 0))
	round_number = int(d.get("round", 1))
	task_forces.clear()
	_by_id.clear()
	_next_id = 1
	for t_v: Variant in d.get("task_forces", []):
		add_task_force(TaskForce.from_dict(t_v))
	info_triggers.clear()
	for t_v: Variant in d.get("info_triggers", []):
		var t: Dictionary = t_v
		info_triggers[Vector2i(int(t["q"]), int(t["r"]))] = t.get("reasons", [])
	if d.has("rng"):
		rng.restore(d["rng"])
	changed.emit()
