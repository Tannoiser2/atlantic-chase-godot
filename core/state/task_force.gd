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

## Nomi delle navi (chiavi in ships.json). La velocita' della TF e' quella
## della sua nave piu' lenta (RB, tabella Scorrere del Tempo).
var ships: Array[String] = []

## Velocita' della TF: indice in TimeLapse.Speed.
var speed: int = TimeLapse.Speed.MEDIUM

var trajectory: Trajectory = null

## Segnalini assegnati alla TF nel suo complesso (non a un segmento).
var evasive: bool = false
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


func display_name() -> String:
	if name != "":
		return name
	var s := "KM" if side == Side.KRIEGSMARINE else "RN"
	return "%s %s-%d" % [s, color, slot]


func to_dict() -> Dictionary:
	return {
		"id": id, "side": side, "color": color, "slot": slot, "name": name,
		"ships": ships, "speed": speed, "evasive": evasive, "leader": leader,
		"trajectory": trajectory.to_dict(),
	}


static func from_dict(d: Dictionary) -> TaskForce:
	var tf := TaskForce.new(int(d.get("id", 0)), int(d.get("side", 0)))
	tf.color = String(d.get("color", "GE"))
	tf.slot = int(d.get("slot", 0))
	tf.name = String(d.get("name", ""))
	var ss: Array[String] = []
	for s_v: Variant in d.get("ships", []):
		ss.append(String(s_v))
	tf.ships = ss
	tf.speed = int(d.get("speed", TimeLapse.Speed.MEDIUM))
	tf.evasive = bool(d.get("evasive", false))
	tf.leader = String(d.get("leader", ""))
	tf.trajectory = Trajectory.from_dict(d.get("trajectory", {}))
	return tf
