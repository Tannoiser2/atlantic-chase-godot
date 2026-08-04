class_name Stealth
extends RefCounted

## Le forze Furtive: Mine, Sottomarini, U-Boat. RB p.41.
##
## Non sono Task Force. Non hanno navi, non hanno Traiettoria - il loro Totale
## Traiettoria e' zero - e stanno in un esagono e basta. Quello che le rende
## interessanti e' che il nemico non le vede: innescano Informazioni, non le
## subiscono, e non possono essere bersaglio di un Attacco Aereo.
##
## Questa classe e' pura: legge e scrive `GameState.stealth_forces`, che e' un
## semplice elenco di dizionari serializzabili, e non conosce la GUI.
##
## Le due azioni della pedina, dal regolamento:
##
##   RICOGNIZIONE - solo Sottomarini e U-Boat. La forza "deve poi essere mossa
##   di un esagono sulla mappa", e "non fa differenza dove la forza Furtiva e'
##   al momento in cui viene annunciata l'azione": e' un PIAZZAMENTO, non un
##   movimento, e non c'e' distanza da rispettare.
##
##   ATTACCO FURTIVO - Mine, Sottomarini e U-Boat. Bersaglia una TF nemica
##   nell'esagono della forza. La restrizione e' quella che da' senso al
##   segnalino Contatto: si puo' colpire solo una STAZIONE, oppure una
##   Traiettoria se il segmento bersaglio ha assegnato un Contatto o delle
##   Informazioni.

enum Kind { MINES, SUBMARINE, UBOAT }

const KIND_NAMES := {
	Kind.MINES: "Mine",
	Kind.SUBMARINE: "Sottomarino",
	Kind.UBOAT: "U-Boat",
}


static func kind_from_name(name: String) -> int:
	match name.to_lower():
		"mine", "mines":
			return Kind.MINES
		"sottomarino", "submarine":
			return Kind.SUBMARINE
	return Kind.UBOAT


static func kind_name(kind: int) -> String:
	return String(KIND_NAMES.get(kind, "U-Boat"))


## Le Mine non si spostano: una volta posate restano dove sono. Il regolamento
## da' la Ricognizione a "una delle sue forze U-Boat o Sottomarini", e le Mine
## non sono nell'elenco.
static func can_recon(kind: int) -> bool:
	return kind != Kind.MINES


static func forces_of(state: GameState, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in state.stealth_forces:
		if int(f.get("side", -1)) == side:
			out.append(f)
	return out


static func forces_at(state: GameState, h: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in state.stealth_forces:
		if _hex_of(f) == h:
			out.append(f)
	return out


## C'e' una forza Furtiva nemica in questo esagono? E' una delle quattro cause
## che assegnano Informazioni a un segmento (RB p.21).
static func enemy_force_at(state: GameState, h: Vector2i, mover_side: int) -> bool:
	for f in state.stealth_forces:
		if int(f.get("side", -1)) != mover_side and _hex_of(f) == h:
			return true
	return false


## Aggiunge una forza Furtiva senza controlli: serve allo schieramento, che
## trascrive posizioni stampate e non deve passare dalle regole di piazzamento.
static func place(state: GameState, side: int, kind: int, h: Vector2i,
		note: String = "") -> Dictionary:
	var f := {
		"side": side,
		"kind": kind,
		"q": h.x,
		"r": h.y,
		"note": note,
	}
	state.stealth_forces.append(f)
	state.changed.emit()
	return f


static func remove_at(state: GameState, h: Vector2i, side: int) -> bool:
	for i in range(state.stealth_forces.size() - 1, -1, -1):
		var f: Dictionary = state.stealth_forces[i]
		if _hex_of(f) == h and int(f.get("side", -1)) == side:
			state.stealth_forces.remove_at(i)
			state.changed.emit()
			return true
	return false


## Si puo' piazzare qui? RB p.41: mai in un esagono con una Base Aerea nemica o
## un esagono di porto nemico. E' invece PERMESSO stare in un esagono con una
## Task Force nemica che contiene un CV - il regolamento lo dice apposta, ed e'
## il caso che uno si aspetterebbe vietato.
##
## `port_control` e' la mappa nome-porto -> parte che lo controlla, la stessa
## che usano le azioni di Completamento.
static func placement_error(state: GameState, graph: MapGraph,
		port_control: Dictionary, side: int, h: Vector2i) -> String:
	if not graph.has_hex(h):
		return "l'esagono %s non e' sulla mappa" % str(h)
	for name in graph.ports_in(h):
		var owner_v: Variant = port_control.get(name, null)
		if owner_v == null:
			continue
		if int(owner_v) != side:
			return "%s e' un porto nemico" % name
	for base in graph.air_bases:
		if Vector2i(int(base.get("q", 0)), int(base.get("r", 0))) != h:
			continue
		if _side_from_tag(String(base.get("side", ""))) != side:
			return "c'e' una base aerea nemica"
	return ""


static func can_place_at(state: GameState, graph: MapGraph,
		port_control: Dictionary, side: int, h: Vector2i) -> bool:
	return placement_error(state, graph, port_control, side, h) == ""


## RICOGNIZIONE (RB p.41). Sposta la forza e assegna Informazioni a ogni Task
## Force nemica che ha una Stazione o un segmento nell'esagono di arrivo.
##
## Ritorna { "ok", "reason", "log", "informed", "declared_gap" }.
static func recon(state: GameState, graph: MapGraph, port_control: Dictionary,
		force: Dictionary, h: Vector2i) -> Dictionary:
	var out := {"ok": false, "reason": "", "log": [] as Array[String],
		"informed": [] as Array[String], "declared_gap": false}
	var side := int(force.get("side", -1))
	if not can_recon(int(force.get("kind", Kind.UBOAT))):
		out["reason"] = "le Mine non fanno Ricognizione: una volta posate restano dove sono"
		return out
	var err := placement_error(state, graph, port_control, side, h)
	if err != "":
		out["reason"] = err
		return out
	var from := _hex_of(force)
	force["q"] = h.x
	force["r"] = h.y
	out["ok"] = true
	(out["log"] as Array[String]).append(
		"Ricognizione: la forza %s va da %s a %s."
		% [kind_name(int(force.get("kind", Kind.UBOAT))), str(from), str(h)])
	# "assegnate un segnalino Informazioni alla Task Force in quell'esagono.
	# Fatelo per OGNI Task Force nemica che ha una Stazione o segmento
	# nell'esagono."
	for tf in state.task_forces:
		if tf.side == side or tf.completed:
			continue
		if not tf.trajectory.occupies(h):
			continue
		if tf.trajectory.is_station():
			# Il modello tiene le Informazioni sui SEGMENTI: una Stazione non ha
			# dove portarle. Non si inventa un posto, si dichiara.
			out["declared_gap"] = true
			(out["log"] as Array[String]).append(
				("LACUNA DICHIARATA: %s e' una Stazione, e il modello non sa "
					+ "ancora assegnare Informazioni a una Stazione.") % tf.display_name())
			continue
		var i := tf.trajectory.index_of_hex(h)
		if i >= 0 and tf.trajectory.set_info(i, true):
			(out["informed"] as Array[String]).append(tf.display_name())
			(out["log"] as Array[String]).append(
				"Informazioni assegnate a %s." % tf.display_name())
	state.changed.emit()
	return out


## ATTACCO FURTIVO, restrizione al bersaglio (RB p.41): "si puo' attaccare solo
## una Stazione Task Force nemica, o una Traiettoria se il segmento bersaglio ha
## assegnato un segnalino Contatto o Informazioni. La Stazione o segmento
## Traiettoria deve essere nell'esagono della forza Furtiva".
static func attack_error(state: GameState, force: Dictionary,
		target: TaskForce) -> String:
	if target == null or target.completed:
		return "nessun bersaglio"
	var side := int(force.get("side", -1))
	if target.side == side:
		return "non si attacca una Task Force della propria parte"
	var h := _hex_of(force)
	if not target.trajectory.occupies(h):
		return "%s non e' nell'esagono della forza Furtiva" % target.display_name()
	if target.trajectory.is_station():
		return ""
	var i := target.trajectory.index_of_hex(h)
	if i < 0:
		return "%s non ha un segmento in %s" % [target.display_name(), str(h)]
	var seg: Dictionary = target.trajectory.segments[i]
	if bool(seg.get("contact", false)) or bool(seg.get("info", false)):
		return ""
	return ("il segmento bersaglio non ha ne' Contatto ne' Informazioni: "
		+ "una Traiettoria e' immune all'Attacco Furtivo senza uno dei due")


static func can_attack(state: GameState, force: Dictionary,
		target: TaskForce) -> bool:
	return attack_error(state, force, target) == ""


## I bersagli legali di una forza Furtiva nel suo esagono.
static func targets_for(state: GameState, force: Dictionary) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in state.task_forces:
		if can_attack(state, force, tf):
			out.append(tf)
	return out


static func _hex_of(f: Dictionary) -> Vector2i:
	return Vector2i(int(f.get("q", 0)), int(f.get("r", 0)))


static func _side_from_tag(tag: String) -> int:
	return TaskForce.Side.ROYAL_NAVY if tag == "UK" else TaskForce.Side.KRIEGSMARINE
