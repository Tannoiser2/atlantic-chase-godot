class_name Lingering
extends RefCounted

## Effetti Duraturi e Disingaggio (Regole Avanzate, pp.11 e 14).
##
## Sono le due fasi in cui gli effetti speciali possono migliorare o peggiorare:
## una a ogni Round di Battaglia, l'altra all'uscita.
##
## ATTENZIONE, LIMITE NOTO. Le due TABELLE - quale somma dia quale risultato,
## effetto per effetto - stanno su una carta player aid che NON e' dentro
## `AC_Adv_Battle_Rules_May_4_2021.pdf`. Qui ci sono le procedure e il
## significato di ogni risultato, che il fascicolo scrive per esteso, ma la
## griglia va tirata a mano. `roll()` prepara il tiro giusto e dice cosa
## cercare; `apply()` esegue il risultato una volta che il giocatore lo ha
## letto. E' la divisione onesta: il motore fa tutto quello che sa fare, e
## chiede solo il pezzo che non ha.

## I risultati della Tabella degli Effetti Duraturi, con il loro significato.
const FIRE_STOPPED := "Incendio (ferma)"
const FIRE_SLOW := "Incendio (molto lenta)"
const FLOOD_STOPPED := "Allagamento (ferma)"
const FLOOD_SLOW := "Allagamento (molto lenta)"
const HIT_NO_CHANGE := "Colpo e nessun cambiamento"
const NO_CHANGE := "nessun cambiamento"
const REPAIRED := "Riparato"
const SUNK := "Affondata"

## I risultati del Disingaggio.
const DIS_NO_CHANGE := "-"
const DIS_OIL := "Scia di nafta"
const DIS_REPAIR := "Riparato"
const DIS_SCUTTLE := "Autoaffondamento"

## Le Torrette e la Santabarbara non passano dagli Effetti Duraturi: le
## Torrette si verificano solo al Disingaggio, e la Santabarbara non lascia
## un marcatore da riparare.
const EXEMPT_FROM_LINGERING := [SpecialEffects.TURRETS]


## Gli effetti di questa nave che vanno verificati negli Effetti Duraturi.
## Uno per uno, con un tiro ciascuno: due effetti fanno due tiri, non uno.
static func lingering_checks(ship: Ship) -> Array[String]:
	var out: Array[String] = []
	for e in ship.special_effects:
		if not EXEMPT_FROM_LINGERING.has(e):
			out.append(e)
	return out


## Il tiro degli Effetti Duraturi.
##
## Con il Controllo Danni si tirano TRE dadi e si tengono i due piu' ALTI - ed
## e' il solito baratto del gioco: in cambio, quella nave non spara nel Round
## successivo. Riparare costa un turno di fuoco.
static func roll(rng: DiceRNG, damage_control: bool,
		effect: String) -> Dictionary:
	var rolled: Array[int] = []
	var n := 3 if damage_control else 2
	for i in n:
		rolled.append(rng.d6("Effetti Duraturi (%s)" % effect))
	var kept := rolled.duplicate()
	kept.sort()
	if damage_control:
		kept = [kept[1], kept[2]]      # i due piu' alti
	return {"rolled": rolled, "kept": kept, "sum": kept[0] + kept[1],
		"effect": effect, "damage_control": damage_control}


## Esegue un risultato degli Effetti Duraturi, una volta letto sulla tabella.
## Ritorna la riga da mettere nel registro.
static func apply(ship: Ship, effect: String, result: String) -> String:
	match result:
		REPAIRED:
			ship.special_effects.erase(effect)
			return "%s: %s riparato." % [ship.name, effect]
		SUNK:
			ship.sunk = true
			return "%s: AFFONDATA." % ship.name
		HIT_NO_CHANGE:
			return "%s: l'effetto resta. %s" % [ship.name, ship.apply_hits(1)]
		NO_CHANGE:
			return "%s: %s resta." % [ship.name, effect]
		FIRE_STOPPED, FIRE_SLOW, FLOOD_STOPPED, FLOOD_SLOW:
			ship.special_effects.erase(effect)
			if not ship.special_effects.has(result):
				ship.special_effects.append(result)
			return "%s: %s diventa %s." % [ship.name, effect, result]
	return "%s: risultato non riconosciuto (%s)" % [ship.name, result]


## Il Controllo Danni impedisce il Fuoco nel Round successivo.
## Va ricordato sulla nave, se no il costo non si paga.
static func damage_control_blocks_gunnery() -> bool:
	return true


# ------------------------------------------------------------ disingaggio --

## Gli effetti da verificare all'uscita. Qui le Torrette CI SONO: e' l'unica
## occasione in cui si possono togliere.
static func disengagement_checks(ship: Ship) -> Array[String]:
	return ship.special_effects.duplicate()


## Il tiro del Disingaggio.
##
## `german_vulnerability` e' la regola opzionale "vulnerabilita' tedesca": il
## tedesco tira TRE dadi e tiene i due piu' BASSI, che e' l'esatto contrario
## del Controllo Danni. Vale solo negli scenari operativi e nella Campagna, non
## nei mini-scenari, e non si applica se la Battaglia e' avvenuta entro due
## esagoni da un porto o una base aerea amica, o in un esagono con un U-Boat o
## un'altra Stazione tedesca.
static func disengagement_roll(rng: DiceRNG,
		german_vulnerability: bool = false) -> Dictionary:
	var rolled: Array[int] = []
	var n := 3 if german_vulnerability else 2
	for i in n:
		rolled.append(rng.d6("Verifica del Disingaggio"))
	var kept := rolled.duplicate()
	kept.sort()
	if german_vulnerability:
		kept = [kept[0], kept[1]]      # i due piu' BASSI
	return {"rolled": rolled, "kept": kept, "sum": kept[0] + kept[1],
		"german_vulnerability": german_vulnerability}


## Esegue un risultato del Disingaggio.
static func apply_disengagement(ship: Ship, effect: String,
		result: String) -> String:
	match result:
		DIS_REPAIR:
			ship.special_effects.erase(effect)
			return "%s: %s riparato all'uscita." % [ship.name, effect]
		DIS_SCUTTLE:
			ship.sunk = true
			return ("%s: autoaffondamento. Negli scenari conta come affondata "
				+ "durante la partita.") % ship.name
		DIS_OIL:
			ship.special_effects.erase(effect)
			if not ship.special_effects.has(DIS_OIL):
				ship.special_effects.append(DIS_OIL)
			return ("%s: %s rimosso, ma resta una scia di nafta. Non le fa "
				+ "niente, pero' la sua Task Force non potra' piu' prendere "
				+ "un segnalino Manovre Evasive.") % [ship.name, effect]
		DIS_NO_CHANGE:
			return "%s: %s resta." % [ship.name, effect]
	return "%s: risultato non riconosciuto (%s)" % [ship.name, result]


## Niente Radar (dalla Verifica Snafu): -2 al Fuoco a raggio Estremo e -1 a
## Lungo. E' l'unica delle penalita' avanzate di cui il fascicolo da' la
## tabella per esteso, quindi qui e' automatica: 10-12 la toglie, 9 o meno la
## lascia fino al prossimo Disingaggio.
const NO_RADAR := "Niente Radar"


static func no_radar_modifier(ship: Ship, range_index: int) -> int:
	if not ship.special_effects.has(NO_RADAR):
		return 0
	match range_index:
		Gunnery.FireRange.EXTREME:
			return -2
		Gunnery.FireRange.LONG:
			return -1
	return 0


static func no_radar_check(ship: Ship, rng: DiceRNG) -> Dictionary:
	if not ship.special_effects.has(NO_RADAR):
		return {"applies": false, "removed": false, "sum": 0}
	var s := rng.d6x2("Niente Radar di %s" % ship.name)
	var removed := s >= 10
	if removed:
		ship.special_effects.erase(NO_RADAR)
	return {"applies": true, "removed": removed, "sum": s}
