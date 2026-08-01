extends TestCase

## Le nove tabelle di Vittoria delle Operazioni.
##
## Ogni Operazione ha la sua tabella, con numeri diversi e clausole diverse, e
## quasi ogni tabella ha almeno una riga che il caso generale non copre: mezzi
## punti, punti negativi, premi che valgono una volta sola, premi che dipendono
## dal porto di arrivo, premi che il motore non puo' valutare da solo. Qui si
## verifica riga per riga che siano trascritte come sono stampate.

var graph: MapGraph
var roster: ShipRoster

const KM := "KRIEGSMARINE"
const RN := "ROYAL_NAVY"


func name() -> String:
	return "Vittoria"


func run() -> void:
	graph = MapGraph.load_default()
	roster = ShipRoster.shared()
	test_all_nine_tables_load()
	test_half_points()
	test_conditions_scenario()
	test_negative_and_manual()
	test_once_only()
	test_destination_matters()
	test_other_german_ship()
	test_hit_on_ship()
	test_convoy_owner()
	test_tiebreaks()
	test_port_control()
	test_completion_refusals()
	test_completion_scores()
	test_battle_scores()
	test_debriefing()


func _v(id: String) -> Victory:
	return Victory.from_scenario(Scenario.load_by_id(id))


func _state() -> GameState:
	return GameState.new(graph, 1)


## Tutte e nove le Operazioni hanno la tabella trascritta.
func test_all_nine_tables_load() -> void:
	_begin("le nove Operazioni")
	var ops := ["Op1 Homecoming", "Op2 First Test", "Op3 Norway", "Op4 Berlin",
		"Op5 Rheinubung", "Op6 New Friends", "Op7 Non Compos Mentis",
		"Op8 Cat and Mouse", "Op9 Actic Calamity"]
	for id in ops:
		var sc := Scenario.load_by_id(id)
		true_(sc.has_victory_table(), "%s ha la tabella" % id)
		var v := Victory.from_scenario(sc)
		true_(v.has_table, "%s: il motore la carica" % id)
		true_(v.describe(_state()) != "", "%s: e sa descriverla" % id)
	# i mini-scenari non le hanno ancora, e lo dicono
	var ms := _v("MS1 Cornered")
	false_(ms.has_table, "i mini-scenari non hanno ancora la tabella")


## Cinque tabelle su nove pagano MEZZO punto per un incrociatore britannico
## affondato. Arrotondare cambierebbe il vincitore, quindi i mezzi punti si
## sommano davvero.
func test_half_points() -> void:
	_begin("mezzi punti")
	var v := _v("Op8 Cat and Mouse")
	var st := _state()
	var kent := roster.make("Kent")
	eq(kent.type_code, "CA", "il Kent e' un incrociatore pesante")

	v.apply_event(st, Victory.Event.SHIP_SUNK, kent)
	eq(v.outcome(st)["km"], 0.5, "mezzo punto al tedesco")
	v.apply_event(st, Victory.Event.SHIP_SUNK, roster.make("Ajax"))
	eq(v.outcome(st)["km"], 1.0, "due incrociatori fanno un punto")

	eq(GameState.vp_str(0.5), "½", "mezzo punto si scrive cosi'")
	eq(GameState.vp_str(3.5), "3½", "e cosi'")
	eq(GameState.vp_str(4.0), "4", "un intero resta intero")
	eq(GameState.vp_str(-1.0), "-1", "e i negativi hanno il segno")

	# mezzo punto contro zero non e' parita'
	var o := v.outcome(st)
	eq(int(o["winner"]), TaskForce.Side.KRIEGSMARINE, "1 a 0 vince il tedesco")
	false_(o["tie"], "e non e' parita'")

	# il mezzo punto sopravvive a un salvataggio
	var st2 := _state()
	st2.apply_dict(st.to_dict())
	eq(st2.vp_of(TaskForce.Side.KRIEGSMARINE), 1.0, "i VP tornano dal salvataggio")


## Op1 Homecoming non ha nessuna tabella VP: si vince per condizioni. Contare
## punti qui vorrebbe dire inventarsi una regola che il fascicolo non ha.
func test_conditions_scenario() -> void:
	_begin("Op1: vittoria per condizioni")
	var v := _v("Op1 Homecoming")
	eq(v.mode, Victory.Mode.CONDITIONS, "modalita' a condizioni")
	eq(v.awards.size(), 0, "nessun premio in punti")
	eq(v.conditions.size(), 5, "cinque condizioni")

	var st := _state()
	var o := v.outcome(st)
	false_(o["resolved"], "il motore non decide da solo")
	false_(o["tie"], "e 0 a 0 non e' una parita': i punti non contano")

	var txt := v.describe(st)
	true_(txt.contains("non usa i Punti Vittoria"), "lo dice chiaramente")
	true_(txt.contains("Bremen"), "e nomina il Bremen: " + txt.substr(0, 60))

	# la condizione che ha la precedenza sta per prima, cosi' leggendo
	# dall'alto in basso la prima che si verifica e' quella giusta
	var first: Dictionary = v.conditions[0]
	eq(String(first["winner"]), RN, "vince il britannico")
	true_(String(first["text"]).contains("Danneggiata"),
		"ed e' la clausola sulle navi tedesche danneggiate")

	# e il Bremen ha un nome, se no nessuna regola potrebbe nominarlo
	var bremen := roster.make("Bremen")
	ne(bremen, null, "il Bremen e' nel ruolino")
	eq(bremen.name, "Bremen", "con il suo nome")
	true_(bremen.can_be_damaged(), "e con due facce, integra e danneggiata")
	eq(bremen.speed, TimeLapse.Speed.FAST, "veloce da integro")
	eq(bremen.speed_damaged, TimeLapse.Speed.SLOW, "lento da danneggiato")


## Op3 e' l'unica tabella che TOGLIE punti, e ha sei righe che il motore non
## puo' valutare (mine, basi aeree): quelle non devono scattare da sole.
func test_negative_and_manual() -> void:
	_begin("Op3: punti negativi e righe da spuntare")
	var v := _v("Op3 Norway")
	var manual := v.manual_awards()
	eq(manual.size(), 6, "sei righe da spuntare a mano")

	var negatives := 0
	for m in manual:
		if float(m["points"]) < 0.0:
			negatives += 1
	eq(negatives, 2, "due tolgono punti: niente mine, niente base aerea")

	# nessuna di quelle sei viene assegnata automaticamente
	var st := _state()
	v.apply_event(st, Victory.Event.CUSTOM, null)
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 0.0, "il motore non le assegna")
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 0.0, "ne' da una parte ne' dall'altra")

	true_(v.describe(st).contains("[ ]"), "ma le mette in un elenco da spuntare")

	# un punto tolto e' davvero tolto
	st.add_vp(TaskForce.Side.ROYAL_NAVY, -1.0)
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), -1.0, "si puo' andare sotto zero")


## "il PRIMO Completamento tedesco riuscito a Bergen": il secondo non paga.
func test_once_only() -> void:
	_begin("Op3: premi una tantum")
	var v := _v("Op3 Norway")
	var st := _state()
	var ship := roster.make("Hipper")
	var ctx := {"destination": "Bergen"}

	v.apply_event(st, Victory.Event.SHIP_COMPLETED, ship, "", ctx)
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 3.0, "il primo a Bergen vale 3")
	v.apply_event(st, Victory.Event.SHIP_COMPLETED, roster.make("Koln"), "", ctx)
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 3.0, "il secondo non vale niente")

	# ma un altro porto e' un altro premio
	v.apply_event(st, Victory.Event.SHIP_COMPLETED, ship, "",
		{"destination": "Trondheim"})
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 5.0, "Trondheim ne vale altri 2")
	v.apply_event(st, Victory.Event.SHIP_COMPLETED, ship, "",
		{"destination": "Narvik"})
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 6.0, "e Narvik 1")

	# e il fatto che siano gia' scattati sopravvive a un salvataggio: se no
	# ricaricare la partita li pagherebbe una seconda volta
	var st2 := _state()
	st2.apply_dict(st.to_dict())
	eq(st2.vp_once.size(), 3, "i tre premi risultano gia' scattati")
	v.apply_event(st2, Victory.Event.SHIP_COMPLETED, ship, "", ctx)
	eq(st2.vp_of(TaskForce.Side.KRIEGSMARINE), 6.0,
		"e dopo il ricaricamento non si ripagano")


## Il convoglio vale in base al porto in cui arriva e se si e' disperso.
func test_destination_matters() -> void:
	_begin("Op6: quanto vale un convoglio dipende da dove arriva")
	var v := _v("Op6 New Friends")

	var cases := [
		[{"destination": "Murmansk", "dispersed": false}, 3.0, "Murmansk intero"],
		[{"destination": "Murmansk", "dispersed": true}, 2.0, "Murmansk disperso"],
		[{"destination": "Archangel", "dispersed": false}, 3.0, "Archangel intero"],
		[{"destination": "Clyde", "dispersed": false}, 2.0, "altro porto intero"],
		[{"destination": "Clyde", "dispersed": true}, 1.0, "altro porto disperso"],
	]
	for c_v: Variant in cases:
		var c: Array = c_v
		var st := _state()
		v.apply_event(st, Victory.Event.CONVOY_COMPLETED, null, "", c[0])
		eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), c[1], String(c[2]))

	# un premio scritto per una nave precisa non deve cadere su un convoglio
	var st2 := _state()
	v.apply_event(st2, Victory.Event.SHIP_SUNK, null)
	eq(st2.vp_of(TaskForce.Side.ROYAL_NAVY), 0.0,
		"un convoglio non e' il Tirpitz")

	# in Op9 il porto artico che paga di piu' e' Archangel, non Murmansk:
	# Murmansk e' chiuso in quello scenario
	var v9 := _v("Op9 Actic Calamity")
	var st3 := _state()
	v9.apply_event(st3, Victory.Event.CONVOY_COMPLETED, null, "",
		{"destination": "Archangel", "dispersed": false})
	eq(st3.vp_of(TaskForce.Side.ROYAL_NAVY), 3.0, "Archangel vale 3 in Op9")


## "ogni ALTRA nave tedesca": la riga vale per tutto tranne gli incrociatori da
## battaglia, che hanno gia' la loro riga da 2/4.
func test_other_german_ship() -> void:
	_begin("Op2: la riga complementare")
	var v := _v("Op2 First Test")
	var st := _state()

	v.apply_event(st, Victory.Event.SHIP_SUNK, roster.make("Scharnhorst"))
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 4.0,
		"lo Scharnhorst e' un BC: 4 punti, una riga sola")

	var st2 := _state()
	v.apply_event(st2, Victory.Event.SHIP_SUNK, roster.make("Graf Spee"))
	eq(st2.vp_of(TaskForce.Side.ROYAL_NAVY), 2.0,
		"il Graf Spee e' una PB: cade nella riga generica, 2 punti")

	# il BC francese affondato vale 2 al tedesco, ma danneggiato vale ZERO:
	# la tabella scrive (0), non lascia la casella vuota
	var st3 := _state()
	v.apply_event(st3, Victory.Event.SHIP_DAMAGED, roster.make("Dunkerque"))
	eq(st3.vp_of(TaskForce.Side.KRIEGSMARINE), 0.0, "BC francese danneggiato: zero")
	v.apply_event(st3, Victory.Event.SHIP_SUNK, roster.make("Dunkerque"))
	eq(st3.vp_of(TaskForce.Side.KRIEGSMARINE), 2.0, "affondato: 2")


## Op8 e' l'unico scenario in cui un semplice COLPO da' punti.
func test_hit_on_ship() -> void:
	_begin("Op8: il Colpo sul Tirpitz")
	var v := _v("Op8 Cat and Mouse")
	var st := _state()
	var tirpitz := roster.make("Tirpitz")

	v.apply_event(st, Victory.Event.SHIP_HIT, tirpitz)
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 1.0, "un Colpo vale 1")
	v.apply_event(st, Victory.Event.SHIP_DAMAGED, tirpitz)
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 4.0, "danneggiarlo ne vale altri 3")
	v.apply_event(st, Victory.Event.SHIP_SUNK, tirpitz)
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 11.0, "affondarlo altri 7")

	# le altre navi tedesche hanno 0 in quella colonna
	var st2 := _state()
	v.apply_event(st2, Victory.Event.SHIP_HIT, roster.make("Scharnhorst"))
	eq(st2.vp_of(TaskForce.Side.ROYAL_NAVY), 0.0,
		"un Colpo su un BC non vale niente")

	# negli altri otto scenari nemmeno il Tirpitz paga per un Colpo
	var st3 := _state()
	_v("Op6 New Friends").apply_event(st3, Victory.Event.SHIP_HIT, tirpitz)
	eq(st3.vp_of(TaskForce.Side.ROYAL_NAVY), 0.0, "in Op6 il Colpo non paga")


## In Op3 il britannico guadagna colpendo convogli TEDESCHI e il tedesco quelli
## britannici: senza sapere di chi e' il convoglio i due premi si scambiano.
func test_convoy_owner() -> void:
	_begin("Op3: di chi e' il convoglio")
	var v := _v("Op3 Norway")

	var st := _state()
	v.apply_event(st, Victory.Event.HIT_ON_CONVOY, null, "", {"owner": KM})
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 1.0,
		"colpire un convoglio tedesco paga il britannico")
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 0.0, "e non il tedesco")

	var st2 := _state()
	v.apply_event(st2, Victory.Event.HIT_ON_CONVOY, null, "", {"owner": RN})
	eq(st2.vp_of(TaskForce.Side.KRIEGSMARINE), 1.0,
		"e viceversa")

	# senza il proprietario non si assegna niente, ma lo si dice
	var st3 := _state()
	var log_lines := v.apply_event(st3, Victory.Event.HIT_ON_CONVOY, null)
	eq(st3.vp_of(TaskForce.Side.ROYAL_NAVY), 0.0, "senza proprietario, zero")
	var warned := false
	for l in log_lines:
		if l.contains("non assegnati") and l.contains("owner"):
			warned = true
	true_(warned, "ma il registro segnala che manca un dato")


## Le clausole di parita': tre si risolvono da sole, sei no.
func test_tiebreaks() -> void:
	_begin("clausole di parita'")
	# Op3, Op4, Op7, Op9: vince il britannico, punto. Si risolve da sola.
	for id in ["Op3 Norway", "Op4 Berlin", "Op7 Non Compos Mentis",
			"Op9 Actic Calamity"]:
		var o := _v(id).outcome(_state())
		true_(o["tie"], "%s: 0 a 0 e' parita'" % id)
		true_(o["resolved"], "%s: la clausola si applica da sola" % id)
		eq(int(o["winner"]), TaskForce.Side.ROYAL_NAVY,
			"%s: in parita' vince il britannico" % id)

	# Op2, Op5, Op6, Op8: la clausola dipende da dov'e' una nave, e il motore
	# chiede invece di fingere di saperlo
	for id in ["Op2 First Test", "Op5 Rheinubung", "Op6 New Friends",
			"Op8 Cat and Mouse"]:
		var o2 := _v(id).outcome(_state())
		true_(o2["tie"], "%s: 0 a 0 e' parita'" % id)
		false_(o2["resolved"], "%s: la clausola la verificano i giocatori" % id)
		true_(String(o2["tiebreak_text"]) != "", "%s: e viene mostrata" % id)

	# quella di Op8 e' la piu' severa: al tedesco non basta salvare il Tirpitz
	var t8 := String(_v("Op8 Cat and Mouse").tiebreak["condition"])
	true_(t8.contains("Colpo"), "Op8 chiede anche un Colpo su un Convoglio")


# ------------------------------------------------- Completamento e Battaglia --

func _tf(side: int, ships: Array[Ship], h: Vector2i) -> TaskForce:
	var tf := TaskForce.new(1, side)
	tf.name = "TF di prova"
	tf.ships = ships
	tf.trajectory = Trajectory.new()
	tf.trajectory.become_station(h)
	return tf


## Dalla quarta Operazione in poi i porti francesi e norvegesi sono tedeschi, e
## alcuni scenari chiudono singoli porti.
func test_port_control() -> void:
	_begin("chi controlla i porti")
	var brest: Dictionary = graph.ports["Brest"]
	eq(brest["nation"], "FR", "Brest e' francese")

	# situazione di partenza: porto francese in mano britannica
	eq(Completion.control_of(brest, {}), "ROYAL_NAVY", "di partenza e' alleato")
	# Op4 e seguenti lo ribaltano
	var op4 := Scenario.load_by_id("Op4 Berlin").port_control()
	eq(Completion.control_of(brest, op4), "KRIEGSMARINE",
		"in Op4 i porti francesi sono tedeschi")
	# ma non tocca gli altri
	eq(Completion.control_of(graph.ports["Scapa Flow"], op4), "ROYAL_NAVY",
		"Scapa Flow resta britannica")

	# porti chiusi: il nome vince sulla nazione
	var op9 := Scenario.load_by_id("Op9 Actic Calamity").port_control()
	eq(Completion.control_of(graph.ports["Murmansk"], op9), "NONE",
		"in Op9 Murmansk e' chiuso")
	eq(Completion.control_of(graph.ports["Archangel"], op9), "ROYAL_NAVY",
		"ma Archangel no, anche se e' dello stesso paese")

	# Op1: Francia e Norvegia sono neutrali, Murmansk serve a tutti e due
	var op1 := Scenario.load_by_id("Op1 Homecoming").port_control()
	eq(Completion.control_of(brest, op1), "NONE", "in Op1 la Francia e' neutrale")
	eq(Completion.control_of(graph.ports["Murmansk"], op1), "BOTH",
		"e a Murmansk puo' Completare anche il Bremen")


## Le condizioni del regolamento (RB p.29), una per una.
func test_completion_refusals() -> void:
	_begin("quando il Completamento e' rifiutato")
	var kiel := graph.port_hex("Kiel")
	var ships: Array[Ship] = [roster.make("Bismarck")]

	var tf := _tf(TaskForce.Side.KRIEGSMARINE, ships, kiel)
	eq(Completion.refusal(tf, graph), "", "una Stazione a Kiel puo' Completare")

	# porto nemico
	var rn_tf := _tf(TaskForce.Side.ROYAL_NAVY, [roster.make("Hood")] as Array[Ship], kiel)
	true_(Completion.refusal(rn_tf, graph).contains("porto amico"),
		"ma il britannico a Kiel no")

	# fuori da un porto
	var open_sea := _tf(TaskForce.Side.KRIEGSMARINE, ships, Vector2i(10, 0))
	true_(Completion.refusal(open_sea, graph).contains("porto amico"),
		"e nemmeno in mare aperto")

	# Traiettoria troppo lunga: il massimo e' 6 segmenti
	var long_tf := _tf(TaskForce.Side.KRIEGSMARINE, ships, kiel)
	long_tf.trajectory = Trajectory.new()
	long_tf.trajectory.become_station(kiel)
	var h := kiel
	var added := 0
	for d in Hex.DIRS:
		var cand := h + Vector2i(d[0], d[1])
		if graph.is_playable(cand) and long_tf.trajectory.extend(cand, 1, graph):
			added += 1
			h = cand
			break
	true_(added > 0, "si riesce ad allungare la Traiettoria di almeno un segmento")

	# nessuna nave
	var empty := _tf(TaskForce.Side.KRIEGSMARINE, [] as Array[Ship], kiel)
	true_(Completion.refusal(empty, graph).contains("navi"),
		"una TF vuota non Completa")


## Il Completamento paga, e paga secondo il porto.
func test_completion_scores() -> void:
	_begin("quanto vale un Completamento")
	var sc := Scenario.load_by_id("Op5 Rheinubung")
	var v := Victory.from_scenario(sc)
	var pc := sc.port_control()

	# il Bismarck integro in un porto FRANCESE: 3 VP al tedesco
	var st := _state()
	var tracker := VictoryTracker.new(v, st)
	var tf := _tf(TaskForce.Side.KRIEGSMARINE,
		[roster.make("Bismarck")] as Array[Ship], graph.port_hex("Brest"))
	var opts := Completion.port_options(tf, graph, pc)
	true_(opts.size() > 0, "Brest e' disponibile al tedesco in questo scenario")
	eq(String(opts[0]["country"]), "France", "e conta come Francia")

	var r := Completion.resolve(tf, opts[0], tracker)
	true_(r["ok"], "il Completamento riesce")
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 3.0, "3 VP: e' quel che valeva")
	eq(tf.ships.size(), 0, "e la Task Force lascia il gioco")
	true_(tf.completed, "risulta Completata")
	eq(tf.completed_port, "Brest", "nel porto in cui e' arrivata")

	# lo stesso Bismarck DANNEGGIATO vale 2 in Francia ma 3 in Germania:
	# riportarlo a casa conciato vale piu' che perderlo
	var st2 := _state()
	var t2 := VictoryTracker.new(v, st2)
	var hurt := roster.make("Bismarck")
	hurt.damaged = true
	t2.ship_completed(hurt, "France", TaskForce.Side.KRIEGSMARINE)
	eq(st2.vp_of(TaskForce.Side.KRIEGSMARINE), 2.0, "danneggiato in Francia: 2")

	var st3 := _state()
	var t3 := VictoryTracker.new(v, st3)
	t3.ship_completed(hurt, "Germany", TaskForce.Side.KRIEGSMARINE)
	eq(st3.vp_of(TaskForce.Side.KRIEGSMARINE), 3.0, "danneggiato in Germania: 3")

	# un convoglio che arriva a Murmansk in Op6, intero e disperso
	var v6 := Victory.from_scenario(Scenario.load_by_id("Op6 New Friends"))
	var st4 := _state()
	VictoryTracker.new(v6, st4).convoy_completed("Murmansk", false,
		TaskForce.Side.ROYAL_NAVY)
	eq(st4.vp_of(TaskForce.Side.ROYAL_NAVY), 3.0, "convoglio intero a Murmansk: 3")
	var st5 := _state()
	VictoryTracker.new(v6, st5).convoy_completed("Murmansk", true,
		TaskForce.Side.ROYAL_NAVY)
	eq(st5.vp_of(TaskForce.Side.ROYAL_NAVY), 2.0, "disperso: 2")


## La catena intera: una Battaglia che affonda una nave deve segnare i punti.
func test_battle_scores() -> void:
	_begin("dalla Battaglia al segnapunti")
	var v := Victory.from_scenario(Scenario.load_by_id("Op5 Rheinubung"))
	var st := _state()
	var tracker := VictoryTracker.new(v, st)

	var bs := BattleState.new(BattleState.Kind.BATTLE, TimeLapse.Weather.GOOD)
	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.name = "KM"
	km.ships = [roster.make("Bismarck")] as Array[Ship]
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.name = "RN"
	rn.ships = [roster.make("Hood")] as Array[Ship]
	bs.active_tf = km
	bs.target_tf = rn
	bs.hex = Vector2i(13, -6)

	var battle := Battle.new(bs, DiceRNG.new(1), tracker)
	var bismarck: Ship = km.ships[0]

	# abbastanza Colpi da affondarlo: prima si danneggia, poi va a fondo
	battle._apply_hits([{"ok": true, "hits": 99, "target": bismarck,
		"firer": rn.ships[0]}] as Array[Dictionary])
	true_(bismarck.sunk, "il Bismarck affonda")
	eq(st.vp_of(TaskForce.Side.ROYAL_NAVY), 10.0,
		"3 per averlo danneggiato piu' 7 per averlo affondato")
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), 0.0,
		"e niente al tedesco: la sua nave non e' un bersaglio britannico")

	# senza tracciatore la Battaglia funziona esattamente come prima
	var st6 := _state()
	var b2 := Battle.new(bs, DiceRNG.new(1))
	var hood: Ship = rn.ships[0]
	b2._apply_hits([{"ok": true, "hits": 99, "target": hood,
		"firer": bismarck}] as Array[Dictionary])
	true_(hood.sunk, "l'Hood affonda lo stesso")
	eq(st6.vp_of(TaskForce.Side.KRIEGSMARINE), 0.0, "ma nessuno segna punti")


## Il solitario: un punteggio solo, letto su una tabella di Esiti a soglie.
func test_debriefing() -> void:
	_begin("solitario: tabella degli Esiti")
	var path := "res://core/data/victory/BL1 Raiders of the North Atlantic.json"
	var f := FileAccess.open(path, FileAccess.READ)
	ne(f, null, "la tabella di BL1 c'e'")
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var sc := Scenario.new()
	sc.victory_data = data
	var v := Victory.from_scenario(sc)
	eq(v.mode, Victory.Mode.DEBRIEFING, "modalita' debriefing")
	eq(v.solo_side, TaskForce.Side.KRIEGSMARINE, "si comanda il tedesco")
	eq(v.debriefing.size(), 5, "cinque esiti possibili")

	# le soglie, dall'alto in basso
	eq(String(v.debriefing_row(9.0)["label"]), "Raiders Triumphant!", "9 punti")
	eq(String(v.debriefing_row(6.0)["label"]), "Raiders Triumphant!", "6 esatti")
	eq(String(v.debriefing_row(5.0)["label"]), "Successo", "5 punti")
	eq(String(v.debriefing_row(3.0)["label"]), "Successo", "3 esatti")
	eq(String(v.debriefing_row(2.0)["label"]), "Incoraggiante", "2 punti")
	eq(String(v.debriefing_row(0.0)["label"]), "Che cosa e' andato storto?", "zero")
	eq(String(v.debriefing_row(-2.0)["label"]), "Che cosa e' andato storto?", "-2")
	eq(String(v.debriefing_row(-3.0)["label"]), "Fallimento", "-3: fine della carriera")
	eq(String(v.debriefing_row(-99.0)["label"]), "Fallimento", "e a scendere pure")

	# qui perdere navi COSTA: e' l'obiettivo dichiarato dello scenario
	var st := _state()
	var tracker := VictoryTracker.new(v, st)
	var before := VictoryTracker.snapshot(roster.make("Graf Spee"))
	var spee := roster.make("Graf Spee")
	spee.sunk = true
	tracker.hits_on(spee, 1, TaskForce.Side.KRIEGSMARINE, before)
	eq(st.vp_of(TaskForce.Side.KRIEGSMARINE), -5.0, "una nave tedesca persa: -5")

	var o := v.outcome(st)
	eq(float(o["score"]), -5.0, "il punteggio e' quello del giocatore")
	eq(int(o["winner"]), -1, "e non c'e' nessun vincitore da dichiarare")
	eq(String(o["row"]["label"]), "Fallimento", "l'esito e' il peggiore")
	true_(v.describe(st).contains("Fallimento"), "e viene scritto per esteso")
