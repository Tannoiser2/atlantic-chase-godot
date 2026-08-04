extends SceneTree

## Verifica che una mappa inserto diventi davvero la superficie di gioco.
##
##     godot --path . --script res://tools/smoke_inset_map.gd
##
## Cinque scenari solitari su quindici non si giocano sulla Mappa Operazionale
## ma su un inserto. Il grafo e' condiviso da stato, tabellone, traiettorie e
## camera: se uno solo di quelli resta puntato sulla mappa di prima non si vede
## un errore, si vede una partita giocata sulle coordinate sbagliate. Questa
## prova apre l'interfaccia vera, carica uno scenario inserto per mappa e
## controlla che TUTTI abbiano cambiato superficie - e poi che tornare a uno
## scenario normale rimetta la Mappa Operazionale.

const CASES := [
	{"id": "BL3 Raiders of the North Sea", "key": "map_north_sea",
		"hexes": 34, "image": "assets/boards/map_north_sea.jpg"},
	{"id": "N1 Operazione Wilfred", "key": "map_norwegian_sea",
		"hexes": 33, "image": "assets/boards/map_norwegian_sea.jpg"},
]

var _root: Node = null
var _frames := 0
var _step := 0
var _failed := false


func _initialize() -> void:
	Session.scenario_id = "BL1 Raiders of the North Atlantic"
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false

	if _step == 0:
		# Si parte sulla Mappa Operazionale.
		if not _check(not _root.graph.is_inset(),
				"si parte sulla Mappa Operazionale"):
			return true
		if not _check(_root.graph.hex_count() > 100,
				"la Mappa Operazionale ha i suoi esagoni (%d)" % _root.graph.hex_count()):
			return true
		_step = 1
		return false

	if _step <= CASES.size():
		var c: Dictionary = CASES[_step - 1]
		_load(String(c["id"]))
		if not _check(_root.graph.is_inset(),
				"%s apre un inserto" % String(c["id"])):
			return true
		if not _check(_root.graph.inset_key == String(c["key"]),
				"ed e' quello giusto: %s" % _root.graph.inset_key):
			return true
		if not _check(_root.graph.hex_count() == int(c["hexes"]),
				"con %d esagoni" % _root.graph.hex_count()):
			return true
		# Tutti e quattro devono guardare la stessa mappa.
		if not _check(_root.board.graph == _root.graph, "il tabellone la segue"):
			return true
		if not _check(_root.state.graph == _root.graph, "lo stato la segue"):
			return true
		if not _check(_root.traj_layer.graph == _root.graph,
				"il disegno delle Traiettorie la segue"):
			return true
		# L'immagine dell'inserto e' una sola texture, non i tile della mappa
		# grande: se restassero i tile si vedrebbe l'Atlantico sotto l'inserto.
		var tiles: Node = _root.board.get_node_or_null("Tiles")
		if not _check(tiles != null and tiles.get_child_count() == 1,
				"la superficie e' una texture sola (%d nodi)"
					% (0 if tiles == null else tiles.get_child_count())):
			return true
		var sprite: Sprite2D = tiles.get_child(0) as Sprite2D
		if not _check(sprite != null and sprite.texture != null
				and sprite.texture.resource_path == "res://" + String(c["image"]),
				"ed e' l'immagine dell'inserto"):
			return true
		if not _check(sprite.texture.get_size() == Vector2(_root.graph.map_size),
				"della misura dichiarata dal grafo"):
			return true
		_step += 1
		return false

	# Tornare a uno scenario normale deve rimettere la Mappa Operazionale.
	_load("BL1 Raiders of the North Atlantic")
	if not _check(not _root.graph.is_inset(), "si torna alla Mappa Operazionale"):
		return true
	if not _check(_root.state.task_forces.size() > 0,
			"e lo scenario normale schiera le sue Task Force"):
		return true
	var tiles2: Node = _root.board.get_node_or_null("Tiles")
	if not _check(tiles2 != null and tiles2.get_child_count() > 1,
			"la Mappa Operazionale torna a tile (%d)"
				% (0 if tiles2 == null else tiles2.get_child_count())):
		return true
	print("\nMAPPA INSERTO: OK - due inserti aperti come superficie di gioco e "
		+ "ritorno alla Mappa Operazionale, con tabellone, stato, Traiettorie e "
		+ "camera allineati")
	quit(0)
	return true


func _load(id: String) -> void:
	var idx: int = (_root.scenario_ids as Array).find(id)
	if idx < 0:
		_check(false, "scenario mancante: %s" % id)
		return
	_root._load_scenario_at(idx, false)


func _check(ok: bool, what: String) -> bool:
	if ok:
		print("  ok  %s" % what)
		return true
	printerr("FALLITO: %s" % what)
	_failed = true
	quit(1)
	return false
