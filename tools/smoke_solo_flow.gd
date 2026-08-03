extends SceneTree

## Prova di fumo del ciclo SOLITARIO nell'interfaccia vera.
##
##     godot --path . --script res://tools/smoke_solo_flow.gd
##     godot --path . --script res://tools/smoke_solo_flow.gd -- BL1
##
## `tests/unit/test_replay.gd` verifica il ciclo nel core, dove non ci sono ne'
## dialoghi ne' attese. Ma il ciclo che il giocatore vede davvero e' quello di
## `ui/main.gd`, ed e' fatto di `await`, `call_deferred` e scelte nel pannello
## di stato: un motore perfetto puo' benissimo stare dietro un'interfaccia che
## si pianta. E' gia' successo con la Battaglia, che si apriva e non andava
## piu' avanti perche' i tasti non le arrivavano, e nessun test del motore
## poteva accorgersene.
##
## Questa prova quindi apre il gioco per davvero, passa l'Iniziativa
## all'avversario immaginario e lo lascia giocare, rispondendo alle scelte come
## farebbe una persona: la prima opzione nel pannello di stato, il primo
## esagono legale sulla mappa. Poi controlla che qualcosa sia successo -
## la Tabella e' stata tirata, il bot ha annunciato la sua mossa, l'Iniziativa
## e' tornata a girare - e che l'interfaccia risponda ancora ai tasti.
##
## Non verifica REGOLE: quelle sono nel core e le prova la suite dei replay.
## Verifica che il ciclo non si fermi, che e' l'altra meta' del problema.

## Quanti fotogrammi lasciare al ciclo prima di dichiararlo bloccato. Il bot
## fa parecchie cose per turno e ognuna passa da un `call_deferred`, quindi il
## margine e' largo di proposito: qui interessa distinguere "lento" da "fermo".
const BUDGET_FRAMES := 900

## Dopo quanti fotogrammi senza NESSUN progresso il ciclo e' considerato fermo.
const STALL_FRAMES := 240

var _root: Node = null
var _frames := 0
var _phase := 0
var _scenario_id := "BL2 Contain and Destroy"

var _status_answers := 0
var _hex_answers := 0
var _bot_rolls_before := 0
var _log_size_before := 0
var _last_progress_frame := 0
var _last_progress_key := ""
var _saw_bot_summary := false
var _initiative_returned := false


func _initialize() -> void:
	for a_v: Variant in OS.get_cmdline_user_args():
		var a := String(a_v)
		if a.begins_with("BL1"):
			_scenario_id = "BL1 Raiders of the North Atlantic"
	Session.scenario_id = _scenario_id
	Session.seed_value = 20260803
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _process(_delta: float) -> bool:
	_frames += 1
	# Le scelte vanno servite SEMPRE, non solo nella fase in cui le aspetti:
	# il bot puo' aprirne una in qualunque momento, e una scelta lasciata
	# aperta blocca il ciclo esattamente come un difetto vero. La differenza e'
	# che questa la sappiamo riconoscere.
	_answer_pending_choices()
	_note_progress()

	match _phase:
		0:
			if _frames < 12:
				return false
			var why := _check_setup()
			if why != "":
				return _finish(false, why)
			_bot_rolls_before = _count_bot_rolls()
			_log_size_before = _root._messages.size()
			# In BL1 e BL2 l'Iniziativa iniziale e' del giocatore: senza
			# passarla, l'avversario immaginario non gioca mai e la prova non
			# proverebbe niente.
			_root._change_initiative_to(_root._solo_imaginary_side())
			_root.call_deferred("_kick_solo_opponent_turn", "prova di fumo")
			_last_progress_frame = _frames
			_phase = 1
		1:
			if _root._last_bot_summary != "":
				_saw_bot_summary = true
			if _root.state.initiative == _root._solo_player_side():
				_initiative_returned = true
			if _root.state.solo_ended:
				return _finish_report()
			if _saw_bot_summary and _initiative_returned:
				return _finish_report()
			if _frames - _last_progress_frame > STALL_FRAMES:
				return _finish(false, ("il ciclo solitario e' fermo da %d "
					+ "fotogrammi senza progresso (ultimo stato: %s)")
					% [STALL_FRAMES, _last_progress_key])
			if _frames > BUDGET_FRAMES:
				return _finish(false, ("il ciclo solitario non ha concluso un "
					+ "turno in %d fotogrammi") % BUDGET_FRAMES)
	return false


## Riconosce ogni cambiamento osservabile del gioco. Finche' qualcosa si muove
## il ciclo e' vivo, anche se lento; quando non si muove piu' niente e nessuno
## aspetta una scelta, e' bloccato.
func _note_progress() -> void:
	var key := "%d|%d|%d|%d|%s|%s" % [_root._messages.size(), _count_bot_rolls(),
		_root.state.initiative, _root.state.initiative_count,
		str(_root.state.solo_ended), _root._last_bot_summary]
	if key != _last_progress_key:
		_last_progress_key = key
		_last_progress_frame = _frames


## Risponde come farebbe una persona: la prima opzione, il primo esagono
## evidenziato. Non e' una strategia, e' un dito che preme.
func _answer_pending_choices() -> void:
	if _root._status_choice_active:
		_status_answers += 1
		_root._complete_status_choice(0)
	if _root._hex_choice_active:
		var options: Dictionary = _root._hex_choice_options
		if options.is_empty():
			_root._hex_choice_active = false
			_root._hex_choice_made.emit(Vector2i.MAX)
		else:
			_hex_answers += 1
			var first: Vector2i = options.keys()[0]
			_root._hex_choice_active = false
			_root._hex_choice_options.clear()
			_root._hex_choice_made.emit(first)


func _count_bot_rolls() -> int:
	return _root._bot_trace_serial


func _check_setup() -> String:
	if _root.solo == null:
		return "%s non ha caricato le tabelle solitarie" % _scenario_id
	if _root._solo_player_side() < 0:
		return "lo scenario non e' riconosciuto come solitario (nessun Debriefing)"
	if _root._solo_imaginary_side() < 0:
		return "nessuna parte avversaria configurata"
	if _root.state.task_forces.is_empty():
		return "nessuna Task Force schierata"
	if _root._solo_is_imaginary_turn():
		return "l'Iniziativa iniziale dovrebbe essere del giocatore"
	return ""


## Il controllo finale: qualcosa e' successo, ed e' successo per intero.
func _finish_report() -> bool:
	if _count_bot_rolls() <= _bot_rolls_before:
		return _finish(false, "l'avversario immaginario non ha tirato la Tabella delle Azioni")
	if not _saw_bot_summary:
		return _finish(false, "il bot non ha annunciato nessuna mossa nel pannello di stato")
	if _root._messages.size() <= _log_size_before:
		return _finish(false, "il Registro non e' cresciuto durante il turno del bot")
	if _root.state.solo_ended:
		# Anche a scenario finito l'interfaccia deve restare viva, e nessuna
		# procedura deve poter ripartire: e' il difetto corretto in bf65a2b.
		var rolls := _count_bot_rolls()
		_root._queue_next_solo_action("prova di fumo dopo la fine")
		if _count_bot_rolls() != rolls:
			return _finish(false, "una procedura riparte dopo la fine dello scenario")
	elif not _initiative_returned:
		return _finish(false, "l'Iniziativa non e' mai tornata al giocatore")
	# L'ultimo controllo e' quello che nessun test del motore puo' fare:
	# i tasti arrivano ancora?
	var before: TaskForce = _root.selected_tf
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	_root._unhandled_input(key)
	if _root.state.forces_of(_root._solo_player_side()).size() > 1 \
			and _root.selected_tf == before:
		return _finish(false, "dopo il turno del bot l'interfaccia non risponde piu' ai tasti")
	return _finish(true, ("%d tiri della Tabella, %d scelte nel pannello, "
		+ "%d scelte sulla mappa, %s") % [_count_bot_rolls() - _bot_rolls_before,
		_status_answers, _hex_answers,
		"scenario concluso" if _root.state.solo_ended
			else "Iniziativa tornata al giocatore"])


func _finish(ok: bool, detail: String) -> bool:
	print("")
	print("FLUSSO SOLITARIO (%s): %s - %s"
		% [_scenario_id, "OK" if ok else "ERRORE", detail])
	_root.queue_free()
	_root = null
	quit(0 if ok else 1)
	return true
