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

## Punti Vittoria. La traccia VP e' stampata sulla mappa; come si guadagnano
## dipende dallo scenario (RB e fascicolo Scenari), quindi qui si tiene solo il
## conteggio e chi lo incrementa e' il codice dell'azione o il giocatore.
##
## Il conteggio e' in virgola mobile perche' diverse tabelle assegnano MEZZO
## punto: "British CA or CL sunk 0.5" compare in Op4, Op6, Op7, Op8 e Op9.
## Arrotondare a interi cambierebbe il vincitore, quindi i mezzi punti si
## sommano davvero e si arrotondano solo quando si stampano (vedi vp_text).
var vp: Dictionary = {
	TaskForce.Side.KRIEGSMARINE: 0.0,
	TaskForce.Side.ROYAL_NAVY: 0.0,
}

## Premi "una tantum" gia' assegnati, per etichetta. Alcune tabelle pagano solo
## la PRIMA volta ("il primo Completamento tedesco riuscito a Bergen"), quindi
## va ricordato quali sono scattati - e va ricordato nello stato, non nel
## motore dei VP, se no un salvataggio ricaricato li pagherebbe di nuovo.
var vp_once: Array[String] = []

## Quanti Convogli hanno gia' Completato. Non e' una statistica: e' la
## condizione che chiude gli scenari. Quasi tutte le Operazioni dicono "quando
## tre Convogli hanno Completato, il tedesco puo' solo fare Attacco Aereo,
## Completamento, Passare e Traiettoria - e se puo' Completare, deve farlo".
## Da quel momento la partita cambia natura: non si caccia piu', si torna a
## casa.
var convoys_completed: int = 0

## Si gioca col fascicolo delle Regole Avanzate di Battaglia?
##
## E' una scelta di partita, non di battaglia: si accetta prima di cominciare e
## vale fino alla fine. Sta in GameState e non solo in Session perche' deve
## finire nel salvataggio - ricaricare una partita avanzata come base
## cambierebbe le tabelle sotto i piedi al giocatore.
var advanced_battle: bool = false


func add_vp(side: int, amount: float, reason: String = "") -> void:
	vp[side] = float(vp.get(side, 0.0)) + amount
	changed.emit()


func vp_of(side: int) -> float:
	return float(vp.get(side, 0.0))


## I VP come li scrive un giocatore sul segnapunti: "3" oppure "3½".
static func vp_str(value: float) -> String:
	var whole := int(floor(absf(value)))
	var half := absf(value) - float(whole) >= 0.25
	var sign_txt := "-" if value < 0.0 else ""
	if not half:
		return "%s%d" % [sign_txt, whole]
	if whole == 0:
		return "%s½" % sign_txt
	return "%s%d½" % [sign_txt, whole]


func vp_text(side: int) -> String:
	return vp_str(vp_of(side))


## Chi conduce ai punti. -1 in caso di parita'.
func vp_leader() -> int:
	var a := vp_of(TaskForce.Side.KRIEGSMARINE)
	var b := vp_of(TaskForce.Side.ROYAL_NAVY)
	if is_equal_approx(a, b):
		return -1
	return TaskForce.Side.KRIEGSMARINE if a > b else TaskForce.Side.ROYAL_NAVY


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
		"vp_km": vp_of(TaskForce.Side.KRIEGSMARINE),
		"vp_rn": vp_of(TaskForce.Side.ROYAL_NAVY),
		"vp_once": vp_once.duplicate(),
		"convoys_completed": convoys_completed,
		"advanced_battle": advanced_battle,
		"rng": rng.to_dict(),
	}


func apply_dict(d: Dictionary) -> void:
	scenario_name = String(d.get("scenario", ""))
	weather = int(d.get("weather", TimeLapse.Weather.GOOD))
	initiative = int(d.get("initiative", 0))
	initiative_count = int(d.get("initiative_count", 0))
	round_number = int(d.get("round", 1))
	vp[TaskForce.Side.KRIEGSMARINE] = float(d.get("vp_km", 0.0))
	vp[TaskForce.Side.ROYAL_NAVY] = float(d.get("vp_rn", 0.0))
	convoys_completed = int(d.get("convoys_completed", 0))
	# le partite salvate prima che le Regole Avanzate esistessero sono
	# tutte partite base: false e' il default giusto
	advanced_battle = bool(d.get("advanced_battle", false))
	vp_once.clear()
	for k_v: Variant in d.get("vp_once", []):
		vp_once.append(String(k_v))
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
