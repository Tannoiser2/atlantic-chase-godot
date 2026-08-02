class_name ResultTables
extends RefCounted

## Tabelle dei Risultati Speciali (player aid delle Regole Avanzate).
##
## Chiudono la catena del Fuoco avanzato. Un Risultato Grave o Catastrofico non
## e' ancora un effetto: e' un RIMANDO. Si tirano altri due dadi - senza
## modificatori - e si guarda in quale parte della nave e' entrato il colpo:
##
##   S.R./C.R.  ->  Cintura, Sovrastruttura, Linea di Galleggiamento,
##                  Rapporto Esagerato, Rapporto Falso
##   e ognuna di quelle  ->  l'effetto vero
##
## Due tiri per un colpo sembrano tanti finche' non si guarda cosa producono:
## la colonna dipende dal RAGGIO, e il raggio cambia tutto. A raggio Estremo un
## Catastrofico e' spesso solo un "Rapporto Esagerato" - gli avvistatori si
## erano sbagliati - mentre a Bruciapelo lo stesso risultato entra sotto la
## linea di galleggiamento. E' la differenza fra sparare da lontano e sparare
## addosso, resa con due tabelle invece che con un modificatore.

const BELT := "Belt"
const SUPERSTRUCTURE := "Superstructure"
const WATERLINE := "Waterline"
const EXAGGERATED := "Rapporto Esagerato"
const FALSE_REPORT := "Rapporto Falso"

## Le colonne dipendono dal raggio, raggruppato in tre fasce.
enum Band { EXTREME_LONG, SHORT, POINT_BLANK }

## GRAVE. Colonne: Estremo/Lungo, Corto/Bruciapelo.
const SEVERE := {
	Band.EXTREME_LONG: [
		[10, BELT], [6, SUPERSTRUCTURE], [3, SUPERSTRUCTURE], [2, FALSE_REPORT]],
	Band.SHORT: [
		[10, WATERLINE], [6, BELT], [3, SUPERSTRUCTURE], [2, FALSE_REPORT]],
}

## CATASTROFICO. Colonne: Estremo/Lungo, Corto, Bruciapelo.
const CATASTROPHIC := {
	Band.EXTREME_LONG: [
		[12, BELT], [9, SUPERSTRUCTURE], [6, SUPERSTRUCTURE],
		[3, SUPERSTRUCTURE], [2, EXAGGERATED]],
	Band.SHORT: [
		[12, WATERLINE], [9, WATERLINE], [6, BELT], [3, BELT], [2, SUPERSTRUCTURE]],
	Band.POINT_BLANK: [
		[12, WATERLINE], [9, WATERLINE], [6, WATERLINE], [3, BELT],
		[2, SUPERSTRUCTURE]],
}

## Cintura: dove la corazzatura e' piu' spessa. Colpirla di rado affonda, ma
## spesso rompe qualcosa di grosso.
const BELT_TABLE := {
	"severe": [[10, SpecialEffects.FIRE_STOPPED], [7, SpecialEffects.FIRE_SLOW],
		[5, SpecialEffects.TURRETS], [2, SpecialEffects.RUDDER]],
	"catastrophic": [[10, SpecialEffects.TURRETS],
		[7, SpecialEffects.FIRE_STOPPED], [5, SpecialEffects.MAGAZINE],
		[2, SpecialEffects.FLOOD_SLOW]],
}

## Sovrastruttura: tutto quello che sta sopra lo scafo. Non affonda una nave,
## la rende inutile - ed e' l'unica tabella che puo' dare "Affondata".
const SUPERSTRUCTURE_TABLE := {
	"severe": [[12, SpecialEffects.FIRE_STOPPED],
		[10, SpecialEffects.FIRE_SLOW], [8, SpecialEffects.COMMUNICATIONS],
		[7, SpecialEffects.BRIDGE], [2, SpecialEffects.BATTERIES]],
	"catastrophic": [[12, "Affondata"], [10, SpecialEffects.FIRE_STOPPED],
		[8, SpecialEffects.TURRETS], [7, SpecialEffects.MAGAZINE],
		[2, SpecialEffects.FIRE_SLOW]],
}

## Linea di Galleggiamento: l'acqua entra. E' la tabella dei siluri, e la
## peggiore per una nave che vuole andarsene.
const WATERLINE_TABLE := {
	"severe": [[8, SpecialEffects.FLOOD_SLOW],
		[6, SpecialEffects.FLOOD_STOPPED], [2, SpecialEffects.RUDDER]],
	"catastrophic": [[8, SpecialEffects.FLOOD_STOPPED],
		[6, SpecialEffects.FLOOD_SLOW], [2, SpecialEffects.FIRE_SLOW]],
}


## La fascia di colonna per un raggio del Fuoco.
static func band_for_range(range_index: int) -> int:
	match range_index:
		Gunnery.FireRange.POINT_BLANK:
			return Band.POINT_BLANK
		Gunnery.FireRange.SHORT:
			return Band.SHORT
	return Band.EXTREME_LONG


static func _read(rows: Array, total: int) -> String:
	for r_v: Variant in rows:
		var r: Array = r_v
		if total >= int(r[0]):
			return String(r[1])
	return String((rows[rows.size() - 1] as Array)[1])


## Primo tiro: in che parte della nave e' entrato il colpo.
## `catastrophic` sceglie la tabella; `range_index` la colonna.
static func hit_location(catastrophic: bool, range_index: int,
		total: int) -> String:
	var band := band_for_range(range_index)
	if catastrophic:
		return _read(CATASTROPHIC.get(band, CATASTROPHIC[Band.SHORT]), total)
	# la tabella Grave non distingue Corto da Bruciapelo
	var b := Band.EXTREME_LONG if band == Band.EXTREME_LONG else Band.SHORT
	return _read(SEVERE[b], total)


## Secondo tiro: l'effetto vero.
##
## `attacker_gv` serve solo per la Sovrastruttura: con valore dei cannoni zero
## o meno il colpo e' solo un Colpo, senza effetto. E' il caso che il fascicolo
## illustra nell'esempio - il Bismarck che divide il fuoco e assegna 0 al
## secondo bersaglio lo colpisce, ma non gli rompe niente.
static func effect_for(location: String, catastrophic: bool, total: int,
		attacker_gv: int = 1) -> Dictionary:
	var col := "catastrophic" if catastrophic else "severe"
	match location:
		FALSE_REPORT:
			return {"effect": "", "hit": false,
				"note": "Rapporto Falso: gli avvistatori si erano sbagliati."}
		EXAGGERATED:
			return {"effect": "", "hit": true,
				"note": "Rapporto Esagerato: il danno non era grave, "
					+ "vale un Colpo."}
		BELT:
			return {"effect": _read(BELT_TABLE[col], total), "hit": false,
				"note": "Cintura"}
		WATERLINE:
			return {"effect": _read(WATERLINE_TABLE[col], total), "hit": false,
				"note": "Linea di Galleggiamento"}
		SUPERSTRUCTURE:
			if attacker_gv <= 0:
				return {"effect": "", "hit": true,
					"note": "Sovrastruttura con valore dei cannoni 0: "
						+ "vale un Colpo e basta."}
			return {"effect": _read(SUPERSTRUCTURE_TABLE[col], total),
				"hit": false, "note": "Sovrastruttura"}
	return {"effect": "", "hit": true, "note": location}


## Catena completa: dal Risultato Speciale all'effetto, tirando i dadi.
## Ritorna { location, effect, hit, note, rolls }.
static func resolve(catastrophic: bool, range_index: int, attacker_gv: int,
		rng: DiceRNG) -> Dictionary:
	var first := rng.d6x2("dove ha colpito")
	var loc := hit_location(catastrophic, range_index, first)
	var rolls: Array[int] = [first]
	if loc == FALSE_REPORT or loc == EXAGGERATED:
		var q := effect_for(loc, catastrophic, 0, attacker_gv)
		q["location"] = loc
		q["rolls"] = rolls
		return q
	if loc == SUPERSTRUCTURE and attacker_gv <= 0:
		var q2 := effect_for(loc, catastrophic, 0, attacker_gv)
		q2["location"] = loc
		q2["rolls"] = rolls
		return q2
	var second := rng.d6x2("tabella %s" % loc)
	rolls.append(second)
	var out := effect_for(loc, catastrophic, second, attacker_gv)
	out["location"] = loc
	out["rolls"] = rolls
	return out
