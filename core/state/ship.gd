class_name Ship
extends RefCounted

## Una nave (o Convoglio, o Squadrone DD) dentro una Task Force.
##
## Regole di danno (RB p.51 "Danneggiato" + Charts "Colpo"):
##   - DANNEGGIATO gira la pedina sul lato Danneggiato; se era gia' danneggiata,
##     la nave affonda
##   - i Colpi gia' assegnati RESTANO quando la nave si gira
##   - Convogli e Squadroni DD non si danneggiano: per loro un risultato di
##     Danno vale 2 Colpi
##   - sono distrutti se subiscono quattro Colpi
##
## Le statistiche complete (valore dei cannoni, corazza, ecc.) sono stampate
## sulle pedine e non sono ancora trascritte: vedi STATO.md. Qui c'e' quanto
## serve alle regole della mappa operazionale.

enum Kind { WARSHIP, CONVOY, DD_SQUADRON, SHORE_BATTERY }

const HITS_TO_DESTROY_UNARMORED := 4

var name: String = ""
var nation: String = ""          ## GE / UK / FR / US
var type_code: String = ""       ## BB, BC, CA, CL, CV, PB, AC, AO, DD, ...
var kind: int = Kind.WARSHIP
var speed: int = TimeLapse.Speed.MEDIUM

var damaged: bool = false
var sunk: bool = false
var hits: int = 0


func _init(p_name: String = "", p_speed: int = TimeLapse.Speed.MEDIUM,
		p_kind: int = Kind.WARSHIP) -> void:
	name = p_name
	speed = p_speed
	kind = p_kind


func can_be_damaged() -> bool:
	return kind == Kind.WARSHIP


## Applica un risultato DANNEGGIATO. Ritorna la descrizione di cosa e' successo.
func apply_damage() -> String:
	if sunk:
		return "%s e' gia' affondata" % name
	if not can_be_damaged():
		# RB p.51: per Convogli e Squadroni DD un Danno vale 2 Colpi
		var a := apply_hit()
		var b := apply_hit()
		return "%s non puo' essere danneggiata: vale 2 Colpi (%s)" % [name, b]
	if damaged:
		sunk = true
		return "%s era gia' danneggiata: AFFONDATA" % name
	damaged = true
	return "%s e' ora Danneggiata%s" % [name,
		" (conserva %d Colpi)" % hits if hits > 0 else ""]


## Applica un COLPO. Ritorna la descrizione.
func apply_hit() -> String:
	if sunk:
		return "%s e' gia' affondata" % name
	hits += 1
	if not can_be_damaged() and hits >= HITS_TO_DESTROY_UNARMORED:
		sunk = true
		return "%s ha subito %d Colpi: DISTRUTTA" % [name, hits]
	return "%s ha subito un Colpo (totale %d)" % [name, hits]


## Il bersaglio e' abbastanza lento perche' il risultato lo colpisca?
func is_slow_or_slower() -> bool:
	return speed <= TimeLapse.Speed.SLOW


func is_very_slow() -> bool:
	return speed == TimeLapse.Speed.VERY_SLOW


func display() -> String:
	var s := name
	if type_code != "":
		s = "%s %s" % [type_code, name]
	if sunk:
		s += " [affondata]"
	elif damaged:
		s += " [danneggiata]"
	if hits > 0:
		s += " (%d colpi)" % hits
	return s


func to_dict() -> Dictionary:
	return {"name": name, "nation": nation, "type": type_code, "kind": kind,
		"speed": speed, "damaged": damaged, "sunk": sunk, "hits": hits}


static func from_dict(d: Dictionary) -> Ship:
	var s := Ship.new(String(d.get("name", "")),
		int(d.get("speed", TimeLapse.Speed.MEDIUM)),
		int(d.get("kind", Kind.WARSHIP)))
	s.nation = String(d.get("nation", ""))
	s.type_code = String(d.get("type", ""))
	s.damaged = bool(d.get("damaged", false))
	s.sunk = bool(d.get("sunk", false))
	s.hits = int(d.get("hits", 0))
	return s


## Le voci di scenario possono essere una semplice stringa (solo il nome) o un
## oggetto completo: accettiamo entrambe, cosi' gli scenari importati dai .vsav
## restano validi anche prima che le statistiche siano trascritte.
static func from_variant(v: Variant) -> Ship:
	if typeof(v) == TYPE_DICTIONARY:
		return Ship.from_dict(v)
	return Ship.new(String(v))
