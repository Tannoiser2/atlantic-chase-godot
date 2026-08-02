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

## Spessore della linea, in frazione di inradius. Volutamente sottile: la mappa
## sotto deve restare leggibile, e con quattro o cinque Traiettorie in acqua
## delle strisce spesse diventano un groviglio.
const LINE_WIDTH := 0.115

## Distanza fra due Traiettorie che passano per lo stesso esagono.
const LANE_SPACING := 0.34

## Raggio degli angoli arrotondati, in frazione di inradius. Sopra ~0.5 la
## curva mangia il segmento corto e la linea non passa piu' per l'esagono.
const CORNER_RADIUS := 0.42

## Punti per ogni angolo curvo. Otto bastano: a questa scala l'occhio non
## distingue di piu' e il disegno resta leggero.
const CURVE_STEPS := 8

## Corsia assegnata a ogni Task Force: tf.id -> intero con segno (0, +1, -1...).
## Ricalcolata a ogni _draw() perche' le Traiettorie cambiano di continuo.
var _lanes: Dictionary = {}


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

	_compute_lanes()
	for tf in state.task_forces:
		_draw_task_force(tf)

	if not preview_hexes.is_empty():
		_draw_preview()


# ------------------------------------------------------------ corsie --

## Assegna a ogni Task Force una corsia, cioe' di quanto scostare la sua linea
## dai centri degli esagoni perche' non finisca sotto quella di un'altra.
##
## Le corsie vanno 0, +1, -1, +2, -2...: la corsia ZERO passa esattamente per i
## centri, ed e' quella che prende chi non ha nessuno intorno. Cosi' una
## Traiettoria isolata resta disegnata dove il gioco dice che sta, e lo
## scostamento e' un rimedio che si paga solo quando serve davvero.
##
## La corsia e' UNA per Traiettoria, non una per segmento: se cambiasse strada
## facendo, la linea si spezzerebbe a ogni esagono condiviso.
func _compute_lanes() -> void:
	_lanes.clear()
	var occupied: Dictionary = {}          # Vector2i -> { corsia: true }

	# le Stazioni si prendono la corsia zero del loro esagono: sono cerchi
	# piantati sul centro, e le linee di passaggio devono scansarle
	for tf in state.task_forces:
		if tf.trajectory.is_station():
			var h := tf.trajectory.station_hex
			if not occupied.has(h):
				occupied[h] = {}
			(occupied[h] as Dictionary)[0] = true

	for tf in state.task_forces:
		if tf.trajectory.is_station():
			continue
		var hexes := tf.trajectory.hexes()
		var taken: Dictionary = {}
		for h in hexes:
			for lane_v: Variant in occupied.get(h, {}):
				taken[lane_v] = true
		var lane := 0
		for i in 24:
			var cand := int(ceil(i / 2.0)) * (1 if i % 2 == 1 else -1)
			if not taken.has(cand):
				lane = cand
				break
		_lanes[tf.id] = lane
		for h in hexes:
			if not occupied.has(h):
				occupied[h] = {}
			(occupied[h] as Dictionary)[lane] = true


## Sposta ogni punto della spezzata di `d` pixel, perpendicolarmente alla
## direzione locale della linea. Nei punti interni la direzione si prende fra il
## punto PRIMA e quello DOPO: e' la bisettrice dell'angolo, ed e' quello che
## tiene lo scostamento continuo anche dove la linea gira.
func _offset(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	if is_zero_approx(d) or pts.size() < 2:
		return pts
	var out := PackedVector2Array()
	for i in pts.size():
		var a := pts[max(i - 1, 0)]
		var b := pts[min(i + 1, pts.size() - 1)]
		var dir := (b - a).normalized()
		out.append(pts[i] + dir.orthogonal() * d)
	return out


## Arrotonda gli angoli di una spezzata con una Bezier quadratica per vertice.
##
## Il punto di controllo e' il vertice stesso: e' questo che rende il conto
## banale invece che geometria vera. Si torna indietro di `radius` lungo i due
## lati - mai piu' della loro meta', se no due angoli vicini si mangiano a
## vicenda - e si curva fra i due punti cosi' trovati.
func _rounded(pts: PackedVector2Array, radius: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size() - 1):
		var a := pts[i - 1]
		var b := pts[i]
		var c := pts[i + 1]
		var r_in: float = minf(radius, a.distance_to(b) * 0.5)
		var r_out: float = minf(radius, b.distance_to(c) * 0.5)
		var p0 := b + (a - b).normalized() * r_in
		var p2 := b + (c - b).normalized() * r_out
		out.append(p0)
		for s in range(1, CURVE_STEPS):
			var t := float(s) / CURVE_STEPS
			out.append(p0.lerp(b, t).lerp(b.lerp(p2, t), t))
		out.append(p2)
	out.append(pts[pts.size() - 1])
	return out


# ------------------------------------------------------------ disegno --

func _draw_task_force(tf: TaskForce) -> void:
	var col := color_for(tf)
	var is_sel := tf.id == selected_tf_id
	var is_hov := tf.id == hovered_tf_id
	var traj := tf.trajectory
	var w := graph.inradius * LINE_WIDTH
	if is_sel:
		w *= 1.6

	if traj.is_station():
		_draw_station(graph.center_of(traj.station_hex), col, is_sel, tf)
		return

	# linea attraverso i centri degli esagoni dei segmenti, scostata sulla
	# propria corsia e arrotondata agli angoli
	var raw := PackedVector2Array()
	for h in traj.hexes():
		raw.append(graph.center_of(h))
	var lane: int = int(_lanes.get(tf.id, 0))
	var pts := _offset(raw, lane * graph.inradius * LANE_SPACING)
	var line := _rounded(pts, graph.inradius * CORNER_RADIUS)

	if line.size() >= 2:
		if is_sel or is_hov:
			draw_polyline(line, Color(1, 1, 1, 0.6), w * 2.8, true)
		# fodera scura: una linea sottile sul fondo azzurro della mappa
		# sparirebbe, questa la stacca senza ingrossarla
		draw_polyline(line, Color(0, 0, 0, 0.35), w * 1.9, true)
		draw_polyline(line, col, w, true)
		# capi: un trattino perpendicolare rende evidente dove si puo' estendere
		_draw_end_cap(line[0], line[1], col, w)
		_draw_end_cap(line[line.size() - 1], line[line.size() - 2], col, w)
	elif line.size() == 1:
		draw_circle(line[0], w * 1.2, col)

	# segnalini sui segmenti: seguono la corsia, se no restano staccati
	# dalla linea a cui appartengono
	for i in traj.segments.size():
		var seg: Dictionary = traj.segments[i]
		var c: Vector2 = pts[i] if i < pts.size() \
			else graph.center_of(seg["hex"] as Vector2i)
		if seg["info"]:
			_draw_info_marker(c, col)
		if seg["contact"]:
			_draw_contact_marker(c)

	# badge col nome: in coda alla Traiettoria, un po' oltre il capo, cosi' non
	# copre ne' la linea ne' i segnalini
	if pts.size() >= 2:
		var back := (pts[0] - pts[1]).normalized()
		_draw_badge(pts[0] + back * graph.inradius * 0.62,
			tf.short_name(), col, is_sel)

	if is_sel:
		_draw_label(pts[pts.size() - 1] + Vector2(0, -graph.inradius * 0.75),
			"%d seg" % traj.length(), col)


func _draw_end_cap(tip: Vector2, prev: Vector2, col: Color, w: float) -> void:
	var dir := (tip - prev).normalized()
	# il trattino segue lo spessore della linea: con una linea sottile un capo
	# lungo un terzo di esagono sembrerebbe un martello
	var perp := dir.orthogonal() * graph.inradius * 0.20
	draw_line(tip - perp, tip + perp, col, w * 1.1, true)


func _draw_station(c: Vector2, col: Color, selected: bool, tf: TaskForce) -> void:
	var r := graph.inradius * 0.36
	if selected:
		draw_circle(c, r * 1.35, Color(1, 1, 1, 0.6))
	draw_circle(c, r, Color(1, 1, 1, 0.92))
	draw_circle(c, r * 0.78, col)
	# una Stazione con Contatto si riconosce a colpo d'occhio
	if tf.trajectory.station_contact:
		_draw_contact_marker(c)
	_draw_badge(c + Vector2(0, -r * 1.9), tf.short_name(), col, selected)


## Il badge col nome della Task Force.
##
## Il testo va bianco o nero secondo quanto e' chiaro il colore della Task
## Force: il Tan e' quasi giallo, e su quello il bianco non si legge.
func _draw_badge(pos: Vector2, text: String, col: Color,
		emphasised: bool = false) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var size := int(maxf(graph.inradius * 0.25, 9.0))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pad := size * 0.38
	var rect := Rect2(pos - Vector2(tw * 0.5 + pad, size * 0.62 + pad * 0.4),
		Vector2(tw + pad * 2, size + pad * 0.8))
	var bg := col.darkened(0.12)
	draw_rect(rect, Color(bg.r, bg.g, bg.b, 0.93), true)
	draw_rect(rect, Color(1, 1, 1, 0.9 if emphasised else 0.55), false,
		2.0 if emphasised else 1.0)
	var fg := Color.BLACK if col.get_luminance() > 0.5 else Color.WHITE
	draw_string(font, pos - Vector2(tw * 0.5, -size * 0.30), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, fg)


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
		draw_polyline(_rounded(pts, graph.inradius * CORNER_RADIUS), col,
			graph.inradius * LINE_WIDTH * 1.2, true)
	for p in pts:
		draw_circle(p, graph.inradius * 0.11, col)


func set_preview(hexes: Array[Vector2i], valid: bool) -> void:
	preview_hexes = hexes
	preview_valid = valid
	queue_redraw()


func clear_preview() -> void:
	preview_hexes.clear()
	queue_redraw()
