extends TestCase

## Modificatori Comuni (RB pp.45-47), Manovre Evasive sull'Iniziativa (pp.24,
## 46) e la scelta dell'avversario immaginario fra Sottrarre e Manovre Evasive
## (AC Solo scenarios 2022 p.2).
##
## Nessuno di questi era implementato prima del 2026-11: la suite esisteva
## verde, e il gioco tirava le azioni senza un solo modificatore.

var graph: MapGraph
var eng: ActionEngine
var origin: Vector2i       ## un esagono con sei vicini
var near: Vector2i         ## adiacente a origin
var far: Vector2i          ## a due esagoni da origin
var beyond: Vector2i       ## a tre esagoni da origin


func name() -> String:
	return "Modificatori Comuni e Manovre Evasive"


func run() -> void:
	graph = MapGraph.load_default()
	eng = ActionEngine.load_default()
	_pick_hexes()
	test_printed_tables()
	test_contact()
	test_coordination_both_sides()
	test_coordination_by_stealth_force()
	test_air_support_by_range()
	test_air_support_needs_good_weather()
	test_air_strike_source_is_its_own_air_support()
	test_evasive_against_an_action()
	test_evasive_not_spent_when_interruption_cancels()
	test_dispersed_convoy_bonus()
	test_printed_modifier_adds_up()
	test_options_and_auto_designation()
	test_target_supports_do_time_lapse()
	test_evasive_on_initiative_rolls()
	test_evasive_chooses_removed_segments()
	test_imaginary_steal_choice()
	test_scenarios_that_always_seize()
	test_emptied_identified_tf_is_removed()


## Quattro esagoni in fila a distanza 0, 1, 2 e 3 dall'origine.
func _pick_hexes() -> void:
	for h_v: Variant in graph.all_hexes():
		var h: Vector2i = h_v
		if graph.adjacent_hexes(h).size() != 6:
			continue
		for a in graph.adjacent_hexes(h):
			for b in graph.adjacent_hexes(a):
				if Hex.distance(h, b) != 2:
					continue
				for c in graph.adjacent_hexes(b):
					if Hex.distance(h, c) == 3:
						origin = h
						near = a
						far = b
						beyond = c
						return


func _state(weather: int = TimeLapse.Weather.GOOD) -> GameState:
	var st := GameState.new(graph, 1)
	st.weather = weather
	return st


func _station(st: GameState, side: int, h: Vector2i, ship: String = "Sheffield",
		speed: int = TimeLapse.Speed.MEDIUM) -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	tf.ships.append(ShipRoster.shared().make(ship))
	tf.trajectory.become_station(h)
	tf.speed = speed
	st.add_task_force(tf)
	return tf


func _line(st: GameState, side: int, hexes: Array, ship: String = "Sheffield") -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	tf.ships.append(ShipRoster.shared().make(ship))
	for h_v: Variant in hexes:
		tf.trajectory.segments.append({"hex": h_v, "info": false, "contact": false})
	st.add_task_force(tf)
	return tf


## Un Ingaggio tedesco contro una Stazione britannica nell'esagono d'origine.
func _engage(st: GameState) -> ActionEngine.Declaration:
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "ENGAGE"
	dec.active = _station(st, TaskForce.Side.KRIEGSMARINE, origin, "Bismarck")
	dec.target = _station(st, TaskForce.Side.ROYAL_NAVY, origin, "Hood")
	dec.target_hex = origin
	return dec


func _total(dec: ActionEngine.Declaration, st: GameState) -> int:
	return int(CommonModifiers.compute(dec, st)["total"])


func test_printed_tables() -> void:
	_begin("le tabelle stampate (RB pp.45-47)")
	eq(CommonModifiers.air_support_value(0, true), 3, "Supporto Aereo Attivo, nell'esagono")
	eq(CommonModifiers.air_support_value(1, true), 2, "Attivo, adiacente")
	eq(CommonModifiers.air_support_value(2, true), 1, "Attivo, a due esagoni")
	eq(CommonModifiers.air_support_value(3, true), 0, "oltre due esagoni non vale")
	eq(CommonModifiers.air_support_value(0, false), -2, "Bersaglio, nell'esagono")
	eq(CommonModifiers.air_support_value(1, false), -1, "Bersaglio, adiacente")
	eq(CommonModifiers.air_support_value(2, false), 0, "Bersaglio, a due esagoni: zero")
	eq(CommonModifiers.contact_value(TimeLapse.Speed.VERY_SLOW), 4, "Contatto, molto lenta")
	eq(CommonModifiers.contact_value(TimeLapse.Speed.SLOW), 3, "Contatto, lenta")
	eq(CommonModifiers.contact_value(TimeLapse.Speed.MEDIUM), 2, "Contatto, media")
	eq(CommonModifiers.contact_value(TimeLapse.Speed.FAST), 2, "Contatto, veloce")
	eq(CommonModifiers.evasive_value(TimeLapse.Weather.GOOD), -1, "Manovre Evasive, Meteo Buono")
	eq(CommonModifiers.evasive_value(TimeLapse.Weather.BAD), -2, "Manovre Evasive, Meteo Avverso")
	eq(CommonModifiers.coordination_value(TimeLapse.Weather.GOOD, true), 2, "Coordinamento Attivo, Buono")
	eq(CommonModifiers.coordination_value(TimeLapse.Weather.BAD, true), 1, "Coordinamento Attivo, Avverso")
	eq(CommonModifiers.coordination_value(TimeLapse.Weather.GOOD, false), -1, "Coordinamento Bersaglio")
	eq(CommonModifiers.coordination_value(TimeLapse.Weather.BAD, false), -1, "Bersaglio: -1 con ogni meteo")
	true_(CommonModifiers.applies_to("ENGAGE") and CommonModifiers.applies_to("NAVAL_SEARCH")
		and CommonModifiers.applies_to("AIR_STRIKE") and CommonModifiers.applies_to("STEALTH_ATTACK"),
		"valgono per le quattro azioni su tabella (p.23)")
	false_(CommonModifiers.applies_to("TRAJECTORY") or CommonModifiers.applies_to("PASS"),
		"e non per le altre")


func test_contact() -> void:
	_begin("Contatto: solo se il bersaglio ha il segnalino")
	var st := _state()
	var dec := _engage(st)
	eq(_total(dec, st), 0, "senza segnalino nessun modificatore")
	dec.target.trajectory.station_contact = true
	eq(_total(dec, st), 2, "Stazione media con Contatto: +2")
	dec.target.speed = TimeLapse.Speed.SLOW
	eq(_total(dec, st), 3, "lenta: +3")
	dec.target.speed = TimeLapse.Speed.VERY_SLOW
	eq(_total(dec, st), 4, "molto lenta: +4")

	# Su una Traiettoria conta il segmento BERSAGLIO, non uno qualunque.
	var st2 := _state()
	var search := ActionEngine.Declaration.new()
	search.action_key = "NAVAL_SEARCH"
	search.active = _station(st2, TaskForce.Side.KRIEGSMARINE, origin, "Bismarck")
	search.target = _line(st2, TaskForce.Side.ROYAL_NAVY, [origin, near, far], "Hood")
	search.target_hex = origin
	search.target.trajectory.set_contact_at(far, true)
	eq(_total(search, st2), 0, "il Contatto su un altro segmento non conta")
	search.target.trajectory.set_contact_at(origin, true)
	eq(_total(search, st2), 2, "quello sul segmento bersaglio si'")


func test_coordination_both_sides() -> void:
	_begin("Coordinamento: +2/+1 all'Attivo, -1 al Bersaglio")
	var st := _state()
	var dec := _engage(st)
	dec.active_coordinating = _station(st, TaskForce.Side.KRIEGSMARINE, origin, "Scharnhorst")
	eq(_total(dec, st), 2, "Attivo col Meteo Buono: +2")
	st.weather = TimeLapse.Weather.BAD
	eq(_total(dec, st), 1, "Attivo col Meteo Avverso: +1")
	dec.target_coordinating = _station(st, TaskForce.Side.ROYAL_NAVY, origin, "Rodney")
	eq(_total(dec, st), 0, "il Bersaglio toglie 1")
	st.weather = TimeLapse.Weather.GOOD
	eq(_total(dec, st), 1, "+2 e -1 col Meteo Buono")
	eq(eng.legality_error(dec, st), "", "due Coordinatrici nell'esagono Bersaglio sono legali")
	dec.target_coordinating.trajectory.become_station(near)
	true_(eng.legality_error(dec, st) != "",
		"una Coordinatrice fuori dall'esagono Bersaglio no (p.47)")


func test_coordination_by_stealth_force() -> void:
	_begin("una forza Furtiva puo' coordinare (p.47)")
	var st := _state()
	var dec := _engage(st)
	var sub := Stealth.place(st, TaskForce.Side.ROYAL_NAVY, Stealth.Kind.SUBMARINE, origin)
	dec.target_coordinating_stealth = sub
	eq(_total(dec, st), -1, "il Sottomarino del Bersaglio vale -1")
	eq(eng.legality_error(dec, st), "", "ed e' una designazione legale")
	dec.target_coordinating = _station(st, TaskForce.Side.ROYAL_NAVY, origin, "Rodney")
	true_(eng.legality_error(dec, st) != "", "ma una sola forza Coordinatrice per giocatore")
	dec.target_coordinating = null
	var elsewhere := Stealth.place(st, TaskForce.Side.ROYAL_NAVY, Stealth.Kind.MINES, far)
	dec.target_coordinating_stealth = elsewhere
	true_(eng.legality_error(dec, st) != "", "e deve stare nell'esagono Bersaglio")


func test_air_support_by_range() -> void:
	_begin("Supporto Aereo: vale per la distanza")
	var st := _state()
	var dec := _engage(st)
	dec.active_air_support_hex = origin
	eq(_total(dec, st), 3, "Attivo, nell'esagono Bersaglio: +3")
	dec.active_air_support_hex = near
	eq(_total(dec, st), 2, "adiacente: +2")
	dec.active_air_support_hex = far
	eq(_total(dec, st), 1, "a due esagoni: +1")
	dec.active_air_support_hex = beyond
	eq(_total(dec, st), 0, "a tre non arriva")
	dec.active_air_support_hex = origin
	dec.target_air_support_hex = near
	# l'esempio di RB p.45: +3 dell'Attivo nell'esagono, -1 del Bersaglio
	# adiacente, totale +2
	eq(_total(dec, st), 2, "l'esempio stampato a p.45: +3 e -1 fanno +2")
	dec.target_air_support_hex = origin
	eq(_total(dec, st), 1, "Bersaglio nell'esagono: -2")
	# Una TF designata senza dire da dove lancia usa il suo esagono migliore.
	var st2 := _state()
	var dec2 := _engage(st2)
	dec2.active_air_support = _line(st2, TaskForce.Side.KRIEGSMARINE,
		[beyond, far, near], "Grzeppelin")
	eq(_total(dec2, st2), 2, "la portaerei lancia dal segmento piu' vicino: adiacente, +2")


func test_air_support_needs_good_weather() -> void:
	_begin("Supporto Aereo: solo Meteo Buono")
	var st := _state(TimeLapse.Weather.BAD)
	var dec := _engage(st)
	dec.active_air_support_hex = origin
	dec.target_air_support_hex = origin
	eq(_total(dec, st), 0, "col Meteo Avverso non si applica a nessuno")
	var lines: Array = CommonModifiers.compute(dec, st)["lines"]
	eq(lines.size(), 2, "e lo dice, una riga per parte")


func test_air_strike_source_is_its_own_air_support() -> void:
	_begin("nell'Attacco Aereo la fonte e' il Supporto Aereo (p.27)")
	var st := _state()
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "AIR_STRIKE"
	dec.active = _station(st, TaskForce.Side.ROYAL_NAVY, near, "Ark Royal")
	dec.target = _station(st, TaskForce.Side.KRIEGSMARINE, origin, "Bismarck")
	dec.launch_hex = near
	dec.target_hex = origin
	eq(_total(dec, st), 2, "lancio dall'esagono adiacente: +2 senza designare altro")
	eq(eng.legality_error(dec, st), "", "ed e' un Attacco Aereo legale")
	st.rng.push_forced([3, 3])
	var res := eng.resolve(dec, st)
	eq(int(res["modifier"]), 2, "il +2 entra nel tiro")
	eq(int(res["sum"]), 8, "6 di dadi piu' 2")


func test_evasive_against_an_action() -> void:
	_begin("Manovre Evasive contro un'azione (p.46)")
	var st := _state()
	var dec := _engage(st)
	dec.target.evasive = true
	eq(_total(dec, st), 0, "avere il segnalino non basta: va speso")
	dec.target_spends_evasive = true
	eq(_total(dec, st), -1, "speso col Meteo Buono: -1")
	st.weather = TimeLapse.Weather.BAD
	eq(_total(dec, st), -2, "col Meteo Avverso: -2")
	st.rng.push_forced([4, 4])
	var res := eng.resolve(dec, st)
	eq(int(res["sum"]), 6, "8 di dadi meno 2")
	false_(dec.target.evasive, "e il segnalino se ne va")
	# Senza segnalino la richiesta di spenderlo non inventa un modificatore.
	var st2 := _state()
	var dec2 := _engage(st2)
	dec2.target_spends_evasive = true
	eq(_total(dec2, st2), 0, "non si spende quello che non si ha")


func test_evasive_not_spent_when_interruption_cancels() -> void:
	_begin("un'Interruzione che annulla non consuma il segnalino")
	var st := _state()
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "ENGAGE"
	dec.active = _line(st, TaskForce.Side.KRIEGSMARINE, [near, origin], "Bismarck")
	dec.target = _station(st, TaskForce.Side.ROYAL_NAVY, origin, "Hood")
	dec.target_hex = origin
	dec.target.evasive = true
	dec.target_spends_evasive = true
	dec.active.trajectory.set_info(0, true)
	# Si cerca un tiro d'Interruzione che annulli: con un segnalino la banda
	# cambia da un tiro all'altro, quindi si provano tutte le somme.
	var canceled := false
	for a in range(1, 7):
		for b in range(1, 7):
			dec.target.evasive = true
			st.rng.push_forced([a, b, 3, 3])
			var res := eng.resolve(dec, st)
			var ir: Dictionary = res["interruption"]
			# toglie dalla coda i dadi dell'azione rimasti quando non si tira
			while st.rng.forced_remaining() > 0:
				st.rng.d6("scarto")
			if int(ir.get("result", Interruption.Result.ALERT)) != Interruption.Result.ALERT:
				canceled = true
				true_(dec.target.evasive,
					"Interruzione %d+%d annulla: il segnalino resta" % [a, b])
				break
		if canceled:
			break
	true_(canceled, "almeno un tiro d'Interruzione annulla l'azione")


func test_dispersed_convoy_bonus() -> void:
	_begin("Attacco Furtivo tedesco a un Convoglio Disperso: +2 (p.41)")
	var st := _state()
	var dec := ActionEngine.Declaration.new()
	dec.action_key = "STEALTH_ATTACK"
	dec.active_stealth = Stealth.place(st, TaskForce.Side.KRIEGSMARINE,
		Stealth.Kind.UBOAT, origin)
	dec.target = _station(st, TaskForce.Side.ROYAL_NAVY, origin, "Convoy x3")
	dec.target_hex = origin
	eq(_total(dec, st), 0, "un Convoglio in formazione non da' niente")
	dec.target.ships[0].dispersed = true
	eq(_total(dec, st), 2, "Disperso: +2")
	dec.active_stealth["side"] = TaskForce.Side.ROYAL_NAVY
	dec.target.side = TaskForce.Side.KRIEGSMARINE
	eq(_total(dec, st), 0, "il bonus e' stampato per l'attacco TEDESCO")
	var lines: Array = CommonModifiers.compute(dec, st)["lines"]
	var declared := false
	for l_v: Variant in lines:
		if String(l_v).contains("Zona U-Boat"):
			declared = true
	true_(declared, "la Zona U-Boat resta una lacuna DICHIARATA, non un +3 inventato")


func test_printed_modifier_adds_up() -> void:
	_begin("il modificatore di una procedura stampata si somma ai Comuni")
	var st := _state()
	var dec := _engage(st)
	dec.modifier = 3
	dec.target.trajectory.station_contact = true
	st.rng.push_forced([1, 1])
	var res := eng.resolve(dec, st)
	eq(int(res["modifier"]), 5, "+3 stampato e +2 di Contatto")
	eq(int(res["sum"]), 7, "2 di dadi piu' 5")
	eq((res["modifier_lines"] as Array).size(), 2, "una riga per ciascuno")
	true_(eng.describe(res).contains("Contatto"), "il riassunto dice da dove viene il numero")


func test_options_and_auto_designation() -> void:
	_begin("che cosa puo' designare una parte, e la policy del bot (solitario p.1)")
	var st := _state()
	var dec := _engage(st)
	var ge := TaskForce.Side.KRIEGSMARINE
	var rn := TaskForce.Side.ROYAL_NAVY
	# `null` al posto del grafo: le basi aeree STAMPATE sulla mappa restano
	# fuori da questo caso, che misura le Task Force. L'esagono di prova e'
	# scelto per la forma, e puo' cadere accanto a una coccarda RAF.
	var o := CommonModifiers.options_for(dec, st, null, rn)
	eq((o["coordinating_tfs"] as Array).size(), 0, "senza altre forze non c'e' niente da designare")
	false_(bool(o["evasive"]), "ne' un segnalino da spendere")
	var coord := _station(st, rn, origin, "Rodney")
	var carrier := _line(st, rn, [beyond, far], "Ark Royal")
	var too_far := _station(st, rn, beyond, "Victorious")
	dec.target.evasive = true
	o = CommonModifiers.options_for(dec, st, null, rn)
	eq((o["coordinating_tfs"] as Array).size(), 1, "la TF nell'esagono Bersaglio puo' coordinare")
	eq((o["air_tfs"] as Array).size(), 1, "una sola portaerei e' a portata")
	eq(int(((o["air_tfs"] as Array)[0] as Dictionary)["distance"]), 2, "a due esagoni")
	true_(bool(o["evasive"]), "e la TF Bersaglio ha il segnalino")
	eq((CommonModifiers.options_for(dec, st, graph, ge)["coordinating_tfs"] as Array).size(), 0,
		"all'Attivo quelle forze non servono: sono dell'altro")
	false_(bool(CommonModifiers.options_for(dec, st, graph, ge)["evasive"]),
		"e le Manovre Evasive le spende solo chi subisce")

	CommonModifiers.designate_all(dec, st, null, rn, true)
	eq(dec.target_coordinating, coord, "il bot designa la Coordinatrice")
	eq(dec.target_air_support, carrier, "e la portaerei a portata")
	eq(dec.target_air_support_hex, far, "dal suo esagono piu' vicino")
	true_(dec.target_spends_evasive, "e spende il segnalino appena puo' (p.2)")
	# -1 Coordinamento, 0 Supporto Aereo a due esagoni, -1 Manovre Evasive
	eq(_total(dec, st), -2, "il conto torna")
	true_(too_far != null, "la portaerei a tre esagoni resta fuori")

	# Col Meteo Avverso il Supporto Aereo non si designa nemmeno.
	var st2 := _state(TimeLapse.Weather.BAD)
	var dec2 := _engage(st2)
	_line(st2, rn, [beyond, far], "Ark Royal")
	CommonModifiers.designate_all(dec2, st2, graph, rn, true)
	eq(dec2.target_air_support, null, "niente fonte aerea col Meteo Avverso")

	# Una base aerea piazzata conta come fonte, e a parita' si preferisce.
	var st3 := _state()
	var dec3 := _engage(st3)
	AirBase.place(st3, ge, near)
	CommonModifiers.designate_all(dec3, st3, graph, ge, true)
	eq(dec3.active_air_support_hex, near, "l'Attivo lancia dalla base aerea adiacente")
	eq(dec3.active_air_support, null, "che non e' una Task Force")
	eq(_total(dec3, st3), 2, "e vale +2")

	# Il giocatore simulato puo' designare senza spendere.
	var st4 := _state()
	var dec4 := _engage(st4)
	dec4.target.evasive = true
	CommonModifiers.designate_all(dec4, st4, graph, rn, false)
	false_(dec4.target_spends_evasive, "spend_evasive=false lascia il segnalino dov'e'")


func test_target_supports_do_time_lapse() -> void:
	_begin("le TF designate dal Bersaglio fanno lo Scorrere del Tempo")
	var st := _state()
	var dec := _engage(st)
	var coord := _station(st, TaskForce.Side.ROYAL_NAVY, origin, "Rodney")
	var carrier := _line(st, TaskForce.Side.ROYAL_NAVY, [beyond, far], "Ark Royal")
	dec.target_coordinating = coord
	dec.target_air_support = carrier
	var list := dec.designated_target_support()
	eq(list.size(), 2, "Coordinatrice e Supporto Aereo del Bersaglio")
	false_(list.has(dec.target), "la TF Bersaglio no (pp.27, 31, 33)")
	# e le loro lunghezze si sottraggono dal Totale Traiettoria, come prima
	var d := dec.to_designations()
	eq(d.target_air_support, 2, "la lunghezza della TF di Supporto Aereo e' nel conto")


func test_evasive_on_initiative_rolls() -> void:
	_begin("Manovre Evasive sui tiri d'Iniziativa: +1 / +2 (pp.24, 46)")
	var st := _state()
	st.initiative = TaskForce.Side.KRIEGSMARINE
	var tf := _station(st, TaskForce.Side.ROYAL_NAVY, origin)
	eq(Initiative.evasive_bonus(st), 1, "Meteo Buono: +1")
	st.weather = TimeLapse.Weather.BAD
	eq(Initiative.evasive_bonus(st), 2, "Meteo Avverso: +2")

	# Sottrarre: 7 non basta, 7 + 2 si'.
	tf.evasive = true
	st.rng.push_forced([3, 4, 1])
	var r := Initiative.steal(st, tf)
	true_(bool(r["success"]), "7 + 2 di Manovre Evasive arriva a 9")
	false_(tf.evasive, "il segnalino e' speso")
	eq(int(r["modifier"]), 2, "il modificatore e' nel risultato")

	# Senza segnalino la TF indicata non regala niente.
	st.initiative = TaskForce.Side.KRIEGSMARINE
	st.initiative_count = 0
	st.weather = TimeLapse.Weather.BAD
	st.rng.push_forced([3, 4])
	r = Initiative.steal(st, tf)
	false_(bool(r["success"]), "una TF senza segnalino non da' modificatore")
	eq(int(r["modifier"]), 0, "zero")

	# Cercare: 3 contro 3 resta all'Attivo, 3 + 1 no.
	st.initiative = TaskForce.Side.KRIEGSMARINE
	st.initiative_count = 0
	st.weather = TimeLapse.Weather.GOOD
	tf.evasive = true
	st.rng.push_forced([3, 3, 1])
	r = Initiative.seek(st, tf)
	true_(bool(r["changed"]), "3 + 1 batte 3")
	false_(tf.evasive, "speso anche qui")
	st.initiative = TaskForce.Side.KRIEGSMARINE
	st.rng.push_forced([3, 3])
	r = Initiative.seek(st)
	false_(bool(r["changed"]), "senza spenderlo la parita' resta all'Attivo")


func _five(st: GameState) -> TaskForce:
	# cinque segmenti in fila: beyond-far-near-origin piu' un vicino di origin
	var tail := Vector2i.MAX
	for h in graph.adjacent_hexes(origin):
		if h != near and Hex.distance(h, far) == 3:
			tail = h
			break
	return _line(st, TaskForce.Side.ROYAL_NAVY, [beyond, far, near, origin, tail], "Hood")


func test_evasive_chooses_removed_segments() -> void:
	_begin("Manovre Evasive: l'Inattivo sceglie i segmenti (p.24)")
	var spend_front := {"spend_evasive": true, "drop_front": true}
	var spend_back := {"spend_evasive": true, "drop_front": false}

	# In Anticipo/In Ritardo sul segmento `near` (indice 2 di 5): davanti 2,
	# dietro 2... si usa `far` (indice 1): davanti 1, dietro 3.
	var st := _state()
	var tf := _five(st)
	var pv := Results.removal_preview("EARLY_LATE", tf, far)
	true_(bool(pv["choice"]), "un segmento in mezzo apre un buco: c'e' una scelta")
	eq(int(pv["front"]), 1, "un segmento davanti")
	eq(int(pv["back"]), 3, "tre dietro")
	Results.apply("EARLY_LATE", null, tf, far, st)
	eq(tf.length(), 1, "senza segnalino l'Attivo toglie il troncone piu' lungo: resta 1")

	var st2 := _state()
	var tf2 := _five(st2)
	tf2.evasive = true
	Results.apply("EARLY_LATE", null, tf2, far, st2, Callable(), -1, spend_front)
	eq(tf2.length(), 3, "spendendo, l'Inattivo perde il troncone corto: restano 3")
	false_(tf2.evasive, "e il segnalino e' speso")

	var st3 := _state()
	var tf3 := _five(st3)
	tf3.evasive = true
	Results.apply("EARLY_LATE", null, tf3, far, st3, Callable(), -1, spend_back)
	eq(tf3.length(), 1, "puo' anche scegliere l'altro")

	# Chiedere di spendere senza avere il segnalino non cambia niente.
	var st4 := _state()
	var tf4 := _five(st4)
	Results.apply("EARLY_LATE", null, tf4, far, st4, Callable(), -1, spend_front)
	eq(tf4.length(), 1, "senza segnalino decide comunque l'Attivo")

	# Ai capi non c'e' buco, quindi niente da scegliere.
	false_(bool(Results.removal_preview("EARLY_LATE", _five(_state()), beyond)["choice"]),
		"sul capo non c'e' scelta")

	# Seguire: restano 3 segmenti, e l'Inattivo sceglie da che parte accorciare.
	var st5 := _state()
	var tf5 := _five(st5)
	tf5.evasive = true
	var head := tf5.trajectory.end_hex(0)
	Results.apply("SHADOW", null, tf5, near, st5, Callable(), -1,
		{"spend_evasive": true, "remove_from_end": 1})
	eq(tf5.length(), 3, "Seguire lascia tre segmenti")
	eq(tf5.trajectory.end_hex(0), head, "accorciando dalla coda la testa resta dov'era")
	false_(tf5.evasive, "segnalino speso")
	var st6 := _state()
	var tf6 := _five(st6)
	var tail6 := tf6.trajectory.end_hex(1)
	Results.apply("SHADOW", null, tf6, near, st6)
	eq(tf6.trajectory.end_hex(1), tail6, "senza segnalino si accorcia dalla testa, come prima")
	true_(bool(Results.removal_preview("SHADOW", _five(_state()), near)["choice"]),
		"con piu' di tre segmenti c'e' una scelta")


func _opponent(always: bool = false) -> SoloOpponent:
	var o := SoloOpponent.new()
	o.always_seizes = always
	o.always_seizes_source = "prova"
	return o


func test_imaginary_steal_choice() -> void:
	_begin("avversario immaginario: Sottrarre o Manovre Evasive (solitario p.2)")
	var bot := TaskForce.Side.KRIEGSMARINE
	var st := _state()
	var o := _opponent()

	# Nessuna TF in gioco: tenta, senza tirare.
	var before := st.rng.log.size()
	var c := o.steal_choice(st, bot)
	true_(bool(c["attempt"]), "senza TF tenta di Sottrarre")
	eq(st.rng.log.size(), before, "e non tira il dado")

	var plain := _station(st, bot, origin, "Bismarck")
	var convoy := _station(st, bot, near, "Convoy x3")
	for die in [1, 2, 3, 4]:
		st.rng.push_forced([die])
		c = o.steal_choice(st, bot)
		true_(bool(c["attempt"]), "con %d tenta" % die)
	for die in [5, 6]:
		st.rng.push_forced([die])
		c = o.steal_choice(st, bot)
		false_(bool(c["attempt"]), "con %d prende il segnalino" % die)
		eq(c["evasive_to"], convoy, "e lo da' alla TF col Convoglio")

	# Senza Convoglio: una TF con una nave Danneggiata.
	convoy.evasive = true
	var hurt := _station(st, bot, far, "Scharnhorst")
	hurt.ships[0].damaged = true
	st.rng.push_forced([6])
	c = o.steal_choice(st, bot)
	eq(c["evasive_to"], hurt, "poi a una TF con una nave Danneggiata")
	# Senza ne' l'una ne' l'altra: una qualsiasi.
	hurt.evasive = true
	st.rng.push_forced([6])
	c = o.steal_choice(st, bot)
	eq(c["evasive_to"], plain, "poi a una qualsiasi")
	# Tutte gia' col segnalino: tenta, e spende appena puo'.
	plain.evasive = true
	before = st.rng.log.size()
	c = o.steal_choice(st, bot)
	true_(bool(c["attempt"]), "se tutte hanno gia' il segnalino tenta")
	eq(st.rng.log.size(), before, "senza tirare")
	eq(c["spend_from"], plain, "e spende il segnalino della TF con l'id piu' basso")

	# Una TF dell'ALTRA parte non conta.
	var st2 := _state()
	_station(st2, TaskForce.Side.ROYAL_NAVY, origin)
	before = st2.rng.log.size()
	c = o.steal_choice(st2, bot)
	true_(bool(c["attempt"]) and st2.rng.log.size() == before,
		"le TF del giocatore non danno al bot un posto per il segnalino")

	# "Tenta sempre": nessun dado, anche con una TF libera.
	var st3 := _state()
	_station(st3, bot, origin, "Bismarck")
	before = st3.rng.log.size()
	c = _opponent(true).steal_choice(st3, bot)
	true_(bool(c["attempt"]), "lo scenario che lo stampa fa tentare sempre")
	eq(st3.rng.log.size(), before, "senza dado")


func test_scenarios_that_always_seize() -> void:
	_begin("gli scenari che stampano 'tenta sempre' (pp.17, 28, 32)")
	for id in ["N1 Operazione Wilfred", "N4 Operazione Weser (nord & sud)",
			"N5 Meglio Tardi che Mai"]:
		var o := SoloOpponent.load_for(id)
		true_(o != null and o.always_seizes, "%s: tenta sempre" % id)
		true_(o != null and o.always_seizes_source.contains("p."),
			"%s: con la pagina citata" % id)
	for id in ["BL1 Raiders of the North Atlantic", "BL2 Contain and Destroy",
			"B3 Operazione Reno", "A2 L'Ultima Battaglia"]:
		var o := SoloOpponent.load_for(id)
		true_(o != null and not o.always_seizes, "%s: tira il dado di p.2" % id)


func test_emptied_identified_tf_is_removed() -> void:
	_begin("una TF identificata rimasta senza navi esce dal gioco (solitario p.1)")
	var st := _state()
	var rn := TaskForce.Side.ROYAL_NAVY
	var hurt := _station(st, rn, origin, "Belfast")
	hurt.ships[0].damaged = true
	var fine := _station(st, rn, near, "Sheffield")
	var ghost := _station(st, rn, far, "Rodney")
	ghost.ships.clear()
	ghost.unidentified = true
	SoloAI._remove_damaged_ships(st, rn)
	eq(st.task_force(hurt.id), null, "la TF svuotata dalla rimozione viene tolta")
	true_(st.task_force(fine.id) != null, "quella con navi integre resta")
	true_(st.task_force(ghost.id) != null,
		"una TF NON identificata e' vuota per definizione e resta")
