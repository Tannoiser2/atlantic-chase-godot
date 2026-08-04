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
	test_enemy_presence_is_explained()
	test_bl2_french_force_is_reinforcement_only()
	test_battle_scenarios()
	test_predeployed_battle_is_preserved()
	test_battle_scenario_specials()


func _tf_for_side(bs: BattleState, side: int) -> TaskForce:
	return bs.active_tf if bs.active_tf.side == side else bs.target_tf


func test_list() -> void:
	_begin("elenco")
	var ids := Scenario.list_ids()
	eq(ids.size(), 37,
		"37 scenari (22 VASSAL + 15 solitari trascritti dal fascicolo)")
	true_(ids.has("Op5 Rheinubung"), "Rheinubung c'e'")
	true_(ids.has("MS1 Cornered"), "il primo mini-scenario c'e'")
	true_(ids.has("N1 Operazione Wilfred"), "il primo solitario N c'e'")
	true_(ids.has("A2 L'Ultima Battaglia"), "l'ultimo solitario c'e'")


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
		# Ogni scenario va validato sulla SUA mappa: cinque scenari solitari si
		# giocano su una mappa inserto, e una Traiettoria legale li' sarebbe
		# illegale sulla Mappa Operazionale e viceversa.
		var sc_graph := graph if sc.inset_key() == "" \
			else MapGraph.load_inset(sc.inset_key())
		var st := GameState.new(sc_graph, 1)
		st.apply_dict(sc.to_state_dict())
		for tf in st.task_forces:
			var errs := tf.trajectory.validate(sc_graph)
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
		"solo %d scenari VASSAL hanno avvisi: %s" % [flagged.size(), str(flagged)])


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

	for solo_id in ["BL1 Raiders of the North Atlantic",
			"BL2 Contain and Destroy", "BL3 Raiders of the North Sea"]:
		var solo_brief := Scenario.load_by_id(solo_id).briefing_text()
		false_(solo_brief.contains("Vedi il fascicolo"),
			"%s mostra la vera condizione di fine, non un rinvio" % solo_id)
	true_(Scenario.load_by_id("BL1 Raiders of the North Atlantic")
		.briefing_text().contains("OBIETTIVO"), "BL1 mostra l'obiettivo")


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
	# tutti e 22 gli scenari hanno ora le loro condizioni di vittoria
	for id in Scenario.list_ids():
		if id == "Campaign":
			continue      # la Campagna non e' uno scenario, e' la riserva navi
		true_(Scenario.load_by_id(id).has_victory_table(),
			"%s ha le sue condizioni di vittoria" % id)


func test_enemy_presence_is_explained() -> void:
	_begin("presenza TF avversarie")
	var bad: Array[String] = []
	var solo_one_side := 0
	var two_sided := 0
	for id in Scenario.list_ids():
		var sc := Scenario.load_by_id(id)
		if id == "Campaign" or sc.is_battle_scenario():
			continue
		var sides := {}
		for tf_v: Variant in sc.task_forces:
			var tf: Dictionary = tf_v
			sides[int(tf.get("side", -1))] = true
		if sides.size() >= 2:
			two_sided += 1
		elif SoloOpponent.load_for(id) != null:
			solo_one_side += 1
		else:
			bad.append(id)
	eq(bad.size(), 0,
		"nessuno scenario operativo non solitario parte senza avversario: %s" % str(bad))
	true_(solo_one_side >= 10,
		"%d scenari solitari partono con una sola parte e usano la tabella" % solo_one_side)
	true_(two_sided >= 10, "%d scenari partono con entrambe le parti in mappa" % two_sided)


func test_bl2_french_force_is_reinforcement_only() -> void:
	_begin("BL2: francesi solo come rinforzo")
	var sc := Scenario.load_by_id("BL2 Contain and Destroy")
	var setup_ships := {}
	for tf_v: Variant in sc.task_forces:
		var tf: Dictionary = tf_v
		for ship_v: Variant in tf.get("ships", []):
			setup_ships[String(ship_v)] = true
	var group_b: Array = sc.reinforcements.get("RN Reinforcement B", [])
	for ship in ["Strasbourg", "Dunkerque", "Gloire", "Montcalm"]:
		false_(setup_ships.has(ship), "BL2: %s non parte come TF sulla mappa" % ship)
		true_(group_b.has(ship), "BL2: %s resta nel Gruppo Rinforzi B" % ship)


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
		true_(bs.active_tf.ships.size() > 0, "%s: il giocatore Attivo ha navi" % id)
		true_(bs.target_tf.ships.size() > 0, "%s: il Bersaglio ha navi" % id)
		false_(sc.is_battle_scenario() and not sc.task_forces.is_empty(),
			"%s: o Battaglia o mappa operazionale, non tutt'e due" % id)

	# le coppie storiche devono tornare
	var ms9 := Scenario.load_by_id("MS9 Sink the Bismarck").make_battle_state()
	var km9: Array[String] = []
	for s in _tf_for_side(ms9, TaskForce.Side.KRIEGSMARINE).ships:
		km9.append(s.name)
	km9.sort()
	eq(km9, ["Bismarck", "Preugen"] as Array[String],
		"Stretto di Danimarca: Bismarck e Prinz Eugen")
	var rn9: Array[String] = []
	for s in _tf_for_side(ms9, TaskForce.Side.ROYAL_NAVY).ships:
		rn9.append(s.name)
	rn9.sort()
	eq(rn9, ["Hood", "Pow"] as Array[String], "contro Hood e Prince of Wales")

	# MS1 e' Rio de la Plata: il Graf Spee contro tre incrociatori
	var ms1 := Scenario.load_by_id("MS1 Cornered").make_battle_state()
	var km1 := _tf_for_side(ms1, TaskForce.Side.KRIEGSMARINE)
	var rn1 := _tf_for_side(ms1, TaskForce.Side.ROYAL_NAVY)
	eq(km1.ships.size(), 1, "un solo corsaro tedesco")
	eq(km1.ships[0].name, "Graf Spee", "ed e' il Graf Spee")
	eq(rn1.ships.size(), 3, "contro tre incrociatori britannici")

	# MS5 e' Mers-el-Kebir: britannici contro FRANCESI, senza una sola nave
	# tedesca. E' il caso che rompe l'euristica "cerca i tedeschi".
	var ms5 := Scenario.load_by_id("MS5 With Friends Like These")
	var b5 := ms5.make_battle_state()
	var fr := 0
	for s in _tf_for_side(b5, TaskForce.Side.KRIEGSMARINE).ships:
		if s.nation == "FR":
			fr += 1
	eq(fr, 4, "le quattro navi francesi stanno dalla parte avversaria")
	for s in _tf_for_side(b5, TaskForce.Side.ROYAL_NAVY).ships:
		eq(s.nation, "UK", "e dall'altra ci sono solo britannici")
	false_(ms5.has_import_warnings(), "senza avvisi di import")

	# le bande di partenza non sono tutte Lontane: in MS3 i britannici
	# partono gia' in zona Vicina
	var ms3 := Scenario.load_by_id("MS3 Norwegian Patrol").make_battle_state()
	for s in _tf_for_side(ms3, TaskForce.Side.ROYAL_NAVY).ships:
		eq(s.battle_zone, BattleState.Zone.NEAR,
			"%s parte in zona Vicina" % s.name)
	for s in _tf_for_side(ms3, TaskForce.Side.KRIEGSMARINE).ships:
		eq(s.battle_zone, BattleState.Zone.FAR,
			"%s parte in zona Lontana" % s.name)

	# uno scenario operazionale non e' una Battaglia
	false_(Scenario.load_by_id("Op5 Rheinubung").is_battle_scenario(),
		"la Rheinubung si gioca sulla mappa")

func test_predeployed_battle_is_preserved() -> void:
	_begin("schieramento dei mini-scenari mantenuto")
	var bs := Scenario.load_by_id("MS1 Cornered").make_battle_state()
	true_(bs.predeployed, "la Battaglia e' marcata come gia' schierata")
	var before := {}
	for s in bs.all_ships():
		before[s.name] = s.battle_zone
	Battle.new(bs, DiceRNG.new(3)).start()
	for s in bs.all_ships():
		eq(s.battle_zone, int(before[s.name]), "%s resta nella zona del fascicolo" % s.name)
	var graf := _tf_for_side(bs, TaskForce.Side.KRIEGSMARINE).ships[0]
	true_(bs.fixed_setup_attitudes.has(graf), "l'attitudine imposta e' bloccata")
	eq(Battle.new(bs, DiceRNG.new(4)).setup_attitudes_for(graf),
		[graf.attitude] as Array[int], "nel Round Uno non puo' essere cambiata")


func test_battle_scenario_specials() -> void:
	_begin("istruzioni speciali dei mini-scenari")
	var ms2 := Scenario.load_by_id("MS2 Escape").make_battle_state()
	eq(ms2.minimum_break_away_round, 3, "MS2 salta la Fuga sino al Round Tre")
	var graf := _tf_for_side(ms2, TaskForce.Side.KRIEGSMARINE).ships[0]
	eq(int(graf.get_meta("break_away_required_zone", -1)), BattleState.Zone.NEAR,
		"MS2: il Graf Spee fugge solo dalla zona Vicina")

	var ms3 := Scenario.load_by_id("MS3 Norwegian Patrol").make_battle_state()
	eq(ms3.weather, TimeLapse.Weather.BAD, "MS3 usa il meteo Sfavorevole")
	true_(ms3.skip_snafu, "MS3 salta la Verifica Snafu")
	eq(ms3.starting_confusion_side, TaskForce.Side.ROYAL_NAVY,
		"MS3 assegna Confusione al britannico")
	var dd3: Ship = _tf_for_side(ms3, TaskForce.Side.ROYAL_NAVY).ships.filter(
		func(s: Ship) -> bool: return s.name == "DD Squadron")[0]
	eq([dd3.torpedo_attack_limit, dd3.hit_limit], [2, 8],
		"MS3: lo Squadrone DD lancia due volte e regge otto Colpi")

	var ms10 := Scenario.load_by_id("MS10 Three Days Later").make_battle_state()
	eq(ms10.minimum_break_away_round, 2, "MS10 vieta la Fuga nel Round Uno")

	var ms11 := Scenario.load_by_id(
		"MS11 Skirmish on the Barents Sea").make_battle_state()
	eq(ms11.weather, TimeLapse.Weather.BAD, "MS11 usa il meteo Sfavorevole")
	var km11 := _tf_for_side(ms11, TaskForce.Side.KRIEGSMARINE)
	for s in km11.ships:
		eq(s.battle_zone, BattleState.Zone.NEAR,
			"MS11: %s parte in zona Vicina" % s.name)
	var rn11 := _tf_for_side(ms11, TaskForce.Side.ROYAL_NAVY)
	var dd11: Ship = rn11.ships.filter(
		func(s: Ship) -> bool: return s.name == "DD Squadron")[0]
	eq([dd11.torpedo_attack_limit, dd11.hit_limit], [2, 6],
		"MS11: doppio lancio e limite di sei Colpi sono dello Squadrone DD")
	eq(ms11.delayed_entry.size(), 2,
		"MS11 tiene fuori Fiji e Sheffield sino alla Fuga del Round Uno")

	ms3.advanced = true
	var b3 := Battle.new(ms3, DiceRNG.new(3))
	b3.start()
	eq(ms3.confusion_side, TaskForce.Side.ROYAL_NAVY,
		"MS3 applica davvero il segnalino Confusione senza tirare")
	true_(b3.snafu.is_empty(), "MS3 non applica di nascosto un altro Snafu")

	ms11.advanced = true
	var b11 := Battle.new(ms11, DiceRNG.new(11))
	b11.start()
	eq(ms11.target_ships().size(), 2,
		"MS11 comincia soltanto con Convoglio e Squadrone DD britannici")
	b11.break_away_phase(false, false)
	eq(ms11.target_ships().size(), 4,
		"Fiji e Sheffield entrano davvero all'inizio della fase di Fuga")

	var ms4 := Scenario.load_by_id("MS4 Chance Encounter").make_battle_state()
	var dd4: Ship = _tf_for_side(ms4, TaskForce.Side.ROYAL_NAVY).ships.filter(
		func(s: Ship) -> bool: return s.name == "DD Squadron")[0]
	eq(dd4.hit_limit, 2, "MS4: lo Squadrone DD e' distrutto al secondo Colpo")
	eq(dd4.torpedo_attack_limit, 1, "MS4: puo' lanciare i siluri una volta")
	true_(dd4.smoke, "MS4: lo Squadrone DD parte con il segnalino Fumo")

	var ms5 := Scenario.load_by_id(
		"MS5 With Friends Like These").make_battle_state()
	var battery: Ship = _tf_for_side(ms5, TaskForce.Side.KRIEGSMARINE).ships.filter(
		func(s: Ship) -> bool: return s.name == "Shore Battery")[0]
	false_(bool(SpecialEffects.apply(battery, SpecialEffects.RUDDER)["applied"]),
		"MS5: la Batteria Costiera e' immune agli Effetti Speciali")

	var ms6 := Scenario.load_by_id("MS6 Hard Lesson").make_battle_state()
	var dd6: Ship = _tf_for_side(ms6, TaskForce.Side.ROYAL_NAVY).ships.filter(
		func(s: Ship) -> bool: return s.name == "DD Squadron")[0]
	eq([dd6.hit_limit, dd6.torpedo_attack_limit], [1, 0],
		"MS6: Jervis Bay affonda al primo Colpo e non ha siluri")
	false_(Maneuver.can_make_smoke(dd6), "MS6: Jervis Bay non produce Fumo")
