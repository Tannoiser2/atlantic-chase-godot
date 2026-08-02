extends SceneTree

## Avvia la scena principale, lascia passare qualche frame e salva un PNG.
## Serve a verificare il rendering senza guardare a occhio una finestra:
##     godot --path . --script res://tools/screenshot.gd -- <output.png> [scenario]

var _frames := 0
var _out := "user://shot.png"
var _root_node: Node = null
var _args: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	# primo argomento opzionale "splash": fotografa la schermata iniziale
	var scene_path := "res://ui/main.tscn"
	if args.size() >= 2 and args[1] == "splash":
		scene_path = "res://ui/splash/splash.tscn"
	# "scen:<id>" sceglie lo scenario da fotografare, come farebbe la
	# schermata iniziale: serve per verificare i mini-scenari, che aprono
	# subito la Mappa di Battaglia
	for a in args:
		if a.begins_with("scen:"):
			Session.scenario_id = a.substr(5)
	# "adv": gioca con le Regole Avanzate di Battaglia, come la casella nella
	# schermata iniziale
	Session.advanced_battle = args.has("adv")
	var packed: PackedScene = load(scene_path)
	_root_node = packed.instantiate()
	root.add_child(_root_node)
	_args = args


func _process(_delta: float) -> bool:
	_frames += 1
	# la configurazione va fatta dopo _ready() della scena, non in _initialize()
	if _frames == 2:
		# argomenti opzionali: <reticolo 0-3 | "splash"> <zoom> <centro_x> <centro_y>
		if _args.size() >= 2 and _args[1] == "splash":
			pass
		elif _args.size() >= 2:
			_root_node.board.set_grid_mode(int(_args[1]))
		if _args.size() >= 5:
			var cam: Camera2D = _root_node.cam
			var z := float(_args[2])
			cam.zoom = Vector2(z, z)
			cam.position = Vector2(float(_args[3]), float(_args[4]))
	# argomento 5: se vale "battle", apre una Battaglia di prova prima dello scatto
	if _frames == 6 and _args.size() >= 6 and _args[5] == "battle":
		var root_node: Node = _root_node
		var tf = root_node.selected_tf
		if tf != null:
			var en = root_node._nearest_enemy(tf)
			if en != null:
				var t = tf.trajectory
				root_node._open_battle(2, tf, en,
					t.station_hex if t.is_station() else t.end_hex(0))
	# Le texture salgono in VRAM al primo disegno: se lo scatto arriva subito
	# dopo, le pedine escono bianche. Si forza un ridisegno tardivo.
	if _frames == 6 and _args.size() >= 6 and _args[5] == "dialog":
		# seleziona una TF con una Traiettoria lunga e apre lo Scorrere del Tempo
		for tf in _root_node.state.task_forces:
			if tf.length() >= 5:
				_root_node.selected_tf = tf
				break
		_root_node._do_time_lapse()
	if _frames == 6 and _args.size() >= 6 and _args[5] == "help":
		_root_node._toggle_help()
	# "rounds:N": preme SPAZIO N volte prima dello scatto, per fotografare una
	# Battaglia a meta' invece che allo schieramento
	if _frames == 8:
		for a in _args:
			if a.begins_with("rounds:"):
				for n in int(a.substr(7)):
					var k := InputEventKey.new()
					k.keycode = KEY_SPACE
					k.pressed = true
					_root_node._unhandled_input(k)
	if _frames == 26 and _root_node != null and _root_node.get("_battle_view") != null:
		_root_node._battle_view.queue_redraw()
	if _frames < 34:
		return false
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	if err != OK:
		printerr("salvataggio non riuscito: %d" % err)
	else:
		print("screenshot salvato in %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	return true
