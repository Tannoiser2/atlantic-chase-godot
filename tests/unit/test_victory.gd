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
