class_name ShipRoster
extends RefCounted

## Il ruolino di tutte le navi del gioco, con le statistiche stampate sulle
## pedine (core/data/ships.json, prodotto da tools/extract_ships.py +
## tools/merge_ships.py).
##
## Serve a costruire una nave a partire dal nome: gli scenari elencano le navi
## per nome, non ripetono le statistiche.

const DATA_PATH := "res://core/data/ships.json"

var _by_name: Dictionary = {}      ## nome minuscolo -> Dictionary
var load_error: String = ""

const SPEEDS := {
	"VERY_SLOW": TimeLapse.Speed.VERY_SLOW,
	"SLOW": TimeLapse.Speed.SLOW,
	"MEDIUM": TimeLapse.Speed.MEDIUM,
	"FAST": TimeLapse.Speed.FAST,
}
const KINDS := {
	"WARSHIP": Ship.Kind.WARSHIP,
	"CONVOY": Ship.Kind.CONVOY,
	"DD_SQUADRON": Ship.Kind.DD_SQUADRON,
	"SHORE_BATTERY": Ship.Kind.SHORE_BATTERY,
}


static func load_default() -> ShipRoster:
	var r := ShipRoster.new()
	r.load_from(DATA_PATH)
	return r


func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "impossibile aprire %s" % path
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		load_error = "JSON non valido in %s" % path
		return false
	_by_name.clear()
	for s_v: Variant in (d as Dictionary).get("ships", []):
		var s: Dictionary = s_v
		_by_name[String(s["name"]).to_lower()] = s
	return true


func count() -> int:
	return _by_name.size()


func has(name: String) -> bool:
	return _by_name.has(name.to_lower())


func names() -> Array:
	return _by_name.keys()


func data(name: String) -> Dictionary:
	return _by_name.get(name.to_lower(), {})


## Costruisce una nave pronta al gioco. Ritorna null se il nome e' sconosciuto,
## cosi' uno scenario con un refuso fallisce subito invece di produrre una nave
## fantasma con statistiche a zero.
func make(name: String) -> Ship:
	if not has(name):
		return null
	var d := data(name)
	var s := Ship.new(String(d["name"]),
		SPEEDS.get(String(d.get("speed", "MEDIUM")), TimeLapse.Speed.MEDIUM),
		KINDS.get(String(d.get("kind", "WARSHIP")), Ship.Kind.WARSHIP))
	s.nation = String(d.get("nation", ""))
	s.type_code = String(d.get("type", ""))
	s.defense = int(d.get("defense", 0))
	s.defense_damaged = int(d.get("defense_damaged", 0))
	s.gun_close = d.get("gun_close", null)
	s.gun_far = d.get("gun_far", null)
	s.gun_close_damaged = d.get("gun_close_damaged", null)
	s.gun_far_damaged = d.get("gun_far_damaged", null)
	s.speed_damaged = SPEEDS.get(String(d.get("speed_damaged", "")), s.speed)
	return s
