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
	var packed: PackedScene = load("res://ui/main.tscn")
	_root_node = packed.instantiate()
	root.add_child(_root_node)
	_args = args


func _process(_delta: float) -> bool:
	_frames += 1
	# la configurazione va fatta dopo _ready() della scena, non in _initialize()
	if _frames == 2:
		# argomenti opzionali: <reticolo 0-3> <zoom> <centro_x> <centro_y>
		if _args.size() >= 2:
			_root_node.board.set_grid_mode(int(_args[1]))
		if _args.size() >= 5:
			var cam: Camera2D = _root_node.cam
			var z := float(_args[2])
			cam.zoom = Vector2(z, z)
			cam.position = Vector2(float(_args[3]), float(_args[4]))
	if _frames < 30:
		return false
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	if err != OK:
		printerr("salvataggio non riuscito: %d" % err)
	else:
		print("screenshot salvato in %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	return true
