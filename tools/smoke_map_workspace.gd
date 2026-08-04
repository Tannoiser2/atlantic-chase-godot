extends SceneTree

## Verifica che il SubViewport della mappa riceva davvero puntatore e zoom.
## La separazione fisica fra HUD e mappa non deve rendere il gioco una foto.

var _root: Node = null
var _frames := 0
var _target: TaskForce = null
var _zoom_before := 0.0
var _width_before := 0.0
var _length_before_t := 0
var _failed := false


func _initialize() -> void:
	Session.scenario_id = "Op5 Rheinubung"
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 8:
		for tf in _root.state.task_forces:
			if not tf.completed and tf != _root.selected_tf:
				_target = tf
				break
		if _target == null:
			return _finish(false, "nessuna seconda TF disponibile")
		var traj: Trajectory = _target.trajectory
		var h := traj.station_hex if traj.is_station() else traj.end_hex(0)
		var pos: Vector2 = _root.cam.get_canvas_transform() \
			* _root.graph.center_of(h)
		var press := InputEventMouseButton.new()
		press.position = pos
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		_root._map_viewport.push_input(press, true)
		var release := InputEventMouseButton.new()
		release.position = pos
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		_root._map_viewport.push_input(release, true)
		_zoom_before = _root.cam.zoom.x
		var wheel := InputEventMouseButton.new()
		wheel.position = pos
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		_root._map_viewport.push_input(wheel, true)
	if _frames == 14:
		if _root.selected_tf != _target:
			return _finish(false, "il clic nel SubViewport non seleziona la TF")
		if _root.cam.zoom.x <= _zoom_before:
			return _finish(false, "la rotella nel SubViewport non raggiunge la camera")
		var inset_panel: Control = _root._inset_panel
		if inset_panel == null:
			return _finish(false, "la finestra delle mappe inserto non e' presente")
		var inset_tabs: TabContainer = inset_panel.get_node("InsetTabs")
		if inset_tabs.get_child_count() != 2:
			return _finish(false, "le due mappe inserto non sono presenti")
		for inset in inset_tabs.get_children():
			if not inset is TextureRect or (inset as TextureRect).texture == null:
				return _finish(false, "una mappa inserto non ha caricato la sua immagine")
		if inset_panel.get_global_rect().end.x > _root._map_container.get_global_rect().position.x:
			return _finish(false, "le mappe inserto si sovrappongono alla mappa principale")
		var tf_panel: Control = _root._tf_panel
		var bottom_row: Control = tf_panel.get_parent()
		var status_panel: Control = bottom_row.get_node("StatusPanel")
		if bottom_row.name != "BottomWorkspace" or not tf_panel.visible:
			return _finish(false, "la composizione TF non vive nella fascia inferiore")
		if tf_panel.get_global_rect().position.y \
				< _root._map_container.get_global_rect().end.y:
			return _finish(false, "la composizione TF si sovrappone ancora alla mappa")
		if tf_panel.get_global_rect().position.x < status_panel.get_global_rect().end.x:
			return _finish(false, "la composizione TF non e' a destra dello stato")
		if tf_panel.size.x < 540.0:
			return _finish(false, "la composizione TF e' ancora troppo stretta")
		if not _root._tf_ships is HFlowContainer:
			return _finish(false, "le navi della TF non vanno su piu' righe")
		# ATTENZIONE, difetto gia' pagato: qui c'era `root.size.y`, cioe'
		# l'altezza della FINESTRA in pixel, confrontata con un rettangolo che
		# vive nelle coordinate LOGICHE della HUD. Con
		# `window/stretch/mode="canvas_items"` e `aspect="expand"` i due spazi
		# non coincidono: una finestra da 948 px porta un viewport logico da
		# 1000, e la fascia inferiore a quota 988 risultava "tagliata" pur
		# essendo tutta visibile. Il controllo passava o falliva a seconda di
		# quanto spazio lo schermo concedeva - barra e Dock - il che lo rendeva
		# non deterministico, ed e' cosi' che si e' notato.
		var viewport_height: float = bottom_row.get_viewport_rect().size.y
		if bottom_row.get_global_rect().end.y > viewport_height + 0.5:
			return _finish(false, "la fascia inferiore viene tagliata dal viewport")
		if _target.leader != "":
			var leader_counter: Control = _root._tf_ships.get_node_or_null(
				"LeaderCounter") as Control
			if leader_counter == null or String(leader_counter.tooltip_text) == "":
				return _finish(false, "il comandante non ha pedina e flyover")
		_width_before = _root._map_container.size.x
		_length_before_t = _root.selected_tf.length()
		var forbidden := InputEventKey.new()
		forbidden.keycode = KEY_T
		forbidden.pressed = true
		_root._unhandled_input(forbidden)
		_root._toggle_log_panel()
	if _frames == 18:
		if _root._map_container.size.x <= _width_before:
			return _finish(false, "chiudere il Registro non restituisce spazio alla mappa")
		if _root.selected_tf.length() != _length_before_t or _root._hex_choice_active:
			return _finish(false, "T innesca ancora liberamente lo Scorrere del Tempo")
		if _has_button_text(_root._bar, "Scorrere del Tempo"):
			return _finish(false, "la barra espone ancora Scorrere del Tempo come comando")
		_root._toggle_log_panel()
		_root._active_bot_trace = 101
		_root._msg("dettaglio procedura vecchia")
		_root._msg("BOT - azione vecchia")
		_root._active_bot_trace = 102
		_root._msg("dettaglio procedura nuova")
		_root._msg("BOT - azione nuova")
		_root._active_bot_trace = 0
		_root._refresh()
	if _frames == 22:
		var log_text: String = _root._lbl_log.text
		if log_text.find("azione nuova") > log_text.find("azione vecchia"):
			return _finish(false, "il Registro non mostra prima la procedura piu' recente")
		if log_text.contains("dettaglio procedura vecchia") \
				or log_text.contains("dettaglio procedura nuova"):
			return _finish(false, "le procedure BOT non partono collassate")
		_root._on_log_meta_clicked("bot_trace:101")
	if _frames == 26:
		var expanded_text: String = _root._lbl_log.text
		if not expanded_text.contains("dettaglio procedura vecchia"):
			return _finish(false, "la singola procedura BOT non si espande")
		if expanded_text.contains("dettaglio procedura nuova"):
			return _finish(false, "espandere una procedura BOT apre anche le altre")
		return _finish(true, "inserti, mappa e composizione TF separati; Scorrere non libero e Registro BOT indipendente")
	return false


func _has_button_text(node: Node, needle: String) -> bool:
	if node is Button and String((node as Button).text).contains(needle):
		return true
	for child in node.get_children():
		if _has_button_text(child, needle):
			return true
	return false


func _finish(ok: bool, detail: String) -> bool:
	print("WORKSPACE MAPPA: %s - %s" % ["OK" if ok else "ERRORE", detail])
	_root.queue_free()
	_root = null
	_failed = not ok
	call_deferred("_quit_after_cleanup")
	return false


func _quit_after_cleanup() -> void:
	quit(1 if _failed else 0)
