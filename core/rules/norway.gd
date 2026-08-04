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
	state.changed.emit()
	return out


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
