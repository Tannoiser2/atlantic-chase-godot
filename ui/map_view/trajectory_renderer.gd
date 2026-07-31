class_name TrajectoryRenderer
extends Node2D

## Disegna Stazioni e Traiettorie in modo procedurale.
##
## Scelta deliberata: NON si usano le pedine Trajectory_*.png del modulo VASSAL.
## Disegnare la linea a codice da tre vantaggi concreti:
##   - resta nitida a qualunque zoom (le pedine sono 120x24 px fissi)
##   - non c'e' nulla da allineare o ruotare a mano
##   - si puo' evidenziare la Traiettoria sotto il cursore, animare l'aggiunta
##     e la rimozione dei segmenti, e mostrare i capi in modo esplicito

var graph: MapGraph
var state: GameState

var selected_tf_id: int = -1
var hovered_tf_id: int = -1

## Anteprima della traiettoria in costruzione: lista di esagoni + capo.
var preview_hexes: Array[Vector2i] = []
var preview_valid: bool = true

const COLORS := {
	"GE": Color(0.16, 0.18, 0.22),
	"Brown": Color(0.44, 0.29, 0.16),
	"Tan": Color(0.80, 0.68, 0.44),
	"Red": Color(0.66, 0.15, 0.15),
}


func setup(p_graph: MapGraph, p_state: GameState) -> void:
	graph = p_graph
	state = p_state
	state.changed.connect(queue_redraw)
	queue_redraw()


func color_for(tf: TaskForce) -> Color:
	return COLORS.get(tf.color, Color(0.5, 0.5, 0.5))


func _draw() -> void:
	if state == null or graph == null:
		return

	for tf in state.task_forces:
		_draw_task_force(tf)

	if not preview_hexes.is_empty():
		_draw_preview()


func _draw_task_force(tf: TaskForce) -> void:
	var col := color_for(tf)
	var is_sel := tf.id == selected_tf_id
	var is_hov := tf.id == hovered_tf_id
	var traj := tf.trajectory
	var w := graph.inradius * 0.20
	if is_sel:
		w *= 1.35

	if traj.is_station():
		_draw_station(graph.center_of(traj.station_hex), col, is_sel, tf)
		return

	# linea attraverso i centri degli esagoni dei segmenti
	var pts := PackedVector2Array()
	for h in traj.hexes():
		pts.append(graph.center_of(h))

	if pts.size() >= 2:
		if is_sel or is_hov:
			draw_polyline(pts, Color(1, 1, 1, 0.55), w * 2.1, true)
		draw_polyline(pts, col, w, true)
	elif pts.size() == 1:
		draw_circle(pts[0], w * 1.2, col)

	# capi: un trattino perpendicolare rende evidente dove si puo' estendere
	if pts.size() >= 2:
		_draw_end_cap(pts[0], pts[1], col, w)
		_draw_end_cap(pts[-1], pts[-2], col, w)

	# segnalini sui segmenti
	for i in traj.segments.size():
		var seg: Dictionary = traj.segments[i]
		var c := graph.center_of(seg["hex"] as Vector2i)
		if seg["info"]:
			_draw_info_marker(c, col)
		if seg["contact"]:
			_draw_contact_marker(c)

	if is_sel:
		var label := "%s  %d seg" % [tf.display_name(), traj.length()]
		_draw_label(pts[0] + Vector2(0, -graph.inradius * 0.75), label, col)


func _draw_end_cap(tip: Vector2, prev: Vector2, col: Color, w: float) -> void:
	var dir := (tip - prev).normalized()
	var perp := dir.orthogonal() * graph.inradius * 0.32
	draw_line(tip - perp, tip + perp, col, w * 0.9, true)


func _draw_station(c: Vector2, col: Color, selected: bool, tf: TaskForce) -> void:
	var r := graph.inradius * 0.36
	if selected:
		draw_circle(c, r * 1.35, Color(1, 1, 1, 0.6))
	draw_circle(c, r, Color(1, 1, 1, 0.92))
	draw_circle(c, r * 0.78, col)
	# una Stazione con Contatto si riconosce a colpo d'occhio
	if tf.trajectory.station_contact:
		_draw_contact_marker(c)
	if selected:
		_draw_label(c + Vector2(0, -r * 2.2), tf.display_name(), col)


func _draw_info_marker(c: Vector2, col: Color) -> void:
	# quadrato bianco bordato: e' il segnalino piu' importante del gioco,
	# deve staccare dal fondo azzurro della mappa
	var s := graph.inradius * 0.26
	var r := Rect2(c - Vector2(s, s), Vector2(s * 2, s * 2))
	draw_rect(r, Color(1, 1, 1, 0.95), true)
	draw_rect(r, Color(0.05, 0.05, 0.05, 0.9), false, 3.0)
	_draw_label(c, "I", Color(0.05, 0.05, 0.05), 0.34)


func _draw_contact_marker(c: Vector2) -> void:
	var r := graph.inradius * 0.20
	draw_arc(c, r * 1.9, 0, TAU, 24, Color(1.0, 0.45, 0.0, 0.95), 4.0, true)


func _draw_label(pos: Vector2, text: String, col: Color, scale_f: float = 0.30) -> void:
	var font := ThemeDB.fallback_font
	var size := int(graph.inradius * scale_f)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w * 0.5, -size * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_preview() -> void:
	var col := Color(0.3, 1.0, 0.4, 0.85) if preview_valid else Color(1.0, 0.25, 0.25, 0.85)
	var pts := PackedVector2Array()
	for h in preview_hexes:
		pts.append(graph.center_of(h))
	if pts.size() >= 2:
		draw_polyline(pts, col, graph.inradius * 0.16, true)
	for p in pts:
		draw_circle(p, graph.inradius * 0.13, col)


func set_preview(hexes: Array[Vector2i], valid: bool) -> void:
	preview_hexes = hexes
	preview_valid = valid
	queue_redraw()


func clear_preview() -> void:
	preview_hexes.clear()
	queue_redraw()
