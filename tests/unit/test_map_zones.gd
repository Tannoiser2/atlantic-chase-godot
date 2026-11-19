extends TestCase

## Linea Artica e Zona U-Boat: il dato di mappa (`core/data/map_zones.json`) e
## le sei regole che lo usano.
##
##   - RB p.17: un esagono con la Linea Artica ha sempre Meteo Avverso;
##   - RB p.20: Scorrere del Tempo, dado o Tabella a scelta nel caso misto;
##   - RB p.26: Manovre Evasive sull'Iniziativa valgono +2;
##   - RB p.27: l'Attacco Aereo non parte, non arriva e non attraversa;
##   - RB p.45: il Supporto Aereo non si applica, ma puo' attraversare;
##   - RB p.41 e tabella stampata: +3 all'Attacco Furtivo nella Zona U-Boat.
##
## Prima del 2026-11 erano tutte lacune dichiarate.

var graph: MapGraph
var eng: ActionEngine

const BEAR := Vector2i(17, -11)      ## sulla Linea Artica (Isola degli Orsi)
const NORTH_CAPE := Vector2i(18, -11)  ## sotto la Linea, accanto
const BARENTS := Vector2i(19, -12)   ## sulla Linea
const NARVIK := Vector2i(17, -9)     ## Zona U-Boat
const BISCAY := Vector2i(15, -1)     ## Zona U-Boat
const OCEAN := Vector2i(12, -3)      ## ne' l'una ne' l'altra


func name() -> String:
	return "Linea Artica e Zona U-Boat"


func run() -> void:
	graph = MapGraph.load_default()
	eng = ActionEngine.load_default()
	test_data_is_on_the_map()
	test_scenarios_carry_the_zones()
	test_save_and_load()
	test_weather_at_hex()
	test_time_lapse()
	test_evasive_on_initiative()
	test_air_strike()
	test_air_support()
	test_uboat_zone_bonus()


func _state(weather: int = TimeLapse.Weather.GOOD) -> GameState:
	var st := GameState.new(graph, 1)
	st.weather = weather
	st.arctic_hexes = GameState._zone_dict(MapZones.hexes("arctic_line"))
	st.uboat_zone = GameState._zone_dict(MapZones.hexes("uboat_zone"))
	return st


func _station(st: GameState, side: int, h: Vector2i, ship: String = "Sheffield",
		speed: int = TimeLapse.Speed.MEDIUM) -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	tf.ships.append(ShipRoster.shared().make(ship))
	tf.trajectory.become_station(h)
	tf.speed = speed
	st.add_task_force(tf)
	return tf


func _line(st: GameState, side: int, hexes: Array) -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	tf.ships.append(ShipRoster.shared().make("Sheffield"))
	for h_v: Variant in hexes:
		tf.trajectory.segments.append({"hex": h_v, "info": false, "contact": false})
	tf.speed = TimeLapse.Speed.MEDIUM
	st.add_task_force(tf)
	return tf


func test_data_is_on_the_map() -> void:
	_begin("il dato: esagoni veri, catene continue, dubbi tenuti fuori")
	var arctic := MapZones.hexes("arctic_line")
	var zone := MapZones.hexes("uboat_zone")
	eq(arctic.size(), 14, "quattordici esagoni della Linea Artica")
	eq(zone.size(), 10, "dieci esagoni della Zona U-Boat")
	for item_v: Variant in arctic + zone + MapZones.hexes("arctic_line", "dubbi"):
		var h := Vector2i(int(item_v[0]), int(item_v[1]))
		true_(graph.has_hex(h), "%s esiste nel grafo" % str(h))
	var st := _state()
	for item_v: Variant in MapZones.hexes("arctic_line", "dubbi"):
		var h := Vector2i(int(item_v[0]), int(item_v[1]))
		false_(st.is_arctic(h), "%s e' un dubbio: NON conta come Linea Artica" % str(h))
	eq(MapZones.hexes("arctic_line", "dubbi").size(), 2, "due dubbi dichiarati")
	# la linea e' una linea: ogni esagono ha un vicino sulla linea, salvo dove
	# la interrompe un dubbio (fra 9,-3 e 11,-5 c'e' 10,-4)
	var isolated := 0
	for item_v: Variant in arctic:
		var h := Vector2i(int(item_v[0]), int(item_v[1]))
		var linked := false
		for d in 6:
			if st.is_arctic(Hex.neighbor(h, d)):
				linked = true
		if not linked:
			isolated += 1
	eq(isolated, 0, "nessun esagono della Linea e' isolato dagli altri")
	for item_v: Variant in arctic:
		false_(st.in_uboat_zone(Vector2i(int(item_v[0]), int(item_v[1]))),
			"Linea Artica e Zona U-Boat non si sovrappongono")


func test_scenarios_carry_the_zones() -> void:
	_begin("gli scenari: la Mappa Operazionale le ha, gli inserti no")
	var with_zones := 0
	var inset_clean := 0
	var insets := 0
	for id in Scenario.list_ids():
		var sc := Scenario.load_by_id(id)
		if sc == null:
			continue
		var d := sc.to_state_dict()
		if sc.inset_key() == "":
			if (d["arctic_line"] as Array).size() == 14 \
					and (d["uboat_zone"] as Array).size() == 10:
				with_zones += 1
		else:
			insets += 1
			if (d["arctic_line"] as Array).is_empty() \
					and (d["uboat_zone"] as Array).is_empty():
				inset_clean += 1
	true_(with_zones > 20, "tutti gli scenari sulla Mappa Operazionale (%d)" % with_zones)
	eq(insets, 5, "cinque scenari su mappa inserto")
	eq(inset_clean, 5, "e nessuno dei cinque porta le zone: li' le coordinate "
		+ "sono un altro mare")


func test_save_and_load() -> void:
	_begin("salvataggio e ricarica")
	var st := _state()
	var d := st.to_dict()
	var back := GameState.new(graph, 1)
	back.apply_dict(d)
	true_(back.is_arctic(BEAR), "la Linea Artica torna dal salvataggio")
	true_(back.in_uboat_zone(BISCAY), "e la Zona U-Boat anche")
	false_(back.is_arctic(OCEAN), "senza inventare esagoni")
	var old := d.duplicate(true)
	old.erase("arctic_line")
	old.erase("uboat_zone")
	var legacy := GameState.new(graph, 1)
	legacy.apply_dict(old)
	false_(legacy.is_arctic(BEAR), "un salvataggio vecchio si carica senza zone, "
		+ "non si rompe")


func test_weather_at_hex() -> void:
	_begin("RB p.17: sulla Linea Artica il meteo e' sempre Avverso")
	var st := _state(TimeLapse.Weather.GOOD)
	eq(st.weather_at(BEAR), TimeLapse.Weather.BAD, "Buono in partita, Avverso li'")
	eq(st.weather_at(OCEAN), TimeLapse.Weather.GOOD, "altrove resta Buono")
	st.weather = TimeLapse.Weather.BAD
	eq(st.weather_at(OCEAN), TimeLapse.Weather.BAD, "col Meteo Avverso e' Avverso ovunque")
	st.weather = TimeLapse.Weather.GOOD
	var on := _station(st, TaskForce.Side.ROYAL_NAVY, BEAR)
	var off := _station(st, TaskForce.Side.ROYAL_NAVY, OCEAN)
	var mixed := _line(st, TaskForce.Side.ROYAL_NAVY, [NORTH_CAPE, BEAR])
	eq(st.arctic_share(on), 2, "una Stazione sulla Linea: tutta")
	eq(st.arctic_share(off), 0, "una Stazione altrove: niente")
	eq(st.arctic_share(mixed), 1, "una rotta meta' e meta': alcuni ma non tutti")


func test_time_lapse() -> void:
	_begin("RB p.20: Scorrere del Tempo sulla Linea Artica")
	var st := _state(TimeLapse.Weather.GOOD)
	var off := _line(st, TaskForce.Side.ROYAL_NAVY, [OCEAN, Vector2i(13, -4)])
	var mixed := _line(st, TaskForce.Side.ROYAL_NAVY, [NORTH_CAPE, BEAR])
	var all := _line(st, TaskForce.Side.ROYAL_NAVY, [BEAR, Vector2i(18, -12)])
	var table: int = TimeLapse.GOOD_REMOVAL[TimeLapse.Speed.MEDIUM]

	var before := st.rng.log.size()
	eq(TimeLapse.required_removal_for(off, st), table, "fuori dalla Linea: la Tabella")
	eq(st.rng.log.size(), before, "senza tirare")
	false_(TimeLapse.arctic_choice(off, st), "e senza scelta")

	true_(TimeLapse.arctic_choice(mixed, st), "caso misto: il giocatore sceglie")
	eq(TimeLapse.required_removal_for(mixed, st, false), table, "sceglie la Tabella")
	eq(st.rng.log.size(), before, "che non tira")
	st.rng.push_forced([5])
	eq(TimeLapse.required_removal_for(mixed, st, true), 5, "oppure il dado: 5")

	false_(TimeLapse.arctic_choice(all, st), "tutta sulla Linea: nessuna scelta")
	st.rng.push_forced([6])
	eq(TimeLapse.required_removal_for(all, st, false), 6,
		"si tira comunque, anche chiedendo la Tabella")

	st.weather = TimeLapse.Weather.BAD
	false_(TimeLapse.arctic_choice(mixed, st), "col Meteo Avverso non c'e' scelta")
	st.rng.push_forced([2])
	eq(TimeLapse.required_removal_for(off, st), 2, "e si tira ovunque")


func test_evasive_on_initiative() -> void:
	_begin("RB p.26: Manovre Evasive sull'Iniziativa, +2 sulla Linea Artica")
	var st := _state(TimeLapse.Weather.GOOD)
	var on := _station(st, TaskForce.Side.ROYAL_NAVY, BEAR)
	var off := _station(st, TaskForce.Side.ROYAL_NAVY, OCEAN)
	var mixed := _line(st, TaskForce.Side.ROYAL_NAVY, [NORTH_CAPE, BEAR])
	eq(Initiative.evasive_bonus(st, off), 1, "Meteo Buono, fuori dalla Linea: +1")
	eq(Initiative.evasive_bonus(st, on), 2, "Stazione sulla Linea: +2")
	eq(Initiative.evasive_bonus(st, mixed), 2, "basta UN segmento sulla Linea: +2")
	eq(Initiative.evasive_bonus(st), 1, "senza dire quale TF: +1")
	st.weather = TimeLapse.Weather.BAD
	eq(Initiative.evasive_bonus(st, off), 2, "col Meteo Avverso +2 a tutti")
	# il +2 entra davvero nel tiro di Sottrarre
	st.weather = TimeLapse.Weather.GOOD
	st.initiative = TaskForce.Side.KRIEGSMARINE
	on.evasive = true
	st.rng.push_forced([3, 4])
	var r := Initiative.steal(st, on)
	true_(bool(r.get("changed", false)), "2d6 = 7, +2: 9, l'Iniziativa passa")
	false_(on.evasive, "e il segnalino e' speso")


func _air_strike(st: GameState, from: Vector2i, to: Vector2i) -> ActionEngine.Declaration:
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "AIR_STRIKE"
	dec.active = _station(st, TaskForce.Side.ROYAL_NAVY, from, "Ark Royal")
	dec.target = _station(st, TaskForce.Side.KRIEGSMARINE, to, "Bismarck")
	dec.launch_hex = from
	dec.target_hex = to
	return dec


func test_air_strike() -> void:
	_begin("RB p.27: l'Attacco Aereo e la Linea Artica")
	var st := _state()
	eq(eng.legality_error(_air_strike(st, NORTH_CAPE, Vector2i(17, -10)), st), "",
		"sotto la Linea, fra due esagoni liberi: legale")
	var st2 := _state()
	true_(eng.legality_error(_air_strike(st2, BEAR, NORTH_CAPE), st2)
		.contains("Punto di Lancio non puo' essere sulla Linea Artica"),
		"non parte dalla Linea")
	var st3 := _state()
	true_(eng.legality_error(_air_strike(st3, NORTH_CAPE, BEAR), st3)
		.contains("bersaglio di un Attacco Aereo non puo' essere sulla Linea"),
		"non arriva sulla Linea")
	# l'esempio stampato: dalla base tedesca di Capo Nord a Murmansk
	var murmansk := Vector2i(20, -12)
	eq(Hex.distance(NORTH_CAPE, murmansk), 2, "Capo Nord e Murmansk sono a due esagoni")
	var st4 := _state()
	var blocked := eng.legality_error(_air_strike(st4, NORTH_CAPE, murmansk), st4)
	true_(blocked.contains("attraversare la Linea Artica"),
		"l'esempio di RB p.27: Capo Nord -> Murmansk attraversa la Linea (%s)" % blocked)
	# con un passaggio libero non e' bloccato
	false_(ActionEngine._air_path_blocked_by_arctic(Vector2i(16, -9),
		Vector2i(18, -11), st4), "se uno dei due esagoni in mezzo e' libero, passa")
	false_(ActionEngine._air_path_blocked_by_arctic(NORTH_CAPE, Vector2i(17, -10), st4),
		"a un esagono non c'e' niente da attraversare")
	# senza zone (mappa inserto) niente di tutto questo
	var bare := GameState.new(graph, 1)
	eq(eng.legality_error(_air_strike(bare, BEAR, NORTH_CAPE), bare), "",
		"senza il dato la regola non scatta: sugli inserti e' cosi'")


func test_air_support() -> void:
	_begin("RB p.45: Supporto Aereo e Linea Artica")
	var st := _state()
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "ENGAGE"
	dec.active = _station(st, TaskForce.Side.KRIEGSMARINE, NORTH_CAPE, "Bismarck")
	dec.target = _station(st, TaskForce.Side.ROYAL_NAVY, NORTH_CAPE, "Hood")
	dec.target_hex = NORTH_CAPE
	dec.active_air_support_hex = Vector2i(17, -10)
	eq(int(CommonModifiers.compute(dec, st)["total"]), 2,
		"bersaglio e lancio fuori dalla Linea: +2")
	dec.active_air_support_hex = BEAR
	eq(int(CommonModifiers.compute(dec, st)["total"]), 0,
		"Punto di Lancio sulla Linea: non si applica")
	# attraversare si puo': Capo Nord -> Murmansk, bersaglio a Murmansk
	var st2 := _state()
	var dec2 := ActionEngine.Declaration.new()
	dec2.action_key = "ENGAGE"
	dec2.active = _station(st2, TaskForce.Side.KRIEGSMARINE, Vector2i(20, -12), "Bismarck")
	dec2.target = _station(st2, TaskForce.Side.ROYAL_NAVY, Vector2i(20, -12), "Hood")
	dec2.target_hex = Vector2i(20, -12)
	dec2.active_air_support_hex = NORTH_CAPE
	eq(int(CommonModifiers.compute(dec2, st2)["total"]), 1,
		"il Supporto Aereo PUO' attraversare la Linea: +1 a due esagoni")
	# bersaglio sulla Linea
	var st3 := _state()
	var dec3 := ActionEngine.Declaration.new()
	dec3.action_key = "ENGAGE"
	dec3.active = _station(st3, TaskForce.Side.KRIEGSMARINE, BEAR, "Bismarck")
	dec3.target = _station(st3, TaskForce.Side.ROYAL_NAVY, BEAR, "Hood")
	dec3.target_hex = BEAR
	dec3.active_air_support_hex = NORTH_CAPE
	var r := CommonModifiers.compute(dec3, st3)
	eq(int(r["total"]), 0, "bersaglio sulla Linea: non si applica")
	true_("\n".join(r["lines"]).contains("Linea Artica"), "e la riga dice perche'")


func _stealth(st: GameState, kind: int, side: int, h: Vector2i) -> ActionEngine.Declaration:
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "STEALTH_ATTACK"
	dec.active_stealth = Stealth.place(st, side, kind, h)
	dec.target = _station(st, 1 - side, h)
	dec.target_hex = h
	return dec


func test_uboat_zone_bonus() -> void:
	_begin("RB p.41 e tabella stampata: +3 nella Zona U-Boat")
	eq(CommonModifiers.UBOAT_ZONE_BONUS, 3, "+3, come stampato")
	var st := _state()
	var km := TaskForce.Side.KRIEGSMARINE
	var rn := TaskForce.Side.ROYAL_NAVY
	eq(int(CommonModifiers.compute(_stealth(st, Stealth.Kind.UBOAT, km, OCEAN), st)["total"]),
		0, "in pieno Atlantico: niente")
	eq(int(CommonModifiers.compute(_stealth(st, Stealth.Kind.UBOAT, km, BISCAY), st)["total"]),
		3, "U-Boat in Biscaglia: +3")
	eq(int(CommonModifiers.compute(_stealth(st, Stealth.Kind.UBOAT, km, NARVIK), st)["total"]),
		3, "U-Boat davanti a Narvik: +3")
	eq(int(CommonModifiers.compute(_stealth(st, Stealth.Kind.SUBMARINE, rn,
		Vector2i(17, -6)), st)["total"]), 3,
		"vale anche per un Sottomarino britannico (p.41)")
	eq(int(CommonModifiers.compute(_stealth(st, Stealth.Kind.MINES, rn,
		Vector2i(16, -7)), st)["total"]), 3, "e per le Mine")
	# si somma al Convoglio Disperso
	var st2 := _state()
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "STEALTH_ATTACK"
	dec.active_stealth = Stealth.place(st2, km, Stealth.Kind.UBOAT, BISCAY)
	dec.target = _station(st2, rn, BISCAY, "Convoy x3")
	dec.target.ships[0].dispersed = true
	dec.target_hex = BISCAY
	eq(int(CommonModifiers.compute(dec, st2)["total"]), 5, "+3 e +2 del Convoglio Disperso")
	# non tocca le altre azioni
	var st3 := _state()
	var eng_dec := ActionEngine.Declaration.new()
	eng_dec.action_key = "ENGAGE"
	eng_dec.active = _station(st3, km, BISCAY, "Bismarck")
	eng_dec.target = _station(st3, rn, BISCAY, "Hood")
	eng_dec.target_hex = BISCAY
	eq(int(CommonModifiers.compute(eng_dec, st3)["total"]), 0,
		"un Ingaggio nella Zona non prende niente")
