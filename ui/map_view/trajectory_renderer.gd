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

const TRACK_MARKERS := {
	"weather_good": preload("res://assets/counters/markers_track_weather.png"),
	"weather_bad": preload("res://assets/counters/markers_track_weatherb.png"),
	"modifier_km": preload("res://assets/counters/markers_track_modifier.png"),
	"modifier_rn": preload("res://assets/counters/markers_track_modifierb.png"),
	"tally_km": preload("res://assets/counters/markers_track_tally_km.png"),
	"tally_rn": preload("res://assets/counters/markers_track_tally_rn.png"),
	"vp_km": preload("res://assets/counters/markers_track_vp.png"),
	"vp_km_10": preload("res://assets/counters/markers_track_vp_10.png"),
	"vp_rn": preload("res://assets/counters/markers_track_vprn.png"),
	"vp_rn_10": preload("res://assets/counters/markers_track_vprn_10.png"),
}

## Posizione del segnalino Meteo nel modulo VASSAL originale. Il segnalino si
## gira fra Buono e Cattivo, ma resta nella stessa casella della tabella.
const WEATHER_MARKER_POSITION := Vector2(3195, 1161)

const EVASIVE_MARKER := preload("res://assets/counters/markers_evasive.png")
const INTEL_MARKERS := {
	TaskForce.Side.KRIEGSMARINE: preload("res://assets/counters/intel_ge.png"),
	TaskForce.Side.ROYAL_NAVY: preload("res://assets/counters/intel_uk.png"),
}
const CONTACT_MARKERS := {
	TaskForce.Side.KRIEGSMARINE: preload("res://assets/counters/markers_ge_contact.png"),
	TaskForce.Side.ROYAL_NAVY: preload("res://assets/counters/markers_uk_contact.png"),
}
const AIR_ACTION_MARKERS := {
	TaskForce.Side.KRIEGSMARINE: {
		"launch": preload("res://assets/counters/markers_ge_action_launch.png"),
		"strike": preload("res://assets/counters/markers_ge_actionstrike.png"),
	},
	TaskForce.Side.ROYAL_NAVY: {
		"launch": preload("res://assets/counters/markers_uk_launch.png"),
		"strike": preload("res://assets/counters/markers_uk_strike.png"),
	},
}

## Designazioni temporanee di un Attacco Aereo. Non sono stato di partita:
## esistono dalla dichiarazione fino alla fine dello Scorrere del Tempo.
var air_action_side: int = -1
var air_launch_hex: Vector2i = Vector2i.MAX
var air_strike_hex: Vector2i = Vector2i.MAX

## Centri delle caselle 0 e 9, letti sulla mappa a risoluzione nativa. Il
## tracciato e' inclinato, quindi ogni colonna ha i propri estremi.
const TRACK_ENDPOINTS := {
	"modifier": [Vector2(2801, 2224), Vector2(2939, 1507)],
	"vp": [Vector2(2899, 2240), Vector2(3024, 1525)],
	"tally": [Vector2(2998, 2257), Vector2(3107, 1542)],
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

## Scostamento delle Stazioni quando piu' Task Force condividono lo stesso
## esagono. Brest in BL1 e' il caso tipico: se si disegna tutto al centro, una
## Stazione sparisce sotto l'altra pur essendo correttamente piazzata.
var _station_lanes: Dictionary = {}


## Puo' essere richiamato per cambiare superficie di gioco: i cinque scenari
## solitari su mappa inserto rimettono qui un altro grafo. La connessione al
## segnale va quindi rifatta con criterio, non aggiunta una seconda volta.
func setup(p_graph: MapGraph, p_state: GameState) -> void:
	if state != null and state.changed.is_connected(queue_redraw):
		state.changed.disconnect(queue_redraw)
	graph = p_graph
	state = p_state
	if not state.changed.is_connected(queue_redraw):
		state.changed.connect(queue_redraw)
	queue_redraw()


func color_for(tf: TaskForce) -> Color:
	return COLORS.get(tf.color, Color(0.5, 0.5, 0.5))


func _draw() -> void:
	if state == null or graph == null:
		return

	_compute_lanes()
	for tf in state.task_forces:
		if not tf.completed:
			_draw_task_force(tf)
	_draw_air_action_markers()
	_draw_rendezvous_markers()
	_draw_map_tracks()

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
	_station_lanes.clear()
	var occupied: Dictionary = {}          # Vector2i -> { corsia: true }
	var stations_by_hex: Dictionary = {}   # Vector2i -> Array[TaskForce]

	# le Stazioni si prendono la corsia zero del loro esagono: sono cerchi
	# piantati sul centro, e le linee di passaggio devono scansarle
	for tf in state.task_forces:
		if tf.completed:
			continue
		if tf.trajectory.is_station():
			var h := tf.trajectory.station_hex
			if not stations_by_hex.has(h):
				stations_by_hex[h] = []
			(stations_by_hex[h] as Array).append(tf)
			if not occupied.has(h):
				occupied[h] = {}
			(occupied[h] as Dictionary)[0] = true

	for h_v: Variant in stations_by_hex.keys():
		var tfs: Array = stations_by_hex[h_v]
		for i in tfs.size():
			var lane := 0
			if i > 0:
				lane = int(ceil(i / 2.0)) * (1 if i % 2 == 1 else -1)
			_station_lanes[(tfs[i] as TaskForce).id] = lane

	for tf in state.task_forces:
		if tf.completed:
			continue
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
		var station_pos := graph.center_of(traj.station_hex)
		var station_lane: int = int(_station_lanes.get(tf.id, 0))
		if station_lane != 0:
			station_pos += Vector2(graph.inradius * 0.44,
				-graph.inradius * 0.24) * float(station_lane)
		_draw_station(station_pos, col, is_sel, tf)
		if tf.evasive:
			_draw_evasive_marker(station_pos + Vector2(graph.inradius * 0.72, 0))
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
		_draw_end_badge(line[0], "T", col, is_sel)
		_draw_end_badge(line[line.size() - 1], "C", col, is_sel)
	elif line.size() == 1:
		draw_circle(line[0], w * 1.2, col)

	# segnalini sui segmenti: seguono la corsia, se no restano staccati
	# dalla linea a cui appartengono
	for i in traj.segments.size():
		var seg: Dictionary = traj.segments[i]
		var c: Vector2 = pts[i] if i < pts.size() \
			else graph.center_of(seg["hex"] as Vector2i)
		if seg["info"]:
			_draw_info_marker(c, tf.side)
		if seg["contact"]:
			_draw_contact_marker(c, tf.side)

	# badge col nome: in coda alla Traiettoria, un po' oltre il capo, cosi' non
	# copre ne' la linea ne' i segnalini
	if pts.size() >= 2:
		var back := (pts[0] - pts[1]).normalized()
		_draw_badge(pts[0] + back * graph.inradius * 0.62,
			tf.short_name(), col, is_sel)

		if is_sel:
			_draw_label(pts[pts.size() - 1] + Vector2(0, -graph.inradius * 0.75),
				"%d seg" % traj.length(), col)
	if tf.evasive and not pts.is_empty():
		_draw_evasive_marker(pts[0] + Vector2(0, graph.inradius * 0.70))


func _draw_rendezvous_markers() -> void:
	for rv_v: Variant in state.rendezvous_markers:
		var rv: Dictionary = rv_v
		if not bool(rv.get("active", true)):
			continue
		var h := Vector2i(int(rv.get("q", 0)), int(rv.get("r", 0)))
		if not graph.is_playable(h):
			continue
		var c := graph.center_of(h)
		var s := graph.inradius * 0.44
		var rect := Rect2(c - Vector2(s, s), Vector2(s * 2, s * 2))
		draw_rect(rect, Color(0.80, 0.98, 1.0, 0.92), true)
		draw_rect(rect, Color(0.02, 0.15, 0.20, 0.92), false, 4.0)
		draw_rect(rect.grow(graph.inradius * 0.06), Color(1, 1, 1, 0.76), false, 2.0)
		_draw_label(c, "RV", Color(0.02, 0.15, 0.20), 0.32)


func _track_position(column: String, value: int) -> Vector2:
	var ends: Array = TRACK_ENDPOINTS[column]
	return (ends[0] as Vector2).lerp(ends[1] as Vector2,
		float(clampi(value, 0, 9)) / 9.0)


func _draw_track_counter(texture: Texture2D, column: String, value: int,
		offset: Vector2 = Vector2.ZERO, exact_label: String = "") -> void:
	var size := Vector2(texture.get_width(), texture.get_height())
	var pos := _track_position(column, value) + offset
	var ends: Array = TRACK_ENDPOINTS[column]
	# Le caselle sono quasi verticali ma inclinate in modo diverso per ogni
	# colonna. L'asse X della pedina deve seguire il bordo corto delle caselle.
	var rotation := ((ends[1] as Vector2) - (ends[0] as Vector2)).angle() + PI / 2.0
	draw_set_transform(pos, rotation)
	draw_texture_rect(texture, Rect2(-size * 0.5, size), false)
	draw_set_transform(Vector2.ZERO, 0.0)
	if exact_label != "":
		_draw_badge(pos + Vector2(0, size.y * 0.72), exact_label,
			Color(0.08, 0.09, 0.11), true)


## Stato delle quattro pedine di plancia. Modificatore, VP e Tally sono pedine
## bifacciali nel gioco fisico: il colore indica la parte e non esistono due
## pedine affiancate. Il VP registra il saldo fra i due punteggi.
static func map_track_marker_state(p_state: GameState) -> Dictionary:
	var modifier_side := p_state.modifier_track_side
	var modifier_value := p_state.modifier_track_value
	if modifier_value < 0:
		modifier_side = 1 - modifier_side
		modifier_value = -modifier_value

	var vp_delta := p_state.vp_of(TaskForce.Side.KRIEGSMARINE) \
		- p_state.vp_of(TaskForce.Side.ROYAL_NAVY)
	var vp_side := TaskForce.Side.KRIEGSMARINE \
		if vp_delta >= 0.0 else TaskForce.Side.ROYAL_NAVY

	return {
		"weather": p_state.weather,
		"modifier_side": modifier_side,
		"modifier_value": modifier_value,
		"vp_side": vp_side,
		"vp_value": absf(vp_delta),
		"tally_side": 1 - p_state.initiative,
		"tally_value": p_state.initiative_count,
	}


func _draw_map_tracks() -> void:
	var markers := map_track_marker_state(state)
	var weather_texture: Texture2D = TRACK_MARKERS["weather_bad"] \
		if int(markers["weather"]) == TimeLapse.Weather.BAD \
		else TRACK_MARKERS["weather_good"]
	var weather_size := Vector2(weather_texture.get_width(), weather_texture.get_height())
	draw_texture_rect(weather_texture,
		Rect2(WEATHER_MARKER_POSITION - weather_size * 0.5, weather_size), false)

	var modifier_side := int(markers["modifier_side"])
	var modifier_texture: Texture2D = TRACK_MARKERS["modifier_km"] \
		if modifier_side == TaskForce.Side.KRIEGSMARINE \
		else TRACK_MARKERS["modifier_rn"]
	_draw_track_counter(modifier_texture, "modifier",
		int(markers["modifier_value"]))

	var vp_side := int(markers["vp_side"])
	var vp_score := float(markers["vp_value"])
	var vp_whole := int(floor(vp_score))
	var vp_key := "vp_km" if vp_side == TaskForce.Side.KRIEGSMARINE else "vp_rn"
	if vp_whole >= 10:
		vp_key += "_10"
	var vp_exact := GameState.vp_str(vp_score) \
		if not is_equal_approx(vp_score, floor(vp_score)) or vp_whole >= 20 else ""
	_draw_track_counter(TRACK_MARKERS[vp_key], "vp", vp_whole % 10,
		Vector2.ZERO, vp_exact)

	var tally_side := int(markers["tally_side"])
	var tally_texture: Texture2D = TRACK_MARKERS["tally_km"] \
		if tally_side == TaskForce.Side.KRIEGSMARINE \
		else TRACK_MARKERS["tally_rn"]
	_draw_track_counter(tally_texture, "tally", int(markers["tally_value"]))


func _draw_end_cap(tip: Vector2, prev: Vector2, col: Color, w: float) -> void:
	var dir := (tip - prev).normalized()
	# il trattino segue lo spessore della linea: con una linea sottile un capo
	# lungo un terzo di esagono sembrerebbe un martello
	var perp := dir.orthogonal() * graph.inradius * 0.20
	draw_line(tip - perp, tip + perp, col, w * 1.1, true)


func _draw_end_badge(pos: Vector2, text: String, col: Color, selected: bool) -> void:
	var r := graph.inradius * (0.18 if selected else 0.14)
	draw_circle(pos, r * 1.45, Color(1, 1, 1, 0.88 if selected else 0.68))
	draw_circle(pos, r, col)
	_draw_label(pos - Vector2(0, r * 0.18), text,
		Color.BLACK if col.get_luminance() > 0.5 else Color.WHITE,
		0.20 if selected else 0.16)


func _draw_station(c: Vector2, col: Color, selected: bool, tf: TaskForce) -> void:
	var r := graph.inradius * 0.36
	if selected:
		draw_circle(c, r * 1.35, Color(1, 1, 1, 0.6))
	draw_circle(c, r, Color(1, 1, 1, 0.92))
	draw_circle(c, r * 0.78, col)
	# una Stazione con Contatto si riconosce a colpo d'occhio
	if tf.trajectory.station_contact:
		_draw_contact_marker(c, tf.side)
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


func _draw_info_marker(c: Vector2, side: int) -> void:
	# Usa la pedina originale: il vecchio quadratino con una sola "I" diventava
	# quasi indistinguibile dalla linea quando si osservava l'intera plancia.
	var texture: Texture2D = INTEL_MARKERS.get(side, INTEL_MARKERS[
		TaskForce.Side.ROYAL_NAVY])
	var marker_size := graph.inradius * 0.72
	var rect := Rect2(c - Vector2.ONE * marker_size * 0.5,
		Vector2.ONE * marker_size)
	draw_rect(rect.grow(graph.inradius * 0.035), Color(1, 1, 1, 0.82), true)
	draw_texture_rect(texture, rect, false)


func _draw_contact_marker(c: Vector2, target_side: int) -> void:
	# Il segnalino appartiene alla parte che ha stabilito il Contatto, cioe'
	# all'avversario della TF sulla quale e' posato.
	var owner := 1 - target_side
	var texture: Texture2D = CONTACT_MARKERS.get(owner, CONTACT_MARKERS[
		TaskForce.Side.ROYAL_NAVY])
	_draw_counter(texture, c, 0.62)


func _draw_evasive_marker(c: Vector2) -> void:
	_draw_counter(EVASIVE_MARKER, c, 0.68)


func _draw_air_action_markers() -> void:
	if air_action_side < 0:
		return
	var textures: Dictionary = AIR_ACTION_MARKERS.get(air_action_side, {})
	if textures.is_empty():
		return
	var same_hex := air_launch_hex != Vector2i.MAX \
		and air_launch_hex == air_strike_hex
	if air_launch_hex != Vector2i.MAX:
		var launch_pos := graph.center_of(air_launch_hex)
		if same_hex:
			launch_pos += Vector2(-graph.inradius * 0.30, 0)
		_draw_counter(textures["launch"], launch_pos, 0.66)
	if air_strike_hex != Vector2i.MAX:
		var strike_pos := graph.center_of(air_strike_hex)
		if same_hex:
			strike_pos += Vector2(graph.inradius * 0.30, 0)
		_draw_counter(textures["strike"], strike_pos, 0.66)


func _draw_counter(texture: Texture2D, c: Vector2, scale_f: float) -> void:
	var side := graph.inradius * scale_f
	var rect := Rect2(c - Vector2.ONE * side * 0.5, Vector2.ONE * side)
	draw_rect(rect.grow(graph.inradius * 0.025), Color(1, 1, 1, 0.72), true)
	draw_texture_rect(texture, rect, false)


func set_air_action_markers(side: int, launch: Vector2i,
		strike: Vector2i) -> void:
	air_action_side = side
	air_launch_hex = launch
	air_strike_hex = strike
	queue_redraw()


func clear_air_action_markers() -> void:
	air_action_side = -1
	air_launch_hex = Vector2i.MAX
	air_strike_hex = Vector2i.MAX
	queue_redraw()


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
