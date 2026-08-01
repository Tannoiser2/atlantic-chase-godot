class_name BattleView
extends Control

## Vista della Mappa di Battaglia.
##
## Sulla mappa stampata la Battaglia e' un pannello verticale a cinque bande:
##
##     LONTANA   (avversario)
##     VICINA    (avversario)
##     RAVVICINATA        <- la fascia centrale, divisa a meta' fra i due lati
##     VICINA    (giocatore Attivo)
##     LONTANA   (giocatore Attivo)
##
## Qui e' disegnata a codice invece di ritagliare il pannello GMT: le pedine
## restano leggibili a qualunque dimensione di finestra, si puo' evidenziare la
## nave selezionata e mostrare i valori che contano (cannoni per raggio, Difesa,
## Colpi) senza doverli cercare sulla pedina.

signal closed()

const ZONE_ORDER := [
	# [lato, zona]  dall'alto in basso; il lato Bersaglio sta in alto
	["target", BattleState.Zone.FAR],
	["target", BattleState.Zone.NEAR],
	["target", BattleState.Zone.CLOSE],
	["active", BattleState.Zone.CLOSE],
	["active", BattleState.Zone.NEAR],
	["active", BattleState.Zone.FAR],
]

const BAND_COLORS := {
	BattleState.Zone.FAR: Color(0.42, 0.56, 0.60, 0.85),
	BattleState.Zone.NEAR: Color(0.48, 0.63, 0.67, 0.85),
	BattleState.Zone.CLOSE: Color(0.55, 0.71, 0.74, 0.9),
}

var battle: Battle
var state: BattleState
var roster: ShipRoster

var selected: Ship = null

## Trascinamento della nave fra le zone: si prende la pedina e la si porta
## nella banda voluta. E' il gesto naturale sulla Mappa di Battaglia, dove
## muovere significa proprio spostare la pedina di una zona.
var _drag_ship: Ship = null
var _drag_pos: Vector2 = Vector2.ZERO
var _drag_target_band: int = -1
var _bands: Array[Rect2] = []
var _ship_rects: Array = []          ## [{rect, ship}]
## Le pedine sono nodi TextureRect, non disegnate in _draw(): con
## draw_texture_rect() su questo renderer uscivano bianche, e come nodi si
## possono comunque evidenziare e in futuro dotare di tooltip.
var _ship_nodes: Node2D
var _log: RichTextLabel
var _header: RichTextLabel
var _hint: Label


func setup(p_battle: Battle) -> void:
	battle = p_battle
	state = p_battle.state
	roster = ShipRoster.shared()
	# Un Control figlio di un CanvasLayer non eredita il rettangolo del viewport.
	# Si dimensiona a mano: mettere ANCHE il preset di ancoraggio fa litigare i
	# due meccanismi e Godot avvisa che la dimensione verra' sovrascritta.
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)
	_ship_nodes = Node2D.new()
	_ship_nodes.name = "Pedine"
	add_child(_ship_nodes)
	_build_ui()
	refresh()


func _on_viewport_resized() -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _build_ui() -> void:
	var head := PanelContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 12
	head.offset_right = -12
	head.offset_top = 10
	head.add_theme_stylebox_override("panel", _panel_style())
	add_child(head)
	_header = RichTextLabel.new()
	_header.bbcode_enabled = true
	_header.fit_content = true
	_header.custom_minimum_size = Vector2(0, 52)
	head.add_child(_header)

	var logp := PanelContainer.new()
	logp.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	logp.offset_left = 12
	logp.offset_right = -12
	logp.offset_top = -190
	logp.offset_bottom = -46
	logp.add_theme_stylebox_override("panel", _panel_style())
	add_child(logp)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	logp.add_child(_log)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 16
	_hint.offset_top = -38
	_hint.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	add_child(_hint)


static func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.92)
	sb.border_color = Color(0.45, 0.60, 0.72, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


# ------------------------------------------------------------------ disegno --

func _draw() -> void:
	if state == null:
		return
	# fondo pieno: la Battaglia occupa tutto lo schermo, la mappa operazionale
	# non deve trasparire e confondere
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.09, 0.97))
	var area := Rect2(Vector2(40, 96), size - Vector2(80, 310))
	# la fascia Ravvicinata e' piu' stretta delle altre, come sulla mappa
	var weights := [1.0, 1.0, 0.55, 0.55, 1.0, 1.0]
	var total := 0.0
	for w in weights:
		total += w
	_bands.clear()
	_ship_rects.clear()
	if _ship_nodes != null:
		for c in _ship_nodes.get_children():
			c.queue_free()

	var y := area.position.y
	var font := ThemeDB.fallback_font
	for i in ZONE_ORDER.size():
		var h := area.size.y * float(weights[i]) / total
		var r := Rect2(area.position.x, y, area.size.x, h - 4)
		_bands.append(r)
		var pair: Array = ZONE_ORDER[i]
		var zone: int = pair[1]
		var is_active: bool = pair[0] == "active"

		draw_rect(r, BAND_COLORS[zone])
		if _drag_ship != null and i == _drag_target_band:
			var reachable := Maneuver.can_move_to(_drag_ship, zone) \
				or _drag_ship.battle_zone == zone
			var same_side := (String(pair[0]) == "active") \
				== state.active_ships().has(_drag_ship)
			draw_rect(r, Color(0.3, 1.0, 0.4, 0.22) if (reachable and same_side)
				else Color(1.0, 0.3, 0.3, 0.18))
		draw_rect(r, Color(1, 1, 1, 0.25), false, 2.0)

		var label := "%s  -  %s" % [
			BattleState.ZONE_LABELS[zone],
			(state.active_tf.display_name() if is_active else state.target_tf.display_name())
				if state.active_tf and state.target_tf else ""]
		draw_string(font, r.position + Vector2(14, 26), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.08, 0.14, 0.18, 0.85))

		_draw_ships_in(r, is_active, zone)
		y += h

	# separatore fra i due lati: la linea di contatto
	if _bands.size() >= 4:
		var mid := (_bands[2].position.y + _bands[2].size.y + _bands[3].position.y) * 0.5
		draw_line(Vector2(area.position.x, mid),
			Vector2(area.position.x + area.size.x, mid),
			Color(1, 0.9, 0.4, 0.85), 3.0)


func _draw_ships_in(band: Rect2, is_active: bool, zone: int) -> void:
	var tf := state.active_tf if is_active else state.target_tf
	if tf == null:
		return
	var ships := state.ships_in_zone(tf, zone)
	if ships.is_empty():
		return
	# Le pedine non hanno tutte lo stesso formato (la Bismarck e' 148x72, il
	# Prinz Eugen 116x56): si scalano a un'altezza comune mantenendo il
	# rapporto, altrimenti le piu' piccole risultano stirate.
	var ch := 66.0
	var gap := 14.0
	var widths: Array[float] = []
	var texs: Array = []
	for s in ships:
		var path := roster.counter_path(s.name, s.damaged)
		var tex: Texture2D = load(path) if path != "" else null
		texs.append(tex)
		widths.append(ch * (tex.get_size().x / tex.get_size().y) if tex != null else 136.0)
	var total := 0.0
	for w in widths:
		total += w + gap
	total -= gap
	var x := band.position.x + (band.size.x - total) * 0.5
	var y := band.position.y + (band.size.y - ch) * 0.5
	var font := ThemeDB.fallback_font

	for i in ships.size():
		var s: Ship = ships[i]
		var cw: float = widths[i]
		var r := Rect2(Vector2(x, y), Vector2(cw, ch))
		var tex: Texture2D = texs[i]
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.position = r.position
			tr.size = r.size
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_ship_nodes.add_child(tr)
		else:
			draw_rect(r, Color(0.75, 0.72, 0.6))
			draw_string(font, r.position + Vector2(8, 24), s.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)

		if s == selected:
			draw_rect(r.grow(4), Color(1, 0.95, 0.3), false, 4.0)
		if s.smoke:
			draw_rect(r, Color(0.85, 0.9, 0.95, 0.35))
			draw_string(font, r.position + Vector2(6, ch - 8), "FUMO",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.1, 0.2, 0.3))
		if s.hits > 0:
			var badge := Rect2(r.position + Vector2(cw - 30, 4), Vector2(26, 22))
			draw_rect(badge, Color(0.75, 0.1, 0.1, 0.95))
			draw_string(font, badge.position + Vector2(8, 17), str(s.hits),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

		_ship_rects.append({"rect": r, "ship": s})
		x += cw + gap


# ------------------------------------------------------------------- input --

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _drag_ship != null:
		_drag_pos = (event as InputEventMouseMotion).position
		_drag_target_band = _band_at(_drag_pos)
		queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			for e_v: Variant in _ship_rects:
				var e: Dictionary = e_v
				if (e["rect"] as Rect2).has_point(mb.position):
					selected = e["ship"]
					if state.phase == BattleState.Phase.MANEUVER:
						_drag_ship = selected
						_drag_pos = mb.position
					queue_redraw()
					refresh()
					return
			# clic su una banda con una nave gia' selezionata: manovra
			if selected != null and state.phase == BattleState.Phase.MANEUVER:
				_move_to_band(selected, _band_at(mb.position))
			return
		# rilascio: se si stava trascinando, la nave va nella banda sotto il mouse
		if _drag_ship != null:
			var target := _drag_target_band
			var ship := _drag_ship
			_drag_ship = null
			_drag_target_band = -1
			if target >= 0:
				_move_to_band(ship, target)
			else:
				queue_redraw()


func _band_at(pos: Vector2) -> int:
	for i in _bands.size():
		if _bands[i].has_point(pos):
			return i
	return -1


func _move_to_band(ship: Ship, band_index: int) -> void:
	if band_index < 0:
		return
	var pair: Array = ZONE_ORDER[band_index]
	var on_active_side: bool = String(pair[0]) == "active"
	var ship_is_active: bool = state.active_ships().has(ship)
	if on_active_side != ship_is_active:
		state.note("una nave manovra solo nelle zone del proprio lato")
		refresh()
		return
	var txt := Maneuver.apply(ship, int(pair[1]), ship.smoke)
	state.note(txt if txt != "" else
		"%s non puo' raggiungere quella zona (si muove di una zona per volta)"
		% ship.name)
	refresh()


func handle_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_SPACE:
			_advance_phase()
			return true
		KEY_S:
			if selected != null and state.phase == BattleState.Phase.MANEUVER:
				var txt := Maneuver.apply(selected, -1, not selected.smoke)
				state.note(txt if txt != "" else
					"%s non puo' creare Fumo" % selected.name)
				refresh()
			return true
		KEY_F:
			if state.phase == BattleState.Phase.BREAK_AWAY:
				_do_break_away(true, false)
			return true
		KEY_G:
			if state.phase == BattleState.Phase.BREAK_AWAY:
				_do_break_away(false, true)
			return true
		KEY_ESCAPE:
			closed.emit()
			return true
	return false


# -------------------------------------------------------------------- fasi --

func _advance_phase() -> void:
	if state.ended:
		closed.emit()
		return
	match state.phase:
		BattleState.Phase.GUNNERY:
			battle.gunnery_phase(battle.auto_targeting())
			if not state.ended:
				state.phase = BattleState.Phase.TORPEDO
		BattleState.Phase.TORPEDO:
			var t := battle.auto_torpedoes()
			if t.is_empty():
				state.note("Nessuna nave con siluri in zona Ravvicinata.")
			else:
				battle.torpedo_phase(t)
			if not state.ended:
				state.phase = BattleState.Phase.MANEUVER
		BattleState.Phase.MANEUVER:
			state.note("Manovra conclusa.")
			state.phase = BattleState.Phase.BREAK_AWAY
		BattleState.Phase.BREAK_AWAY:
			_do_break_away(false, false)
		_:
			closed.emit()
			return
	refresh()


func _do_break_away(active: bool, target: bool) -> void:
	battle.break_away_phase(active, target)
	if not state.ended:
		if battle.end_round():
			pass
	refresh()


# ------------------------------------------------------------------ refresh --

func refresh() -> void:
	queue_redraw()
	if _header == null:
		return
	var lines: Array[String] = []
	lines.append("[b]%s[/b] in %s   -   Round [b]%d[/b] di %d   -   fase [b]%s[/b]" % [
		BattleState.KIND_LABELS[state.kind], str(state.hex),
		state.round_number, state.last_round,
		BattleState.PHASE_LABELS[state.phase]])
	if selected != null:
		var gc: Variant = selected.gun_value("close")
		var gf: Variant = selected.gun_value("far")
		lines.append("Selezionata: [b]%s[/b]  cannoni %s/%s  Difesa %d  Colpi %d  %s%s"
			% [selected.name,
				"na" if gc == null else str(gc), "na" if gf == null else str(gf),
				selected.defense_damaged if selected.damaged else selected.defense,
				selected.hits,
				TimeLapse.SPEED_LABELS[selected.current_speed()],
				"  [danneggiata]" if selected.damaged else ""])
	_header.text = "\n".join(lines)

	var tail: Array[String] = []
	var start: int = maxi(0, state.log.size() - 9)
	for i in range(start, state.log.size()):
		tail.append(state.log[i])
	_log.text = "\n".join(tail)

	_hint.text = _hint_for_phase()


func _hint_for_phase() -> String:
	if state.ended:
		return "Battaglia conclusa: %s   -   SPAZIO o ESC per tornare alla mappa" \
			% state.end_reason
	match state.phase:
		BattleState.Phase.GUNNERY:
			return "SPAZIO: risolvi il Fuoco di Cannoni (tutte le navi sparano simultaneamente)"
		BattleState.Phase.TORPEDO:
			return "SPAZIO: risolvi i Siluri (solo dalla zona Ravvicinata, contro Ravvicinata o Vicina)"
		BattleState.Phase.MANEUVER:
			return "Trascina una nave nella zona adiacente (o clic nave + clic zona).  S: Fumo.  SPAZIO: fine Manovra"
		BattleState.Phase.BREAK_AWAY:
			return "F: la TF Attiva tenta la Fuga   G: la TF Bersaglio tenta la Fuga   SPAZIO: nessuno tenta"
	return ""
