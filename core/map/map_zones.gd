class_name MapZones
extends RefCounted

## Linea Artica e Zona U-Boat della Mappa Operazionale.
##
## Sono disegnate sulla mappa e contano in sei regole, ma fino a qui non erano
## un dato: il motore le dichiarava come lacune e tirava dritto. Adesso stanno
## in `core/data/map_zones.json`, lette dalla mappa stampata, con i due esagoni
## in cui la lettura e' dubbia tenuti FUORI e scritti come dubbi.
##
## Lo stato le riceve da `Scenario.to_state_dict()` e le salva con se': cosi'
## le regole le interrogano su `GameState` senza conoscere il grafo, e uno
## scenario su mappa inserto - dove quelle coordinate vorrebbero dire un altro
## mare - semplicemente non le ha.

const PATH := "res://core/data/map_zones.json"

static var _data: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_data = parsed


## Gli esagoni di una zona come lista di [q, r]. `key`: "arctic_line" o
## "uboat_zone"; `field`: "hexes" o "dubbi".
static func hexes(key: String, field: String = "hexes") -> Array:
	_load()
	var zone: Variant = _data.get(key, {})
	if typeof(zone) != TYPE_DICTIONARY:
		return []
	var out: Variant = (zone as Dictionary).get(field, [])
	return out if typeof(out) == TYPE_ARRAY else []
