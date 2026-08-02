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
## Le pedine si disegnavano come TextureRect figli di questo Control. Non
## andava bene: i figli di un Control disegnano SOPRA il suo _draw(), quindi il
## badge dei Colpi, la velatura FUMO e il bordo di selezione finivano sotto la
## pedina e non si vedevano.
##
## Ora si disegnano dentro _draw() con draw_texture_rect, e l'ordine e' quello
## in cui sono scritte le righe. Un commento piu' vecchio diceva che cosi' le
## pedine uscivano BIANCHE: era vero, ma la causa era un'altra - le texture
## salgono in VRAM al primo disegno, e chi guardava era uno screenshot scattato
## troppo presto. Ricaricare la texture a ogni _draw() con load() peggiorava le
## cose; questa cache la tiene, e dal secondo fotogramma in poi si vede.
var _tex_cache: Dictionary = {}

## Effetti visivi e sonori. Vivono sopra la vista e non fermano il gioco.
var _fx: BattleFX = null
var _sfx: Sfx = null
## Chi spara a chi, deciso dal GIOCATORE. Nave che spara -> bersaglio.
##
## Prima questa vista chiamava sempre Battle.auto_targeting(), che il motore
## offre come ripiego "per far girare la battaglia" - e infatti il commento di
## Battle dice che le decisioni le passa il chiamante. Il risultato era che il
## codice sceglieva i bersagli al posto del giocatore, cioe' gli toglieva la
## meta' interessante del Fuoco di Cannoni: a chi sparare quando puoi
## raggiungerne due, e se concentrare o dividere il fuoco.
var targeting: Dictionary = {}

## La nave che sta per ricevere un bersaglio: si clicca chi spara, poi il
## bersaglio. Null = nessuna in attesa.
var _assigning: Ship = null

## Le navi che hanno dichiarato il Controllo Danni per gli Effetti Duraturi:
## tirano tre dadi e tengono i due piu' alti, ma non spareranno nel Round
## successivo. Si dichiara PRIMA di tirare, e per questo va raccolto qui.
var _damage_control: Array[Ship] = []

var _log: RichTextLabel
var _header: RichTextLabel
var _hint: Label
var _buttons: HBoxContainer


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
	_build_ui()
	# Il livello degli effetti va aggiunto DOPO _build_ui(), se no i pannelli
	# della barra dei comandi gli finiscono sopra e le esplosioni spariscono
	# dietro i pulsanti.
	_sfx = Sfx.new()
	add_child(_sfx)
	_fx = BattleFX.new()
	_fx.sfx = _sfx
	add_child(_fx)
	_fx.klaxon()
	_preassign()
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

	# Barra dei comandi della Battaglia. La sola riga di aiuto in fondo non
	# bastava: chi apre la Battaglia per la prima volta non ha modo di sapere
	# che il gioco aspetta un tasto, e resta fermo a guardare. I pulsanti
	# dicono cosa si puo' fare ADESSO, e cambiano a ogni fase.
	_buttons = HBoxContainer.new()
	_buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_buttons.offset_left = -820
	_buttons.offset_right = -16
	_buttons.offset_top = 88
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	_buttons.add_theme_constant_override("separation", 8)
	add_child(_buttons)


## Ricostruisce i pulsanti per la fase in corso. Il primo e' quello che fa
## avanzare la Battaglia ed e' evidenziato: se uno non legge niente e preme
## quello, la partita procede comunque nell'ordine giusto.
func _rebuild_buttons() -> void:
	if _buttons == null:
		return
	for c in _buttons.get_children():
		c.queue_free()

	var items: Array = []      # [testo, scorciatoia, Callable, principale]
	if state.ended:
		items.append(["Torna alla mappa", "ESC", func() -> void: closed.emit(), true])
	else:
		match state.phase:
			BattleState.Phase.GUNNERY:
				items.append(["Fuoco di Cannoni", "SPAZIO", _advance_phase, true])
				items.append(["Bersagli automatici", "A", _auto_assign, false])
				if not targeting.is_empty():
					items.append(["Azzera bersagli", "R", _clear_targets, false])
			BattleState.Phase.TORPEDO:
				items.append(["Lancia i Siluri", "SPAZIO", _advance_phase, true])
				items.append(["Bersagli automatici", "A", _auto_assign, false])
				if not targeting.is_empty():
					items.append(["Azzera bersagli", "R", _clear_targets, false])
			BattleState.Phase.ATTITUDE:
				items.append(["Conferma Attitudini", "SPAZIO", _advance_phase,
					true])
				items.append(["Cambia attitudine", "A", _cycle_attitude, false])
			BattleState.Phase.LINGERING:
				items.append(["Tira gli Effetti Duraturi", "SPAZIO",
					_advance_phase, true])
				items.append(["Controllo Danni: %s" % (
					selected.name if selected != null else "-"), "C",
					_toggle_damage_control, false])
			BattleState.Phase.MANEUVER:
				items.append(["Fine Manovra", "SPAZIO", _advance_phase, true])
				items.append(["Fumo", "S", _smoke_selected, false])
				if selected != null and Attitude.can_pursue(selected):
					items.append(["Insegui", "I", _pursue_selected, false])
			BattleState.Phase.BREAK_AWAY:
				items.append(["Nessuna Fuga", "SPAZIO", _advance_phase, true])
				items.append(["Fuga: %s" % _side_label(true), "F",
					func() -> void: _do_break_away(true, false), false])
				items.append(["Fuga: %s" % _side_label(false), "G",
					func() -> void: _do_break_away(false, true), false])
		items.append(["Abbandona", "ESC", func() -> void: closed.emit(), false])

	for it_v: Variant in items:
		var it: Array = it_v
		var b := Button.new()
		b.text = "  %s (%s)  " % [it[0], it[1]]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(it[2])
		if bool(it[3]):
			b.add_theme_color_override("font_color", Color(1, 0.93, 0.72))
			b.add_theme_color_override("font_hover_color", Color(1, 1, 0.85))
		_buttons.add_child(b)


# ------------------------------------------------------ scelta dei bersagli --

func _is_targeting_phase() -> bool:
	return not state.ended and (state.phase == BattleState.Phase.GUNNERY
		or state.phase == BattleState.Phase.TORPEDO)


## Le navi nemiche che questa puo' colpire ADESSO, nella fase in corso.
## Serve a due cose: impedire assegnazioni illegali, e far vedere al giocatore
## quali sono le sue opzioni prima che scelga.
func _legal_targets(firer: Ship) -> Array[Ship]:
	var out: Array[Ship] = []
	if firer == null or firer.sunk:
		return out
	var enemies := state.target_ships() if state.active_ships().has(firer) \
		else state.active_ships()
	for e in enemies:
		if e.sunk:
			continue
		if state.phase == BattleState.Phase.TORPEDO:
			# i siluri partono solo dalla zona Ravvicinata e colpiscono solo
			# Ravvicinata o Vicina (RB p.59)
			if Torpedo.can_attack(firer) and Torpedo.is_valid_target(e):
				out.append(e)
		else:
			var r := Gunnery.range_between(firer.battle_zone, e.battle_zone)
			if firer.can_fire(Gunnery.band_for(r)):
				out.append(e)
	return out


func _can_fire_now(firer: Ship) -> bool:
	return not _legal_targets(firer).is_empty()


## Assegna un bersaglio, o lo toglie se si riclicca lo stesso.
func _assign_target(firer: Ship, target: Ship) -> void:
	if not _legal_targets(firer).has(target):
		state.note("%s non puo' colpire %s da qui." % [firer.name, target.name])
		refresh()
		return
	if targeting.get(firer) == target:
		targeting.erase(firer)
		state.note("%s non spara piu' a %s." % [firer.name, target.name])
	else:
		targeting[firer] = target
		state.note("%s prende di mira %s." % [firer.name, target.name])
	_assigning = null
	refresh()


## Riempie i bersagli non assegnati con la scelta del motore. NON sovrascrive
## quelli scelti dal giocatore: e' un aiuto, non una correzione.
func _auto_assign() -> void:
	if not _is_targeting_phase():
		return
	var auto: Dictionary = battle.auto_torpedoes() \
		if state.phase == BattleState.Phase.TORPEDO else battle.auto_targeting()
	var added := 0
	for f_v: Variant in auto.keys():
		if not targeting.has(f_v):
			targeting[f_v] = auto[f_v]
			added += 1
	state.note("Bersagli automatici: %d assegnazioni aggiunte." % added
		if added > 0 else "Bersagli automatici: non c'era altro da assegnare.")
	refresh()


## All'inizio di una fase di fuoco i bersagli si assegnano da soli con la
## scelta del motore, e il giocatore li CAMBIA.
##
## E' diverso dal farli scegliere al codice: la decisione resta sua, ma il
## valore di partenza e' quello sensato. Lasciando tutto vuoto, chi preme
## SPAZIO senza aver capito si trova una fase in cui non spara nessuno - che e'
## legale ma sembra rotto, ed e' il modo peggiore di insegnare una regola.
func _preassign() -> void:
	targeting.clear()
	_assigning = null
	if not _is_targeting_phase():
		return
	var auto: Dictionary = battle.auto_torpedoes() \
		if state.phase == BattleState.Phase.TORPEDO else battle.auto_targeting()
	for f_v: Variant in auto.keys():
		targeting[f_v] = auto[f_v]


func _clear_targets() -> void:
	targeting.clear()
	_assigning = null
	state.note("Bersagli azzerati.")
	refresh()


## Chi potrebbe sparare ma non ha ancora un bersaglio.
func _unassigned() -> Array[Ship]:
	var out: Array[Ship] = []
	for s in state.all_ships():
		if not s.sunk and _can_fire_now(s) and not targeting.has(s):
			out.append(s)
	return out


func _side_label(active: bool) -> String:
	var tf := state.active_tf if active else state.target_tf
	if tf == null:
		return "Attiva" if active else "Bersaglio"
	return "Kriegsmarine" if tf.side == TaskForce.Side.KRIEGSMARINE else "Royal Navy"


## Cicla l'attitudine della nave selezionata fra le tre.
##
## Il fascicolo vorrebbe che si scegliessero in segreto e si rivelassero
## insieme; qui si assegnano a vista, che e' l'unico modo sensato quando i due
## giocatori guardano lo stesso schermo.
func _cycle_attitude() -> void:
	if selected == null:
		state.note("Attitudine: seleziona prima una nave.")
		refresh()
		return
	if selected.current_speed() == TimeLapse.Speed.STOPPED:
		state.note("%s e' ferma: non puo' cambiare attitudine." % selected.name)
		refresh()
		return
	selected.attitude = (selected.attitude + 1) % 3
	state.note("%s: %s - %s" % [selected.name,
		Attitude.label(selected.attitude),
		Attitude.describe(selected.attitude)])
	refresh()


func _toggle_damage_control() -> void:
	if selected == null:
		state.note("Controllo Danni: seleziona prima una nave.")
	elif not selected.has_special_effect():
		state.note("%s non ha effetti speciali da riparare." % selected.name)
	elif _damage_control.has(selected):
		_damage_control.erase(selected)
		state.note("%s: Controllo Danni annullato." % selected.name)
	else:
		_damage_control.append(selected)
		state.note("%s dichiara il Controllo Danni: tre dadi invece di due, "
			% selected.name + "ma non sparera' nel Round successivo.")
	refresh()


## Inseguimento: la nave selezionata si tira dietro una nave nemica.
func _pursue_selected() -> void:
	if selected == null or not Attitude.can_pursue(selected):
		state.note("Inseguire: serve una nave in Avvicinamento in zona Vicina "
			+ "o Ravvicinata.")
		refresh()
		return
	var enemies := state.target_ships() if state.active_ships().has(selected) \
		else state.active_ships()
	var best: Ship = null
	for e in enemies:
		if Attitude.pursuit_refusal(selected, e) == "":
			best = e
			break
	if best == null:
		state.note("%s non riesce a tirarsi dietro nessuno." % selected.name)
		refresh()
		return
	var r := Attitude.pursue(selected, best)
	state.note(String(r["log"]) if bool(r["ok"]) else String(r["error"]))
	refresh()


func _smoke_selected() -> void:
	if selected == null:
		state.note("Fumo: seleziona prima una nave.")
	else:
		var txt := Maneuver.apply(selected, -1, not selected.smoke)
		state.note(txt if txt != "" else "%s non puo' creare Fumo" % selected.name)
	refresh()


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
	var area := Rect2(Vector2(40, 142), size - Vector2(80, 356))
	# la fascia Ravvicinata e' piu' stretta delle altre, come sulla mappa
	var weights := [1.0, 1.0, 0.55, 0.55, 1.0, 1.0]
	var total := 0.0
	for w in weights:
		total += w
	_bands.clear()
	_ship_rects.clear()

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
	_draw_targeting()
	# gli incendi si ridisegnano da soli fotogramma per fotogramma, ma devono
	# sapere DOVE stanno le pedine, e i rettangoli esistono solo dopo questo giro
	_update_fires()


## Le linee di fuoco: chi spara a chi, disegnato mentre si decide.
##
## Senza, l'assegnazione dei bersagli sarebbe un elenco invisibile nella testa
## del giocatore. Con le linee si vede a colpo d'occhio chi ha gia' un
## bersaglio, chi ne e' rimasto senza, e se si sta concentrando o dividendo il
## fuoco - che e' esattamente la decisione da prendere.

func _draw_targeting() -> void:
	if not _is_targeting_phase():
		return
	var font := ThemeDB.fallback_font

	# chi puo' sparare ma non ha ancora un bersaglio: contorno tratteggiato
	for e_v: Variant in _ship_rects:
		var e: Dictionary = e_v
		var sh: Ship = e["ship"]
		if targeting.has(sh) or not _can_fire_now(sh):
			continue
		var r: Rect2 = e["rect"]
		draw_rect(r.grow(3.0), Color(0.95, 0.82, 0.45, 0.55), false, 2.0)

	# i bersagli possibili della nave in attesa: cerchiati
	if _assigning != null:
		var legal := _legal_targets(_assigning)
		for e_v2: Variant in _ship_rects:
			var e2: Dictionary = e_v2
			if legal.has(e2["ship"]):
				draw_rect((e2["rect"] as Rect2).grow(5.0),
					Color(1.0, 0.45, 0.35, 0.9), false, 3.0)
		var from := _rect_of(_assigning)
		if from != Rect2():
			draw_rect(from.grow(5.0), Color(1.0, 0.95, 0.6, 0.95), false, 3.0)

	# le assegnazioni gia' fatte. Le etichette si sfalsano lungo la linea:
	# messe tutte a meta' si accavallano, perche' le linee si incrociano
	# proprio li' in mezzo.
	var idx := 0
	for f_v: Variant in targeting.keys():
		var f: Ship = f_v
		var t: Ship = targeting[f_v]
		var a := _rect_of(f)
		var b := _rect_of(t)
		if a == Rect2() or b == Rect2():
			continue
		var p1 := a.get_center()
		var p2 := b.get_center()
		var col := Color(1.0, 0.55, 0.35, 0.85)
		draw_line(p1, p2, col, 2.5)
		# punta della freccia sul bersaglio
		var dir := (p2 - p1).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var tip := p2 - dir * 14.0
		draw_colored_polygon([p2 - dir * 2.0, tip + perp * 7.0,
			tip - perp * 7.0], col)
		var t_pos := 0.30 + 0.13 * float(idx % 4)
		draw_string(font, p1 + (p2 - p1) * t_pos + Vector2(6, -6),
			_range_label(f, t), HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1, 0.9, 0.75, 0.95))
		idx += 1


func _rect_of(ship: Ship) -> Rect2:
	for e_v: Variant in _ship_rects:
		var e: Dictionary = e_v
		if e["ship"] == ship:
			return e["rect"]
	return Rect2()


## Il raggio a cui avverrebbe questo attacco, scritto sulla linea di fuoco:
## e' il dato che decide se conviene sparare a quel bersaglio o a un altro.
func _range_label(firer: Ship, target: Ship) -> String:
	if state.phase == BattleState.Phase.TORPEDO:
		return "siluri"
	var r := Gunnery.range_between(firer.battle_zone, target.battle_zone)
	var v: Variant = firer.gun_value(Gunnery.band_for(r))
	# i valori arrivano da JSON, quindi sono float: "1.0" al posto di "1" fa
	# sembrare un numero decimale un valore che sulla pedina e' un intero
	var txt := "na" if v == null else str(int(round(float(v))))
	return "%s  %s" % [Gunnery.RANGE_LABELS[r], txt]


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
	# con le Regole Avanzate ogni pedina si porta dietro la linguetta
	# dell'attitudine sul fianco sinistro: senza spazio in piu' finirebbe sopra
	# la pedina precedente
	var gap: float = 32.0 if state.advanced else 14.0
	var widths: Array[float] = []
	var texs: Array = []
	for s in ships:
		var tex := _counter_texture(s)
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
			draw_texture_rect(tex, r, false)
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

		if state.advanced:
			_draw_attitude_tab(r, s, font)
			_draw_effect_chips(r, s, font)

		_ship_rects.append({"rect": r, "ship": s})
		x += cw + gap


## La linguetta dell'attitudine, sul fianco sinistro della pedina.
##
## Con le Regole Avanzate l'attitudine decide con quale colonna della Tabella
## dei Cannoni si spara, se si possono lanciare siluri e se ci si puo' sganciare:
## chiedere di cambiarla senza mostrarla qual e' - come faceva prima questa
## vista - vuol dire chiedere al buio.
func _draw_attitude_tab(r: Rect2, s: Ship, font: Font) -> void:
	var w := 20.0
	var tab := Rect2(r.position + Vector2(-w - 3, 0), Vector2(w, r.size.y))
	draw_rect(tab, Attitude.color(s.attitude))
	draw_rect(tab, Color(0, 0, 0, 0.55), false, 1.0)
	var letter := Attitude.initial(s.attitude)
	var tw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(font, tab.position + Vector2((w - tw) * 0.5, r.size.y * 0.5 + 6),
		letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)


## Gli Effetti Speciali, sotto la pedina.
##
## Sono la sostanza delle Regole Avanzate: una nave puo' essere intatta sulla
## carta e fuori combattimento perche' non ha piu' il timone o la plancia. Se
## non si vedono, il giocatore non capisce perche' la sua nave non spara.
##
## Le sigle sono le iniziali di quello che c'e' scritto sul marcatore; il nome
## per esteso resta nel registro, che e' dove si legge cosa e' successo.
func _draw_effect_chips(r: Rect2, s: Ship, font: Font) -> void:
	if s.special_effects.is_empty():
		return
	var x := r.position.x
	var y := r.position.y + r.size.y + 3.0
	for e_v: Variant in s.special_effects:
		var e := String(e_v)
		var short := e.substr(0, 3).to_upper()
		# gli incendi e gli allagamenti hanno due gravita': si distinguono con
		# un punto esclamativo, che e' quella che ferma la nave
		if e.contains("ferma"):
			short += "!"
		var tw := font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var chip := Rect2(Vector2(x, y), Vector2(tw + 10, 18))
		var col := Color(0.55, 0.16, 0.10) if e.contains("Incendio") \
			else (Color(0.12, 0.30, 0.55) if e.contains("Allagamento")
				else Color(0.25, 0.24, 0.22))
		draw_rect(chip, Color(col.r, col.g, col.b, 0.95))
		draw_rect(chip, Color(1, 1, 1, 0.5), false, 1.0)
		draw_string(font, chip.position + Vector2(5, 13), short,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		x += chip.size.x + 4.0


# --------------------------------------------------------- effetti --

## Chi era a galla, e dove, prima che la fase risolvesse.
##
## I rettangoli di _rect_of() sono quelli dell'ultimo _draw(): per una nave che
## sta per affondare vanno presi PRIMA di risolvere la fase, se no il motore
## l'ha gia' tolta dalla sua zona e non c'e' piu' nessun rettangolo da cui
## farla affondare.
func _afloat_snapshot() -> Dictionary:
	var out := {}
	for s in state.all_ships():
		if not s.sunk:
			out[s] = _rect_of(s)
	return out


## Traduce i risultati di una fase in vampe, traccianti e schizzi.
##
## Il motore non sa nulla di tutto questo e non deve saperlo: restituisce
## Dictionary con chi ha sparato, a chi, e com'e' andata. Qui si guarda solo
## quello.
func _play_attacks(results: Array, before: Dictionary, torpedo: bool) -> void:
	if _fx == null or results.is_empty():
		return
	var shots: Array = []
	for a_v: Variant in results:
		var a: Dictionary = a_v
		if not bool(a.get("ok", false)):
			continue
		var firer: Ship = a["firer"]
		var target: Ship = a["target"]
		var fr: Rect2 = before.get(firer, _rect_of(firer))
		var tr: Rect2 = before.get(target, _rect_of(target))
		if fr.size == Vector2.ZERO or tr.size == Vector2.ZERO:
			continue
		shots.append({
			"from": fr.get_center(), "to": tr.get_center(),
			"hit": int(a.get("hits", 0)) > 0,
			"special": bool(a.get("special", false)),
			"label": String(a.get("label", "")),
		})
	if shots.is_empty():
		return
	if torpedo:
		_fx.torpedoes(shots)
	else:
		_fx.salvo(shots)

	# le navi che sono affondate in questa fase: l'affondamento parte quando la
	# bordata e' finita, se no si vedrebbe una nave colare a picco mentre le
	# stanno ancora sparando
	var when := float(shots.size()) * BattleFX.SHOT_STAGGER + 0.4
	for s_v: Variant in before.keys():
		var s: Ship = s_v
		if s.sunk:
			_fx.sinking(before[s] as Rect2, when)


## Le navi che bruciano, con la fiamma sopra la pedina. Si aggiorna a ogni
## ridisegno perche' un incendio puo' nascere e spegnersi in qualunque fase.
func _update_fires() -> void:
	if _fx == null:
		return
	var pts: Array[Vector2] = []
	for r_v: Variant in _ship_rects:
		var d: Dictionary = r_v
		var s: Ship = d["ship"]
		for e_v: Variant in s.special_effects:
			if String(e_v).contains("Incendio"):
				var r: Rect2 = d["rect"]
				pts.append(Vector2(r.position.x + r.size.x * 0.5,
					r.position.y + 6.0))
				break
	_fx.set_fires(pts)


## Le pedine si ricaricano a ogni ridisegno: load() rilegge dal disco ogni
## volta, e con una ventina di navi su schermo si sente.
func _counter_texture(s: Ship) -> Texture2D:
	var path := roster.counter_path(s.name, s.damaged)
	if path == "":
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


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
				if not (e["rect"] as Rect2).has_point(mb.position):
					continue
				var clicked: Ship = e["ship"]
				# Nelle fasi di fuoco il clic serve a DECIDERE: primo clic
				# sulla nave che spara, secondo sul bersaglio. Ricliccare la
				# stessa coppia toglie l'assegnazione.
				if _is_targeting_phase():
					if _assigning != null and _assigning != clicked:
						_assign_target(_assigning, clicked)
						return
					if _can_fire_now(clicked):
						_assigning = clicked
						selected = clicked
						state.note("%s: scegli il bersaglio (%d possibili)."
							% [clicked.name, _legal_targets(clicked).size()])
					else:
						_assigning = null
						selected = clicked
						state.note("%s non puo' colpire nessuno da qui."
							% clicked.name)
					queue_redraw()
					refresh()
					return
				selected = clicked
				if state.phase == BattleState.Phase.MANEUVER:
					_drag_ship = selected
					_drag_pos = mb.position
				queue_redraw()
				refresh()
				return
			# clic nel vuoto durante il fuoco: annulla l'assegnazione in corso
			if _is_targeting_phase() and _assigning != null:
				_assigning = null
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
			if state.phase == BattleState.Phase.MANEUVER:
				_smoke_selected()
			return true
		KEY_A:
			if _is_targeting_phase():
				_auto_assign()
			elif state.phase == BattleState.Phase.ATTITUDE:
				_cycle_attitude()
			return true
		KEY_C:
			if state.phase == BattleState.Phase.LINGERING:
				_toggle_damage_control()
			return true
		KEY_I:
			if state.phase == BattleState.Phase.MANEUVER:
				_pursue_selected()
			return true
		KEY_R:
			if _is_targeting_phase():
				_clear_targets()
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
	# Se c'e' ancora una bordata in volo la si butta via e si tira dritto: il
	# tasto NON viene mangiato. Un'animazione che si prende una pressione di
	# SPAZIO sembra un gioco che non risponde, ed e' il modo piu' veloce di far
	# odiare gli effetti che si sono appena aggiunti.
	if _fx != null and _fx.busy():
		_fx.skip()
	match state.phase:
		BattleState.Phase.ATTITUDE:
			# le attitudini le ha gia' scritte il giocatore cliccando le navi;
			# qui si applicano gli effetti che scattano in questa fase
			battle.attitude_phase({})
			if not state.ended:
				state.phase = BattleState.Phase.GUNNERY
				_preassign()
		BattleState.Phase.LINGERING:
			battle.lingering_phase(_damage_control)
			_damage_control.clear()
			if not state.ended:
				state.phase = BattleState.Phase.BREAK_AWAY
		BattleState.Phase.GUNNERY:
			# I bersagli sono quelli scelti dal GIOCATORE (RB p.57: ogni nave
			# "ha l'opportunita' di attaccare una volta" e "deve attaccare una
			# singola nave" - quindi sparare e' facoltativo, ma chi spara
			# colpisce un bersaglio solo, non divide il fuoco).
			var g := _player_targeting()
			if g.is_empty():
				state.note("Nessuna nave ha un bersaglio assegnato: "
					+ "nessuno apre il fuoco.")
			else:
				var afloat := _afloat_snapshot()
				var res := battle.gunnery_phase(g)
				_play_attacks(res, afloat, false)
			targeting.clear()
			_assigning = null
			if not state.ended:
				state.phase = BattleState.Phase.TORPEDO
				_preassign()
		BattleState.Phase.TORPEDO:
			var t := _player_targeting()
			if t.is_empty():
				state.note("Nessun lancio di siluri.")
			else:
				var afloat := _afloat_snapshot()
				var res := battle.torpedo_phase(t)
				_play_attacks(res, afloat, true)
			targeting.clear()
			_assigning = null
			if not state.ended:
				state.phase = BattleState.Phase.MANEUVER
		BattleState.Phase.MANEUVER:
			state.note("Manovra conclusa.")
			state.phase = state.next_phase()
		BattleState.Phase.BREAK_AWAY:
			_do_break_away(false, false)
			_preassign()
			# in avanzato il Round riparte dall'Attitudine, non dal Fuoco
			if not state.ended and state.advanced \
					and state.phase == BattleState.Phase.GUNNERY:
				state.phase = BattleState.Phase.ATTITUDE
		_:
			closed.emit()
			return
	refresh()


## Le assegnazioni valide al momento di risolvere: una nave affondata o che ha
## cambiato zona nel frattempo non spara piu'.
func _player_targeting() -> Dictionary:
	var out := {}
	for f_v: Variant in targeting.keys():
		var f: Ship = f_v
		var t: Ship = targeting[f_v]
		if f.sunk or t.sunk:
			continue
		if _legal_targets(f).has(t):
			out[f] = t
	return out


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
				TimeLapse.speed_label(selected.current_speed()),
				"  [danneggiata]" if selected.damaged else ""])
	_header.text = "\n".join(lines)

	var tail: Array[String] = []
	var start: int = maxi(0, state.log.size() - 9)
	for i in range(start, state.log.size()):
		tail.append(state.log[i])
	_log.text = "\n".join(tail)

	_hint.text = _hint_for_phase()
	_rebuild_buttons()


func _hint_for_phase() -> String:
	if state.ended:
		return "Battaglia conclusa: %s   -   SPAZIO o ESC per tornare alla mappa" \
			% state.end_reason
	match state.phase:
		BattleState.Phase.GUNNERY:
			if _assigning != null:
				return "%s: clicca il bersaglio (cerchiati in rosso).  Clic nel vuoto per annullare." % _assigning.name
			var left := _unassigned().size()
			if left > 0:
				return ("Clicca una nave che spara, poi il suo bersaglio.  "
					+ "%d senza bersaglio.  A: automatici.  SPAZIO: fuoco" % left)
			return "Tutti i bersagli assegnati.  SPAZIO: apri il fuoco (tutte le navi sparano insieme)"
		BattleState.Phase.TORPEDO:
			if _assigning != null:
				return "%s: clicca il bersaglio dei siluri." % _assigning.name
			if targeting.is_empty():
				return ("Siluri: clicca una nave in zona Ravvicinata, poi il "
					+ "bersaglio.  A: automatici.  SPAZIO: nessun lancio")
			return "SPAZIO: lancia i siluri"
		BattleState.Phase.ATTITUDE:
			return ("Clicca una nave e premi A per cambiarle attitudine.  "
				+ "SPAZIO: conferma e passa al Fuoco")
		BattleState.Phase.LINGERING:
			return ("Effetti Duraturi: C dichiara il Controllo Danni sulla "
				+ "nave selezionata (tre dadi, ma non sparera').  SPAZIO: tira")
		BattleState.Phase.MANEUVER:
			return "Trascina una nave nella zona adiacente.  S: Fumo.  I: Insegui.  SPAZIO: fine Manovra"
		BattleState.Phase.BREAK_AWAY:
			return "F: la TF Attiva tenta la Fuga   G: la TF Bersaglio tenta la Fuga   SPAZIO: nessuno tenta"
	return ""
