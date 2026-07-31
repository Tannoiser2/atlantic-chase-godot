class_name MapBoard
extends Node2D

## Disegna la mappa (tile) e il reticolo esagonale.
##
## La mappa e' 4203x2763: come texture unica sarebbero ~46 MB in VRAM, troppi
## per l'export web. Viene caricata a tile da 1024 posizionati sulle coordinate
## originali, cosi' le coordinate del gioco restano quelle della mappa stampata
## e tutti i dati estratti dal modulo VASSAL restano validi senza conversioni.

const MANIFEST := "res://assets/map/manifest.json"

var graph: MapGraph

## Modalita' di disegno del reticolo.
enum GridMode { OFF, SUBTLE, FULL, EDITOR }
var grid_mode: int = GridMode.SUBTLE

var hover_hex: Vector2i = Vector2i.MAX
var selected_hex: Vector2i = Vector2i.MAX
var highlight: Dictionary = {}       ## Vector2i -> Color, esagoni evidenziati

var _tiles_root: Node2D


func setup(p_graph: MapGraph) -> void:
	graph = p_graph
	_load_tiles()
	queue_redraw()


func _load_tiles() -> void:
	if _tiles_root != null:
		_tiles_root.queue_free()
	_tiles_root = Node2D.new()
	_tiles_root.name = "Tiles"
	_tiles_root.z_index = -10
	add_child(_tiles_root)

	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_error("manifest dei tile mancante: esegui tools/prepare_assets.py")
		return
	var m: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(m) != TYPE_DICTIONARY:
		push_error("manifest dei tile illeggibile")
		return
	for t_v: Variant in (m as Dictionary).get("tiles", []):
		var t: Dictionary = t_v
		var tex: Texture2D = load("res://assets/map/%s" % t["file"])
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.position = Vector2(float(t["x"]), float(t["y"]))
		_tiles_root.add_child(s)


func set_grid_mode(m: int) -> void:
	grid_mode = m
	queue_redraw()


func _draw() -> void:
	if graph == null:
		return
	if grid_mode == GridMode.OFF and highlight.is_empty() \
			and hover_hex == Vector2i.MAX:
		return

	var line_col := Color(1, 1, 1, 0.10)
	var width := 2.0
	match grid_mode:
		GridMode.SUBTLE:
			line_col = Color(1, 1, 1, 0.10)
		GridMode.FULL:
			line_col = Color(0.2, 0.9, 1.0, 0.45)
			width = 3.0
		GridMode.EDITOR:
			line_col = Color(1.0, 0.3, 0.3, 0.55)
			width = 3.0

	if grid_mode != GridMode.OFF:
		for h_v: Variant in graph.all_hexes():
			var pts := graph.hex_corners(h_v)
			pts.append(pts[0])
			draw_polyline(pts, line_col, width, true)

	# lati negati dalle frecce "not adjacent": vanno visti, sono invisibili
	# sulla mappa stampata se non si legge il testo
	if grid_mode == GridMode.EDITOR or grid_mode == GridMode.FULL:
		for h_v: Variant in graph.all_hexes():
			var h: Vector2i = h_v
			for d in 6:
				var n := Hex.neighbor(h, d)
				if not graph.has_hex(n):
					continue
				if graph.is_edge_blocked(h, n):
					var a := graph.center_of(h)
					var b := graph.center_of(n)
					var mid := (a + b) * 0.5
					var perp := (b - a).orthogonal().normalized() * graph.inradius * 0.55
					draw_line(mid - perp, mid + perp, Color(1, 0.15, 0.15, 0.95), 7.0, true)

	for h_v: Variant in highlight.keys():
		var pts := graph.hex_corners(h_v)
		draw_colored_polygon(pts, highlight[h_v])

	if hover_hex != Vector2i.MAX and graph.has_hex(hover_hex):
		var pts := graph.hex_corners(hover_hex)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 0.3, 0.9), 5.0, true)

	if selected_hex != Vector2i.MAX and graph.has_hex(selected_hex):
		var pts := graph.hex_corners(selected_hex)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.3, 1.0, 0.4, 0.95), 6.0, true)


func set_hover(h: Vector2i) -> void:
	if h != hover_hex:
		hover_hex = h
		queue_redraw()


func set_highlight(d: Dictionary) -> void:
	highlight = d
	queue_redraw()
