extends TestCase

## Il modo solitario: l'avversario immaginario e le sue tabelle.

var graph: MapGraph


func name() -> String:
	return "Solitario"


func run() -> void:
	graph = MapGraph.load_default()
	test_tables_load()
	test_action_table_rows()
	test_phase_switch()
	test_modifiers()
	test_identify()
	test_unidentified_speed()
	test_fueling()


func _rng(forced: Array) -> DiceRNG:
	var r := DiceRNG.new(1)
	r.push_forced(forced)
	return r


func test_tables_load() -> void:
	_begin("le tabelle si caricano")
	for id in ["BL1 Raiders of the North Atlantic", "BL2 Contain and Destroy"]:
		var o := SoloOpponent.load_for(id)
		ne(o, null, "%s ha le sue tabelle" % id)
		eq(o.scenario_id, id, "e sa di chi sono")
		true_(o.has("identify"), "%s: tabella di Identificazione" % id)
	# uno scenario senza tabelle non esplode, ritorna null
	eq(SoloOpponent.load_for("Op5 Rheinubung"), null,
		"le Operazioni non hanno un avversario immaginario")


## La riga si sceglie contando i Completamenti riusciti dell'altra parte: piu'
## l'avversario e' avanti, piu' la tabella diventa aggressiva.
func test_action_table_rows() -> void:
	_begin("BL2: righe della Tabella delle Azioni")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	var t: SoloTable = o.table("actions_early")
	ne(t, null, "la tabella Presto c'e'")
	eq(t.rows.size(), 3, "tre righe")

	eq(t.row_for(0), 0, "zero Completamenti: prima riga")
	eq(t.row_for(1), 1, "uno: seconda")
	eq(t.row_for(2), 2, "due: terza")
	eq(t.row_for(7), 2, "e sette resta la terza")

	# le caselle agli estremi, lette come le stampa il fascicolo
	eq(String(t.read(0, 1)["code"]), "A", "riga 0, dado 1")
	eq(String(t.read(0, 6)["code"]), "C", "riga 0, dado 6")
	eq(String(t.read(2, 1)["code"]), "E", "riga 2+, dado 1")
	eq(String(t.read(2, 6)["code"]), "C", "riga 2+, dado 6")

	# un dado fuori scala non deve uscire dalla tabella
	eq(String(t.read(0, 9)["code"]), "C", "un tiro troppo alto resta sull'ultima")
	eq(String(t.read(0, -3)["code"]), "A", "e uno troppo basso sulla prima")

	# ogni casella ha la sua procedura per esteso
	for code in ["A", "C", "E", "T", "X", "convoy"]:
		true_(String(t.legend.get(code, "")).length() > 40,
			"la procedura '%s' e' trascritta" % code)


## Si comincia con la tabella Presto e si passa alla Tardi dopo una Battaglia,
## un Convoglio distrutto o un Attacco Aereo.
func test_phase_switch() -> void:
	_begin("BL2: da Presto a Tardi")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	eq(o.phase, SoloOpponent.Phase.EARLY, "si comincia Presto")

	var r := o.act(_rng([1]), 0)
	true_(r["ok"], "la tabella si legge")
	eq(String(r["table"]), "actions_early", "ed e' quella Presto")

	true_(o.go_late("c'e' stata una Battaglia"), "si passa a Tardi")
	false_(o.go_late("di nuovo"), "ma una volta sola")
	eq(String(o.phase_reason), "c'e' stata una Battaglia", "e si sa perche'")

	var r2 := o.act(_rng([1]), 0)
	eq(String(r2["table"]), "actions_late", "ora si legge la Tardi")
	# nella Tardi la riga e' il METEO, non i Completamenti
	eq(String(r2["code"]), "E", "meteo buono, dado 1")
	eq(String(o.act(_rng([1]), 1)["code"]), "E", "meteo cattivo, dado 1")
	eq(String(o.act(_rng([3]), 0)["code"]), "A", "meteo buono, dado 3")
	eq(String(o.act(_rng([3]), 1)["code"]), "T", "meteo cattivo, dado 3")


## Il modificatore c'e' ma non si applica da solo: il motore non sa se una nave
## tedesca e' danneggiata finche' non glielo si dice.
func test_modifiers() -> void:
	_begin("BL2: il modificatore -1")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	o.go_late("prova")
	var t: SoloTable = o.table("actions_late")
	eq(t.modifiers.size(), 1, "un solo modificatore")
	var label := String((t.modifiers[0] as Dictionary)["label"])
	eq(int((t.modifiers[0] as Dictionary)["value"]), -1, "e vale -1")

	eq(t.modifier_total([]), 0, "senza condizioni non si applica")
	eq(t.modifier_total([label]), -1, "con la condizione si applica")

	# con il -1 il tiro scivola di una colonna
	var senza := o.act(_rng([3]), 0)
	var con := o.act(_rng([3]), 0, [label])
	eq(int(senza["roll"]), 3, "3 senza modificatore")
	eq(int(con["roll"]), 2, "2 con il modificatore")
	eq(String(senza["code"]), "A", "colonna 3")
	eq(String(con["code"]), "A", "colonna 2")
	# e il registro mostra il conto
	true_(SoloTable.describe(con).contains("-1"), "il conto e' scritto: "
		+ SoloTable.describe(con).substr(0, 40))


func test_identify() -> void:
	_begin("identificare una Task Force")
	var o := SoloOpponent.load_for("BL2 Contain and Destroy")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.name = "TF ignota"
	tf.unidentified = true

	var r := o.identify(_rng([1]), tf)
	true_(r["ok"], "l'identificazione si esegue")
	eq(String(r["code"]), "PB", "dado 1: corazzata tascabile")
	eq(String(o.identify(_rng([3]), tf)["code"]), "CA", "dado 3")
	eq(String(o.identify(_rng([5]), tf)["code"]), "Convoglio", "dado 5")

	# una TF gia' identificata non si ri-identifica
	tf.unidentified = false
	var r2 := o.identify(_rng([1]), tf)
	false_(r2["ok"], "una TF nota non si identifica di nuovo")
	true_(String(r2["error"]).contains("gia' identificata"), "e lo dice")

	# le sostituzioni ("se ci sono gia' due CA...") restano scritte, perche'
	# le fa il giocatore
	var t: SoloTable = o.table("identify")
	true_(t.note.contains("sostituisci"), "le sostituzioni sono riportate")


## Una TF non identificata e' "molto lenta" per definizione.
func test_unidentified_speed() -> void:
	_begin("velocita' di una TF non identificata")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.ships.append(ShipRoster.shared().make("Bismarck"))
	tf.recompute_speed()
	ne(tf.speed, TimeLapse.Speed.VERY_SLOW, "con il Bismarck non e' lentissima")

	tf.unidentified = true
	tf.recompute_speed()
	eq(tf.speed, TimeLapse.Speed.VERY_SLOW,
		"ma se non e' identificata si', qualunque cosa contenga")

	# e la cosa sopravvive a un salvataggio
	var back := TaskForce.from_dict(tf.to_dict())
	true_(back.unidentified, "resta non identificata dopo il salvataggio")
	eq(back.speed, TimeLapse.Speed.VERY_SLOW, "e resta lentissima")


## In BL1 il giocatore e' il tedesco, e la tabella che conta e' quella del
## Rifornimento: e' il caso, non un avversario.
func test_fueling() -> void:
	_begin("BL1: Tabella del Rifornimento")
	var o := SoloOpponent.load_for("BL1 Raiders of the North Atlantic")
	var t: SoloTable = o.table("fueling")
	ne(t, null, "la tabella c'e'")
	eq(t.rows.size(), 2, "due righe: meteo buono e cattivo")

	eq(String(t.read(0, 1)["code"]), "a", "buono, dado 1")
	eq(String(t.read(0, 6)["code"]), "e", "buono, dado 6")
	eq(String(t.read(1, 1)["code"]), "a", "cattivo, dado 1")
	eq(String(t.read(1, 6)["code"]), "g", "cattivo, dado 6")
	# il maltempo peggiora le cose: con 3 il buono da' 'b', il cattivo 'e'
	eq(String(t.read(0, 3)["code"]), "b", "buono, dado 3")
	eq(String(t.read(1, 3)["code"]), "e", "cattivo, dado 3")

	for code in ["a", "b", "c", "d", "e", "f", "g"]:
		ne(String(t.legend.get(code, "")), "",
			"la procedura '%s' e' trascritta" % code)

	# la tabella Murmansk ha un modificatore che il giocatore attiva
	var m: SoloTable = o.table("murmansk")
	ne(m, null, "e c'e' anche la tabella Murmansk")
	eq(m.modifier_total(["due o piu' Convogli distrutti"]), -1,
		"che peggiora se hai distrutto molti Convogli")
	eq(String(m.read(0, 1)["code"]), "confisca", "con 1 le navi sono confiscate")
	eq(String(m.read(0, 6)["code"]), "salvi", "con 6 rientrano a Kiel")
