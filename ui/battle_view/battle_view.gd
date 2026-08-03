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

const ATTITUDE_COUNTERS := {
	Attitude.Kind.ACQUIRING: preload("res://assets/counters/markers_snafu_acquire.png"),
	Attitude.Kind.CLOSING: preload("res://assets/counters/markers_snafu_closing.png"),
	Attitude.Kind.RUNNING: preload("res://assets/counters/markers_snafu_running.png"),
}
const SMOKE_COUNTER := preload("res://assets/counters/markers_smoke.png")
const HIT_COUNTERS := [
	preload("res://assets/counters/markers_hits1.png"),
	preload("res://assets/counters/markers_hits2.png"),
]
const TORPEDO_ATTACK_COUNTER := preload("res://assets/counters/markers_torpedo_attack.png")
const NO_TORPEDO_COUNTER := preload("res://assets/counters/markers_torpedo_no.png")
const ROUND_COUNTER := preload("res://assets/counters/markers_battle_round.png")
const LAST_ROUND_COUNTER := preload("res://assets/counters/markers_track_last_round.png")
const FOG_COUNTER := preload("res://assets/counters/markers_track_fog.png")
const CONFUSION_COUNTERS := {
	TaskForce.Side.KRIEGSMARINE: preload("res://assets/counters/snafu_confusion_ge.png"),
	TaskForce.Side.ROYAL_NAVY: preload("res://assets/counters/snafu_confusion_uk.png"),
}
const NO_RADAR_COUNTER := preload("res://assets/counters/snafu_no_radar.png")
const DAMAGE_CONTROL_COUNTER := preload("res://assets/counters/special_effect_damage_control.png")
const SPECIAL_COUNTERS := {
	SpecialEffects.BATTERIES: preload("res://assets/counters/special_effect_batteries.png"),
	SpecialEffects.BRIDGE: preload("res://assets/counters/special_effect_bridge.png"),
	SpecialEffects.FIRE_SLOW: preload("res://assets/counters/special_effect_fire.png"),
	SpecialEffects.FIRE_STOPPED: preload("res://assets/counters/special_effect_fire_stopped.png"),
	SpecialEffects.FLOOD_SLOW: preload("res://assets/counters/special_effect_flooding_very_slow.png"),
	SpecialEffects.FLOOD_STOPPED: preload("res://assets/counters/special_effect_flooding_stopped.png"),
	SpecialEffects.RUDDER: preload("res://assets/counters/special_effect_rudder_out.png"),
	SpecialEffects.TURRETS: preload("res://assets/counters/special_effect_turret.png"),
}

var battle: Battle
var state: BattleState
var roster: ShipRoster
var solo_player_side: int = -1

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

## Navi che hanno gia' consumato la propria opportunita' nella Manovra del
## Round corrente. Impedisce di trascinare la stessa nave avanti e indietro.
var _maneuvered: Array[Ship] = []

var _log: RichTextLabel
var _header: RichTextLabel
var _hint: Label
var _buttons: HBoxContainer


func setup(p_battle: Battle, p_solo_player_side: int = -1) -> void:
	battle = p_battle
	state = p_battle.state
	solo_player_side = p_solo_player_side
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
				if not battle.pending_snafu.is_empty():
					items.append(["Applica Snafu alla nave selezionata", "N",
						_resolve_snafu_selected, true])
				else:
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
				var current := _current_maneuver_ship()
				items.append(["Resta: %s" % current.name, "SPAZIO",
					_advance_phase, true] if current != null else
					["Fine Manovra", "SPAZIO", _advance_phase, true])
				items.append(["Fumo", "S", _smoke_selected, false])
				if selected != null and Attitude.can_pursue(selected):
					items.append(["Insegui", "I", _pursue_selected, false])
			BattleState.Phase.BREAK_AWAY:
				items.append(["Nessuna Fuga", "SPAZIO", _advance_phase, true])
				if state.round_number >= state.minimum_break_away_round:
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
			var obscured := Maneuver.is_obscured(state, firer)
			var can_attack := AdvancedTorpedo.can_attack(firer, obscured) \
				if state.advanced else Torpedo.can_attack(firer, obscured)
			var valid := AdvancedTorpedo.is_valid_target(e) \
				if state.advanced else Torpedo.is_valid_target(e)
			if can_attack and valid:
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
	var auto: Dictionary = _auto_targeting_for_phase()
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
	var auto: Dictionary = _auto_targeting_for_phase()
	for f_v: Variant in auto.keys():
		targeting[f_v] = auto[f_v]


func _auto_targeting_for_phase() -> Dictionary:
	var torpedoes := state.phase == BattleState.Phase.TORPEDO
	var auto: Dictionary = battle.auto_torpedoes() if torpedoes else battle.auto_targeting()
	var imaginary := _solo_imaginary_side()
	if imaginary >= 0:
		var solo: Dictionary = SoloBattle.targeting(state, imaginary, torpedoes)
		for f_v: Variant in solo.keys():
			auto[f_v] = solo[f_v]
	return auto


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
	var legal := battle.setup_attitudes_for(selected)
	var i := legal.find(selected.attitude)
	selected.attitude = legal[wrapi(i + 1, 0, legal.size())]
	state.note("%s: %s - %s" % [selected.name,
		Attitude.label(selected.attitude),
		Attitude.describe(selected.attitude)])
	refresh()


func _resolve_snafu_selected() -> void:
	var r := battle.resolve_snafu_choice(selected)
	if not bool(r.get("ok", false)):
		state.note("Snafu: %s" % String(r.get("error", "scelta non valida")))
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
	if selected == null or selected != _current_maneuver_ship() \
			or not Attitude.can_pursue(selected):
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
	if bool(r["ok"]):
		_maneuvered.append(selected)
		_select_current_maneuver_ship()
	refresh()


func _smoke_selected() -> void:
	if selected == null:
		state.note("Fumo: seleziona prima una nave.")
	elif state.phase == BattleState.Phase.MANEUVER \
			and selected != _current_maneuver_ship():
		state.note("Fumo: ora deve manovrare %s." % _current_maneuver_ship().name)
	else:
		var want := not selected.smoke
		var refusal := Attitude.maneuver_refusal(selected, -1, want) \
			if state.advanced else ""
		var txt := "" if refusal != "" else Maneuver.apply(selected, -1, want)
		state.note(txt if txt != "" else (refusal if refusal != "" \
			else "%s non puo' creare Fumo" % selected.name))
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
			var reachable := (Attitude.maneuver_refusal(_drag_ship, zone,
				_drag_ship.smoke) == "") if state.advanced else (
				Maneuver.can_move_to(_drag_ship, zone) \
				or _drag_ship.battle_zone == zone)
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
	_draw_battle_markers(font)

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
	var gap: float = 46.0 if state.advanced else 14.0
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
			var rotation := _attitude_rotation(s, is_active) if state.advanced else 0.0
			draw_set_transform(r.get_center(), rotation)
			draw_texture_rect(tex, Rect2(-r.size * 0.5, r.size), false)
			draw_set_transform(Vector2.ZERO, 0.0)
		else:
			draw_rect(r, Color(0.75, 0.72, 0.6))
			draw_string(font, r.position + Vector2(8, 24), s.name,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)

		if s == selected:
			draw_rect(r.grow(4), Color(1, 0.95, 0.3), false, 4.0)
		if s.smoke:
			_draw_small_counter(SMOKE_COUNTER, r.position + Vector2(4, 4), 30.0)
		if s.hits > 0:
			var hit_tex: Texture2D = HIT_COUNTERS[1] if s.hits >= 2 else HIT_COUNTERS[0]
			_draw_small_counter(hit_tex, r.position + Vector2(cw - 34, 4), 30.0)
			if s.hits > 2:
				draw_string(font, r.position + Vector2(cw - 18, 25), str(s.hits),
					HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)

		if state.advanced:
			_draw_attitude_tab(r, s, font)
			_draw_effect_chips(r, s, font)
			if int(s.get_meta("damage_control_round", -1)) == state.round_number:
				_draw_small_counter(DAMAGE_CONTROL_COUNTER,
					r.position + Vector2(cw * 0.5 - 15, -33), 30.0)
		if s.torpedo_attacks_used >= s.torpedo_attack_limit and s.has_torpedo:
			_draw_small_counter(NO_TORPEDO_COUNTER,
				r.position + Vector2(cw + 3, 3), 30.0)
		elif state.phase == BattleState.Phase.TORPEDO and targeting.has(s):
			_draw_small_counter(TORPEDO_ATTACK_COUNTER,
				r.position + Vector2(cw + 3, 3), 30.0)

		_ship_rects.append({"rect": r, "ship": s})
		x += cw + gap


## La linguetta dell'attitudine, sul fianco sinistro della pedina.
##
## Con le Regole Avanzate l'attitudine decide con quale colonna della Tabella
## dei Cannoni si spara, se si possono lanciare siluri e se ci si puo' sganciare:
## chiedere di cambiarla senza mostrarla qual e' - come faceva prima questa
## vista - vuol dire chiedere al buio.
func _draw_attitude_tab(r: Rect2, s: Ship, font: Font) -> void:
	_draw_small_counter(ATTITUDE_COUNTERS[s.attitude],
		r.position + Vector2(-45, r.size.y * 0.5 - 21), 42.0)


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
		if e == Lingering.NO_RADAR_KEY:
			_draw_small_counter(NO_RADAR_COUNTER, Vector2(x, y), 30.0)
			x += 34.0
			continue
		if SPECIAL_COUNTERS.has(e):
			_draw_small_counter(SPECIAL_COUNTERS[e], Vector2(x, y), 30.0)
			x += 34.0
			continue
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


func _attitude_rotation(s: Ship, is_active: bool) -> float:
	if s.attitude == Attitude.Kind.ACQUIRING:
		return 0.0
	var toward_enemy := -PI / 2.0 if is_active else PI / 2.0
	return toward_enemy if s.attitude == Attitude.Kind.CLOSING \
		else -toward_enemy


func _draw_small_counter(texture: Texture2D, pos: Vector2, side: float) -> void:
	draw_texture_rect(texture, Rect2(pos, Vector2(side, side)), false)


func _draw_battle_markers(font: Font) -> void:
	var p := Vector2(20, 88)
	_draw_small_counter(ROUND_COUNTER, p, 44.0)
	draw_string(font, p + Vector2(16, 31), str(state.round_number),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)
	p.x += 50
	_draw_small_counter(LAST_ROUND_COUNTER, p, 44.0)
	draw_string(font, p + Vector2(16, 31), str(state.last_round),
		HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color.WHITE)
	p.x += 50
	if not battle.snafu.is_empty() \
			and int(battle.snafu.get("result", -1)) == Snafu.Result.FOG:
		_draw_small_counter(FOG_COUNTER, p, 44.0)
		p.x += 50
	if state.confusion_side >= 0 and not state.confusion_used:
		var tex: Texture2D = CONFUSION_COUNTERS[state.confusion_side]
		draw_texture_rect(tex, Rect2(p, Vector2(96, 44)), false)


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
					var current := _current_maneuver_ship()
					if current != null and clicked != current:
						selected = current
						state.note("Ordine di Manovra: ora tocca a %s." % current.name)
						refresh()
						return
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


func _current_maneuver_ship() -> Ship:
	if state == null or state.phase != BattleState.Phase.MANEUVER:
		return null
	var imaginary := _solo_imaginary_side()
	for ship in Maneuver.move_order(state):
		if _maneuvered.has(ship):
			continue
		var tf := state.own_tf_of(ship)
		if imaginary >= 0 and tf != null and tf.side == imaginary:
			continue
		return ship
	return null


func _select_current_maneuver_ship() -> void:
	var current := _current_maneuver_ship()
	if current != null:
		selected = current
		state.note("Ordine di Manovra: ora tocca a %s (%s)." % [current.name,
			Attitude.label(current.attitude) if state.advanced else
			TimeLapse.speed_label(current.current_speed())])


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
	var current := _current_maneuver_ship()
	if current != null and ship != current:
		state.note("Ordine di Manovra: ora tocca a %s." % current.name)
		refresh()
		return
	var zone := int(pair[1])
	var refusal := Attitude.maneuver_refusal(ship, zone, ship.smoke) \
		if state.advanced else ""
	var txt := "" if refusal != "" else Maneuver.apply(ship, zone, ship.smoke)
	state.note(txt if txt != "" else
		(refusal if refusal != "" else
		"%s non puo' raggiungere quella zona (si muove di una zona per volta)"
		% ship.name))
	if txt != "":
		_maneuvered.append(ship)
		_select_current_maneuver_ship()
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
		KEY_N:
			if state.phase == BattleState.Phase.ATTITUDE \
					and not battle.pending_snafu.is_empty():
				_resolve_snafu_selected()
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
			if not battle.pending_snafu.is_empty():
				state.note("Prima risolvi la scelta Snafu selezionando una nave.")
				refresh()
				return
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
				_maneuvered.clear()
				_select_current_maneuver_ship()
		BattleState.Phase.MANEUVER:
			var current := _current_maneuver_ship()
			if current != null:
				state.note("%s resta in zona %s." % [current.name,
					BattleState.ZONE_LABELS[current.battle_zone]])
				_maneuvered.append(current)
				_select_current_maneuver_ship()
				refresh()
				return
			_apply_solo_maneuver()
			state.note("Manovra conclusa.")
			state.phase = state.next_phase()
		BattleState.Phase.BREAK_AWAY:
			_resolve_break_away(false, false)
			if not state.ended:
				battle.end_round()
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
	_resolve_break_away(active, target)
	if not state.ended:
		if battle.end_round():
			pass
	refresh()


func _resolve_break_away(active: bool, target: bool) -> void:
	var imaginary := _solo_imaginary_side()
	if imaginary >= 0 and SoloBattle.wants_break_away(state, imaginary):
		if state.active_tf != null and state.active_tf.side == imaginary:
			active = true
		if state.target_tf != null and state.target_tf.side == imaginary:
			target = true
		state.note("Solitario: l'avversario immaginario tenta la Fuga.")
	battle.break_away_phase(active, target)


# ------------------------------------------------------------------ refresh --

func refresh() -> void:
	queue_redraw()
	if _header == null:
		return
	var lines: Array[String] = []
	lines.append("[b]%s[/b] in %s   -   [color=#9edcf2]%s[/color]   -   Round [b]%d[/b] di %d   -   fase [b]%s[/b]" % [
		BattleState.KIND_LABELS[state.kind], str(state.hex),
		"Regole avanzate: Attitudini attive" if state.advanced \
		else "Regole base: nessuna Attitudine",
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
			if _solo_imaginary_side() >= 0:
				return ("Solitario: i bersagli dell'avversario immaginario sono gia' assegnati. "
					+ "Clicca le tue navi per cambiare/assegnare i tuoi bersagli. "
					+ "A: riapplica la dottrina solitaria. SPAZIO: fuoco simultaneo.")
			if left > 0:
				return ("Clicca una nave che spara, poi il suo bersaglio.  "
					+ "%d senza bersaglio.  A: automatici.  SPAZIO: fuoco" % left)
			return "Tutti i bersagli assegnati.  SPAZIO: apri il fuoco (tutte le navi sparano insieme)"
		BattleState.Phase.TORPEDO:
			if _assigning != null:
				return "%s: clicca il bersaglio dei siluri." % _assigning.name
			if _solo_imaginary_side() >= 0:
				return "Solitario: i siluri dell'avversario sono assegnati se legali. Scegli i tuoi; SPAZIO risolve."
			if targeting.is_empty():
				var zones := "Vicina o Ravvicinata" if state.advanced \
					else "Ravvicinata"
				return ("Siluri: clicca una nave in zona %s, poi il bersaglio.  "
					+ "A: automatici.  SPAZIO: nessun lancio") % zones
			return "SPAZIO: lancia i siluri"
		BattleState.Phase.ATTITUDE:
			if not battle.pending_snafu.is_empty():
				var candidates: Array = battle.pending_snafu.get("candidates", [])
				var names: Array[String] = []
				for s_v: Variant in candidates:
					names.append((s_v as Ship).name)
				return "Snafu: seleziona una nave fra %s, poi premi N." \
					% ", ".join(names)
			return ("Clicca una nave e premi A per cambiarle attitudine.  "
				+ "SPAZIO: conferma e passa al Fuoco")
		BattleState.Phase.LINGERING:
			return ("Effetti Duraturi: C dichiara il Controllo Danni sulla "
				+ "nave selezionata (tre dadi, ma non sparera').  SPAZIO: tira")
		BattleState.Phase.MANEUVER:
			var current := _current_maneuver_ship()
			if current != null and state.advanced:
				return ("Manovra di %s: %s. Trascinala solo nella direzione "
					+ "della freccia; SPAZIO la lascia ferma. S: Fumo, I: Insegui.") \
					% [current.name, Attitude.describe(current.attitude)]
			if _solo_imaginary_side() >= 0:
				return "Manovra: muovi le tue navi. SPAZIO muove l'avversario immaginario secondo il fascicolo e chiude la fase."
			return "Manovra: muovi anche l'altro lato, in ordine di velocita' alternando i giocatori. S: Fumo. I: Insegui. SPAZIO: fine fase"
		BattleState.Phase.BREAK_AWAY:
			if state.round_number < state.minimum_break_away_round:
				return "Lo scenario vieta la Fuga sino al Round %d. SPAZIO: continua." \
					% state.minimum_break_away_round
			if _solo_imaginary_side() >= 0:
				return "Fuga: dichiara la tua con F/G se vuoi. SPAZIO applica anche la scelta dell'avversario immaginario."
			return "F: la TF Attiva tenta la Fuga   G: la TF Bersaglio tenta la Fuga   SPAZIO: nessuno tenta"
	return ""


func _solo_imaginary_side() -> int:
	if solo_player_side < 0:
		return -1
	return 1 - solo_player_side


func _apply_solo_maneuver() -> void:
	var imaginary := _solo_imaginary_side()
	if imaginary < 0:
		return
	var moves := SoloBattle.maneuver_moves(state, imaginary)
	if moves.is_empty():
		return
	state.note("Solitario: manovra dell'avversario immaginario.")
	battle.maneuver_phase(moves)
