extends TestCase

## Gli scenari operativi a due giocatori, giocati da soli da `DuelRunner`.
##
## Non verifica chi vince: verifica che lo scenario REGGA una partita. Prima
## del 2026-11 dei nove scenari operativi si sapeva solo che si aprivano.


func name() -> String:
	return "Scenari a due giocatori (DuelRunner)"


func run() -> void:
	test_all_operations_play()
	test_same_seed_same_game()
	test_attach_plays_one_side()
	test_pass_designates_a_trajectory()
	test_mini_scenarios_fight_to_the_end()


const OPS := ["Op1 Homecoming", "Op2 First Test", "Op3 Norway", "Op4 Berlin",
	"Op5 Rheinubung", "Op6 New Friends", "Op7 Non Compos Mentis",
	"Op8 Cat and Mouse", "Op9 Actic Calamity"]


func test_all_operations_play() -> void:
	_begin("i nove scenari operativi reggono una partita")
	for id in OPS:
		var r := DuelRunner.new()
		true_(r.load_scenario(id, 20261119), "%s si carica (%s)" % [id, r.load_error])
		if r.state == null:
			continue
		var out := r.run(40)
		true_(int(out["turns"]) >= 10 or String(out["stop"]) == "vuota",
			"%s: almeno dieci turni, o una parte svuotata (%d, %s)"
				% [id, int(out["turns"]), String(out["stopped"])])
		true_(r.state.rng.log.size() > 0, "%s: si tirano dadi" % id)
		var moved := false
		for line in r.transcript:
			if String(line).contains("Traiettoria di") \
					or String(line).contains("Completamento"):
				moved = true
		true_(moved, "%s: qualcuno traccia una rotta o Completa" % id)
		for tf in r.state.task_forces:
			true_(tf.trajectory.length() <= Trajectory.MAX_SEGMENTS,
				"%s: nessuna rotta oltre il massimo (%s)" % [id, tf.display_name()])


func test_same_seed_same_game() -> void:
	_begin("stesso seme, stessa partita")
	var a := DuelRunner.new()
	var b := DuelRunner.new()
	a.load_scenario("Op5 Rheinubung", 7)
	b.load_scenario("Op5 Rheinubung", 7)
	a.run(30)
	b.run(30)
	eq(a.transcript.size(), b.transcript.size(), "stesso numero di righe")
	var same := true
	for i in mini(a.transcript.size(), b.transcript.size()):
		if a.transcript[i] != b.transcript[i]:
			same = false
	true_(same, "riga per riga")
	var c := DuelRunner.new()
	c.load_scenario("Op5 Rheinubung", 8)
	c.run(30)
	ne("\n".join(c.transcript), "\n".join(a.transcript), "un seme diverso da' un'altra partita")


func test_attach_plays_one_side() -> void:
	_begin("agganciato a una partita, gioca solo la sua parte")
	var host := DuelRunner.new()
	host.load_scenario("Op5 Rheinubung", 11)
	var st := host.state
	st.initiative = TaskForce.Side.ROYAL_NAVY
	var km_before: Array[String] = []
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		km_before.append("%d:%s:%d" % [tf.id, str(tf.trajectory.station_hex),
			tf.trajectory.length()])
	var cpu := DuelRunner.new()
	cpu.attach(st, host.graph, host.engine, host.scenario, host.victory,
		host.vp_tracker)
	var lines := cpu.play_turns_for(TaskForce.Side.ROYAL_NAVY, 3)
	true_(lines.size() > 0, "produce righe di trascrizione")
	var km_after: Array[String] = []
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		km_after.append("%d:%s:%d" % [tf.id, str(tf.trajectory.station_hex),
			tf.trajectory.length()])
	var battles_fought: int = cpu.battles
	true_(battles_fought > 0 or km_after == km_before,
		"senza una Battaglia le Task Force tedesche restano dov'erano")
	eq(cpu.play_turns_for(TaskForce.Side.KRIEGSMARINE if st.initiative
		== TaskForce.Side.ROYAL_NAVY else TaskForce.Side.ROYAL_NAVY, 3).size(), 0,
		"e non gioca se l'Iniziativa non e' della parte richiesta")


func test_pass_designates_a_trajectory() -> void:
	_begin("RB p.35: chi passa designa una Traiettoria")
	var r := DuelRunner.new()
	r.load_scenario("Op5 Rheinubung", 3)
	r.player_side = TaskForce.Side.ROYAL_NAVY
	r.imaginary_side = TaskForce.Side.KRIEGSMARINE
	var longest: TaskForce = null
	var has_station := false
	for tf in r.state.forces_of(TaskForce.Side.ROYAL_NAVY):
		if tf.trajectory.is_station():
			has_station = true
		elif longest == null or tf.trajectory.length() > longest.trajectory.length():
			longest = tf
	true_(has_station and longest != null,
		"Rheinubung: la Royal Navy ha sia Stazioni sia rotte")
	if longest != null:
		var picked := r._pass_trajectory()
		false_(picked.trajectory.is_station(),
			"con rotte in mare si designa una rotta, non una Stazione")
		for tf in r.state.forces_of(TaskForce.Side.ROYAL_NAVY):
			if not tf.trajectory.is_station():
				tf.trajectory.become_station(tf.trajectory.end_hex(0))
		true_(r._pass_trajectory() == null or r._pass_trajectory().trajectory.is_station(),
			"senza rotte non c'e' niente da designare")


func test_mini_scenarios_fight_to_the_end() -> void:
	_begin("i dodici mini-scenari: la Battaglia arriva in fondo")
	var seen := 0
	for id in Scenario.list_ids():
		if not id.begins_with("MS"):
			continue
		var sc := Scenario.load_by_id(id)
		if sc == null or not sc.is_battle_scenario():
			continue
		seen += 1
		var bs := sc.make_battle_state()
		true_(bs != null, "%s: lo stato di Battaglia si costruisce" % id)
		if bs == null:
			continue
		var r := DuelRunner.new()
		r.state = GameState.new(MapGraph.load_default(), 5)
		r.player_side = TaskForce.Side.KRIEGSMARINE
		r.imaginary_side = TaskForce.Side.ROYAL_NAVY
		var b := Battle.new(bs, r.state.rng, null)
		b.start()
		var steps := 0
		while not bs.ended and steps < SoloRunner.MAX_BATTLE_STEPS:
			steps += 1
			r._battle_step(b, bs)
		true_(bs.ended, "%s: la Battaglia finisce (%d fasi)" % [id, steps])
	eq(seen, 12, "dodici mini-scenari")
