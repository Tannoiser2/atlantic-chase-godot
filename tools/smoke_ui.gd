extends SceneTree

## Prova di fumo dell'interfaccia: apre il gioco per davvero e preme i tasti.
##
##     godot --path . --script res://tools/smoke_ui.gd -- [adv]
##
## Con l'argomento "adv" gioca la stessa Battaglia con le REGOLE AVANZATE, e
## pretende di vederne le tracce: la Verifica Snafu nel registro e le due fasi
## che le regole base non hanno, Attitudine ed Effetti Duraturi. Serve a
## impedire il ritorno del difetto peggiore che questo progetto abbia avuto:
## un motore avanzato completo e verde nei test, ma con `advanced` fermo a
## false, cioe' mai eseguito in partita.
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


var _advanced := false
var _targets_seen := false


func _initialize() -> void:
	_advanced = OS.get_cmdline_user_args().has("adv")
	Session.advanced_battle = _advanced
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

	# I bersagli devono essere pre-assegnati quando si arriva a una fase che
	# spara: senza, premere SPAZIO darebbe una fase in cui non tira nessuno,
	# che e' legale ma sembra rotta. NON si puo' verificare alla prima
	# occasione: con le Regole Avanzate la prima fase e' l'Attitudine, dove i
	# bersagli e' giusto che non ci siano ancora.
	if not (bv.get("targeting") as Dictionary).is_empty():
		_targets_seen = true

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
		if _advanced:
			var snafu_seen := false
			for line in st.log:
				if String(line).contains("Verifica Snafu"):
					snafu_seen = true
			if not snafu_seen:
				_failures.append("Regole Avanzate chieste ma nessuna Verifica "
					+ "Snafu nel registro: la Battaglia e' partita base")
			for needed in ["Attitudine", "Effetti Duraturi"]:
				if not _phases_seen.has(needed):
					_failures.append("fase avanzata mai vista: %s" % needed)
		if not _targets_seen:
			_failures.append("nessun bersaglio pre-assegnato in tutta la "
				+ "Battaglia: le fasi di fuoco partirebbero mute")
		if _phases_seen.size() < 4:
			_failures.append("la Battaglia e' finita senza passare da tutte "
				+ "le fasi: viste solo %s" % ", ".join(_phases_seen))
		print("Battaglia (%s) percorsa fino in fondo in %d pressioni di SPAZIO."
			% ["REGOLE AVANZATE" if _advanced else "regole base", _n - 2])
		print("  fasi viste: %s" % ", ".join(_phases_seen))
		print("  esito: %s" % st.end_reason)
		return _done()

	if _n > 60:
		_failures.append("la Battaglia non finisce dopo 58 pressioni")
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
