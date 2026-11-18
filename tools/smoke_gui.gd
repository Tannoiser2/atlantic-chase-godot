extends SceneTree

## Prova di fumo della nuova interfaccia: guida, rotta evidenziata, menu,
## trascinamento della mappa, Casella Porto, e la caccia al testo verticale.
##
##     godot --path . --script res://tools/smoke_gui.gd
##
## Usa eventi di mouse veri, che attraversano HUD, SubViewport e proxy della
## mappa. Controlla cio' che prima si scopriva solo guardando lo schermo:
##
##   1. la riga di guida dice sempre qualcosa e offre un pulsante;
##   2. "Traccia la rotta" arma l'azione e accende gli esagoni legali;
##      "Rotta finita" la chiude e li spegne, senza cedere l'Iniziativa;
##   3. trascinare sul mare sposta la mappa e NON deseleziona ne' estende;
##   4. il Menu si apre e si chiude;
##   5. entrare e uscire dalla Casella Porto e' un pulsante della scheda;
##   6. nessuna etichetta con a capo automatico e' piu' stretta di 110 px - il
##      difetto del testo "una lettera per riga";
##   7. il salvataggio automatico si scrive e si ricarica;
##   8. nessun carattere a video e' fuori dai font (lo fa
##      `tools/controlla_glifi.py`, che legge anche i dati).

var _f := 0
var _root: Node
var _tf: TaskForce
var _failures: Array[String] = []
var _cam_before := Vector2.ZERO


func _initialize() -> void:
	Session.scenario_id = "Op5 Rheinubung"
	Session.advanced_battle = false
	Session.resume_path = ""
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _guide_button(text: String) -> Button:
	for c in _root._guide_buttons.get_children():
		if c is Button and not c.is_queued_for_deletion() \
				and (c as Button).text == text:
			return c
	return null


func _tf_button(text: String) -> Button:
	for c in _root._tf_buttons.get_children():
		if c is Button and not c.is_queued_for_deletion() \
				and (c as Button).text == text:
			return c
	return null


func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	if pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


func _move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)


## Un punto di mare libero dentro il riquadro della mappa: lontano dalle
## Stazioni, dai bordi e dai pulsanti della vista.
func _sea_point() -> Vector2:
	var rect: Rect2 = _root._map_container.get_global_rect()
	return rect.position + rect.size * Vector2(0.62, 0.72)


## Cerca le etichette che vanno a capo e sono rimaste senza larghezza.
func _narrow_labels(node: Node, out: Array[String]) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	var wraps := false
	if node is Label:
		wraps = (node as Label).autowrap_mode != TextServer.AUTOWRAP_OFF \
			and (node as Label).text.length() > 12
	elif node is RichTextLabel:
		wraps = (node as RichTextLabel).autowrap_mode != TextServer.AUTOWRAP_OFF \
			and (node as RichTextLabel).get_parsed_text().length() > 12
	if wraps and (node as Control).size.x < 110.0:
		out.append("%s (largo %.0f)" % [node.get_path(), (node as Control).size.x])
	for c in node.get_children():
		_narrow_labels(c, out)


func _process(_delta: float) -> bool:
	_f += 1
	match _f:
		20:
			_tf = _root.selected_tf
			_expect(_tf != null, "all'avvio c'e' una Task Force selezionata")
			if _tf == null:
				return _finish()
			_expect(_root._guide_label.text.length() > 10,
				"la riga di guida dice che cosa fare")
			_expect(_guide_button("Traccia la rotta") != null,
				"e offre il pulsante per tracciare la rotta")
			var narrow: Array[String] = []
			_narrow_labels(_root.hud, narrow)
			_expect(narrow.is_empty(), "nessuna etichetta schiacciata: %s"
				% ", ".join(narrow))
			_expect(_root._bar._act_buttons.size() == 9,
				"le nove azioni sono tutte nella barra")
			var b := _guide_button("Traccia la rotta")
			if b != null:
				b.pressed.emit()
		30:
			_expect(_root._trajectory_action_armed, "il pulsante arma la Traiettoria")
			_expect(not _root.board.highlight.is_empty(),
				"e gli esagoni legali si accendono")
			for h_v: Variant in _root.board.highlight.keys():
				_expect(_tf.trajectory.extend_error(h_v, 0, _root.graph,
					_root.state.port_hexes(), _tf.side) == "" \
					or _tf.trajectory.extend_error(h_v, 1, _root.graph,
					_root.state.port_hexes(), _tf.side) == "",
					"ogni esagono acceso e' una mossa legale (%s)" % str(h_v))
			_expect(_guide_button("Rotta finita") != null,
				"la guida offre Rotta finita")
			var b := _guide_button("Rotta finita")
			if b != null:
				b.pressed.emit()
		40:
			_expect(not _root._trajectory_action_armed, "Rotta finita chiude l'azione")
			_expect(_root.board.highlight.is_empty(), "e spegne gli esagoni")
			_expect(_root.state.initiative == _tf.side,
				"senza cedere l'Iniziativa (RB p.43)")
			# trascinamento sul mare
			_cam_before = _root.cam.position
			_root.cam.zoom_by(2.0)
		46:
			_cam_before = _root.cam.position
			var p := _sea_point()
			_mouse(p, true)
		48:
			_move(_sea_point() + Vector2(-30, -10), Vector2(-30, -10))
		50:
			_move(_sea_point() + Vector2(-90, -40), Vector2(-60, -30))
		52:
			_mouse(_sea_point() + Vector2(-90, -40), false)
		60:
			_expect(_root.cam.position.distance_to(_cam_before) > 20.0,
				"trascinare sul mare sposta la mappa (spostata di %.0f)"
					% _root.cam.position.distance_to(_cam_before))
			_expect(_root.selected_tf == _tf,
				"e non deseleziona la Task Force")
			_expect(_tf.trajectory.is_station(), "ne' traccia una rotta")
			_root._toggle_menu()
		64:
			_expect(_root._menu_panel.visible, "il Menu si apre")
			var menu_rect: Rect2 = _root._menu_panel.get_global_rect()
			var full: Vector2 = _root.get_viewport_rect().size
			_expect(menu_rect.position.x >= 0.0 and menu_rect.end.x <= full.x + 1.0
				and menu_rect.end.y <= full.y + 1.0,
				"e sta tutto dentro lo schermo (%s)" % str(menu_rect))
			_root._close_menu()
		68:
			_expect(not _root._menu_panel.visible, "il Menu si chiude")
			# Casella Porto: la Bismarck parte da un porto tedesco
			var enter := _tf_button("Entra nella Casella Porto")
			_expect(enter != null, "la scheda offre di entrare nella Casella Porto")
			if enter != null:
				enter.pressed.emit()
		76:
			_expect(PortBox.is_in_box(_tf), "il pulsante porta la TF nella Casella")
			var leave := _tf_button("Esci dalla Casella Porto")
			_expect(leave != null, "e la scheda offre di uscirne")
			if leave != null:
				leave.pressed.emit()
		84:
			_expect(not PortBox.is_in_box(_tf), "il pulsante la riporta nell'esagono")
			_root._toggle_help()
		88:
			_expect(_root._help.visible, "l'Aiuto si apre")
			var narrow: Array[String] = []
			_narrow_labels(_root.hud, narrow)
			_expect(narrow.is_empty(), "nessuna etichetta schiacciata con l'Aiuto "
				+ "aperto: %s" % ", ".join(narrow))
			_root._toggle_help()
			# salvataggio automatico: si scrive, e ricaricarlo rimette lo stato
			_root._autosave(true)
			var path := ""
			for sv in SaveGame.list_saves():
				if String(sv["name"]) == "Automatico - Op5 Rheinubung":
					path = String(sv["path"])
			_expect(path != "", "il salvataggio automatico viene scritto")
			if path != "":
				var round_saved: int = _root.state.round_number
				_root.state.round_number = round_saved + 3
				_root._load_save_path(path)
				_expect(_root.state.round_number == round_saved,
					"e ricaricarlo riporta la partita dov'era")
				_expect(_root.selected_tf != null,
					"con una Task Force di nuovo selezionata")
			return _finish()
	return false


func _finish() -> bool:
	if _failures.is_empty():
		print("\nINTERFACCIA NUOVA: OK - guida, rotta evidenziata, trascinamento, "
			+ "menu, Casella Porto, salvataggio automatico, nessun testo schiacciato")
		quit(0)
	else:
		print("\nINTERFACCIA NUOVA: FALLITA")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
	return true
