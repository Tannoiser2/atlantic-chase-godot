extends SceneTree

## Verifica che il SubViewport della mappa riceva davvero puntatore e zoom.
## La separazione fisica fra HUD e mappa non deve rendere il gioco una foto.

var _root: Node = null
var _frames := 0
var _target: TaskForce = null
var _zoom_before := 0.0
var _width_before := 0.0
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
		_width_before = _root._map_container.size.x
		_root._toggle_log_panel()
	if _frames == 18:
		if _root._map_container.size.x <= _width_before:
			return _finish(false, "chiudere il Registro non restituisce spazio alla mappa")
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
		return _finish(true, "mappa separata e Registro inverso con procedure BOT indipendenti")
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
