class_name Gunnery
extends RefCounted

## Fuoco di Cannoni (RB pp.56-58).
##
## Il raggio dipende dalla coppia di zone, e il raggio decide quanti dadi si
## tirano e quali si tengono:
##
##   Lontana <-> Lontana      ESTREMO      3 dadi, si tengono i due MINORI
##   Lontana <-> Vicina       LUNGO        2 dadi
##   Lontana <-> Ravvicinata  LUNGO        2 dadi
##   Vicina  <-> Vicina       CORTO        2 dadi
##   Vicina  <-> Ravvicinata  BRUCIAPELO   3 dadi, si tengono i due MAGGIORI
##   Ravvic. <-> Ravvicinata  BRUCIAPELO   3 dadi, si tengono i due MAGGIORI
##
## Somma modificata: 8 o meno Splash, 9-12 un Colpo, 13+ due Colpi.

enum FireRange { EXTREME, LONG, SHORT, POINT_BLANK }

const RANGE_LABELS := ["Estremo", "Lungo", "Corto", "Bruciapelo"]

## Banda del valore dei cannoni da usare per ciascun raggio (RB p.56):
## le pedine riportano un valore per bruciapelo & corto e uno per lungo & estremo.
const RANGE_BAND := ["far", "far", "close", "close"]

const Z := BattleState.Zone


## Raggio fra due zone. L'ordine non conta.
static func range_between(za: int, zb: int) -> int:
	var lo: int = mini(za, zb)
	var hi: int = maxi(za, zb)
	if lo == Z.FAR and hi == Z.FAR:
		return FireRange.EXTREME
	if lo == Z.FAR:                      # FAR-NEAR oppure FAR-CLOSE
		return FireRange.LONG
	if lo == Z.NEAR and hi == Z.NEAR:
		return FireRange.SHORT
	return FireRange.POINT_BLANK             # NEAR-CLOSE oppure CLOSE-CLOSE


static func dice_count(r: int) -> int:
	return 3 if (r == FireRange.EXTREME or r == FireRange.POINT_BLANK) else 2


static func band_for(r: int) -> String:
	return RANGE_BAND[r]


## Tira i dadi del raggio e restituisce la somma dei due che contano.
## A raggio Estremo si tengono i due minori, a Bruciapelo i due maggiori.
static func roll_for_range(r: int, rng: DiceRNG, reason: String = "") -> Dictionary:
	var n := dice_count(r)
	var rolled: Array[int] = []
	for i in n:
		rolled.append(rng.d6("%s (%s, dado %d)" % [reason, RANGE_LABELS[r], i + 1]))
	var sorted_dice := rolled.duplicate()
	sorted_dice.sort()
	var kept: Array[int] = []
	if n == 2:
		kept = rolled.duplicate()
	elif r == FireRange.EXTREME:
		kept = [sorted_dice[0], sorted_dice[1]]
	else:
		kept = [sorted_dice[1], sorted_dice[2]]
	var total := 0
	for k in kept:
		total += k
	return {"rolled": rolled, "kept": kept, "sum": total}


## Modificatori comuni a Cannoni e Siluri (RB p.57).
## `smoke_target` = il bersaglio e' oscurato dal Fumo,
## `smoke_firer`  = chi spara e' oscurato dal Fumo. Entrambi -> -2.
static func modifiers(target: Ship, gun_value: int,
		smoke_target: bool, smoke_firer: bool) -> Dictionary:
	var out: Array[Dictionary] = []
	if target.is_very_slow():
		out.append({"label": "bersaglio molto lento", "value": 2})
	elif target.is_slow_or_slower():
		out.append({"label": "bersaglio lento", "value": 1})
	var smoke := 0
	if smoke_target:
		smoke -= 1
	if smoke_firer:
		smoke -= 1
	if smoke != 0:
		out.append({"label": "fumo", "value": smoke})
	if gun_value != 0:
		out.append({"label": "valore dei cannoni", "value": gun_value})
	var total := 0
	for m in out:
		total += int(m["value"])
	return {"list": out, "total": total}


## Risultato dalla somma modificata (RB p.57).
static func hits_for(total: int) -> int:
	if total <= 8:
		return 0
	if total <= 12:
		return 1
	return 2


static func result_label(hits: int) -> String:
	match hits:
		0: return "Splash"
		1: return "un Colpo"
		_: return "due Colpi"


## Risolve un attacco. NON applica i Colpi: la regola vuole che gli effetti si
## applichino dopo che tutte le navi hanno sparato (RB p.57), quindi il
## chiamante raccoglie i risultati e li applica in blocco.
## `advanced` accende la Tabella del Fuoco delle Regole Avanzate: due colonne
## invece di una, e due risultati in piu' (Grave e Catastrofico). Spento, tutto
## si comporta esattamente come prima - le regole base restano corrette e non
## dipendono da niente delle avanzate.
##
## `targets` serve solo in avanzato: chi divide il fuoco su due bersagli
## rinuncia alla colonna Acquisizione.
static func attack(firer: Ship, target: Ship, rng: DiceRNG,
		smoke_target: bool = false, smoke_firer: bool = false,
		advanced: bool = false, targets: int = 1) -> Dictionary:
	var r := range_between(firer.battle_zone, target.battle_zone)
	var band := band_for(r)
	if not firer.can_fire(band):
		return {"ok": false, "reason": "%s non puo' sparare a raggio %s ('na' sulla pedina)"
			% [firer.name, RANGE_LABELS[r]], "hits": 0, "range": r}

	var gv := int(firer.gun_value(band))
	var roll := roll_for_range(r, rng, "cannoni %s -> %s" % [firer.name, target.name])
	var mods := modifiers(target, gv, smoke_target, smoke_firer)
	var total: int = int(roll["sum"]) + int(mods["total"])
	var hits := hits_for(total)
	var out := {
		"ok": true, "firer": firer, "target": target,
		"range": r, "range_label": RANGE_LABELS[r], "band": band,
		"rolled": roll["rolled"], "kept": roll["kept"], "raw": roll["sum"],
		"modifiers": mods["list"], "modifier_total": mods["total"],
		"sum": total, "hits": hits, "label": result_label(hits),
		"advanced": advanced,
	}
	if advanced:
		# In avanzato il risultato non e' piu' "quanti Colpi" ma una casella
		# della tabella, e le due cose non coincidono: Grave e Catastrofico
		# non sono "tre Colpi", sono un tiro in piu' su un'altra tabella.
		var res := AdvancedGunnery.resolve(firer, total, targets)
		out["result"] = res
		out["label"] = AdvancedGunnery.label(res)
		out["hits"] = 1 if res == AdvancedGunnery.Result.HIT else 0
		out["special"] = res >= AdvancedGunnery.Result.SEVERE
	return out


static func describe(a: Dictionary) -> String:
	if not a["ok"]:
		return String(a["reason"])
	var parts: Array[String] = []
	for m in a["modifiers"] as Array:
		parts.append("%s %+d" % [m["label"], int(m["value"])])
	var mtxt := (" [" + ", ".join(parts) + "]") if not parts.is_empty() else ""
	return "%s -> %s, raggio %s: dadi %s tenuti %s = %d%s -> %d = %s" % [
		(a["firer"] as Ship).name, (a["target"] as Ship).name, a["range_label"],
		str(a["rolled"]), str(a["kept"]), a["raw"], mtxt, a["sum"], a["label"]]
