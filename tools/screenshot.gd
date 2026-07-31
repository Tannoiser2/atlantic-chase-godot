extends SceneTree

## Avvia la scena principale, lascia passare qualche frame e salva un PNG.
## Serve a verificare il rendering senza guardare a occhio una finestra:
##     godot --path . --script res://tools/screenshot.gd -- <output.png> [scenario]

var _frames := 0
var _out := "user://shot.png"
var _root_node: Node = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var packed: PackedScene = load("res://ui/main.tscn")
	_root_node = packed.instantiate()
	root.add_child(_root_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 30:
		return false
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	if err != OK:
		printerr("salvataggio non riuscito: %d" % err)
	else:
		print("screenshot salvato in %s (%dx%d)" % [_out, img.get_width(), img.get_height()])
	return true
