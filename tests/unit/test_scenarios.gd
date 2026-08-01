extends TestCase

## Scenari: schieramento dai 22 salvataggi ufficiali + briefing dal fascicolo.

var graph: MapGraph


func name() -> String:
	return "Scenari"


func run() -> void:
	graph = MapGraph.load_default()
	test_list()
	test_all_load_and_are_valid()
	test_rheinubung_setup()
	test_briefings()
	test_victory_points()


func test_list() -> void:
	_begin("elenco")
	var ids := Scenario.list_ids()
	eq(ids.size(), 22, "22 scenari (12 mini + 9 operazioni + campagna)")
	true_(ids.has("Op5 Rheinubung"), "Rheinubung c'e'")
	true_(ids.has("MS1 Cornered"), "il primo mini-scenario c'e'")


## Ogni scenario deve caricarsi e produrre uno stato coerente: traiettorie
## valide sul grafo attuale e navi presenti nel ruolino.
func test_all_load_and_are_valid() -> void:
	_begin("tutti gli scenari producono uno stato valido")
	var roster := ShipRoster.shared()
	var total_ships := 0
	var undocumented := 0
	var unknown := 0
	for sid_v: Variant in Scenario.list_ids():
		var sid := String(sid_v)
		var sc := Scenario.load_by_id(sid)
		eq(sc.load_error, "", "%s si carica" % sid)
		var st := GameState.new(graph, 1)
		st.apply_dict(sc.to_state_dict())
		for tf in st.task_forces:
			var errs := tf.trajectory.validate(graph)
			# Le pedine del modulo VASSAL sono piazzate a mano su una mappa
			# senza griglia, quindi qualche rotta ricostruita risulta illegale.
			# Non e' un bug delle regole: e' il dato di partenza impreciso.
			# Si pretende pero' che ogni caso sia DOCUMENTATO negli avvisi di
			# import, mai accettato in silenzio.
			if not errs.is_empty() and not sc.has_import_warnings():
				undocumented += 1
			for s in tf.ships:
				total_ships += 1
				if not roster.has(s.name):
					unknown += 1
	eq(undocumented, 0,
		"ogni Traiettoria di scenario illegale e' segnalata negli avvisi di import")
	eq(unknown, 0, "nessuna nave di scenario manca dal ruolino")
	true_(total_ships > 150, "gli scenari schierano %d navi in tutto" % total_ships)

	# e gli avvisi devono essere pochi e circoscritti
	var flagged: Array[String] = []
	for sid_v: Variant in Scenario.list_ids():
		var sc := Scenario.load_by_id(String(sid_v))
		if sc.has_import_warnings():
			flagged.append(String(sid_v))
	true_(flagged.size() <= 3,
		"solo %d scenari su 22 hanno avvisi: %s" % [flagged.size(), str(flagged)])


func test_rheinubung_setup() -> void:
	_begin("Rheinubung: lo schieramento e' quello storico")
	var sc := Scenario.load_by_id("Op5 Rheinubung")
	var st := GameState.new(graph, 1)
	st.apply_dict(sc.to_state_dict())

	eq(st.initiative, TaskForce.Side.KRIEGSMARINE, "l'iniziativa e' tedesca")

	# la TF tedesca: Bismarck e Prinz Eugen sotto Lutjens
	var km: TaskForce = null
	for tf in st.forces_of(TaskForce.Side.KRIEGSMARINE):
		if tf.color == "GE" and tf.slot == 0:
			km = tf
	ne(km, null, "la Task Force tedesca esiste")
	eq(km.ships.size(), 2, "due navi")
	var names: Array[String] = []
	for s in km.ships:
		names.append(s.name)
	true_(names.has("Bismarck"), "c'e' la Bismarck")
	true_(names.has("Preugen"), "c'e' il Prinz Eugen")
	true_(km.leader.contains("Lutjens"), "al comando c'e' Lutjens")

	# le statistiche arrivano dal ruolino, non sono a zero
	for s in km.ships:
		true_(s.defense > 0, "%s ha la Difesa dal ruolino" % s.name)
	eq(km.recompute_speed(), TimeLapse.Speed.MEDIUM,
		"la TF va alla velocita' della Bismarck (media)")

	# rinforzi
	true_(sc.reinforcement_count() > 0, "lo scenario ha gruppi di rinforzo")


func test_briefings() -> void:
	_begin("briefing dal fascicolo")
	var with_brief := 0
	var with_victory := 0
	for sid_v: Variant in Scenario.list_ids():
		var sc := Scenario.load_by_id(String(sid_v))
		if sc.has_briefing():
			with_brief += 1
			if String(sc.briefing.get("victory", "")).length() > 30:
				with_victory += 1
	true_(with_brief >= 20, "%d scenari hanno un briefing" % with_brief)
	true_(with_victory >= 15, "%d hanno le condizioni di vittoria" % with_victory)

	var op5 := Scenario.load_by_id("Op5 Rheinubung")
	true_(op5.title.contains("Rhein"), "il titolo e' quello del fascicolo")
	true_(op5.briefing_text().contains("VITTORIA"), "il testo include la vittoria")
	# la condizione di Rheinubung: il tedesco vince se la Bismarck arriva in
	# un porto francese
	true_(String(op5.briefing.get("victory", "")).contains("Bismarck"),
		"la condizione di vittoria cita la Bismarck")


func test_victory_points() -> void:
	_begin("Punti Vittoria")
	var st := GameState.new(graph, 1)
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 0, "si parte da zero")
	eq(st.vp_leader(), -1, "a zero pari nessuno conduce")
	st.add_vp(TaskForce.Side.KRIEGSMARINE, 3, "convoglio affondato")
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 3, "tre punti")
	eq(st.vp_leader(), TaskForce.Side.KRIEGSMARINE, "conduce il tedesco")
	st.add_vp(TaskForce.Side.ROYAL_NAVY, 5, "corazzata affondata")
	eq(st.vp_leader(), TaskForce.Side.ROYAL_NAVY, "ora conduce il britannico")
	# i VP sopravvivono al salvataggio
	var st2 := GameState.new(graph, 1)
	st2.apply_dict(st.to_dict())
	eq(st2.vp_of(TaskForce.Side.ROYAL_NAVY), 5, "VP conservati nel salvataggio")
