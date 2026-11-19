extends SceneTree

## Prova di fumo dell'avversario computer negli scenari a due giocatori.
##
##     godot --path . --script res://tools/smoke_computer.gd
##
## Apre Rheinubung col computer alla Royal Navy e controlla che: le Task Force
## del computer non si comandino, la guida passi la mano al computer quando
## l'Iniziativa e' sua, il suo turno giochi davvero e scriva nel registro, e
## la scelta sopravviva a un salvataggio.

var _f := 0
var _root: Node
var _failures: Array[String] = []
var _messages_before := 0


func _initialize() -> void:
	Session.scenario_id = "Op5 Rheinubung"
	Session.computer_side = TaskForce.Side.ROYAL_NAVY
	Session.advanced_battle = false
	Session.resume_path = ""
	_root = (load("res://ui/main.tscn") as PackedScene).instantiate()
	root.add_child(_root)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_failures.append(what)


func _process(_delta: float) -> bool:
	_f += 1
	match _f:
		15:
			var st: GameState = _root.state
			_expect(st.computer_side == TaskForce.Side.ROYAL_NAVY,
				"il computer gioca la Royal Navy")
			for tf in st.forces_of(TaskForce.Side.ROYAL_NAVY):
				_expect(not _root._can_control_tf(tf),
					"%s e' del computer: non si comanda" % tf.display_name())
			for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
				_expect(_root._can_control_tf(tf),
					"%s e' del giocatore" % tf.display_name())
			_expect(st.initiative == TaskForce.Side.KRIEGSMARINE,
				"Rheinubung parte con l'Iniziativa tedesca")
			var back := GameState.new(_root.graph, 1)
			back.apply_dict(st.to_dict())
			_expect(back.computer_side == TaskForce.Side.ROYAL_NAVY,
				"la scelta del computer sopravvive al salvataggio")
			_root._declare_action("PASS")
		30:
			_expect(_root.state.initiative == TaskForce.Side.ROYAL_NAVY,
				"dopo Passare l'Iniziativa e' del computer")
			_expect(String(_root._guide_label.text).contains("Tocca al computer"),
				"e la guida lo dice (%s)" % _root._guide_label.text)
			var found := false
			for c in _root._guide_buttons.get_children():
				if c is Button and (c as Button).text == "Fai giocare il computer":
					found = true
					_messages_before = _root._messages.size()
					(c as Button).pressed.emit()
			_expect(found, "con il pulsante per farlo giocare")
		45:
			_expect(_root._messages.size() > _messages_before + 1,
				"il turno del computer scrive nel registro")
			var said := false
			for line in _root._messages:
				if String(line).contains("Computer:"):
					said = true
			_expect(said, "con righe che dicono che cosa ha fatto")
			_expect(not String(_root._guide_label.text).contains("policy harness"),
				"senza gergo dell'harness sullo schermo")
			return _finish()
	return false


func _finish() -> bool:
	if _failures.is_empty():
		print("\nAVVERSARIO COMPUTER: OK - comanda solo la sua parte, gioca il suo "
			+ "turno, sopravvive al salvataggio")
		quit(0)
	else:
		print("\nAVVERSARIO COMPUTER: FALLITO")
		for f in _failures:
			print("  - %s" % f)
		quit(1)
	return true
