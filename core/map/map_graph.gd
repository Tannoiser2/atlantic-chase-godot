class_name MapGraph
extends RefCounted

## Il grafo della mappa principale: esagoni giocabili, adiacenze, geometria.
##
## Caricato da core/data/map_graph.json, generato da tools/build_map_graph.py e
## rifinito con tools/map_editor.
##
## Nota importante: l'adiacenza NON e' solo geometrica. La mappa stampa frecce
## "not adjacent" che negano il passaggio attraverso la terraferma (Firth of
## Forth, Irlanda, Galles, ...). Quei lati stanno in `blocked_edges` e questa
## classe li rispetta in `is_adjacent()`.

const DATA_PATH := "res://core/data/map_graph.json"

var map_size: Vector2i
var map_image: String

# geometria del reticolo
var spacing: float
var theta_deg: float
var origin: Vector2
var circumradius: float
var inradius: float
var e1: Vector2
var e2: Vector2
var _inv_a: float
var _inv_b: float
var _inv_c: float
var _inv_d: float

# topologia
var hexes: Dictionary = {}          # Vector2i -> Dictionary
var _blocked: Dictionary = {}       # "q,r|q,r" -> true
## Lati percorribili da una sola parte (es. il Canale di Kiel, "German only").
## chiave lato -> { "side": int, "label": String }
var _restricted: Dictionary = {}
var ports: Dictionary = {}          # String -> Dictionary

var load_error: String = ""


static func load_default() -> MapGraph:
	var g := MapGraph.new()
	g.load_from(DATA_PATH)
	return g


func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "impossibile aprire %s" % path
		push_error(load_error)
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error = "JSON non valido in %s" % path
		push_error(load_error)
		return false
	return _apply(parsed as Dictionary)


func _apply(d: Dictionary) -> bool:
	map_image = String(d.get("map_image", ""))
	var ms: Array = d.get("map_size", [0, 0])
	map_size = Vector2i(int(ms[0]), int(ms[1]))

	var lat: Dictionary = d.get("lattice", {})
	spacing = float(lat.get("spacing_px", 213.5))
	theta_deg = float(lat.get("theta_deg", 44.28))
	var o: Array = lat.get("origin_px", [0, 0])
	origin = Vector2(float(o[0]), float(o[1]))
	circumradius = float(lat.get("circumradius_px", spacing / sqrt(3.0)))
	inradius = float(lat.get("inradius_px", spacing / 2.0))
	var a1: Array = lat.get("basis_e1", [])
	var a2: Array = lat.get("basis_e2", [])
	if a1.size() == 2 and a2.size() == 2:
		e1 = Vector2(float(a1[0]), float(a1[1]))
		e2 = Vector2(float(a2[0]), float(a2[1]))
	else:
		var t := deg_to_rad(theta_deg)
		e1 = Vector2(cos(t), sin(t)) * spacing
		e2 = Vector2(cos(t + PI / 3.0), sin(t + PI / 3.0)) * spacing
	_compute_inverse()

	hexes.clear()
	for h_v: Variant in d.get("hexes", []):
		var h: Dictionary = h_v
		var key := Vector2i(int(h["q"]), int(h["r"]))
		var nbrs: Array[Vector2i] = []
		for n_v: Variant in h.get("neighbors", []):
			var n: Dictionary = n_v
			nbrs.append(Vector2i(int(n["q"]), int(n["r"])))
		hexes[key] = {
			"center": Vector2(float(h["cx"]), float(h["cy"])),
			"land_frac": float(h.get("land_frac", 0.0)),
			"coastal": bool(h.get("coastal", false)),
			"neighbors": nbrs,
		}

	_blocked.clear()
	for b_v: Variant in d.get("blocked_edges", []):
		var b: Dictionary = b_v
		var x := Vector2i(int(b["aq"]), int(b["ar"]))
		var y := Vector2i(int(b["bq"]), int(b["br"]))
		_blocked[_edge_key(x, y)] = true

	_restricted.clear()
	for r_v: Variant in d.get("restricted_edges", []):
		var rr: Dictionary = r_v
		var x2 := Vector2i(int(rr["aq"]), int(rr["ar"]))
		var y2 := Vector2i(int(rr["bq"]), int(rr["br"]))
		var side := TaskForce.Side.KRIEGSMARINE
		if String(rr.get("side", "")) == "ROYAL_NAVY":
			side = TaskForce.Side.ROYAL_NAVY
		_restricted[_edge_key(x2, y2)] = {
			"side": side, "label": String(rr.get("label", "")),
		}

	ports.clear()
	for p_v: Variant in d.get("ports", []):
		var p: Dictionary = p_v
		var rec := p.duplicate()
		rec["hex"] = Vector2i(int(p.get("q", 0)), int(p.get("r", 0)))
		ports[String(p["name"])] = rec

	return true


## L'esagono di un porto, o Vector2i.MAX se sconosciuto.
func port_hex(name: String) -> Vector2i:
	if ports.has(name):
		return (ports[name] as Dictionary)["hex"]
	return Vector2i.MAX


## Tutti i porti che stanno in un esagono (piu' porti possono condividerlo:
## Clyde e Liverpool stanno entrambi in 15,-4).
func ports_in(h: Vector2i) -> Array[String]:
	var out: Array[String] = []
	for k_v: Variant in ports.keys():
		if (ports[k_v] as Dictionary)["hex"] == h:
			out.append(String(k_v))
	return out


func port_count() -> int:
	return ports.size()


func _compute_inverse() -> void:
	# inversa della matrice [e1 e2] (colonne), per pixel -> assiali
	var det := e1.x * e2.y - e2.x * e1.y
	if is_zero_approx(det):
		push_error("base del reticolo degenere")
		det = 1.0
	_inv_a = e2.y / det
	_inv_b = -e2.x / det
	_inv_c = -e1.y / det
	_inv_d = e1.x / det


# --------------------------------------------------------------- geometria --

func hex_to_pixel(h: Vector2i) -> Vector2:
	return origin + e1 * float(h.x) + e2 * float(h.y)


func pixel_to_hex(p: Vector2) -> Vector2i:
	var rel := p - origin
	var qf := _inv_a * rel.x + _inv_b * rel.y
	var rf := _inv_c * rel.x + _inv_d * rel.y
	return Hex.round_axial(qf, rf)


## I 6 vertici dell'esagono in pixel. I lati sono perpendicolari alle direzioni
## dei vicini, quindi i vertici stanno a theta + 30 + k*60.
func hex_corners(h: Vector2i) -> PackedVector2Array:
	var c := hex_to_pixel(h)
	var out := PackedVector2Array()
	for k in 6:
		var a := deg_to_rad(theta_deg + 30.0 + 60.0 * float(k))
		out.append(c + Vector2(cos(a), sin(a)) * circumradius)
	return out


# --------------------------------------------------------------- topologia --

func has_hex(h: Vector2i) -> bool:
	return hexes.has(h)


func center_of(h: Vector2i) -> Vector2:
	if hexes.has(h):
		return (hexes[h] as Dictionary)["center"]
	return hex_to_pixel(h)


func is_playable(h: Vector2i) -> bool:
	return hexes.has(h)


func land_fraction(h: Vector2i) -> float:
	if hexes.has(h):
		return (hexes[h] as Dictionary)["land_frac"]
	return 0.0


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	# chiave simmetrica
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


## Adiacenza di gioco: geometrica, entrambi giocabili, e non negata da una
## freccia "not adjacent".
func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	if not Hex.are_adjacent(a, b):
		return false
	if not (hexes.has(a) and hexes.has(b)):
		return false
	return not _blocked.has(_edge_key(a, b))


## Adiacenza per una parte specifica. Aggiunge ai vincoli di is_adjacent() i
## lati riservati a una nazione: il Canale di Kiel e' percorribile solo dalle
## Task Force tedesche ("KW Kanal German only" stampato sulla mappa).
func is_adjacent_for(side: int, a: Vector2i, b: Vector2i) -> bool:
	if not is_adjacent(a, b):
		return false
	var k := _edge_key(a, b)
	if _restricted.has(k):
		return int((_restricted[k] as Dictionary)["side"]) == side
	return true


## Etichetta della restrizione su un lato, o stringa vuota.
func restriction_label(a: Vector2i, b: Vector2i) -> String:
	var k := _edge_key(a, b)
	if _restricted.has(k):
		return String((_restricted[k] as Dictionary)["label"])
	return ""


func is_edge_restricted(a: Vector2i, b: Vector2i) -> bool:
	return _restricted.has(_edge_key(a, b))


func restricted_edge_count() -> int:
	return _restricted.size()


func adjacent_hexes(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not hexes.has(h):
		return out
	for n in (hexes[h] as Dictionary)["neighbors"] as Array[Vector2i]:
		if not _blocked.has(_edge_key(h, n)):
			out.append(n)
	return out


func block_edge(a: Vector2i, b: Vector2i, blocked: bool = true) -> void:
	var k := _edge_key(a, b)
	if blocked:
		_blocked[k] = true
	else:
		_blocked.erase(k)


func is_edge_blocked(a: Vector2i, b: Vector2i) -> bool:
	return _blocked.has(_edge_key(a, b))


func blocked_edge_count() -> int:
	return _blocked.size()


func all_hexes() -> Array:
	return hexes.keys()


func hex_count() -> int:
	return hexes.size()
