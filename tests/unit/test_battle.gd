extends TestCase

## Battaglia (RB pp.55-62): raggi, cannoni, siluri, manovra, fumo, fuga, uscita.

var graph: MapGraph


func name() -> String:
	return "Battaglia"


func run() -> void:
	graph = MapGraph.load_default()
	test_ranges()
	test_dice_selection()
	test_gunnery_table()
	test_gunnery_attack()
	test_gun_value_na()
	test_smoke()
	test_torpedo()
	test_damage_model()
	test_maneuver_order()
	test_maneuver_moves()
	test_break_away()
	test_deployment()
	test_full_round()
	test_battle_end()
	test_real_denmark_strait()


func _ship(n: String, spd: int, gc: Variant = 2, gf: Variant = 1,
		def: int = 3, defd: int = 2) -> Ship:
	var s := Ship.new(n, spd)
	s.gun_close = gc
	s.gun_far = gf
	s.defense = def
	s.defense_damaged = defd
	return s


func _battle(kind: int = BattleState.Kind.BATTLE,
		weather: int = TimeLapse.Weather.GOOD) -> BattleState:
	var st := BattleState.new(kind, weather)
	var a := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	a.name = "KM"
	a.ships = [_ship("Bismarck", TimeLapse.Speed.FAST)] as Array[Ship]
	var b := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	b.name = "RN"
	b.ships = [_ship("Hood", TimeLapse.Speed.FAST)] as Array[Ship]
	a.recompute_speed()
	b.recompute_speed()
	st.active_tf = a
	st.target_tf = b
	st.hex = Vector2i(15, -4)
	return st


func test_ranges() -> void:
	_begin("raggi fra zone (tabella sulla mappa)")
	var Z := BattleState.Zone
	eq(Gunnery.range_between(Z.FAR, Z.FAR), Gunnery.FireRange.EXTREME, "Lontana-Lontana")
	eq(Gunnery.range_between(Z.FAR, Z.NEAR), Gunnery.FireRange.LONG, "Lontana-Vicina")
	eq(Gunnery.range_between(Z.FAR, Z.CLOSE), Gunnery.FireRange.LONG, "Lontana-Ravvicinata")
	eq(Gunnery.range_between(Z.NEAR, Z.NEAR), Gunnery.FireRange.SHORT, "Vicina-Vicina")
	eq(Gunnery.range_between(Z.NEAR, Z.CLOSE), Gunnery.FireRange.POINT_BLANK, "Vicina-Ravvicinata")
	eq(Gunnery.range_between(Z.CLOSE, Z.CLOSE), Gunnery.FireRange.POINT_BLANK, "Ravv.-Ravv.")
	# l'ordine non conta
	eq(Gunnery.range_between(Z.NEAR, Z.FAR), Gunnery.range_between(Z.FAR, Z.NEAR),
		"il raggio e' simmetrico")
	# banda del valore dei cannoni
	eq(Gunnery.band_for(Gunnery.FireRange.POINT_BLANK), "close", "bruciapelo usa il GV vicino")
	eq(Gunnery.band_for(Gunnery.FireRange.SHORT), "close", "corto usa il GV vicino")
	eq(Gunnery.band_for(Gunnery.FireRange.LONG), "far", "lungo usa il GV lontano")
	eq(Gunnery.band_for(Gunnery.FireRange.EXTREME), "far", "estremo usa il GV lontano")


func test_dice_selection() -> void:
	_begin("numero di dadi e scelta")
	eq(Gunnery.dice_count(Gunnery.FireRange.EXTREME), 3, "estremo: 3 dadi")
	eq(Gunnery.dice_count(Gunnery.FireRange.POINT_BLANK), 3, "bruciapelo: 3 dadi")
	eq(Gunnery.dice_count(Gunnery.FireRange.LONG), 2, "lungo: 2 dadi")
	eq(Gunnery.dice_count(Gunnery.FireRange.SHORT), 2, "corto: 2 dadi")

	# estremo: si tengono i DUE MINORI
	var r1 := DiceRNG.new(0)
	r1.push_forced([6, 2, 4])
	var a := Gunnery.roll_for_range(Gunnery.FireRange.EXTREME, r1)
	eq(a["sum"], 6, "estremo con 6,2,4 tiene 2+4 = 6")
	# bruciapelo: si tengono i DUE MAGGIORI
	var r2 := DiceRNG.new(0)
	r2.push_forced([6, 2, 4])
	var b := Gunnery.roll_for_range(Gunnery.FireRange.POINT_BLANK, r2)
	eq(b["sum"], 10, "bruciapelo con 6,2,4 tiene 4+6 = 10")
	# lungo: entrambi
	var r3 := DiceRNG.new(0)
	r3.push_forced([5, 3])
	eq(Gunnery.roll_for_range(Gunnery.FireRange.LONG, r3)["sum"], 8, "lungo somma i due dadi")


func test_gunnery_table() -> void:
	_begin("tabella del Fuoco di Cannoni")
	eq(Gunnery.hits_for(2), 0, "2 = Splash")
	eq(Gunnery.hits_for(8), 0, "8 = Splash")
	eq(Gunnery.hits_for(9), 1, "9 = un Colpo")
	eq(Gunnery.hits_for(12), 1, "12 = un Colpo")
	eq(Gunnery.hits_for(13), 2, "13 = due Colpi")
	eq(Gunnery.hits_for(30), 2, "somme alte restano due Colpi")


func test_gunnery_attack() -> void:
	_begin("attacco con cannoni completo")
	var f := _ship("Attaccante", TimeLapse.Speed.FAST, 2, 1)
	var t := _ship("Bersaglio", TimeLapse.Speed.MEDIUM, 2, 1)
	f.battle_zone = BattleState.Zone.NEAR
	t.battle_zone = BattleState.Zone.NEAR      # corto, 2 dadi, GV close = 2
	var rng := DiceRNG.new(0)
	rng.push_forced([5, 4])
	var a := Gunnery.attack(f, t, rng)
	true_(a["ok"], "attacco valido")
	eq(a["range"], Gunnery.FireRange.SHORT, "raggio corto")
	eq(a["raw"], 9, "dadi 5+4")
	eq(a["modifier_total"], 2, "solo il valore dei cannoni (+2)")
	eq(a["sum"], 11, "somma modificata 11")
	eq(a["hits"], 1, "un Colpo")

	# bersaglio lento: +1 ; molto lento: +2
	var slow := _ship("Lenta", TimeLapse.Speed.SLOW)
	slow.battle_zone = BattleState.Zone.NEAR
	var rng2 := DiceRNG.new(0)
	rng2.push_forced([5, 4])
	var a2 := Gunnery.attack(f, slow, rng2)
	eq(a2["sum"], 12, "bersaglio lento aggiunge +1")
	var vslow := _ship("Molto lenta", TimeLapse.Speed.VERY_SLOW)
	vslow.battle_zone = BattleState.Zone.NEAR
	var rng3 := DiceRNG.new(0)
	rng3.push_forced([5, 4])
	var a3 := Gunnery.attack(f, vslow, rng3)
	eq(a3["sum"], 13, "bersaglio molto lento aggiunge +2")
	eq(a3["hits"], 2, "e diventa due Colpi")


func test_gun_value_na() -> void:
	_begin("valore dei cannoni 'na'")
	var f := _ship("Senza cannoni lunghi", TimeLapse.Speed.FAST, 2, null)
	var t := _ship("Bersaglio", TimeLapse.Speed.FAST)
	f.battle_zone = BattleState.Zone.FAR
	t.battle_zone = BattleState.Zone.FAR       # estremo -> banda 'far' = na
	true_(f.can_fire("close"), "puo' sparare a bruciapelo/corto")
	false_(f.can_fire("far"), "non puo' sparare a lungo/estremo")
	var a := Gunnery.attack(f, t, DiceRNG.new(0))
	false_(a["ok"], "attacco rifiutato")
	true_(String(a["reason"]).contains("na"), "il motivo cita 'na'")

	# RB p.56: si spara anche con GV zero o negativo
	var g := _ship("GV negativo", TimeLapse.Speed.FAST, -1, -1)
	g.battle_zone = BattleState.Zone.NEAR
	t.battle_zone = BattleState.Zone.NEAR
	var rng := DiceRNG.new(0)
	rng.push_forced([6, 6])
	var b := Gunnery.attack(g, t, rng)
	true_(b["ok"], "GV negativo puo' comunque sparare")
	eq(b["sum"], 11, "12 - 1 = 11")


func test_smoke() -> void:
	_begin("fumo")
	var st := _battle()
	var b := Battle.new(st, DiceRNG.new(0))
	b.start()
	var km: Ship = st.active_ships()[0]
	var rn: Ship = st.target_ships()[0]

	false_(Maneuver.is_obscured(st, rn), "nessun fumo all'inizio")
	rn.smoke = true
	true_(Maneuver.is_obscured(st, rn), "chi crea fumo e' oscurato")

	km.battle_zone = BattleState.Zone.NEAR
	rn.battle_zone = BattleState.Zone.NEAR
	var rng := DiceRNG.new(0)
	rng.push_forced([5, 4])
	var a := Gunnery.attack(km, rn, rng, true, false)
	eq(a["modifier_total"], 1, "GV +2 e fumo sul bersaglio -1")
	var rng2 := DiceRNG.new(0)
	rng2.push_forced([5, 4])
	var a2 := Gunnery.attack(km, rn, rng2, true, true)
	eq(a2["modifier_total"], 0, "entrambi oscurati: -2")

	# Convogli e navi danneggiate non possono creare fumo
	var convoy := Ship.new("Convoglio", TimeLapse.Speed.VERY_SLOW, Ship.Kind.CONVOY)
	false_(Maneuver.can_make_smoke(convoy), "un Convoglio non crea fumo")
	km.damaged = true
	false_(Maneuver.can_make_smoke(km), "una nave danneggiata non crea fumo")


func test_torpedo() -> void:
	_begin("siluri")
	var f := _ship("Silurante", TimeLapse.Speed.FAST)
	f.has_torpedo = true
	var t := _ship("Bersaglio", TimeLapse.Speed.MEDIUM)

	f.battle_zone = BattleState.Zone.NEAR
	t.battle_zone = BattleState.Zone.NEAR
	true_(Torpedo.legality_error(f, t).contains("Ravvicinata"),
		"si silura solo dalla zona Ravvicinata")

	f.battle_zone = BattleState.Zone.CLOSE
	t.battle_zone = BattleState.Zone.FAR
	true_(Torpedo.legality_error(f, t).contains("Lontana"),
		"la zona Lontana e' fuori portata")

	t.battle_zone = BattleState.Zone.NEAR
	eq(Torpedo.legality_error(f, t), "", "Ravvicinata -> Vicina e' legale")

	var rng := DiceRNG.new(0)
	rng.push_forced([5, 5])              # 10, sotto la soglia
	var a := Torpedo.attack(f, t, rng)
	eq(a["sum"], 10, "somma 10")
	eq(a["hits"], 0, "10 o meno: nessun effetto")

	var rng2 := DiceRNG.new(0)
	rng2.push_forced([6, 5])             # 11
	eq(Torpedo.attack(f, t, rng2)["hits"], 2, "11 o piu': due Colpi")

	# il bersaglio lento aiuta anche i siluri, il fumo no
	var slow := _ship("Lenta", TimeLapse.Speed.SLOW)
	slow.battle_zone = BattleState.Zone.CLOSE
	slow.smoke = true
	var rng3 := DiceRNG.new(0)
	rng3.push_forced([5, 5])
	var a3 := Torpedo.attack(f, slow, rng3)
	eq(a3["sum"], 11, "bersaglio lento +1, il fumo non conta")
	eq(a3["hits"], 2, "e va a segno")

	var nt := _ship("Senza siluri", TimeLapse.Speed.FAST)
	nt.battle_zone = BattleState.Zone.CLOSE
	false_(Torpedo.can_attack(nt), "una nave senza siluri non attacca")


func test_damage_model() -> void:
	_begin("Colpi, Difesa e affondamento (RB p.58)")
	var s := _ship("Prova", TimeLapse.Speed.FAST, 2, 1, 3, 2)
	s.apply_hits(2)
	eq(s.hits, 2, "due Colpi accumulati")
	false_(s.damaged, "non ancora danneggiata")
	s.apply_hits(1)
	true_(s.damaged, "raggiunta la Difesa: Danneggiata")
	eq(s.hits, 0, "i segnalini Colpo si rimuovono girando la pedina")
	s.apply_hits(2)
	true_(s.sunk, "raggiunta la Difesa del lato Danneggiato: affondata")

	# i Colpi eccedenti passano subito sul lato Danneggiato
	var s2 := _ship("Eccedenza", TimeLapse.Speed.FAST, 2, 1, 2, 3)
	s2.apply_hits(3)
	true_(s2.damaged, "danneggiata")
	eq(s2.hits, 1, "il Colpo eccedente e' gia' sul lato Danneggiato")

	# Difesa non trascritta: si accumula senza girare, e lo si dice
	var unknown := Ship.new("Senza statistiche", TimeLapse.Speed.FAST)
	var txt := unknown.apply_hits(5)
	eq(unknown.hits, 5, "i Colpi si accumulano")
	false_(unknown.damaged, "ma la pedina non si gira")
	true_(txt.contains("non trascritta"), "il log lo dichiara: " + txt)

	# Convogli: mai danneggiati, distrutti al limite di Colpi
	var convoy := Ship.new("Convoglio", TimeLapse.Speed.VERY_SLOW, Ship.Kind.CONVOY)
	convoy.apply_hits(3)
	false_(convoy.damaged, "un Convoglio non si danneggia mai")
	false_(convoy.sunk, "e a 3 Colpi non e' distrutto")
	convoy.apply_hits(1)
	true_(convoy.sunk, "al limite di 4 Colpi e' distrutto")


func test_maneuver_order() -> void:
	_begin("ordine di manovra: dalla piu' lenta, alternando")
	var st := _battle()
	st.active_tf.ships = [_ship("KM veloce", TimeLapse.Speed.FAST),
		_ship("KM lenta", TimeLapse.Speed.SLOW)] as Array[Ship]
	st.target_tf.ships = [_ship("RN lenta", TimeLapse.Speed.SLOW),
		_ship("RN media", TimeLapse.Speed.MEDIUM)] as Array[Ship]
	var order := Maneuver.move_order(st)
	eq(order.size(), 4, "tutte le navi muovono")
	eq(order[0].name, "RN lenta", "a parita' apre il giocatore Inattivo")
	eq(order[1].name, "KM lenta", "poi l'Attivo, stessa velocita'")
	eq(order[2].name, "RN media", "poi la velocita' successiva")
	eq(order[3].name, "KM veloce", "la piu' veloce per ultima")


func test_maneuver_moves() -> void:
	_begin("movimento fra zone")
	var Z := BattleState.Zone
	eq(Maneuver.adjacent_zones(Z.FAR), [Z.NEAR] as Array[int], "dalla Lontana solo Vicina")
	eq(Maneuver.adjacent_zones(Z.CLOSE), [Z.NEAR] as Array[int], "dalla Ravvicinata solo Vicina")
	eq(Maneuver.adjacent_zones(Z.NEAR).size(), 2, "dalla Vicina due opzioni")

	var s := _ship("Nave", TimeLapse.Speed.FAST)
	s.battle_zone = Z.FAR
	false_(Maneuver.can_move_to(s, Z.CLOSE), "non si saltano due zone")
	true_(Maneuver.can_move_to(s, Z.NEAR), "una zona alla volta")
	ne(Maneuver.apply(s, Z.NEAR, false), "", "mossa applicata")
	eq(s.battle_zone, Z.NEAR, "ora in zona Vicina")
	eq(Maneuver.apply(s, Z.FAR, true), "Nave da Vicina a Lontana, crea Fumo",
		"si puo' muovere e creare Fumo nello stesso turno")
	true_(s.smoke, "fumo attivo")


func test_break_away() -> void:
	_begin("Fuga")
	var st := _battle()
	var b := Battle.new(st, DiceRNG.new(0))
	b.start()
	var km: Ship = st.active_ships()[0]
	var rn: Ship = st.target_ships()[0]

	# entrambe in zona Lontana: +2 per chi tenta; nessuna nave nemica vicina
	var m := BreakAway.modifiers(st, st.active_tf)
	eq(m["total"], 2, "tutte le proprie navi in Lontana: +2")

	rn.battle_zone = BattleState.Zone.NEAR
	m = BreakAway.modifiers(st, st.active_tf)
	eq(m["total"], 1, "nemico in Vicina: -1, restano +1")

	rn.speed = TimeLapse.Speed.FAST
	km.speed = TimeLapse.Speed.MEDIUM
	st.active_tf.recompute_speed()
	m = BreakAway.modifiers(st, st.active_tf)
	eq(m["total"], 0, "nemico piu' veloce: un altro -1")

	# tiro: 9 o piu' riesce
	var rng := DiceRNG.new(0)
	rng.push_forced([5, 4])
	var a := BreakAway.attempt(st, st.active_tf, rng)
	eq(a["sum"], 9, "9 modificato")
	true_(a["success"], "riuscita con 9")

	var rng2 := DiceRNG.new(0)
	rng2.push_forced([4, 4])
	false_(BreakAway.attempt(st, st.active_tf, rng2)["success"], "8 fallisce")

	# entrambi dichiarano: finisce senza tiro
	var st2 := _battle()
	var b2 := Battle.new(st2, DiceRNG.new(0))
	b2.start()
	var res := b2.break_away_phase(true, true)
	true_(res["mutual"], "uscita concordata")
	true_(st2.ended, "Battaglia conclusa")

	# Fuga parziale con Manovre Evasive
	var st3 := _battle()
	var b3 := Battle.new(st3, DiceRNG.new(0))
	b3.start()
	st3.active_tf.ships.append(_ship("Seconda", TimeLapse.Speed.FAST))
	for s in st3.active_tf.ships:
		s.battle_zone = BattleState.Zone.FAR
	var ev := BreakAway.spend_evasive(st3, st3.active_tf)
	false_(ev["ok"], "senza segnalino non si puo'")
	st3.active_tf.evasive = true
	ev = BreakAway.spend_evasive(st3, st3.active_tf)
	true_(ev["ok"], "col segnalino una nave esce")
	eq(st3.active_ships().size(), 1, "una sola nave e' uscita")
	false_(st3.active_tf.evasive, "il segnalino e' stato speso")


func test_deployment() -> void:
	_begin("schieramento")
	var st := _battle()
	var b := Battle.new(st, DiceRNG.new(0))
	b.start()
	for s in st.all_ships():
		eq(s.battle_zone, BattleState.Zone.FAR, "Battaglia: tutti in zona Lontana")

	# Sorpresa con TF Attiva piu' veloce: il Bersaglio viene piazzato avanti
	var st2 := _battle(BattleState.Kind.SURPRISE)
	st2.active_tf.ships[0].speed = TimeLapse.Speed.FAST
	st2.target_tf.ships[0].speed = TimeLapse.Speed.SLOW
	st2.active_tf.recompute_speed()
	st2.target_tf.recompute_speed()
	var b2 := Battle.new(st2, DiceRNG.new(0))
	b2.start()
	true_(b2.surprise_first_strike, "l'Attivo ha il vantaggio")
	eq(st2.target_ships()[0].battle_zone, BattleState.Zone.NEAR,
		"le navi Bersaglio sono piazzate avanti")

	# Sorpresa senza vantaggio di velocita': vale come Battaglia normale
	var st3 := _battle(BattleState.Kind.SURPRISE)
	st3.active_tf.ships[0].speed = TimeLapse.Speed.SLOW
	st3.target_tf.ships[0].speed = TimeLapse.Speed.FAST
	st3.active_tf.recompute_speed()
	st3.target_tf.recompute_speed()
	var b3 := Battle.new(st3, DiceRNG.new(0))
	b3.start()
	false_(b3.surprise_first_strike, "nessun vantaggio")
	eq(st3.target_ships()[0].battle_zone, BattleState.Zone.FAR, "entrambi in Lontana")

	# durata
	eq(BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD).last_round, 3,
		"meteo buono: tre round")
	eq(BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.BAD).last_round, 2,
		"meteo avverso: due round")
	eq(BattleState.new(BattleState.Kind.LIMITED, TimeLapse.Weather.GOOD).last_round, 1,
		"Battaglia Limitata: un round")


func test_full_round() -> void:
	_begin("round completo")
	var st := _battle()
	var rng := DiceRNG.new(0)
	# due attacchi a raggio estremo (3 dadi ciascuno), poi la Fuga non tentata
	rng.push_forced([6, 6, 6, 6, 6, 6])
	var b := Battle.new(st, rng)
	b.start()
	eq(st.round_number, 1, "si parte dal Round Uno")

	var res := b.gunnery_phase(b.auto_targeting())
	eq(res.size(), 2, "entrambe le navi hanno sparato")
	for a in res:
		eq(a["range"], Gunnery.FireRange.EXTREME, "raggio estremo dalla zona Lontana")
	# 6+6 tenuti = 12, GV lontano = 1 -> 13 -> due Colpi
	for a in res:
		eq(a["sum"], 13, "somma 13")
		eq(a["hits"], 2, "due Colpi")
	for s in st.all_ships():
		eq(s.hits, 2, "entrambe hanno incassato due Colpi")

	b.maneuver_phase({st.active_ships()[0]: {"zone": BattleState.Zone.NEAR}})
	eq(st.active_ships()[0].battle_zone, BattleState.Zone.NEAR, "ha manovrato")

	var ba := b.break_away_phase(false, false)
	false_(ba["attempted"], "nessuno tenta la Fuga")
	false_(b.end_round(), "si passa al Round Due")
	eq(st.round_number, 2, "Round Due")


func test_battle_end() -> void:
	_begin("fine della Battaglia e uscita")
	# fine per Ultimo Round
	var st := BattleState.new(BattleState.Kind.LIMITED, TimeLapse.Weather.GOOD)
	var a := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	a.ships = [_ship("A", TimeLapse.Speed.FAST)] as Array[Ship]
	var t := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	t.ships = [_ship("B", TimeLapse.Speed.FAST)] as Array[Ship]
	st.active_tf = a
	st.target_tf = t
	st.hex = Vector2i(15, -4)
	var b := Battle.new(st, DiceRNG.new(0))
	b.start()
	true_(b.end_round(), "la Battaglia Limitata finisce dopo un round")
	true_(String(st.end_reason).contains("Ultimo Round"), "il motivo e' l'Ultimo Round")

	# fine perche' un lato resta senza navi
	var st2 := _battle()
	var b2 := Battle.new(st2, DiceRNG.new(0))
	b2.start()
	st2.target_tf.ships[0].sunk = true
	true_(st2.check_end(), "Battaglia conclusa")
	true_(String(st2.end_reason).contains("non ha piu' navi"), "motivo corretto")

	# uscita: le TF superstiti diventano Stazioni con Contatto nell'esagono
	var st3 := _battle()
	var b3 := Battle.new(st3, DiceRNG.new(0))
	b3.start()
	var out := b3.finish()
	eq((out["survivors"] as Array).size(), 2, "due superstiti")
	for tf in [st3.active_tf, st3.target_tf]:
		true_(tf.trajectory.is_station(), "%s e' una Stazione" % tf.display_name())
		eq(tf.trajectory.station_hex, st3.hex, "nell'esagono di Battaglia")
		true_(tf.trajectory.station_contact, "con segnalino Contatto")


## Battaglia completa con le navi vere di Rheinubung: e' il test che dimostra
## che i pezzi combaciano - ruolino, scenario, motore di battaglia.
func test_real_denmark_strait() -> void:
	_begin("Stretto di Danimarca: battaglia completa con navi reali")
	var sc := Scenario.load_by_id("Op5 Rheinubung")
	var gs := GameState.new(graph, 4242)
	gs.apply_dict(sc.to_state_dict())

	var km: TaskForce = null
	var rn: TaskForce = null
	for tf in gs.task_forces:
		if tf.color == "GE" and tf.slot == 0:
			km = tf
		elif tf.color == "Brown" and tf.slot == 0:
			rn = tf
	ne(km, null, "la TF tedesca c'e'")
	ne(rn, null, "la TF britannica c'e'")

	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.active_tf = km
	st.target_tf = rn
	st.hex = Vector2i(14, -5)
	var b := Battle.new(st, gs.rng)
	b.start()
	eq(st.last_round, 3, "tre round con meteo buono")
	for s in st.all_ships():
		eq(s.battle_zone, BattleState.Zone.FAR, "%s parte in zona Lontana" % s.name)

	# gioca la battaglia fino alla fine: nessun round infinito, nessun errore
	var guard := 0
	while not st.ended and guard < 20:
		guard += 1
		b.gunnery_phase(b.auto_targeting())
		if st.ended:
			break
		b.torpedo_phase(b.auto_torpedoes())
		if st.ended:
			break
		b.maneuver_phase({})
		b.break_away_phase(false, false)
		b.end_round()
	true_(st.ended, "la Battaglia termina")
	true_(guard <= st.last_round + 1, "in non piu' round dell'Ultimo Round")
	true_(st.log.size() > 5, "il registro racconta cosa e' successo (%d righe)"
		% st.log.size())

	# a raggio estremo con questi valori i colpi sono rari ma il sistema regge:
	# quello che conta e' che ogni nave abbia sparato con valori reali
	var fired := 0
	for line in st.log:
		if line.contains("raggio"):
			fired += 1
	true_(fired > 0, "ci sono stati attacchi con cannoni (%d)" % fired)

	var out := b.finish()
	eq((out["sunk"] as Array).size() + (out["survivors"] as Array).size(), 4,
		"quattro navi in tutto fra affondate e superstiti")
	for tf in [km, rn]:
		true_(tf.trajectory.is_station(), "%s esce come Stazione" % tf.display_name())
		eq(tf.trajectory.station_hex, Vector2i(14, -5), "nell'esagono di Battaglia")
		true_(tf.trajectory.station_contact, "con un segnalino Contatto")
