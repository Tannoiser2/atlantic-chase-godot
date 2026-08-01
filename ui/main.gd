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

## Trascinamento per disegnare la Traiettoria: si tiene premuto su una Task
## Force (o su un capo della sua Traiettoria) e si trascina sugli esagoni; i
## segmenti si accumulano in anteprima e si confermano al rilascio. E' il gesto
## naturale per tracciare una rotta, invece di un clic per esagono.
var dragging: bool = false
var drag_end: int = 1
var drag_path: Array[Vector2i] = []
var _press_hex: Vector2i = Vector2i.MAX
var _press_shift: bool = false

## Su schermo tattile non esiste il tasto destro: un tocco prolungato sullo
## stesso esagono fa la stessa cosa, cioe' rimuove un segmento dal capo piu'
## vicino. Il conto parte alla pressione e si annulla se il dito si sposta.
const LONG_PRESS_SECONDS := 0.55
var _press_time: float = 0.0
var _long_press_done: bool = false
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

## Lo scenario scelto nella schermata iniziale; se manca (avvio diretto della
## scena di gioco, come nei test e negli screenshot) si parte da Rheinubung.
func _default_scenario_index() -> int:
	if Session.has_choice():
		var idx := scenario_ids.find(Session.scenario_id)
		if idx >= 0:
			return idx
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


func _process(delta: float) -> void:
	# tocco prolungato = clic destro
	if _press_time > 0.0 and not _long_press_done:
		_press_time += delta
		if _press_time >= LONG_PRESS_SECONDS:
			_long_press_done = true
			dragging = false
			drag_path.clear()
			traj_layer.clear_preview()
			_on_right_click(_press_hex)
			_refresh()


# --------------------------------------------------------------------- input --

func _unhandled_input(event: InputEvent) -> void:
	if _battle_view != null:
		return
	# durante un pinch il mouse emulato dal primo dito va ignorato, altrimenti
	# si disegnerebbe una Traiettoria mentre si zooma
	if cam.multitouch_active():
		if dragging:
			dragging = false
			drag_path.clear()
			traj_layer.clear_preview()
		_press_time = 0.0
		return
	if event is InputEventMouseMotion:
		var w := cam.world_from_screen((event as InputEventMouseMotion).position)
		var h := graph.pixel_to_hex(w)
		board.set_hover(h if graph.has_hex(h) else Vector2i.MAX)
		if h != _press_hex:
			_press_time = 0.0        # il dito si e' spostato: non e' piu' un tocco lungo
		if dragging:
			_extend_drag(h)
		else:
			_update_preview(h)
		_refresh()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var w := cam.world_from_screen(mb.position)
		var h := graph.pixel_to_hex(w)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_hex = h
				_press_shift = mb.shift_pressed
				_press_time = 0.0001
				_long_press_done = false
				_begin_drag(h)
			else:
				_press_time = 0.0
				if _long_press_done:
					_long_press_done = false
					get_viewport().set_input_as_handled()
					return
				# un trascinamento senza percorso e' un clic: si comporta come
				# prima (seleziona una TF, oppure estende di un esagono)
				if drag_path.is_empty():
					dragging = false
					traj_layer.clear_preview()
					_on_left_click(_press_hex, _press_shift)
				else:
					_finish_drag()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_right_click(h)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		# durante una Battaglia i tasti li gestisce la sua vista
		if _battle_view != null:
			if _battle_view.handle_key(event as InputEventKey):
				get_viewport().set_input_as_handled()
			return
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
			_toggle_editor()
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
		KEY_0:
			# scorciatoia: apre una Battaglia fra la TF selezionata e la piu'
			# vicina avversaria, senza passare da un'azione. Serve a provare la
			# Mappa di Battaglia senza dipendere dal tiro di dadi.
			if selected_tf != null:
				var en := _nearest_enemy(selected_tf)
				if en != null:
					var t := selected_tf.trajectory
					_open_battle(Results.Battle.FULL, selected_tf, en,
						t.station_hex if t.is_station() else t.end_hex(0))
		KEY_F1:
			_toggle_help()
		KEY_HOME:
			_focus_selected()
	_refresh()


## Dichiara un'azione. Le designazioni contano: la TF Coordinatrice e quella di
## Supporto Aereo entrano nel Totale Traiettoria (RB p.17), quindi le sceglie il
## giocatore. Le domande si saltano quando non c'e' nulla da scegliere.
func _declare_action(key: String) -> void:
	var why := _action_unavailable_reason(key)
	if why != "":
		_msg("%s: %s" % [String(engine.action(key).get("label", key)), why])
		return

	var enemies := state.forces_of(1 - selected_tf.side)
	var target := await _pick_tf(enemies, "Task Force Bersaglio",
		"Contro chi dichiari l'azione?", false)
	if target == null:
		return

	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = selected_tf
	dec.target = target
	var t := target.trajectory
	dec.target_hex = t.station_hex if t.is_station() else t.end_hex(0)

	# Coordinatrice: una propria TF diversa dall'Attiva
	var own: Array[TaskForce] = []
	for tf in state.forces_of(selected_tf.side):
		if tf != selected_tf:
			own.append(tf)
	if not own.is_empty():
		dec.active_coordinating = await _pick_tf(own, "TF Coordinatrice",
			"Designa una Task Force Coordinatrice? La sua lunghezza puo' "
			+ "sostituire quella della TF Attiva nel Totale Traiettoria.", true)

	# Supporto Aereo: serve una portaerei a bordo
	var carriers: Array[TaskForce] = []
	for tf in own:
		for sh in tf.ships:
			if sh.type_code == "CV" and not sh.sunk:
				carriers.append(tf)
				break
	if not carriers.is_empty():
		dec.active_air_support = await _pick_tf(carriers, "TF Supporto Aereo",
			"Designa una Task Force di Supporto Aereo? Deve avere una "
			+ "portaerei.", true)

	var res := engine.resolve(dec, state)
	var label := String(engine.action(key).get("label", key))
	if not res["ok"]:
		_msg("%s: %s" % [label, res["error"]])
		return
	_msg("%s -> %s" % [label, engine.describe(res)])

	var pending_battle := Results.Battle.NONE
	for code_v: Variant in res["results"] as Array:
		var applied := Results.apply(String(code_v), selected_tf, target,
			dec.target_hex, state, _ship_chooser)
		_msg("    %s" % applied["text"])
		if applied["battle"] != Results.Battle.NONE:
			pending_battle = applied["battle"]
	log.record("%s (%s)" % [label, selected_tf.display_name()])
	state.changed.emit()
	if pending_battle != Results.Battle.NONE:
		_open_battle(pending_battle, selected_tf, target, dec.target_hex)
	_refresh()


## Chiede di scegliere una Task Force. Se ce n'e' una sola e non e' opzionale,
## non disturba il giocatore. Ritorna null se annullato o "nessuna".
func _pick_tf(candidates: Array[TaskForce], title: String, desc: String,
		optional: bool) -> TaskForce:
	if candidates.is_empty():
		return null
	if candidates.size() == 1 and not optional:
		return candidates[0]
	var options: Array = []
	for tf in candidates:
		var tj := tf.trajectory
		var kind := "Stazione" if tj.is_station() else "%d segmenti" % tj.length()
		var ships: Array[String] = []
		for sh in tf.ships:
			ships.append(sh.display())
		options.append({"label": "%s  (%s)" % [tf.display_name(), kind],
			"detail": ", ".join(ships) if not ships.is_empty() else "nessuna nave elencata"})
	if optional:
		options.append({"label": "Nessuna", "detail": ""})
	var i: int = await Choice.ask(self, title, desc, options, not optional)
	if i < 0:
		return null
	if optional and i == candidates.size():
		return null
	return candidates[i]


## Apre la Mappa di Battaglia. RB p.55: le TF Coordinatrici e di Supporto Aereo
## non partecipano, quindi entrano solo la TF Attiva e quella Bersaglio.
func _open_battle(kind_result: int, active: TaskForce, target: TaskForce,
		hex: Vector2i) -> void:
	var kind := BattleState.Kind.BATTLE
	if kind_result == Results.Battle.SURPRISE:
		kind = BattleState.Kind.SURPRISE
	elif kind_result == Results.Battle.LIMITED:
		kind = BattleState.Kind.LIMITED

	if active.afloat_ships().is_empty() or target.afloat_ships().is_empty():
		_msg("Battaglia non aperta: una delle due Task Force non ha navi "
			+ "(lo scenario non ne elenca).")
		return

	var bstate := BattleState.new(kind, state.weather)
	bstate.active_tf = active
	bstate.target_tf = target
	bstate.hex = hex
	var b := Battle.new(bstate, state.rng)
	b.start()

	_battle_layer = CanvasLayer.new()
	_battle_layer.layer = 20
	add_child(_battle_layer)
	_battle_view = BattleView.new()
	_battle_layer.add_child(_battle_view)
	_battle_view.setup(b)
	_battle_view.closed.connect(_close_battle.bind(b))
	_msg("%s aperta in %s." % [BattleState.KIND_LABELS[kind], str(hex)])


func _close_battle(b: Battle) -> void:
	var out := b.finish()
	for t_v: Variant in (out["sunk"] as Array):
		_msg("  affondata: %s" % String(t_v))
	_msg("Battaglia conclusa: %s" % b.state.end_reason)
	if _battle_layer != null:
		_battle_layer.queue_free()
		_battle_layer = null
		_battle_view = null
	log.record("Battaglia in %s" % str(b.state.hex))
	state.changed.emit()
	_refresh()


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


## Inizia un trascinamento se il punto premuto e' una TF selezionabile o un
## capo della Traiettoria gia' selezionata.
func _begin_drag(h: Vector2i) -> void:
	if mode != Mode.PLAY or selected_tf == null:
		return
	var t := selected_tf.trajectory
	var on_own := t.occupies(h)
	if not on_own and not _can_extend_to(h):
		return
	dragging = true
	drag_path.clear()
	# si estende dal capo piu' vicino al punto premuto
	if t.is_station():
		drag_end = 1
	else:
		var d0 := graph.center_of(t.end_hex(0)).distance_to(graph.center_of(h))
		var d1 := graph.center_of(t.end_hex(1)).distance_to(graph.center_of(h))
		drag_end = 0 if d0 <= d1 else 1


## Aggiunge un esagono al percorso in anteprima, se e' una prosecuzione legale.
func _extend_drag(h: Vector2i) -> void:
	if not dragging or selected_tf == null:
		return
	if not drag_path.is_empty() and drag_path[-1] == h:
		return
	# tornare indietro sull'ultimo esagono annulla quel passo
	if drag_path.size() >= 2 and drag_path[drag_path.size() - 2] == h:
		drag_path.remove_at(drag_path.size() - 1)
		_show_drag_preview(true)
		return
	if not _drag_step_legal(h):
		_show_drag_preview(false)
		return
	drag_path.append(h)
	_show_drag_preview(true)


## Un passo del trascinamento e' legale se lo sarebbe la corrispondente
## estensione, tenendo conto dei segmenti gia' accumulati in anteprima.
func _drag_step_legal(h: Vector2i) -> bool:
	var t := selected_tf.trajectory
	var from := drag_path[-1] if not drag_path.is_empty() else t.end_hex(drag_end)
	if drag_path.has(h) or t.occupies(h):
		return false
	if t.length() + drag_path.size() >= Trajectory.MAX_SEGMENTS:
		return false
	if state.port_hexes().has(h):
		return false
	return graph.is_adjacent_for(selected_tf.side, from, h)


func _show_drag_preview(valid: bool) -> void:
	var pts: Array[Vector2i] = []
	if selected_tf != null:
		pts.append(selected_tf.trajectory.end_hex(drag_end))
	pts.append_array(drag_path)
	traj_layer.set_preview(pts, valid)


## Al rilascio i segmenti accumulati diventano una mossa sola, annullabile in
## un colpo solo con Ctrl+Z.
func _finish_drag() -> void:
	if not dragging:
		return
	dragging = false
	if drag_path.is_empty() or selected_tf == null:
		traj_layer.clear_preview()
		return
	var t := selected_tf.trajectory
	var ports := state.port_hexes()
	var added := 0
	var infos := 0
	for h in drag_path:
		var info := state.triggers_info(h, selected_tf.side)
		if t.extend(h, drag_end, graph, ports, info, selected_tf.side):
			added += 1
			if info:
				infos += 1
		else:
			break
	drag_path.clear()
	traj_layer.clear_preview()
	if added > 0:
		var extra := "" if infos == 0 else "  -> %d segnalino/i INFORMAZIONI" % infos
		_msg("%s estesa di %d segmenti (ora %d)%s"
			% [selected_tf.display_name(), added, t.length(), extra])
		log.record("estensione di %d segmenti (%s)"
			% [added, selected_tf.display_name()])
		state.changed.emit()
	_refresh()


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

	# RB p.19-20: la scelta e' del proprietario della Traiettoria, e conta:
	# invocare il Limite di Informazioni toglie un segnalino ma rimuove meno
	# segmenti. La decide il giocatore, non il codice.
	var chosen: Dictionary = opts[0]
	if opts.size() > 1:
		var options: Array = []
		for o in opts:
			var detail := "%d segmenti" % int(o["total"])
			if o["uses_intel_limit"]:
				detail += "  -  rimuove un segnalino INFORMAZIONI (Limite di Informazioni)"
			options.append({"label": String(o["label"]), "detail": detail})
		var desc := ("Velocita' [b]%s[/b], meteo [b]%s[/b]: lo Scorrere del Tempo "
			+ "chiede di rimuovere [b]%d[/b] segmenti.\n"
			+ "I segmenti si tolgono solo dai capi.") % [
				TimeLapse.SPEED_LABELS[selected_tf.speed],
				"cattivo" if state.weather == 1 else "buono", amount]
		var i: int = await Choice.ask(self, "Scorrere del Tempo - %s"
			% selected_tf.display_name(), desc, options)
		if i < 0:
			_msg("Scorrere del Tempo annullato")
			return
		chosen = opts[i]

	var freed := TimeLapse.apply(traj, chosen)
	var note := ""
	if traj.length() == 0 and not freed.is_empty():
		# RB p.14: la Stazione va in UNO QUALSIASI degli esagoni appena liberati
		var hex_choice := freed[0]
		if freed.size() > 1:
			var opts2: Array = []
			for h in freed:
				opts2.append({"label": "Esagono %s" % str(h), "detail": ""})
			var j: int = await Choice.ask(self, "Dove poni la Stazione?",
				"La Traiettoria ha esaurito i segmenti. La Stazione puo' andare "
				+ "in uno qualsiasi degli esagoni appena liberati.", opts2, false)
			if j >= 0:
				hex_choice = freed[j]
		traj.become_station(hex_choice)
		note = " -> diventa Stazione in %s" % str(hex_choice)
	_msg("Scorrere del Tempo (%s, meteo %s): richiesti %d, %s%s"
		% [TimeLapse.SPEED_LABELS[selected_tf.speed],
			"cattivo" if state.weather == 1 else "buono",
			amount, chosen["label"], note])
	log.record("Scorrere del Tempo (%s)" % selected_tf.display_name())
	state.changed.emit()
	_refresh()


## Scelta della nave bersaglio quando una regola la lascia al giocatore.
## Passata a Results.apply come Callable: il core non sa che esiste una UI.
func _ship_chooser(candidates: Array, reason: String) -> Variant:
	# le scelte non-nave (quale troncone eliminare) passano un elenco vuoto
	if candidates.is_empty():
		return null
	var options: Array = []
	for c_v: Variant in candidates:
		var sh: Ship = c_v
		options.append({"label": sh.display(),
			"detail": "Difesa %d, Colpi %d, %s" % [
				sh.defense_damaged if sh.damaged else sh.defense, sh.hits,
				TimeLapse.SPEED_LABELS[sh.current_speed()]]})
	var i: int = await Choice.ask(self, "Scegli la nave", reason, options, false)
	return candidates[i] if i >= 0 else candidates[0]


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
var _bar: ActionBar
var _battle_layer: CanvasLayer
var _battle_view: BattleView


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
	panel.position = Vector2(12, 62)     # sotto la barra dei comandi
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

	_build_action_bar(hud)
	_build_briefing(hud)
	_build_help(hud)


## Sfondo scuro semitrasparente: senza, il testo bianco sull'azzurro della
## mappa e' semplicemente illeggibile.
## Motivo per cui un'azione non e' dichiarabile ora (stringa vuota = si puo').
func _action_unavailable_reason(key: String) -> String:
	if mode == Mode.EDITOR:
		return "sei in modalita' editor del grafo"
	if selected_tf == null:
		return "nessuna Task Force selezionata"
	if _nearest_enemy(selected_tf) == null:
		return "nessuna Task Force avversaria in gioco"
	if not engine.is_verified(key):
		return String(engine.action(key).get("verified_note",
			"tabella non ancora trascritta"))
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = selected_tf
	dec.target = _nearest_enemy(selected_tf)
	return engine.legality_error(dec, state)


func _refresh_action_bar() -> void:
	if _bar == null:
		return
	var reasons := {}
	for a in ActionBar.ACTIONS:
		reasons[a[0]] = _action_unavailable_reason(String(a[0]))
	_bar.update_state(reasons, log != null and log.can_undo(),
		log != null and log.can_redo())


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
func _build_action_bar(root: Control) -> void:
	_bar = ActionBar.new()
	# barra a tutta larghezza in alto, come una toolbar: cosi' non deborda
	# quando la finestra e' stretta e resta sempre nello stesso posto
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_left = 10
	_bar.offset_right = -10
	_bar.offset_top = 8
	root.add_child(_bar)
	_bar.action_requested.connect(_declare_action)
	_bar.time_lapse_requested.connect(_do_time_lapse)
	_bar.undo_requested.connect(func() -> void:
		if log.undo():
			_msg("annullato")
		_resync_selection()
		_refresh())
	_bar.redo_requested.connect(func() -> void:
		if log.redo():
			_msg("ripristinato")
		_resync_selection()
		_refresh())
	_bar.briefing_toggled.connect(func() -> void:
		_briefing_panel.visible = not _briefing_panel.visible)
	_bar.help_toggled.connect(_toggle_help)
	_bar.scenario_step.connect(func(d: int) -> void:
		_load_scenario_at(scenario_index + d))
	_bar.grid_cycled.connect(func() -> void:
		board.set_grid_mode((board.grid_mode + 1) % 4))
	_bar.editor_toggled.connect(_toggle_editor)
	_bar.menu_requested.connect(func() -> void:
		get_tree().change_scene_to_file("res://ui/splash/splash.tscn"))


func _toggle_editor() -> void:
	mode = Mode.EDITOR if mode == Mode.PLAY else Mode.PLAY
	board.set_grid_mode(MapBoard.GridMode.EDITOR if mode == Mode.EDITOR
		else MapBoard.GridMode.SUBTLE)
	edit_anchor = Vector2i.MAX
	_msg("modalita': %s" % ("EDITOR del grafo" if mode == Mode.EDITOR else "gioco"))
	_refresh()


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
	_help.position = Vector2(-360, -300)
	_help.visible = false
	_help.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_help)
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.custom_minimum_size = Vector2(700, 600)
	t.scroll_active = true
	t.text = """[b]Atlantic Chase - comandi[/b]

[b]Mappa[/b]
  trascina col tasto centrale, oppure WASD    sposta la vista
  rotella                                     zoom sul cursore
  Home                                        centra sulla TF selezionata

[b]Traiettorie[/b]
  clic su una Task Force                      seleziona
  [b]trascina dalla TF sugli esagoni[/b]             disegna la rotta in un gesto solo
  clic su un esagono adiacente                estende di un esagono
  clic destro                                 rimuove un segmento dal capo piu' vicino
  Tab / Shift+Tab                             TF successiva / precedente
  F                                           cambia capo attivo (testa/coda)

[b]Azioni[/b]  (anche dai pulsanti in alto)
  1  Ingaggiare      2  Ricerca Navale
  3  Attacco Aereo   4  Attacco Furtivo
  T   Scorrere del Tempo sulla TF selezionata
  0   apre una Battaglia di prova
  Ctrl+W  alterna meteo buono/cattivo
  Ctrl+Z / Ctrl+Shift+Z   annulla / ripristina

[b]In Battaglia[/b]
  SPAZIO                     risolve la fase corrente
  [b]trascina una nave[/b]          la muove di una zona
  S                          crea o toglie il Fumo
  F / G                      tenta la Fuga (Attivo / Bersaglio)
  ESC                        torna alla mappa

[b]Touch (iPad)[/b]
  due dita             sposta la mappa e zooma (pinch)
  un dito              seleziona e disegna la Traiettoria
  tocco prolungato     come il clic destro: rimuove un segmento

[b]Scenario e vista[/b]
  [ e ]        scenario precedente / successivo
  B            briefing        G   visibilita' del reticolo
  E            editor del grafo (Ctrl+S salva)
  F1           chiude questo pannello"""
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
	_refresh_action_bar()
	var sc := scenario.title if scenario != null else "-"
	_lbl_title.text = "%s   [%s]" % [sc, "EDITOR" if mode == Mode.EDITOR else "gioco"]

	var lines: Array[String] = []
	lines.append("Meteo: [b]%s[/b]    Iniziativa: [b]%s[/b]"
		% ["cattivo" if state.weather == 1 else "buono",
			"Kriegsmarine" if state.initiative == 0 else "Royal Navy"])
	# %s e non %d: i VP possono valere mezzo punto (un incrociatore britannico
	# affondato ne vale 0,5 in cinque scenari su nove)
	lines.append("Punti Vittoria - KM [b]%s[/b]   RN [b]%s[/b]"
		% [state.vp_text(TaskForce.Side.KRIEGSMARINE),
			state.vp_text(TaskForce.Side.ROYAL_NAVY)])
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
