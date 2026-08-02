extends TestCase

## Iniziativa e Verifica Meteo (RB p.25, p.54).


func name() -> String:
	return "Iniziativa"


func run() -> void:
	test_weather_check()
	test_seek_initiative()
	test_steal_initiative()
	test_decline_for_evasive()


func test_weather_check() -> void:
	_begin("Verifica Meteo")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.weather = TimeLapse.Weather.GOOD
	st.rng.push_forced([6])
	var r := Initiative.weather_check(st)
	true_(r["changed"], "con meteo buono il 6 cambia")
	eq(st.weather, TimeLapse.Weather.BAD, "diventa cattivo")

	st.rng.push_forced([5])
	r = Initiative.weather_check(st)
	true_(r["changed"], "con meteo cattivo il 5 cambia")
	eq(st.weather, TimeLapse.Weather.GOOD, "torna buono")


func test_seek_initiative() -> void:
	_begin("Cercare l'Iniziativa")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.initiative = TaskForce.Side.KRIEGSMARINE
	st.initiative_count = 2
	st.rng.push_forced([3, 2])
	var r := Initiative.seek(st)
	true_(r["changed"], "l'Inattivo supera con il Conto")
	eq(st.initiative, TaskForce.Side.ROYAL_NAVY, "l'Iniziativa cambia")
	eq(st.initiative_count, 0, "il Conto si azzera")

	st.rng.push_forced([4, 4])
	r = Initiative.seek(st)
	false_(r["changed"], "la parita' resta all'Attivo")
	eq(st.initiative_count, 1, "il Conto sale")


func test_steal_initiative() -> void:
	_begin("Sottrarre l'Iniziativa")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.initiative = TaskForce.Side.KRIEGSMARINE
	st.initiative_count = 1
	st.rng.push_forced([3, 4])
	var r := Initiative.steal(st)
	false_(r["success"], "7 + 1 non basta")
	eq(st.initiative_count, 2, "fallire aumenta il Conto")

	st.rng.push_forced([4, 4, 1])
	r = Initiative.steal(st)
	true_(r["success"], "8 + 2 basta")
	eq(st.initiative, TaskForce.Side.ROYAL_NAVY, "l'Inattivo prende iniziativa")
	eq(st.initiative_count, 0, "il Conto si azzera")


func test_decline_for_evasive() -> void:
	_begin("Rinuncia al tiro")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.initiative_count = 3
	var tf := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	Initiative.decline_steal_for_evasive(st, tf)
	eq(st.initiative_count, 3, "il Conto non aumenta")
	true_(tf.evasive, "la TF prende Manovre Evasive")
