class_name Victory
extends RefCounted

## Punti Vittoria e assegnazione della vittoria.
##
## In Atlantic Chase i VP non hanno una tabella unica: OGNI scenario ha la sua,
## con valori diversi per nave e per evento (nella Rheinubung affondare il
## Bismarck vale 7 VP al britannico, un incrociatore 2). Quindi la tabella e'
## un dato dello scenario, non del regolamento, e sta in
## core/data/victory/<nome>.json - file separato dallo scenario, che invece e'
## generato dal .vsav: cosi' una rigenerazione non cancella una trascrizione
## fatta a mano.
##
## Schema di un premio:
##   { "side": "ROYAL_NAVY", "event": "SHIP_SUNK",
##     "match": {"names": ["Bismarck"], "nations": ["GE"]}, "points": 7 }
##
## Il filtro `match` accetta names, types, nations ed exclude_names. Servono
## tutti: senza `nations` il premio tedesco per una corazzata britannica
## affondata scatterebbe anche sul Bismarck, che e' una corazzata; senza
## `exclude_names` il Bismarck prenderebbe sia la sua riga sia quella generica
## delle corazzate, e la tabella dice esplicitamente "non il Bismarck".
##
## `tiebreak.auto` false significa che la condizione e' scritta a parole e la
## verificano i giocatori: sono clausole come "il tedesco vince se il Bismarck
## e' in un porto francese", che cambiano da scenario a scenario. Il motore la
## mostra e chiede, invece di fingere di saperla valutare.

enum Event { SHIP_DAMAGED, SHIP_SUNK, CONVOY_COMPLETED, HIT_ON_CONVOY, CUSTOM }

const EVENT_NAMES := {
	"SHIP_DAMAGED": Event.SHIP_DAMAGED,
	"SHIP_SUNK": Event.SHIP_SUNK,
	"CONVOY_COMPLETED": Event.CONVOY_COMPLETED,
	"HIT_ON_CONVOY": Event.HIT_ON_CONVOY,
	"CUSTOM": Event.CUSTOM,
}

var awards: Array[Dictionary] = []
var tiebreak: Dictionary = {}
var has_table: bool = false
var notes: Array = []


static func from_scenario(sc: Scenario) -> Victory:
	var v := Victory.new()
	var d: Dictionary = sc.victory_data
	v.notes = d.get("notes", [])
	v.tiebreak = d.get("tiebreak", {})
	for a_v: Variant in d.get("awards", []):
		var a: Dictionary = a_v
		v.awards.append({
			"side": TaskForce.Side.KRIEGSMARINE if String(a.get("side", "")) == "KRIEGSMARINE"
				else TaskForce.Side.ROYAL_NAVY,
			"event": EVENT_NAMES.get(String(a.get("event", "CUSTOM")), Event.CUSTOM),
			"match": a.get("match", {}),
			"points": float(a.get("points", 0.0)),
			"label": String(a.get("label", "")),
		})
	v.has_table = not v.awards.is_empty()
	return v


## La nave corrisponde al filtro? Un filtro vuoto vale per qualunque nave.
static func _matches(ship: Ship, m: Dictionary) -> bool:
	if m.is_empty():
		return true
	# le righe generiche escludono le navi che hanno una riga propria: la
	# tabella della Rheinubung lo scrive nero su bianco ("non il Bismarck")
	if m.has("exclude_names"):
		for n_v: Variant in m["exclude_names"]:
			if ship.name.to_lower() == String(n_v).to_lower():
				return false
	if m.has("names"):
		var ok := false
		for n_v: Variant in m["names"]:
			if ship.name.to_lower() == String(n_v).to_lower():
				ok = true
		if not ok:
			return false
	if m.has("types"):
		var ok2 := false
		for t_v: Variant in m["types"]:
			if ship.type_code == String(t_v):
				ok2 = true
		if not ok2:
			return false
	if m.has("nations"):
		var ok3 := false
		for n_v: Variant in m["nations"]:
			if ship.nation == String(n_v):
				ok3 = true
		if not ok3:
			return false
	return true


## Punti che un evento su questa nave assegna, e a chi.
## Ritorna un Array di { "side": int, "points": float, "label": String }.
func awards_for(event: int, ship: Ship) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in awards:
		if int(a["event"]) != event:
			continue
		if ship != null and not _matches(ship, a["match"]):
			continue
		out.append({"side": int(a["side"]), "points": float(a["points"]),
			"label": String(a["label"])})
	return out


## Applica a GameState i VP di un evento. Ritorna le righe da mettere nel log.
func apply_event(state: GameState, event: int, ship: Ship = null,
		detail: String = "") -> Array[String]:
	var lines: Array[String] = []
	for a in awards_for(event, ship):
		var pts := float(a["points"])
		if is_zero_approx(pts):
			continue
		state.add_vp(int(a["side"]), int(round(pts)))
		var who := "Kriegsmarine" if int(a["side"]) == TaskForce.Side.KRIEGSMARINE \
			else "Royal Navy"
		var what := String(a["label"])
		if what == "":
			what = ship.name if ship != null else detail
		lines.append("VP: %+d a %s  (%s)" % [int(round(pts)), who, what])
	return lines


## Esito finale. Ritorna:
##   { "km": int, "rn": int, "winner": int (-1 = parita' da risolvere),
##     "tie": bool, "tiebreak_text": String, "resolved": bool }
func outcome(state: GameState) -> Dictionary:
	var km := state.vp_of(TaskForce.Side.KRIEGSMARINE)
	var rn := state.vp_of(TaskForce.Side.ROYAL_NAVY)
	var out := {"km": km, "rn": rn, "tie": km == rn, "resolved": true,
		"winner": -1, "tiebreak_text": String(tiebreak.get("condition", ""))}
	if km > rn:
		out["winner"] = TaskForce.Side.KRIEGSMARINE
	elif rn > km:
		out["winner"] = TaskForce.Side.ROYAL_NAVY
	else:
		# parita': decide la clausola dello scenario, che quasi sempre e'
		# scritta a parole e la verificano i giocatori
		out["resolved"] = bool(tiebreak.get("auto", false))
		if out["resolved"]:
			out["winner"] = TaskForce.Side.KRIEGSMARINE \
				if String(tiebreak.get("side", "")) == "KRIEGSMARINE" \
				else TaskForce.Side.ROYAL_NAVY
	return out


func describe(state: GameState) -> String:
	var o := outcome(state)
	var lines: Array[String] = []
	lines.append("Punti Vittoria - Kriegsmarine %d, Royal Navy %d" % [o["km"], o["rn"]])
	if not o["tie"]:
		lines.append("Vince %s." % ("la Kriegsmarine"
			if int(o["winner"]) == TaskForce.Side.KRIEGSMARINE else "la Royal Navy"))
	elif o["resolved"]:
		lines.append("Parita': per la regola dello scenario vince %s."
			% ("la Kriegsmarine" if int(o["winner"]) == TaskForce.Side.KRIEGSMARINE
				else "la Royal Navy"))
	else:
		lines.append("Parita'. Decide la clausola dello scenario:")
		lines.append("  " + String(o["tiebreak_text"]))
	if not has_table:
		lines.append("(tabella VP non trascritta per questo scenario: "
			+ "i punti vanno contati a mano dal fascicolo)")
	return "\n".join(lines)
