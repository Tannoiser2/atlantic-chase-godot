extends SceneTree

## Prova di fumo dell'interfaccia: apre il gioco per davvero e preme i tasti.
##
##     godot --path . --script res://tools/smoke_ui.gd
##
## I test in tests/ verificano il motore, che non sa che Godot esiste. Restava
## scoperta la strada che i tasti fanno per arrivarci, ed e' proprio li' che si
## era rotto tutto: _unhandled_input usciva subito quando c'era una Battaglia
## aperta, quindi il blocco che passa i tasti alla vista non veniva mai
## raggiunto. La Battaglia si apriva e non andava piu' avanti - nessun errore,
## nessun avviso, solo una schermata ferma.
##
## Un test del motore non l'avrebbe mai preso: il motore funzionava.
##
## Esce con codice 1 se qualcosa non risponde, quindi e' usabile in CI.

var _n := 0
var _root: Node = null
var _failures: Array[String] = []
var _phases_seen: Array[String] = []


func _initialize() -> void:
	Session.scenario_id = "MS9 Sink the Bismarck"
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _key(code: int) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	_root._unhandled_input(k)


func _process(_delta: float) -> bool:
	_n += 1
	if _n < 3:
		return false

	var bv: Variant = _root.get("_battle_view")
	if bv == null:
		_failures.append("il mini-scenario non ha aperto la Battaglia")
		return _done()
	var st: BattleState = bv.state

	if _n == 3:
		# la barra dei comandi deve esistere ed essere popolata: senza, chi
		# gioca non ha modo di sapere che il gioco aspetta qualcosa
		var btns: Variant = bv.get("_buttons")
		if btns == null or btns.get_child_count() == 0:
			_failures.append("la Battaglia non mostra nessun pulsante")
		# e i bersagli devono essere pre-assegnati: senza, premere SPAZIO
		# darebbe una fase in cui non spara nessuno, che sembra rotta
		var tg: Dictionary = bv.get("targeting")
		if tg.is_empty():
			_failures.append("nessun bersaglio pre-assegnato: "
				+ "la fase di fuoco partirebbe muta")

	var before := st.phase
	var before_round := st.round_number
	_key(KEY_SPACE)
	var label := String(BattleState.PHASE_LABELS[st.phase])
	if not _phases_seen.has(label):
		_phases_seen.append(label)
	if st.phase == before and st.round_number == before_round and not st.ended:
		_failures.append("SPAZIO non fa avanzare la fase (%s): "
			% BattleState.PHASE_LABELS[before]
			+ "i tasti non arrivano alla Battaglia")
		return _done()

	if st.ended:
		# la Battaglia deve aver sparato davvero: se il registro non contiene
		# nessun attacco, le fasi sono avanzate a vuoto
		var fired := false
		for line in st.log:
			if String(line).contains("raggio"):
				fired = true
		if not fired:
			_failures.append("nessun attacco nel registro: "
				+ "le fasi avanzano ma non spara nessuno")
		if _phases_seen.size() < 4:
			_failures.append("la Battaglia e' finita senza passare da tutte "
				+ "le fasi: viste solo %s" % ", ".join(_phases_seen))
		print("Battaglia percorsa fino in fondo in %d pressioni di SPAZIO."
			% (_n - 2))
		print("  fasi viste: %s" % ", ".join(_phases_seen))
		print("  esito: %s" % st.end_reason)
		return _done()

	if _n > 40:
		_failures.append("la Battaglia non finisce dopo 38 pressioni")
		return _done()
	return false


func _done() -> bool:
	print("")
	if _failures.is_empty():
		print("PROVA DI FUMO INTERFACCIA: tutto risponde.")
		quit(0)
	else:
		print("PROVA DI FUMO INTERFACCIA: %d problemi" % _failures.size())
		for f in _failures:
			print("  - %s" % f)
		quit(1)
	return true
