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
const MAP_INPUT_PROXY := preload("res://ui/map_view/map_input_proxy.gd")

signal _hex_choice_made(h: Vector2i)
signal _status_choice_made(index: int)

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
var _trajectory_action_armed: bool = false

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
var solo: SoloOpponent = null

var _messages: Array[String] = []
var _message_bot_trace: Array[int] = []
var _message_seq: int = 0
var _bot_trace_serial: int = 0
var _active_bot_trace: int = 0
var _expanded_bot_traces: Dictionary = {}
var _last_bot_summary: String = ""
var _battle_post_time_lapse: Array[TaskForce] = []
var _battle_post_bl2_incident: bool = false
var _hex_choice_active: bool = false
var _hex_choice_options: Dictionary = {}
var _hex_choice_prompt: String = ""
var _bl1_fueling_running: bool = false

const MAP_TOP := 100.0
const MAP_LEFT := 310.0
const MAP_RIGHT := 410.0
const MAP_BOTTOM := 352.0
var _map_container: SubViewportContainer = null
var _map_viewport: SubViewport = null
var _map_frame: Panel = null
var _inset_panel: PanelContainer = null
## "" = Mappa Operazionale, altrimenti la chiave dell'inserto in uso.
var _current_map_key: String = ""


func _build_map_viewport() -> void:
	var layer := CanvasLayer.new()
	layer.name = "MapSurface"
	layer.layer = 0
	add_child(layer)

	_map_frame = Panel.new()
	_map_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_frame.offset_left = MAP_LEFT
	_map_frame.offset_top = MAP_TOP
	_map_frame.offset_right = -MAP_RIGHT
	_map_frame.offset_bottom = -MAP_BOTTOM
	_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.015, 0.02, 0.025, 1.0)
	frame_style.border_color = Color(0.32, 0.43, 0.50, 1.0)
	frame_style.set_border_width_all(1)
	_map_frame.add_theme_stylebox_override("panel", frame_style)
	layer.add_child(_map_frame)

	_map_container = SubViewportContainer.new()
	_map_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_container.offset_left = MAP_LEFT + 1
	_map_container.offset_top = MAP_TOP + 1
	_map_container.offset_right = -MAP_RIGHT - 1
	_map_container.offset_bottom = -MAP_BOTTOM - 1
	_map_container.stretch = true
	_map_container.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(_map_container)

	_map_viewport = SubViewport.new()
	_map_viewport.name = "MapViewport"
	_map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_viewport.handle_input_locally = true
	_map_container.add_child(_map_viewport)
	_resize_map_viewport()
	get_viewport().size_changed.connect(_resize_map_viewport)


func _resize_map_viewport() -> void:
	# Con stretch attivo e' il Container ad assegnare automaticamente la
	# dimensione al SubViewport. Alla camera resta soltanto da ricalcolare i
	# limiti quando la finestra cambia forma.
	if cam != null:
		cam.call_deferred("_clamp_position")


func _set_map_right_margin(margin: float) -> void:
	if _map_frame == null or _map_container == null:
		return
	_map_frame.offset_right = -margin
	_map_container.offset_right = -margin - 1
	_resize_map_viewport()


func _ready() -> void:
	graph = MapGraph.load_default()
	if graph.load_error != "":
		push_error(graph.load_error)
	state = GameState.new(graph, 20240114)
	engine = ActionEngine.load_default()

	_build_map_viewport()

	board = MapBoard.new()
	board.name = "Board"
	_map_viewport.add_child(board)
	board.setup(graph)

	traj_layer = TrajectoryRenderer.new()
	traj_layer.name = "Trajectories"
	traj_layer.z_index = 10
	_map_viewport.add_child(traj_layer)
	traj_layer.setup(graph, state)

	cam = MapCamera.new()
	cam.name = "Camera"
	_map_viewport.add_child(cam)
	cam.make_current()
	cam.setup(Vector2(graph.map_size))

	var input_proxy: Node = MAP_INPUT_PROXY.new()
	input_proxy.receiver = self
	_map_viewport.add_child(input_proxy)

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


func _load_scenario_at(idx: int, offer_setup_choices: bool = true) -> void:
	if scenario_ids.is_empty():
		_msg("nessuno scenario (esegui tools/import_scenarios.py)")
		return
	scenario_index = wrapi(idx, 0, scenario_ids.size())
	scenario = Scenario.load_by_id(scenario_ids[scenario_index])
	if scenario.load_error != "":
		_msg(scenario.load_error)
		return
	# La superficie va scelta PRIMA di schierare: cinque scenari solitari si
	# giocano su una mappa inserto, non sulla Mappa Operazionale.
	_use_map_for(scenario)
	state.apply_dict(scenario.to_state_dict())
	state.configure_port_info_triggers(scenario.port_control())
	# apply_dict riparte dal dizionario dello scenario, che non sa nulla delle
	# Regole Avanzate: la scelta va rimessa dopo, se no cambiare scenario la
	# perde in silenzio.
	state.advanced_battle = Session.advanced_battle
	_select_first_initiative_force()
	log = CommandLog.new(state)
	victory = Victory.from_scenario(scenario)
	vp_tracker = VictoryTracker.new(victory, state)
	solo = SoloOpponent.load_for(scenario.id)
	if solo != null:
		solo.set_phase(state.solo_phase, state.solo_phase_reason)
	_msg("Scenario: %s  -  %d Task Force, %d navi"
		% [scenario.title, state.task_forces.size(), scenario.ship_count()])
	if solo != null:
		_msg("Solitario: tabelle caricate (%s). Premi O per l'avversario immaginario."
			% ("Tardi" if solo.phase == SoloOpponent.Phase.LATE else "Presto"))
	if not scenario.map_info.is_empty() and state.task_forces.is_empty():
		_msg("Scenario non ancora giocabile: %s. %s" % [
			String(scenario.map_info.get("name", "mappa speciale")),
			String(scenario.map_info.get("status", "schieramento non trascritto"))])
		if graph.is_inset():
			_msg("La mappa pero' c'e': %d esagoni, %d porti, %d frecce 'non adiacente'%s. "
				% [graph.hex_count(), graph.port_count(), graph.blocked_edge_count(),
					"" if graph.air_bases.is_empty()
					else ", %d basi aeree" % graph.air_bases.size()]
				+ "Premi G per vedere il reticolo.")
	if scenario.has_import_warnings():
		for w_v: Variant in scenario.import_warnings:
			_msg("  [avviso di import] %s" % String(w_v))
	_update_briefing()
	_focus_selected()
	_refresh()
	if scenario.is_battle_scenario():
		_open_scenario_battle()
	elif _solo_is_imaginary_turn():
		call_deferred("_kick_solo_opponent_turn", "inizio scenario")
	call_deferred("_kick_bl1_fueling_check")
	if offer_setup_choices and scenario.id == "BL2 Contain and Destroy":
		call_deferred("_choose_bl2_setup")


## BL2 lascia al giocatore quattro navi indicate come "any" e la posizione
## iniziale della Home Fleet. I nomi nel JSON sono soltanto il ripiego valido
## per test e avvii senza interazione; una partita normale chiede le scelte.
func _choose_bl2_setup() -> void:
	var home_fleet := _bl2_home_fleet()
	if home_fleet == null:
		_msg("BL2: Home Fleet non trovata; scelte di schieramento non disponibili.")
		return
	await _choose_bl2_home_fleet_ships(home_fleet)
	await _choose_bl2_home_fleet_station(home_fleet)
	_msg("BL2: Gruppo Rinforzi A con Rodney e Valiant nella casella Scapa Flow; "
		+ "non e' una TF finche' non entra con Riorganizzare.")
	_refresh()


func _bl2_home_fleet() -> TaskForce:
	for tf in state.task_forces:
		if tf.display_name() == "Home Fleet":
			return tf
	return null


func _choose_bl2_home_fleet_ships(home_fleet: TaskForce) -> void:
	var chosen: Array[String] = ["Repulse"]
	for spec_v: Variant in [{"type": "CA", "count": 3}, {"type": "CL", "count": 1}]:
		var spec: Dictionary = spec_v
		for index in int(spec["count"]):
			var candidates: Array[Ship] = []
			for roster_name_v: Variant in ShipRoster.shared().names():
				var ship := ShipRoster.shared().make(String(roster_name_v))
				if ship != null and ship.nation == "UK" \
						and ship.type_code == String(spec["type"]) \
						and not chosen.has(ship.name):
					candidates.append(ship)
			candidates.sort_custom(func(a: Ship, b: Ship) -> bool:
				return a.name < b.name)
			var options: Array = []
			for ship in candidates:
				options.append({"label": ship.name, "detail": ship.type_code})
			var picked: int = await Choice.ask(self, "Schieramento BL2 - Home Fleet",
				"Scegli %s %d di %d. Il fascicolo indica 'any'." % [
					String(spec["type"]), index + 1, int(spec["count"])], options)
			if picked < 0:
				_msg("BL2: scelta navi annullata; resta la composizione di ripiego valida.")
				return
			chosen.append(candidates[picked].name)
	var ships: Array[Ship] = []
	for ship_name in chosen:
		ships.append(ShipRoster.shared().make(ship_name))
	home_fleet.ships = ships
	home_fleet.recompute_speed()
	_msg("Schieramento BL2: Home Fleet contiene %s; Forbes e' assegnato alla TF."
		% ", ".join(chosen))


## BL2 lascia al giocatore la posizione iniziale della Home Fleet. La scelta
## usa soltanto porti e adiacenze calibrati; il valore nel JSON e' un ripiego
## legale per avvii headless, screenshot e annullamento.
func _choose_bl2_home_fleet_station(home_fleet: TaskForce = null) -> void:
	if scenario == null or scenario.id != "BL2 Contain and Destroy":
		return
	if home_fleet == null:
		home_fleet = _bl2_home_fleet()
	if home_fleet == null:
		_msg("BL2: Home Fleet non trovata; scelta di schieramento non disponibile.")
		return
	var legal := SoloAI.bl2_home_fleet_station_hexes(graph, scenario.port_control())
	if legal.is_empty():
		_msg("BL2: nessun esagono calibrato soddisfa lo schieramento della Home Fleet.")
		return
	var picked := await _pick_hex_on_map(legal,
		"Schieramento BL2: scegli l'esagono della Home Fleet, adiacente a un "
		+ "porto controllato britannico eccetto Scapa Flow e Methil. ESC mantiene "
		+ "il ripiego legale presso Clyde.")
	if picked == Vector2i.MAX:
		return
	home_fleet.trajectory.become_station(picked)
	selected_tf = home_fleet
	_msg("Schieramento BL2: Home Fleet piazzata in (%d,%d)." % [picked.x, picked.y])
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
	# Il puntatore della mappa arriva dal suo SubViewport tramite
	# MapInputProxy. Qui restano tastiera e scorciatoie del workspace principale.
	if event is InputEventKey:
		_handle_game_input(event)


func _handle_map_input(event: InputEvent) -> void:
	_handle_game_input(event)


func _handle_game_input(event: InputEvent) -> void:
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
					await _on_left_click(_press_hex, _press_shift)
				else:
					await _finish_drag()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_right_click(h)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		_on_key(event as InputEventKey)


func _on_key(k: InputEventKey) -> void:
	if _status_choice_active:
		if k.keycode == KEY_ESCAPE:
			_complete_status_choice(-1)
		elif k.keycode >= KEY_1 and k.keycode <= KEY_9:
			var option := int(k.keycode - KEY_1)
			if option < _status_choice_option_count:
				_complete_status_choice(option)
		return
	if _hex_choice_active and k.keycode == KEY_ESCAPE:
		_hex_choice_active = false
		_hex_choice_options.clear()
		_hex_choice_prompt = ""
		board.set_highlight({})
		_msg("Scelta esagono annullata.")
		_hex_choice_made.emit(Vector2i.MAX)
		_refresh()
		return
	if k.keycode == KEY_ESCAPE and _briefing_panel != null \
			and _briefing_panel.visible:
		_briefing_panel.visible = false
		return
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
		KEY_O:
			await _do_solo()
		KEY_B:
			_toggle_briefing()
		KEY_0:
			# scorciatoia: apre una Battaglia fra la TF selezionata e la piu'
			# vicina avversaria, senza passare da un'azione. Serve a provare la
			# Mappa di Battaglia senza dipendere dal tiro di dadi.
			if selected_tf != null:
				var en := _nearest_enemy(selected_tf)
				if en != null and await _prepare_solo_battle(selected_tf, en):
					var t := selected_tf.trajectory
					_open_battle(Results.Battle.FULL, selected_tf, en,
						t.station_hex if t.is_station() else t.end_hex(0))
		KEY_F1:
			_toggle_help()
		KEY_HOME:
			_focus_selected()
		KEY_ESCAPE:
			_cancel_trajectory_action()
	_refresh()


## Dichiara un'azione. Le designazioni contano: la TF Coordinatrice e quella di
## Supporto Aereo entrano nel Totale Traiettoria (RB p.17), quindi le sceglie il
## giocatore. Le domande si saltano quando non c'e' nulla da scegliere.
func _declare_action(key: String) -> void:
	if _solo_is_imaginary_turn():
		await _maybe_run_solo_opponent_turn("turno dell'avversario immaginario")
		return
	if await _maybe_run_bl1_fueling():
		return
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
			_arm_trajectory_action()
			_msg("Traiettoria: trascina dalla Task Force selezionata per "
				+ "disegnare la rotta, oppure clicca un esagono adiacente a "
				+ "un capo. ESC annulla senza tracciare altro.")
			return

	var active := selected_tf
	var launch_hex := Vector2i.MAX
	if key == "AIR_STRIKE":
		var sources := _air_sources(active.side)
		active = await _pick_tf(sources, "Attacco Aereo - fonte",
			"Scegli la Task Force con la portaerei integra che lancia l'attacco. "
			+ "Le basi aeree non sono ancora modellate.", false)
		if active == null:
			return
		selected_tf = active
		traj_layer.selected_tf_id = active.id
		var launches := ActionEngine.air_launch_hexes(active)
		launch_hex = launches[0]
		if launches.size() > 1:
			launch_hex = await _pick_hex_on_map(launches,
				"Punto di Lancio: clicca un esagono evidenziato della TF con la CV.")
			if launch_hex == Vector2i.MAX:
				_msg("Attacco Aereo annullato: nessun Punto di Lancio scelto.")
				return

	var enemies := _eligible_targets_for_action(key, active, launch_hex)
	if enemies.is_empty():
		_msg("%s: %s" % [String(engine.action(key).get("label", key)),
			_enemy_action_unavailable_reason(key, active)])
		return
	var target := await _pick_tf(enemies, "Task Force Bersaglio",
		"Contro chi dichiari l'azione?", false)
	if target == null:
		return

	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = active
	dec.target = target
	dec.launch_hex = launch_hex
	var target_hexes := _target_hexes_for_action(key, active, target, launch_hex)
	if target_hexes.is_empty():
		_msg("%s: nessun esagono bersaglio legale." % String(
			engine.action(key).get("label", key)))
		return
	dec.target_hex = target_hexes[0]
	if target_hexes.size() > 1:
		dec.target_hex = await _pick_hex_on_map(target_hexes,
			"Esagono Bersaglio: clicca uno degli esagoni evidenziati.")
		if dec.target_hex == Vector2i.MAX:
			_msg("%s annullata: nessun esagono Bersaglio scelto." % String(
				engine.action(key).get("label", key)))
			return
	if key == "AIR_STRIKE":
		traj_layer.set_air_action_markers(active.side, launch_hex, dec.target_hex)

	# RB p.47: la Coordinatrice deve occupare l'esagono Bersaglio.
	var own: Array[TaskForce] = []
	for tf in state.forces_of(active.side):
		if tf != active and tf.trajectory.occupies(dec.target_hex):
			own.append(tf)
	if not own.is_empty():
		dec.active_coordinating = await _pick_tf(own, "TF Coordinatrice",
			"Designa una Task Force Coordinatrice? La sua lunghezza puo' "
			+ "sostituire quella della TF Attiva nel Totale Traiettoria.", true)

	# Nell'Attacco Aereo la fonte e' gia' il Supporto Aereo (RB p.27).
	var carriers: Array[TaskForce] = []
	if key != "AIR_STRIKE":
		for tf in state.forces_of(active.side):
			if tf == active or ActionEngine.air_launch_hexes(tf).is_empty():
				continue
			for h in ActionEngine.air_launch_hexes(tf):
				if Hex.distance(h, dec.target_hex) <= 2:
					carriers.append(tf)
					break
	if not carriers.is_empty():
		dec.active_air_support = await _pick_tf(carriers, "TF Supporto Aereo",
			"Designa una Task Force di Supporto Aereo? Deve avere una "
			+ "portaerei.", true)

	# Gensoul agisce sulle designazioni, quindi PRIMA della risoluzione:
	# l'Interruzione si tira sui segnalini Informazioni delle TF designate, e
	# toglierne uno dopo non servirebbe a niente.
	await _offer_gensoul(dec)

	var res := engine.resolve(dec, state)
	var label := String(engine.action(key).get("label", key))
	if not res["ok"]:
		_msg("%s: %s" % [label, res["error"]])
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		return
	_msg("%s -> %s" % [label, engine.describe(res)])
	if _action_canceled_by_interruption(res):
		await _handle_interruption_cancel(res, dec)
		log.record("%s annullata da Interruzione (%s)"
			% [label, active.display_name()])
		state.changed.emit()
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		_refresh()
		return

	var pending_battle := Results.Battle.NONE
	var initiative_changed := false
	for code_v: Variant in res["results"] as Array:
		var code := String(code_v)
		var applied := Results.apply(code, active, target,
			dec.target_hex, state, _ship_chooser, _designated_active_info_count(dec))
		_msg("    %s" % applied["text"])
		if bool(applied.get("initiative_changes", false)):
			initiative_changed = true
		if applied["battle"] != Results.Battle.NONE:
			pending_battle = applied["battle"]
	_report_eliminated_forces(label)
	log.record("%s (%s)" % [label, dec.active.display_name()])
	state.changed.emit()
	if key == "AIR_STRIKE":
		_solo_maybe_go_late("air_strike", "e' stato eseguito un Attacco Aereo")
	elif key == "STEALTH_ATTACK":
		_solo_maybe_go_late("stealth_attack", "e' stato eseguito un Attacco Furtivo")
	if pending_battle != Results.Battle.NONE \
			and not await _prepare_solo_battle(dec.active, target):
		pending_battle = Results.Battle.NONE
	if pending_battle != Results.Battle.NONE:
		_battle_post_bl2_incident = _bl2_neutral_incident_required(key,
			dec.active, dec.target_hex)
		_solo_maybe_go_late("battle", "un risultato ha aperto una Battaglia")
		_battle_post_time_lapse.clear()
		for tf in [dec.active_coordinating, dec.active_air_support]:
			if tf != null and tf != dec.active and tf != dec.target \
					and not _battle_post_time_lapse.has(tf):
				_battle_post_time_lapse.append(tf)
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		_open_battle(pending_battle, dec.active, target, dec.target_hex)
	elif initiative_changed:
		await _maybe_bl2_neutral_incident(key, dec.active, dec.target_hex)
		if bool(engine.action(key).get("causes_time_lapse", false)):
			await _time_lapse_designated_active(dec)
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		if _change_initiative_to(1 - dec.active.side):
			await _maybe_run_solo_opponent_turn("risultato dell'azione")
	else:
		await _maybe_bl2_neutral_incident(key, dec.active, dec.target_hex)
		await _post_table_action_flow(key, dec)
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
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


func _target_hexes_for_action(key: String, active: TaskForce, target: TaskForce,
		launch_hex: Vector2i = Vector2i.MAX) -> Array[Vector2i]:
	if key == "AIR_STRIKE":
		return ActionEngine.air_target_hexes(launch_hex, target)
	var out: Array[Vector2i] = []
	if key == "ENGAGE" or key == "NAVAL_SEARCH":
		var occupied := [target.trajectory.station_hex] \
			if target.trajectory.is_station() else target.trajectory.hexes()
		for h_v: Variant in occupied:
			var h: Vector2i = h_v
			if active.trajectory.occupies(h):
				out.append(h)
		return out
	var t := target.trajectory
	out.append(t.station_hex if t.is_station() else t.end_hex(0))
	return out


func _air_sources(side: int) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in state.forces_of(side):
		if Convoy.action_refusal(tf, "AIR_STRIKE") == "" \
				and not ActionEngine.air_launch_hexes(tf).is_empty():
			out.append(tf)
	return out


func _eligible_targets_for_action(key: String, active: TaskForce,
		launch_hex: Vector2i = Vector2i.MAX) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	if active == null:
		return out
	for tf in state.forces_of(1 - active.side):
		var target_hexes := _target_hexes_for_action(key, active, tf, launch_hex)
		if target_hexes.is_empty():
			continue
		var dec := ActionEngine.Declaration.new()
		dec.action_key = key
		dec.active = active
		dec.target = tf
		dec.launch_hex = launch_hex
		dec.target_hex = target_hexes[0]
		if engine.legality_error(dec, state) == "":
			out.append(tf)
	return out


func _sample_target_for_action(key: String, active: TaskForce) -> TaskForce:
	var eligible := _eligible_targets_for_action(key, active)
	if not eligible.is_empty():
		return eligible[0]
	return _nearest_enemy(active)


func _designated_active_info_count(dec: ActionEngine.Declaration) -> int:
	var n := 0
	for tf in dec.designated_active():
		if tf != null:
			n += tf.info_count()
	return n


func _enemy_action_unavailable_reason(key: String, active: TaskForce) -> String:
	if active == null:
		return "nessuna Task Force selezionata"
	if state.forces_of(1 - active.side).is_empty():
		if solo != null:
			return ("nessuna TF avversaria e' ancora in mappa: nel solitario "
				+ "usa O per la Tabella Solitario o crea una TF non identificata "
				+ "quando lo scenario lo ordina")
		return "nessuna Task Force avversaria in gioco"
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = active
	dec.target = _nearest_enemy(active)
	var err := engine.legality_error(dec, state)
	if err != "" and not err.contains("stesso esagono") \
			and not err.contains("Bersaglio") and not err.contains("Traiettoria"):
		return err
	match key:
		"ENGAGE":
			return "nessuna Stazione avversaria occupa lo stesso esagono della TF Attiva"
		"NAVAL_SEARCH":
			return "nessuna Traiettoria avversaria attraversa l'esagono della TF Attiva"
		"STEALTH_ATTACK":
			return "nessun segmento avversario con Contatto e' bersagliabile adesso"
		_:
			return "nessuna Task Force avversaria soddisfa le condizioni dell'azione"


func _action_canceled_by_interruption(res: Dictionary) -> bool:
	var ir: Dictionary = res.get("interruption", {})
	return not ir.is_empty() and bool(ir.get("triggered", false)) \
		and int(ir.get("result", Interruption.Result.ALERT)) != Interruption.Result.ALERT


func _handle_interruption_cancel(res: Dictionary, dec: ActionEngine.Declaration) -> void:
	var ir: Dictionary = res.get("interruption", {})
	_msg("    %s" % String(ir.get("effect", "Azione annullata.")))
	match int(ir.get("result", Interruption.Result.ALERT)):
		Interruption.Result.SLIP_AWAY:
			await _handle_slip_away(dec)
			if _seek_initiative():
				await _maybe_run_solo_opponent_turn("Interruzione")
		Interruption.Result.VIE_FOR_INITIATIVE:
			if _seek_initiative():
				await _maybe_run_solo_opponent_turn("Interruzione")
		Interruption.Result.INITIATIVE_CHANGE:
			if _change_initiative_to(1 - dec.acting_side()):
				await _maybe_run_solo_opponent_turn("Interruzione")


func _handle_slip_away(dec: ActionEngine.Declaration) -> void:
	var opts: Array = [
		{"label": "Segnalazione", "detail": "contro la TF Attiva o una Coordinatrice"},
		{"label": "Manovre Evasive", "detail": "alla TF Bersaglio"},
	]
	var i: int = await Choice.ask(self, "Interruzione - Sfuggire",
		"L'Inattivo sceglie l'effetto prima che l'azione sia annullata.", opts)
	if i == 0:
		var cands: Array[TaskForce] = []
		for tf in [dec.active, dec.active_coordinating]:
			if tf != null and not SignalAction.target_hexes(tf).is_empty():
				cands.append(tf)
		if cands.is_empty():
			_msg("Sfuggire: nessuna TF Attiva/Coordinatrice ha segnalini Informazioni da segnalare.")
			return
		var target := await _pick_tf(cands, "Sfuggire - Segnalazione",
			"Quale TF viene localizzata?", false)
		if target == null:
			return
		var hexes := SignalAction.target_hexes(target)
		var at := hexes[0]
		if hexes.size() > 1:
			var choices: Array = []
			for h in hexes:
				choices.append({"label": str(h), "detail": ""})
			var j: int = await Choice.ask(self, "Sfuggire - quale segnalino?",
				"La Stazione viene posta su quel segnalino Informazioni.", choices)
			if j < 0:
				return
			at = hexes[j]
		_report(SignalAction.resolve(target, at))
	else:
		if dec.target != null:
			_report_initiative(Initiative.decline_steal_for_evasive(state, dec.target))
		else:
			_msg("Sfuggire: manca la TF Bersaglio per Manovre Evasive.")


func _post_table_action_flow(key: String, dec: ActionEngine.Declaration) -> void:
	if bool(engine.action(key).get("causes_time_lapse", false)):
		await _time_lapse_designated_active(dec)
	match key:
		"NAVAL_SEARCH":
			if await _offer_steal_initiative("Ricerca Navale"):
				await _maybe_run_solo_opponent_turn("Ricerca Navale")
		"ENGAGE", "AIR_STRIKE", "STEALTH_ATTACK":
			if _seek_initiative():
				await _maybe_run_solo_opponent_turn("Cercare l'Iniziativa")


func _time_lapse_designated_active(dec: ActionEngine.Declaration) -> void:
	for tf in dec.designated_active():
		if tf != null and tf != dec.target:
			var protected_hex := dec.launch_hex if dec.action_key == "AIR_STRIKE" \
				and tf == dec.active else Vector2i.MAX
			await _do_time_lapse_for(tf, true, protected_hex)


func _do_time_lapse_for(tf: TaskForce, allow_bl1_fueling: bool = true,
		protected_hex: Vector2i = Vector2i.MAX) -> void:
	var old := selected_tf
	selected_tf = tf
	traj_layer.selected_tf_id = tf.id
	await _do_time_lapse(allow_bl1_fueling, protected_hex)
	selected_tf = old if old != null and state.task_force(old.id) != null else selected_tf
	traj_layer.selected_tf_id = selected_tf.id if selected_tf != null else -1


func _report_initiative(r: Dictionary) -> bool:
	for line_v: Variant in r.get("log", []):
		_msg(String(line_v))
	if bool(r.get("changed", false)):
		_select_first_initiative_force()
		return true
	return false


func _change_initiative_to(side: int) -> bool:
	if state.initiative == side:
		return false
	state.initiative = side
	state.initiative_count = 0
	var w := Initiative.weather_check(state)
	_msg("L'Iniziativa passa a %s; il conteggio torna a zero."
		% Initiative.side_name(side))
	_msg(String(w["log"]))
	_select_first_initiative_force()
	return true


func _seek_initiative() -> bool:
	return _report_initiative(Initiative.seek(state))


func _offer_steal_initiative(reason: String) -> bool:
	var inactive := 1 - state.initiative
	if solo != null and inactive == _solo_imaginary_side():
		_msg("%s - Iniziativa: l'avversario immaginario tenta di Sottrarre."
			% reason)
		var auto := Initiative.steal(state)
		_report_initiative(auto)
		return bool(auto.get("changed", false))
	var opts: Array = [
		{"label": "Tenta di Sottrarre", "detail": "2d6 + Conto; con 9+ prende l'Iniziativa"},
		{"label": "Rinuncia: Manovre Evasive", "detail": "il Conto non aumenta"},
	]
	var i: int = await Choice.ask(self, "%s - Iniziativa" % reason,
		"L'Inattivo (%s) puo' tentare di Sottrarre l'Iniziativa."
			% Initiative.side_name(inactive), opts)
	if i == 0:
		var r := Initiative.steal(state)
		_report_initiative(r)
		return bool(r.get("changed", false))
	if i == 1:
		var cands := state.forces_of(inactive)
		var tf := await _pick_tf(cands, "Manovre Evasive",
			"A quale Task Force dell'Inattivo assegni il segnalino?", true)
		_report_initiative(Initiative.decline_steal_for_evasive(state, tf))
	return false


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


## Regole solitarie generali: una TF ignota viene identificata appena un
## risultato trasferisce le sue navi alla Mappa di Battaglia. La scelta delle
## navi e' del core; qui rendiamo leggibili tiro, applicazione ed eventuale gap.
func _prepare_solo_battle(active: TaskForce, target: TaskForce) -> bool:
	if solo == null:
		return true
	for tf_v: Variant in [active, target]:
		var tf: TaskForce = tf_v
		# Con un attaccante Furtivo l'Attiva non esiste: niente da identificare.
		if tf == null:
			continue
		var identified := SoloAI.identify_for_battle(solo, state, graph, engine,
			_port_control(), tf)
		if not bool(identified.get("needed", false)):
			continue
		_msg("Solitario - Identificazione automatica prima della Battaglia: %s"
			% tf.display_name())
		var roll: Dictionary = identified.get("roll", {})
		if not roll.is_empty():
			for line in SoloTable.describe(roll).split("\n"):
				_msg("  " + line)
		for line_v: Variant in identified.get("log", []):
			var line := String(line_v)
			if line != "":
				_msg("  " + line)
		if not bool(identified.get("ok", false)):
			var failure := "Identificazione automatica non applicabile."
			var failure_log: Array = identified.get("log", [])
			if not failure_log.is_empty():
				failure = String(failure_log[0])
			_msg("Battaglia non aperta: %s"
				% failure)
			log.record("Solitario: Identificazione automatica non riuscita")
			state.changed.emit()
			return false
		log.record("Solitario: Identificazione automatica di %s"
			% tf.display_name())
	_resync_selection()
	state.changed.emit()
	return true


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
	var solo_side := victory.solo_side if victory != null \
		and victory.mode == Victory.Mode.DEBRIEFING else -1
	_battle_view.setup(b, solo_side)
	_battle_view.closed.connect(_close_battle.bind(b))
	var where := " in %s" % str(bstate.hex) if bstate.hex != Vector2i.ZERO else ""
	_msg("%s aperta%s." % [BattleState.KIND_LABELS[bstate.kind], where])


func _close_battle(b: Battle) -> void:
	var out := b.finish()
	for t_v: Variant in (out["sunk"] as Array):
		_msg("  affondata: %s" % String(t_v))
	_report_eliminated_forces("Battaglia")
	_msg("Battaglia conclusa: %s" % b.state.end_reason)
	for tf in _battle_post_time_lapse:
		if tf != null and state.task_force(tf.id) != null:
			await _do_time_lapse_for(tf)
	_battle_post_time_lapse.clear()
	if _battle_post_bl2_incident:
		_battle_post_bl2_incident = false
		await _roll_bl2_international_incident()
	if _seek_initiative():
		await _maybe_run_solo_opponent_turn("fine Battaglia")
	if _battle_layer != null:
		_battle_layer.queue_free()
		_battle_layer = null
		_battle_view = null
	log.record("Battaglia in %s" % str(b.state.hex))
	state.changed.emit()
	_refresh()


func _report_eliminated_forces(reason: String) -> void:
	var removed := state.remove_eliminated_forces(reason)
	for loss in removed:
		_msg("TF rimossa dalla mappa: %s (nessuna nave a galla)."
			% String(loss.get("tf_name", "Task Force")))
		if int(loss.get("convoys", 0)) > 0:
			_solo_maybe_go_late("convoy_destroyed", "un Convoglio e' stato distrutto")
	if not removed.is_empty():
		_resync_selection()


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
	# Le decisioni aperte nel pannello di stato sono modali rispetto alla
	# mappa: un clic non deve cambiare la TF mentre l'azione conserva gia'
	# la propria dichiarazione.
	if _status_choice_active:
		return
	if _hex_choice_active:
		if _hex_choice_options.has(h):
			_hex_choice_active = false
			_hex_choice_options.clear()
			board.set_highlight({})
			_hex_choice_made.emit(h)
			return
		else:
			_msg("Scegli uno degli esagoni evidenziati; ESC annulla.")
		return
	if mode == Mode.EDITOR:
		_editor_click(h, shift)
		return

	# 1) se c'e' una TF nell'esagono e non stiamo estendendo, selezionala
	var here := state.forces_in(h)
	if not here.is_empty() and (selected_tf == null or not _can_extend_to(h)):
		var idx := here.find(selected_tf)
		selected_tf = here[(idx + 1) % here.size()] if idx >= 0 else here[0]
		traj_layer.selected_tf_id = selected_tf.id
		_cancel_trajectory_action(false)
		_msg("selezionata %s (%d segmenti)"
			% [selected_tf.display_name(), selected_tf.length()])
		return

	# 2) un clic sul mare deseleziona. Se l'azione Traiettoria e' armata, invece,
	# quel clic resta il punto da aggiungere alla rotta.
	if selected_tf == null:
		return
	if not _trajectory_action_armed:
		selected_tf = null
		traj_layer.selected_tf_id = -1
		_tf_card_signature = ""
		_msg("Task Force deselezionata")
		return
	await _try_extend(h)


func _on_right_click(h: Vector2i) -> void:
	if _status_choice_active:
		return
	if mode == Mode.EDITOR:
		if graph.has_hex(h):
			edit_anchor = h
			board.selected_hex = h
			board.queue_redraw()
			_msg("ancora impostata su %s (clic sinistro su un vicino per bloccare il lato)"
				% str(h))
		return
	if selected_tf == null:
		return
	_msg("I segmenti si rimuovono soltanto quando un'Azione o un evento innesca "
		+ "lo Scorrere del Tempo. Per correggere l'ultima rotta usa Ctrl+Z.")


## Inizia un trascinamento se il punto premuto e' una TF selezionabile o un
## capo della Traiettoria gia' selezionata.
func _begin_drag(h: Vector2i) -> void:
	if _status_choice_active:
		return
	if mode != Mode.PLAY or selected_tf == null:
		return
	if not _trajectory_action_armed:
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
	var projected := t.length() + drag_path.size() + 1
	if t.is_station() and drag_path.is_empty() and not state.port_hexes().has(t.station_hex):
		projected += 1
	if projected > Trajectory.MAX_SEGMENTS:
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
		var before := t.length()
		if t.extend(h, drag_end, graph, ports, info, selected_tf.side):
			added += t.length() - before
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
		_trajectory_action_armed = false
		await _after_trajectory_action(selected_tf)
	_refresh()


func _can_extend_to(h: Vector2i) -> bool:
	if selected_tf == null:
		return false
	if not _can_control_tf(selected_tf):
		return false
	return selected_tf.trajectory.extend_error(
		h, active_end, graph, state.port_hexes(), selected_tf.side) == ""


func _try_extend(h: Vector2i) -> void:
	if not _trajectory_action_armed:
		_msg("Per tracciare una rotta dichiara prima l'azione Traiettoria (5).")
		return
	if not _can_control_tf(selected_tf):
		_msg("Traiettoria: questa Task Force appartiene all'avversario immaginario.")
		return
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
			_trajectory_action_armed = false
			await _after_trajectory_action(selected_tf)
			return
	_msg("mossa illegale: %s" % traj.extend_error(h, active_end, graph, ports, selected_tf.side))


func _after_trajectory_action(active: TaskForce) -> void:
	if active == null:
		return
	if await _offer_steal_initiative("Traiettoria"):
		await _maybe_run_solo_opponent_turn("Traiettoria")


func _cycle_tf(step: int) -> void:
	if state.task_forces.is_empty():
		return
	var pool := _controllable_forces(state.task_forces)
	if pool.is_empty():
		for tf in state.task_forces:
			if not tf.completed:
				pool.append(tf)
	if pool.is_empty():
		return
	var i := pool.find(selected_tf)
	i = wrapi(i + step, 0, pool.size())
	selected_tf = pool[i]
	traj_layer.selected_tf_id = selected_tf.id
	_cancel_trajectory_action(false)
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
	if selected_tf == null:
		_cancel_trajectory_action(false)


func _select_first_initiative_force() -> void:
	selected_tf = null
	for tf in _controllable_forces(state.task_forces):
		if tf.side == state.initiative:
			selected_tf = tf
			break
	var pool := _controllable_forces(state.task_forces)
	if selected_tf == null and not pool.is_empty():
		selected_tf = pool[0]
	if selected_tf == null:
		for tf in state.task_forces:
			if not tf.completed:
				selected_tf = tf
				break
	if traj_layer != null:
		traj_layer.selected_tf_id = selected_tf.id if selected_tf != null else -1


func _can_control_tf(tf: TaskForce) -> bool:
	if tf == null or tf.completed:
		return false
	var player := _solo_player_side()
	if player < 0:
		return true
	return tf.side == player


func _controllable_forces(forces: Array) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf_v: Variant in forces:
		var tf: TaskForce = tf_v
		if _can_control_tf(tf):
			out.append(tf)
	return out


func _arm_trajectory_action() -> void:
	if selected_tf == null:
		return
	if not _can_control_tf(selected_tf):
		_msg("Traiettoria: questa Task Force appartiene all'avversario immaginario.")
		return
	_trajectory_action_armed = true
	traj_layer.clear_preview()


func _cancel_trajectory_action(report: bool = true) -> void:
	if not _trajectory_action_armed:
		return
	_trajectory_action_armed = false
	dragging = false
	drag_path.clear()
	traj_layer.clear_preview()
	if report:
		_msg("Traiettoria annullata.")


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
	_load_scenario_at(idx, false)
	state.apply_dict(doc["state"])
	# Aggiorna anche i vecchi salvataggi creati quando i porti nemici non
	# venivano ancora registrati come cause di Informazioni.
	state.configure_port_info_triggers(scenario.port_control())
	if solo != null:
		solo.set_phase(state.solo_phase, state.solo_phase_reason)
	log = CommandLog.new(state)
	_resync_selection()
	_msg("Partita ripresa: %s, round %d." % [scenario.title, state.round_number])
	_focus_selected()
	_refresh()


## Esito della partita, con le righe che il motore non puo' valutare da solo.
func _show_outcome() -> void:
	if victory == null:
		return
	_bl1_murmansk_before_debriefing()
	var description := victory.describe(state)
	var late := Endgame.notice(state, scenario.rules() if scenario != null
		else {}, graph, _port_control())
	var text := "[b]VALORI SULLA MAPPA[/b]\n"
	text += "Modificatori: [b]%+d[/b] (%s)    Conto Iniziativa: [b]%d[/b]\n" % [
		state.modifier_track_value,
		Initiative.side_name(state.modifier_track_side), state.initiative_count]
	text += "Punti: Kriegsmarine [b]%s[/b], Royal Navy [b]%s[/b]\n\n" % [
		state.vp_text(TaskForce.Side.KRIEGSMARINE),
		state.vp_text(TaskForce.Side.ROYAL_NAVY)]
	text += "[b]PUNTEGGIO ED ESITO CORRENTE[/b]\n" + description
	if late != "":
		text += "\n\n[color=#ff9a3c][b]FINE PARTITA[/b]\n%s[/color]" % late
	_show_info_panel("Punteggio ed Esito", text)


## BL1 p.8: la tabella Murmansk si tira PRIMA del Debriefing, una volta sola,
## se una TF tedesca vi ha Completato. Il pannello del Punteggio e' il momento
## in cui il giocatore lo guarda, quindi e' li' che va fatto.
func _bl1_murmansk_before_debriefing() -> void:
	if solo == null or not SoloAI.bl1_murmansk_pending(state):
		return
	var applied := SoloAI.bl1_murmansk_check(state, solo.table("murmansk"))
	_msg("BL1 - Murmansk? Una TF tedesca ha Completato a Murmansk: "
		+ "si tira prima del Debriefing.")
	var roll: Dictionary = applied.get("roll", {})
	if not roll.is_empty():
		for line in SoloTable.describe(roll).split("\n"):
			_msg("  " + line)
	for line_v: Variant in applied.get("log", []):
		_msg("  " + String(line_v))
	log.record("BL1: Murmansk?")
	state.changed.emit()


# --------------------------------------------------------------- solitario --

func _do_solo() -> void:
	if solo == null:
		_msg("Solitario: questo scenario non ha tabelle trascritte.")
		return
	if state.solo_ended:
		_msg("Solitario: lo scenario e' terminato. Apri Punteggio per il Debriefing.")
		return
	while true:
		var opts: Array = [
			{"label": "Tira Tabella delle Azioni",
				"detail": "fase %s" % _solo_phase_label()},
			{"label": "Identifica la TF selezionata",
				"detail": _solo_identify_detail()},
			{"label": "Passa alla tabella Tardi",
				"detail": state.solo_phase_reason if state.solo_phase == SoloOpponent.Phase.LATE else ""},
			{"label": "Leggi un'altra tabella",
				"detail": "Rifornimento, Murmansk, Incidente Internazionale, ecc."},
			{"label": "Crea TF non identificata in porto",
				"detail": "strumento manuale per le procedure del fascicolo"},
			{"label": _intel_marker_label(), "detail": _intel_marker_detail()},
			{"label": "Chiudi", "detail": ""},
		]
		var i: int = await Choice.ask(self, "Solitario - %s" % scenario.title,
			"L'avversario immaginario tira e mostra le procedure trascritte; "
			+ "le scelte discorsive restano al giocatore.", opts)
		match i:
			0:
				await _solo_roll_action()
			1:
				_solo_identify_selected()
			2:
				await _solo_go_late()
			3:
				await _solo_roll_any_table()
			4:
				await _solo_create_unidentified_tf()
			5:
				await _do_intel_marker()
			_:
				return
		_refresh()


## Gensoul (RB p.10): quando la sua Task Force e' designata Attiva, toglie un
## segnalino Informazioni da una TF britannica o francese designata nell'Azione
## corrente. Una volta per scenario, e la decisione e' del giocatore: qui si
## limita a offrirla quando le condizioni stampate ci sono davvero.
func _offer_gensoul(dec: ActionEngine.Declaration) -> void:
	if not LeaderRules.gensoul_available(state, dec):
		return
	var targets := LeaderRules.gensoul_targets(dec)
	var opts: Array = []
	for tf in targets:
		opts.append({"label": tf.display_name(),
			"detail": "%d segnalini Informazioni" % tf.info_count()})
	opts.append({"label": "Non usarlo ora", "detail": "resta per un'altra Azione"})
	var i: int = await Choice.ask(self, "Gensoul",
		LeaderRules.effect_text("Gensoul"), opts, false)
	if i < 0 or i >= targets.size():
		return
	var chosen := targets[i]
	var hexes: Array = []
	for seg_v: Variant in chosen.trajectory.segments:
		var seg: Dictionary = seg_v
		if bool(seg["info"]):
			hexes.append(seg["hex"])
	var picked: Vector2i = hexes[0]
	if hexes.size() > 1:
		picked = await _pick_hex_on_map(hexes,
			"Gensoul: clicca il segmento di %s da cui togliere il segnalino "
				% chosen.display_name() + "Informazioni.")
		if picked == Vector2i.MAX:
			return
	var applied := LeaderRules.gensoul_remove_info(state, chosen, picked)
	if not bool(applied["ok"]):
		_msg("Gensoul: %s" % String(applied["error"]))
		return
	for line_v: Variant in applied["log"]:
		_msg(String(line_v))
	log.record("Gensoul: Informazioni rimosse")
	state.changed.emit()
	_refresh()


## Il segnalino Informazioni che si piazza una volta per scenario: il B-Dienst
## tedesco di BL1 e il Bletchley Park britannico di A1 sono la stessa facolta'
## con le parti scambiate, e il nome lo dice il dato di scenario. La regola sta
## nel core; qui c'e' solo la scelta del segmento, che e' del giocatore.
func _intel_marker_label() -> String:
	if state.solo_intel_marker_once.is_empty():
		return "Segnalino Informazioni"
	return SoloAI.intel_marker_label(state)


func _intel_marker_detail() -> String:
	if state.solo_intel_marker_once.is_empty():
		return "questo scenario non lo prevede"
	if bool(state.solo_counters.get("intel_marker_once_used", false)):
		return "gia' usato: vale una volta sola per scenario"
	if state.initiative != SoloAI.intel_marker_side(state):
		return "serve l'Iniziativa di %s" % Initiative.side_name(
			SoloAI.intel_marker_side(state))
	return "un segnalino Informazioni su una Traiettoria avversaria"


func _do_intel_marker() -> void:
	var label := _intel_marker_label()
	if not SoloAI.intel_marker_available(state):
		_msg("%s: %s." % [label, _intel_marker_detail()])
		return
	var candidates := SoloAI.intel_marker_targets(state)
	if candidates.is_empty():
		_msg("%s: nessuna Traiettoria avversaria ha un segmento libero da "
			% label + "segnalini Informazioni.")
		return
	var tf := await _pick_tf(candidates, "%s - quale Traiettoria?" % label,
		"Solo Traiettorie avversarie con almeno un segmento senza Informazioni.",
		true)
	if tf == null:
		return
	var free_hexes: Array = []
	for seg_v: Variant in tf.trajectory.segments:
		var seg: Dictionary = seg_v
		if not bool(seg["info"]):
			free_hexes.append(seg["hex"])
	var picked := await _pick_hex_on_map(free_hexes,
		"%s: scegli il segmento di %s su cui mettere il segnalino Informazioni. "
			% [label, tf.display_name()] + "ESC annulla.")
	if picked == Vector2i.MAX:
		return
	var applied := SoloAI.intel_marker_apply(state, tf, picked)
	for line_v: Variant in applied.get("log", []):
		_msg(String(line_v))
	if bool(applied.get("ok", false)):
		log.record(label)
		state.changed.emit()
		_refresh()


func _solo_phase_label() -> String:
	if state.solo_phase == SoloOpponent.Phase.LATE:
		return "Tardi" + (" - " + state.solo_phase_reason
			if state.solo_phase_reason != "" else "")
	return "Presto"


## Quale riga della Tabella Azioni: e' una regola stampata e sta nel core
## (`SoloOpponent.action_row_selector`), non qui. La vista si limita a chiedere.
func _solo_selector_for(table_id: String) -> int:
	if solo == null:
		return state.convoys_completed
	return solo.action_row_selector(state, _solo_player_side(), table_id)


func _solo_selector_label(table_id: String) -> String:
	if solo == null:
		return "%d Completamenti riusciti" % state.convoys_completed
	return solo.action_row_selector_label(state, _solo_player_side(), table_id)


func _solo_player_side() -> int:
	if victory != null and victory.mode == Victory.Mode.DEBRIEFING:
		return victory.solo_side
	return -1


func _solo_imaginary_side() -> int:
	var player_side := _solo_player_side()
	if player_side < 0:
		return -1
	return 1 - player_side


func _solo_is_imaginary_turn() -> bool:
	var imaginary := _solo_imaginary_side()
	return solo != null and not state.solo_ended and imaginary >= 0 \
		and state.initiative == imaginary


func _maybe_run_solo_opponent_turn(reason: String = "") -> void:
	if not _solo_is_imaginary_turn():
		return
	if reason != "":
		_msg("Solitario: l'Iniziativa e' dell'avversario immaginario (%s)."
			% reason)
	await _solo_roll_action(true)


func _kick_solo_opponent_turn(reason: String = "") -> void:
	await _maybe_run_solo_opponent_turn(reason)


func _solo_modifiers(t: SoloTable) -> Array:
	var active: Array = []
	while true:
		var opts: Array = []
		for m in t.modifiers:
			var label := String(m["label"])
			opts.append({"label": "%s %s" % ["[x]" if active.has(label) else "[ ]", label],
				"detail": "%+d" % int(m["value"])})
		opts.append({"label": "Tira", "detail": "modificatore totale %+d" % t.modifier_total(active)})
		var i: int = await Choice.ask(self, "Modificatori",
			"Attiva solo le condizioni vere adesso.", opts)
		if i < 0:
			return []
		if i >= t.modifiers.size():
			return active
		var label := String((t.modifiers[i] as Dictionary)["label"])
		if active.has(label):
			active.erase(label)
		else:
			active.append(label)
	return active


func _solo_roll_action(auto: bool = false) -> void:
	if solo == null:
		return
	if state.solo_ended:
		if not auto:
			_msg("Solitario: lo scenario e' terminato. Apri Punteggio per il Debriefing.")
		return
	solo.set_phase(state.solo_phase, state.solo_phase_reason)
	var tid := solo.action_table_id()
	var t := solo.table(tid)
	if t == null:
		_msg("Solitario: lo scenario non ha una Tabella delle Azioni.")
		return
	if auto:
		_bot_trace_serial += 1
		_active_bot_trace = _bot_trace_serial
		_msg("Solitario: tiro automatico della Tabella delle Azioni. "
			+ "L'AI applica la procedura senza aprire scelte manuali.")
	var mods: Array = []
	if auto:
		var inferred := SoloAI.automatic_modifiers(t, state, _solo_imaginary_side())
		mods = inferred["active"]
		for line_v: Variant in inferred["explanations"]:
			_msg("  Modificatore automatico: %s" % String(line_v))
		for line_v: Variant in inferred["unresolved"]:
			_msg("  Dato non modellato, modificatore non applicato: %s" % String(line_v))
	else:
		mods = await _solo_modifiers(t)
	var result := solo.act(state.rng, _solo_selector_for(tid), mods)
	state.set_modifier_track(_solo_imaginary_side(), int(result.get("modifier", 0)))
	_msg("Solitario - %s (%s)" % [t.title, _solo_selector_label(tid)])
	for line in SoloTable.describe(result).split("\n"):
		_msg("  " + line)
	log.record("Solitario: %s" % String(result.get("code", "")))
	var bot_summary := await _apply_solo_ai_result(result)
	if auto:
		_last_bot_summary = bot_summary
		_msg("BOT - %s" % bot_summary)
		_active_bot_trace = 0
	state.changed.emit()


func _apply_solo_ai_result(result: Dictionary) -> String:
	var imaginary := _solo_imaginary_side()
	if imaginary < 0:
		return "nessuna parte avversaria configurata."
	if String(result.get("code", "")).to_upper() == "I":
		_solo_maybe_go_late("result_i", "la Tabella Azioni ha dato I")
	var decision := SoloAI.execute_code(String(result.get("code", "")),
		state, graph, engine, _port_control(), imaginary)
	return await _apply_solo_ai_decision(result, decision)


func _apply_solo_ai_decision(result: Dictionary, decision: Dictionary) -> String:
	var imaginary := _solo_imaginary_side()
	if imaginary < 0:
		return "nessuna parte avversaria configurata."
	for line_v: Variant in decision.get("log", []):
		_msg(String(line_v))
	var code := String(result.get("code", "?"))
	var summary := "risultato %s; nessun effetto applicato." % code
	# Una decisione che non applica niente non puo' lasciare l'Iniziativa al
	# bot: resterebbe Attivo senza nessuna procedura accodata, e la partita
	# aspetterebbe un giocatore che non deve muovere. Nel motore headless si
	# vedeva come un turno senza tiri; qui non si vedrebbe affatto, perche' non
	# c'e' niente da mostrare.
	if SoloSequence.must_yield_initiative(decision):
		_msg("Solitario AI: risultato %s senza effetto applicabile; cede l'Iniziativa."
			% code)
		var idle_player := _solo_player_side()
		if idle_player >= 0:
			_change_initiative_to(idle_player)
		return "risultato %s: nessun effetto applicabile; l'Iniziativa passa al giocatore." % code
	if SoloSequence.branch_of(decision) == SoloSequence.Branch.COMPLETION:
		if await _offer_steal_initiative("Completamento del bot"):
			_msg("Solitario AI: Completamento impedito dal cambio d'Iniziativa.")
			await _solo_time_lapse(decision.get("active", null),
				decision.get("target_hex", Vector2i.MAX))
			return "risultato %s: Completamento impedito; l'Iniziativa e' cambiata." % code
		var comp := Completion.resolve(decision["active"], decision["completion_port"], vp_tracker)
		for line_v2: Variant in comp.get("log", []):
			_msg(String(line_v2))
		log.record("Solitario AI: Completamento")
		_show_completed_notice(decision["active"], comp, "BOT")
		summary = "risultato %s: %s ha Completato a %s." % [code,
			(decision["active"] as TaskForce).display_name(),
			String((comp.get("port", {}) as Dictionary).get("name", "un porto"))]
		state.changed.emit()
		_queue_next_solo_action("dopo il Completamento")
	elif SoloSequence.branch_of(decision) == SoloSequence.Branch.ACTION:
		summary = "risultato %s: %s" % [code, await _resolve_solo_ai_action(decision)]
	elif SoloSequence.branch_of(decision) == SoloSequence.Branch.EFFECT:
		log.record("Solitario AI: %s" % String(decision.get("turn_kind", "effetto")))
		state.changed.emit()
		if SoloSequence.effect_needs_time_lapse_before_pass(decision):
			_msg("Solitario AI: il Completamento e' impossibile; esegue Passare e Scorrere del Tempo.")
			await _solo_time_lapse(decision.get("active", null))
		if SoloSequence.effect_rolls_again(decision):
			_queue_next_solo_action("la tabella ordina un altro tiro")
		elif SoloSequence.effect_is_trajectory(decision):
			await _solo_time_lapse(decision.get("active", null),
				decision.get("target_hex", Vector2i.MAX))
			if not await _offer_steal_initiative("Traiettoria del bot"):
				if SoloSequence.has_follow_up(decision):
					_msg("Solitario AI: continua la procedura prescritta senza ritirare la Tabella.")
					var next := SoloAI.continue_follow_up(decision, state, graph,
						engine, _port_control(), imaginary)
					summary = await _apply_solo_ai_decision(result, next)
				else:
					_queue_next_solo_action("il bot mantiene l'Iniziativa")
		var decision_log: Array = decision.get("log", [])
		if not decision_log.is_empty() and summary.begins_with("risultato %s;" % code):
			summary = "risultato %s: %s" % [code, String(decision_log[-1])]
	if bool(decision.get("pass_initiative", false)) and _solo_is_imaginary_turn():
		var player := _solo_player_side()
		if player >= 0:
			_change_initiative_to(player)
			summary += " L'Iniziativa passa al giocatore."
	return summary


func _show_solo_event(result: Dictionary, decision: Dictionary,
		actor: String = "BOT") -> void:
	if _solo_event_panel == null:
		return
	_solo_event_serial += 1
	var serial := _solo_event_serial
	var title := String(result.get("code", "?"))
	var table_name := String(result.get("table", "Tabella Solitario"))
	var lines: Array[String] = ["[b]%s - %s: risultato %s[/b]" % [actor, table_name, title]]
	var row := String(result.get("row_label", ""))
	if row != "":
		lines.append("Riga: %s; dado %d -> colonna %d." % [row,
			int(result.get("roll", 0)), int(result.get("column", 0))])
	var active: TaskForce = decision.get("active", null)
	var target: TaskForce = decision.get("target", null)
	if active != null:
		lines.append("Scelta: %s%s." % [active.display_name(),
			" contro " + target.display_name() if target != null else ""])
	var decision_log: Array = decision.get("log", [])
	if not decision_log.is_empty():
		lines.append(String(decision_log[-1]))
	_lbl_solo_event.text = "\n".join(lines)
	_solo_event_panel.visible = true
	var focus: Vector2i = decision.get("target_hex", Vector2i.MAX)
	if focus == Vector2i.MAX and active != null:
		focus = active.trajectory.station_hex if active.trajectory.is_station() \
			else active.trajectory.end_hex(0)
	if focus != Vector2i.MAX and graph.is_playable(focus):
		cam.focus_on(graph.center_of(focus))
		if not _hex_choice_active:
			board.set_highlight({focus: Color(1.0, 0.55, 0.12, 0.42)})
	await get_tree().create_timer(7.0).timeout
	if serial != _solo_event_serial:
		return
	_solo_event_panel.visible = false
	if not _hex_choice_active:
		board.set_highlight({})


func _show_completed_notice(tf: TaskForce, result: Dictionary,
		actor: String = "Giocatore") -> void:
	var port := String((result.get("port", {}) as Dictionary).get("name", "porto"))
	var ships: Array = result.get("ships", [])
	var manifest := ", ".join(ships) if not ships.is_empty() \
		else "composizione non identificata"
	_msg(("%s - %s ha Completato a %s: %s lascia la mappa e resta nel registro "
		+ "delle TF uscite.") % [actor, tf.display_name(), port, manifest])


func _resolve_solo_ai_action(decision: Dictionary) -> String:
	var key := String(decision.get("action_key", ""))
	var dec := SoloSequence.declaration_for(decision)
	if dec == null:
		return "azione incompleta: manca la TF attiva o il bersaglio."
	var active := dec.active
	var target := dec.target
	# RB p.41: l'Attacco Furtivo puo' essere eseguito dalla forza Furtiva, e
	# allora una TF Attiva non c'e'. Ogni riga che la nominava deve saperlo.
	var actor_name := active.display_name() if active != null \
		else "la forza Furtiva %s" % Stealth.kind_name(
			int(dec.active_stealth.get("kind", -1)))
	if not dec.active_stealth.is_empty():
		_msg("Solitario AI: l'azione la esegue %s (Totale Traiettoria zero, RB p.41)."
			% actor_name)
	if dec.active_coordinating != null:
		_msg("Solitario AI: %s coordina l'azione."
			% dec.active_coordinating.display_name())
	if key == "AIR_STRIKE" and active != null:
		traj_layer.set_air_action_markers(active.side, dec.launch_hex, dec.target_hex)
		await get_tree().create_timer(0.55).timeout
	var res := engine.resolve(dec, state)
	var label := String(engine.action(key).get("label", key))
	if not res["ok"]:
		_msg("Solitario AI - %s: %s" % [label, String(res["error"])])
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		return "%s non eseguito: %s" % [label, String(res["error"])]
	_msg("Solitario AI - %s -> %s" % [label, engine.describe(res)])
	if _action_canceled_by_interruption(res):
		_msg("Solitario AI: azione annullata da Interruzione.")
		log.record("Solitario AI: %s annullata" % label)
		state.changed.emit()
		await _handle_interruption_cancel(res, dec)
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		if _solo_is_imaginary_turn():
			_queue_next_solo_action("dopo l'Interruzione")
		return "%s di %s contro %s annullato da Interruzione." % [label,
			actor_name, target.display_name()]
	var pending_battle := Results.Battle.NONE
	var initiative_changes := false
	var applied_texts: Array[String] = []
	for code_v: Variant in res["results"] as Array:
		var code := String(code_v)
		var applied := Results.apply(code, active, target, dec.target_hex, state)
		_msg("    %s" % applied["text"])
		applied_texts.append(String(applied["text"]))
		if bool(applied.get("initiative_changes", false)):
			initiative_changes = true
		if applied["battle"] != Results.Battle.NONE:
			pending_battle = applied["battle"]
	_report_eliminated_forces("Solitario AI - %s" % label)
	log.record("Solitario AI: %s" % label)
	state.changed.emit()
	var late_event := SoloSequence.late_event_for_action(key)
	if late_event != "":
		_solo_maybe_go_late(late_event, "il bot ha eseguito %s" % label)
	if pending_battle != Results.Battle.NONE \
			and not await _prepare_solo_battle(active, target):
		pending_battle = Results.Battle.NONE
	if pending_battle != Results.Battle.NONE:
		_solo_maybe_go_late("battle", "un risultato del bot ha aperto una Battaglia")
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		_open_battle(pending_battle, active, target, dec.target_hex)
	else:
		if bool(engine.action(key).get("causes_time_lapse", false)):
			# Con un attaccante Furtivo non c'e' nessuna Traiettoria designata da
			# accorciare, e `active` nullo fa uscire subito la funzione.
			await _solo_time_lapse(active,
				decision.get("time_lapse_goal", dec.target_hex),
				dec.launch_hex if key == "AIR_STRIKE" else Vector2i.MAX,
				bool(decision.get("time_lapse_prefer_near", false)))
		if key == "AIR_STRIKE":
			traj_layer.clear_air_action_markers()
		match SoloSequence.after_action(key, initiative_changes):
			SoloSequence.AfterAction.CHANGE:
				# RB p.53: qui l'Iniziativa CAMBIA, non si Cerca. Questo ramo
				# mancava del tutto nel percorso del bot: il risultato Mancato
				# con Informazioni faceva tirare per Cercarla, e il Conto
				# dell'Iniziativa si comportava in modo diverso da quello del
				# percorso del giocatore, che la regola la applicava.
				if _change_initiative_to(1 - dec.acting_side()) \
						and _solo_is_imaginary_turn():
					_queue_next_solo_action("l'Iniziativa e' cambiata")
			SoloSequence.AfterAction.OFFER_STEAL:
				if not await _offer_steal_initiative("Ricerca Navale del bot"):
					_queue_next_solo_action("il bot mantiene l'Iniziativa")
			_:
				var changed := _seek_initiative()
				if not changed and _solo_is_imaginary_turn():
					_queue_next_solo_action("il bot vince la ricerca dell'Iniziativa")
	var outcome := "; ".join(applied_texts)
	if pending_battle != Results.Battle.NONE:
		outcome = "apre una Battaglia" if outcome == "" else outcome + "; apre una Battaglia"
	if outcome == "":
		outcome = engine.describe(res)
	return "%s con %s contro %s. Esito: %s" % [label,
		actor_name, target.display_name(), outcome]


func _queue_next_solo_action(reason: String) -> void:
	# Alcune procedure concludono lo scenario e, nello stesso frame, tentano di
	# accodare il tiro successivo. La fine va applicata qui, prima del deferred:
	# aspettare il refresh lascia partire un'intera azione oltre la fine.
	if SoloAI.enforce_scenario_end(state):
		_msg("Solitario - FINE SCENARIO: %s" % state.solo_end_reason)
		return
	if state.solo_ended:
		return
	if _solo_is_imaginary_turn():
		call_deferred("_kick_solo_opponent_turn", reason)


## Lo Scorrere del Tempo del bot usa una scelta deterministica: rimuove dal
## capo piu' lontano dall'obiettivo dichiarato dalla procedura. Se la TF
## diventa Stazione, sceglie fra gli esagoni liberati quello piu' vicino alla
## destinazione. Sono decisioni del bot, quindi non aprono dialoghi umani.
func _solo_time_lapse(tf: TaskForce, goal: Vector2i = Vector2i.MAX,
		protected_hex: Vector2i = Vector2i.MAX,
		prefer_near: bool = false) -> void:
	if tf == null or tf.trajectory.is_station():
		return
	var amount := TimeLapse.required_removal(tf.speed, state.weather, state.rng)
	var opts := TimeLapse.removal_options(tf.trajectory, tf.speed, amount,
		protected_hex)
	if opts.is_empty():
		_msg("Solitario AI - Scorrere del Tempo: nessuna rimozione legale.")
		return
	# La preferenza stampata dalla procedura sta in `SoloSequence`: e' una
	# regola, e qui ne serve la stessa lettura del ciclo headless.
	var chosen: Dictionary = opts[SoloSequence.time_lapse_preference(
		opts, tf.trajectory, goal, prefer_near)]
	var freed := TimeLapse.apply(tf.trajectory, chosen)
	var station_note := ""
	if tf.trajectory.length() == 0 and not freed.is_empty():
		var station := freed[0]
		if protected_hex != Vector2i.MAX and freed.has(protected_hex):
			station = protected_hex
		elif goal != Vector2i.MAX:
			for h in freed:
				if Hex.distance(h, goal) < Hex.distance(station, goal):
					station = h
		tf.trajectory.become_station(station)
		station_note = "; Stazione in %s" % str(station)
	_msg("Solitario AI - Scorrere del Tempo: %s rimuove %s%s."
		% [tf.display_name(), String(chosen["label"]), station_note])
	state.changed.emit()


func _solo_roll_any_table() -> void:
	var keys: Array[String] = []
	var opts: Array = []
	for k_v: Variant in solo.tables.keys():
		var k := String(k_v)
		var t: SoloTable = solo.table(k)
		keys.append(k)
		opts.append({"label": t.title if t.title != "" else k,
			"detail": k})
	var i: int = await Choice.ask(self, "Tabella solitario",
		"Quale tabella vuoi leggere?", opts)
	if i < 0:
		return
	var t: SoloTable = solo.table(keys[i])
	var selector := _solo_selector_for(keys[i])
	if t.rows.size() > 1 and not keys[i].begins_with("actions"):
		var rows: Array = []
		for r in t.rows:
			rows.append({"label": String(r["label"]), "detail": ""})
		var j: int = await Choice.ask(self, "Riga della tabella",
			"Per questa tabella scegli la riga stampata applicabile.", rows)
		if j < 0:
			return
		selector = int((t.rows[j] as Dictionary)["min"])
	var mods := await _solo_modifiers(t)
	var result := t.roll_and_read(state.rng, selector, mods)
	state.set_modifier_track(_solo_imaginary_side(), int(result.get("modifier", 0)))
	_msg("Solitario - %s" % (t.title if t.title != "" else keys[i]))
	for line in SoloTable.describe(result).split("\n"):
		_msg("  " + line)
	log.record("Solitario: %s" % String(result.get("code", "")))
	if ["actions", "actions_early", "actions_late", "british_actions"].has(keys[i]):
		await _apply_solo_ai_result(result)
	else:
		await _apply_solo_table_result(keys[i], result, selected_tf)
	state.changed.emit()


func _solo_identify_detail() -> String:
	if selected_tf == null:
		return "nessuna TF selezionata"
	if not selected_tf.unidentified:
		return "%s e' gia' identificata" % selected_tf.display_name()
	return selected_tf.display_name()


func _solo_identify_selected() -> void:
	if selected_tf == null:
		_msg("Solitario: nessuna TF selezionata.")
		return
	var result := solo.identify(state.rng, selected_tf)
	_msg("Solitario - Identificare la TF")
	for line in SoloTable.describe(result).split("\n"):
		_msg("  " + line)
	var t := solo.table("identify")
	if t != null and t.note != "":
		_msg("  Nota: %s" % t.note)
	if bool(result.get("ok", false)):
		var applied := await _apply_solo_table_result("identify", result, selected_tf)
		if not bool(applied.get("ok", false)):
			_msg("  Aggiungi le navi indicate manualmente: il motore non sceglie sostituzioni non stampate.")
	log.record("Solitario: identificazione")
	state.changed.emit()


func _apply_solo_table_result(table_id: String, result: Dictionary,
		subject: TaskForce = null) -> Dictionary:
	var imaginary := _solo_imaginary_side()
	var decision := SoloAI.apply_table_result(table_id, result, state, graph, engine,
		_port_control(), imaginary, subject)
	for line_v: Variant in decision.get("log", []):
		var line := String(line_v)
		if line != "":
			_msg("  " + line)
	if bool(decision.get("ok", false)):
		log.record("Solitario AI: %s" % table_id)
		_resync_selection()
		_refresh()
	if String(decision.get("initiative", "")) == "vie":
		if _seek_initiative():
			await _maybe_run_solo_opponent_turn("Tabella solitario")
	return decision


func _kick_bl1_fueling_check() -> void:
	await _maybe_run_bl1_fueling()


## BL1 p.6: il controllo non e' una scelta del giocatore. Appena le condizioni
## esistono, l'app tira la riga del meteo, applica l'effetto e mostra il luogo.
func _maybe_run_bl1_fueling() -> bool:
	if _bl1_fueling_running or solo == null:
		return false
	var candidates := SoloAI.bl1_fueling_candidates(state)
	if candidates.is_empty():
		return false
	var table := solo.table("fueling")
	if table == null:
		_msg("BL1: manca la Tabella del Rifornimento; controllo non risolto.")
		return false
	_bl1_fueling_running = true
	var resolved := false
	while not candidates.is_empty():
		var tf: TaskForce = candidates[0]
		var h := tf.trajectory.station_hex
		var result := table.roll_and_read(state.rng, state.weather, [])
		state.set_modifier_track(TaskForce.Side.KRIEGSMARINE,
			int(result.get("modifier", 0)))
		_msg("BL1 - Controllo Rifornimento obbligatorio: %s e' una Stazione sul marker RV in %s."
			% [tf.display_name(), str(h)])
		for line in SoloTable.describe(result).split("\n"):
			_msg("  " + line)
		var decision := await _apply_solo_table_result("fueling", result, tf)
		decision["active"] = tf
		decision["target_hex"] = h
		_show_solo_event(result, decision, "RIFORNIMENTO")
		resolved = bool(decision.get("ok", false)) or resolved
		if not bool(decision.get("ok", false)):
			break
		candidates = SoloAI.bl1_fueling_candidates(state)
	_bl1_fueling_running = false
	state.changed.emit()
	return resolved


func _solo_go_late() -> void:
	if state.solo_phase == SoloOpponent.Phase.LATE:
		_msg("Solitario: la tabella Tardi e' gia' attiva.")
		return
	var opts: Array = [
		{"label": "c'e' stata una Battaglia", "detail": ""},
		{"label": "un Convoglio e' stato distrutto", "detail": ""},
		{"label": "qualcuno ha eseguito un Attacco Aereo", "detail": ""},
		{"label": "istruzione dello scenario", "detail": ""},
	]
	var i: int = await Choice.ask(self, "Solitario - tabella Tardi",
		"Il passaggio e' permanente e finisce nel salvataggio.", opts)
	if i < 0:
		return
	state.solo_phase = SoloOpponent.Phase.LATE
	state.solo_phase_reason = String(opts[i]["label"])
	solo.set_phase(state.solo_phase, state.solo_phase_reason)
	_msg("Solitario: passa a Tardi (%s)." % state.solo_phase_reason)
	log.record("Solitario: Tardi")
	state.changed.emit()


func _solo_create_unidentified_tf() -> void:
	var side := await _pick_side("Solitario - parte della nuova TF")
	if side < 0:
		return
	var port := await _pick_port("Solitario - porto iniziale")
	if port.is_empty():
		return
	var h := graph.port_hex(port)
	if h == Vector2i.MAX:
		_msg("Solitario: porto non calibrato sulla mappa: %s" % port)
		return
	var tf := TaskForce.new(0, side)
	tf.unidentified = true
	tf.color = _solo_color_for(side)
	tf.slot = _solo_next_slot(tf.color)
	tf.name = "%s non identificata %d" % [
		"KM" if side == TaskForce.Side.KRIEGSMARINE else "RN", tf.slot]
	tf.trajectory.become_station(h)
	tf.trajectory.station_port = port
	tf.recompute_speed()
	state.add_task_force(tf)
	selected_tf = tf
	traj_layer.selected_tf_id = tf.id
	_msg("Solitario: creata %s in %s (%s)." % [tf.display_name(), port, str(h)])
	log.record("Solitario: nuova TF non identificata")
	state.changed.emit()


func _pick_side(title: String) -> int:
	var i: int = await Choice.ask(self, title, "Scegli la parte.",
		[{"label": "Kriegsmarine", "detail": ""},
			{"label": "Royal Navy", "detail": ""}])
	return i if i >= 0 else -1


func _pick_port(title: String) -> String:
	var names: Array[String] = []
	for k_v: Variant in graph.ports.keys():
		names.append(String(k_v))
	names.sort()
	var opts: Array = []
	for p in names:
		var h := graph.port_hex(p)
		opts.append({"label": p, "detail": str(h)})
	var i: int = await Choice.ask(self, title, "Scegli un porto gia' calibrato sulla mappa.", opts)
	return names[i] if i >= 0 else ""


func _solo_color_for(side: int) -> String:
	return "GE" if side == TaskForce.Side.KRIEGSMARINE else "Brown"


func _solo_next_slot(color: String) -> int:
	var slot := 0
	for tf in state.task_forces:
		if tf.color == color:
			slot = maxi(slot, tf.slot + 1)
	return slot


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
		if _report_initiative(Initiative.pass_to_inactive(state)):
			await _maybe_run_solo_opponent_turn("Rinforzi falliti")
		return true
	if bool(r["success"]):
		var leaders := scenario.reinforcement_leaders()
		if leaders.has(keys[i]):
			var reinforced_tf: TaskForce = r.get("tf", null)
			if reinforced_tf != null:
				reinforced_tf.leader = String(leaders[keys[i]])
				_msg("%s entra assegnato a %s."
					% [reinforced_tf.leader, reinforced_tf.display_name()])
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


## Le quattro coppie Presto/Tardi non hanno lo stesso innesco. Questi sono gli
## eventi stampati in AC Solo scenarios 2022 pp.10, 13, 18 e 22.
func _solo_maybe_go_late(event: String, reason: String) -> bool:
	if solo == null or state.solo_phase == SoloOpponent.Phase.LATE:
		return false
	if not solo.goes_late_after(event):
		return false
	state.solo_phase = SoloOpponent.Phase.LATE
	state.solo_phase_reason = reason
	solo.set_phase(state.solo_phase, state.solo_phase_reason)
	_msg("Solitario: passa automaticamente alla tabella Tardi: %s." % reason)
	state.changed.emit()
	return true


func _bl2_neutral_incident_required(action_key: String, active: TaskForce,
		target_hex: Vector2i) -> bool:
	if scenario == null or scenario.id != "BL2 Contain and Destroy" \
			or active == null or active.side != TaskForce.Side.ROYAL_NAVY \
			or not ["ENGAGE", "AIR_STRIKE"].has(action_key):
		return false
	return SoloAI.bl2_is_neutral_water(scenario.rules(), target_hex)


func _maybe_bl2_neutral_incident(action_key: String, active: TaskForce,
		target_hex: Vector2i) -> void:
	if _bl2_neutral_incident_required(action_key, active, target_hex):
		await _roll_bl2_international_incident()


## BL2 p.11: si tira dopo aver risolto Ingaggiare/Battaglia o Attacco Aereo.
func _roll_bl2_international_incident() -> void:
	if solo == null or not solo.has("incident"):
		_msg("BL2: Incidente Internazionale richiesto, ma tabella non disponibile.")
		return
	var table: SoloTable = solo.table("incident")
	var result := table.roll_and_read(state.rng, 0)
	_msg("Solitario - Incidente Internazionale nelle Acque Neutrali")
	for line in SoloTable.describe(result).split("\n"):
		_msg("  " + line)
	await _apply_solo_table_result("incident", result)
	log.record("BL2: Incidente Internazionale")


## Segnalazione (RB p.39): una Traiettoria nemica con un segnalino Informazioni
## collassa in una Stazione.
func _do_signal() -> void:
	if selected_tf == null:
		return
	var active := selected_tf
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
	if active != null and state.task_force(active.id) != null \
			and not active.trajectory.is_station() and active.trajectory.occupies(at):
		var opts2: Array = [
			{"label": "Scorrere del Tempo", "detail": "la TF Attiva e' nell'esagono segnalato"},
			{"label": "No", "detail": "non effettua Scorrere del Tempo adesso"},
		]
		var j: int = await Choice.ask(self, "Segnalazione - TF Attiva",
			"La TF Attiva si trova nell'esagono bersaglio: puo' effettuare Scorrere del Tempo.",
			opts2)
		if j == 0:
			await _do_time_lapse_for(active)
	if await _offer_steal_initiative("Segnalazione"):
		await _maybe_run_solo_opponent_turn("Segnalazione")


## Completamento (RB p.29): le navi entrano in porto e lasciano il gioco.
## Se la Task Force tocca piu' di un porto amico, la scelta e' del giocatore.
## Sbarco in Norvegia, se lo scenario e la posizione lo permettono. Ritorna vero
## se ha gestito l'azione: il chiamante allora non prova il Completamento in
## porto.
##
## L'offerta e' esplicita e si puo' rifiutare, perche' le due azioni portano a
## esiti diversi e la scelta e' del giocatore: sbarcare tiene la Task Force in
## gioco, entrare in porto la toglie.
func _try_norway_completion() -> bool:
	if selected_tf == null or not scenario.id.begins_with("N"):
		return false
	var h := selected_tf.trajectory.station_hex if selected_tf.trajectory.is_station() \
		else Vector2i.MAX
	if h == Vector2i.MAX:
		return false
	if not Norway.can_complete(graph, selected_tf, h):
		return false
	var targets: Array = scenario.mines_targets()
	var lays_mines := not targets.is_empty() \
		and Stealth.can_lay_mines(state, targets, selected_tf, h)
	var detail := "La Task Force resta in gioco e fa Scorrere del Tempo."
	if lays_mines:
		detail += " Posa anche le Mine in questo esagono."
	var pick: int = await Choice.ask(self, "Completamento in Norvegia",
		"%s puo' sbarcare qui invece di entrare in porto. %s"
			% [selected_tf.display_name(), detail],
		[{"label": "Sbarca in Norvegia", "detail": detail},
			{"label": "No, cerca un porto",
				"detail": "Completamento normale: la Task Force esce di scena."}])
	if pick != 0:
		return false

	var acting := selected_tf
	if await _offer_steal_initiative("Completamento in Norvegia"):
		_msg("Sbarco impedito: l'Inattivo ha preso l'Iniziativa.")
		await _do_time_lapse_for(acting)
		await _maybe_run_solo_opponent_turn("Sbarco impedito")
		return true

	var done := Norway.complete(state, graph, acting, h, false)
	for line_v: Variant in done.get("log", []):
		_msg(String(line_v))
	if not bool(done.get("ok", false)):
		return true
	if lays_mines:
		var mines := Stealth.lay_mines(state, targets, acting, h)
		for line_v: Variant in mines.get("log", []):
			_msg(String(line_v))
	if bool(done.get("check_reaction", false)):
		var reaction := Norway.roll_reaction(state, graph, state.rng, scenario.id,
			acting, h)
		if bool(reaction.get("ok", false)):
			for line_v: Variant in reaction.get("log", []):
				_msg(String(line_v))
			var applied := Norway.apply_reaction(state, reaction, acting)
			for line_v: Variant in applied.get("log", []):
				_msg(String(line_v))
			if int(applied.get("initiative_to", -1)) >= 0:
				state.initiative = int(applied["initiative_to"])
				_msg("L'Iniziativa passa a %s." % Initiative.side_name(state.initiative))
		else:
			_msg("Reazione Norvegese non tirata: %s" % String(reaction.get("reason", "")))
	if bool(done.get("time_lapse", false)):
		await _do_time_lapse_for(acting)
	_refresh()
	await _maybe_run_solo_opponent_turn("Sbarco in Norvegia")
	return true


func _do_completion() -> void:
	# Negli scenari 'N' un Completamento puo' essere uno SBARCO IN NORVEGIA, che
	# e' un'altra cosa: serve un Convoglio o uno Squadrone DD, la Task Force NON
	# esce di scena, e dopo si tira la Reazione Norvegese (fascicolo p.16).
	if await _try_norway_completion():
		return
	var opts := Completion.port_options(selected_tf, graph, _port_control())
	if opts.is_empty():
		_msg("Completamento: nessun porto amico raggiunto")
		return

	var completing_tf := selected_tf
	if await _offer_steal_initiative("Completamento"):
		_msg("Completamento fallito: l'Inattivo ha preso l'Iniziativa.")
		await _do_time_lapse_for(completing_tf)
		await _maybe_run_solo_opponent_turn("Completamento impedito")
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
	_show_completed_notice(selected_tf, res)
	# Completion cambia la TF in un record storico fuori mappa. Senza questo
	# segnale il renderer conservava la linea gia' disegnata fino alla mossa
	# successiva, anche se il core l'aveva correttamente marcata completed.
	state.changed.emit()
	_select_first_initiative_force()
	_refresh()


## Passare (RB p.35): si designa una propria Traiettoria che effettua lo
## Scorrere del Tempo, poi l'Iniziativa passa all'avversario e il conteggio
## torna a zero. E' l'unica azione che si dichiara per cedere il turno.
func _do_pass() -> void:
	var pass_all_name := LeaderRules.pass_all_commander(state, state.initiative)
	var pass_all := false
	if pass_all_name != "":
		var options: Array = [
			{"label": "Passare con %s" % selected_tf.display_name(),
				"detail": "Scorrere del Tempo solo per la TF selezionata"},
			{"label": "Passare Tutto - %s" % pass_all_name,
				"detail": "Tutte le TF effettuano Scorrere del Tempo; restano %d utilizzi"
					% LeaderRules.uses_left(state, pass_all_name)},
		]
		var choice: int = await Choice.ask(self, "Passare",
			"Scegli nel pannello come usare l'azione.", options)
		if choice < 0:
			_msg("Passare annullato.")
			return
		pass_all = choice == 1
	if pass_all:
		for tf in state.forces_of(state.initiative):
			if not tf.trajectory.is_station():
				await _do_time_lapse_for(tf, false)
			else:
				_msg("Passare Tutto: %s e' gia' una Stazione." % tf.display_name())
		LeaderRules.spend(state, pass_all_name)
		_msg("%s usa Passare Tutto; utilizzi rimasti: %d."
			% [pass_all_name, LeaderRules.uses_left(state, pass_all_name)])
	else:
		if not selected_tf.trajectory.is_station():
			await _do_time_lapse(false)
		else:
			_msg("%s e' gia' una Stazione: nessuno Scorrere del Tempo."
				% selected_tf.display_name())
	if _report_initiative(Initiative.pass_to_inactive(state)):
		await _maybe_run_solo_opponent_turn("Passare")
	_refresh()


func _do_time_lapse(allow_bl1_fueling: bool = true,
		protected_hex: Vector2i = Vector2i.MAX) -> void:
	if selected_tf == null:
		return
	if not _can_control_tf(selected_tf):
		_msg("Scorrere del Tempo: questa Task Force appartiene all'avversario immaginario.")
		return
	var traj := selected_tf.trajectory
	if traj.is_station():
		_msg("%s e' gia' una Stazione" % selected_tf.display_name())
		return
	var amount := TimeLapse.required_removal(selected_tf.speed, state.weather, state.rng)
	var opts := TimeLapse.removal_options(traj, selected_tf.speed, amount,
		protected_hex)
	if opts.is_empty():
		_msg("nessuna rimozione legale")
		return

	# RB p.19-20: la scelta e' del proprietario della Traiettoria, e conta:
	# invocare il Limite di Informazioni toglie un segnalino ma rimuove meno
	# segmenti. La decide il giocatore, non il codice.
	var chosen := await _pick_time_lapse_option(traj, opts, amount)
	if chosen.is_empty():
		_msg("Scorrere del Tempo annullato")
		return

	var freed := TimeLapse.apply(traj, chosen)
	var note := ""
	if traj.length() == 0 and not freed.is_empty():
		# RB p.14: la Stazione va in UNO QUALSIASI degli esagoni appena liberati
		var hex_choice := freed[0]
		if protected_hex != Vector2i.MAX and freed.has(protected_hex):
			hex_choice = protected_hex
			_msg("Attacco Aereo: la Stazione resta nel Punto di Lancio %s."
				% str(protected_hex))
		elif freed.size() > 1:
			var picked := await _pick_hex_on_map(freed,
				"Dove poni la Stazione? Clicca uno degli esagoni evidenziati.")
			if picked == Vector2i.MAX:
				_msg("Scelta annullata: Stazione nel primo esagono liberato.")
			else:
				hex_choice = picked
		traj.become_station(hex_choice)
		note = " -> diventa Stazione in %s" % str(hex_choice)
	_msg("Scorrere del Tempo (%s, meteo %s): richiesti %d, %s%s"
		% [TimeLapse.speed_label(selected_tf.speed),
			"cattivo" if state.weather == 1 else "buono",
			amount, chosen["label"], note])
	log.record("Scorrere del Tempo (%s)" % selected_tf.display_name())
	state.changed.emit()
	_refresh()
	if allow_bl1_fueling:
		await _maybe_run_bl1_fueling()


func _pick_time_lapse_option(traj: Trajectory, options: Array,
		amount: int) -> Dictionary:
	var candidates: Array = options.duplicate()
	var front := 0
	var back := 0
	var selected_marks := {}
	while not candidates.is_empty():
		var exact: Dictionary = {}
		var can_front := false
		var can_back := false
		for option_v: Variant in candidates:
			var option: Dictionary = option_v
			var ends: Array = option["ends"]
			if int(ends[0]) == front and int(ends[1]) == back:
				exact = option
			can_front = can_front or int(ends[0]) > front
			can_back = can_back or int(ends[1]) > back
		if not exact.is_empty() and not can_front and not can_back:
			return exact

		var clickable: Array = []
		var front_hex := Vector2i.MAX
		var back_hex := Vector2i.MAX
		if can_front:
			front_hex = traj.segments[front]["hex"] as Vector2i
			clickable.append(front_hex)
		if can_back:
			back_hex = traj.segments[traj.length() - 1 - back]["hex"] as Vector2i
			if not clickable.has(back_hex):
				clickable.append(back_hex)
		var prompt := ("Scorrere del Tempo: selezionati %d segmenti. "
			+ "Clicca un segmento terminale evidenziato; la scelta termina "
			+ "automaticamente quando la rimozione e' completa (richiesti %d).") \
			% [front + back, amount]
		var picked := await _pick_hex_on_map(clickable, prompt, selected_marks)
		if picked == Vector2i.MAX:
			return {}
		selected_marks[picked] = Color(1.0, 0.48, 0.16, 0.58)
		if picked == front_hex:
			front += 1
		elif picked == back_hex:
			back += 1
		var remaining: Array = []
		for option_v2: Variant in candidates:
			var ends2: Array = (option_v2 as Dictionary)["ends"]
			if int(ends2[0]) >= front and int(ends2[1]) >= back:
				remaining.append(option_v2)
		candidates = remaining
	return {}


func _pick_hex_on_map(hexes: Array, prompt: String,
		extra_highlights: Dictionary = {}) -> Vector2i:
	var highlights := {}
	for h_v: Variant in hexes:
		var h: Vector2i = h_v
		highlights[h] = Color(0.2, 0.95, 0.45, 0.36)
	_hex_choice_options = highlights.duplicate()
	for h_v: Variant in extra_highlights:
		highlights[h_v] = extra_highlights[h_v]
	_hex_choice_active = true
	_hex_choice_prompt = prompt
	board.set_highlight(highlights)
	_msg(prompt)
	_refresh()
	var picked: Vector2i = await _hex_choice_made
	_hex_choice_active = false
	_hex_choice_options.clear()
	_hex_choice_prompt = ""
	board.set_highlight({})
	_refresh()
	return picked


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
	board.selected_hex = h if graph.has_hex(h) else Vector2i.MAX
	board.queue_redraw()
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
	if mode != Mode.PLAY or selected_tf == null or not _trajectory_action_armed \
			or not graph.has_hex(h):
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
var _lbl_roster: RichTextLabel
var _tf_panel: PanelContainer
var _tf_info: RichTextLabel
var _tf_ships: HFlowContainer
var _log_panel: PanelContainer
var _log_toggle: Button
var _log_scroll: ScrollContainer
var _log_expanded: bool = true
var _log_rendered_message_seq: int = -1
var _tf_card_signature: String = ""
var _tf_panel_tf_id: int = -1

## Pannello "ora tocca a": chi sta agendo, cosa aspetta il gioco, e cosa NON si
## puo' fare con il motivo accanto.
var _lbl_now: RichTextLabel
var _status_choice_box: VBoxContainer
var _status_choice_title: Label
var _status_choice_detail: RichTextLabel
var _status_choice_buttons: FlowContainer
var _status_choice_active: bool = false
var _status_choice_option_count: int = 0
var _solo_event_panel: PanelContainer
var _lbl_solo_event: RichTextLabel
var _solo_event_serial: int = 0
var _help: PanelContainer
var _briefing_panel: PanelContainer
var _lbl_briefing_title: Label
var _lbl_briefing: RichTextLabel
var _bar: ActionBar
var _battle_layer: CanvasLayer
var _battle_view: BattleView


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	layer.layer = 10
	add_child(layer)

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	# Scheda della sola TF selezionata. Viene inserita piu' sotto, a destra del
	# pannello di stato, e sparisce quando si clicca sul mare.
	_tf_panel = PanelContainer.new()
	_tf_panel.custom_minimum_size = Vector2(560, 0)
	_tf_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tf_panel.size_flags_stretch_ratio = 0.75
	_tf_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_tf_panel.add_theme_stylebox_override("panel", _panel_style())
	_tf_panel.visible = false
	var tf_col := VBoxContainer.new()
	tf_col.add_theme_constant_override("separation", 7)
	_tf_panel.add_child(tf_col)
	_tf_info = RichTextLabel.new()
	_tf_info.bbcode_enabled = true
	_tf_info.fit_content = true
	_tf_info.custom_minimum_size = Vector2(0, 0)
	_tf_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tf_col.add_child(_tf_info)
	var ship_scroll := ScrollContainer.new()
	ship_scroll.custom_minimum_size = Vector2(0, 128)
	ship_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ship_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ship_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ship_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ship_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	tf_col.add_child(ship_scroll)
	_tf_ships = HFlowContainer.new()
	_tf_ships.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tf_ships.add_theme_constant_override("h_separation", 7)
	_tf_ships.add_theme_constant_override("v_separation", 7)
	ship_scroll.add_child(_tf_ships)

	# Il registro occupa una colonna richiudibile a destra. Il pulsante resta
	# sempre disponibile anche quando il testo e' nascosto.
	_log_panel = PanelContainer.new()
	_log_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_log_panel.offset_left = -410
	_log_panel.offset_right = -12
	_log_panel.offset_top = MAP_TOP
	_log_panel.offset_bottom = -MAP_BOTTOM
	_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_panel.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(_log_panel)
	var log_col := VBoxContainer.new()
	_log_panel.add_child(log_col)
	var log_header := HBoxContainer.new()
	log_header.add_theme_constant_override("separation", 6)
	log_col.add_child(log_header)
	_log_toggle = Button.new()
	_log_toggle.text = "Registro  >"
	_log_toggle.tooltip_text = "Comprimi il registro degli eventi"
	_log_toggle.focus_mode = Control.FOCUS_NONE
	_log_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_toggle.pressed.connect(_toggle_log_panel)
	log_header.add_child(_log_toggle)
	var copy_log := Button.new()
	copy_log.text = "Copia tutto"
	copy_log.tooltip_text = "Copia l'intero registro negli appunti"
	copy_log.focus_mode = Control.FOCUS_NONE
	copy_log.pressed.connect(_copy_full_log)
	log_header.add_child(copy_log)
	_log_scroll = ScrollContainer.new()
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_col.add_child(_log_scroll)
	_lbl_log = RichTextLabel.new()
	_lbl_log.bbcode_enabled = true
	_lbl_log.fit_content = true
	_lbl_log.custom_minimum_size.x = 370
	_lbl_log.selection_enabled = true
	_lbl_log.context_menu_enabled = true
	_lbl_log.mouse_filter = Control.MOUSE_FILTER_STOP
	_lbl_log.meta_clicked.connect(_on_log_meta_clicked)
	_log_scroll.add_child(_lbl_log)

	# Pannello "ora tocca a": prende il posto del vecchio registro in basso.
	#
	# Nasce da una critica precisa all'interfaccia: i motivi per cui un'azione
	# non si puo' dichiarare c'erano gia', ma uno alla volta, nel tooltip di
	# ogni pulsante. Per sapere perche' sei azioni su nove erano spente
	# bisognava passare il mouse su sei pulsanti, uno dopo l'altro. Qui si
	# vedono insieme, RAGGRUPPATE PER MOTIVO: quasi sempre e' un motivo solo che
	# ne blocca quattro, e detto cosi' si capisce cosa fare.
	var bottom_row := HBoxContainer.new()
	bottom_row.name = "BottomWorkspace"
	bottom_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_row.offset_left = 12
	bottom_row.offset_right = -12
	bottom_row.offset_top = -340
	bottom_row.offset_bottom = -12
	bottom_row.add_theme_constant_override("separation", 8)
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom_row)

	var nowpanel := PanelContainer.new()
	nowpanel.name = "StatusPanel"
	nowpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nowpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nowpanel.mouse_filter = Control.MOUSE_FILTER_STOP
	nowpanel.add_theme_stylebox_override("panel", _panel_style())
	bottom_row.add_child(nowpanel)
	var now_col := VBoxContainer.new()
	now_col.add_theme_constant_override("separation", 6)
	nowpanel.add_child(now_col)
	_lbl_now = RichTextLabel.new()
	_lbl_now.bbcode_enabled = true
	# un punto piu' piccolo del resto: e' un pannello di servizio, non deve
	# rubare l'occhio alla mappa
	_lbl_now.add_theme_font_size_override("normal_font_size", 14)
	_lbl_now.add_theme_font_size_override("bold_font_size", 14)
	_lbl_now.add_theme_font_size_override("italics_font_size", 14)
	_lbl_now.scroll_active = true
	_lbl_now.selection_enabled = true
	_lbl_now.context_menu_enabled = true
	_lbl_now.mouse_filter = Control.MOUSE_FILTER_STOP
	_lbl_now.size_flags_vertical = Control.SIZE_EXPAND_FILL
	now_col.add_child(_lbl_now)

	_status_choice_box = VBoxContainer.new()
	_status_choice_box.add_theme_constant_override("separation", 3)
	_status_choice_box.visible = false
	now_col.add_child(_status_choice_box)
	_status_choice_title = Label.new()
	_status_choice_title.add_theme_font_size_override("font_size", 15)
	_status_choice_box.add_child(_status_choice_title)
	_status_choice_detail = RichTextLabel.new()
	_status_choice_detail.bbcode_enabled = true
	_status_choice_detail.fit_content = true
	_status_choice_detail.selection_enabled = true
	_status_choice_detail.context_menu_enabled = true
	_status_choice_detail.custom_minimum_size.y = 22
	_status_choice_box.add_child(_status_choice_detail)
	_status_choice_buttons = FlowContainer.new()
	_status_choice_buttons.add_theme_constant_override("h_separation", 6)
	_status_choice_buttons.add_theme_constant_override("v_separation", 4)
	_status_choice_box.add_child(_status_choice_buttons)

	_tf_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tf_panel.name = "TaskForcePanel"
	bottom_row.add_child(_tf_panel)

	# Avviso non modale: porta l'occhio sull'esagono interessato e spiega la
	# catena tabella -> scelta -> effetto senza fermare il turno del bot.
	_solo_event_panel = PanelContainer.new()
	_solo_event_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_solo_event_panel.offset_left = 12
	_solo_event_panel.offset_right = -430
	_solo_event_panel.offset_top = 108
	_solo_event_panel.offset_bottom = 236
	_solo_event_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_solo_event_panel.add_theme_stylebox_override("panel", _solo_event_style())
	_solo_event_panel.visible = false
	hud.add_child(_solo_event_panel)
	_lbl_solo_event = RichTextLabel.new()
	_lbl_solo_event.bbcode_enabled = true
	_lbl_solo_event.fit_content = false
	_lbl_solo_event.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lbl_solo_event.add_theme_font_size_override("normal_font_size", 15)
	_lbl_solo_event.add_theme_font_size_override("bold_font_size", 16)
	_solo_event_panel.add_child(_lbl_solo_event)

	_build_action_bar(hud)
	_build_inset_maps(hud)
	_build_briefing(hud)
	_build_help(hud)


func _build_inset_maps(parent: Control) -> void:
	_inset_panel = PanelContainer.new()
	_inset_panel.name = "InsetMaps"
	_inset_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_inset_panel.offset_left = 12
	_inset_panel.offset_right = MAP_LEFT - 8
	_inset_panel.offset_top = MAP_TOP
	_inset_panel.offset_bottom = -MAP_BOTTOM
	_inset_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inset_panel.add_theme_stylebox_override("panel", _panel_style())
	parent.add_child(_inset_panel)

	var tabs := TabContainer.new()
	tabs.name = "InsetTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tooltip_text = ("Mappe inserto originali. Il reticolo e' calibrato e il "
		+ "motore le carica: aprendo uno scenario inserto diventano la "
		+ "superficie di gioco. Qui restano un riferimento visivo.")
	_inset_panel.add_child(tabs)
	_add_inset_map(tabs, "Nord", "Mare del Nord",
		"res://assets/boards/map_north_sea.jpg")
	_add_inset_map(tabs, "Norvegia", "Mare di Norvegia",
		"res://assets/boards/map_norwegian_sea.jpg")


func _add_inset_map(tabs: TabContainer, tab_title: String, title: String,
		path: String) -> void:
	var image := TextureRect.new()
	image.name = tab_title
	image.texture = load(path)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_PASS
	image.tooltip_text = ("%s - riferimento visivo; il reticolo e' calibrato" % title)
	tabs.add_child(image)


## Cambia la superficie di gioco: Mappa Operazionale o una delle due inserto.
##
## Il grafo e' condiviso da stato, tabellone, traiettorie e camera, quindi vanno
## ripuntati tutti insieme o restano a guardare la mappa di prima - e siccome i
## centri degli esagoni esistono su entrambe, non si vedrebbe un errore, si
## vedrebbe una partita giocata sulle coordinate sbagliate.
func _use_map_for(sc: Scenario) -> void:
	var key := sc.inset_key()
	if key == _current_map_key:
		return
	var g: MapGraph = MapGraph.load_default() if key == "" else MapGraph.load_inset(key)
	if g.load_error != "":
		push_error(g.load_error)
		_msg("mappa non caricata (%s): resto sulla Mappa Operazionale" % g.load_error)
		if _current_map_key == "":
			return
		g = MapGraph.load_default()
		key = ""
	_current_map_key = key
	graph = g
	state.graph = g
	board.setup(g)
	traj_layer.setup(g, state)
	cam.setup(Vector2(g.map_size))
	_focus_selected()


func _toggle_log_panel() -> void:
	_log_expanded = not _log_expanded
	_log_panel.offset_left = -410 if _log_expanded else -54
	_log_scroll.visible = _log_expanded
	_log_toggle.text = "Registro  >" if _log_expanded else "<"
	_log_toggle.tooltip_text = "Comprimi il registro degli eventi" \
		if _log_expanded else "Apri il registro degli eventi"
	_set_map_right_margin(MAP_RIGHT if _log_expanded else 54.0)


func _on_log_meta_clicked(meta: Variant) -> void:
	var value := String(meta)
	if not value.begins_with("bot_trace:"):
		return
	var trace_id := int(value.trim_prefix("bot_trace:"))
	if bool(_expanded_bot_traces.get(trace_id, false)):
		_expanded_bot_traces.erase(trace_id)
	else:
		_expanded_bot_traces[trace_id] = true
	_refresh()


func _copy_full_log() -> void:
	var lines: Array[String] = ["Mosse: %d" % log.applied_count() if log else ""]
	var newest_first := _messages.duplicate()
	newest_first.reverse()
	lines.append_array(newest_first)
	DisplayServer.clipboard_set("\n".join(lines))
	_msg("Registro completo copiato negli appunti.")
	_refresh()


func _status_choose(title: String, description: String, options: Array,
		allow_cancel: bool = true) -> int:
	if options.is_empty() or _status_choice_box == null:
		return -1
	if _status_choice_active:
		_msg("Completa prima la scelta gia' aperta nel pannello di stato.")
		return -1
	_status_choice_active = true
	_status_choice_option_count = options.size()
	_status_choice_title.text = title
	_status_choice_detail.text = description
	for child in _status_choice_buttons.get_children():
		child.queue_free()
	for i in options.size():
		var option: Dictionary = options[i]
		var button := Button.new()
		button.text = String(option.get("label", "Opzione %d" % (i + 1)))
		button.tooltip_text = String(option.get("detail", ""))
		button.custom_minimum_size = Vector2(150, 40)
		_style_status_button(button, false)
		var index := i
		button.pressed.connect(func() -> void: _complete_status_choice(index))
		_status_choice_buttons.add_child(button)
	if allow_cancel:
		var cancel := Button.new()
		cancel.text = "Annulla"
		cancel.custom_minimum_size = Vector2(110, 40)
		_style_status_button(cancel, true)
		cancel.pressed.connect(func() -> void: _complete_status_choice(-1))
		_status_choice_buttons.add_child(cancel)
	_status_choice_box.visible = true
	_refresh_now()
	var chosen: int = await _status_choice_made
	_status_choice_active = false
	_status_choice_option_count = 0
	_status_choice_box.visible = false
	for child in _status_choice_buttons.get_children():
		child.queue_free()
	_refresh_now()
	return chosen


func _complete_status_choice(index: int) -> void:
	if not _status_choice_active:
		return
	_status_choice_made.emit(index)


func _style_status_button(button: Button, secondary: bool) -> void:
	var colors := [Color("253746"), Color("31546b"), Color("1b2934")]
	if secondary:
		colors = [Color("292f35"), Color("3b4650"), Color("20262b")]
	for i in 3:
		var style := StyleBoxFlat.new()
		style.bg_color = colors[i]
		style.border_color = Color("78a8c4") if not secondary else Color("697783")
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		button.add_theme_stylebox_override(["normal", "hover", "pressed"][i], style)
	button.add_theme_color_override("font_color", Color("f3f6f8"))
	button.add_theme_color_override("font_hover_color", Color.WHITE)


func _solo_event_style() -> StyleBoxFlat:
	var sb := _panel_style()
	sb.bg_color = Color(0.08, 0.12, 0.15, 0.96)
	sb.border_color = Color(0.95, 0.68, 0.25, 0.95)
	sb.set_border_width_all(2)
	return sb


## Sfondo scuro semitrasparente: senza, il testo bianco sull'azzurro della
## mappa e' semplicemente illeggibile.
## Motivo per cui un'azione non e' dichiarabile ora (stringa vuota = si puo').
func _action_unavailable_reason(key: String) -> String:
	if mode == Mode.EDITOR:
		return "sei in modalita' editor del grafo"
	if state.solo_ended:
		return "lo scenario solitario e' terminato: apri Punteggio per il Debriefing"
	if _solo_is_imaginary_turn():
		return "e' il turno dell'avversario immaginario: l'app tira la Tabella Solitario"
	if selected_tf == null:
		return "nessuna Task Force selezionata"
	if not _can_control_tf(selected_tf):
		return "questa Task Force appartiene all'avversario immaginario"
	if selected_tf.side != state.initiative:
		if solo != null and state.forces_of(state.initiative).is_empty():
			return ("l'Iniziativa e' dell'avversario immaginario: la Tabella "
				+ "Solitario viene tirata automaticamente; O la riapre")
		return "l'Iniziativa e' di %s" % Initiative.side_name(state.initiative)
	var forced_actions: Array = selected_tf.solo_flags.get("bl1_actions_only", [])
	if not forced_actions.is_empty() and not forced_actions.has(key):
		return "BL1: i guasti meccanici consentono solo Traiettoria, Completamento e Passare"
	if key == "REORGANIZE" and bool(selected_tf.solo_flags.get("bl1_no_reorganize", false)):
		return "BL1: il Rifornimento vieta Riorganizzazione a questa TF"
	# Passare, Completamento e Traiettoria si dichiarano anche senza nemici in
	# vista: pretendere un bersaglio le renderebbe indichiarabili
	if not engine.is_verified(key):
		return String(engine.action(key).get("verified_note",
			"tabella non ancora trascritta"))
	var late := Endgame.action_refusal(state, scenario.rules() if scenario != null
		else {}, selected_tf.side, key)
	if late != "":
		return late
	if key == "SIGNAL" and SignalAction.candidates(state, selected_tf.side).is_empty():
		return ("nessuna Traiettoria avversaria ha un segnalino Informazioni; "
			+ "Segnalazione sostituisce quel segnalino con la Stazione bersaglio")
	if key == "AIR_STRIKE":
		if state.weather != TimeLapse.Weather.GOOD:
			return "Attacco Aereo richiede Condizioni Meteo Buone"
		var sources := _air_sources(selected_tf.side)
		if sources.is_empty():
			return ("nessuna TF di questa parte ha una CV integra; le basi aeree "
				+ "non sono ancora modellate")
		for source in sources:
			for launch in ActionEngine.air_launch_hexes(source):
				if not _eligible_targets_for_action(key, source, launch).is_empty():
					return ""
		return "nessuna TF nemica e' entro due esagoni da una CV integra"
	if ActionBar.needs_enemy(key) and _eligible_targets_for_action(key, selected_tf).is_empty():
		return _enemy_action_unavailable_reason(key, selected_tf)
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = selected_tf
	dec.target = _sample_target_for_action(key, selected_tf)
	var err := engine.legality_error(dec, state)
	if err != "":
		return err
	# il Completamento ha condizioni sue, che stanno nella regola e non nella
	# tabella: porto amico raggiunto, non piu' di 6 segmenti (RB p.29)
	if key == "COMPLETION":
		return Completion.refusal(selected_tf, graph, _port_control())
	return ""


## Il pannello "ora tocca a".
##
## Tre domande, in quest'ordine, che sono quelle che si fa chi guarda lo
## schermo senza sapere cosa succede:
##
##   chi sta agendo?      il lato che ha l'Iniziativa; la TF selezionata puo'
##                        essere ispezionata, ma agisce solo se e' di quel lato
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
			+ "gioca. Le coordinate sono al centro di ogni esagono; clic per "
			+ "selezionarlo, Shift+clic su un vicino per modificare il lato. "
			+ "E torna alla partita.")
		return

	var scenario_name := scenario.title if scenario != null else "Scenario"
	var status := "[b]%s[/b]    Meteo: [b]%s[/b]    Iniziativa: [b]%s[/b]" % [
		scenario_name, "cattivo" if state.weather == 1 else "buono",
		Initiative.side_name(state.initiative)]
	if solo != null:
		status += "    Solitario: [b]%s[/b]" % _solo_phase_label()
	out.append(status)
	if state.solo_ended:
		out.append("[bgcolor=#4a241f][color=#ffd0a8][b]  FINE SCENARIO  [/b][/color]  "
			+ "[color=#ffffff][b]%s[/b] Apri Punteggio per il Debriefing.[/color][/bgcolor]"
			% state.solo_end_reason)
	if _last_bot_summary != "":
		out.append("[bgcolor=#183541][color=#7ee5ff][b]  ULTIMA AZIONE DEL BOT  [/b][/color]  "
			+ "[color=#ffffff][b]%s[/b][/color][/bgcolor]" % _last_bot_summary)
	if _hex_choice_active and _hex_choice_prompt != "":
		out.append("[bgcolor=#203c2d][color=#9af0b7][b]  SCELTA SULLA MAPPA  [/b][/color]  "
			+ "[color=#ffffff]%s[/color][/bgcolor]" % _hex_choice_prompt)
	var late := Endgame.notice(state, scenario.rules() if scenario != null
		else {}, graph, _port_control())
	if late != "":
		out.append("[color=#ff9a3c]%s[/color]" % late)

	if selected_tf == null:
		out.append("[b]Ora tocca a...[/b]  [b]%s[/b]" % Initiative.side_name(state.initiative))
		out.append("[color=#ffd27f]Clicca una Task Force sulla mappa.[/color] "
			+ "Finche' non ne scegli una, nessuna azione e' dichiarabile: "
			+ "in Atlantic Chase si dichiara sempre PER una forza.")
		_lbl_now.text = "\n".join(out)
		return

	var side_name := "Kriegsmarine" if selected_tf.side \
		== TaskForce.Side.KRIEGSMARINE else "Royal Navy"
	var has_init := state.initiative == selected_tf.side
	out.append("[b]Ora tocca a...[/b]  [b]%s[/b] - %s%s"
		% [side_name, selected_tf.display_name(),
		"   [color=#8fd0ff](ha l'Iniziativa)[/color]" if has_init else ""])
	if not has_init:
		if solo != null and state.forces_of(state.initiative).is_empty():
			out.append("[color=#ff9a3c]L'Iniziativa e' dell'avversario immaginario: "
				+ "la Tabella Solitario viene tirata automaticamente quando "
				+ "riceve il turno; O la riapre/manuale.[/color]")
		else:
			out.append("[color=#ff9a3c]Questa TF non puo' agire: l'Iniziativa e' di "
				+ "[b]%s[/b].[/color]" % Initiative.side_name(state.initiative))

	# che cosa aspetta il gioco, adesso
	var t := selected_tf.trajectory
	if t.is_station():
		if _trajectory_action_armed:
			out.append("[color=#8fd0ff][b]Azione Traiettoria attiva.[/b][/color] "
				+ "Trascina dalla Stazione o clicca un esagono adiacente. "
				+ "Dopo il primo tratto l'azione si chiude; ESC annulla.")
		else:
			out.append("E' una [b]Stazione[/b]. Per tracciare una rotta dichiara "
				+ "[b]Traiettoria (5)[/b]; altrimenti puoi solo selezionare e "
				+ "dichiarare altre azioni.")
	elif t.length() >= Trajectory.MAX_SEGMENTS:
		out.append("Traiettoria al massimo (%d segmenti): non puo' essere allungata "
			% Trajectory.MAX_SEGMENTS
			+ "finche' un'Azione o un evento non innesca [b]Scorrere del Tempo[/b].")
	else:
		if _trajectory_action_armed:
			out.append("[color=#8fd0ff][b]Azione Traiettoria attiva.[/b][/color] "
				+ "La rotta ha [b]%d[/b] segmenti, capo attivo [b]%s[/b]: "
				% [t.length(), "testa" if active_end == 0 else "coda"]
				+ "trascina dal capo o clicca un esagono adiacente. F cambia capo; ESC annulla.")
		else:
			out.append("Traiettoria di [b]%d[/b] segmenti. Per modificarla dichiara "
				% t.length()
				+ "[b]Traiettoria (5)[/b]. [b]7 Passare[/b] innesca lo Scorrere "
				+ "del Tempo e passa l'Iniziativa. "
				+ "F cambia il capo preparato.")

	# I pulsanti in alto mostrano gia' le azioni disponibili. Qui restano solo
	# i motivi dei divieti, raggruppati per non ripetere la stessa spiegazione.
	var by_reason: Dictionary = {}
	for a in ActionBar.ACTIONS:
		var key := String(a[0])
		var label := String(a[1])
		var why := _action_unavailable_reason(key)
		if why != "":
			if not by_reason.has(why):
				by_reason[why] = []
			(by_reason[why] as Array).append(label)

	if not by_reason.is_empty():
		out.append("")
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
		log != null and log.can_redo(), mode == Mode.EDITOR)


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
		_toggle_briefing())
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
	board.selected_hex = Vector2i.MAX
	_msg("modalita': %s" % ("EDITOR del grafo" if mode == Mode.EDITOR else "gioco"))
	_refresh()


func _build_briefing(root: Control) -> void:
	_briefing_panel = PanelContainer.new()
	_briefing_panel.set_anchor(SIDE_LEFT, 0.14)
	_briefing_panel.set_anchor(SIDE_TOP, 0.13)
	_briefing_panel.set_anchor(SIDE_RIGHT, 0.86)
	_briefing_panel.set_anchor(SIDE_BOTTOM, 0.78)
	_briefing_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_briefing_panel.visible = false
	_briefing_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(_briefing_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_briefing_panel.add_child(col)
	var header := HBoxContainer.new()
	col.add_child(header)
	_lbl_briefing_title = Label.new()
	_lbl_briefing_title.text = "Scenario"
	_lbl_briefing_title.add_theme_font_size_override("font_size", 19)
	_lbl_briefing_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_lbl_briefing_title)
	var close := Button.new()
	close.text = "X"
	close.tooltip_text = "Chiudi"
	close.custom_minimum_size = Vector2(36, 32)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _briefing_panel.visible = false)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_lbl_briefing = RichTextLabel.new()
	_lbl_briefing.bbcode_enabled = true
	_lbl_briefing.fit_content = true
	_lbl_briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_briefing.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_lbl_briefing)


func _show_info_panel(title: String, text: String) -> void:
	_lbl_briefing_title.text = title
	_lbl_briefing.text = text
	_briefing_panel.visible = true


func _toggle_briefing() -> void:
	if _briefing_panel.visible and _lbl_briefing_title.text == "Scenario":
		_briefing_panel.visible = false
		return
	_update_briefing()
	_briefing_panel.visible = true


func _update_briefing() -> void:
	if _lbl_briefing == null or scenario == null:
		return
	var txt := scenario.briefing_text()
	txt += "\n\n[b]SCHIERAMENTO[/b]\n%d Task Force, %d navi" % [
		scenario.task_forces.size(), scenario.ship_count()]
	if scenario.reinforcement_count() > 0:
		txt += ", %d navi di rinforzo" % scenario.reinforcement_count()
	for note_v: Variant in scenario.raw_setup_notes():
		txt += "\n- " + String(note_v)
	if solo != null:
		var table_names: Array[String] = []
		for table_v: Variant in solo.tables.values():
			var table: SoloTable = table_v
			table_names.append(table.title if table.title != "" else "Tabella senza titolo")
		txt += "\n\n[b]AVVERSARIO IMMAGINARIO[/b]\nFase: [b]%s[/b]" % _solo_phase_label()
		if not table_names.is_empty():
			txt += "\nTabelle disponibili: " + ", ".join(table_names)
	if victory != null and not victory.notes.is_empty():
		txt += "\n\n[b]NOTE DI PUNTEGGIO[/b]"
		for note_v: Variant in victory.notes:
			txt += "\n- " + String(note_v)
	if scenario.has_import_warnings():
		txt += "\n\n[color=#ff9a3c][b]Avvisi di import[/b][/color]"
		for w_v: Variant in scenario.import_warnings:
			txt += "\n  " + String(w_v)
	_lbl_briefing_title.text = "Scenario"
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
  5 / Traiettoria                             arma il tracciamento della rotta
  [b]trascina dalla TF sugli esagoni[/b]             disegna la rotta armata in un gesto solo
  clic su un esagono adiacente                estende di un esagono, solo dopo 5
  Scorrere del Tempo                          si apre solo quando una regola lo innesca
  Tab / Shift+Tab                             TF successiva / precedente
  F                                           cambia capo attivo (testa/coda)
  ESC                                         annulla l'azione Traiettoria armata

[b]Azioni[/b]  (anche dai pulsanti in alto)
  1  Ingaggiare      2  Ricerca Navale
  3  Attacco Aereo   4  Attacco Furtivo
  5  Traiettoria     6  Completamento
  7  Passare         8  Riorganizzare
  9  Segnalazione
  O   avversario immaginario (modo solitario; riapre le tabelle)
  Nel solitario, quando l'avversario immaginario riceve l'Iniziativa,
     la sua Tabella delle Azioni viene tirata automaticamente.
  0   apre una Battaglia di prova
  Ctrl+W  alterna meteo buono/cattivo
  Ctrl+Z / Ctrl+Shift+Z   annulla / ripristina

[b]Guida in tempo reale[/b]
	  Il pannello in basso dice chi ha l'Iniziativa, cosa puoi fare ora e
	  perche' un'azione e' bloccata. Le scelte compaiono li' come pulsanti.
	  Il risultato del bot resta evidenziato; ogni procedura apre i propri calcoli.
	  Registro e pannello di stato consentono di selezionare e copiare il testo.

[b]Comandanti[/b]
	  La scheda TF mostra effetto e utilizzi residui. Raeder e Pound offrono
	  Passare Tutto quando dichiari Passare; gli altri effetti sono indicati
	  esplicitamente come automatizzati o ancora manuali.

[b]In Battaglia[/b]
  SPAZIO                     risolve la fase corrente
  [b]trascina una nave[/b]          la muove di una zona
  S                          crea o toglie il Fumo
  F / G                      tenta la Fuga (Attivo / Bersaglio)
  ESC                        torna alla mappa

[b]Touch (iPad)[/b]
  due dita             sposta la mappa e zooma (pinch)
  un dito              seleziona; dopo 5 disegna la Traiettoria
  durante Scorrere     tocca i segmenti terminali evidenziati

[b]Scenario e vista[/b]
  [ e ]        scenario precedente / successivo
  B            briefing        G   visibilita' del reticolo
  E            editor del grafo (Ctrl+S salva)
  F1           chiude questo pannello"""
	_help.add_child(t)


func _toggle_help() -> void:
	_help.visible = not _help.visible


func _msg(s: String) -> void:
	_message_seq += 1
	_messages.append("%04d  %s" % [_message_seq, s])
	_message_bot_trace.append(_active_bot_trace)


func _tf_card_text(tf: TaskForce) -> String:
	var t := tf.trajectory
	var kind := "Stazione" if t.is_station() else "Traiettoria"
	var lines: Array[String] = [
		"[font_size=18][b]%s[/b][/font_size]  [color=#9eb5c2]%s[/color]" % [
			tf.display_name(), "Kriegsmarine" if tf.side == TaskForce.Side.KRIEGSMARINE
			else "Royal Navy"],
		"%s, [b]%d[/b] segmenti    velocita': [b]%s[/b]" % [kind, t.length(),
			TimeLapse.speed_label(tf.speed)],
	]
	if t.is_station():
		lines.append("Esagono: [b]%s[/b]%s" % [_hex_text(t.station_hex),
			"    porto: [b]%s[/b]" % t.station_port if t.station_port != "" else ""])
	else:
		lines.append("Testa [b]%s[/b]    Coda [b]%s[/b]    capo attivo: [b]%s[/b]" % [
			_hex_text(t.end_hex(0)), _hex_text(t.end_hex(1)),
			"testa" if active_end == 0 else "coda"])
	lines.append("Informazioni: [b]%d[/b]    Contatto: [b]%d[/b]" % [
		t.info_count(), t.contact_count()])
	if tf.evasive:
		lines.append("[color=#9ee8ff][b]Manovre Evasive[/b] assegnate[/color]")
	if tf.unidentified:
		lines.append("[color=#ffd27f]TF non identificata: composizione nascosta[/color]")
	elif not _can_control_tf(tf) and solo != null:
		lines.append("[color=#ffd27f]Avversario immaginario: ispezionabile, non comandabile[/color]")
	if t.info_count() > 0:
		lines.append("[color=#ff9a3c]Completamento impedito; vulnerabile a Interruzione[/color]")
	return "\n".join(lines)


func _refresh_tf_panel() -> void:
	if _tf_panel == null:
		return
	if mode == Mode.EDITOR or selected_tf == null or selected_tf.completed:
		_tf_panel.visible = false
		_tf_card_signature = ""
		_tf_panel_tf_id = -1
		return
	if _tf_panel_tf_id != selected_tf.id:
		_tf_panel_tf_id = selected_tf.id
	_tf_panel.visible = true
	var signature := JSON.stringify(selected_tf.to_dict()) + ":%d" % active_end
	if signature == _tf_card_signature:
		return
	_tf_card_signature = signature
	_tf_info.text = _tf_card_text(selected_tf)
	for child in _tf_ships.get_children():
		child.queue_free()
	if selected_tf.unidentified:
		var hidden := Label.new()
		hidden.text = "Composizione non ancora identificata"
		hidden.custom_minimum_size = Vector2(390, 56)
		hidden.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_tf_ships.add_child(hidden)
		return
	_add_leader_counter(selected_tf)
	for ship in selected_tf.ships:
		var path := ShipRoster.shared().counter_path(ship.name, ship.damaged)
		if path == "" or not ResourceLoader.exists(path):
			var missing := Label.new()
			missing.text = ship.display()
			missing.custom_minimum_size = Vector2(116, 56)
			_tf_ships.add_child(missing)
			continue
		var counter := TextureRect.new()
		counter.texture = load(path)
		counter.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		counter.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		counter.custom_minimum_size = Vector2(116, 56)
		counter.tooltip_text = ship.display()
		counter.mouse_filter = Control.MOUSE_FILTER_PASS
		_tf_ships.add_child(counter)


const LEADER_COUNTERS := {
	"Raeder": "res://assets/counters/leader_ge_raeder.png",
	"Lutjens": "res://assets/counters/leader_ge_lutjens.png",
	"Krancke": "res://assets/counters/leader_ge_krancke.png",
	"Marschall": "res://assets/counters/leader_ge_marschall.png",
	"Prien": "res://assets/counters/leader_ge_prien.png",
	"Pound": "res://assets/counters/leader_uk_pound.png",
	"Forbes": "res://assets/counters/leader_uk_forbes.png",
	"Somerville": "res://assets/counters/leader_uk_somerville.png",
	"Tovey": "res://assets/counters/leader_uk_tovey.png",
	"Walker": "res://assets/counters/leader_uk_walker.png",
	"Gensoul": "res://assets/counters/leader_fr_gensoul.png",
}


func _add_leader_counter(tf: TaskForce) -> void:
	if tf.leader == "" or not LEADER_COUNTERS.has(tf.leader):
		return
	var path := String(LEADER_COUNTERS[tf.leader])
	if not ResourceLoader.exists(path):
		return
	var uses := LeaderRules.uses_left(state, tf.leader)
	var counter := TextureRect.new()
	counter.name = "LeaderCounter"
	counter.texture = load(path)
	counter.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	counter.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	counter.custom_minimum_size = Vector2(74, 74)
	counter.tooltip_text = "%s\n%s\nUtilizzi rimasti: %d%s" % [tf.leader,
		LeaderRules.effect_text(tf.leader), uses,
		"" if LeaderRules.is_implemented(tf.leader)
		else "\nEffetto non ancora automatizzato"]
	counter.mouse_filter = Control.MOUSE_FILTER_STOP
	_tf_ships.add_child(counter)

func _refresh() -> void:
	if state == null:
		return
	if SoloAI.enforce_scenario_end(state):
		_msg("Solitario BL2 - FINE SCENARIO: %s" % state.solo_end_reason)
	_refresh_action_bar()
	_refresh_tf_panel()
	_refresh_now()

	var lg: Array[String] = []
	lg.append("[b]Mosse:[/b] %d    (F1 = comandi)" % log.applied_count() if log else "")
	var entries: Array[Dictionary] = []
	var trace_entries := {}
	for i in _messages.size():
		var trace_id := _message_bot_trace[i] if i < _message_bot_trace.size() else 0
		if trace_id > 0:
			if not trace_entries.has(trace_id):
				var entry := {"index": i, "trace": trace_id, "lines": [] as Array[String]}
				trace_entries[trace_id] = entry
				entries.append(entry)
			(trace_entries[trace_id]["lines"] as Array[String]).append(_messages[i])
			trace_entries[trace_id]["index"] = i
		else:
			entries.append({"index": i, "trace": 0,
				"lines": [_messages[i]] as Array[String]})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["index"]) > int(b["index"]))
	for entry in entries:
		var trace_id := int(entry["trace"])
		var lines: Array[String] = entry["lines"]
		if trace_id <= 0:
			lg.append(_format_log_line(lines[0]))
			continue
		var expanded := bool(_expanded_bot_traces.get(trace_id, false))
		var summary := "Procedura conclusa; consulta i dettagli."
		var details: Array[String] = []
		for line in lines:
			if line.contains("BOT - "):
				summary = line.get_slice("BOT - ", 1)
			else:
				details.append(line)
		var symbol := "Nascondi" if expanded else "Mostra"
		lg.append(("[url=bot_trace:%d][color=#9fd4ee][b]%s procedura BOT %02d[/b]"
			+ "[/color][/url]  [color=#718796](%d righe)[/color]") \
			% [trace_id, symbol, trace_id, details.size()])
		lg.append("[bgcolor=#173542][color=#7ee5ff][b]  AZIONE EFFETTIVA  [/b][/color]\n"
			+ "[color=#ffffff][b]  %s  [/b][/color][/bgcolor]" % summary)
		if expanded:
			for line in details:
				lg.append("  [color=#b9c7cf]%s[/color]" % line)
		lg.append("")
	if _lbl_log != null:
		var old_scroll := _log_scroll.scroll_vertical if _log_scroll != null else 0
		var has_new_messages := _log_rendered_message_seq != _message_seq
		_lbl_log.text = "\n".join(lg)
		_log_rendered_message_seq = _message_seq
		if has_new_messages:
			call_deferred("_set_log_scroll", 0)
		else:
			call_deferred("_set_log_scroll", old_scroll)


func _format_log_line(line: String) -> String:
	if line.contains("BOT - "):
		return ("[bgcolor=#173542][color=#7ee5ff][b]  AZIONE EFFETTIVA  [/b][/color]\n"
			+ "[color=#ffffff][b]  %s  [/b][/color][/bgcolor]" \
			% line.get_slice("BOT - ", 1))
	return "  " + line


func _set_log_scroll(value: int) -> void:
	if _log_scroll == null or not _log_expanded:
		return
	_log_scroll.scroll_vertical = value


func _refresh_roster() -> void:
	if _lbl_roster == null:
		return
	var out: Array[String] = []
	out.append("[b]Task Force in gioco[/b]")
	if state == null or state.task_forces.is_empty():
		out.append("[color=#c8b8a0]Nessuna TF sulla mappa.[/color]")
	else:
		_append_rendezvous_markers(out)
		_append_roster_side(out, TaskForce.Side.KRIEGSMARINE, "Kriegsmarine")
		_append_roster_side(out, TaskForce.Side.ROYAL_NAVY, "Royal Navy")
		_append_completed_forces(out)
	_append_reinforcements(out)
	_append_global_commanders(out)
	_lbl_roster.text = "\n".join(out)


func _append_roster_side(out: Array[String], side: int, label: String) -> void:
	var forces := state.forces_of(side)
	if forces.is_empty():
		return
	out.append("")
	out.append("[b]%s[/b]" % label)
	for tf in forces:
		var col := traj_layer.color_for(tf).to_html(false) if traj_layer != null else "ffffff"
		var selected := " [color=#8fd0ff](selezionata)[/color]" if tf == selected_tf else ""
		out.append("[color=#%s]*[/color] [b]%s[/b]%s - %s"
			% [col, tf.display_name(), selected, _tf_roster_position(tf)])
		out.append("  %s" % _tf_roster_contents(tf))
		if tf.leader != "" and not tf.unidentified:
			out.append("  Cmd: %s" % tf.leader)


func _tf_roster_position(tf: TaskForce) -> String:
	var t := tf.trajectory
	if t.is_station():
		var port := " %s" % t.station_port if t.station_port != "" else ""
		return "Stazione%s %s" % [port, _hex_text(t.station_hex)]
	var head := t.end_hex(0)
	var tail := t.end_hex(1)
	return "Traiettoria %d seg, testa %s, coda %s" \
		% [t.length(), _hex_text(head), _hex_text(tail)]


func _tf_roster_contents(tf: TaskForce) -> String:
	if tf.unidentified:
		return "[color=#ffd27f]TF non identificata: navi nascoste[/color]"
	if tf.ships.is_empty():
		return "[color=#c8b8a0]Nessuna nave elencata[/color]"
	var names: Array[String] = []
	for sh in tf.ships:
		names.append(sh.display())
	return ", ".join(names)


func _append_completed_forces(out: Array[String]) -> void:
	var completed: Array[TaskForce] = []
	for tf in state.task_forces:
		if tf.completed:
			completed.append(tf)
	if completed.is_empty():
		return
	out.append("")
	out.append("[b]TF uscite dal gioco (Completamento)[/b]")
	for tf in completed:
		var side := "KM" if tf.side == TaskForce.Side.KRIEGSMARINE else "RN"
		var contents := ", ".join(tf.completed_ships) \
			if not tf.completed_ships.is_empty() else "navi non registrate"
		out.append("[color=#8fb7c9]*[/color] %s %s -> [b]%s[/b]" % [
			side, tf.display_name(), tf.completed_port])
		out.append("  %s" % contents)


func _append_reinforcements(out: Array[String]) -> void:
	if scenario == null or scenario.reinforcements.is_empty():
		return
	var any := false
	for k_v: Variant in scenario.reinforcements.keys():
		var ships: Array = scenario.reinforcements[k_v]
		if not ships.is_empty():
			any = true
			break
	out.append("")
	out.append("[b]Box Rinforzi[/b]")
	if not any:
		out.append("[color=#c8b8a0]Tutti i gruppi disponibili sono gia' entrati o vuoti.[/color]")
		return
	var ports := scenario.reinforcement_ports()
	var leaders := scenario.reinforcement_leaders()
	for k_v: Variant in scenario.reinforcements.keys():
		var group := String(k_v)
		var ships: Array = scenario.reinforcements[k_v]
		if ships.is_empty():
			continue
		var port_txt := ""
		if ports.has(group):
			var p_v: Variant = ports[group]
			if typeof(p_v) == TYPE_DICTIONARY:
				port_txt = " -> %s" % String((p_v as Dictionary).get("port", "porto"))
			else:
				port_txt = " -> %s" % String(p_v)
		else:
			port_txt = " -> porto non trascritto"
		out.append("[b]%s[/b]%s" % [group, port_txt])
		out.append("  %s" % ", ".join(ships))
		if leaders.has(group):
			out.append("  Cmd: %s (entra assegnato al Gruppo)" % String(leaders[group]))


func _append_global_commanders(out: Array[String]) -> void:
	if state == null or state.commanders.is_empty():
		return
	out.append("")
	out.append("[b]Comandanti non assegnati[/b]")
	for commander in state.commanders:
		out.append("[b]%s[/b] - %s (utilizzi rimasti: %d)" % [commander,
			LeaderRules.effect_text(commander), LeaderRules.uses_left(state, commander)])


func _append_rendezvous_markers(out: Array[String]) -> void:
	if state == null or state.rendezvous_markers.is_empty():
		return
	var active: Array[String] = []
	for rv_v: Variant in state.rendezvous_markers:
		var rv: Dictionary = rv_v
		if not bool(rv.get("active", true)):
			continue
		var h := Vector2i(int(rv.get("q", 0)), int(rv.get("r", 0)))
		active.append("%s %s" % [String(rv.get("id", "RV")), _hex_text(h)])
	out.append("")
	out.append("[b]Marker RV[/b]")
	if active.is_empty():
		out.append("[color=#c8b8a0]Nessun marker RV attivo.[/color]")
	else:
		out.append("  %s" % ", ".join(active))


func _hex_text(h: Vector2i) -> String:
	return "(%d,%d)" % [h.x, h.y]
