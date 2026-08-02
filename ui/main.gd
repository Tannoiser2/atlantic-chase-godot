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

## Tabella dei Punti Vittoria dello scenario in corso, e chi ci porta gli
## eventi. Restano null finche' lo scenario non ha una tabella trascritta: in
## quel caso si gioca lo stesso, semplicemente nessuno segna punti.
var victory: Victory = null
var vp_tracker: VictoryTracker = null

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
	# apply_dict riparte dal dizionario dello scenario, che non sa nulla delle
	# Regole Avanzate: la scelta va rimessa dopo, se no cambiare scenario la
	# perde in silenzio.
	state.advanced_battle = Session.advanced_battle
	selected_tf = state.task_forces[0] if not state.task_forces.is_empty() else null
	traj_layer.selected_tf_id = selected_tf.id if selected_tf else -1
	log = CommandLog.new(state)
	victory = Victory.from_scenario(scenario)
	vp_tracker = VictoryTracker.new(victory, state)
	_msg("Scenario: %s  -  %d Task Force, %d navi"
		% [scenario.title, state.task_forces.size(), scenario.ship_count()])
	if scenario.has_import_warnings():
		for w_v: Variant in scenario.import_warnings:
			_msg("  [avviso di import] %s" % String(w_v))
	_update_briefing()
	_focus_selected()
	_refresh()
	if scenario.is_battle_scenario():
		_open_scenario_battle()


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
	# Durante una Battaglia i tasti li gestisce la sua vista, e vanno passati
	# PRIMA di tutto il resto: c'era un `return` secco qui sopra che tagliava
	# fuori anche il blocco della tastiera piu' in basso, e la Battaglia
	# restava sorda a SPAZIO. Si apriva e non andava piu' avanti.
	if _battle_view != null:
		if event is InputEventKey and (event as InputEventKey).pressed \
				and not (event as InputEventKey).echo:
			if _battle_view.handle_key(event as InputEventKey):
				get_viewport().set_input_as_handled()
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
		KEY_5:
			_declare_action("TRAJECTORY")
		KEY_6:
			_declare_action("COMPLETION")
		KEY_7:
			_declare_action("PASS")
		KEY_8:
			_declare_action("REORGANIZE")
		KEY_9:
			_declare_action("SIGNAL")
		KEY_D:
			await _do_disperse()
		KEY_S:
			if k.ctrl_pressed or k.meta_pressed:
				await _do_save()
			else:
				await _do_load()
		KEY_V:
			_show_outcome()
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

	# Azioni che non si risolvono su una tabella e non hanno un bersaglio:
	# hanno una procedura loro e prendono strade separate.
	match key:
		"COMPLETION":
			await _do_completion()
			return
		"PASS":
			await _do_pass()
			return
		"REORGANIZE":
			await _do_reorganize()
			return
		"SIGNAL":
			await _do_signal()
			return
		"TRAJECTORY":
			_msg("Traiettoria: trascina dalla Task Force selezionata per "
				+ "disegnare la rotta, oppure clicca un esagono adiacente a "
				+ "un capo. Il tasto destro toglie l'ultimo segmento.")
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
	_show_battle(bstate)


## I dodici mini-scenari partono direttamente qui: sono Battaglie gia'
## schierate, senza una fase sulla mappa operazionale che le preceda.
func _open_scenario_battle() -> void:
	var bstate := scenario.make_battle_state(state.weather)
	if bstate == null:
		return
	_msg("%s: Battaglia gia' schierata (%d navi contro %d)."
		% [scenario.title, bstate.active_tf.ships.size(),
			bstate.target_tf.ships.size()])
	_show_battle(bstate)


func _show_battle(bstate: BattleState) -> void:
	# Va deciso PRIMA di start(): la Verifica Snafu si tira una volta sola,
	# prima del Round Uno, e con le regole base non si tira affatto.
	bstate.advanced = state.advanced_battle
	var b := Battle.new(bstate, state.rng, vp_tracker)
	b.start()

	_battle_layer = CanvasLayer.new()
	_battle_layer.layer = 20
	add_child(_battle_layer)
	_battle_view = BattleView.new()
	_battle_layer.add_child(_battle_view)
	_battle_view.setup(b)
	_battle_view.closed.connect(_close_battle.bind(b))
	var where := " in %s" % str(bstate.hex) if bstate.hex != Vector2i.ZERO else ""
	_msg("%s aperta%s." % [BattleState.KIND_LABELS[bstate.kind], where])


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

# --------------------------------------------------------- salva / ricarica --

func _do_save() -> void:
	if scenario == null:
		return
	var slot := "%s - round %d" % [scenario.id, state.round_number]
	var r := SaveGame.save(state, scenario.id, scenario.title, slot)
	if not bool(r["ok"]):
		_msg("Salvataggio: %s" % String(r["error"]))
		return
	_msg("Partita salvata come \"%s\"." % slot)


func _do_load() -> void:
	var saves := SaveGame.list_saves()
	if saves.is_empty():
		_msg("Nessuna partita salvata. Ctrl+S per salvare.")
		return
	var opts: Array = []
	for sv in saves:
		opts.append({"label": String(sv["name"]),
			"detail": "%s  -  round %d  -  %s" % [String(sv["scenario"]),
				int(sv["round"]), String(sv["saved_at"])]})
	opts.append({"label": "Annulla", "detail": ""})
	var i: int = await Choice.ask(self, "Riprendere una partita",
		"Il salvataggio contiene anche lo stato dei dadi: ricaricare "
		+ "restituisce la stessa partita, non una simile.", opts)
	if i < 0 or i >= saves.size():
		return
	var doc := SaveGame.read(String(saves[i]["path"]))
	if not bool(doc["ok"]):
		_msg("Ricarica: %s" % String(doc["error"]))
		return
	# prima si carica lo SCENARIO giusto, poi ci si applica sopra lo stato: se
	# no si applicherebbe una partita a una mappa che non e' la sua
	var idx := scenario_ids.find(String(doc["scenario"]))
	if idx < 0:
		_msg("Ricarica: lo scenario \"%s\" non esiste piu'." % String(doc["scenario"]))
		return
	_load_scenario_at(idx)
	state.apply_dict(doc["state"])
	log = CommandLog.new(state)
	_resync_selection()
	_msg("Partita ripresa: %s, round %d." % [scenario.title, state.round_number])
	_focus_selected()
	_refresh()


## Esito della partita, con le righe che il motore non puo' valutare da solo.
func _show_outcome() -> void:
	if victory == null:
		return
	_msg("--- ESITO ---")
	for line in victory.describe(state).split("\n"):
		_msg(line)
	var late := Endgame.notice(state, scenario.rules() if scenario != null
		else {}, graph, _port_control())
	if late != "":
		_msg(late)


## Dispersione di un Convoglio (RB p.11). Non e' un'azione: e' una scelta che
## il proprietario fa quando ha l'Iniziativa, e non si puo' disfare.
func _do_disperse() -> void:
	if scenario == null:
		return
	var allowed := scenario.convoy_dispersal_allowed()
	var pool: Array[Ship] = []
	for tf in state.forces_of(state.initiative):
		for c in Convoy.convoys_in(tf):
			if not c.dispersed:
				pool.append(c)
	if pool.is_empty():
		_msg("Dispersione: nessun Convoglio da disperdere fra le Task Force "
			+ "di chi ha l'Iniziativa.")
		return
	if not allowed:
		_msg("Dispersione: le istruzioni di questo scenario non la "
			+ "consentono (o non sono ancora trascritte).")
		return
	var opts: Array = []
	for c in pool:
		opts.append({"label": c.name,
			"detail": "da disperso incassa un solo Colpo per attacco, "
				+ "ma vale un punto in meno se arriva"})
	opts.append({"label": "Annulla", "detail": ""})
	var i: int = await Choice.ask(self, "Disperdere un Convoglio",
		"La scelta non si puo' disfare: un Convoglio disperso resta disperso "
		+ "per tutto lo scenario.", opts)
	if i < 0 or i >= pool.size():
		return
	_report(Convoy.disperse(pool[i], allowed))


## Riorganizzazione (RB p.37). Con una sola dichiarazione si possono fare piu'
## cose, quindi il menu resta aperto finche' il giocatore non chiude - o finche'
## un tentativo di Rinforzo fallisce, che chiude l'azione e passa l'Iniziativa.
func _do_reorganize() -> void:
	while true:
		var opts: Array = [
			{"label": "Dividere una Task Force",
				"detail": Reorganize.split_refusal(state, selected_tf)},
			{"label": "Unire due Task Force",
				"detail": "servono due Stazioni nello stesso esagono"},
			{"label": "Tentativo di Rinforzo",
				"detail": "2d6, riesce con 7 o piu'; se fallisce l'Iniziativa passa"},
			{"label": "Chiudi la Riorganizzazione", "detail": ""},
		]
		var i: int = await Choice.ask(self, "Riorganizzazione - %s"
			% selected_tf.display_name(),
			"Caselle libere: [b]%d[/b] su %d." % [
				Reorganize.free_slots(state, selected_tf.side),
				Reorganize.max_task_forces(selected_tf.side)], opts)
		match i:
			0:
				await _reorg_split()
			1:
				await _reorg_merge()
			2:
				if await _reorg_reinforce():
					return       # fallito: l'azione finisce qui
			_:
				_msg("Riorganizzazione conclusa.")
				return
		_refresh()


func _reorg_split() -> void:
	var why := Reorganize.split_refusal(state, selected_tf)
	if why != "":
		_msg("Dividere: %s" % why)
		return
	# si sceglie una nave alla volta: e' il gesto del gioco da tavolo, dove le
	# pedine si spostano una per una da una casella all'altra
	var moving: Array[Ship] = []
	while true:
		var opts: Array = []
		var pool: Array[Ship] = []
		for s in selected_tf.ships:
			if not moving.has(s):
				pool.append(s)
				opts.append({"label": s.display(), "detail": ""})
		opts.append({"label": "Fatto (%d navi scelte)" % moving.size(),
			"detail": "almeno una nave deve restare in ciascuna Task Force"})
		var i: int = await Choice.ask(self, "Dividere - quali navi partono?",
			"Scelte finora: %s" % ("nessuna" if moving.is_empty()
				else ", ".join(_ship_names(moving))), opts)
		if i < 0 or i >= pool.size():
			break
		moving.append(pool[i])
	if moving.is_empty():
		_msg("Dividere annullato.")
		return

	var contact_to_new := false
	if selected_tf.trajectory.station_contact:
		contact_to_new = 1 == await Choice.ask(self, "Segnalino Contatto",
			"Dividere non genera nuovi segnalini: il Contatto resta a una "
			+ "sola delle due Task Force.",
			[{"label": "Resta a %s" % selected_tf.display_name(), "detail": ""},
				{"label": "Passa alla nuova Task Force", "detail": ""}])
	var evasive_to_new := false
	if selected_tf.evasive:
		evasive_to_new = 1 == await Choice.ask(self, "Manovre Evasive",
			"Anche le Manovre Evasive vanno a una sola delle due.",
			[{"label": "Restano a %s" % selected_tf.display_name(), "detail": ""},
				{"label": "Passano alla nuova", "detail": ""}])

	var r := Reorganize.split(state, selected_tf, moving, contact_to_new,
		evasive_to_new)
	_report(r)


func _reorg_merge() -> void:
	var here := selected_tf.trajectory
	if not here.is_station():
		_msg("Unire: %s e' una Traiettoria, non una Stazione." % selected_tf.display_name())
		return
	var others: Array[TaskForce] = []
	for tf in state.forces_of(selected_tf.side):
		if tf != selected_tf and Reorganize.merge_refusal(selected_tf, tf) == "":
			others.append(tf)
	if others.is_empty():
		_msg("Unire: nessun'altra Stazione in %s." % str(here.station_hex))
		return
	var other := await _pick_tf(others, "Unire - quale Task Force assorbire?",
		"Le sue navi passano a %s e la sua pedina torna disponibile."
			% selected_tf.display_name(), true)
	if other == null:
		return
	_report(Reorganize.merge(selected_tf, other))


## Ritorna true se il tentativo e' fallito e l'azione deve chiudersi.
func _reorg_reinforce() -> bool:
	var groups: Array = []
	var keys: Array[String] = []
	var mine := "KM" if selected_tf.side == TaskForce.Side.KRIEGSMARINE else "RN"
	for k_v: Variant in scenario.reinforcements.keys():
		var k := String(k_v)
		if not k.begins_with(mine):
			continue
		var ships: Array = scenario.reinforcements[k_v]
		if ships.is_empty():
			continue
		keys.append(k)
		groups.append({"label": k, "detail": ", ".join(ships)})
	if groups.is_empty():
		_msg("Rinforzi: nessun Gruppo disponibile per questa parte.")
		return false
	groups.append({"label": "Annulla", "detail": ""})
	var i: int = await Choice.ask(self, "Tentativo di Rinforzo",
		"2d6: con [b]7 o piu'[/b] le navi entrano in gioco. Se fallisce, una "
		+ "Task Force effettua lo Scorrere del Tempo e l'Iniziativa passa.",
		groups)
	if i < 0 or i >= keys.size():
		return false

	var port := _reinforcement_port(keys[i])
	if port == Vector2i.MAX:
		_msg("Rinforzi %s: il porto di questo Gruppo non e' trascritto. "
			% keys[i] + "E' stampato sulla mappa dello scenario nel "
			+ "fascicolo; va aggiunto a core/data/victory/. Meglio non "
			+ "farlo entrare che farlo entrare nel porto sbagliato.")
		return false
	var r := Reorganize.attempt_reinforcement(state, selected_tf.side, port,
		scenario.reinforcements[keys[i]], keys[i])
	_report(r)
	if not r["ok"]:
		return false
	if bool(r["initiative_passes"]):
		await _do_time_lapse()
		state.initiative = 1 - state.initiative
		state.initiative_count = 0
		_msg("L'Iniziativa passa a %s."
			% ("Kriegsmarine" if state.initiative == TaskForce.Side.KRIEGSMARINE
				else "Royal Navy"))
		return true
	if bool(r["success"]):
		scenario.reinforcements[keys[i]] = []
	return false


## Il porto di un Gruppo di Rinforzi. Il nome del gruppo non lo dice ("KM
## Reinforcement A"), quindi si guarda dove sta la Casella sul Display: e' il
## porto in cui il Gruppo e' stampato.
func _reinforcement_port(group: String) -> Vector2i:
	var meta: Dictionary = scenario.reinforcement_ports()
	if meta.has(group):
		return graph.port_hex(String(meta[group]))
	return Vector2i.MAX


func _ship_names(ships: Array[Ship]) -> Array[String]:
	var out: Array[String] = []
	for s in ships:
		out.append(s.name)
	return out


func _report(r: Dictionary) -> void:
	if not bool(r.get("ok", false)):
		_msg(String(r.get("error", "operazione non riuscita")))
		return
	for l_v: Variant in r.get("log", []):
		_msg(String(l_v))
	_resync_selection()
	_refresh()


## Segnalazione (RB p.39): una Traiettoria nemica con un segnalino Informazioni
## collassa in una Stazione.
func _do_signal() -> void:
	var cands := SignalAction.candidates(state, selected_tf.side)
	if cands.is_empty():
		_msg("Segnalazione: nessuna Traiettoria avversaria ha un segnalino "
			+ "Informazioni. Senza, non c'e' niente da segnalare.")
		return
	var target := await _pick_tf(cands, "Segnalazione - quale Task Force?",
		"Solo le Traiettorie con almeno un segnalino Informazioni.", false)
	if target == null:
		return

	var hexes := SignalAction.target_hexes(target)
	var at := hexes[0]
	if hexes.size() > 1:
		var opts: Array = []
		for h in hexes:
			opts.append({"label": str(h),
				"detail": "la Stazione finisce qui, il resto della Traiettoria sparisce"})
		var i: int = await Choice.ask(self, "Segnalazione - quale segnalino?",
			"Il bersaglio ha piu' di un segnalino Informazioni.", opts)
		if i < 0:
			return
		at = hexes[i]
	_report(SignalAction.resolve(target, at))
	_msg("Ora il giocatore Inattivo puo' tentare di Sottrarre l'Iniziativa.")


## Completamento (RB p.29): le navi entrano in porto e lasciano il gioco.
## Se la Task Force tocca piu' di un porto amico, la scelta e' del giocatore.
func _do_completion() -> void:
	var opts := Completion.port_options(selected_tf, graph, _port_control())
	if opts.is_empty():
		_msg("Completamento: nessun porto amico raggiunto")
		return

	var chosen: Dictionary = opts[0]
	if opts.size() > 1:
		var choices: Array = []
		for o in opts:
			choices.append({"label": String(o["name"]),
				"detail": "in %s" % String(o["country"])})
		var i: int = await Choice.ask(self, "Completamento - %s"
			% selected_tf.display_name(),
			"La Task Force tocca piu' di un porto amico. In quale entra?",
			choices)
		if i < 0:
			_msg("Completamento annullato")
			return
		chosen = opts[i]

	var ships := selected_tf.ships.size()
	var res := Completion.resolve(selected_tf, chosen, vp_tracker)
	if not res["ok"]:
		_msg("Completamento: %s" % String(res["error"]))
		return
	for line_v: Variant in res["log"]:
		_msg(String(line_v))
	_msg("%d navi in porto a %s." % [ships, String(chosen["name"])])
	_resync_selection()
	_refresh()


## Passare (RB p.35): si designa una propria Traiettoria che effettua lo
## Scorrere del Tempo, poi l'Iniziativa passa all'avversario e il conteggio
## torna a zero. E' l'unica azione che si dichiara per cedere il turno.
func _do_pass() -> void:
	if not selected_tf.trajectory.is_station():
		await _do_time_lapse()
	else:
		_msg("%s e' gia' una Stazione: nessuno Scorrere del Tempo."
			% selected_tf.display_name())
	state.initiative = 1 - state.initiative
	state.initiative_count = 0
	_msg("Passo. L'Iniziativa passa a %s; il conteggio torna a zero."
		% ("Kriegsmarine" if state.initiative == TaskForce.Side.KRIEGSMARINE
			else "Royal Navy"))
	_refresh()


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
				TimeLapse.speed_label(selected_tf.speed),
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
		% [TimeLapse.speed_label(selected_tf.speed),
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
				TimeLapse.speed_label(sh.current_speed())]})
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

## Pannello "ora tocca a": chi sta agendo, cosa aspetta il gioco, e cosa NON si
## puo' fare con il motivo accanto.
var _lbl_now: RichTextLabel
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

	# Pannello "ora tocca a": sta in basso a destra, sopra il registro.
	#
	# Nasce da una critica precisa all'interfaccia: i motivi per cui un'azione
	# non si puo' dichiarare c'erano gia', ma uno alla volta, nel tooltip di
	# ogni pulsante. Per sapere perche' sei azioni su nove erano spente
	# bisognava passare il mouse su sei pulsanti, uno dopo l'altro. Qui si
	# vedono insieme, RAGGRUPPATE PER MOTIVO: quasi sempre e' un motivo solo che
	# ne blocca quattro, e detto cosi' si capisce cosa fare.
	var nowpanel := PanelContainer.new()
	nowpanel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	nowpanel.offset_left = -600
	nowpanel.offset_right = -12
	nowpanel.offset_top = -430
	nowpanel.offset_bottom = -178
	nowpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nowpanel.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(nowpanel)
	_lbl_now = RichTextLabel.new()
	_lbl_now.bbcode_enabled = true
	# un punto piu' piccolo del resto: e' un pannello di servizio, non deve
	# rubare l'occhio alla mappa
	_lbl_now.add_theme_font_size_override("normal_font_size", 14)
	_lbl_now.add_theme_font_size_override("bold_font_size", 14)
	_lbl_now.add_theme_font_size_override("italics_font_size", 14)
	_lbl_now.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nowpanel.add_child(_lbl_now)

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
	# Passare, Completamento e Traiettoria si dichiarano anche senza nemici in
	# vista: pretendere un bersaglio le renderebbe indichiarabili
	if ActionBar.needs_enemy(key) and _nearest_enemy(selected_tf) == null:
		return "nessuna Task Force avversaria in gioco"
	if not engine.is_verified(key):
		return String(engine.action(key).get("verified_note",
			"tabella non ancora trascritta"))
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = selected_tf
	dec.target = _nearest_enemy(selected_tf)
	var err := engine.legality_error(dec, state)
	if err != "":
		return err
	# il Completamento ha condizioni sue, che stanno nella regola e non nella
	# tabella: porto amico raggiunto, non piu' di 6 segmenti (RB p.29)
	if key == "COMPLETION":
		return Completion.refusal(selected_tf, graph, _port_control())
	var late := Endgame.action_refusal(state, scenario.rules() if scenario != null
		else {}, selected_tf.side, key)
	if late != "":
		return late
	return ""


## Il pannello "ora tocca a".
##
## Tre domande, in quest'ordine, che sono quelle che si fa chi guarda lo
## schermo senza sapere cosa succede:
##
##   chi sta agendo?      il lato della Task Force selezionata - qui non c'e'
##                        un turno imposto, agisce chi si seleziona
##   cosa aspetta il gioco?   una frase, quella giusta per la situazione
##   cosa non posso fare, e perche'?
##
## L'ultima e' la ragione per cui questo pannello esiste. I motivi c'erano gia'
## tutti, ma nel tooltip di ogni pulsante, uno alla volta.
func _refresh_now() -> void:
	if _lbl_now == null:
		return
	var out: Array[String] = []

	if mode == Mode.EDITOR:
		_lbl_now.text = ("[b]EDITOR DEL GRAFO[/b]\nSi modifica la mappa, non si "
			+ "gioca. E per tornare alla partita.")
		return

	if selected_tf == null:
		_lbl_now.text = ("[b]Ora tocca a...[/b]  nessuno\n"
			+ "[color=#ffd27f]Clicca una Task Force sulla mappa.[/color] "
			+ "Finche' non ne scegli una, nessuna azione e' dichiarabile: "
			+ "in Atlantic Chase si dichiara sempre PER una forza.")
		return

	var side_name := "Kriegsmarine" if selected_tf.side \
		== TaskForce.Side.KRIEGSMARINE else "Royal Navy"
	var has_init := state.initiative == selected_tf.side
	out.append("[b]Ora tocca a...[/b]  [b]%s[/b] - %s%s"
		% [side_name, selected_tf.display_name(),
			"   [color=#8fd0ff](ha l'Iniziativa)[/color]" if has_init else ""])

	# che cosa aspetta il gioco, adesso
	var t := selected_tf.trajectory
	if t.is_station():
		out.append("E' una [b]Stazione[/b]: trascina da qui a un esagono "
			+ "adiacente per cominciare una Traiettoria, o dichiara un'azione.")
	elif t.length() >= Trajectory.MAX_SEGMENTS:
		out.append("Traiettoria al massimo (%d segmenti): per allungarla serve "
			% Trajectory.MAX_SEGMENTS
			+ "prima uno [b]Scorrere del Tempo[/b] (T).")
	else:
		out.append("Traiettoria di [b]%d[/b] segmenti, capo attivo [b]%s[/b]: "
			% [t.length(), "testa" if active_end == 0 else "coda"]
			+ "trascina dal capo per allungarla. TAB cambia capo.")

	# le azioni, divise in due e i motivi raggruppati
	var ok_names: Array[String] = []
	var by_reason: Dictionary = {}
	for a in ActionBar.ACTIONS:
		var key := String(a[0])
		var label := String(a[1])
		var why := _action_unavailable_reason(key)
		if why == "":
			ok_names.append("%s (%s)" % [label, String(a[2])])
		else:
			if not by_reason.has(why):
				by_reason[why] = []
			(by_reason[why] as Array).append(label)

	out.append("")
	if ok_names.is_empty():
		out.append("[color=#ff9a3c][b]Nessuna azione dichiarabile.[/b][/color]")
	else:
		out.append("[b]Puoi dichiarare:[/b] [color=#a8e6a1]%s[/color]"
			% ", ".join(ok_names))
	for why_v: Variant in by_reason.keys():
		out.append("[color=#c8b8a0]%s[/color] - [i]%s[/i]"
			% [", ".join(by_reason[why_v] as Array), String(why_v)])

	_lbl_now.text = "\n".join(out)


## Chi controlla i porti nello scenario in corso.
func _port_control() -> Dictionary:
	return scenario.port_control() if scenario != null else {}


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
	_bar.disperse_requested.connect(_do_disperse)
	_bar.outcome_requested.connect(_show_outcome)
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
	lines.append("Punti Vittoria - KM [b]%s[/b]   RN [b]%s[/b]%s"
		% [state.vp_text(TaskForce.Side.KRIEGSMARINE),
			state.vp_text(TaskForce.Side.ROYAL_NAVY),
			"    Convogli arrivati: [b]%d[/b]" % state.convoys_completed
				if state.convoys_completed > 0 else ""])
	# Il finale di partita cambia le regole, e va detto: da tre Convogli in
	# avanti al tedesco restano quattro azioni e l'obbligo di rientrare.
	var late := Endgame.notice(state, scenario.rules() if scenario != null
		else {}, graph, _port_control())
	if late != "":
		lines.append("[color=#ff9a3c]%s[/color]" % late)
	if selected_tf != null:
		var t := selected_tf.trajectory
		var kind := "Stazione" if t.is_station() else "Traiettoria"
		lines.append("")
		lines.append("[b]%s[/b]  (%s)" % [selected_tf.display_name(), selected_tf.color])
		lines.append("  %s, [b]%d[/b] segmenti su %d" % [kind, t.length(),
			Trajectory.MAX_SEGMENTS])
		lines.append("  velocita': %s    capo attivo: %s"
			% [TimeLapse.speed_label(selected_tf.speed),
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

	_refresh_now()

	var lg: Array[String] = []
	lg.append("[b]Mosse:[/b] %d    (F1 = comandi)" % log.applied_count() if log else "")
	for m in _messages:
		lg.append("  " + m)
	_lbl_log.text = "\n".join(lg)
