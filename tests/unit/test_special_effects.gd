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
	test_bridge_choice()
	test_rudder_control_changes_hands()
	test_split_fire()
	test_split_fire_ui_distribution_is_always_legal()


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


## LA SCELTA DELLA PLANCIA (Regole Avanzate).
##
## Una nave che ha preso la Plancia deve scegliere, OGNI Round, fra non sparare
## e restare Ferma. E' una decisione del proprietario, e finora nessuno gliela
## chiedeva: la Plancia era un segnalino che non faceva niente.
func test_bridge_choice() -> void:
	_begin("la Plancia: o non spari, o non ti muovi")
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.advanced = true
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var hurt := _ship("Scharnhorst")
	hurt.battle_zone = BattleState.Zone.NEAR
	km.ships = [hurt] as Array[Ship]
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	var enemy := _ship("Hood")
	enemy.battle_zone = BattleState.Zone.NEAR
	rn.ships = [enemy] as Array[Ship]
	st.active_tf = km
	st.target_tf = rn
	var b := Battle.new(st, DiceRNG.new(3))

	eq(b.bridge_choices_pending().size(), 0,
		"senza Plancia non c'e' niente da scegliere")
	true_(b.set_bridge_choice(hurt, "no_fire").contains("non ha la Plancia"),
		"e la scelta viene rifiutata col motivo")

	SpecialEffects.apply(hurt, SpecialEffects.BRIDGE)
	eq(b.bridge_choices_pending().size(), 1,
		"con la Plancia la nave deve scegliere")
	true_(b.set_bridge_choice(hurt, "mezza").contains("'no_fire' e 'stopped'"),
		"e le scelte sono due, non una terza a piacere")

	# Restare Ferma: la nave e' Ferma DAVVERO, quindi bersaglio con +3.
	eq(b.set_bridge_choice(hurt, "stopped"), "", "la scelta si registra")
	eq(hurt.current_speed(), TimeLapse.Speed.STOPPED,
		"restare Ferma vuol dire essere Ferma, non solo dichiararlo")
	eq(b.bridge_choices_pending().size(), 0, "e non resta piu' niente da scegliere")

	# Fine del Round: la scelta vale un Round solo, se no la Plancia sarebbe un
	# affondamento lento.
	st.round_number = 1
	st.last_round = 5
	b.end_round()
	eq(hurt.current_speed(), TimeLapse.Speed.FAST,
		"nel Round dopo la nave torna alla sua velocita'")
	eq(b.bridge_choices_pending().size(), 1, "e deve scegliere di nuovo")

	# Rinunciare al Fuoco: la nave non spara, ma si muove.
	eq(b.set_bridge_choice(hurt, "no_fire"), "", "la seconda scelta si registra")
	eq(hurt.current_speed(), TimeLapse.Speed.FAST,
		"chi rinuncia al Fuoco non e' Ferma")
	var results := b.gunnery_phase({hurt: enemy, enemy: hurt})
	var fired_by_hurt := 0
	for r_v: Variant in results:
		if (r_v as Dictionary).get("firer") == hurt:
			fired_by_hurt += 1
	eq(fired_by_hurt, 0, "e infatti non spara")
	true_(results.size() > 0, "mentre il nemico spara normalmente")


## IL TIMONE FUORI USO (Regole Avanzate).
##
## A ogni Manovra e a ogni Attitudine si tira un dado: DISPARI e la nave la
## muove l'AVVERSARIO. `rudder_check()` c'era dal commit degli Effetti
## Speciali, e non la chiamava nessuno: la nave restava tua comunque.
func test_rudder_control_changes_hands() -> void:
	_begin("col Timone Fuori Uso la nave non e' piu' tua")
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.advanced = true
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var drifting := _ship("Bismarck")
	km.ships = [drifting] as Array[Ship]
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.ships = [_ship("Hood")] as Array[Ship]
	st.active_tf = km
	st.target_tf = rn
	var rng := DiceRNG.new(5)
	var b := Battle.new(st, rng)

	eq(b.controller_side(drifting), TaskForce.Side.KRIEGSMARINE,
		"senza Timone la nave la comanda la sua parte")

	SpecialEffects.apply(drifting, SpecialEffects.RUDDER)
	# DISPARI: la comanda l'avversario.
	rng.push_forced([3])
	b.roll_rudder_control("prova")
	eq(b.controller_side(drifting), TaskForce.Side.ROYAL_NAVY,
		"con un DISPARI la nave la muove l'avversario")

	# PARI: torna al proprietario. Il tiro si rifa' ogni fase, non e' uno stato
	# che dura.
	rng.push_forced([4])
	b.roll_rudder_control("prova")
	eq(b.controller_side(drifting), TaskForce.Side.KRIEGSMARINE,
		"con un PARI resta al proprietario")

	# E si tira una volta sola per fase: due chiamate nella stessa fase non
	# devono consumare due dadi, se no la nave cambierebbe padrone a ogni
	# disegno della vista.
	st.phase = BattleState.Phase.MANEUVER
	st.round_number = 1
	rng.push_forced([3])
	b.ensure_rudder_rolled()
	var after_first := b.controller_side(drifting)
	b.ensure_rudder_rolled()
	eq(b.controller_side(drifting), after_first,
		"chiamata due volte nella stessa fase, il tiro resta quello")


## LA DIVISIONE DEL FUOCO (Regole Avanzate, in cima alla Tabella del Fuoco).
##
## "If Acquiring AND Gunnery Value is 1 or more, may distribute G.V. to attack
## two targets (Splitting column)." La regola stava in `split_refusal()` e non
## la chiamava nessuno: il fuoco non si poteva dividere.
func test_split_fire() -> void:
	_begin("dividere il fuoco costa la colonna Acquisizione")
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.advanced = true
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var firer := _ship("Bismarck")
	firer.attitude = Attitude.Kind.ACQUIRING
	firer.battle_zone = BattleState.Zone.NEAR
	km.ships = [firer] as Array[Ship]
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	var a := _ship("Hood")
	var b2 := _ship("Repulse")
	a.battle_zone = BattleState.Zone.NEAR
	b2.battle_zone = BattleState.Zone.NEAR
	rn.ships = [a, b2] as Array[Ship]
	st.active_tf = km
	st.target_tf = rn
	var rng := DiceRNG.new(11)
	var b := Battle.new(st, rng)

	var band := Gunnery.band_for(Gunnery.range_between(firer.battle_zone,
		a.battle_zone))
	var gv := int(firer.gun_value(band))
	true_(gv >= 2, "la nave di prova ha cannoni da dividere (gv=%d)" % gv)

	# Le parti devono sommare al Valore dei Cannoni: non si inventa potenza.
	true_(b.set_split_fire(firer, [{"target": a, "gv": gv}, {"target": b2, "gv": 1}])
		.contains("sommare"), "due parti che sommano piu' del valore sono rifiutate")
	# E i due bersagli devono essere diversi.
	true_(b.set_split_fire(firer, [{"target": a, "gv": 1}, {"target": a, "gv": gv - 1}])
		.contains("DIVERSI"), "sparare due volte allo stesso bersaglio non e' dividere")
	# Solo in Acquisizione.
	firer.attitude = Attitude.Kind.CLOSING
	true_(b.set_split_fire(firer, [{"target": a, "gv": 1}, {"target": b2, "gv": gv - 1}])
		.contains("Acquisizione"), "chi non e' in Acquisizione non divide")

	firer.attitude = Attitude.Kind.ACQUIRING
	eq(b.set_split_fire(firer, [{"target": a, "gv": 1}, {"target": b2, "gv": gv - 1}]),
		"", "la divisione legale si registra")

	# Due attacchi, uno per bersaglio, e la colonna non e' piu' quella
	# dell'Acquisizione: e' il prezzo stampato della divisione.
	eq(AdvancedGunnery.column_for(firer, 2), AdvancedGunnery.COLUMN_CLOSING,
		"chi divide perde la colonna Acquisizione")
	var results := b.gunnery_phase({})
	eq(results.size(), 2, "escono due attacchi, uno per bersaglio")
	var hit_targets := {}
	for r_v: Variant in results:
		hit_targets[(r_v as Dictionary)["target"]] = true
	eq(hit_targets.size(), 2, "e i bersagli sono due diversi")

	# La divisione vale un Round solo.
	st.round_number = 1
	st.last_round = 5
	b.end_round()
	eq(st.split_fire.size(), 0, "nel Round dopo va dichiarata di nuovo")


## La divisione del fuoco dichiarata dalla vista passa dallo stesso controllo
## del motore: qui si verifica che le parti scelte a schermo - una al primo
## bersaglio, il resto al secondo - siano sempre una ripartizione legale.
func test_split_fire_ui_distribution_is_always_legal() -> void:
	_begin("ogni ripartizione offerta dalla vista e' legale")
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.advanced = true
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	var firer := _ship("Bismarck")
	firer.attitude = Attitude.Kind.ACQUIRING
	firer.battle_zone = BattleState.Zone.NEAR
	km.ships = [firer] as Array[Ship]
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	var a := _ship("Hood")
	var b2 := _ship("Repulse")
	a.battle_zone = BattleState.Zone.NEAR
	b2.battle_zone = BattleState.Zone.NEAR
	rn.ships = [a, b2] as Array[Ship]
	st.active_tf = km
	st.target_tf = rn
	var b := Battle.new(st, DiceRNG.new(21))

	var band := Gunnery.band_for(Gunnery.range_between(firer.battle_zone,
		a.battle_zone))
	var gv := int(firer.gun_value(band))
	# La vista cicla il primo pezzo da 1 a gv-1: ogni valore deve produrre una
	# dichiarazione accettata, se no il pulsante offrirebbe scelte illegali.
	for first in range(1, gv):
		st.split_fire.clear()
		eq(b.set_split_fire(firer, [{"target": a, "gv": first},
			{"target": b2, "gv": gv - first}]), "",
			"ripartizione %d/%d accettata" % [first, gv - first])
	# Il ciclo della vista va da 1 a gv-1, quindi non offre MAI zero cannoni a
	# un bersaglio. Il motore invece una parte da zero la accetta, e resta
	# cosi': il fascicolo dice "may distribute G.V. to attack two targets" e non
	# vieta da nessuna parte una parte nulla. Vietarla qui sarebbe una regola
	# inventata; a non offrirla basta l'interfaccia.
	eq(b.set_split_fire(firer, [{"target": a, "gv": 0}, {"target": b2, "gv": gv}]),
		"", "il motore non vieta una parte da zero: il fascicolo non lo dice")
