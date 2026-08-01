class_name TaskForce
extends RefCounted

## Una Task Force: un gruppo di navi rappresentato sulla mappa da una Stazione
## o da una Traiettoria.
##
## I colori corrispondono ai set di pedine del modulo:
##   Kriegsmarine -> GE 0..4
##   Royal Navy   -> Brown 0..2, Tan 0..3, Red 0..2

enum Side { KRIEGSMARINE, ROYAL_NAVY }

var id: int = 0
var side: int = Side.KRIEGSMARINE
var color: String = "GE"       ## "GE" | "Brown" | "Tan" | "Red"
var slot: int = 0              ## indice nel set colore
var name: String = ""

## Le navi della Task Force.
var ships: Array[Ship] = []

## Velocita' della TF: indice in TimeLapse.Speed.
## Regola: e' quella della nave piu' lenta. Se ci sono navi, viene ricalcolata;
## il campo resta impostabile a mano per gli scenari privi di elenco navi.
var speed: int = TimeLapse.Speed.MEDIUM

var trajectory: Trajectory = null

## Segnalini assegnati alla TF nel suo complesso (non a un segmento).
var evasive: bool = false

## La Task Force ha eseguito il Completamento e ha lasciato il gioco. Il porto
## resta segnato perche' in una Operazione di campagna le navi possono tornare
## in gioco piu' avanti, e da li' devono ripartire.
var completed: bool = false
var completed_port: String = ""
var leader: String = ""


func _init(p_id: int = 0, p_side: int = Side.KRIEGSMARINE) -> void:
	id = p_id
	side = p_side
	trajectory = Trajectory.new()


func is_station() -> bool:
	return trajectory.is_station()


func length() -> int:
	return trajectory.length()


func info_count() -> int:
	return trajectory.info_count()


## RB p.21: una TF con un segnalino Informazioni non puo' fare Completamento.
func can_complete() -> bool:
	return trajectory.info_count() == 0


## La velocita' della TF e' quella della sua nave piu' lenta (le navi affondate
## non contano). Senza elenco navi resta il valore impostato dallo scenario.
func recompute_speed() -> int:
	var slowest := -1
	for s in ships:
		if s.sunk:
			continue
		var sp := s.current_speed()
		if slowest < 0 or sp < slowest:
			slowest = sp
	if slowest >= 0:
		speed = slowest
	return speed


func afloat_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for s in ships:
		if not s.sunk:
			out.append(s)
	return out


func is_eliminated() -> bool:
	return not ships.is_empty() and afloat_ships().is_empty()


func display_name() -> String:
	if name != "":
		return name
	var s := "KM" if side == Side.KRIEGSMARINE else "RN"
	return "%s %s-%d" % [s, color, slot]


func to_dict() -> Dictionary:
	var sh: Array = []
	for s in ships:
		sh.append(s.to_dict())
	return {
		"id": id, "side": side, "color": color, "slot": slot, "name": name,
		"ships": sh, "speed": speed, "evasive": evasive, "leader": leader,
		"completed": completed, "completed_port": completed_port,
		"trajectory": trajectory.to_dict(),
	}


static func from_dict(d: Dictionary) -> TaskForce:
	var tf := TaskForce.new(int(d.get("id", 0)), int(d.get("side", 0)))
	tf.color = String(d.get("color", "GE"))
	tf.slot = int(d.get("slot", 0))
	tf.name = String(d.get("name", ""))
	# Gli scenari elencano le navi per NOME: le statistiche si prendono dal
	# ruolino (core/data/ships.json). Un nome sconosciuto produce comunque una
	# nave, ma senza statistiche, e il log lo dira' al primo Colpo.
	var ss: Array[Ship] = []
	for s_v: Variant in d.get("ships", []):
		if typeof(s_v) == TYPE_STRING:
			var from_roster := ShipRoster.shared().make(String(s_v))
			ss.append(from_roster if from_roster != null else Ship.new(String(s_v)))
		else:
			ss.append(Ship.from_variant(s_v))
	tf.ships = ss
	tf.speed = int(d.get("speed", TimeLapse.Speed.MEDIUM))
	if not ss.is_empty():
		tf.recompute_speed()
	tf.evasive = bool(d.get("evasive", false))
	tf.completed = bool(d.get("completed", false))
	tf.completed_port = String(d.get("completed_port", ""))
	tf.leader = String(d.get("leader", ""))
	tf.trajectory = Trajectory.from_dict(d.get("trajectory", {}))
	return tf
