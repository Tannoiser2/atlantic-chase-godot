extends TestCase

## Completamenti in Norvegia (fascicolo solitario p.16).
##
## Tre differenze rispetto a un Completamento normale, e sono tutte stampate:
## serve un Convoglio o uno Squadrone DD nella Task Force; la Task Force NON
## viene rimossa e fa Scorrere del Tempo; ma l'avversario immaginario invece la
## perde. La terza sembra un'incoerenza ed e' scritta cosi' nel fascicolo.

var inset: MapGraph


func name() -> String:
	return "Completamenti in Norvegia"


func run() -> void:
	inset = MapGraph.load_inset("map_norwegian_sea")
	test_neutral_ports()
	test_who_may_complete()
	test_player_keeps_the_force()
	test_imaginary_player_loses_it()
	test_n5_adjacent_landing()
	test_norwegian_reaction_tables()


func _tf(st: GameState, side: int, h: Vector2i, ships: Array) -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	for n_v: Variant in ships:
		var s := ShipRoster.shared().make(String(n_v))
		if s != null:
			tf.ships.append(s)
	tf.trajectory.become_station(h)
	st.add_task_force(tf)
	return tf


func test_neutral_ports() -> void:
	_begin("i porti norvegesi sono neutrali")
	true_(Norway.is_neutral_port("Narvik"), "Narvik")
	true_(Norway.is_neutral_port("Trondheim"), "Trondheim")
	true_(Norway.is_neutral_port("Bergen"), "Bergen")
	false_(Norway.is_neutral_port("Scapa Flow"), "Scapa Flow no")
	# Un porto norvegese e' un esagono di Norvegia; e lo e' anche l'esagono di
	# un Punto di Interesse, perche' N1 chiede di posare le Mine "in the hexes
	# with Bud and Andalsnes".
	true_(Norway.is_norway_hex(inset, inset.port_hex("Narvik")), "l'esagono di Narvik")
	true_(Norway.is_norway_hex(inset, Vector2i(6, 1)),
		"e quello di Andalsnes, che e' un Punto di Interesse")
	false_(Norway.is_norway_hex(inset, Vector2i(3, 1)), "il mare aperto no")


func test_who_may_complete() -> void:
	_begin("in Norvegia si Completa solo col carico")
	var st := GameState.new(inset, 1)
	var uk := TaskForce.Side.ROYAL_NAVY
	var narvik := inset.port_hex("Narvik")

	var warship := _tf(st, uk, narvik, ["Sheffield"])
	false_(Norway.can_complete(inset, warship, narvik),
		"una TF di sole navi da guerra non Completa in Norvegia")
	true_(Norway.completion_error(inset, warship, narvik).contains("Convoglio"),
		"e il motivo cita il carico richiesto")

	var convoy := _tf(st, uk, narvik, ["Convoy x2", "Sheffield"])
	true_(Norway.can_complete(inset, convoy, narvik), "col Convoglio si'")
	var dd := _tf(st, uk, narvik, ["DD Squadron"])
	true_(Norway.can_complete(inset, dd, narvik),
		"e anche col solo Squadrone DD, che porta truppe")

	# Fuori dalla Norvegia, e fuori dal proprio esagono, no.
	false_(Norway.can_complete(inset, convoy, Vector2i(3, 1)),
		"il mare aperto non e' Norvegia")
	var elsewhere := _tf(st, uk, Vector2i(3, 1), ["Convoy x2"])
	false_(Norway.can_complete(inset, elsewhere, narvik),
		"e una TF altrove non Completa qui")


## "do not remove the TF or its ships. Instead, perform Time Lapse."
func test_player_keeps_the_force() -> void:
	_begin("il giocatore tiene la Task Force")
	var st := GameState.new(inset, 1)
	var uk := TaskForce.Side.ROYAL_NAVY
	var narvik := inset.port_hex("Narvik")
	var tf := _tf(st, uk, narvik, ["Convoy x2"])
	var before := st.task_forces.size()

	var out := Norway.complete(st, inset, tf, narvik, false)
	true_(bool(out["ok"]), "il Completamento riesce: %s" % String(out["reason"]))
	false_(bool(out["removed"]),
		"e la Task Force NON viene rimossa: e' l'opposto di un Completamento in porto")
	true_(bool(out["time_lapse"]), "al suo posto si fa Scorrere del Tempo")
	eq(st.task_forces.size(), before, "la TF e' ancora sulla mappa")
	false_(tf.completed, "e non risulta Completata")
	# "roll a die and check the result on the Norwegian Reaction Table"
	true_(bool(out["check_reaction"]), "e va controllata la Reazione Norvegese")


## "Enemy Completion in Norway: When the imaginary player successfully Completes
## in Norway, remove the TF and its ships." Il contrario, ed e' scritto cosi'.
func test_imaginary_player_loses_it() -> void:
	_begin("l'avversario immaginario la perde")
	var st := GameState.new(inset, 1)
	var ge := TaskForce.Side.KRIEGSMARINE
	var trondheim := inset.port_hex("Trondheim")
	var tf := _tf(st, ge, trondheim, ["Convoy x2"])
	var before := st.task_forces.size()

	var out := Norway.complete(st, inset, tf, trondheim, true)
	true_(bool(out["ok"]), "il Completamento riesce")
	true_(bool(out["removed"]), "ma la Task Force esce di scena con le sue navi")
	false_(bool(out["time_lapse"]), "e non fa Scorrere del Tempo")
	eq(st.task_forces.size(), before - 1, "una TF in meno sulla mappa")
	# "The imaginary player is not required to do this (Reaction is incorporated
	# into the Action Tables)."
	false_(bool(out["check_reaction"]),
		"e il bot non tira la Reazione Norvegese: e' gia' dentro le sue Tabelle")


## N5 p.32: si puo' Completare in un esagono ADIACENTE a Narvik o Trondheim,
## "however, the 'landing' hex must have land in it and not all sea".
func test_n5_adjacent_landing() -> void:
	_begin("lo sbarco adiacente di N5")
	var narvik := inset.port_hex("Narvik")
	var ports := ["Narvik", "Trondheim"]
	# Un esagono di solo mare non va bene nemmeno se e' adiacente.
	var open_sea := Vector2i(4, -1)
	true_(inset.land_fraction(open_sea) < Norway.LAND_MIN,
		"(4,-1) e' mare aperto: il 2%% di verde e' sfumatura di costa (%.2f)"
			% inset.land_fraction(open_sea))
	true_(Norway.adjacent_landing_error(inset, open_sea, ports).contains("terra"),
		"un esagono tutto mare non e' un punto di sbarco")
	# Un esagono con della terra ma lontano dai due porti nemmeno.
	var far_land := Vector2i(6, 2)
	true_(Norway.adjacent_landing_error(inset, far_land, ports) != "",
		"e nemmeno uno lontano dai due porti")
	# L'esagono di Narvik stesso non e' "adiacente a Narvik".
	true_(Norway.adjacent_landing_error(inset, narvik, ports) != "",
		"l'esagono del porto non e' adiacente a se stesso")


## Le quattro tabelle di Reazione Norvegese, trascritte da pp.19, 24, 27, 34.
##
## Non hanno la stessa forma, ed e' il motivo per cui questo test esiste: N1 ha
## una riga sola, N2 si divide sulle Mine britanniche, N3 su una TF britannica,
## N5 su "nell'esagono o adiacente". Trattarle come quattro copie della stessa
## tabella e' l'errore facile.
func test_norwegian_reaction_tables() -> void:
	_begin("le quattro tabelle di Reazione Norvegese")
	var f := FileAccess.open("res://core/data/solo/norwegian_reaction.json",
		FileAccess.READ)
	true_(f != null, "il file delle tabelle c'e'")
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	true_(typeof(parsed) == TYPE_DICTIONARY, "ed e' JSON valido")
	var doc: Dictionary = parsed
	var tables: Dictionary = doc.get("tables", {})
	eq(tables.size(), 4, "quattro tabelle, una per scenario")

	var pages := {"N1 Operazione Wilfred": 19, "N2 Operazione Weser (nord)": 24,
		"N3 Operazione Weser (sud)": 27, "N5 Meglio Tardi che Mai": 34}
	var missing: Array[String] = []
	var unsourced: Array[String] = []
	var bad_shape: Array[String] = []
	for id_v: Variant in pages.keys():
		var id := String(id_v)
		if not tables.has(id):
			missing.append(id)
			continue
		var t: Dictionary = tables[id]
		if int(t.get("_page", 0)) != int(pages[id]):
			unsourced.append(id)
		if String(t.get("trigger", "")) == "" or (t.get("legend", {}) as Dictionary).is_empty():
			unsourced.append(id)
		# Ogni riga deve avere una cella per colonna: una tabella sbilanciata e'
		# una trascrizione sbagliata, non un dato incompleto.
		var cols: int = (t.get("columns", []) as Array).size()
		for row_v: Variant in t.get("rows", []):
			var row: Dictionary = row_v
			if (row.get("cells", []) as Array).size() != cols:
				bad_shape.append("%s/%s" % [id, String(row.get("label", "?"))])
			for c_v: Variant in row.get("cells", []):
				if not (t.get("legend", {}) as Dictionary).has(String(c_v)):
					bad_shape.append("%s: risultato '%s' senza legenda" % [id, String(c_v)])
	eq(missing.size(), 0, "nessuna tabella manca: %s" % ", ".join(missing))
	eq(unsourced.size(), 0, "tutte citano pagina, innesco e legenda: %s" % ", ".join(unsourced))
	eq(bad_shape.size(), 0, "tutte le righe sono complete e spiegate: %s" % ", ".join(bad_shape))

	# Le quattro forme sono DIVERSE, e il dato lo deve dire.
	var n1: Dictionary = tables["N1 Operazione Wilfred"]
	eq((n1.get("rows", []) as Array).size(), 1, "N1 ha una riga sola")
	# p.19, e il testo estratto dal PDF lo dava all'incontrario: 1-2 e' la
	# reazione adirata, non l'assenza di reazione.
	var n1_row: Dictionary = (n1["rows"] as Array)[0]
	eq(String((n1_row["cells"] as Array)[0]), "angry",
		"su 1-2 la reazione e' adirata")
	eq(String((n1_row["cells"] as Array)[1]), "none",
		"e su 3-6 non c'e' reazione")
	true_(String(n1.get("note", "")).contains("Debriefing"),
		"e N1 dichiara che la reazione non tocca la partita, solo il Debriefing")

	true_(String(tables["N2 Operazione Weser (nord)"].get("axis", "")).contains("Mine"),
		"N2 si divide sulle Mine britanniche")
	true_(String(tables["N3 Operazione Weser (sud)"].get("axis", "")).contains("Task Force"),
		"N3 su una Task Force britannica")
	true_(String(tables["N5 Meglio Tardi che Mai"].get("axis", "")).contains("ADIACENTE"),
		"N5 su dentro o adiacente all'esagono del porto")
	# N5 e' l'unica con risultati che spostano Basi Aeree.
	true_((tables["N5 Meglio Tardi che Mai"]["legend"] as Dictionary).has("g"),
		"e solo N5 ha risultati che spostano le Basi Aeree")
	true_(String(doc.get("_status", "")).contains("non ancora automatizzate"),
		"il dato dichiara che le tabelle non sono ancora giocate")
