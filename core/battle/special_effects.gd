class_name SpecialEffects
extends RefCounted

## Effetti Speciali (Regole Avanzate, pp.7-8).
##
## Un Risultato Grave o Catastrofico non produce Colpi: produce un EFFETTO, che
## resta attaccato alla nave finche' non viene riparato o la nave affonda. E'
## quello che rende le regole avanzate diverse dal contare danni: una nave puo'
## restare a galla e integra sulla carta ed essere comunque fuori combattimento
## perche' non ha piu' il timone, o la plancia, o le comunicazioni.
##
## LA REGOLA CHE TORNA OVUNQUE: un effetto che si ripete non si accumula, si
## AGGRAVA o si converte in un Colpo. Prendere due volte lo stesso incendio non
## fa "doppio incendio": la prima volta rallenta, la seconda ferma, la terza e'
## un Colpo. Nessun effetto compare due volte sulla stessa nave.

const BATTERIES := "Batterie"
const BRIDGE := "Plancia"
const COMMUNICATIONS := "Comunicazioni"
const FIRE_SLOW := "Incendio (molto lenta)"
const FIRE_STOPPED := "Incendio (ferma)"
const FLOOD_SLOW := "Allagamento (molto lenta)"
const FLOOD_STOPPED := "Allagamento (ferma)"
const MAGAZINE := "Santabarbara"
const RUDDER := "Timone Fuori Uso"
const TURRETS := "Torrette"

## Coppie "grave -> lieve": prendere il grave quando c'e' gia' il lieve lo
## sostituisce; prendere di nuovo il grave e' un Colpo.
const ESCALATION := {
	FIRE_STOPPED: FIRE_SLOW,
	FLOOD_STOPPED: FLOOD_SLOW,
}

## Effetti che impediscono del tutto il Fuoco di Cannoni.
const NO_GUNNERY := [FIRE_STOPPED, FLOOD_STOPPED]

## Effetti che fermano la nave.
const STOPS_SHIP := [FIRE_STOPPED, FLOOD_STOPPED]

## Effetti che rallentano la nave a "molto lenta".
const SLOWS_SHIP := [FIRE_SLOW, FLOOD_SLOW]

## Le Torrette non si riparano: sono l'unico effetto permanente.
const NOT_REPAIRABLE := [TURRETS]


static func has(ship: Ship, effect: String) -> bool:
	return ship.special_effects.has(effect)


static func repairable(effect: String) -> bool:
	return not NOT_REPAIRABLE.has(effect)


## L'effetto grave corrispondente a questo lieve, o "" se non ne ha uno.
static func heavier_of(effect: String) -> String:
	for k_v: Variant in ESCALATION.keys():
		if String(ESCALATION[k_v]) == effect:
			return String(k_v)
	return ""


## Assegna un effetto a una nave, applicando le regole di aggravamento.
##
## Ritorna { applied, hit, removed, log }: `hit` true significa che l'effetto
## non si e' applicato e la nave prende invece un Colpo.
static func apply(ship: Ship, effect: String) -> Dictionary:
	var out := {"applied": false, "hit": false, "removed": "", "log": ""}

	# la Santabarbara non e' un marcatore: danneggia subito, e se la nave era
	# gia' danneggiata la affonda
	if effect == MAGAZINE:
		out["applied"] = true
		out["log"] = ship.apply_damage()
		return out

	# gia' presente: non si accumula, vale un Colpo
	if has(ship, effect):
		out["hit"] = true
		out["log"] = "%s ha gia' %s: non si accumula, vale un Colpo. %s" \
			% [ship.name, effect, ship.apply_hits(1)]
		return out

	# l'effetto GRAVE sostituisce il suo corrispondente lieve
	if ESCALATION.has(effect):
		var lighter := String(ESCALATION[effect])
		if has(ship, lighter):
			ship.special_effects.erase(lighter)
			out["removed"] = lighter
		ship.special_effects.append(effect)
		out["applied"] = true
		out["log"] = "%s: %s%s" % [ship.name, effect,
			"  (sostituisce %s)" % lighter if out["removed"] != "" else ""]
		return out

	# l'effetto LIEVE non si applica se c'e' gia' il suo grave
	var heavier := heavier_of(effect)
	if heavier != "" and has(ship, heavier):
		out["hit"] = true
		out["log"] = ("%s ha gia' %s, che e' peggio: vale un Colpo. "
			% [ship.name, heavier] + ship.apply_hits(1))
		return out

	ship.special_effects.append(effect)
	out["applied"] = true
	out["log"] = "%s: %s" % [ship.name, effect]
	return out


## Modificatore al Fuoco di Cannoni di questa nave, al raggio indicato.
##
## Le Torrette valgono -2 a QUALUNQUE raggio; le Batterie -2 solo a Corto e
## Bruciapelo. Insieme fanno -4 a quei due raggi, e il fascicolo lo dice
## esplicitamente: si sommano.
static func gunnery_modifier(ship: Ship, range_index: int) -> int:
	var m := 0
	if has(ship, TURRETS):
		m -= 2
	if has(ship, BATTERIES) and Gunnery.band_for(range_index) == "close":
		m -= 2
	return m


## La nave puo' sparare?
static func can_fire(ship: Ship) -> bool:
	for e in NO_GUNNERY:
		if has(ship, e):
			return false
	return true


## Velocita' imposta dagli effetti, o -99 se nessuno la tocca.
## Ferma batte molto lenta: se una nave ha entrambi, vince il peggiore.
static func speed_override(ship: Ship) -> int:
	for e in STOPS_SHIP:
		if has(ship, e):
			return TimeLapse.Speed.STOPPED
	for e in SLOWS_SHIP:
		if has(ship, e):
			return TimeLapse.Speed.VERY_SLOW
	return -99


## Chi controlla la nave in questo passo? Con il Timone Fuori Uso si tira un
## dado a ogni Manovra e a ogni Attitudine: DISPARI e la nave la muove
## l'avversario, PARI resta al proprietario.
##
## E' l'effetto piu' crudele del fascicolo: la nave non e' danneggiata, e'
## semplicemente non piu' tua.
static func rudder_check(ship: Ship, rng: DiceRNG) -> Dictionary:
	if not has(ship, RUDDER):
		return {"applies": false, "opponent_controls": false, "roll": 0}
	var d := rng.d6("Timone Fuori Uso di %s" % ship.name)
	return {"applies": true, "opponent_controls": d % 2 == 1, "roll": d}


## Gli effetti che scattano da soli nella fase dell'Attitudine.
## Comunicazioni: la nave subisce un Colpo a ogni fase dell'Attitudine.
static func attitude_step(ship: Ship) -> Array[String]:
	var out: Array[String] = []
	if has(ship, COMMUNICATIONS):
		out.append("%s (Comunicazioni): %s" % [ship.name, ship.apply_hits(1)])
	return out


## La Plancia costringe a scegliere, ogni Round, fra non sparare e restare
## fermi. La scelta la fa il proprietario e va fatta subito.
static func bridge_choice_needed(ship: Ship) -> bool:
	return has(ship, BRIDGE)


## Il Controllo Danni puo' riparare questo effetto?
## Con la Plancia addosso, il Controllo Danni DEVE puntare a quella e a
## nient'altro: e' la regola che impedisce di ignorare il danno peggiore.
static func repair_targets(ship: Ship) -> Array[String]:
	if has(ship, BRIDGE):
		return [BRIDGE] as Array[String]
	var out: Array[String] = []
	for e in ship.special_effects:
		if repairable(e):
			out.append(e)
	return out
