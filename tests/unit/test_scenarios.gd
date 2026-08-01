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
	test_victory_table()
	test_battle_scenarios()


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


## Tabella dei Punti Vittoria. E' un dato per scenario, non del regolamento:
## nella Rheinubung affondare il Bismarck vale 7 VP, un incrociatore 2.
func test_victory_table() -> void:
	_begin("tabella VP dello scenario")
	var sc := Scenario.load_by_id("Op5 Rheinubung")
	true_(sc.has_victory_table(), "Rheinubung ha la tabella VP trascritta")
	var v := Victory.from_scenario(sc)
	true_(v.has_table, "il motore la carica")

	var st := GameState.new(graph, 1)
	st.apply_dict(sc.to_state_dict())

	# il Bismarck vale molto piu' di un incrociatore
	var bismarck := ShipRoster.shared().make("Bismarck")
	var eugen := ShipRoster.shared().make("Preugen")
	var a_sunk := v.awards_for(Victory.Event.SHIP_SUNK, bismarck)
	eq(a_sunk.size(), 1, "una sola voce per il Bismarck affondato")
	eq(int(a_sunk[0]["points"]), 7, "vale 7 VP")
	eq(int(a_sunk[0]["side"]), TaskForce.Side.ROYAL_NAVY, "al britannico")

	# il Prinz Eugen prende punti solo se si sa CHI lo controlla: la tabella
	# della Rheinubung ragiona per controllo, non per bandiera, perche' con la
	# Variante Francese le navi francesi giocano su tutti e due i lati
	var km_ctx := {"owner": "KRIEGSMARINE"}
	var e_sunk := v.awards_for(Victory.Event.SHIP_SUNK, eugen, km_ctx)
	eq(e_sunk.size(), 1, "una sola voce per il Prinz Eugen affondato")
	eq(int(e_sunk[0]["points"]), 2, "il Prinz Eugen affondato ne vale 2")
	eq(v.awards_for(Victory.Event.SHIP_SUNK, eugen).size(), 0,
		"senza sapere chi lo controlla il motore non assegna niente")
	var lost := v.unevaluated(Victory.Event.SHIP_SUNK, eugen)
	true_(lost.size() > 0, "ma lo segnala invece di perderlo in silenzio")
	true_(String(lost[0]["missing"][0]) == "owner", "e dice cosa manca")

	# applicazione allo stato
	v.apply_event(st, Victory.Event.SHIP_SUNK, bismarck)
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 7, "i VP finiscono nello stato")
	var o := v.outcome(st)
	eq(int(o["winner"]), TaskForce.Side.ROYAL_NAVY, "con 7 a 0 vince il britannico")
	false_(o["tie"], "non e' parita'")

	# parita': la clausola di questo scenario NON e' valutabile in automatico
	var st2 := GameState.new(graph, 1)
	var o2 := v.outcome(st2)
	true_(o2["tie"], "0 a 0 e' parita'")
	false_(o2["resolved"], "la clausola va verificata dai giocatori")
	true_(String(o2["tiebreak_text"]).contains("Bismarck"),
		"e viene mostrata: " + String(o2["tiebreak_text"]))

	# uno scenario senza tabella lo dichiara invece di inventare punteggi
	var ms := Scenario.load_by_id("MS1 Cornered")
	false_(ms.has_victory_table(), "i mini-scenari non hanno ancora la tabella")
	var v2 := Victory.from_scenario(ms)
	true_(v2.describe(GameState.new(graph, 1)).contains("non trascritta"),
		"e il motore lo dice")


## I dodici mini-scenari non sono partite sulla mappa operazionale: sono
## Battaglie gia' schierate. Le navi partono dentro il pannello della Mappa di
## Battaglia, senza Traiettorie ne' Stazioni - ed e' per questo che a lungo
## sono sembrati "vuoti": l'importatore cercava rotte che non esistono.
func test_battle_scenarios() -> void:
	_begin("mini-scenari: Battaglie gia' schierate")
	var ids := Scenario.list_ids()
	var battle_ids: Array[String] = []
	for id in ids:
		if Scenario.load_by_id(id).is_battle_scenario():
			battle_ids.append(id)
	eq(battle_ids.size(), 12, "dodici mini-scenari con lo schieramento")

	for id in battle_ids:
		var sc := Scenario.load_by_id(id)
		var bs := sc.make_battle_state()
		ne(bs, null, "%s: la Battaglia si costruisce" % id)
		true_(bs.active_tf.ships.size() > 0, "%s: il tedesco ha navi" % id)
		true_(bs.target_tf.ships.size() > 0, "%s: il britannico ha navi" % id)
		false_(sc.is_battle_scenario() and not sc.task_forces.is_empty(),
			"%s: o Battaglia o mappa operazionale, non tutt'e due" % id)

	# le coppie storiche devono tornare
	var ms9 := Scenario.load_by_id("MS9 Sink the Bismarck").make_battle_state()
	var km9: Array[String] = []
	for s in ms9.active_tf.ships:
		km9.append(s.name)
	km9.sort()
	eq(km9, ["Bismarck", "Preugen"] as Array[String],
		"Stretto di Danimarca: Bismarck e Prinz Eugen")
	var rn9: Array[String] = []
	for s in ms9.target_tf.ships:
		rn9.append(s.name)
	rn9.sort()
	eq(rn9, ["Hood", "Pow"] as Array[String], "contro Hood e Prince of Wales")

	# MS1 e' Rio de la Plata: il Graf Spee contro tre incrociatori
	var ms1 := Scenario.load_by_id("MS1 Cornered").make_battle_state()
	eq(ms1.active_tf.ships.size(), 1, "un solo corsaro tedesco")
	eq(ms1.active_tf.ships[0].name, "Graf Spee", "ed e' il Graf Spee")
	eq(ms1.target_tf.ships.size(), 3, "contro tre incrociatori britannici")

	# MS5 e' Mers-el-Kebir: britannici contro FRANCESI, senza una sola nave
	# tedesca. E' il caso che rompe l'euristica "cerca i tedeschi".
	var ms5 := Scenario.load_by_id("MS5 With Friends Like These")
	var b5 := ms5.make_battle_state()
	var fr := 0
	for s in b5.active_tf.ships:
		if s.nation == "FR":
			fr += 1
	eq(fr, 4, "le quattro navi francesi stanno dalla parte avversaria")
	for s in b5.target_tf.ships:
		eq(s.nation, "UK", "e dall'altra ci sono solo britannici")
	false_(ms5.has_import_warnings(), "senza avvisi di import")

	# le bande di partenza non sono tutte Lontane: in MS3 i britannici
	# partono gia' in zona Vicina
	var ms3 := Scenario.load_by_id("MS3 Norwegian Patrol").make_battle_state()
	for s in ms3.target_tf.ships:
		eq(s.battle_zone, BattleState.Zone.NEAR,
			"%s parte in zona Vicina" % s.name)
	for s in ms3.active_tf.ships:
		eq(s.battle_zone, BattleState.Zone.FAR,
			"%s parte in zona Lontana" % s.name)

	# uno scenario operazionale non e' una Battaglia
	false_(Scenario.load_by_id("Op5 Rheinubung").is_battle_scenario(),
		"la Rheinubung si gioca sulla mappa")
