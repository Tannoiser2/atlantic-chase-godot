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

## Ultimo totale dei Modificatori Comuni mostrato sul tracciato stampato. Il
## segno e il lato dicono quale dei due segnalini avanza: un valore negativo e'
## un vantaggio equivalente per l'avversario.
var modifier_track_value: int = 0
var modifier_track_side: int = TaskForce.Side.KRIEGSMARINE

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
var convoys_completed_by_side: Dictionary = {}

## Si gioca col fascicolo delle Regole Avanzate di Battaglia?
##
## E' una scelta di partita, non di battaglia: si accetta prima di cominciare e
## vale fino alla fine. Sta in GameState e non solo in Session perche' deve
## finire nel salvataggio - ricaricare una partita avanzata come base
## cambierebbe le tabelle sotto i piedi al giocatore.
var advanced_battle: bool = false

## Stato del modo solitario. Le tabelle dell'avversario immaginario passano da
## Presto a Tardi durante la partita, quindi la scelta deve sopravvivere a
## undo, salvataggi e ricariche come qualunque altro stato di gioco.
var solo_phase: int = SoloOpponent.Phase.EARLY
var solo_phase_reason: String = ""

## Marker Rendezvous degli scenari solitari BL. Sono dati di scenario, ma devono
## vivere nello stato perche' il Rifornimento li rimuove o li sposta.
var rendezvous_markers: Array[Dictionary] = []

## Quante volte e' stato speso ciascun Comandante. Raeder e Pound hanno due
## utilizzi, gli altri uno (RB p.10); il dato deve sopravvivere al salvataggio.
var commander_uses: Dictionary = {}

## Perdite gia' rimosse dalla mappa. Servono alle tabelle solitarie che
## distinguono "Danneggiata in gioco" da "affondata in precedenza": lasciare
## una TF eliminata sulla mappa conservava l'informazione, ma mentiva al
## giocatore. La storia delle perdite e' il posto corretto dove conservarla.
var casualties: Array[Dictionary] = []

## Contatori ed esito delle procedure solitarie specifiche di scenario. Sono
## dati di gioco: per esempio BL2 distingue il primo, secondo e terzo risultato
## E e ricorda i tipi gia' ottenuti dalla tabella di Identificazione.
var solo_counters: Dictionary = {}
var solo_ended: bool = false
var solo_end_reason: String = ""


func add_vp(side: int, amount: float, reason: String = "") -> void:
	vp[side] = float(vp.get(side, 0.0)) + amount
	changed.emit()


func set_modifier_track(side: int, value: int) -> void:
	modifier_track_side = side
	modifier_track_value = value
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


func convoys_completed_for(side: int) -> int:
	var key := str(side)
	# Nei vecchi salvataggi esiste solo il totale. Appena compare almeno un
	# conteggio per parte, una chiave assente significa invece zero: usare il
	# totale mescolerebbe i Completamenti britannici e tedeschi di BL2.
	if convoys_completed_by_side.is_empty():
		return convoys_completed
	return int(convoys_completed_by_side.get(key, 0))


func count_convoy_completed(side: int) -> void:
	convoys_completed += 1
	var key := str(side)
	convoys_completed_by_side[key] = int(convoys_completed_by_side.get(key, 0)) + 1
	changed.emit()


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


func remove_task_force(tf: TaskForce) -> bool:
	if tf == null:
		return false
	var idx := task_forces.find(tf)
	if idx < 0:
		return false
	task_forces.remove_at(idx)
	_by_id.erase(tf.id)
	changed.emit()
	return true


## Toglie dalla mappa le TF senza piu' navi a galla e conserva una fotografia
## delle perdite. Una TF non identificata e una TF senza ruolino non sono
## eliminate: in entrambi i casi l'assenza di navi e' un dato ancora ignoto.
func remove_eliminated_forces(reason: String = "") -> Array[Dictionary]:
	var removed: Array[Dictionary] = []
	for tf in task_forces.duplicate():
		if not tf.is_eliminated():
			continue
		var names: Array[String] = []
		var convoys := 0
		for ship in tf.ships:
			names.append(ship.name)
			if ship.kind == Ship.Kind.CONVOY:
				convoys += 1
		var loss := {
			"tf_id": tf.id,
			"tf_name": tf.display_name(),
			"side": tf.side,
			"ships": names,
			"convoys": convoys,
			"reason": reason,
		}
		casualties.append(loss)
		removed.append(loss)
		remove_task_force(tf)
	return removed


func sunk_count(side: int, convoys_only: bool = false) -> int:
	var total := 0
	# Navi affondate dentro una TF che ha ancora superstiti restano nel suo
	# ruolino; le TF interamente eliminate sono invece nella cronologia sotto.
	for tf in task_forces:
		if tf.side != side:
			continue
		for ship in tf.ships:
			if ship.sunk and (not convoys_only or ship.kind == Ship.Kind.CONVOY):
				total += 1
	for loss in casualties:
		if int(loss.get("side", -1)) != side:
			continue
		if convoys_only:
			total += int(loss.get("convoys", 0))
		else:
			total += (loss.get("ships", []) as Array).size()
	return total


func forces_of(side: int) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in task_forces:
		if tf.side == side and not tf.completed:
			out.append(tf)
	return out


## Tutte le TF che hanno un segmento o una Stazione nell'esagono.
func forces_in(h: Vector2i) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in task_forces:
		if not tf.completed and tf.trajectory.occupies(h):
			out.append(tf)
	return out


func rendezvous_at(h: Vector2i) -> Dictionary:
	for rv in rendezvous_markers:
		if bool(rv.get("active", true)) and Vector2i(int(rv.get("q", 0)),
				int(rv.get("r", 0))) == h:
			return rv
	return {}


func remove_rendezvous_at(h: Vector2i) -> bool:
	for rv in rendezvous_markers:
		if bool(rv.get("active", true)) and Vector2i(int(rv.get("q", 0)),
				int(rv.get("r", 0))) == h:
			rv["active"] = false
			changed.emit()
			return true
	return false


func move_rendezvous_at(from: Vector2i, to: Vector2i) -> bool:
	for rv in rendezvous_markers:
		if bool(rv.get("active", true)) and Vector2i(int(rv.get("q", 0)),
				int(rv.get("r", 0))) == from:
			rv["q"] = to.x
			rv["r"] = to.y
			changed.emit()
			return true
	return false


# ------------------------------------------------------- informazioni (21) --

## Un segmento posto qui riceve un segnalino Informazioni?
## RB p.21: porto nemico, base aerea nemica, Stazione TF nemica, forza Furtiva.
## NON lo innesca un semplice segmento Traiettoria nemico.
func triggers_info(h: Vector2i, mover_side: int) -> bool:
	if info_triggers.has(h):
		for reason_v: Variant in info_triggers[h]:
			var reason := String(reason_v)
			if reason.begins_with("side:"):
				if _info_trigger_side(reason) != mover_side:
					return true
			else:
				return true
	for tf in task_forces:
		if tf.side == mover_side or tf.completed:
			continue
		if tf.trajectory.is_station() and tf.trajectory.station_port == "" \
				and tf.trajectory.station_hex == h:
			return true
	return false


func info_reasons(h: Vector2i, mover_side: int) -> Array[String]:
	var out: Array[String] = []
	if info_triggers.has(h):
		for reason_v: Variant in info_triggers[h]:
			var reason := String(reason_v)
			if reason.begins_with("side:"):
				if _info_trigger_side(reason) != mover_side:
					out.append(reason.get_slice("|", 1) if reason.contains("|") \
						else "causa nemica")
			else:
				out.append(reason)
	for tf in task_forces:
		if tf.side != mover_side and not tf.completed \
				and tf.trajectory.is_station() and tf.trajectory.station_port == "" \
				and tf.trajectory.station_hex == h:
			out.append("Stazione TF nemica (%s)" % tf.display_name())
	return out


func add_info_trigger(h: Vector2i, reason: String) -> void:
	if not info_triggers.has(h):
		info_triggers[h] = []
	if not (info_triggers[h] as Array).has(reason):
		(info_triggers[h] as Array).append(reason)


## Registra i porti che causano Informazioni senza duplicare nei file scenario
## la geometria gia' calibrata in MapGraph. `port_control` contiene soltanto
## le eccezioni dello scenario; Completion.control_of applica poi i controlli
## nazionali predefiniti (RB p.8 e p.21).
func configure_port_info_triggers(port_control: Dictionary = {}) -> void:
	for pname_v: Variant in graph.ports.keys():
		var pname := String(pname_v)
		var port: Dictionary = graph.ports[pname]
		var control := Completion.control_of(port, port_control)
		var owner := -1
		if control == "KRIEGSMARINE":
			owner = TaskForce.Side.KRIEGSMARINE
		elif control == "ROYAL_NAVY":
			owner = TaskForce.Side.ROYAL_NAVY
		if owner < 0:
			continue
		for h_v: Variant in port.get("hexes", []):
			var h: Vector2i = h_v
			add_info_trigger(h, "side:%d|porto nemico: %s" % [owner, pname])


static func _info_trigger_side(reason: String) -> int:
	return int(reason.get_slice("|", 0).trim_prefix("side:"))


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
		"modifier_track_value": modifier_track_value,
		"modifier_track_side": modifier_track_side,
		"round": round_number,
		"task_forces": tfs,
		"info_triggers": trig,
		"vp_km": vp_of(TaskForce.Side.KRIEGSMARINE),
		"vp_rn": vp_of(TaskForce.Side.ROYAL_NAVY),
		"vp_once": vp_once.duplicate(),
		"convoys_completed": convoys_completed,
		"convoys_completed_by_side": convoys_completed_by_side.duplicate(),
		"advanced_battle": advanced_battle,
		"solo_phase": solo_phase,
		"solo_phase_reason": solo_phase_reason,
		"rendezvous_markers": rendezvous_markers.duplicate(true),
		"commander_uses": commander_uses.duplicate(),
		"casualties": casualties.duplicate(true),
		"solo_counters": solo_counters.duplicate(true),
		"solo_ended": solo_ended,
		"solo_end_reason": solo_end_reason,
		"rng": rng.to_dict(),
	}


func apply_dict(d: Dictionary) -> void:
	scenario_name = String(d.get("scenario", ""))
	weather = int(d.get("weather", TimeLapse.Weather.GOOD))
	initiative = int(d.get("initiative", 0))
	initiative_count = int(d.get("initiative_count", 0))
	modifier_track_value = int(d.get("modifier_track_value", 0))
	modifier_track_side = int(d.get("modifier_track_side", initiative))
	round_number = int(d.get("round", 1))
	vp[TaskForce.Side.KRIEGSMARINE] = float(d.get("vp_km", 0.0))
	vp[TaskForce.Side.ROYAL_NAVY] = float(d.get("vp_rn", 0.0))
	convoys_completed = int(d.get("convoys_completed", 0))
	convoys_completed_by_side = (d.get("convoys_completed_by_side", {}) \
		as Dictionary).duplicate()
	# le partite salvate prima che le Regole Avanzate esistessero sono
	# tutte partite base: false e' il default giusto
	advanced_battle = bool(d.get("advanced_battle", false))
	solo_phase = int(d.get("solo_phase", SoloOpponent.Phase.EARLY))
	solo_phase_reason = String(d.get("solo_phase_reason", ""))
	rendezvous_markers.clear()
	for rv_v: Variant in d.get("rendezvous_markers", []):
		var rv: Dictionary = rv_v
		rendezvous_markers.append(rv.duplicate(true))
	commander_uses.clear()
	var saved_commanders: Dictionary = d.get("commander_uses", {})
	for name_v: Variant in saved_commanders.keys():
		commander_uses[String(name_v)] = int(saved_commanders[name_v])
	casualties.clear()
	for loss_v: Variant in d.get("casualties", []):
		var loss: Dictionary = loss_v
		casualties.append(loss.duplicate(true))
	solo_counters = (d.get("solo_counters", {}) as Dictionary).duplicate(true)
	solo_ended = bool(d.get("solo_ended", false))
	solo_end_reason = String(d.get("solo_end_reason", ""))
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
