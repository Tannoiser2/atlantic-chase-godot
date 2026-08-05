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
		# Una mappa inserto e' VERTICALE: la superficie di gioco si sposta
		# nella colonna di sinistra, alta quanto la finestra, e i pannelli si
		# prendono il centro. Prima stava in un riquadro orizzontale con due
		# fasce nere ai lati.
		var map_rect: Rect2 = _root._map_container.get_global_rect()
		var full: Vector2 = _root._map_container.get_viewport_rect().size
		if not _check(_root._inset_layout(), "la disposizione passa a inserto"):
			return true
		if not _check(map_rect.size.y > map_rect.size.x,
				"la mappa e' piu' alta che larga (%.0fx%.0f)"
					% [map_rect.size.x, map_rect.size.y]):
			return true
		if not _check(map_rect.end.y > full.y - 32.0,
				"e arriva in fondo alla finestra (%.0f su %.0f)"
					% [map_rect.end.y, full.y]):
			return true
		if not _check(map_rect.position.x < 24.0,
				"partendo da sinistra (x=%.0f)" % map_rect.position.x):
			return true
		# E la camera inquadra la mappa NELLA nuova misura: se si inquadrasse
		# quella di prima, l'inserto resterebbe piccolo fra due fasce nere.
		var shown: float = _root.graph.map_size.y * _root.cam.zoom.y
		if not _check(shown > map_rect.size.y * 0.85,
				"la camera riempie il riquadro (%.0f su %.0f)"
					% [shown, map_rect.size.y]):
			return true
		# I pannelli non restano sotto una mappa che ormai e' alta quanto la
		# finestra: si spostano nel centro liberato.
		var panels: Rect2 = _root._bottom_row.get_global_rect()
		if not _check(panels.position.x >= map_rect.end.x - 1.0,
				"i pannelli stanno a destra della mappa (%.0f contro %.0f)"
					% [panels.position.x, map_rect.end.x]):
			return true
		if not _check(panels.size.y > 400.0,
				"e si prendono l'altezza del centro (%.0f)" % panels.size.y):
			return true
		# Difetto gia' pagato: qui il registro e' alto quanto la finestra, e la
		# fascia arrivava al bordo destro come nell'altra disposizione. La
		# scheda della Task Force finiva sopra il registro e si leggevano tutti
		# e due insieme.
		if not _check(panels.end.x <= _root._log_panel.get_global_rect().position.x + 1.0,
				"e non finiscono sopra il registro (%.0f contro %.0f)"
					% [panels.end.x, _root._log_panel.get_global_rect().position.x]):
			return true
		# Difetto gia' pagato: affiancati in una colonna stretta, la scheda
		# della Task Force schiacciava il pannello di stato a una lettera per
		# riga. Qui si impilano.
		var status: Control = _root._bottom_row.get_node("StatusPanel")
		if not _check(status.size.x > 300.0,
				"il pannello di stato resta leggibile (largo %.0f)" % status.size.x):
			return true
		if not _check(_root._tf_panel.get_global_rect().position.y >= status.get_global_rect().end.y - 1.0,
				"e la scheda della Task Force gli sta SOTTO, non accanto"):
			return true
		if not _check(_root._grab_inset.visible and not _root._grab_bottom.visible,
				"la maniglia e' quella del bordo verticale, non dell'orizzontale"):
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
	# E la disposizione torna quella larga: mappa al centro, pannelli sotto.
	if not _check(not _root._inset_layout(), "la disposizione torna larga"):
		return true
	var wide: Rect2 = _root._map_container.get_global_rect()
	if not _check(wide.size.x > wide.size.y,
			"la mappa torna piu' larga che alta (%.0fx%.0f)"
				% [wide.size.x, wide.size.y]):
		return true
	if not _check(_root._bottom_row.get_global_rect().position.y > wide.end.y - 1.0,
			"e i pannelli tornano sotto la mappa"):
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
