extends TestCase

## Effetti Speciali (Regole Avanzate, pp.7-8).
##
## Sono quello che rende le regole avanzate diverse dal contare danni: una nave
## puo' restare a galla e integra sulla carta ed essere comunque fuori
## combattimento.

func name() -> String:
	return "Effetti Speciali"


func run() -> void:
	test_escalation()
	test_no_stacking()
	test_gunnery_penalties()
	test_speed_and_gunnery_block()
	test_rudder()
	test_communications()
	test_magazine()
	test_repair()
	test_wired_into_battle()


func _ship(n: String = "Bismarck") -> Ship:
	var s := Ship.new(n, TimeLapse.Speed.FAST)
	s.gun_close = 4
	s.gun_far = 2
	s.gun_close_damaged = 3
	s.gun_far_damaged = 1
	s.defense = 3
	s.defense_damaged = 2
	return s


## Un incendio che si ripete non fa "doppio incendio": aggrava.
func test_escalation() -> void:
	_begin("un effetto che si ripete aggrava, non si accumula")
	var s := _ship()

	var r1 := SpecialEffects.apply(s, SpecialEffects.FIRE_SLOW)
	true_(r1["applied"], "il primo incendio si applica")
	eq(s.special_effects.size(), 1, "un effetto")

	var r2 := SpecialEffects.apply(s, SpecialEffects.FIRE_STOPPED)
	true_(r2["applied"], "l'incendio grave si applica")
	eq(String(r2["removed"]), SpecialEffects.FIRE_SLOW, "e sostituisce quello lieve")
	eq(s.special_effects.size(), 1, "resta un effetto solo, non due")
	true_(SpecialEffects.has(s, SpecialEffects.FIRE_STOPPED), "ed e' il peggiore")

	# a questo punto un terzo incendio e' solo un Colpo
	var r3 := SpecialEffects.apply(s, SpecialEffects.FIRE_STOPPED)
	false_(r3["applied"], "il terzo non si applica")
	true_(r3["hit"], "vale un Colpo")
	eq(s.special_effects.size(), 1, "e l'elenco non cresce")

	# lo stesso per l'allagamento, che ha la stessa struttura
	var s2 := _ship()
	SpecialEffects.apply(s2, SpecialEffects.FLOOD_SLOW)
	var f := SpecialEffects.apply(s2, SpecialEffects.FLOOD_STOPPED)
	eq(String(f["removed"]), SpecialEffects.FLOOD_SLOW, "l'allagamento grave sostituisce il lieve")

	# e il LIEVE su chi ha gia' il GRAVE non peggiora niente: e' un Colpo
	var back := SpecialEffects.apply(s2, SpecialEffects.FLOOD_SLOW)
	false_(back["applied"], "il lieve non torna indietro")
	true_(back["hit"], "e vale un Colpo")
	true_(SpecialEffects.has(s2, SpecialEffects.FLOOD_STOPPED), "il grave resta")


func test_no_stacking() -> void:
	_begin("nessun effetto compare due volte")
	var s := _ship()
	for e in [SpecialEffects.BATTERIES, SpecialEffects.TURRETS, SpecialEffects.RUDDER, SpecialEffects.COMMUNICATIONS]:
		true_(SpecialEffects.apply(s, e)["applied"], "%s si applica" % e)
		var again := SpecialEffects.apply(s, e)
		false_(again["applied"], "%s non si applica due volte" % e)
		true_(again["hit"], "e la seconda volta e' un Colpo")
	eq(s.special_effects.size(), 4, "quattro effetti distinti")


## Torrette a qualunque raggio, Batterie solo da vicino, e insieme si sommano.
func test_gunnery_penalties() -> void:
	_begin("penalita' al Fuoco")
	var s := _ship()
	var extreme := Gunnery.FireRange.EXTREME
	var point_blank := Gunnery.FireRange.POINT_BLANK

	eq(SpecialEffects.gunnery_modifier(s, extreme), 0, "senza effetti, nessuna penalita'")

	SpecialEffects.apply(s, SpecialEffects.BATTERIES)
	eq(SpecialEffects.gunnery_modifier(s, extreme), 0,
		"le Batterie non toccano il raggio Estremo")
	eq(SpecialEffects.gunnery_modifier(s, point_blank), -2,
		"ma valgono -2 a Bruciapelo")

	SpecialEffects.apply(s, SpecialEffects.TURRETS)
	eq(SpecialEffects.gunnery_modifier(s, extreme), -2,
		"le Torrette valgono -2 a qualunque raggio")
	eq(SpecialEffects.gunnery_modifier(s, point_blank), -4,
		"e insieme alle Batterie fanno -4 da vicino, come dice il fascicolo")


func test_speed_and_gunnery_block() -> void:
	_begin("effetti che fermano o zittiscono la nave")
	var s := _ship()
	eq(SpecialEffects.speed_override(s), -99, "senza effetti la velocita' non cambia")
	true_(SpecialEffects.can_fire(s), "e la nave spara")

	SpecialEffects.apply(s, SpecialEffects.FLOOD_SLOW)
	eq(SpecialEffects.speed_override(s), TimeLapse.Speed.VERY_SLOW,
		"l'allagamento lieve rallenta a molto lenta")
	true_(SpecialEffects.can_fire(s), "ma la nave spara ancora")

	SpecialEffects.apply(s, SpecialEffects.FLOOD_STOPPED)
	eq(SpecialEffects.speed_override(s), TimeLapse.Speed.STOPPED,
		"quello grave la ferma")
	false_(SpecialEffects.can_fire(s), "e le impedisce di sparare")

	# ferma batte molto lenta anche se ci sono entrambi i tipi
	var s2 := _ship()
	SpecialEffects.apply(s2, SpecialEffects.FIRE_SLOW)
	SpecialEffects.apply(s2, SpecialEffects.FLOOD_STOPPED)
	eq(SpecialEffects.speed_override(s2), TimeLapse.Speed.STOPPED,
		"fra ferma e molto lenta vince la peggiore")


## Il Timone Fuori Uso non danneggia la nave: la toglie a chi la comanda.
func test_rudder() -> void:
	_begin("Timone Fuori Uso")
	var s := _ship()
	var rng := DiceRNG.new(1)

	var none := SpecialEffects.rudder_check(s, rng)
	false_(none["applies"], "senza l'effetto non si tira")

	SpecialEffects.apply(s, SpecialEffects.RUDDER)
	rng.push_forced([3])
	var odd := SpecialEffects.rudder_check(s, rng)
	true_(odd["applies"], "con l'effetto si tira")
	true_(odd["opponent_controls"], "dispari: la muove l'avversario")

	rng.push_forced([4])
	var even := SpecialEffects.rudder_check(s, rng)
	false_(even["opponent_controls"], "pari: resta al proprietario")

	# la nave non e' danneggiata: e' solo non piu' tua
	false_(s.damaged, "il Timone non danneggia la nave")
	true_(AdvancedGunnery.is_crippled(s),
		"ma la azzoppa, quindi le toglie la colonna Acquisizione")


func test_communications() -> void:
	_begin("Comunicazioni")
	var s := _ship()
	eq(SpecialEffects.attitude_step(s).size(), 0, "senza l'effetto non succede niente")

	SpecialEffects.apply(s, SpecialEffects.COMMUNICATIONS)
	var before := s.hits
	var lines := SpecialEffects.attitude_step(s)
	eq(lines.size(), 1, "a ogni fase dell'Attitudine c'e' un Colpo")
	true_(s.hits > before or s.damaged,
		"e il Colpo arriva davvero")


## La Santabarbara non e' un marcatore: e' un danno immediato.
func test_magazine() -> void:
	_begin("Santabarbara")
	var s := _ship()
	var r := SpecialEffects.apply(s, SpecialEffects.MAGAZINE)
	true_(r["applied"], "si applica")
	true_(s.damaged, "e la nave e' Danneggiata subito")
	eq(s.special_effects.size(), 0,
		"senza lasciare nessun marcatore: non e' un effetto duraturo")

	var r2 := SpecialEffects.apply(s, SpecialEffects.MAGAZINE)
	true_(r2["applied"], "una seconda volta si applica ancora")
	true_(s.sunk, "e affonda la nave gia' danneggiata")


func test_repair() -> void:
	_begin("che cosa si puo' riparare")
	var s := _ship()
	SpecialEffects.apply(s, SpecialEffects.BATTERIES)
	SpecialEffects.apply(s, SpecialEffects.TURRETS)

	true_(SpecialEffects.repairable(SpecialEffects.BATTERIES), "le Batterie si riparano")
	false_(SpecialEffects.repairable(SpecialEffects.TURRETS),
		"le Torrette no: sono l'unico effetto permanente")
	var targets := SpecialEffects.repair_targets(s)
	eq(targets.size(), 1, "quindi c'e' un bersaglio solo")
	eq(targets[0], SpecialEffects.BATTERIES, "ed e' quello riparabile")

	# la Plancia obbliga: il Controllo Danni deve puntare a lei e a nient'altro
	SpecialEffects.apply(s, SpecialEffects.BRIDGE)
	true_(SpecialEffects.bridge_choice_needed(s), "la Plancia chiede una scelta ogni Round")
	var forced := SpecialEffects.repair_targets(s)
	eq(forced.size(), 1, "e il Controllo Danni non puo' scegliere")
	eq(forced[0], SpecialEffects.BRIDGE, "deve puntare alla Plancia")


## La catena intera: un siluro avanzato che produce un effetto, e l'effetto che
## cambia davvero la nave.
func test_wired_into_battle() -> void:
	_begin("dal siluro all'effetto, passando per la Battaglia")
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.advanced = true

	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.name = "KM"
	var victim := _ship("Hipper")
	victim.battle_zone = BattleState.Zone.CLOSE
	victim.attitude = Attitude.Kind.CLOSING
	km.ships = [victim] as Array[Ship]

	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.name = "RN"
	var firer := _ship("Galatea")
	firer.has_torpedo = true
	firer.battle_zone = BattleState.Zone.CLOSE
	firer.attitude = Attitude.Kind.CLOSING
	rn.ships = [firer] as Array[Ship]

	st.active_tf = km
	st.target_tf = rn

	var rng := DiceRNG.new(1)
	# 5+5 = 10 sulla tavola dei Siluri: Risultato Grave.
	# Poi 4+4 = 8 sulla Linea di Galleggiamento: Allagamento (molto lenta).
	rng.push_forced([5, 5, 4, 4])
	var b := Battle.new(st, rng)
	b.torpedo_phase({firer: victim})

	true_(SpecialEffects.has(victim, SpecialEffects.FLOOD_SLOW),
		"l'effetto e' finito sulla nave")
	eq(victim.current_speed(), TimeLapse.Speed.VERY_SLOW,
		"e la nave e' davvero rallentata, non solo etichettata")
	false_(victim.damaged, "senza essere Danneggiata: e' un'altra cosa")
	true_(AdvancedGunnery.is_crippled(victim),
		"ma e' azzoppata, quindi perde la colonna Acquisizione")

	# la penalita' al Fuoco arriva fino al tiro
	SpecialEffects.apply(victim, SpecialEffects.TURRETS)
	var a := Gunnery.attack(victim, firer, DiceRNG.new(2), false, false, true)
	var found := false
	for m in a["modifiers"] as Array:
		if String(m["label"]) == "effetti speciali":
			found = true
			eq(int(m["value"]), -2, "le Torrette valgono -2")
	true_(found, "e il modificatore compare nel conto dell'attacco")

	# un incendio grave la zittisce del tutto
	SpecialEffects.apply(victim, SpecialEffects.FIRE_STOPPED)
	var a2 := Gunnery.attack(victim, firer, DiceRNG.new(3), false, false, true)
	false_(a2["ok"], "con l'incendio grave non spara piu'")
	eq(victim.current_speed(), TimeLapse.Speed.STOPPED, "ed e' ferma")
