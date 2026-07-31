extends TestCase

## Scorrere del Tempo, Totale Traiettoria, Interruzione.
##
## Dove possibile i casi riproducono gli ESEMPI STAMPATI nel regolamento, cosi'
## che un fraintendimento delle regole faccia fallire il test invece di
## sopravvivere silenziosamente nel codice.

var graph: MapGraph
var origin: Vector2i


func name() -> String:
	return "Regole: Tempo / Totale / Interruzione"


func run() -> void:
	graph = MapGraph.load_default()
	for h_v: Variant in graph.all_hexes():
		if graph.adjacent_hexes(h_v).size() == 6:
			origin = h_v
			break
	test_time_lapse_table()
	test_time_lapse_options()
	test_intel_limit_example_rb20()
	test_trajectory_total_simple()
	test_trajectory_total_example_rb18()
	test_interruption_table()
	test_interruption_results()
	test_rng_determinism()


func _chain(n: int) -> Trajectory:
	var t := Trajectory.new()
	t.station_hex = origin
	var cur := origin
	for i in n:
		var nxt := Vector2i.MAX
		for cand in graph.adjacent_hexes(cur):
			if not t.occupies(cand) and cand != origin:
				nxt = cand
				break
		if nxt == Vector2i.MAX:
			break
		t.extend(nxt, 1, graph)
		cur = nxt
	return t


func test_time_lapse_table() -> void:
	_begin("tabella Scorrere del Tempo")
	# valori letti dalla mappa: 2 / 2 / 3 / 4, Limite Informazioni 1 / 1 / 2 / 2
	var rng := DiceRNG.new(1)
	eq(TimeLapse.required_removal(TimeLapse.Speed.VERY_SLOW, TimeLapse.Weather.GOOD, rng),
		2, "molto lenta, meteo buono")
	eq(TimeLapse.required_removal(TimeLapse.Speed.SLOW, TimeLapse.Weather.GOOD, rng),
		2, "lenta, meteo buono")
	eq(TimeLapse.required_removal(TimeLapse.Speed.MEDIUM, TimeLapse.Weather.GOOD, rng),
		3, "media, meteo buono")
	eq(TimeLapse.required_removal(TimeLapse.Speed.FAST, TimeLapse.Weather.GOOD, rng),
		4, "veloce, meteo buono")
	eq(TimeLapse.intel_limit(TimeLapse.Speed.VERY_SLOW), 1, "limite molto lenta")
	eq(TimeLapse.intel_limit(TimeLapse.Speed.SLOW), 1, "limite lenta")
	eq(TimeLapse.intel_limit(TimeLapse.Speed.MEDIUM), 2, "limite media")
	eq(TimeLapse.intel_limit(TimeLapse.Speed.FAST), 2, "limite veloce")

	# meteo cattivo: si tira 1d6 e si rimuove quel numero
	var forced := DiceRNG.new(0)
	forced.push_forced([4])
	eq(TimeLapse.required_removal(TimeLapse.Speed.SLOW, TimeLapse.Weather.BAD, forced),
		4, "meteo cattivo: il dado comanda (esempio RB p.20: esce 4, rimuove 4)")


func test_time_lapse_options() -> void:
	_begin("opzioni di rimozione")
	var t := _chain(5)
	var opts := TimeLapse.removal_options(t, TimeLapse.Speed.MEDIUM, 3)
	true_(opts.size() > 0, "esistono opzioni")
	for o in opts:
		if not o["uses_intel_limit"]:
			eq(o["total"], 3, "senza Limite si rimuove esattamente l'ammontare")
	# senza segnalini Informazioni non esistono opzioni con Limite
	var with_limit := 0
	for o in opts:
		if o["uses_intel_limit"]:
			with_limit += 1
	eq(with_limit, 0, "nessun Limite di Informazioni senza segnalini")
	# le combinazioni testa/coda che sommano 3 sono 4: (0,3) (1,2) (2,1) (3,0)
	eq(opts.size(), 4, "quattro modi di distribuire 3 rimozioni fra i due capi")


func test_intel_limit_example_rb20() -> void:
	_begin("Limite di Informazioni - esempio RB p.20")
	# TF media (rimuoverebbe 3). Il segnalino Informazioni sta su un capo.
	# Invocando il Limite si rimuovono solo 2 segmenti in totale.
	var t := _chain(5)
	t.set_info(0, true)   # segnalino sul segmento di testa

	var opts := TimeLapse.removal_options(t, TimeLapse.Speed.MEDIUM, 3)

	var normal: Array[Dictionary] = []
	var limited: Array[Dictionary] = []
	for o in opts:
		if o["uses_intel_limit"]:
			limited.append(o)
		else:
			normal.append(o)

	true_(normal.size() > 0, "esistono opzioni senza Limite")
	for o in normal:
		eq(o["total"], 3, "senza Limite si rimuovono 3 segmenti")
		eq(o["ends"][0], 0, "senza Limite non si tocca la testa (ha Informazioni)")

	true_(limited.size() > 0, "esiste almeno una opzione con Limite")
	for o in limited:
		eq(o["total"], 2, "con Limite (TF media) il totale e' 2")
		true_(o["removes_info"], "il Limite rimuove davvero un segnalino")
		true_(o["ends"][0] >= 1, "la testa col segnalino viene rimossa")

	# TF lenta: il Limite vale 1, quindi si rimuove solo il segmento col segnalino
	var slow_opts := TimeLapse.removal_options(t, TimeLapse.Speed.SLOW, 2)
	var slow_limited: Array[Dictionary] = []
	for o in slow_opts:
		if o["uses_intel_limit"]:
			slow_limited.append(o)
	for o in slow_limited:
		eq(o["total"], 1, "con TF lenta il Limite consente un solo segmento")


func test_trajectory_total_simple() -> void:
	_begin("Totale Traiettoria - caso base RB p.17")
	# esempio del regolamento: TF Attiva 4 segmenti, Bersaglio 5 -> Totale 9
	var d := TrajectoryTotal.Designations.new(4, 5)
	eq(TrajectoryTotal.base_number(d), 9, "numero base 4+5")
	eq(TrajectoryTotal.compute(d), 9, "Totale Traiettoria 9")

	# una Stazione conta zero
	var d2 := TrajectoryTotal.Designations.new(0, 0)
	eq(TrajectoryTotal.compute(d2), 0, "due Stazioni danno zero")

	# mai negativo
	var d3 := TrajectoryTotal.Designations.new(1, 1)
	d3.target_coordinating = 9
	eq(TrajectoryTotal.compute(d3), 0, "il totale non scende sotto zero")


func test_trajectory_total_example_rb18() -> void:
	_begin("Totale Traiettoria - esempio illustrato RB p.18")
	# Britannico: TF Attiva 0 segmenti, Coordinatrice 3, Supporto Aereo 5.
	# La piu' lunga e' il Supporto Aereo con 5.
	# TF Bersaglio tedesca: 6 segmenti -> numero base 5 + 6 = 11.
	# Il tedesco ha una Coordinatrice da 4 -> 11 - 4 = 7.
	var d := TrajectoryTotal.Designations.new(0, 6)
	d.active_coordinating = 3
	d.active_air_support = 5
	d.target_coordinating = 4

	eq(TrajectoryTotal.longest_active(d), 5, "la piu' lunga e' il Supporto Aereo (5)")
	eq(TrajectoryTotal.base_number(d), 11, "numero base 5 + 6 = 11")
	eq(TrajectoryTotal.subtractions(d), 4, "sottrazione della Coordinatrice avversaria")
	eq(TrajectoryTotal.compute(d), 7, "Totale Traiettoria 7")
	true_(TrajectoryTotal.explain(d).size() >= 4, "la spiegazione ha tutti i passi")


func test_interruption_table() -> void:
	_begin("tabella Interruzione (letta dalla mappa)")
	# riga 2-4
	eq(Interruption.lookup(2, 1), "ALERT_0", "2-4 / 1 segnalino")
	eq(Interruption.lookup(4, 2), "ALERT_1", "2-4 / 2")
	eq(Interruption.lookup(3, 3), "ALERT_2", "2-4 / 3")
	eq(Interruption.lookup(4, 4), "SLIP_AWAY", "2-4 / 4+")
	# riga 5-7
	eq(Interruption.lookup(5, 1), "ALERT_1", "5-7 / 1")
	eq(Interruption.lookup(7, 2), "ALERT_2", "5-7 / 2")
	eq(Interruption.lookup(6, 3), "SLIP_AWAY", "5-7 / 3")
	eq(Interruption.lookup(7, 4), "VIE_FOR_INITIATIVE", "5-7 / 4+")
	# riga 8
	eq(Interruption.lookup(8, 1), "ALERT_2", "8 / 1")
	eq(Interruption.lookup(8, 2), "SLIP_AWAY", "8 / 2")
	eq(Interruption.lookup(8, 3), "VIE_FOR_INITIATIVE", "8 / 3")
	eq(Interruption.lookup(8, 4), "INITIATIVE_CHANGE", "8 / 4+")
	# riga 9
	eq(Interruption.lookup(9, 1), "SLIP_AWAY", "9 / 1")
	eq(Interruption.lookup(9, 2), "VIE_FOR_INITIATIVE", "9 / 2")
	eq(Interruption.lookup(9, 3), "INITIATIVE_CHANGE", "9 / 3")
	# riga 10-12
	eq(Interruption.lookup(10, 1), "VIE_FOR_INITIATIVE", "10-12 / 1")
	eq(Interruption.lookup(12, 2), "INITIATIVE_CHANGE", "10-12 / 2")
	eq(Interruption.lookup(11, 4), "INITIATIVE_CHANGE", "10-12 / 4+")
	# la colonna "4+" assorbe qualunque numero maggiore
	eq(Interruption.lookup(2, 7), Interruption.lookup(2, 4), "7 segnalini = colonna 4+")
	eq(Interruption.column_for(1), 0, "colonna 1")
	eq(Interruption.column_for(9), 3, "colonna 4+")


func test_interruption_results() -> void:
	_begin("risultati Interruzione")
	false_(Interruption.is_triggered(0), "senza segnalini non c'e' Interruzione")
	true_(Interruption.is_triggered(1), "con un segnalino c'e' Interruzione")

	var r := Interruption.resolve(2, 1)
	eq(r["result"], Interruption.Result.ALERT, "Allerta")
	eq(r["modifier"], 0, "Allerta -0 non modifica")
	r = Interruption.resolve(5, 2)
	eq(r["modifier"], -2, "Allerta -2")
	r = Interruption.resolve(9, 1)
	eq(r["result"], Interruption.Result.SLIP_AWAY, "Sfuggire")
	r = Interruption.resolve(10, 1)
	eq(r["result"], Interruption.Result.VIE_FOR_INITIATIVE, "Cercare l'Iniziativa")
	r = Interruption.resolve(12, 3)
	eq(r["result"], Interruption.Result.INITIATIVE_CHANGE, "Cambio di Iniziativa")

	# check() completo con dadi imposti: 3 + 4 = 7, due segnalini -> Allerta -2
	var rng := DiceRNG.new(0)
	rng.push_forced([3, 4])
	var c := Interruption.check(2, rng)
	true_(c["triggered"], "innescata")
	eq(c["sum"], 7, "somma dei dadi imposti")
	eq(c["code"], "ALERT_2", "risultato dalla tabella")

	# nessuna Interruzione senza segnalini: non si tira nemmeno
	var rng2 := DiceRNG.new(0)
	var c2 := Interruption.check(0, rng2)
	false_(c2["triggered"], "non innescata")
	eq(rng2.log.size(), 0, "non si tirano dadi se non serve")

	# conteggio sui segnalini delle sole TF designate
	var t1 := _chain(3)
	t1.set_info(0, true)
	t1.set_info(2, true)
	var t2 := _chain(2)
	t2.set_info(0, true)
	eq(Interruption.count_designated_info([t1, t2]), 3, "somma su tutte le designate")


func test_rng_determinism() -> void:
	_begin("determinismo del generatore")
	var a := DiceRNG.new(12345)
	var b := DiceRNG.new(12345)
	for i in 40:
		eq(a.d6("t"), b.d6("t"), "stesso seme, stessa sequenza")
	var c := DiceRNG.new(999)
	c.push_forced([6, 6, 1])
	eq(c.d6x2("prova"), 12, "i tiri imposti hanno la precedenza")
	eq(c.d6("prova"), 1, "consumati in ordine")
	true_(c.log.size() >= 4, "tutti i tiri sono registrati")
	eq(c.forced_remaining(), 0, "coda dei tiri imposti esaurita")
