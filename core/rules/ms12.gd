class_name Ms12
extends RefCounted

## MS12 Finale, dicembre 1943 (fascicolo a due giocatori p.51).
##
## E' l'unico mini-scenario che non e' una Battaglia. E' TRE Battaglie di due
## Round ciascuna, e prima di ognuna il britannico tira 2d6 per sapere con
## quale delle tre Forze combatte:
##
##   A   Convoglio e Squadrone DD          attitudine a scelta
##   B   Belfast, Norfolk, Sheffield       attitudine a scelta
##   C   Fiji e Duke of York               Closing
##
## I due modificatori del tiro raccontano da soli l'arco dello scenario: +2 se
## il Convoglio e' gia' stato preso di mira e +3 se lo Scharnhorst e' azzoppato,
## cioe' piu' la caccia va avanti piu' e' probabile che arrivi la Duke of York.
##
## Fino a oggi l'app lo apriva come una Battaglia sola con tutte le navi in
## campo insieme: si giocava, ma non era MS12 - mancava la sua unica meccanica,
## e il tiro delle Forze non veniva fatto mai.
##
## Che cosa questa classe fa e che cosa NON fa: costruisce le tre Parti e
## applica la regola di chi puo' restare fuori. Non decide l'attitudine dello
## Scharnhorst, che il fascicolo vuole scelta SEGRETAMENTE prima del tiro: e'
## una decisione del giocatore tedesco, e inventarla toglierebbe allo scenario
## la sua sola informazione nascosta.

const DATA_PATH := "res://core/data/ms12.json"

var data: Dictionary = {}
var load_error: String = ""


static func load_default() -> Ms12:
	var m := Ms12.new()
	m.load_from(DATA_PATH)
	return m


func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "impossibile aprire %s" % path
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		load_error = "JSON non valido in %s" % path
		return false
	data = parsed
	return true


func parts() -> int:
	return int(data.get("parts", 3))


func rounds_per_part() -> int:
	return int(data.get("rounds_per_part", 2))


func force_names() -> Array[String]:
	var out: Array[String] = []
	for k_v: Variant in (data.get("forces", {}) as Dictionary).keys():
		out.append(String(k_v))
	out.sort()
	return out


## Il modificatore al tiro delle Forze, dallo stato della Battaglia precedente.
##
## "+2 if the Convoy has been the target of gunnery; +3 if the German BC is
## crippled." I due si sommano: la pagina non li presenta come alternativi.
func force_modifier(convoy_targeted: bool, german_bc_crippled: bool) -> int:
	var total := 0
	if convoy_targeted:
		total += 2
	if german_bc_crippled:
		total += 3
	return total


## Quale Forza tocca al britannico in questa Parte.
## Ritorna { "force", "roll", "modifier", "total", "log" }.
func roll_force(rng: DiceRNG, convoy_targeted: bool,
		german_bc_crippled: bool) -> Dictionary:
	var roll := rng.d6x2("MS12: Forza britannica")
	var modifier := force_modifier(convoy_targeted, german_bc_crippled)
	var total := roll + modifier
	var force := force_for(total)
	var why: Array[String] = []
	if convoy_targeted:
		why.append("+2 il Convoglio e' stato bersaglio del Fuoco")
	if german_bc_crippled:
		why.append("+3 lo Scharnhorst e' azzoppato")
	return {
		"force": force,
		"roll": roll,
		"modifier": modifier,
		"total": total,
		"log": "MS12 - Forza britannica: 2d6=%d%s -> %d, Forza %s." % [roll,
			"" if why.is_empty() else " (%s)" % ", ".join(why), total, force],
	}


func force_for(total: int) -> String:
	for row_v: Variant in (data.get("force_table", {}) as Dictionary).get("rows", []):
		var row: Dictionary = row_v
		if total >= int(row.get("min", 0)) and total <= int(row.get("max", 99)):
			return String(row.get("force", ""))
	return ""


func force_ships(force: String) -> Array[String]:
	var out: Array[String] = []
	var f: Dictionary = (data.get("forces", {}) as Dictionary).get(force, {})
	for s_v: Variant in f.get("ships", []):
		out.append(String(s_v))
	return out


## L'attitudine imposta a una Forza, o -1 se il giocatore puo' scegliere.
func force_attitude(force: String) -> int:
	var f: Dictionary = (data.get("forces", {}) as Dictionary).get(force, {})
	var a := String(f.get("attitude", "either"))
	if a == "CLOSING":
		return Attitude.Kind.CLOSING
	if a == "RUNNING":
		return Attitude.Kind.RUNNING
	return -1


## Questa nave puo' restare fuori dalla Parte?
##
## "Except for the DD Squadron and the Convoy, the British player may elect to
## keep a ship out of the game if it is crippled. All other ships must
## participate regardless of Hits and special effects incurred in a previous
## Part." Sono due regole in una: chi e' azzoppato PUO' restare fuori, ma il
## Convoglio e lo Squadrone DD non possono mai - e nessuno resta fuori solo
## perche' ha preso dei Colpi.
func may_stay_out(ship: Ship) -> bool:
	if ship == null:
		return false
	if ship.kind == Ship.Kind.CONVOY or ship.kind == Ship.Kind.DD_SQUADRON:
		return false
	return AdvancedGunnery.is_crippled(ship)


## Costruisce la Battaglia di una Parte: lo Scharnhorst da una parte, la Forza
## tirata dall'altra, tutti nella zona Lontana, due Round.
##
## `carried` sono le navi britanniche che tornano da una Parte precedente col
## loro danno addosso: il fascicolo dice "regardless of Hits and special
## effects incurred in a previous Part", quindi la nave e' la STESSA, non una
## copia nuova. `kept_out` sono quelle che il giocatore ha scelto di tenere
## fuori, e la scelta viene rifiutata se la regola non la permette.
func build_part(force: String, weather: int, carried: Dictionary = {},
		kept_out: Array = []) -> Dictionary:
	var out := {"ok": false, "error": "", "state": null,
		"ships": [] as Array[Ship], "log": [] as Array[String]}
	var names := force_ships(force)
	if names.is_empty():
		out["error"] = "Forza '%s' sconosciuta" % force
		return out
	var bs := BattleState.new(BattleState.Kind.BATTLE, weather)
	bs.predeployed = true
	bs.advanced = true
	bs.last_round = rounds_per_part()

	var km := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	km.name = "Kriegsmarine"
	var rn := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	rn.name = "Royal Navy"

	for german_v: Variant in (data.get("german", {}) as Dictionary).get("ships", []):
		var gname := String(german_v)
		var g: Ship = carried.get(gname, null)
		if g == null:
			g = ShipRoster.shared().make(gname)
		if g == null:
			out["error"] = "nave tedesca '%s' assente dal ruolino" % gname
			return out
		g.battle_zone = BattleState.Zone.FAR
		km.ships.append(g)
		(out["ships"] as Array[Ship]).append(g)

	var forced := force_attitude(force)
	for name in names:
		if kept_out.has(name):
			continue
		var sh: Ship = carried.get(name, null)
		if sh == null:
			sh = ShipRoster.shared().make(name)
		if sh == null:
			out["error"] = "nave britannica '%s' assente dal ruolino" % name
			return out
		var why := stay_out_refusal(sh)
		sh.battle_zone = BattleState.Zone.FAR
		if forced >= 0:
			sh.attitude = forced
		rn.ships.append(sh)
		(out["ships"] as Array[Ship]).append(sh)
		if why == "" and not kept_out.has(name):
			(out["log"] as Array[String]).append(
				"%s e' azzoppata e potrebbe restare fuori: partecipa lo stesso." % name)
	for name_v: Variant in kept_out:
		var name2 := String(name_v)
		var candidate: Ship = carried.get(name2, null)
		var refusal := stay_out_refusal(candidate) if candidate != null \
			else "%s non ha combattuto prima: non puo' restare fuori" % name2
		if refusal != "":
			out["error"] = refusal
			return out
		(out["log"] as Array[String]).append(
			"%s e' azzoppata e resta fuori da questa Parte." % name2)

	if rn.ships.is_empty():
		out["error"] = "la Forza %s resterebbe senza navi" % force
		return out
	bs.active_tf = rn
	bs.target_tf = km
	out["state"] = bs
	out["ok"] = true
	return out


func stay_out_refusal(ship: Ship) -> String:
	if ship == null:
		return "nave assente"
	if ship.kind == Ship.Kind.CONVOY or ship.kind == Ship.Kind.DD_SQUADRON:
		return "il Convoglio e lo Squadrone DD partecipano sempre"
	if not AdvancedGunnery.is_crippled(ship):
		return ("%s non e' azzoppata: i Colpi e gli effetti presi in una Parte "
			+ "precedente non bastano a tenerla fuori") % ship.name
	return ""
