extends SceneTree

## Prova di fumo di MS12 Finale.
##
##     godot --path . --script res://tools/smoke_ms12.gd
##
## MS12 non e' una Battaglia: sono TRE Battaglie di due Round, e prima di
## ognuna il britannico tira per sapere con quale Forza combatte (fascicolo a
## due giocatori p.51). Il motore lo sa fare e `test_ms12.gd` lo difende, ma la
## strada che i tasti fanno per arrivarci - schermata, dialoghi, Battaglia che
## si chiude e la successiva che si apre - resta scoperta dai test del motore,
## ed e' esattamente il punto in cui questo progetto si e' gia' rotto una volta.
##
## Che cosa pretende: che le tre Parti si aprano davvero, che ognuna duri due
## Round, che le navi che tornano portino con se' il danno preso, e che alla
## terza la sequenza si chiuda da sola. Esce con codice 1 se qualcosa non
## risponde, quindi e' usabile in CI.

var _n := 0
var _root: Node = null
var _failures: Array[String] = []
var _parts_seen: Array[int] = []
var _last_rounds: Array[int] = []
var _answers := 0
var _exit_code := 0
var _idle := 0


func _initialize() -> void:
	Session.advanced_battle = false   # MS12 le Avanzate le prescrive da solo
	Session.scenario_id = "MS12 Finale"
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _key(code: int) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	Input.parse_input_event(down)


func _finish(ok: bool, message: String) -> bool:
	print("\nMS12: %s - %s" % ["OK" if ok else "ERRORE", message])
	_exit_code = 0 if ok else 1
	quit(_exit_code)
	return true


func _process(_d: float) -> bool:
	_n += 1
	if _n < 20:
		return false

	# Le scelte di MS12 passano dal pannello di stato: attitudine segreta dello
	# Scharnhorst e, dalla seconda Parte, chi resta fuori.
	if _root._status_choice_active:
		_answers += 1
		_root._complete_status_choice(0)
		_idle = 0
		return false

	var view: Node = _root._battle_view
	if view == null:
		_idle += 1
		# Finite le tre Parti la Battaglia non si riapre: e' la fine attesa.
		if _parts_seen.size() >= 3 and _idle > 60:
			if _last_rounds.any(func(r: int) -> bool: return r != 2):
				return _finish(false,
					"una Parte non durava due Round: %s" % str(_last_rounds))
			if _answers < 1:
				return _finish(false,
					"nessuna scelta chiesta: l'attitudine segreta non e' stata offerta")
			return _finish(true, ("tre Parti giocate, due Round ciascuna, "
				+ "%d scelte chieste dal pannello") % _answers)
		if _idle > 900:
			return _finish(false, "nessuna Battaglia aperta e nessun progresso")
		return false

	_idle = 0
	var bstate: BattleState = view.state
	var part := _parts_seen.size() + 1
	if _parts_seen.is_empty() or _root._ms12_part != _parts_seen.back():
		if not _parts_seen.has(_root._ms12_part) and _root._ms12_part > 0:
			_parts_seen.append(_root._ms12_part)
			_last_rounds.append(bstate.last_round)
			if not bstate.advanced:
				return _finish(false,
					"la Parte %d non usa le Regole Avanzate, che MS12 prescrive"
						% _root._ms12_part)
			if bstate.target_tf.ships.is_empty():
				return _finish(false, "la Parte %d non ha lo Scharnhorst" % part)

	# SPAZIO manda avanti la fase; la Battaglia si chiude da sola all'Ultimo
	# Round e la Parte successiva si apre da _close_battle.
	_key(KEY_SPACE)
	if _n > 6000:
		return _finish(false, "le tre Parti non si sono concluse in tempo")
	return false
