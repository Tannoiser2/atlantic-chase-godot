extends TestCase

## Completamenti in Norvegia (fascicolo solitario p.16).
##
## Tre differenze rispetto a un Completamento normale, e sono tutte stampate:
## serve un Convoglio o uno Squadrone DD nella Task Force; la Task Force NON
## viene rimossa e fa Scorrere del Tempo; ma l'avversario immaginario invece la
## perde. La terza sembra un'incoerenza ed e' scritta cosi' nel fascicolo.

var inset: MapGraph


func name() -> String:
	return "Completamenti in Norvegia"


func run() -> void:
	inset = MapGraph.load_inset("map_norwegian_sea")
	test_neutral_ports()
	test_who_may_complete()
	test_player_keeps_the_force()
	test_imaginary_player_loses_it()
	test_n5_adjacent_landing()


func _tf(st: GameState, side: int, h: Vector2i, ships: Array) -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	for n_v: Variant in ships:
		var s := ShipRoster.shared().make(String(n_v))
		if s != null:
			tf.ships.append(s)
	tf.trajectory.become_station(h)
	st.add_task_force(tf)
	return tf


func test_neutral_ports() -> void:
	_begin("i porti norvegesi sono neutrali")
	true_(Norway.is_neutral_port("Narvik"), "Narvik")
	true_(Norway.is_neutral_port("Trondheim"), "Trondheim")
	true_(Norway.is_neutral_port("Bergen"), "Bergen")
	false_(Norway.is_neutral_port("Scapa Flow"), "Scapa Flow no")
	# Un porto norvegese e' un esagono di Norvegia; e lo e' anche l'esagono di
	# un Punto di Interesse, perche' N1 chiede di posare le Mine "in the hexes
	# with Bud and Andalsnes".
	true_(Norway.is_norway_hex(inset, inset.port_hex("Narvik")), "l'esagono di Narvik")
	true_(Norway.is_norway_hex(inset, Vector2i(6, 1)),
		"e quello di Andalsnes, che e' un Punto di Interesse")
	false_(Norway.is_norway_hex(inset, Vector2i(3, 1)), "il mare aperto no")


func test_who_may_complete() -> void:
	_begin("in Norvegia si Completa solo col carico")
	var st := GameState.new(inset, 1)
	var uk := TaskForce.Side.ROYAL_NAVY
	var narvik := inset.port_hex("Narvik")

	var warship := _tf(st, uk, narvik, ["Sheffield"])
	false_(Norway.can_complete(inset, warship, narvik),
		"una TF di sole navi da guerra non Completa in Norvegia")
	true_(Norway.completion_error(inset, warship, narvik).contains("Convoglio"),
		"e il motivo cita il carico richiesto")

	var convoy := _tf(st, uk, narvik, ["Convoy x2", "Sheffield"])
	true_(Norway.can_complete(inset, convoy, narvik), "col Convoglio si'")
	var dd := _tf(st, uk, narvik, ["DD Squadron"])
	true_(Norway.can_complete(inset, dd, narvik),
		"e anche col solo Squadrone DD, che porta truppe")

	# Fuori dalla Norvegia, e fuori dal proprio esagono, no.
	false_(Norway.can_complete(inset, convoy, Vector2i(3, 1)),
		"il mare aperto non e' Norvegia")
	var elsewhere := _tf(st, uk, Vector2i(3, 1), ["Convoy x2"])
	false_(Norway.can_complete(inset, elsewhere, narvik),
		"e una TF altrove non Completa qui")


## "do not remove the TF or its ships. Instead, perform Time Lapse."
func test_player_keeps_the_force() -> void:
	_begin("il giocatore tiene la Task Force")
	var st := GameState.new(inset, 1)
	var uk := TaskForce.Side.ROYAL_NAVY
	var narvik := inset.port_hex("Narvik")
	var tf := _tf(st, uk, narvik, ["Convoy x2"])
	var before := st.task_forces.size()

	var out := Norway.complete(st, inset, tf, narvik, false)
	true_(bool(out["ok"]), "il Completamento riesce: %s" % String(out["reason"]))
	false_(bool(out["removed"]),
		"e la Task Force NON viene rimossa: e' l'opposto di un Completamento in porto")
	true_(bool(out["time_lapse"]), "al suo posto si fa Scorrere del Tempo")
	eq(st.task_forces.size(), before, "la TF e' ancora sulla mappa")
	false_(tf.completed, "e non risulta Completata")
	# "roll a die and check the result on the Norwegian Reaction Table"
	true_(bool(out["check_reaction"]), "e va controllata la Reazione Norvegese")


## "Enemy Completion in Norway: When the imaginary player successfully Completes
## in Norway, remove the TF and its ships." Il contrario, ed e' scritto cosi'.
func test_imaginary_player_loses_it() -> void:
	_begin("l'avversario immaginario la perde")
	var st := GameState.new(inset, 1)
	var ge := TaskForce.Side.KRIEGSMARINE
	var trondheim := inset.port_hex("Trondheim")
	var tf := _tf(st, ge, trondheim, ["Convoy x2"])
	var before := st.task_forces.size()

	var out := Norway.complete(st, inset, tf, trondheim, true)
	true_(bool(out["ok"]), "il Completamento riesce")
	true_(bool(out["removed"]), "ma la Task Force esce di scena con le sue navi")
	false_(bool(out["time_lapse"]), "e non fa Scorrere del Tempo")
	eq(st.task_forces.size(), before - 1, "una TF in meno sulla mappa")
	# "The imaginary player is not required to do this (Reaction is incorporated
	# into the Action Tables)."
	false_(bool(out["check_reaction"]),
		"e il bot non tira la Reazione Norvegese: e' gia' dentro le sue Tabelle")


## N5 p.32: si puo' Completare in un esagono ADIACENTE a Narvik o Trondheim,
## "however, the 'landing' hex must have land in it and not all sea".
func test_n5_adjacent_landing() -> void:
	_begin("lo sbarco adiacente di N5")
	var narvik := inset.port_hex("Narvik")
	var ports := ["Narvik", "Trondheim"]
	# Un esagono di solo mare non va bene nemmeno se e' adiacente.
	var open_sea := Vector2i(4, -1)
	true_(inset.land_fraction(open_sea) < Norway.LAND_MIN,
		"(4,-1) e' mare aperto: il 2%% di verde e' sfumatura di costa (%.2f)"
			% inset.land_fraction(open_sea))
	true_(Norway.adjacent_landing_error(inset, open_sea, ports).contains("terra"),
		"un esagono tutto mare non e' un punto di sbarco")
	# Un esagono con della terra ma lontano dai due porti nemmeno.
	var far_land := Vector2i(6, 2)
	true_(Norway.adjacent_landing_error(inset, far_land, ports) != "",
		"e nemmeno uno lontano dai due porti")
	# L'esagono di Narvik stesso non e' "adiacente a Narvik".
	true_(Norway.adjacent_landing_error(inset, narvik, ports) != "",
		"l'esagono del porto non e' adiacente a se stesso")
