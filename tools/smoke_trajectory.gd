extends SceneTree

## Prova di fumo dell'azione Traiettoria tracciata a CLIC, con eventi di mouse
## veri che attraversano HUD, SubViewport e proxy della mappa.
##
##     godot --path . --script res://tools/smoke_trajectory.gd
##
## Difende due difetti corretti insieme, che si vedevano solo giocando:
##
##   1. ogni clic chiudeva l'azione, e il clic successivo - quello con cui si
##      voleva proseguire la rotta - deselezionava la Task Force;
##   2. dopo ogni Traiettoria l'avversario tirava per Sottrarre l'Iniziativa.
##      RB p.43 e Menu delle Azioni: "Traiettoria - Tenete l'Iniziativa".
##
## Verificata guastando di proposito `_try_extend` (rimettendo il disarmo): la
## prova fallisce con "dopo il primo clic l'azione deve restare armata" e "il
## secondo clic deve allungare la rotta (ha 2 segmenti)".

var _f := 0
var _root: Node
var _tf: TaskForce
var _h0: Vector2i
var _h1: Vector2i
var _h2: Vector2i
var _rolls_before := 0
var _found := false
var _failures: Array[String] = []


func _initialize() -> void:
	Session.scenario_id = "BL1 Raiders of the North Atlantic"
	Session.advanced_battle = false
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _screen_pos(h: Vector2i) -> Vector2:
	var world: Vector2 = _root.graph.center_of(h)
	var local: Vector2 = _root.cam.get_canvas_transform() * world
	var rect: Rect2 = _root._map_container.get_global_rect()
	return rect.position + local * (rect.size / Vector2(_root._map_viewport.size))


func _click(h: Vector2i) -> void:
	var p := _screen_pos(h)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _process(_delta: float) -> bool:
	_f += 1
	match _f:
		20:
			_tf = _root.selected_tf
			_expect(_tf != null and _tf.trajectory.is_station(),
				"BL1 deve partire con una Stazione tedesca selezionata")
			if _tf == null:
				return _finish()
			_h0 = _tf.trajectory.station_hex
			# due esagoni in fila, liberi e raggiungibili uno dall'altro
			for a in _root.graph.adjacent_hexes(_h0):
				for b in _root.graph.adjacent_hexes(a):
					if b != _h0 and Hex.distance(_h0, b) == 2 \
							and _root.state.forces_in(a).is_empty() \
							and _root.state.forces_in(b).is_empty() \
							and not _root.state.triggers_info(a, _tf.side) \
							and not _root.state.triggers_info(b, _tf.side):
						_h1 = a
						_h2 = b
						_found = true
						break
				if _found:
					break
			_expect(_found, "servono due esagoni liberi in fila accanto alla Stazione")
			if not _found:
				return _finish()
			_rolls_before = _root.state.rng.log.size()
			_root._declare_action("TRAJECTORY")
		40:
			_expect(_root._trajectory_action_armed, "l'azione Traiettoria deve armarsi")
			_click(_h1)
		70:
			_expect(_tf.length() == 2, "il primo clic deve creare una Traiettoria di due segmenti (ha %d)" % _tf.length())
			_expect(_root._trajectory_action_armed, "dopo il primo clic l'azione deve restare armata")
			_expect(_root.selected_tf == _tf, "e la Task Force deve restare selezionata")
			_click(_h2)
		100:
			_expect(_tf.length() == 3, "il secondo clic deve allungare la rotta (ha %d segmenti)" % _tf.length())
			_expect(_root.selected_tf == _tf, "senza deselezionare la Task Force")
			_expect(_root.state.initiative == _tf.side, "l'Attivo tiene l'Iniziativa (RB p.43)")
			_expect(_root.state.initiative_count == 0, "il Conto dell'Iniziativa non si muove")
			_expect(_root.state.rng.log.size() == _rolls_before,
				"nessun dado tirato: niente tentativo di Sottrarre dopo la Traiettoria")
			# ESC chiude la rotta
			var k := InputEventKey.new()
			k.keycode = KEY_ESCAPE
			k.pressed = true
			_root._on_key(k)
		110:
			_expect(not _root._trajectory_action_armed, "ESC deve chiudere il tracciamento")
			return _finish()
	return false


func _finish() -> bool:
	if _failures.is_empty():
		print("\nTRAIETTORIA A CLIC: OK - due clic, tre segmenti, Iniziativa tenuta, nessun tiro")
		quit(0)
	else:
		print("\nTRAIETTORIA A CLIC: FALLITA")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
	return true
