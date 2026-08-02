class_name AdvancedTorpedo
extends RefCounted

## Attacco con Siluri, Regole Avanzate (fascicolo avanzato p.9).
##
## Quattro differenze dalle regole base, e tutte spostano il peso della
## decisione sull'ATTITUDINE:
##
##   1. si puo' attaccare anche dalla zona Vicina, non solo dalla Ravvicinata;
##   2. solo una nave in AVVICINAMENTO puo' silurare;
##   3. tre modificatori nuovi;
##   4. i risultati Grave e Catastrofico rimandano alla Tabella della Linea di
##      Galleggiamento.
##
##   dadi (2d6)   risultato
##   8 o meno     Splash
##   9-10         Risultato Grave        -> Linea di Galleggiamento
##   11 o piu'    Risultato Catastrofico -> Linea di Galleggiamento
##
## Non c'e' la casella "Colpo": un siluro o manca o fa un danno grave. E'
## coerente con quello che i siluri facevano davvero.

const TABLE := [
	[11, AdvancedGunnery.Result.CATASTROPHIC],
	[9, AdvancedGunnery.Result.SEVERE],
	[0, AdvancedGunnery.Result.SPLASH],
]

## Tabella della Linea di Galleggiamento, colonna GRAVE.
## La colonna Catastrofica sta sul player aid e non e' ancora stata letta:
## meglio dichiararlo che inventarla.
const WATERLINE_SEVERE := [
	[8, "Allagamento (molto lenta)"],
	[6, "Allagamento (ferma)"],
	[2, "Timone Fuori Uso"],
]


static func can_attack(firer: Ship) -> bool:
	return (firer.has_torpedo and not firer.sunk
		and Attitude.can_torpedo(firer)
		and (firer.battle_zone == BattleState.Zone.NEAR
			or firer.battle_zone == BattleState.Zone.CLOSE))


static func is_valid_target(target: Ship) -> bool:
	return (not target.sunk
		and (target.battle_zone == BattleState.Zone.NEAR
			or target.battle_zone == BattleState.Zone.CLOSE))


## I modificatori dell'attacco, con il perche' scritto accanto.
static func modifiers(firer: Ship, target: Ship) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sp := AdvancedGunnery.target_speed_modifier(target)
	if sp != 0:
		out.append({"label": "bersaglio %s"
			% TimeLapse.speed_label(target.current_speed()), "value": sp})
	if firer.battle_zone == BattleState.Zone.NEAR:
		out.append({"label": "attacco dalla zona Vicina", "value": -2})
	var run := Attitude.torpedo_target_modifier(target)
	if run != 0:
		out.append({"label": "bersaglio in Corsa", "value": run})
	return out


static func modifier_total(firer: Ship, target: Ship) -> int:
	var t := 0
	for m in modifiers(firer, target):
		t += int(m["value"])
	return t


static func read(total: int) -> int:
	for row_v: Variant in TABLE:
		var row: Array = row_v
		if total >= int(row[0]):
			return int(row[1])
	return AdvancedGunnery.Result.SPLASH


## L'effetto speciale prodotto da un risultato Grave sulla Linea di
## Galleggiamento. `total` sono due dadi in piu', senza modificatori.
static func waterline_severe(total: int) -> String:
	for row_v: Variant in WATERLINE_SEVERE:
		var row: Array = row_v
		if total >= int(row[0]):
			return String(row[1])
	return "Timone Fuori Uso"


## Risolve un attacco con siluri avanzato.
## Ritorna { ok, reason, firer, target, rolled, raw, modifiers, sum, result,
##           label, special, effect }.
static func attack(firer: Ship, target: Ship, rng: DiceRNG) -> Dictionary:
	if not can_attack(firer):
		return {"ok": false, "reason":
			("%s non puo' silurare: servono i siluri, l'attitudine "
			+ "Avvicinamento e la zona Vicina o Ravvicinata") % firer.name}
	if not is_valid_target(target):
		return {"ok": false, "reason":
			"%s non e' un bersaglio valido per i siluri" % target.name}

	var raw := rng.d6x2("siluri %s -> %s" % [firer.name, target.name])
	var mods := modifiers(firer, target)
	var total := raw + modifier_total(firer, target)
	var res := read(total)
	var out := {"ok": true, "reason": "", "firer": firer, "target": target,
		"raw": raw, "modifiers": mods, "sum": total, "result": res,
		"label": AdvancedGunnery.label(res),
		"special": res >= AdvancedGunnery.Result.SEVERE, "effect": ""}
	if res == AdvancedGunnery.Result.SEVERE:
		var w := rng.d6x2("Linea di Galleggiamento")
		out["waterline_roll"] = w
		out["effect"] = waterline_severe(w)
	elif res == AdvancedGunnery.Result.CATASTROPHIC:
		out["effect"] = ("Linea di Galleggiamento, colonna Catastrofica: "
			+ "non ancora trascritta (sta sul player aid avanzato)")
	return out


static func describe(a: Dictionary) -> String:
	if not bool(a.get("ok", false)):
		return String(a.get("reason", ""))
	var parts: Array[String] = []
	for m in a["modifiers"] as Array:
		parts.append("%s %+d" % [m["label"], int(m["value"])])
	var mtxt := (" [" + ", ".join(parts) + "]") if not parts.is_empty() else ""
	var s := "Siluri %s -> %s: 2d6 = %d%s -> %d = %s" % [
		(a["firer"] as Ship).name, (a["target"] as Ship).name,
		int(a["raw"]), mtxt, int(a["sum"]), String(a["label"])]
	if String(a.get("effect", "")) != "":
		s += "  ->  %s" % String(a["effect"])
	return s
