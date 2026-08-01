extends Node2D

## Controller principale della mappa (M3) e editor del grafo (M1c).
##
## Due modalita' nella stessa scena:
##   GIOCO   - selezione TF, costruzione della Traiettoria, Scorrere del Tempo, undo
##   EDITOR  - correzione del grafo: esagoni giocabili, lati "not adjacent", salvataggio
##
## L'editor sta qui e non in un'applicazione separata perche' le correzioni del
## grafo si scoprono giocando ("questa mossa non dovrebbe essere legale"), e si
## vogliono fare subito, guardando la stessa mappa.

enum Mode { PLAY, EDITOR }

const SCENARIO_DIR := "res://core/data/scenarios/"

var graph: MapGraph
var state: GameState
var log: CommandLog
var engine: ActionEngine

var board: MapBoard
var traj_layer: TrajectoryRenderer
var cam: MapCamera
var hud: Control

var mode: int = Mode.PLAY
var selected_tf: TaskForce = null
var active_end: int = 1            ## capo su cui si estende: 0 testa, 1 coda
var edit_anchor: Vector2i = Vector2i.MAX
var scenario_ids: Array[String] = []
var scenario_index: int = 0
var scenario: Scenario = null

var _messages: Array[String] = []


func _ready() -> void:
	graph = MapGraph.load_default()
	if graph.load_error != "":
		push_error(graph.load_error)
	state = GameState.new(graph, 20240114)
	engine = ActionEngine.load_default()

	board = MapBoard.new()
	board.name = "Board"
	add_child(board)
	board.setup(graph)

	traj_layer = TrajectoryRenderer.new()
	traj_layer.name = "Trajectories"
	traj_layer.z_index = 10
	add_child(traj_layer)
	traj_layer.setup(graph, state)

	cam = MapCamera.new()
	cam.name = "Camera"
	add_child(cam)
	cam.make_current()
	cam.setup(Vector2(graph.map_size))

	_build_hud()

	scenario_ids = Scenario.list_ids()
	_load_scenario_at(_default_scenario_index())

	log = CommandLog.new(state)
	_msg("Pronto. F1 per l'elenco dei comandi.")


# ------------------------------------------------------------------ scenari --

func _default_scenario_index() -> int:
	for i in scenario_ids.size():
		if scenario_ids[i].begins_with("Op5"):
			return i
	return 0


func _load_scenario_at(idx: int) -> void:
	if scenario_ids.is_empty():
		_msg("nessuno scenario (esegui tools/import_scenarios.py)")
		return
	scenario_index = wrapi(idx, 0, scenario_ids.size())
	scenario = Scenario.load_by_id(scenario_ids[scenario_index])
	if scenario.load_error != "":
		_msg(scenario.load_error)
		return
	state.apply_dict(scenario.to_state_dict())
	selected_tf = state.task_forces[0] if not state.task_forces.is_empty() else null
	traj_layer.selected_tf_id = selected_tf.id if selected_tf else -1
	log = CommandLog.new(state)
	_msg("Scenario: %s  -  %d Task Force, %d navi"
		% [scenario.title, state.task_forces.size(), scenario.ship_count()])
	if scenario.has_import_warnings():
		for w_v: Variant in scenario.import_warnings:
			_msg("  [avviso di import] %s" % String(w_v))
	_update_briefing()
	_focus_selected()
	_refresh()


# --------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var w := cam.world_from_screen((event as InputEventMouseMotion).position)
		var h := graph.pixel_to_hex(w)
		board.set_hover(h if graph.has_hex(h) else Vector2i.MAX)
		_update_preview(h)
		_refresh()
		return

	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		var w := cam.world_from_screen(mb.position)
		var h := graph.pixel_to_hex(w)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(h, mb.shift_pressed)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click(h)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		_on_key(event as InputEventKey)


func _on_key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_Z:
			if k.ctrl_pressed or k.meta_pressed:
				if k.shift_pressed:
					if log.redo():
						_msg("ripristinato")
				elif log.undo():
					_msg("annullato")
				_resync_selection()
				_refresh()
		KEY_TAB:
			_cycle_tf(1 if not k.shift_pressed else -1)
		KEY_G:
			board.set_grid_mode((board.grid_mode + 1) % 4)
			_msg("reticolo: %s" % ["nascosto", "leggero", "pieno", "editor"][board.grid_mode])
		KEY_E:
			mode = Mode.EDITOR if mode == Mode.PLAY else Mode.PLAY
			board.set_grid_mode(MapBoard.GridMode.EDITOR if mode == Mode.EDITOR
				else MapBoard.GridMode.SUBTLE)
			edit_anchor = Vector2i.MAX
			_msg("modalita': %s" % ("EDITOR del grafo" if mode == Mode.EDITOR else "gioco"))
		KEY_F:
			active_end = 1 - active_end
			_msg("capo attivo: %s" % ("testa" if active_end == 0 else "coda"))
		KEY_T:
			_do_time_lapse()
		KEY_S:
			if k.ctrl_pressed or k.meta_pressed:
				_save_graph()
		KEY_BRACKETLEFT:
			_load_scenario_at(scenario_index - 1)
		KEY_BRACKETRIGHT:
			_load_scenario_at(scenario_index + 1)
		KEY_W:
			if k.ctrl_pressed:
				state.weather = 1 - state.weather
				_msg("meteo: %s" % ("cattivo" if state.weather == 1 else "buono"))
		KEY_1:
			_declare_action("ENGAGE")
		KEY_2:
			_declare_action("NAVAL_SEARCH")
		KEY_3:
			_declare_action("AIR_STRIKE")
		KEY_4:
			_declare_action("STEALTH_ATTACK")
		KEY_B:
			_briefing_panel.visible = not _briefing_panel.visible
		KEY_F1:
			_toggle_help()
		KEY_HOME:
			_focus_selected()
	_refresh()


## Dichiara un'azione della TF selezionata contro la TF avversaria piu' vicina.
## La scelta completa delle designazioni (Coordinatrice, Supporto Aereo) arrivera'
## con il pannello dedicato; qui basta a rendere il motore verificabile a mano.
func _declare_action(key: String) -> void:
	if selected_tf == null:
		_msg("nessuna Task Force selezionata")
		return
	var target := _nearest_enemy(selected_tf)
	if target == null:
		_msg("nessuna Task Force avversaria in gioco")
		return
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = selected_tf
	dec.target = target
	var t := target.trajectory
	dec.target_hex = t.station_hex if t.is_station() else t.end_hex(0)

	var res := engine.resolve(dec, state)
	var label := String(engine.action(key).get("label", key))
	if not res["ok"]:
		_msg("%s: %s" % [label, res["error"]])
		return
	_msg("%s -> %s" % [label, engine.describe(res)])
	for code_v: Variant in res["results"] as Array:
		var applied := Results.apply(String(code_v), selected_tf, target,
			dec.target_hex, state)
		_msg("    %s" % applied["text"])
		if applied["battle"] != Results.Battle.NONE:
			_msg("    [Mappa di Battaglia non ancora implementata (M5)]")
	log.record("%s (%s)" % [label, selected_tf.display_name()])
	state.changed.emit()


func _nearest_enemy(tf: TaskForce) -> TaskForce:
	var best: TaskForce = null
	var bestd := INF
	var t := tf.trajectory
	var from := graph.center_of(t.station_hex if t.is_station() else t.end_hex(0))
	for other in state.task_forces:
		if other.side == tf.side:
			continue
		var ot := other.trajectory
		var oh := ot.station_hex if ot.is_station() else ot.end_hex(0)
		var d := from.distance_to(graph.center_of(oh))
		if d < bestd:
			bestd = d
			best = other
	return best


func _on_left_click(h: Vector2i, shift: bool) -> void:
	if mode == Mode.EDITOR:
		_editor_click(h, shift)
		return

	# 1) se c'e' una TF nell'esagono e non stiamo estendendo, selezionala
	var here := state.forces_in(h)
	if not here.is_empty() and (selected_tf == null or not _can_extend_to(h)):
		var idx := here.find(selected_tf)
		selected_tf = here[(idx + 1) % here.size()] if idx >= 0 else here[0]
		traj_layer.selected_tf_id = selected_tf.id
		_msg("selezionata %s (%d segmenti)"
			% [selected_tf.display_name(), selected_tf.length()])
		return

	# 2) altrimenti prova a estendere la Traiettoria selezionata
	if selected_tf == null:
		_msg("nessuna Task Force selezionata")
		return
	_try_extend(h)


func _on_right_click(h: Vector2i) -> void:
	if mode == Mode.EDITOR:
		if graph.has_hex(h):
			edit_anchor = h
			_msg("ancora impostata su %s (clic sinistro su un vicino per bloccare il lato)"
				% str(h))
		return
	if selected_tf == null:
		return
	var traj := selected_tf.trajectory
	if traj.is_station():
		_msg("%s e' una Stazione: non ci sono segmenti da rimuovere"
			% selected_tf.display_name())
		return
	# rimuove dal capo piu' vicino al clic
	var d0 := graph.center_of(traj.end_hex(0)).distance_to(graph.center_of(h))
	var d1 := graph.center_of(traj.end_hex(1)).distance_to(graph.center_of(h))
	var end := 0 if d0 <= d1 else 1
	var freed := traj.remove_end(end)
	if traj.length() == 0:
		traj.become_station(freed)
		_msg("%s ha esaurito i segmenti: diventa Stazione in %s"
			% [selected_tf.display_name(), str(freed)])
	else:
		_msg("rimosso un segmento dalla %s" % ("testa" if end == 0 else "coda"))
	log.record("rimozione segmento (%s)" % selected_tf.display_name())
	state.changed.emit()


func _can_extend_to(h: Vector2i) -> bool:
	if selected_tf == null:
		return false
	return selected_tf.trajectory.extend_error(
		h, active_end, graph, state.port_hexes(), selected_tf.side) == ""


func _try_extend(h: Vector2i) -> void:
	var traj := selected_tf.trajectory
	var ports := state.port_hexes()
	# prova prima il capo attivo, poi l'altro: evita di dover premere F di continuo
	var ends := [active_end, 1 - active_end]
	for e_v: Variant in ends:
		var e: int = e_v
		var err := traj.extend_error(h, e, graph, ports, selected_tf.side)
		if err == "":
			var info := state.triggers_info(h, selected_tf.side)
			traj.extend(h, e, graph, ports, info, selected_tf.side)
			active_end = e
			var extra := ""
			if info:
				extra = "  -> segnalino INFORMAZIONI (%s)" \
					% ", ".join(state.info_reasons(h, selected_tf.side))
			_msg("%s estesa a %s (%d segmenti)%s"
				% [selected_tf.display_name(), str(h), traj.length(), extra])
			log.record("estensione (%s)" % selected_tf.display_name(),
				{"tf": selected_tf.id, "hex": [h.x, h.y]})
			state.changed.emit()
			return
	_msg("mossa illegale: %s" % traj.extend_error(h, active_end, graph, ports, selected_tf.side))


func _cycle_tf(step: int) -> void:
	if state.task_forces.is_empty():
		return
	var i := state.task_forces.find(selected_tf)
	i = wrapi(i + step, 0, state.task_forces.size())
	selected_tf = state.task_forces[i]
	traj_layer.selected_tf_id = selected_tf.id
	_focus_selected()
	_msg("selezionata %s" % selected_tf.display_name())


func _focus_selected() -> void:
	if selected_tf == null:
		return
	var t := selected_tf.trajectory
	var h := t.station_hex if t.is_station() else t.end_hex(1)
	cam.focus_on(graph.center_of(h))


func _resync_selection() -> void:
	if selected_tf == null:
		return
	selected_tf = state.task_force(selected_tf.id)
	traj_layer.selected_tf_id = selected_tf.id if selected_tf else -1


# --------------------------------------------------------- Scorrere del Tempo --

func _do_time_lapse() -> void:
	if selected_tf == null:
		return
	var traj := selected_tf.trajectory
	if traj.is_station():
		_msg("%s e' gia' una Stazione" % selected_tf.display_name())
		return
	var amount := TimeLapse.required_removal(selected_tf.speed, state.weather, state.rng)
	var opts := TimeLapse.removal_options(traj, selected_tf.speed, amount)
	if opts.is_empty():
		_msg("nessuna rimozione legale")
		return
	# scelta automatica: la prima opzione senza Limite di Informazioni.
	# In M4 questa scelta passera' al giocatore tramite un pannello.
	var chosen: Dictionary = opts[0]
	for o in opts:
		if not o["uses_intel_limit"]:
			chosen = o
			break
	var freed := TimeLapse.apply(traj, chosen)
	var note := ""
	if traj.length() == 0 and not freed.is_empty():
		traj.become_station(freed[0])
		note = " -> diventa Stazione in %s" % str(freed[0])
	_msg("Scorrere del Tempo (%s, meteo %s): richiesti %d, %s%s"
		% [TimeLapse.SPEED_LABELS[selected_tf.speed],
			"cattivo" if state.weather == 1 else "buono",
			amount, chosen["label"], note])
	log.record("Scorrere del Tempo (%s)" % selected_tf.display_name())
	state.changed.emit()


# ------------------------------------------------------------------- editor --

func _editor_click(h: Vector2i, shift: bool) -> void:
	if shift and edit_anchor != Vector2i.MAX:
		if not Hex.are_adjacent(edit_anchor, h):
			_msg("i due esagoni non sono adiacenti")
			return
		var now := not graph.is_edge_blocked(edit_anchor, h)
		graph.block_edge(edit_anchor, h, now)
		_msg("lato %s-%s: %s" % [str(edit_anchor), str(h),
			"NEGATO ('not adjacent')" if now else "ripristinato"])
		board.queue_redraw()
		return
	edit_anchor = h
	if graph.has_hex(h):
		_msg("ancora su %s. Shift+clic su un vicino per negare/ripristinare il lato."
			% str(h))
	else:
		_msg("%s non fa parte dell'area di gioco" % str(h))


func _save_graph() -> void:
	var src := FileAccess.open(MapGraph.DATA_PATH, FileAccess.READ)
	if src == null:
		_msg("impossibile rileggere map_graph.json")
		return
	var doc: Dictionary = JSON.parse_string(src.get_as_text())
	src.close()

	var edges: Array = []
	for h_v: Variant in graph.all_hexes():
		var h: Vector2i = h_v
		for d in 6:
			var n := Hex.neighbor(h, d)
			if not graph.has_hex(n):
				continue
			if graph.is_edge_blocked(h, n) and (h.x < n.x or (h.x == n.x and h.y < n.y)):
				edges.append({"aq": h.x, "ar": h.y, "bq": n.x, "br": n.y})
	doc["blocked_edges"] = edges

	var out := FileAccess.open(MapGraph.DATA_PATH, FileAccess.WRITE)
	if out == null:
		_msg("scrittura non riuscita (in un export il filesystem e' di sola lettura)")
		return
	out.store_string(JSON.stringify(doc, " "))
	out.close()
	_msg("map_graph.json salvato: %d lati negati" % edges.size())


# ------------------------------------------------------------------ anteprima --

func _update_preview(h: Vector2i) -> void:
	if mode != Mode.PLAY or selected_tf == null or not graph.has_hex(h):
		traj_layer.clear_preview()
		return
	var traj := selected_tf.trajectory
	var ports := state.port_hexes()
	var err := traj.extend_error(h, active_end, graph, ports, selected_tf.side)
	var other := traj.extend_error(h, 1 - active_end, graph, ports, selected_tf.side)
	if err != "" and other != "":
		traj_layer.clear_preview()
		return
	var e := active_end if err == "" else 1 - active_end
	traj_layer.set_preview([traj.end_hex(e), h] as Array[Vector2i], true)


# ----------------------------------------------------------------------- HUD --

var _lbl_title: Label
var _lbl_info: RichTextLabel
var _lbl_log: RichTextLabel
var _help: PanelContainer
var _briefing_panel: PanelContainer
var _lbl_briefing: RichTextLabel


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(380, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	_lbl_title = Label.new()
	_lbl_title.add_theme_font_size_override("font_size", 18)
	vb.add_child(_lbl_title)

	_lbl_info = RichTextLabel.new()
	_lbl_info.bbcode_enabled = true
	_lbl_info.fit_content = true
	_lbl_info.custom_minimum_size = Vector2(340, 0)
	_lbl_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_lbl_info)

	var logpanel := PanelContainer.new()
	logpanel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	logpanel.offset_left = 12
	logpanel.offset_right = -12
	logpanel.offset_top = -168
	logpanel.offset_bottom = -12
	logpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logpanel.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(logpanel)

	_lbl_log = RichTextLabel.new()
	_lbl_log.bbcode_enabled = true
	_lbl_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logpanel.add_child(_lbl_log)

	_build_briefing(hud)
	_build_help(hud)


## Sfondo scuro semitrasparente: senza, il testo bianco sull'azzurro della
## mappa e' semplicemente illeggibile.
func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.10, 0.88)
	sb.border_color = Color(0.45, 0.60, 0.72, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## Pannello del briefing: iniziativa, meteo, fine partita e condizioni di
## vittoria dal fascicolo. Le condizioni di vittoria restano testo, applicate
## dai giocatori: in Atlantic Chase sono discorsive e piene di eccezioni.
func _build_briefing(root: Control) -> void:
	_briefing_panel = PanelContainer.new()
	_briefing_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_briefing_panel.position = Vector2(-560, -300)
	_briefing_panel.visible = false
	_briefing_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_briefing_panel)
	_lbl_briefing = RichTextLabel.new()
	_lbl_briefing.bbcode_enabled = true
	_lbl_briefing.custom_minimum_size = Vector2(520, 600)
	_briefing_panel.add_child(_lbl_briefing)


func _update_briefing() -> void:
	if _lbl_briefing == null or scenario == null:
		return
	var txt := scenario.briefing_text()
	if scenario.has_import_warnings():
		txt += "\n\n[color=#ff9a3c][b]Avvisi di import[/b][/color]"
		for w_v: Variant in scenario.import_warnings:
			txt += "\n  " + String(w_v)
	_lbl_briefing.text = txt


func _build_help(root: Control) -> void:
	_help = PanelContainer.new()
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.position = Vector2(-280, -240)
	_help.visible = false
	_help.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_help)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.custom_minimum_size = Vector2(520, 430)
	t.text = """[b]Atlantic Chase - comandi[/b]

[b]Mappa[/b]
  trascina col tasto centrale, oppure WASD    sposta
  rotella                                     zoom sul cursore
  Home                                        centra sulla TF selezionata

[b]Gioco[/b]
  clic sinistro su una TF                     seleziona
  clic sinistro su un esagono adiacente       estende la Traiettoria
  clic destro                                 rimuove un segmento dal capo piu' vicino
  Tab / Shift+Tab                             TF successiva / precedente
  F                                           cambia capo attivo (testa/coda)
  T                                           Scorrere del Tempo sulla TF selezionata
  1                                           azione Ingaggiare      (tabella verificata)
  2                                           azione Ricerca Navale  (verifica parziale)
  3 / 4                                       Attacco Aereo / Furtivo (tabelle da trascrivere)
  Ctrl+W                                      alterna meteo buono/cattivo
  Ctrl+Z / Ctrl+Shift+Z                       annulla / ripristina
  [ e ]                                       scenario precedente / successivo
  B                                           mostra/nasconde il briefing

[b]Editor del grafo (E)[/b]
  clic destro                                 imposta l'ancora
  Shift+clic su un vicino                     nega/ripristina il lato ("not adjacent")
  Ctrl+S                                      salva map_graph.json

  G                                           cambia visibilita' del reticolo
  F1                                          chiude questo pannello"""
	_help.add_child(t)


func _toggle_help() -> void:
	_help.visible = not _help.visible


func _msg(s: String) -> void:
	_messages.append(s)
	if _messages.size() > 8:
		_messages.pop_front()


func _refresh() -> void:
	if _lbl_title == null:
		return
	var sc := scenario.title if scenario != null else "-"
	_lbl_title.text = "%s   [%s]" % [sc, "EDITOR" if mode == Mode.EDITOR else "gioco"]

	var lines: Array[String] = []
	lines.append("Meteo: [b]%s[/b]    Iniziativa: [b]%s[/b]"
		% ["cattivo" if state.weather == 1 else "buono",
			"Kriegsmarine" if state.initiative == 0 else "Royal Navy"])
	lines.append("Punti Vittoria - KM [b]%d[/b]   RN [b]%d[/b]"
		% [state.vp_of(TaskForce.Side.KRIEGSMARINE),
			state.vp_of(TaskForce.Side.ROYAL_NAVY)])
	if selected_tf != null:
		var t := selected_tf.trajectory
		var kind := "Stazione" if t.is_station() else "Traiettoria"
		lines.append("")
		lines.append("[b]%s[/b]  (%s)" % [selected_tf.display_name(), selected_tf.color])
		lines.append("  %s, [b]%d[/b] segmenti su %d" % [kind, t.length(),
			Trajectory.MAX_SEGMENTS])
		lines.append("  velocita': %s    capo attivo: %s"
			% [TimeLapse.SPEED_LABELS[selected_tf.speed],
				"testa" if active_end == 0 else "coda"])
		lines.append("  Informazioni: [b]%d[/b]    Contatto: %d"
			% [t.info_count(), t.contact_count()])
		if not selected_tf.ships.is_empty():
			var names: Array[String] = []
			for sh in selected_tf.ships:
				names.append(sh.display())
			lines.append("  Navi: %s" % ", ".join(names))
		if selected_tf.leader != "":
			lines.append("  Comandante: [b]%s[/b]" % selected_tf.leader)
		if t.info_count() > 0:
			lines.append("  [color=#ff9a3c]Completamento impedito; vulnerabile a Interruzione[/color]")
		# Totale Traiettoria contro la prima TF avversaria
		var enemy: TaskForce = null
		for tf in state.task_forces:
			if tf.side != selected_tf.side:
				enemy = tf
				break
		if enemy != null:
			var d := TrajectoryTotal.Designations.new(t.length(), enemy.length())
			lines.append("  Totale Traiettoria vs %s: [b]%d[/b]"
				% [enemy.display_name(), TrajectoryTotal.compute(d)])
	_lbl_info.text = "\n".join(lines)

	var lg: Array[String] = []
	lg.append("[b]Mosse:[/b] %d    (F1 = comandi)" % log.applied_count() if log else "")
	for m in _messages:
		lg.append("  " + m)
	_lbl_log.text = "\n".join(lg)
