class_name Torpedo
extends RefCounted

## Attacco con Siluri (RB p.59 + tabella sulla mappa).
##
## Solo le navi con capacita' silurante che si trovano nella zona RAVVICINATA
## possono attaccare, e solo bersagli in zona Ravvicinata o Vicina.
##
##   2d6, 10 o meno = nessun effetto, 11 o piu' = due Colpi
##
## I modificatori di velocita' del bersaglio valgono anche qui (+2 molto lento,
## +1 lento), il Fumo no: "Il Fumo non modifica gli attacchi con Siluri".

const Z := BattleState.Zone
const TARGET_ZONES := [Z.CLOSE, Z.NEAR]
const THRESHOLD := 11
const HITS_ON_SUCCESS := 2


static func can_attack(firer: Ship) -> bool:
	return firer.has_torpedo and firer.battle_zone == Z.CLOSE and not firer.sunk


static func is_valid_target(target: Ship) -> bool:
	return not target.sunk and TARGET_ZONES.has(target.battle_zone)


static func legality_error(firer: Ship, target: Ship) -> String:
	if not firer.has_torpedo:
		return "%s non ha capacita' silurante" % firer.name
	if firer.battle_zone != Z.CLOSE:
		return "%s deve trovarsi in zona Ravvicinata per silurare" % firer.name
	if not TARGET_ZONES.has(target.battle_zone):
		return "%s e' in zona Lontana: fuori portata dei siluri" % target.name
	return ""


## Modificatori: solo la velocita' del bersaglio (il Fumo non conta).
static func modifiers(target: Ship) -> Dictionary:
	var out: Array[Dictionary] = []
	if target.is_very_slow():
		out.append({"label": "bersaglio molto lento", "value": 2})
	elif target.is_slow_or_slower():
		out.append({"label": "bersaglio lento", "value": 1})
	var total := 0
	for m in out:
		total += int(m["value"])
	return {"list": out, "total": total}


## Risolve un attacco con siluri. Come per i cannoni, NON applica i Colpi.
static func attack(firer: Ship, target: Ship, rng: DiceRNG) -> Dictionary:
	var err := legality_error(firer, target)
	if err != "":
		return {"ok": false, "reason": err, "hits": 0}
	var raw := rng.d6x2("siluri %s -> %s" % [firer.name, target.name])
	var mods := modifiers(target)
	var total: int = raw + int(mods["total"])
	var hits := HITS_ON_SUCCESS if total >= THRESHOLD else 0
	return {
		"ok": true, "firer": firer, "target": target,
		"raw": raw, "modifiers": mods["list"], "modifier_total": mods["total"],
		"sum": total, "hits": hits,
		"label": "due Colpi" if hits > 0 else "nessun effetto",
	}


static func describe(a: Dictionary) -> String:
	if not a["ok"]:
		return String(a["reason"])
	var parts: Array[String] = []
	for m in a["modifiers"] as Array:
		parts.append("%s %+d" % [m["label"], int(m["value"])])
	var mtxt := (" [" + ", ".join(parts) + "]") if not parts.is_empty() else ""
	return "siluri %s -> %s: 2d6 = %d%s -> %d (serve %d) = %s" % [
		(a["firer"] as Ship).name, (a["target"] as Ship).name,
		a["raw"], mtxt, a["sum"], THRESHOLD, a["label"]]
