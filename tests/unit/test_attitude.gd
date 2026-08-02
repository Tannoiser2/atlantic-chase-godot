extends TestCase

## Attitudine delle navi (Regole Avanzate di Battaglia, pp.3-4).
##
## E' la scelta tattica centrale delle regole avanzate, e ogni attitudine e' un
## baratto: chi punta non manovra, chi avanza non fugge, chi fugge non silura.

var graph: MapGraph


func name() -> String:
	return "Regole Avanzate di Battaglia"


func run() -> void:
	graph = MapGraph.load_default()
	test_setup_rules()
	test_acquiring()
	test_closing()
	test_running()
	test_break_away_modifier()
	test_serialization()
	test_scenario_attitudes()
	test_advanced_gunnery_table()
	test_crippled()
	test_split_fire()
	test_stopped_speed()
	test_advanced_toggle()
	test_advanced_torpedo()


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


## La Tabella del Fuoco avanzata: due colonne al posto di una.
func test_advanced_gunnery_table() -> void:
	_begin("Tabella del Fuoco avanzata")
	var R := AdvancedGunnery.Result

	# colonna Avvicinamento / Corsa / Divide
	var c := AdvancedGunnery.COLUMN_CLOSING
	eq(AdvancedGunnery.read(c, 6), R.SPLASH, "6 o meno: Splash")
	eq(AdvancedGunnery.read(c, 8), R.SPLASH, "8: ancora Splash")
	eq(AdvancedGunnery.read(c, 9), R.HIT, "9: Colpo")
	eq(AdvancedGunnery.read(c, 10), R.HIT, "10: Colpo")
	eq(AdvancedGunnery.read(c, 11), R.SEVERE, "11: Risultato Grave")
	eq(AdvancedGunnery.read(c, 14), R.SEVERE, "e sopra il 12 resta Grave")

	# colonna Acquisizione: meglio di una casella su tutta la tabella
	var a := AdvancedGunnery.COLUMN_ACQUIRING
	eq(AdvancedGunnery.read(a, 6), R.SPLASH, "6 o meno: Splash anche qui")
	eq(AdvancedGunnery.read(a, 7), R.HIT, "7: dove l'altra fa Splash, colpisce")
	eq(AdvancedGunnery.read(a, 9), R.SEVERE, "9: dove l'altra colpisce, e' Grave")
	eq(AdvancedGunnery.read(a, 12), R.CATASTROPHIC, "12: Catastrofico")

	# ed e' l'unica che arriva al Catastrofico
	var found := false
	for row_v: Variant in c:
		if int((row_v as Array)[1]) == R.CATASTROPHIC:
			found = true
	false_(found, "l'altra colonna non arriva mai al Catastrofico")


## "Azzoppata" = Danneggiata OPPURE con un effetto speciale. Perde la colonna
## Acquisizione ma non l'attitudine, e puo' ancora dividere il fuoco.
func test_crippled() -> void:
	_begin("navi azzoppate")
	var s := _ship("Suffolk", BattleState.Zone.FAR, Attitude.Kind.ACQUIRING)
	false_(AdvancedGunnery.is_crippled(s), "integra non e' azzoppata")
	eq(AdvancedGunnery.column_for(s), AdvancedGunnery.COLUMN_ACQUIRING,
		"e usa la colonna Acquisizione")

	s.damaged = true
	true_(AdvancedGunnery.is_crippled(s), "danneggiata e' azzoppata")
	eq(AdvancedGunnery.column_for(s), AdvancedGunnery.COLUMN_CLOSING,
		"e perde la colonna")

	var s2 := _ship("Hipper", BattleState.Zone.FAR, Attitude.Kind.ACQUIRING)
	s2.special_effects.append("Incendio")
	true_(AdvancedGunnery.is_crippled(s2),
		"anche un effetto speciale azzoppa")

	# chi divide il fuoco rinuncia alla colonna: i due benefici sono
	# alternativi, non cumulabili
	var s3 := _ship("Bismarck", BattleState.Zone.FAR, Attitude.Kind.ACQUIRING)
	eq(AdvancedGunnery.column_for(s3, 1), AdvancedGunnery.COLUMN_ACQUIRING,
		"un bersaglio solo: colonna Acquisizione")
	eq(AdvancedGunnery.column_for(s3, 2), AdvancedGunnery.COLUMN_CLOSING,
		"due bersagli: si rinuncia alla colonna")


## Dividere il fuoco: valore 1 o piu', due parti non negative che sommano al
## valore. Il caso limite che il fascicolo cita: 1 si divide in 1 e 0.
func test_split_fire() -> void:
	_begin("dividere il fuoco")
	var s := _ship("Bismarck", BattleState.Zone.FAR, Attitude.Kind.ACQUIRING)
	s.gun_close = 2
	eq(AdvancedGunnery.split_refusal(s, "close", [2, 0]), "",
		"2 si divide in 2 e 0")
	eq(AdvancedGunnery.split_refusal(s, "close", [1, 1]), "", "oppure 1 e 1")
	ne(AdvancedGunnery.split_refusal(s, "close", [1, 0]), "",
		"ma le parti devono sommare al valore")
	ne(AdvancedGunnery.split_refusal(s, "close", [3, -1]), "",
		"e nessuna puo' essere negativa")
	ne(AdvancedGunnery.split_refusal(s, "close", [2]), "",
		"i bersagli sono esattamente due")

	s.gun_close = 1
	eq(AdvancedGunnery.split_refusal(s, "close", [1, 0]), "",
		"un valore di 1 si divide in 1 e 0: lo dice il fascicolo")

	s.gun_close = 0
	ne(AdvancedGunnery.split_refusal(s, "close", [0, 0]), "",
		"ma uno zero non si divide")

	s.gun_close = 2
	s.attitude = Attitude.Kind.CLOSING
	ne(AdvancedGunnery.split_refusal(s, "close", [1, 1]), "",
		"e solo l'Acquisizione puo' dividere")


## FERMA e' una velocita' nuova, e vale -1 apposta.
func test_stopped_speed() -> void:
	_begin("velocita' Ferma")
	# la numerazione esistente NON deve essere cambiata: gli scenari salvano
	# la velocita' come intero, e "speed": 2 deve restare "media"
	eq(int(TimeLapse.Speed.VERY_SLOW), 0, "molto lenta resta 0")
	eq(int(TimeLapse.Speed.SLOW), 1, "lenta resta 1")
	eq(int(TimeLapse.Speed.MEDIUM), 2, "media resta 2")
	eq(int(TimeLapse.Speed.FAST), 3, "veloce resta 3")
	eq(int(TimeLapse.Speed.STOPPED), -1, "e Ferma vale -1")

	# l'ordine resta giusto, quindi i confronti esistenti funzionano
	true_(TimeLapse.Speed.STOPPED < TimeLapse.Speed.VERY_SLOW,
		"ferma e' piu' lenta di molto lenta")
	eq(TimeLapse.speed_label(TimeLapse.Speed.STOPPED), "ferma",
		"e ha il suo nome")
	eq(TimeLapse.speed_label(TimeLapse.Speed.MEDIUM), "media", "come le altre")

	var s := _ship("Bismarck", BattleState.Zone.FAR, Attitude.Kind.CLOSING)
	eq(AdvancedGunnery.target_speed_modifier(s), 0, "veloce: nessun modificatore")
	s.speed = TimeLapse.Speed.SLOW
	eq(AdvancedGunnery.target_speed_modifier(s), 1, "lenta: +1")
	s.speed = TimeLapse.Speed.VERY_SLOW
	eq(AdvancedGunnery.target_speed_modifier(s), 2, "molto lenta: +2")
	s.speed = TimeLapse.Speed.STOPPED
	eq(AdvancedGunnery.target_speed_modifier(s), 3, "ferma: +3")
	true_(s.is_slow_or_slower(),
		"e una nave ferma conta come lenta o peggio, senza toccare il confronto")


## Le regole avanzate si accendono, e da spente non cambiano niente.
func test_advanced_toggle() -> void:
	_begin("interruttore delle Regole Avanzate")
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	false_(st.advanced, "di default si gioca con le regole base")

	var firer := _ship("Bismarck", BattleState.Zone.NEAR, Attitude.Kind.ACQUIRING)
	var target := _ship("Hood", BattleState.Zone.NEAR, Attitude.Kind.CLOSING)

	# stesso tiro, due mondi diversi. 4+4 = 8, piu' il valore dei cannoni 3
	# (raggio Corto) = 11.
	var base := Gunnery.attack(firer, target, _forced([4, 4]), false, false, false)
	true_(base["ok"], "l'attacco base si risolve")
	false_(base.has("result"), "e non conosce i risultati speciali")

	var adv := Gunnery.attack(firer, target, _forced([4, 4]), false, false, true)
	true_(adv["ok"], "quello avanzato pure")
	eq(int(adv["sum"]), int(base["sum"]), "con la stessa somma")
	true_(adv.has("result"), "ma legge la tabella avanzata")
	eq(int(adv["result"]), AdvancedGunnery.Result.SEVERE,
		"11 in Acquisizione: Risultato Grave")
	true_(adv["special"], "che e' un risultato speciale")
	eq(int(adv["hits"]), 0,
		"e NON e' un Colpo: Grave vuol dire un altro tiro su un'altra tabella")

	# la stessa nave in Avvicinamento, stesso tiro, un risultato diverso
	firer.attitude = Attitude.Kind.CLOSING
	var adv2 := Gunnery.attack(firer, target, _forced([4, 4]), false, false, true)
	eq(int(adv2["result"]), AdvancedGunnery.Result.SEVERE,
		"11 vale Grave anche nell'altra colonna")
	firer.attitude = Attitude.Kind.ACQUIRING
	# ma con 9 la differenza si vede
	var a9 := Gunnery.attack(firer, target, _forced([3, 3]), false, false, true)
	eq(int(a9["sum"]), 9, "3+3+3 = 9")
	eq(int(a9["result"]), AdvancedGunnery.Result.SEVERE,
		"9 in Acquisizione: gia' Grave")
	firer.attitude = Attitude.Kind.CLOSING
	var c9 := Gunnery.attack(firer, target, _forced([3, 3]), false, false, true)
	eq(int(c9["result"]), AdvancedGunnery.Result.HIT,
		"9 in Avvicinamento: solo un Colpo")
	eq(int(c9["hits"]), 1, "e quello e' un Colpo vero")


func _forced(values: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(values)
	return r


## Siluri avanzati: solo in Avvicinamento, anche dalla zona Vicina, e senza
## la casella "Colpo" - o mancano o fanno un danno grave.
func test_advanced_torpedo() -> void:
	_begin("Siluri avanzati")
	var f := _ship("Galatea", BattleState.Zone.CLOSE, Attitude.Kind.CLOSING)
	var t := _ship("Hipper", BattleState.Zone.CLOSE, Attitude.Kind.CLOSING)

	true_(AdvancedTorpedo.can_attack(f), "in Avvicinamento e Ravvicinata: si'")
	f.battle_zone = BattleState.Zone.NEAR
	true_(AdvancedTorpedo.can_attack(f),
		"e anche dalla zona Vicina, che le regole base non permettono")
	f.battle_zone = BattleState.Zone.FAR
	false_(AdvancedTorpedo.can_attack(f), "ma non da Lontano")
	f.battle_zone = BattleState.Zone.CLOSE
	f.attitude = Attitude.Kind.RUNNING
	false_(AdvancedTorpedo.can_attack(f), "e nemmeno in Corsa")
	f.attitude = Attitude.Kind.ACQUIRING
	false_(AdvancedTorpedo.can_attack(f), "ne' in Acquisizione")
	f.attitude = Attitude.Kind.CLOSING

	# la tabella: niente casella "Colpo"
	eq(AdvancedTorpedo.read(8), AdvancedGunnery.Result.SPLASH, "8: Splash")
	eq(AdvancedTorpedo.read(9), AdvancedGunnery.Result.SEVERE, "9: Grave")
	eq(AdvancedTorpedo.read(11), AdvancedGunnery.Result.CATASTROPHIC, "11: Catastrofico")
	var has_hit := false
	for row_v: Variant in AdvancedTorpedo.TABLE:
		if int((row_v as Array)[1]) == AdvancedGunnery.Result.HIT:
			has_hit = true
	false_(has_hit, "un siluro o manca o fa un danno grave")

	# i modificatori
	eq(AdvancedTorpedo.modifier_total(f, t), 0, "bersaglio veloce, da Ravvicinata")
	t.attitude = Attitude.Kind.RUNNING
	eq(AdvancedTorpedo.modifier_total(f, t), -2, "bersaglio in Corsa: -2")
	t.speed = TimeLapse.Speed.STOPPED
	eq(AdvancedTorpedo.modifier_total(f, t), 1, "ma se e' fermo +3, quindi +1")
	f.battle_zone = BattleState.Zone.NEAR
	eq(AdvancedTorpedo.modifier_total(f, t), -1, "e attaccando da Vicina altri -2")

	# la Linea di Galleggiamento
	eq(AdvancedTorpedo.waterline_severe(2), "Timone Fuori Uso", "2-5")
	eq(AdvancedTorpedo.waterline_severe(6), "Allagamento (ferma)", "6-7")
	eq(AdvancedTorpedo.waterline_severe(8), "Allagamento (molto lenta)", "8-12")

	# un attacco intero
	f.battle_zone = BattleState.Zone.CLOSE
	t.attitude = Attitude.Kind.CLOSING
	t.speed = TimeLapse.Speed.FAST
	var a := AdvancedTorpedo.attack(f, t, _forced([5, 5, 4, 4]))
	true_(a["ok"], "l'attacco si risolve")
	eq(int(a["sum"]), 10, "2d6 = 10")
	eq(int(a["result"]), AdvancedGunnery.Result.SEVERE, "Risultato Grave")
	eq(String(a["effect"]), "Allagamento (molto lenta)",
		"e il secondo tiro da' l'effetto")
