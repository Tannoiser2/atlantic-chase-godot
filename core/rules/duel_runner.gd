class_name DuelRunner
extends SoloRunner

## Una partita a due giocatori giocata da sola: tutte e due le parti seguono la
## policy del giocatore simulato di `SoloRunner`.
##
## Serve a due cose che prima non esistevano.
##
## 1. VERIFICARE gli scenari a due giocatori. I quindici solitari hanno un
##    replay che li gioca fino in fondo; i nove scenari operativi non avevano
##    niente: si sapeva che si aprivano, non che reggessero una partita. Qui
##    girano le stesse regole - Traiettoria, Ricerca, Ingaggio, Battaglia,
##    Completamento, Iniziativa, Scorrere del Tempo - con due parti vere.
##
## 2. FARE DA AVVERSARIO. `play_turns_for(side)` gioca i turni di una parte
##    sullo stato della partita in corso, e la vista la usa quando il giocatore
##    sceglie di affrontare il computer.
##
## COSA NON E'. Non e' una tabella del fascicolo: i due scenari a due giocatori
## non hanno un avversario stampato, quindi tutto cio' che decide qui e' POLICY,
## non regola. E' la policy piu' semplice che gioca una partita sensata -
## porta a casa i Convogli, attacca quando conviene, altrimenti naviga verso
## l'obiettivo - e niente di piu'.
##
## FINE DELLA PARTITA. Le condizioni di fine dei nove scenari operativi sono
## stampate a parole e non sono ancora un dato (TODO_REVISIONE.md). Il ciclo
## quindi si ferma per ragioni SUE, e le chiama col loro nome: una parte senza
## piu' Task Force ne' rinforzi, nessun progresso, o il limite dei turni. Non
## sono condizioni di vittoria.

## Turni di fila senza che niente si muova prima di dichiarare la partita
## ferma. Largo: col Meteo Avverso e una rotta lunga servono parecchi Passare
## prima che una Task Force possa Completare.
const QUIET_TURNS := 16

## Perche' il ciclo si e' fermato, in una parola: "vuota", "ferma", "limite".
var stop_kind: String = ""


func load_scenario(scenario_id: String, p_seed: int) -> bool:
	scenario = Scenario.load_by_id(scenario_id)
	if scenario == null or scenario.load_error != "":
		load_error = "scenario '%s' non caricato" % scenario_id
		return false
	var inset := scenario.inset_key()
	graph = MapGraph.load_default() if inset == "" else MapGraph.load_inset(inset)
	engine = ActionEngine.load_default()
	state = GameState.new(graph, p_seed)
	state.apply_dict(scenario.to_state_dict())
	port_control = scenario.port_control()
	state.configure_port_info_triggers(port_control)
	victory = Victory.from_scenario(scenario)
	vp_tracker = VictoryTracker.new(victory, state)
	if state.task_forces.is_empty():
		load_error = "lo scenario '%s' non ha Task Force schierate" % scenario_id
		return false
	return true


## Si aggancia a una partita gia' in corso, per giocarne una parte.
func attach(p_state: GameState, p_graph: MapGraph, p_engine: ActionEngine,
		p_scenario: Scenario, p_victory: Victory,
		p_tracker: VictoryTracker) -> void:
	state = p_state
	graph = p_graph
	engine = p_engine
	scenario = p_scenario
	victory = p_victory
	vp_tracker = p_tracker
	port_control = scenario.port_control() if scenario != null else {}


func _act_as(side: int) -> void:
	player_side = side
	imaginary_side = 1 - side
	_begin_player_turn()
	_player_turn()


## Gioca i turni di `side` finche' tiene l'Iniziativa. Ritorna le righe di
## trascrizione prodotte. `max_actions` evita che una parte che tiene sempre
## l'Iniziativa tenga anche lo schermo.
func play_turns_for(side: int, max_actions: int = 12) -> Array[String]:
	var from := transcript.size()
	var done := 0
	while state.initiative == side and done < max_actions:
		done += 1
		var rolls := state.rng.log.size()
		var signature := _progress_signature()
		_act_as(side)
		if state.rng.log.size() == rolls and signature == _progress_signature():
			break
	var out: Array[String] = []
	for i in range(from, transcript.size()):
		out.append(transcript[i])
	return out


func run(max_turns: int = MAX_TURNS) -> Dictionary:
	_line("=== %s (due giocatori, entrambi automatici) ===" % scenario.title)
	_line("Setup: %d Task Force, meteo %s, Iniziativa %s." % [
		state.task_forces.size(), Initiative.weather_label(state.weather),
		Initiative.side_name(state.initiative)])
	while turns < max_turns:
		turns += 1
		_line("")
		_line("--- Turno %d - Iniziativa %s (conto %d, meteo %s) ---" % [turns,
			Initiative.side_name(state.initiative), state.initiative_count,
			Initiative.weather_label(state.weather)])
		var rolls := state.rng.log.size()
		var before := _progress_signature()
		_act_as(state.initiative)
		var signature := _progress_signature()
		# L'impronta del tabellone SENZA l'Iniziativa: due parti che si
		# passano la mano a vicenda cambiano l'Iniziativa a ogni turno, e
		# sembrerebbero in movimento per sempre.
		var board := _board_signature()
		if board == _last_progress_signature:
			_no_progress_turns += 1
		else:
			_no_progress_turns = 0
			_last_progress_signature = board
		for side in [TaskForce.Side.KRIEGSMARINE, TaskForce.Side.ROYAL_NAVY]:
			if state.forces_of(side).is_empty() and stop_kind == "":
				stop_kind = "vuota"
				stopped_reason = "%s non ha piu' Task Force in gioco" \
					% Initiative.side_name(side)
		if stop_kind != "":
			break
		if (state.rng.log.size() == rolls and signature == before) \
				or _no_progress_turns >= QUIET_TURNS:
			stop_kind = "ferma"
			stopped_reason = ("turno %d: da %d turni nessuna Task Force si muove "
				% [turns, QUIET_TURNS]
				+ "(restano %d KM e %d RN in gioco)" % [
					state.forces_of(TaskForce.Side.KRIEGSMARINE).size(),
					state.forces_of(TaskForce.Side.ROYAL_NAVY).size()])
			break
	if stop_kind == "":
		stop_kind = "limite"
		stopped_reason = "raggiunto il limite di %d turni" % max_turns
	_line("")
	_line("FERMATO (ragione dell'harness, non una regola): %s" % stopped_reason)
	_line("Turni: %d; Battaglie: %d; Completamenti: %d." % [turns, battles, completions])
	_line("VP: Kriegsmarine %s, Royal Navy %s." % [
		state.vp_text(TaskForce.Side.KRIEGSMARINE),
		state.vp_text(TaskForce.Side.ROYAL_NAVY)])
	return {"turns": turns, "battles": battles, "completions": completions,
		"stop": stop_kind, "stopped": stopped_reason, "transcript": transcript}


# --- cio' che nel solitario dipende dalle tabelle, e qui non c'e' -----------

## L'Inattivo tenta sempre di Sottrarre: fra due giocatori e' quasi sempre la
## scelta giusta, e una policy che rinunciasse non metterebbe mai alla prova il
## passaggio dell'Iniziativa.
func _inactive_steals(reason: String) -> bool:
	var r := Initiative.steal(state, null)
	for line_v: Variant in r["log"]:
		_line("   %s: %s" % [reason, String(line_v)])
	return bool(r.get("changed", false))


func _seek_initiative(who: String) -> bool:
	var r := Initiative.seek(state, null)
	for line_v: Variant in r["log"]:
		_line("%s   %s" % [who, String(line_v)])
	return bool(r.get("changed", false))


func ask_steal(_reason: String) -> bool:
	return true


func _maybe_go_late(_event: String, _reason: String) -> bool:
	return false


func _bl1_fueling_checks() -> void:
	pass


func _bl2_neutral_incident(_key: String, _active: TaskForce,
		_hex: Vector2i) -> void:
	pass


func _bl1_murmansk_before_debriefing() -> void:
	pass


## Nel solitario il giocatore ha UNA forza principale e la policy muove quella.
## Fra due giocatori ogni Task Force deve fare la sua strada: qui tocca a
## quella con la rotta piu' corta fra quelle che hanno ancora dove andare, cosi'
## avanzano tutte invece di una sola.
func _player_main_force() -> TaskForce:
	var best: TaskForce = null
	var best_len := 9999
	for tf in state.forces_of(player_side):
		if tf.trajectory.length() >= Trajectory.MAX_SEGMENTS - 3:
			continue
		var goal := _player_goal(tf)
		if goal == Vector2i.MAX or goal == _anchor(tf):
			continue
		if SoloAI.best_route(state, graph, tf, goal).is_empty():
			continue
		if tf.trajectory.length() < best_len:
			best = tf
			best_len = tf.trajectory.length()
	return best if best != null else super()


func _board_signature() -> String:
	var parts: Array[String] = []
	for tf in state.task_forces:
		if tf.completed:
			continue
		parts.append("%d:%s:%d:%d" % [tf.id, str(_anchor(tf)),
			tf.trajectory.length(), tf.afloat_ships().size()])
	parts.append(state.vp_text(TaskForce.Side.KRIEGSMARINE))
	parts.append(state.vp_text(TaskForce.Side.ROYAL_NAVY))
	return "|".join(parts)


# --- la policy delle due parti ---------------------------------------------
#
# Asimmetrica, come la campagna: la Kriegsmarine caccia i Convogli e poi
# rientra (e' la policy del solitario, che nasce per lei); la Royal Navy scorta
# i propri Convogli e con il resto da' la caccia alle Task Force tedesche,
# senza rientrare finche' ce n'e' una in mare. Senza questa differenza la Royal
# Navy portava le sue navi in porto al primo turno, col Bismarck ancora fuori.

func _run_player_step(step: String) -> bool:
	if player_side == TaskForce.Side.ROYAL_NAVY \
			and (step == "go_home" or step == "complete") \
			and not state.forces_of(TaskForce.Side.KRIEGSMARINE).is_empty():
		return false
	if step == "norway" or step == "reinforce":
		return false          # procedure dei solitari, qui non hanno tabelle
	return super(step)


func _player_goal(tf: TaskForce) -> Vector2i:
	if player_side != TaskForce.Side.ROYAL_NAVY or _carries_convoy(tf):
		return super(tf)
	var from := _anchor(tf)
	var best := Vector2i.MAX
	var best_d := 9999
	for enemy in state.forces_of(TaskForce.Side.KRIEGSMARINE):
		var h := _anchor(enemy)
		if not graph.has_hex(h):
			continue
		var d := Hex.distance(from, h)
		if d < best_d:
			best_d = d
			best = h
	return best if best != Vector2i.MAX else super(tf)
