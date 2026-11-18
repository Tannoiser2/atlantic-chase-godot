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


static func _share_hex(a: TaskForce, b: TaskForce) -> bool:
	if a == null or b == null:
		return false
	var hs := a.trajectory.hexes()
	if a.trajectory.is_station():
		hs.append(a.trajectory.station_hex)
	for h in hs:
		if b.trajectory.occupies(h):
			return true
	return false


static func _has_usable_cv(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s in tf.ships:
		if s.type_code == "CV" and not s.damaged and not s.sunk:
			return true
	return false


## Esagoni dai quali una TF puo' lanciare un Attacco Aereo (RB p.27).
## Le basi aeree non sono ancora nello stato di gioco: qui sono comprese solo
## le TF con una CV integra, senza fingere che un innesco Informazioni sia una
## base utilizzabile.
static func air_launch_hexes(tf: TaskForce) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _has_usable_cv(tf):
		return out
	if tf.trajectory.is_station():
		out.append(tf.trajectory.station_hex)
	else:
		out.assign(tf.trajectory.hexes())
	return out


## Esagoni della TF bersaglio entro il raggio di due esagoni (RB p.27).
static func air_target_hexes(launch_hex: Vector2i,
		target: TaskForce) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if launch_hex == Vector2i.MAX or target == null:
		return out
	var occupied: Array[Vector2i] = []
	if target.trajectory.is_station():
		occupied.append(target.trajectory.station_hex)
	else:
		occupied.assign(target.trajectory.hexes())
	for h in occupied:
		if Hex.distance(launch_hex, h) <= 2:
			out.append(h)
	return out


# ------------------------------------------------------------- dichiarazione --

class Declaration extends RefCounted:
	var action_key: String = ""
	var active: TaskForce = null
	var active_coordinating: TaskForce = null
	var active_air_support: TaskForce = null
	var target: TaskForce = null
	var target_coordinating: TaskForce = null
	var target_air_support: TaskForce = null
	var launch_hex: Vector2i = Vector2i.MAX
	var target_hex: Vector2i = Vector2i.MAX
	## Modificatori che una PROCEDURA STAMPATA impone all'azione (il +3
	## dell'Attacco Furtivo di N3, p.26). I Modificatori Comuni NON vanno qui:
	## li calcola `CommonModifiers.compute` dalle designazioni qui sotto.
	var modifier: int = 0

	## Punto di Lancio del Supporto Aereo, per parte. Con una TF e' uno dei
	## suoi esagoni; con una base aerea e' l'esagono della base, e allora la TF
	## resta null e la base sta nel campo `_base`.
	var active_air_support_hex: Vector2i = Vector2i.MAX
	var active_air_support_base: Dictionary = {}
	var target_air_support_hex: Vector2i = Vector2i.MAX
	var target_air_support_base: Dictionary = {}

	## RB p.47: "Invece di una Task Force, un giocatore puo' designare una forza
	## Furtiva amica (U-Boat, Mine o Sottomarini) come forza Coordinatrice".
	var active_coordinating_stealth: Dictionary = {}
	var target_coordinating_stealth: Dictionary = {}

	## L'Inattivo spende il segnalino Manovre Evasive della TF Bersaglio per
	## imporre il modificatore avverso (RB p.46).
	var target_spends_evasive: bool = false

	## Benefici di Comandante invocati in questa Azione (RB p.10), per nome:
	## "Walker" (Coordinamento +4), "Somerville" (+2 al tiro). Chi li mette qui
	## ha gia' verificato che siano disponibili; `LeaderRules.spend_declared`
	## li consuma quando l'azione si risolve.
	var leader_benefits: Array[String] = []

	## Krancke / Tovey: 2d6 col segno scelto, sommati al Totale Traiettoria.
	var trajectory_total_shift: int = 0
	var trajectory_total_shift_by: String = ""
	## La forza Furtiva che esegue l'azione, quando a eseguirla NON e' una Task
	## Force. RB p.41 la ammette come attaccante dell'Attacco Furtivo, ed e'
	## l'unica azione in cui succede: qui l'Attiva puo' quindi restare `null`.
	## E' il Dictionary di `GameState.stealth_forces`, non una copia.
	var active_stealth: Dictionary = {}

	## La base aerea che esegue l'azione, quando a eseguirla NON e' una Task
	## Force. RB p.27 la mette sullo stesso piano: "Una Task Force con una CV non
	## danneggiata, O UNA BASE AEREA, possono essere designate come TF Attiva".
	## E' il Dictionary di `GameState.placed_air_bases` oppure quello che
	## `AirBase.printed_of` ricava da `MapGraph.air_bases`.
	var active_air_base: Dictionary = {}

	## Di chi e' l'azione. Serve perche' con un attaccante Furtivo non c'e' una
	## TF Attiva da cui leggere la parte, e la traccia dei Modificatori e
	## l'Iniziativa hanno comunque bisogno di saperlo.
	func acting_side() -> int:
		if active != null:
			return active.side
		if not active_stealth.is_empty():
			return int(active_stealth.get("side", -1))
		if not active_air_base.is_empty():
			return int(active_air_base.get("side", -1))
		return -1

	func designated_active() -> Array[TaskForce]:
		var out: Array[TaskForce] = []
		for t in [active, active_coordinating, active_air_support]:
			if t != null:
				out.append(t)
		return out

	## Le TF che il BERSAGLIO ha designato a sostegno. RB pp.27, 31, 33: dopo
	## il risultato "ciascuna Task Force designata effettua lo Scorrere del Tempo
	## ECCETTO la Task Force bersaglio" - quindi anche queste.
	func designated_target_support() -> Array[TaskForce]:
		var out: Array[TaskForce] = []
		for t in [target_coordinating, target_air_support]:
			if t != null and t != target and not out.has(t):
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
	# L'Attacco Furtivo e' l'unica azione che una forza Furtiva puo' eseguire da
	# sola (RB p.41): li' l'Attiva manca per costruzione, e la restrizione al
	# bersaglio la detta `Stealth`, non questa funzione.
	var by_stealth := dec.action_key == "STEALTH_ATTACK" \
		and not dec.active_stealth.is_empty()
	if by_stealth:
		if dec.active != null:
			return "un Attacco Furtivo ha una forza Furtiva OPPURE una TF Attiva, non entrambe"
		var stealth_why := Stealth.attack_error(state, dec.active_stealth, dec.target)
		if stealth_why != "":
			return stealth_why
	# Stessa cosa per l'Attacco Aereo lanciato da una base aerea (RB p.27): la
	# fonte e' la base, e una base non e' una Task Force.
	var by_air_base := dec.action_key == "AIR_STRIKE" \
		and not dec.active_air_base.is_empty()
	if by_air_base and dec.active != null:
		return "un Attacco Aereo ha una base aerea OPPURE una TF Attiva, non entrambe"
	if not by_stealth and not by_air_base and dec.active == null:
		return "manca la Task Force Attiva"
	var box_why := PortBox.declaration_error(dec)
	if box_why != "":
		return box_why
	var optional_why := OptionalRules.declaration_error(dec, state)
	if optional_why != "":
		return optional_why
	if not is_verified(dec.action_key):
		return "tabella non ancora trascritta per '%s': %s" \
			% [a.get("label", dec.action_key), a.get("verified_note", "")]
	if bool(a.get("requires_target_station", false)):
		if dec.target == null:
			return "questa azione richiede una Task Force Bersaglio"
		if not dec.target.trajectory.is_station():
			return "il bersaglio dell'Ingaggio deve essere una Stazione Task Force"
		if not _share_hex(dec.active, dec.target):
			return "Ingaggiare richiede una TF Bersaglio nello stesso esagono"
	if dec.action_key == "NAVAL_SEARCH":
		if dec.target == null:
			return "questa azione richiede una Task Force Bersaglio"
		if dec.target.trajectory.is_station():
			return "il bersaglio della Ricerca Navale deve essere una Traiettoria"
		if not _share_hex(dec.active, dec.target):
			return "Ricerca Navale richiede un segmento bersaglio nello stesso esagono della TF Attiva"
	if bool(a.get("requires_good_weather", false)) and state.weather != TimeLapse.Weather.GOOD:
		return "%s richiede Condizioni Meteo Buone" % String(a.get("label", dec.action_key))
	if dec.action_key == "AIR_STRIKE":
		if not by_air_base and not _has_usable_cv(dec.active):
			return "Attacco Aereo richiede una TF Attiva con CV non danneggiata o una base aerea"
		if dec.target == null:
			return "Attacco Aereo richiede una Task Force Bersaglio"
		if dec.launch_hex == Vector2i.MAX:
			return "Attacco Aereo richiede di scegliere il Punto di Lancio"
		# "L'Attacco Aereo origina dall'esagono della Stazione o BASE AEREA o,
		# se Traiettoria, da uno degli esagoni dove vi sono i suoi segmenti."
		if by_air_base:
			if AirBase.hex_of(dec.active_air_base) != dec.launch_hex:
				return "il Punto di Lancio deve essere l'esagono della base aerea"
		elif not dec.active.trajectory.occupies(dec.launch_hex):
			return "il Punto di Lancio deve essere un esagono della TF con la CV"
		if dec.target_hex == Vector2i.MAX:
			return "Attacco Aereo richiede di scegliere l'esagono Bersaglio"
		if not dec.target.trajectory.occupies(dec.target_hex):
			return "l'esagono Bersaglio non appartiene alla TF bersaglio"
		if Hex.distance(dec.launch_hex, dec.target_hex) > 2:
			return "il bersaglio dell'Attacco Aereo e' oltre il raggio di due esagoni"
		# LACUNA DICHIARATA, e vale anche per l'Attacco Aereo da una CV: RB p.27
		# vieta al Punto di Lancio e al bersaglio di stare sulla Linea Artica, e
		# vieta all'attacco di attraversarla. La Linea Artica non e' un dato di
		# mappa in questo progetto - compare solo come testo negli scenari e
		# nella Verifica Snafu - quindi quel vincolo non e' controllabile qui.
	for coordinating in [dec.active_coordinating, dec.target_coordinating]:
		if coordinating != null and (dec.target_hex == Vector2i.MAX \
				or not coordinating.trajectory.occupies(dec.target_hex)):
			return "la TF Coordinatrice deve occupare l'esagono Bersaglio"
	for stealth in [dec.active_coordinating_stealth, dec.target_coordinating_stealth]:
		if not (stealth as Dictionary).is_empty() and (dec.target_hex == Vector2i.MAX \
				or Vector2i(int(stealth.get("q", 0)), int(stealth.get("r", 0)))
					!= dec.target_hex):
			return "la forza Furtiva Coordinatrice deve stare nell'esagono Bersaglio"
	if dec.active_coordinating != null and not dec.active_coordinating_stealth.is_empty():
		return "una sola forza Coordinatrice per giocatore (RB p.47)"
	if dec.target_coordinating != null and not dec.target_coordinating_stealth.is_empty():
		return "una sola forza Coordinatrice per giocatore (RB p.47)"
	if dec.action_key == "COMPLETION" and not dec.active.can_complete():
		return "una TF con segnalino Informazioni non puo' effettuare il Completamento"
	# una Task Force con un Convoglio ha le mani legate: niente Attacco Aereo,
	# Ingaggiare o Ricerca Navale (RB p.11). Sta scortando, non cacciando.
	# Una forza Furtiva non scorta niente, quindi la regola non la tocca.
	# Una base aerea non scorta niente, come la forza Furtiva.
	if not by_stealth and not by_air_base:
		var convoy_why := Convoy.action_refusal(dec.active, dec.action_key)
		if convoy_why != "":
			return convoy_why
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
		"unverified": false, "modifier_lines": [] as Array[String],
	}
	var err := legality_error(dec, state)
	if err != "":
		out["error"] = err
		return out

	# Modificatori Comuni (RB pp.45-47). Si calcolano prima dell'Interruzione
	# perche' dipendono solo dalle designazioni; il segnalino Manovre Evasive
	# pero' si spende solo se si arriva a tirare.
	var common := CommonModifiers.compute(dec, state)
	var mod_lines: Array[String] = []
	if dec.modifier != 0:
		mod_lines.append("Procedura stampata: %+d" % dec.modifier)
	mod_lines.append_array(common["lines"])
	out["modifier"] = dec.modifier + int(common["total"])
	out["modifier_lines"] = mod_lines

	# 3. Totale Traiettoria
	var desig := dec.to_designations()
	var tt := TrajectoryTotal.compute(desig)
	var explain := TrajectoryTotal.explain(desig)
	# Krancke e Tovey (RB p.10): 2d6 aggiunti o sottratti al Totale
	# Traiettoria. Il tiro lo fa chi dichiara, PRIMA di decidere se usarlo;
	# qui arriva gia' col segno. Il Totale non scende sotto zero (p.17).
	if dec.trajectory_total_shift != 0:
		tt = maxi(0, tt + dec.trajectory_total_shift)
		explain.append("%s: %+d al Totale Traiettoria" % [
			dec.trajectory_total_shift_by, dec.trajectory_total_shift])
	out["trajectory_total"] = tt
	out["tt_explain"] = explain
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
			state.set_modifier_track(dec.acting_side(), int(out["modifier"]))
			return out
		out["modifier"] = int(out["modifier"]) + int(ir["modifier"])

	# 5. tiro
	if not is_table_driven(dec.action_key):
		out["ok"] = true
		state.set_modifier_track(dec.acting_side(), int(out["modifier"]))
		return out
	if dec.target_spends_evasive and dec.target != null and dec.target.evasive:
		dec.target.evasive = false
	LeaderRules.spend_declared(state, dec)
	var dice := state.rng.d6x2("azione %s" % dec.action_key)
	out["dice"] = dice
	out["dice_pair"] = state.rng.last_pair()
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
	state.set_modifier_track(dec.acting_side(), int(out["modifier"]))
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
		var applied: Array[String] = []
		for line_v: Variant in res.get("modifier_lines", []):
			# le righe che dichiarano una lacuna o un "non si applica" non sono
			# modificatori: stanno nel dettaglio, non nel riassunto
			if (String(line_v).contains(": +") or String(line_v).contains(": -")) \
					and not String(line_v).ends_with(": +0"):
				applied.append(String(line_v))
		if not applied.is_empty():
			parts.append("[" + "; ".join(applied) + "]")
	if not (res["result_labels"] as Array).is_empty():
		parts.append("risultato: " + ", ".join(res["result_labels"]))
	else:
		parts.append("nessun risultato")
	if res["unverified"]:
		parts.append("[cella da riverificare sulla mappa]")
	return " | ".join(parts)


## Forbes e Marschall (RB p.10): "Quando avete appena tirato uno o piu' dadi
## durante una Azione... e la Task Force [del Comandante] e' la TF Attiva...
## potete sostituire uno dei numeri ottenuti con un 6."
##
## Rilegge la tabella con il dado piu' basso portato a 6 e ritorna il nuovo
## risultato, SENZA applicarlo: decide chi chiama, dopo aver visto che cosa
## cambia. `res` e' il Dictionary di `resolve`. {} se non c'e' niente da
## guadagnare (due 6) o l'azione non tira dadi.
func reread_with_six(res: Dictionary, dec: Declaration) -> Dictionary:
	var pair: Array = res.get("dice_pair", [])
	if pair.size() != 2 or not is_table_driven(dec.action_key):
		return {}
	var low := mini(int(pair[0]), int(pair[1]))
	var high := maxi(int(pair[0]), int(pair[1]))
	if low == 6:
		return {}
	var out := res.duplicate(true)
	var dice := high + 6
	var total := dice + int(res["modifier"])
	var tt := int(res["trajectory_total"])
	var codes := lookup(dec.action_key, total, tt)
	var labels: Array[String] = []
	for c in codes:
		labels.append(String(result_info(c).get("label", c)))
	out["dice"] = dice
	out["dice_pair"] = [high, 6]
	out["sum"] = total
	out["results"] = codes
	out["result_labels"] = labels
	out["unverified"] = is_cell_unverified(dec.action_key, total, tt)
	return out
