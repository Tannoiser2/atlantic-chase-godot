class_name ActionEngine
extends RefCounted

## Motore delle Azioni (M4).
##
## Tutte le azioni tabellari di Atlantic Chase seguono la stessa pipeline, per
## cui conviene scriverla una volta sola e alimentarla con dati:
##
##   1. dichiarazione        - azione + TF designate (Attiva, Coordinatrice, Supporto Aereo)
##   2. legalita'            - vincoli specifici dell'azione
##   3. Totale Traiettoria   - determina la colonna (RB p.17)
##   4. Interruzione         - se le TF designate hanno segnalini Informazioni (RB p.22)
##   5. tiro 2d6 + modificatori
##   6. lettura tabella      - riga = somma, colonna = Totale Traiettoria
##   7. applicazione risultati
##
## Le tabelle stanno in core/data/actions.json, con un campo "verified" per
## ciascuna azione: il motore RIFIUTA di risolvere un'azione non verificata
## invece di inventarsi un risultato. Meglio un errore esplicito che una regola
## sbagliata applicata in silenzio.

const DATA_PATH := "res://core/data/actions.json"

var data: Dictionary = {}
var load_error: String = ""


static func load_default() -> ActionEngine:
	var e := ActionEngine.new()
	e.load_from(DATA_PATH)
	return e


func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "impossibile aprire %s" % path
		return false
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(p) != TYPE_DICTIONARY:
		load_error = "JSON non valido in %s" % path
		return false
	data = p
	return true


func actions() -> Dictionary:
	return data.get("actions", {})


func action(key: String) -> Dictionary:
	return (data.get("actions", {}) as Dictionary).get(key, {})


func result_info(code: String) -> Dictionary:
	return (data.get("results", {}) as Dictionary).get(code, {})


## "verified": true (tabella certa) | "partial" (con celle segnalate) | false.
## GDScript confronta male tipi diversi, quindi si controlla il tipo prima.
func is_verified(key: String) -> bool:
	var v: Variant = action(key).get("verified", false)
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_STRING:
		return String(v) == "partial"
	return false


func is_table_driven(key: String) -> bool:
	var a := action(key)
	return a.get("table_driven", true) == true and not (a.get("rows", []) as Array).is_empty()


## Indice di colonna per un dato Totale Traiettoria.
func column_for(key: String, trajectory_total: int) -> int:
	var cols: Array = action(key).get("columns", [])
	for i in cols.size():
		var c: Dictionary = cols[i]
		if trajectory_total >= int(c["min"]) and trajectory_total <= int(c["max"]):
			return i
	return maxi(0, cols.size() - 1)


func column_label(key: String, idx: int) -> String:
	var cols: Array = action(key).get("columns", [])
	if idx < 0 or idx >= cols.size():
		return "?"
	return String((cols[idx] as Dictionary)["label"])


## Risultati grezzi per somma dei dadi e Totale Traiettoria.
## Ritorna un Array di codici: alcune celle ne contengono due (es. CONTATTO +
## AVVISTATO nella Ricerca Navale).
func lookup(key: String, dice_sum: int, trajectory_total: int) -> Array[String]:
	var out: Array[String] = []
	var a := action(key)
	var col := column_for(key, trajectory_total)
	for row_v: Variant in a.get("rows", []):
		var row: Dictionary = row_v
		if dice_sum < int(row["min"]) or dice_sum > int(row["max"]):
			continue
		var cells: Array = row["results"]
		if col < cells.size():
			for c_v: Variant in cells[col] as Array:
				out.append(String(c_v))
		return out
	return out


## La cella e' fra quelle non ancora verificate sulla mappa fisica?
func is_cell_unverified(key: String, dice_sum: int, trajectory_total: int) -> bool:
	var a := action(key)
	var un: Array = a.get("unverified_cells", [])
	if un.is_empty():
		return false
	var col := column_for(key, trajectory_total)
	var rows: Array = a.get("rows", [])
	for i in rows.size():
		var row: Dictionary = rows[i]
		if dice_sum >= int(row["min"]) and dice_sum <= int(row["max"]):
			for u_v: Variant in un:
				var u: Array = u_v
				if int(u[0]) == i and int(u[1]) == col:
					return true
			return false
	return false


# ------------------------------------------------------------- dichiarazione --

class Declaration extends RefCounted:
	var action_key: String = ""
	var active: TaskForce = null
	var active_coordinating: TaskForce = null
	var active_air_support: TaskForce = null
	var target: TaskForce = null
	var target_coordinating: TaskForce = null
	var target_air_support: TaskForce = null
	var target_hex: Vector2i = Vector2i.MAX
	var modifier: int = 0          ## modificatori comuni gia' sommati

	func designated_active() -> Array[TaskForce]:
		var out: Array[TaskForce] = []
		for t in [active, active_coordinating, active_air_support]:
			if t != null:
				out.append(t)
		return out

	func to_designations() -> TrajectoryTotal.Designations:
		var d := TrajectoryTotal.Designations.new(
			active.length() if active else 0,
			target.length() if target else 0)
		d.active_coordinating = active_coordinating.length() if active_coordinating else -1
		d.active_air_support = active_air_support.length() if active_air_support else -1
		d.target_coordinating = target_coordinating.length() if target_coordinating else -1
		d.target_air_support = target_air_support.length() if target_air_support else -1
		return d


## Motivo per cui l'azione non e' dichiarabile (stringa vuota = legale).
func legality_error(dec: Declaration, state: GameState) -> String:
	var a := action(dec.action_key)
	if a.is_empty():
		return "azione sconosciuta: %s" % dec.action_key
	if dec.active == null:
		return "manca la Task Force Attiva"
	if not is_verified(dec.action_key):
		return "tabella non ancora trascritta per '%s': %s" \
			% [a.get("label", dec.action_key), a.get("verified_note", "")]
	if bool(a.get("requires_target_station", false)):
		if dec.target == null:
			return "questa azione richiede una Task Force Bersaglio"
		if not dec.target.trajectory.is_station():
			return "il bersaglio dell'Ingaggio deve essere una Stazione Task Force"
	if dec.action_key == "COMPLETION" and not dec.active.can_complete():
		return "una TF con segnalino Informazioni non puo' effettuare il Completamento"
	return ""


# ------------------------------------------------------------------ risoluzione --

## Risolve un'azione tabellare per intero.
## Ritorna un Dictionary con tutti i passaggi, cosi' che la UI possa mostrare
## il conto e il giocatore possa verificarlo:
##   { ok, error, trajectory_total, tt_explain, column, interruption,
##     dice, modifier, sum, results, result_labels, unverified }
func resolve(dec: Declaration, state: GameState) -> Dictionary:
	var out := {
		"ok": false, "error": "", "action": dec.action_key,
		"trajectory_total": 0, "tt_explain": [], "column": "",
		"interruption": {}, "dice": 0, "modifier": dec.modifier, "sum": 0,
		"results": [] as Array[String], "result_labels": [] as Array[String],
		"unverified": false,
	}
	var err := legality_error(dec, state)
	if err != "":
		out["error"] = err
		return out

	# 3. Totale Traiettoria
	var desig := dec.to_designations()
	var tt := TrajectoryTotal.compute(desig)
	out["trajectory_total"] = tt
	out["tt_explain"] = TrajectoryTotal.explain(desig)
	out["column"] = column_label(dec.action_key, column_for(dec.action_key, tt))

	# 4. Interruzione (RB p.22) - sospende l'azione
	var info := 0
	for t in dec.designated_active():
		info += t.info_count()
	if Interruption.is_triggered(info):
		var ir := Interruption.check(info, state.rng)
		out["interruption"] = ir
		if ir["result"] != Interruption.Result.ALERT:
			# Sfuggire / Cercare l'Iniziativa / Cambio di Iniziativa
			# annullano l'Azione: non si tira per l'azione stessa.
			out["ok"] = true
			out["error"] = ""
			out["results"] = [] as Array[String]
			return out
		out["modifier"] = int(out["modifier"]) + int(ir["modifier"])

	# 5. tiro
	if not is_table_driven(dec.action_key):
		out["ok"] = true
		return out
	var dice := state.rng.d6x2("azione %s" % dec.action_key)
	out["dice"] = dice
	var total := dice + int(out["modifier"])
	out["sum"] = total

	# 6. lettura tabella
	var codes := lookup(dec.action_key, total, tt)
	out["results"] = codes
	var labels: Array[String] = []
	for c in codes:
		labels.append(String(result_info(c).get("label", c)))
	out["result_labels"] = labels
	out["unverified"] = is_cell_unverified(dec.action_key, total, tt)
	out["ok"] = true
	return out


## Testo compatto del risultato, per il pannello di log.
func describe(res: Dictionary) -> String:
	if res["error"] != "":
		return "non consentita: %s" % res["error"]
	var parts: Array[String] = []
	parts.append("Totale Traiettoria %d (colonna %s)"
		% [res["trajectory_total"], res["column"]])
	var ir: Dictionary = res["interruption"]
	if not ir.is_empty() and ir.get("triggered", false):
		parts.append("Interruzione %d -> %s" % [ir["sum"], ir["label"]])
		if ir["result"] != Interruption.Result.ALERT:
			return " | ".join(parts) + " | Azione annullata"
	if int(res["dice"]) > 0:
		var m := int(res["modifier"])
		var msign := "" if m == 0 else (" %+d" % m)
		parts.append("2d6 = %d%s -> %d" % [res["dice"], msign, res["sum"]])
	if not (res["result_labels"] as Array).is_empty():
		parts.append("risultato: " + ", ".join(res["result_labels"]))
	else:
		parts.append("nessun risultato")
	if res["unverified"]:
		parts.append("[cella da riverificare sulla mappa]")
	return " | ".join(parts)
