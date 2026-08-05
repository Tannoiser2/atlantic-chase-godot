extends TestCase

## MS12 Finale (fascicolo a due giocatori p.51).
##
## E' l'unico mini-scenario che non e' una Battaglia: sono TRE Battaglie di due
## Round, e prima di ognuna il britannico tira per sapere con quale Forza
## combatte. L'app lo apriva come una Battaglia sola con tutte le navi insieme -
## si giocava, ma non era MS12, e il tiro delle Forze non si faceva mai.

var ms: Ms12


func name() -> String:
	return "MS12 Finale"


func run() -> void:
	ms = Ms12.load_default()
	test_data_loads()
	test_force_table()
	test_force_modifiers()
	test_who_may_stay_out()
	test_build_part()
	test_damage_is_carried_between_parts()


func test_data_loads() -> void:
	_begin("il dato di MS12 si carica")
	eq(ms.load_error, "", "nessun errore: %s" % ms.load_error)
	eq(ms.parts(), 3, "tre Parti")
	eq(ms.rounds_per_part(), 2, "due Round ciascuna")
	eq(ms.force_names(), ["A", "B", "C"] as Array[String], "tre Forze")
	# Le composizioni sono quelle stampate, non tre gruppi qualsiasi.
	eq(ms.force_ships("A"), ["Convoy x3", "DD Squadron"] as Array[String],
		"Forza A: Convoglio e Squadrone DD")
	eq(ms.force_ships("B"), ["Belfast", "Norfolk", "Sheffield"] as Array[String],
		"Forza B: i tre incrociatori")
	# 'Doy' e' il nome della Duke of York nel ruolino, dall'abbreviazione
	# stampata sulla pedina: e' lo stesso che usa lo schieramento di MS12.
	eq(ms.force_ships("C"), ["Fiji", "Doy"] as Array[String],
		"Forza C: Fiji e Duke of York")
	# La pagina stampa una sola freccia per la C, e due per A e B.
	eq(ms.force_attitude("C"), Attitude.Kind.CLOSING,
		"la Forza C entra in Closing, non a scelta")
	eq(ms.force_attitude("A"), -1, "la Forza A sceglie l'attitudine")
	eq(ms.force_attitude("B"), -1, "e anche la B")


## "2d6 -> 2-7 Force A, 8-10 Force B, 11+ Force C."
func test_force_table() -> void:
	_begin("la tabella delle Forze legge come stampata")
	eq(ms.force_for(2), "A", "un 2 da' la Forza A")
	eq(ms.force_for(7), "A", "e un 7 pure: la banda arriva fino a li'")
	eq(ms.force_for(8), "B", "un 8 passa alla B")
	eq(ms.force_for(10), "B", "fino a 10")
	eq(ms.force_for(11), "C", "un 11 arriva alla C")
	eq(ms.force_for(16), "C", "e da 11 in su non c'e' altro")


## "+2 if the Convoy has been the target of gunnery; +3 if the German BC is
## crippled." I due si sommano, e insieme raccontano l'arco dello scenario:
## piu' la caccia va avanti, piu' e' probabile che arrivi la Duke of York.
func test_force_modifiers() -> void:
	_begin("i modificatori del tiro portano avanti lo scenario")
	eq(ms.force_modifier(false, false), 0, "senza condizioni non c'e' modificatore")
	eq(ms.force_modifier(true, false), 2, "+2 col Convoglio gia' bersagliato")
	eq(ms.force_modifier(false, true), 3, "+3 con lo Scharnhorst azzoppato")
	eq(ms.force_modifier(true, true), 5, "e i due si sommano")

	# Un 6 secco darebbe la Forza A; con tutti e due i modificatori arriva alla C.
	var rng := DiceRNG.new(1)
	rng.push_forced([3, 3])
	var plain := ms.roll_force(rng, false, false)
	eq(String(plain["force"]), "A", "2d6=6 senza modificatori: Forza A")
	rng.push_forced([3, 3])
	var boosted := ms.roll_force(rng, true, true)
	eq(int(boosted["total"]), 11, "lo stesso tiro con +5 fa 11")
	eq(String(boosted["force"]), "C", "e la Forza diventa la C")
	true_(String(boosted["log"]).contains("+3"),
		"il registro dice da dove viene il modificatore")


## "Except for the DD Squadron and the Convoy, the British player may elect to
## keep a ship out of the game if it is crippled. All other ships must
## participate regardless of Hits and special effects incurred in a previous
## Part."
func test_who_may_stay_out() -> void:
	_begin("chi puo' restare fuori da una Parte, e chi no")
	var cruiser := ShipRoster.shared().make("Belfast")
	false_(ms.may_stay_out(cruiser), "una nave sana partecipa")
	true_(ms.stay_out_refusal(cruiser).contains("non e' azzoppata"),
		"e il rifiuto spiega che i Colpi non bastano")

	# Azzoppata: puo' restare fuori.
	SpecialEffects.apply(cruiser, SpecialEffects.FIRE_SLOW)
	true_(AdvancedGunnery.is_crippled(cruiser), "adesso e' azzoppata")
	true_(ms.may_stay_out(cruiser), "e puo' restare fuori")
	eq(ms.stay_out_refusal(cruiser), "", "senza rifiuto")

	# Il Convoglio e lo Squadrone DD non possono mai, nemmeno azzoppati.
	var convoy := ShipRoster.shared().make("Convoy x3")
	SpecialEffects.apply(convoy, SpecialEffects.FIRE_SLOW)
	false_(ms.may_stay_out(convoy), "il Convoglio partecipa sempre")
	true_(ms.stay_out_refusal(convoy).contains("sempre"),
		"e il motivo lo dice")
	var dd := ShipRoster.shared().make("DD Squadron")
	SpecialEffects.apply(dd, SpecialEffects.FIRE_SLOW)
	false_(ms.may_stay_out(dd), "e nemmeno lo Squadrone DD puo' tirarsi indietro")


func test_build_part() -> void:
	_begin("una Parte e' due Round, lo Scharnhorst contro la Forza tirata")
	var part := ms.build_part("C", TimeLapse.Weather.BAD)
	true_(bool(part["ok"]), "la Parte si costruisce: %s" % String(part["error"]))
	var bs: BattleState = part["state"]
	eq(bs.last_round, 2, "due Round, non cinque")
	true_(bs.advanced, "MS12 usa le Regole Avanzate")
	eq(bs.weather, TimeLapse.Weather.BAD, "col Meteo Cattivo stampato")
	eq(bs.target_tf.ships.size(), 1, "il tedesco ha una nave sola")
	eq(bs.target_tf.ships[0].name, "Scharnhorst", "ed e' lo Scharnhorst")
	eq(bs.active_tf.ships.size(), 2, "la Forza C ne ha due")
	for sh in bs.all_ships():
		eq(sh.battle_zone, BattleState.Zone.FAR,
			"%s si schiera nella zona Lontana" % sh.name)
	for sh in bs.active_tf.ships:
		eq(sh.attitude, Attitude.Kind.CLOSING,
			"%s entra in Closing, come stampato per la Forza C" % sh.name)

	# Una Forza che non esiste non produce una Battaglia vuota: si dichiara.
	var bad := ms.build_part("Z", TimeLapse.Weather.BAD)
	false_(bool(bad["ok"]), "una Forza sconosciuta viene rifiutata")
	true_(String(bad["error"]).contains("sconosciuta"), "col motivo")


## "All other ships must participate regardless of Hits and special effects
## incurred in a previous Part": la nave che torna e' la STESSA, col suo danno.
func test_damage_is_carried_between_parts() -> void:
	_begin("il danno di una Parte se lo porta dietro la nave, non si azzera")
	var first := ms.build_part("B", TimeLapse.Weather.BAD)
	true_(bool(first["ok"]), "la prima Parte si costruisce")
	var belfast: Ship = null
	for sh in (first["state"] as BattleState).active_tf.ships:
		if sh.name == "Belfast":
			belfast = sh
	ne(belfast, null, "la Belfast e' in campo")
	# Un CA non accumula Colpi: il primo lo gira sul lato Danneggiato. E' la
	# regola delle navi da guerra, e va bene lo stesso - quello che il test deve
	# provare e' che il danno RESTA fra una Parte e l'altra.
	belfast.apply_hits(1)
	true_(belfast.damaged, "e il Colpo la gira sul lato Danneggiato")

	var carried := {"Belfast": belfast}
	var second := ms.build_part("B", TimeLapse.Weather.BAD, carried)
	true_(bool(second["ok"]), "la seconda Parte si costruisce")
	var again: Ship = null
	for sh in (second["state"] as BattleState).active_tf.ships:
		if sh.name == "Belfast":
			again = sh
	eq(again, belfast, "e la Belfast e' la STESSA nave, non una copia nuova")
	true_(again.damaged, "col suo danno addosso")

	# La Belfast Danneggiata E' azzoppata (`is_crippled` = Danneggiata oppure con
	# un effetto speciale), quindi puo' restare fuori: e' proprio la regola
	# stampata.
	var allowed := ms.build_part("B", TimeLapse.Weather.BAD, carried, ["Belfast"])
	true_(bool(allowed["ok"]), "azzoppata, puo' restare fuori")
	eq((allowed["state"] as BattleState).active_tf.ships.size(), 2,
		"e in campo restano le altre due")

	# Una nave INTATTA invece no: "must participate regardless of Hits and
	# special effects incurred in a previous Part".
	var healthy: Ship = null
	for sh in (second["state"] as BattleState).active_tf.ships:
		if sh.name == "Norfolk":
			healthy = sh
	ne(healthy, null, "la Norfolk e' in campo")
	false_(healthy.damaged, "ed e' intatta")
	var refused := ms.build_part("B", TimeLapse.Weather.BAD,
		{"Norfolk": healthy}, ["Norfolk"])
	false_(bool(refused["ok"]), "una nave intatta non si tiene fuori")
	true_(String(refused["error"]).contains("azzoppata"), "col motivo stampato")
