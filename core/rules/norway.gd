class_name Norway
extends RefCounted

## Completamenti in Norvegia e Reazione Norvegese.
## Fascicolo Scenari in Solitario, seconda edizione, p.16.
##
## Nei sei scenari 'N' la Norvegia e' neutrale, e il Completamento li' non
## funziona come altrove. Tre differenze, tutte stampate:
##
##   1. CHI PUO'. "The player is only allowed a Completion action in a Norway
##      hex when a Convoy or DD Squadron is in the TF." Non basta essere in un
##      esagono di Norvegia: ci vuole il carico.
##
##   2. LA TF NON SE NE VA. "When such a Completion action succeeds in Norway,
##      do not remove the TF or its ships. Instead, perform Time Lapse." E'
##      l'opposto di un Completamento in porto, dove la Task Force esce di
##      scena. Rappresenta truppe e rifornimenti sbarcati, non una nave
##      rientrata alla base.
##
##   3. TRANNE PER IL BOT. "Enemy Completion in Norway: When the imaginary
##      player successfully Completes in Norway, remove the TF and its ships."
##      L'avversario immaginario invece la TF la perde: e' una semplificazione
##      del fascicolo, non una svista, e va rispettata com'e' scritta.
##
## Sulla neutralita': "A Trajectory segment placed in a space with a Norwegian
## port, such as Narvik, does not trigger Intel", e "Norwegian ports are not
## connected to port boxes (that is, the Bergen, Trondheim, and Narvik port
## boxes are out of play in these scenarios)".

## I porti norvegesi. Sono neutrali: non innescano Informazioni e non hanno
## Casella Porto in questi scenari.
const NEUTRAL_PORTS := ["Narvik", "Trondheim", "Bergen"]

## Quanta terra serve perche' un esagono conti come "ha della terra".
##
## La regola di N5 dice "must have land in it and not all sea", e non da' una
## soglia: la soglia serve alla MISURA, non alla regola. La frazione di terra
## e' misurata contando pixel su un'immagine stampata, e la sfumatura della
## costa lascia un due per cento di verde anche in esagoni di mare aperto -
## (4,-1) del Mare di Norvegia ne ha 0.02 e di terra non ne ha. Cinque per
## cento separa il rumore dalla terra vera.
const LAND_MIN := 0.05


static func is_neutral_port(name: String) -> bool:
	return NEUTRAL_PORTS.has(name)


## Un esagono di Norvegia? Qui vale la definizione operativa che serve al
## gioco: contiene un porto norvegese o un Punto di Interesse norvegese.
## Sugli inserti i Punti di Interesse sono nel grafo (p.16: "no effect on game
## play, except to orient the player" - ma il loro esagono e' un bersaglio).
static func is_norway_hex(graph: MapGraph, h: Vector2i) -> bool:
	for name in graph.ports_in(h):
		if is_neutral_port(name):
			return true
	if graph.is_inset():
		for p in graph.points_of_interest:
			if Vector2i(int(p.get("q", 0)), int(p.get("r", 0))) == h:
				return true
	return false


## Il carico che il fascicolo richiede: un Convoglio o uno Squadrone DD.
static func carries_landing_force(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s in tf.ships:
		if s.sunk:
			continue
		if s.kind == Ship.Kind.CONVOY or s.kind == Ship.Kind.DD_SQUADRON:
			return true
		if s.name.begins_with("Convoy") or s.name == "DD Squadron":
			return true
	return false


## Perche' NON si puo' Completare qui. Stringa vuota = si puo'.
static func completion_error(graph: MapGraph, tf: TaskForce, h: Vector2i) -> String:
	if tf == null or tf.completed:
		return "nessuna Task Force"
	if not tf.trajectory.occupies(h):
		return "%s non e' in %s" % [tf.display_name(), str(h)]
	if not is_norway_hex(graph, h):
		return "%s non e' un esagono di Norvegia" % str(h)
	if not carries_landing_force(tf):
		return ("in Norvegia si Completa solo con un Convoglio o uno Squadrone "
			+ "DD nella Task Force")
	return ""


static func can_complete(graph: MapGraph, tf: TaskForce, h: Vector2i) -> bool:
	return completion_error(graph, tf, h) == ""


## Risolve il Completamento in Norvegia. Ritorna
## { "ok", "reason", "log", "time_lapse", "removed", "check_reaction" }.
##
## `imaginary` distingue le due meta' della regola: il giocatore tiene la Task
## Force e fa Scorrere del Tempo, l'avversario immaginario la perde.
## `check_reaction` e' vero solo per il giocatore: "The imaginary player is not
## required to do this (Reaction is incorporated into the Action Tables)".
static func complete(state: GameState, graph: MapGraph, tf: TaskForce,
		h: Vector2i, imaginary: bool) -> Dictionary:
	var out := {"ok": false, "reason": "", "log": [] as Array[String],
		"time_lapse": false, "removed": false, "check_reaction": false}
	var err := completion_error(graph, tf, h)
	if err != "":
		out["reason"] = err
		return out
	out["ok"] = true
	var where := ", ".join(graph.ports_in(h))
	if where == "" and graph.is_inset():
		var pts: Array[String] = graph.points_of_interest_in(h)
		where = ", ".join(pts)
	if where == "":
		where = str(h)
	if imaginary:
		# "When the imaginary player successfully Completes in Norway, remove
		# the TF and its ships."
		out["removed"] = true
		(out["log"] as Array[String]).append(
			"Completamento in Norvegia a %s: %s esce di scena con le sue navi."
			% [where, tf.display_name()])
		state.remove_task_force(tf)
	else:
		# "do not remove the TF or its ships. Instead, perform Time Lapse."
		out["time_lapse"] = true
		out["check_reaction"] = true
		(out["log"] as Array[String]).append(
			("Completamento in Norvegia a %s: %s resta in gioco e fa Scorrere "
				+ "del Tempo.") % [where, tf.display_name()])
		(out["log"] as Array[String]).append(
			"Va controllata la Reazione Norvegese.")
	_record_landing(state, tf.side, h)
	state.changed.emit()
	return out


## Dove e' avvenuto uno sbarco, e di chi.
##
## Serve perche' piu' di una procedura stampata guarda INDIETRO: il dado del
## Convoglio di N5 (p.33) ha "-1 if British performed a successful Completion
## action in or adjacent to Trondheim", e i modificatori della Reazione
## Norvegese di p.34 contano i Completamenti precedenti. Il Completamento in
## Norvegia non lascia altra traccia - la Task Force del giocatore resta in
## gioco e `completed_port` non viene scritto - quindi senza questo elenco
## quello storico non esisteva, ed era una lacuna dichiarata nel TODO.
##
## Sta in `solo_counters` perche' e' gia' dentro il salvataggio: una partita
## ripresa deve applicare gli stessi modificatori.
static func _record_landing(state: GameState, side: int, h: Vector2i) -> void:
	var landings: Array = state.solo_counters.get("norway_landings", [])
	landings.append({"side": side, "q": h.x, "r": h.y})
	state.solo_counters["norway_landings"] = landings


## Gli sbarchi gia' avvenuti, per parte.
static func landings_of(state: GameState, side: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for entry_v: Variant in state.solo_counters.get("norway_landings", []):
		var entry: Dictionary = entry_v
		if int(entry.get("side", -1)) == side:
			out.append(Vector2i(int(entry.get("q", 0)), int(entry.get("r", 0))))
	return out


## Una parte ha gia' sbarcato in quell'esagono o in uno adiacente?
static func landed_in_or_next_to(state: GameState, side: int,
		h: Vector2i) -> bool:
	if h == Vector2i.MAX:
		return false
	for landed in landings_of(state, side):
		if Hex.distance(landed, h) <= 1:
			return true
	return false


## N5, p.32: "the British are allowed to perform a Completion action in a hex
## adjacent to Narvik or Trondheim (however, the 'landing' hex must have land in
## it and not all sea)". E' una deroga di scenario, non una regola generale:
## chi la usa deve dichiararlo.
static func adjacent_landing_error(graph: MapGraph, h: Vector2i,
		to_ports: Array) -> String:
	if graph.land_fraction(h) < LAND_MIN:
		return "l'esagono di sbarco deve avere della terra, non essere tutto mare"
	for name_v: Variant in to_ports:
		var ph := graph.port_hex(String(name_v))
		if ph != Vector2i.MAX and Hex.are_adjacent(h, ph):
			return ""
	return "%s non e' adiacente a %s" % [str(h), ", ".join(to_ports)]


# ------------------------------------------------- Reazione Norvegese --

## Le quattro tabelle stanno nel dato, una per scenario, con innesco, colonne,
## righe, modificatori e legenda: `core/data/solo/norwegian_reaction.json`,
## trascritte da pp.19, 24, 27 e 34.
const REACTION_PATH := "res://core/data/solo/norwegian_reaction.json"


static func reaction_table(scenario_id: String) -> Dictionary:
	var f := FileAccess.open(REACTION_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var tables: Variant = (parsed as Dictionary).get("tables", {})
	if typeof(tables) != TYPE_DICTIONARY:
		return {}
	for k_v: Variant in (tables as Dictionary).keys():
		var k := String(k_v)
		if scenario_id == k or scenario_id.begins_with(k.get_slice(" ", 0)):
			return (tables as Dictionary)[k]
	return {}


## Quale RIGA della tabella. Le quattro si dividono su condizioni diverse, e
## sono scritte una per una perche' sono predicati sullo stato, non dato.
static func _reaction_row(state: GameState, graph: MapGraph, table: Dictionary,
		scenario_id: String, tf: TaskForce, h: Vector2i) -> int:
	var rows: Array = table.get("rows", [])
	if rows.size() <= 1:
		return 0
	if scenario_id.begins_with("N2"):
		# "British Mines in hex?"
		for f in state.stealth_forces:
			if int(f.get("kind", -1)) == Stealth.Kind.MINES \
					and int(f.get("side", -1)) == TaskForce.Side.ROYAL_NAVY \
					and Vector2i(int(f.get("q", 0)), int(f.get("r", 0))) == h:
				return 0
		return 1
	if scenario_id.begins_with("N3"):
		# "British TF in hex?"
		for other in state.task_forces:
			if other.side == TaskForce.Side.ROYAL_NAVY and not other.completed \
					and other.trajectory.occupies(h):
				return 0
		return 1
	if scenario_id.begins_with("N5"):
		# "in" oppure "adjacent" a Narvik o Trondheim.
		for name in ["Narvik", "Trondheim"]:
			if graph.port_hex(name) == h:
				return 0
		return 1
	return 0


## I modificatori applicabili, calcolati sullo stato. Ritorna
## { "total", "applied": Array[String], "undeclared": Array[String] }.
##
## `undeclared` sono i modificatori stampati che il motore NON sa calcolare
## perche' gli manca lo storico: N5 ne ha due che dipendono da Completamenti
## precedenti. Non si fingono zero in silenzio.
static func _reaction_modifiers(state: GameState, graph: MapGraph,
		scenario_id: String, tf: TaskForce, h: Vector2i) -> Dictionary:
	var total := 0
	var applied: Array[String] = []
	var undeclared: Array[String] = []
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	if scenario_id.begins_with("N1"):
		if _has_type_in(state, uk, h, "BB"):
			total += 1
			applied.append("+1 una BB britannica e' nell'esagono di Narvik")
	elif scenario_id.begins_with("N2"):
		var mines := 0
		for f in state.stealth_forces:
			if int(f.get("kind", -1)) == Stealth.Kind.MINES \
					and int(f.get("side", -1)) == uk:
				mines += 1
		if mines >= 2:
			total += 1
			applied.append("+1 due o piu' Mine britanniche sulla mappa")
		if _has_type_in(state, ge, h, "BC") or _has_type_in(state, ge, h, "CA"):
			total += 1
			applied.append("+1 un BC o CA tedesco e' nell'esagono")
		for other in state.task_forces:
			if other.side == uk and not other.completed and other.trajectory.occupies(h):
				total -= 1
				applied.append("-1 una TF britannica e' nell'esagono")
				break
	elif scenario_id.begins_with("N3"):
		if _has_type_in(state, ge, h, "CL"):
			total += 1
			applied.append("+1 un CL tedesco e' nell'esagono")
	elif scenario_id.begins_with("N5"):
		if _has_type_in(state, uk, h, "BB") or _has_type_in(state, uk, h, "BC"):
			total += 1
			applied.append("+1 una BB o BC britannica e' nell'esagono del Convoglio")
		undeclared.append("+1 se c'e' stato un precedente Completamento "
			+ "britannico nell'esagono o in uno adiacente")
		undeclared.append("+1 se c'e' stato un precedente Completamento "
			+ "britannico a Trondheim")
		undeclared.append("-1 (o -2) se un marker Base Aerea tedesca e' in "
			+ "Norvegia: le Basi Aeree non sono ancora pedine giocabili")
		if state.convoys_completed_for(ge) >= 2:
			total -= 1
			applied.append("-1 due o piu' Convogli tedeschi hanno Completato")
	return {"total": total, "applied": applied, "undeclared": undeclared}


static func _has_type_in(state: GameState, side: int, h: Vector2i,
		type_code: String) -> bool:
	for tf in state.task_forces:
		if tf.side != side or tf.completed or not tf.trajectory.occupies(h):
			continue
		for s in tf.ships:
			if not s.sunk and s.type_code == type_code:
				return true
	return false


## Tira la Reazione Norvegese e dice che cosa e' uscito. NON applica ancora
## nulla: l'applicazione sta in `apply_reaction`, cosi' il tiro si puo' provare
## da solo e il chiamante puo' mostrarlo prima di subirlo.
##
## Ritorna { "ok", "reason", "roll", "modifier", "total", "result", "text",
## "aggressive", "log", "undeclared" }.
static func roll_reaction(state: GameState, graph: MapGraph, rng: DiceRNG,
		scenario_id: String, tf: TaskForce, h: Vector2i) -> Dictionary:
	var out := {"ok": false, "reason": "", "roll": 0, "modifier": 0, "total": 0,
		"result": "", "text": "", "aggressive": false,
		"log": [] as Array[String], "undeclared": [] as Array[String]}
	var table := reaction_table(scenario_id)
	if table.is_empty():
		out["reason"] = "%s non ha una Tabella di Reazione Norvegese" % scenario_id
		return out
	var row_index := _reaction_row(state, graph, table, scenario_id, tf, h)
	var rows: Array = table.get("rows", [])
	if row_index >= rows.size():
		out["reason"] = "riga %d fuori dalla tabella" % row_index
		return out
	var row: Dictionary = rows[row_index]
	var mods := _reaction_modifiers(state, graph, scenario_id, tf, h)
	var roll := rng.d6("Reazione Norvegese (%s)" % scenario_id)
	var total: int = roll + int(mods["total"])
	var cells: Array = row.get("cells", [])
	var key := ""
	for i in (table.get("columns", []) as Array).size():
		var col: Dictionary = (table["columns"] as Array)[i]
		if total >= int(col.get("min", -99)) and total <= int(col.get("max", 99)):
			if i < cells.size():
				key = String(cells[i])
			break
	if key == "":
		out["reason"] = "nessuna colonna per il totale %d" % total
		return out
	var legend: Dictionary = table.get("legend", {})
	out["ok"] = true
	out["roll"] = roll
	out["modifier"] = int(mods["total"])
	out["total"] = total
	out["result"] = key
	out["text"] = String(legend.get(key, key))
	out["aggressive"] = String(out["text"]).contains("Reazione Aggressiva")
	out["undeclared"] = mods["undeclared"]
	var label := String(row.get("label", ""))
	(out["log"] as Array[String]).append(
		"Reazione Norvegese%s: 1d6=%d%s = %d -> %s"
		% ["" if label == "" else " (%s)" % label, roll,
			"" if int(mods["total"]) == 0 else " %+d" % int(mods["total"]),
			total, String(out["text"])])
	for m_v: Variant in mods["applied"]:
		(out["log"] as Array[String]).append("   " + String(m_v))
	for u_v: Variant in mods["undeclared"]:
		(out["log"] as Array[String]).append("   NON CALCOLATO: " + String(u_v))
	return out


## Applica il risultato. Ritorna { "hits", "cancelled", "initiative_to",
## "declared_gap", "log" }.
##
## I risultati che spostano marker Base Aerea (N5, 'b' e 'g') NON si applicano:
## le Basi Aeree non sono ancora pedine giocabili. Si dichiarano.
static func apply_reaction(state: GameState, result: Dictionary,
		tf: TaskForce) -> Dictionary:
	var out := {"hits": 0, "cancelled": false, "initiative_to": -1,
		"declared_gap": false, "log": [] as Array[String]}
	var key := String(result.get("result", ""))
	match key:
		"none":
			(out["log"] as Array[String]).append("Nessuna reazione.")
			return out
		"angry":
			# N1: "The reaction will not affect game play, but will influence
			# the Debriefing Table." Non tocca la partita, quindi non c'e'
			# niente da applicare - ma la Tabella di Debriefing di N1 ha DUE
			# colonne, e sceglie fra loro proprio questo. Se non lo si scrive
			# da qualche parte, al Debriefing la reazione non e' mai avvenuta.
			state.solo_counters["debriefing_norwegian_reaction"] = "angry"
			(out["log"] as Array[String]).append(
				"Reazione Adirata: non tocca la partita, ma al Debriefing si "
				+ "legge la colonna 'reazione norvegese adirata'.")
			state.changed.emit()
			return out
		"hit":
			out["hits"] = 1
		"two_hits":
			out["hits"] = 2
		"g_and_hit":
			out["hits"] = 1
			out["declared_gap"] = true
		"cancel":
			out["hits"] = 2
			out["cancelled"] = true
			# "British have Initiative" in N2/N3; "Germans have Initiative" in
			# N5. In tutti e tre i casi passa a CHI NON stava Completando.
			out["initiative_to"] = 1 - tf.side
		"ar":
			(out["log"] as Array[String]).append(
				"Le forze norvegesi resistono ma vengono sopraffatte: Reazione Aggressiva.")
			return out
		"b", "g":
			out["declared_gap"] = true
	if out["declared_gap"]:
		(out["log"] as Array[String]).append(
			"LACUNA DICHIARATA: il risultato sposta un marker Base Aerea, e le "
			+ "Basi Aeree non sono ancora pedine giocabili.")
	if int(out["hits"]) > 0:
		var landed := _hit_landing_force(tf, int(out["hits"]))
		(out["log"] as Array[String]).append(
			"%s subisce %d Colpo/i dalla Reazione Norvegese." % [landed, int(out["hits"])])
	if bool(out["cancelled"]):
		(out["log"] as Array[String]).append(
			"Il Completamento e' annullato e l'Iniziativa passa all'altra parte.")
	state.changed.emit()
	return out


## I Colpi vanno al Convoglio o allo Squadrone DD, che e' quello che il
## fascicolo colpisce: "Convoy or DD suffers a Hit".
static func _hit_landing_force(tf: TaskForce, hits: int) -> String:
	for s in tf.ships:
		if s.sunk:
			continue
		if s.kind == Ship.Kind.CONVOY or s.kind == Ship.Kind.DD_SQUADRON \
				or s.name.begins_with("Convoy") or s.name == "DD Squadron":
			s.hits += hits
			return s.name
	return tf.display_name()
