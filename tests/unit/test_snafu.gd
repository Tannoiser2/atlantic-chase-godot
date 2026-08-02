extends TestCase

## Verifica Snafu e Battaglia Estesa (Regole Avanzate, carta di aiuto faccia A
## e fascicolo p.13).

func name() -> String:
	return "Snafu e Battaglia Estesa"


func run() -> void:
	test_good_column()
	test_bad_column()
	test_arctic()
	test_visibility()
	test_extended()
	test_round_sequence()
	test_stopped_cannot_change_attitude()
	test_pursuit()
	test_disengagement_on_finish()


func _rng(v: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(v)
	return r


func _ship(n: String, att: int = Attitude.Kind.CLOSING) -> Ship:
	var s := Ship.new(n, TimeLapse.Speed.FAST)
	s.gun_close = 3
	s.gun_far = 2
	s.defense = 3
	s.defense_damaged = 2
	s.attitude = att
	return s


func _battle(advanced: bool) -> BattleState:
	var st := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	st.advanced = advanced
	var a := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	a.name = "KM"
	a.ships = [_ship("Bismarck")] as Array[Ship]
	var b := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	b.name = "RN"
	b.ships = [_ship("Hood")] as Array[Ship]
	st.active_tf = a
	st.target_tf = b
	return st


func test_good_column() -> void:
	_begin("colonna Meteo Buono")
	var S := Snafu.Result
	eq(Snafu.read(false, 2), S.CONFUSION, "2-3: Confusione")
	eq(Snafu.read(false, 4), S.MECHANICAL, "4: Problemi Meccanici")
	eq(Snafu.read(false, 5), S.BOILER, "5: Sala Caldaie")
	eq(Snafu.read(false, 6), S.UNEXPECTED_BEARING, "6: Rotta Inaspettata")
	eq(Snafu.read(false, 7), S.GOOD_VISIBILITY, "7-12: Buona Visibilita'")
	eq(Snafu.read(false, 12), S.GOOD_VISIBILITY, "anche con 12")
	# la Buona Visibilita' e' il risultato piu' probabile, ed e' anche il piu'
	# sanguinoso: un Round in piu' per affondare qualcuno
	true_(Snafu.check(_rng([4, 5]), TimeLapse.Weather.GOOD)["extra_round"],
		"e allunga la Battaglia")


func test_bad_column() -> void:
	_begin("colonna Meteo Cattivo")
	var S := Snafu.Result
	eq(Snafu.read(true, 2), S.CONFUSION, "2-4: Confusione")
	eq(Snafu.read(true, 4), S.CONFUSION, "anche con 4")
	eq(Snafu.read(true, 5), S.NO_RADAR, "5-6: Niente Radar")
	eq(Snafu.read(true, 7), S.FOG, "7: Nebbia")
	eq(Snafu.read(true, 8), S.OPEN_ARC, "8: Arco Aperto")
	eq(Snafu.read(true, 9), S.POOR_VISIBILITY, "9-12: Scarsa Visibilita'")

	# col maltempo non si allunga mai: si spara peggio e basta
	var r := Snafu.check(_rng([5, 5]), TimeLapse.Weather.BAD)
	false_(r["extra_round"], "il maltempo non regala Round")
	true_(r["gunnery_penalty"], "penalizza il Fuoco")


## Sopra la Linea Artica si usa la colonna Cattivo anche col bel tempo.
func test_arctic() -> void:
	_begin("Linea Artica")
	var good := Snafu.check(_rng([4, 3]), TimeLapse.Weather.GOOD, false)
	false_(good["bad_column"], "col bel tempo si legge la colonna Buono")
	eq(int(good["result"]), Snafu.Result.GOOD_VISIBILITY, "7: Buona Visibilita'")

	var arctic := Snafu.check(_rng([4, 3]), TimeLapse.Weather.GOOD, true)
	true_(arctic["bad_column"], "ma in Artico si legge quella Cattivo")
	eq(int(arctic["result"]), Snafu.Result.FOG, "e lo stesso 7 da' Nebbia")


func test_visibility() -> void:
	_begin("Scarsa Visibilita'")
	eq(Snafu.visibility_modifier(false, Gunnery.FireRange.EXTREME), 0,
		"senza il risultato, nessuna penalita'")
	eq(Snafu.visibility_modifier(true, Gunnery.FireRange.EXTREME), -1, "Estremo")
	eq(Snafu.visibility_modifier(true, Gunnery.FireRange.LONG), -1, "Lungo")
	eq(Snafu.visibility_modifier(true, Gunnery.FireRange.SHORT), -1, "Corto")
	eq(Snafu.visibility_modifier(true, Gunnery.FireRange.POINT_BLANK), 0,
		"ma non a Bruciapelo: da li' non c'e' visibilita' che tenga")


## La Battaglia finisce quando qualcuno vuole andarsene.
func test_extended() -> void:
	_begin("Battaglia Estesa")
	eq(Snafu.extra_rounds(false, false), 0, "nessuna condizione")
	eq(Snafu.extra_rounds(true, false), 1, "solo Buona Visibilita'")
	eq(Snafu.extra_rounds(false, true), 1, "solo nessuno in Corsa")
	eq(Snafu.extra_rounds(true, true), 2, "e si sommano")

	var st := _battle(true)
	true_(Snafu.nobody_running(st), "tutti si avvicinano: nessuno scappa")
	st.target_ships()[0].attitude = Attitude.Kind.RUNNING
	false_(Snafu.nobody_running(st), "basta uno in Corsa")

	# la Battaglia si allunga UNA volta sola per questa condizione, se no due
	# flotte decise a restare combatterebbero all'infinito
	var st2 := _battle(true)
	var rng2 := DiceRNG.new(7)
	var b := Battle.new(st2, rng2)
	st2.last_round = 1
	st2.round_number = 1
	false_(b.end_round(), "nessuno in Corsa: si continua")
	true_(st2.extended, "la Battaglia risulta estesa")
	st2.round_number = st2.last_round
	true_(b.end_round(), "ma la seconda volta finisce")


## Le due fasi nuove entrano nella sequenza senza rinumerare quelle base.
func test_round_sequence() -> void:
	_begin("sequenza del Round")
	# la numerazione delle fasi base non deve cambiare: le partite salvate
	# hanno la fase come intero
	eq(int(BattleState.Phase.GUNNERY), 0, "Fuoco resta 0")
	eq(int(BattleState.Phase.TORPEDO), 1, "Siluri resta 1")
	eq(int(BattleState.Phase.MANEUVER), 2, "Manovra resta 2")
	eq(int(BattleState.Phase.BREAK_AWAY), 3, "Fuga resta 3")

	var basic := _battle(false)
	eq(basic.first_phase(), BattleState.Phase.GUNNERY,
		"con le regole base si comincia sparando")
	basic.phase = BattleState.Phase.MANEUVER
	eq(basic.next_phase(), BattleState.Phase.BREAK_AWAY,
		"e dopo la Manovra si va alla Fuga")

	var adv := _battle(true)
	eq(adv.first_phase(), BattleState.Phase.ATTITUDE,
		"in avanzato si comincia decidendo l'attitudine")
	adv.phase = BattleState.Phase.ATTITUDE
	eq(adv.next_phase(), BattleState.Phase.GUNNERY, "poi il Fuoco")
	adv.phase = BattleState.Phase.MANEUVER
	eq(adv.next_phase(), BattleState.Phase.LINGERING,
		"e dopo la Manovra ci sono gli Effetti Duraturi")
	adv.phase = BattleState.Phase.LINGERING
	eq(adv.next_phase(), BattleState.Phase.BREAK_AWAY, "poi la Fuga")
	adv.phase = BattleState.Phase.BREAK_AWAY
	eq(adv.next_phase(), BattleState.Phase.ENDED, "e il Round e' finito")


## Una nave ferma non puo' nemmeno cambiare idea.
func test_stopped_cannot_change_attitude() -> void:
	_begin("una nave ferma non cambia attitudine")
	var st := _battle(true)
	var s: Ship = st.active_ships()[0]
	SpecialEffects.apply(s, SpecialEffects.FLOOD_STOPPED)
	eq(s.current_speed(), TimeLapse.Speed.STOPPED, "la nave e' ferma")

	var rng3 := DiceRNG.new(3)
	var b := Battle.new(st, rng3)
	b.attitude_phase({s: Attitude.Kind.RUNNING})
	ne(s.attitude, Attitude.Kind.RUNNING,
		"e non puo' decidere di scappare: e' bloccata anche nelle intenzioni")


## Inseguimento: l'unico modo di muovere una nave avversaria.
func test_pursuit() -> void:
	_begin("Inseguimento")
	var p := _ship("Hood", Attitude.Kind.CLOSING)
	p.battle_zone = BattleState.Zone.NEAR
	var t := _ship("Bismarck", Attitude.Kind.RUNNING)
	t.battle_zone = BattleState.Zone.FAR
	t.speed = TimeLapse.Speed.SLOW

	eq(Attitude.pursuit_refusal(p, t), "", "una nave piu' veloce puo' tirarsela dietro")
	var r := Attitude.pursue(p, t)
	true_(r["ok"], "l'inseguimento riesce")
	eq(t.battle_zone, BattleState.Zone.NEAR, "e il bersaglio si avvicina")

	# oltre la Ravvicinata non si tira
	t.battle_zone = BattleState.Zone.CLOSE
	true_(Attitude.pursuit_refusal(p, t).contains("Ravvicinata"),
		"da Ravvicinata non si va oltre")

	# serve essere piu' veloci
	t.battle_zone = BattleState.Zone.FAR
	t.speed = TimeLapse.Speed.FAST
	true_(Attitude.pursuit_refusal(p, t).contains("non e' piu' veloce"),
		"con la stessa velocita' non si insegue")

	# ma contro una nave che ACQUISISCE basta pareggiare: chi punta non sta
	# badando a mantenere le distanze
	t.attitude = Attitude.Kind.ACQUIRING
	eq(Attitude.pursuit_refusal(p, t), "",
		"contro chi acquisisce basta essere altrettanto veloci")

	# e solo l'Avvicinamento insegue
	p.attitude = Attitude.Kind.RUNNING
	true_(Attitude.pursuit_refusal(p, t).contains("Avvicinamento"),
		"chi scappa non insegue")


## Il Disingaggio all'uscita: l'ultimo momento in cui una Battaglia uccide.
func test_disengagement_on_finish() -> void:
	_begin("Disingaggio all'uscita")
	var st := _battle(true)
	var s: Ship = st.active_ships()[0]
	SpecialEffects.apply(s, SpecialEffects.FIRE_STOPPED)

	var rngA := DiceRNG.new(11)
	var b := Battle.new(st, rngA)
	b.finish()
	true_(s.sunk,
		"una nave che esce con un incendio che la ferma non torna a casa: "
		+ "autoaffondamento su tutte e quattro le colonne")

	# senza effetti speciali non si tira niente
	var st2 := _battle(true)
	var s2: Ship = st2.active_ships()[0]
	var rngB := DiceRNG.new(11)
	Battle.new(st2, rngB).finish()
	false_(s2.sunk, "chi esce integro non rischia niente")

	# e con le regole base il Disingaggio non esiste
	var st3 := _battle(false)
	var s3: Ship = st3.active_ships()[0]
	s3.special_effects.append(SpecialEffects.FIRE_STOPPED)
	var rngC := DiceRNG.new(11)
	Battle.new(st3, rngC).finish()
	false_(s3.sunk, "con le regole base non si verifica il Disingaggio")
