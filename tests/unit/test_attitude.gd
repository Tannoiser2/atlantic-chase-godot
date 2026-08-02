extends TestCase

## Attitudine delle navi (Regole Avanzate di Battaglia, pp.3-4).
##
## E' la scelta tattica centrale delle regole avanzate, e ogni attitudine e' un
## baratto: chi punta non manovra, chi avanza non fugge, chi fugge non silura.

var graph: MapGraph


func name() -> String:
	return "Attitudine (Regole Avanzate)"


func run() -> void:
	graph = MapGraph.load_default()
	test_setup_rules()
	test_acquiring()
	test_closing()
	test_running()
	test_break_away_modifier()
	test_serialization()
	test_scenario_attitudes()


func _ship(n: String, zone: int, att: int, torp: bool = true) -> Ship:
	var s := Ship.new(n, TimeLapse.Speed.FAST)
	s.gun_close = 3
	s.gun_far = 2
	# anche il lato danneggiato: senza, una nave Danneggiata risulta senza
	# cannoni ("na") e non potrebbe dividere il fuoco per un motivo che non
	# c'entra niente con l'attitudine
	s.gun_close_damaged = 2
	s.gun_far_damaged = 1
	s.defense = 3
	s.defense_damaged = 2
	s.has_torpedo = torp
	s.battle_zone = zone
	s.attitude = att
	return s


func _battle(kind: int = BattleState.Kind.BATTLE) -> BattleState:
	var st := BattleState.new(kind, TimeLapse.Weather.GOOD)
	var a := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	a.name = "KM"
	a.ships = [_ship("Bismarck", BattleState.Zone.FAR, Attitude.Kind.CLOSING)] as Array[Ship]
	var b := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	b.name = "RN"
	b.ships = [_ship("Hood", BattleState.Zone.FAR, Attitude.Kind.CLOSING)] as Array[Ship]
	st.active_tf = a
	st.target_tf = b
	return st


## Le navi Attive DEVONO cominciare in Avvicinamento: e' l'unica non-scelta
## della regola, ed e' coerente - chi ha dichiarato l'Ingaggio si sta
## avvicinando per definizione.
func test_setup_rules() -> void:
	_begin("attitudine al piazzamento")
	var act := Attitude.setup_options(true)
	eq(act.size(), 1, "l'Attivo non sceglie")
	eq(act[0], Attitude.Kind.CLOSING, "e deve avvicinarsi")

	var tgt := Attitude.setup_options(false)
	eq(tgt.size(), 2, "il Bersaglio sceglie fra due")
	true_(tgt.has(Attitude.Kind.CLOSING), "puo' avvicinarsi")
	true_(tgt.has(Attitude.Kind.RUNNING), "oppure correre")
	false_(tgt.has(Attitude.Kind.ACQUIRING),
		"ma nessuno comincia in Acquisizione")

	# dopo una SORPRESA le attitudini del bersaglio le sceglie l'Attivo
	false_(Attitude.active_chooses_for_target(BattleState.Kind.BATTLE),
		"in una Battaglia normale sceglie il Bersaglio")
	true_(Attitude.active_chooses_for_target(BattleState.Kind.SURPRISE),
		"ma colto di sorpresa non decide come reagire")

	var st := _battle()
	st.target_ships()[0].attitude = Attitude.Kind.ACQUIRING
	Attitude.apply_setup(st, {st.target_ships()[0]: Attitude.Kind.ACQUIRING})
	eq(st.active_ships()[0].attitude, Attitude.Kind.CLOSING,
		"l'Attiva finisce in Avvicinamento")
	eq(st.target_ships()[0].attitude, Attitude.Kind.CLOSING,
		"e un'Acquisizione illegale al piazzamento diventa Avvicinamento")


## Acquisizione: spara meglio OPPURE divide il fuoco, ma non fa nient'altro.
func test_acquiring() -> void:
	_begin("Acquisizione")
	var s := _ship("Tirpitz", BattleState.Zone.NEAR, Attitude.Kind.ACQUIRING)

	eq(Attitude.gunnery_column(s), "acquiring", "usa la sua colonna")
	true_(Attitude.can_split_fire(s, "close"), "e puo' dividere il fuoco")
	false_(Attitude.can_torpedo(s), "ma non silura")
	false_(Attitude.can_maneuver(s), "non manovra")
	eq(Attitude.maneuver_direction(s), 0, "resta ferma")
	false_(Attitude.can_make_smoke(s), "non fa Fumo")
	false_(Attitude.can_pursue(s), "non insegue")
	false_(Attitude.can_break_away(s), "e non puo' fuggire")

	# danneggiata perde la colonna ma non la divisione del fuoco
	s.damaged = true
	eq(Attitude.gunnery_column(s), "closing",
		"danneggiata perde il beneficio della colonna")
	true_(Attitude.can_split_fire(s, "close"),
		"ma puo' ancora dividere il fuoco")

	# lo stesso vale per un effetto speciale
	var s2 := _ship("Hipper", BattleState.Zone.NEAR, Attitude.Kind.ACQUIRING)
	s2.special_effects.append("timone")
	true_(s2.has_special_effect(), "ha un effetto speciale")
	eq(Attitude.gunnery_column(s2), "closing", "e perde la colonna")

	# senza valore dei cannoni non si divide niente
	var s3 := _ship("Convoy", BattleState.Zone.NEAR, Attitude.Kind.ACQUIRING)
	s3.gun_close = null
	false_(Attitude.can_split_fire(s3, "close"),
		"un valore 'na' non si divide")


## Avvicinamento: la nave che va addosso al nemico.
func test_closing() -> void:
	_begin("Avvicinamento")
	var s := _ship("Hood", BattleState.Zone.NEAR, Attitude.Kind.CLOSING)

	eq(Attitude.gunnery_column(s), "closing", "colonna normale")
	false_(Attitude.can_split_fire(s, "close"), "non divide il fuoco")
	true_(Attitude.can_torpedo(s), "silura")
	true_(Attitude.can_maneuver(s), "manovra")
	eq(Attitude.maneuver_direction(s), 1, "e si muove verso il nemico")
	false_(Attitude.can_make_smoke(s), "non fa Fumo")
	true_(Attitude.can_pursue(s), "puo' Inseguire dalla zona Vicina")
	false_(Attitude.can_break_away(s), "ma non puo' fuggire")

	# l'Inseguimento vale solo da Vicina o Ravvicinata
	var far := _ship("Renown", BattleState.Zone.FAR, Attitude.Kind.CLOSING)
	false_(Attitude.can_pursue(far), "da Lontano non si insegue")


## Corsa: l'unica che puo' andarsene.
func test_running() -> void:
	_begin("Corsa")
	var s := _ship("Graf Spee", BattleState.Zone.NEAR, Attitude.Kind.RUNNING)

	eq(Attitude.gunnery_column(s), "closing", "colonna normale")
	false_(Attitude.can_torpedo(s), "non silura")
	true_(Attitude.can_maneuver(s), "manovra")
	eq(Attitude.maneuver_direction(s), -1, "ma si allontana")
	true_(Attitude.can_make_smoke(s), "puo' fare Fumo")
	false_(Attitude.can_pursue(s), "non insegue")
	true_(Attitude.can_break_away(s), "ed e' l'unica che puo' fuggire")

	# chi la silura ha -2: sta scappando
	eq(Attitude.torpedo_target_modifier(s), -2, "difficile da silurare")
	eq(Attitude.torpedo_target_modifier(
		_ship("x", BattleState.Zone.NEAR, Attitude.Kind.CLOSING)), 0,
		"una nave che si avvicina no")

	# un Convoglio non fa Fumo nemmeno in Corsa (RB p.11)
	var c := Ship.new("Convoglio", TimeLapse.Speed.SLOW, Ship.Kind.CONVOY)
	c.attitude = Attitude.Kind.RUNNING
	false_(Attitude.can_make_smoke(c), "un Convoglio non fa Fumo mai")


## Il modificatore alla Fuga: -1 se un nemico e' vicino, -1 in piu' se quel
## nemico si sta anche avvicinando.
func test_break_away_modifier() -> void:
	_begin("modificatore alla Fuga")
	var st := _battle()
	var enemy: Ship = st.target_ships()[0]

	enemy.battle_zone = BattleState.Zone.FAR
	eq(Attitude.break_away_modifier(st, true), 0,
		"un nemico Lontano non trattiene nessuno")

	enemy.battle_zone = BattleState.Zone.NEAR
	enemy.attitude = Attitude.Kind.RUNNING
	eq(Attitude.break_away_modifier(st, true), -1,
		"un nemico Vicino vale -1")

	enemy.attitude = Attitude.Kind.CLOSING
	eq(Attitude.break_away_modifier(st, true), -2,
		"e se si sta avvicinando -2")

	# una nave che si avvicina da LONTANO non aggiunge niente
	enemy.battle_zone = BattleState.Zone.FAR
	eq(Attitude.break_away_modifier(st, true), 0,
		"l'avvicinamento conta solo da Vicina o Ravvicinata")

	# le navi affondate non trattengono nessuno
	enemy.battle_zone = BattleState.Zone.CLOSE
	enemy.sunk = true
	eq(Attitude.break_away_modifier(st, true), 0, "una nave affondata no")


func test_serialization() -> void:
	_begin("attitudine ed effetti nel salvataggio")
	var s := _ship("Scharnhorst", BattleState.Zone.CLOSE, Attitude.Kind.RUNNING)
	s.special_effects.append("timone bloccato")
	var back := Ship.from_dict(s.to_dict())
	eq(back.attitude, Attitude.Kind.RUNNING, "l'attitudine si salva")
	eq(back.special_effects.size(), 1, "e gli effetti speciali")
	true_(back.has_special_effect(), "che restano riconoscibili")

	# con le regole BASE non c'e' attitudine: una nave nuova e' in
	# Avvicinamento, cosi' il modello base resta corretto senza toccarlo
	eq(Ship.new("x").attitude, Attitude.Kind.CLOSING,
		"il valore di partenza e' Avvicinamento")

	eq(Attitude.from_marker("RUNNING"), Attitude.Kind.RUNNING,
		"i marcatori del fascicolo si leggono")
	eq(Attitude.from_marker("ACQUIRING"), Attitude.Kind.ACQUIRING, "tutti e tre")
	eq(Attitude.label(Attitude.Kind.ACQUIRING), "Acquisizione", "con i nomi")


## Le attitudini di partenza dei mini-scenari, lette dal fascicolo.
func test_scenario_attitudes() -> void:
	_begin("attitudini di partenza dei mini-scenari")
	var n := 0
	for id in Scenario.list_ids():
		var sc := Scenario.load_by_id(id)
		if sc.is_battle_scenario():
			true_(sc.attitudes().size() > 0,
				"%s ha le attitudini trascritte" % id)
			n += 1
	eq(n, 12, "tutti e dodici i mini-scenari")

	# MS9 e' l'unico che comincia in Acquisizione: lo Stretto di Danimarca,
	# dove i tedeschi aprono il fuoco per primi e meglio
	var ms9 := Scenario.load_by_id("MS9 Sink the Bismarck").make_battle_state()
	for s in ms9.active_tf.ships:
		eq(s.attitude, Attitude.Kind.ACQUIRING,
			"%s parte in Acquisizione" % s.name)
		eq(Attitude.gunnery_column(s), "acquiring",
			"e usa la colonna Acquisizione")
		false_(Attitude.can_break_away(s), "ma non puo' fuggire")
	for s in ms9.target_tf.ships:
		eq(s.attitude, Attitude.Kind.CLOSING, "%s si avvicina" % s.name)

	# MS1: il Graf Spee scappa, i tre incrociatori lo inseguono
	var ms1 := Scenario.load_by_id("MS1 Cornered").make_battle_state()
	eq(ms1.active_tf.ships[0].attitude, Attitude.Kind.RUNNING,
		"il Graf Spee corre")
	true_(Attitude.can_break_away(ms1.active_tf.ships[0]),
		"e quindi puo' tentare la Fuga")
	for s in ms1.target_tf.ships:
		eq(s.attitude, Attitude.Kind.CLOSING, "%s lo insegue" % s.name)
		false_(Attitude.can_break_away(s), "e non puo' andarsene")

	# "ANY" resta al valore predefinito: la scelta e' del giocatore
	var ms2 := Scenario.load_by_id("MS2 Escape")
	eq(String(ms2.attitudes().get("Ajax", "")), "ANY",
		"in MS2 i britannici scelgono")
	eq(ms2.make_battle_state().target_tf.ships[0].attitude,
		Attitude.Kind.CLOSING,
		"e il motore lascia il valore predefinito invece di decidere")
