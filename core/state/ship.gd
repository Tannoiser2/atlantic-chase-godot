class_name Ship
extends RefCounted

## Una nave (o Convoglio, o Squadrone DD) dentro una Task Force.
##
## Regole di danno (RB p.51 "Danneggiato" + Charts "Colpo"):
##   - DANNEGGIATO gira la pedina sul lato Danneggiato; se era gia' danneggiata,
##     la nave affonda
##   - i Colpi gia' assegnati RESTANO quando la nave si gira
##   - Convogli e Squadroni DD non si danneggiano: per loro un risultato di
##     Danno vale 2 Colpi
##   - sono distrutti se subiscono quattro Colpi
##
## Le statistiche complete (valore dei cannoni, corazza, ecc.) sono stampate
## sulle pedine e non sono ancora trascritte: vedi STATO.md. Qui c'e' quanto
## serve alle regole della mappa operazionale.

enum Kind { WARSHIP, CONVOY, DD_SQUADRON, SHORE_BATTERY }

const HITS_TO_DESTROY_UNARMORED := 4

var name: String = ""
var nation: String = ""          ## GE / UK / FR / US
var type_code: String = ""       ## BB, BC, CA, CL, CV, PB, AC, AO, DD, ...
var kind: int = Kind.WARSHIP
var speed: int = TimeLapse.Speed.MEDIUM

var damaged: bool = false
var sunk: bool = false
var hits: int = 0

## Solo per i Convogli: un Convoglio non si affonda, si DISPERDE, e da disperso
## vale meno. Cinque tabelle di Vittoria su nove pagano un punto in meno per un
## convoglio disperso che arriva a destinazione, quindi non e' un dettaglio di
## contorno: e' la differenza fra 3 punti e 2.
var dispersed: bool = false

# --- statistiche di Battaglia (stampate sulle pedine) ------------------------
# Numero di Difesa: quando i Colpi accumulati lo raggiungono, la nave si gira
# sul lato Danneggiato. Sul lato Danneggiato vale defense_damaged e, raggiunto
# quello, la nave affonda (RB p.58).
#
# ZERO significa "non ancora trascritto": in quel caso i Colpi si accumulano
# senza girare la pedina, e chi legge il log lo vede scritto. Meglio che
# inventare un valore e falsare ogni battaglia.
var defense: int = 0
var defense_damaged: int = 0

# Valore dei cannoni, distinto per banda di raggio (RB p.56): uno per
# bruciapelo & corto, uno per lungo & estremo. `null` significa "na" sulla
# pedina, cioe' la nave non puo' sparare a quel raggio.
var gun_close: Variant = null
var gun_far: Variant = null

## Valori del LATO DANNEGGIATO. Girando la pedina cambiano tutti e tre i dati:
## cannoni, Difesa e velocita' (la Bismarck e' 4/2 Difesa 2 media da integra,
## 3/1 Difesa 4 lenta da danneggiata).
var gun_close_damaged: Variant = null
var gun_far_damaged: Variant = null
var speed_damaged: int = -1

var has_torpedo: bool = false

## Limite di Colpi per Convogli e Squadroni DD (le istruzioni dello scenario
## possono cambiarlo; il fascicolo Scenari usa 4).
var hit_limit: int = HITS_TO_DESTROY_UNARMORED

# --- stato transitorio, valido solo durante una Battaglia --------------------
var battle_zone: int = 0        ## indice in BattleState.Zone
var smoke: bool = false

## Attitudine, solo con le Regole Avanzate di Battaglia: indice in
## Attitude.Kind. Sulla pedina si indica girandola, perche' la freccia rossa
## stampata punti verso il nemico, via da lui, o parallela.
##
## Con le regole BASE non esiste: e' come se ogni nave fosse in Avvicinamento,
## ed e' il valore di partenza proprio per questo - il modello base resta
## corretto senza toccare niente.
var attitude: int = 1           ## Attitude.Kind.CLOSING

## Effetti Speciali assegnati (Regole Avanzate). Ogni voce e' il codice del
## risultato: una nave con un effetto speciale e' "gravemente danneggiata" e
## perde alcuni benefici, per esempio la colonna Acquisizione.
var special_effects: Array[String] = []


func has_special_effect() -> bool:
	return not special_effects.is_empty()


func _init(p_name: String = "", p_speed: int = TimeLapse.Speed.MEDIUM,
		p_kind: int = Kind.WARSHIP) -> void:
	name = p_name
	speed = p_speed
	kind = p_kind


func can_be_damaged() -> bool:
	return kind == Kind.WARSHIP


## Applica un risultato DANNEGGIATO. Ritorna la descrizione di cosa e' successo.
func apply_damage() -> String:
	if sunk:
		return "%s e' gia' affondata" % name
	if not can_be_damaged():
		# RB p.51: per Convogli e Squadroni DD un Danno vale 2 Colpi
		var b := apply_hits(2)
		return "%s non puo' essere danneggiata: vale 2 Colpi (%s)" % [name, b]
	if damaged:
		sunk = true
		return "%s era gia' danneggiata: AFFONDATA" % name
	damaged = true
	return "%s e' ora Danneggiata%s" % [name,
		" (conserva %d Colpi)" % hits if hits > 0 else ""]


## Applica un COLPO. Ritorna la descrizione.
func apply_hit() -> String:
	return apply_hits(1)


## Applica `n` Colpi seguendo la regola di Battaglia (RB p.58):
## raggiunta la Difesa la nave si gira, i Colpi eccedenti finiscono subito sul
## lato Danneggiato, e raggiunta la Difesa del lato Danneggiato la nave affonda.
func apply_hits(n: int) -> String:
	if sunk:
		return "%s e' gia' affondata" % name
	if n <= 0:
		return "nessun Colpo su %s" % name
	var parts: Array[String] = []

	if not can_be_damaged():
		hits += n
		if hits >= hit_limit:
			sunk = true
			return "%s ha raggiunto il limite di %d Colpi: DISTRUTTA" % [name, hit_limit]
		return "%s ha subito %d Colpi (totale %d di %d)" % [name, n, hits, hit_limit]

	var remaining := n
	while remaining > 0 and not sunk:
		hits += 1
		remaining -= 1
		var threshold := defense_damaged if damaged else defense
		if threshold <= 0:
			continue  # statistiche non trascritte: si accumula e basta
		if hits >= threshold:
			if damaged:
				sunk = true
				parts.append("AFFONDATA")
			else:
				damaged = true
				hits = 0
				parts.append("Danneggiata")
	var txt := "%s ha subito %d Colpi" % [name, n]
	if not parts.is_empty():
		txt += " -> " + ", ".join(parts)
	if not sunk:
		var threshold := defense_damaged if damaged else defense
		if threshold > 0:
			txt += " (%d/%d)" % [hits, threshold]
		else:
			txt += " (totale %d; Difesa non trascritta)" % hits
	return txt


## Velocita' del lato attualmente a faccia in su.
func current_speed() -> int:
	# gli Effetti Speciali battono tutto: una nave che brucia o si allaga e'
	# molto lenta o ferma qualunque cosa dica la pedina
	var forced := SpecialEffects.speed_override(self)
	if forced != -99:
		return forced
	if damaged and speed_damaged >= 0:
		return speed_damaged
	return speed


## Valore dei cannoni per la banda di raggio, sul lato attualmente a faccia in
## su. `null` = "na" sulla pedina: la nave non puo' sparare a quel raggio
## (RB p.56; e' il caso delle portaerei integre, che al posto dei valori
## stampano l'icona dell'aereo).
func gun_value(band: String) -> Variant:
	if damaged:
		return gun_close_damaged if band == "close" else gun_far_damaged
	return gun_close if band == "close" else gun_far


func can_fire(band: String) -> bool:
	return gun_value(band) != null


## Il bersaglio e' abbastanza lento perche' il risultato lo colpisca?
func is_slow_or_slower() -> bool:
	return current_speed() <= TimeLapse.Speed.SLOW


func is_very_slow() -> bool:
	return current_speed() == TimeLapse.Speed.VERY_SLOW


func display() -> String:
	var s := name
	if type_code != "":
		s = "%s %s" % [type_code, name]
	if sunk:
		s += " [affondata]"
	elif damaged:
		s += " [danneggiata]"
	if hits > 0:
		s += " (%d colpi)" % hits
	return s


func to_dict() -> Dictionary:
	return {"name": name, "nation": nation, "type": type_code, "kind": kind,
		"speed": speed, "damaged": damaged, "sunk": sunk, "hits": hits,
		"dispersed": dispersed,
		"defense": defense, "defense_damaged": defense_damaged,
		"gun_close": gun_close, "gun_far": gun_far,
		"gun_close_damaged": gun_close_damaged, "gun_far_damaged": gun_far_damaged,
		"speed_damaged": speed_damaged,
		"has_torpedo": has_torpedo, "hit_limit": hit_limit,
		"attitude": attitude, "special_effects": special_effects.duplicate()}


static func from_dict(d: Dictionary) -> Ship:
	var s := Ship.new(String(d.get("name", "")),
		int(d.get("speed", TimeLapse.Speed.MEDIUM)),
		int(d.get("kind", Kind.WARSHIP)))
	s.nation = String(d.get("nation", ""))
	s.type_code = String(d.get("type", ""))
	s.damaged = bool(d.get("damaged", false))
	s.sunk = bool(d.get("sunk", false))
	s.hits = int(d.get("hits", 0))
	s.dispersed = bool(d.get("dispersed", false))
	s.defense = int(d.get("defense", 0))
	s.defense_damaged = int(d.get("defense_damaged", 0))
	s.gun_close = d.get("gun_close", null)
	s.gun_far = d.get("gun_far", null)
	s.gun_close_damaged = d.get("gun_close_damaged", null)
	s.gun_far_damaged = d.get("gun_far_damaged", null)
	s.speed_damaged = int(d.get("speed_damaged", -1))
	s.has_torpedo = bool(d.get("has_torpedo", false))
	s.attitude = int(d.get("attitude", 1))
	s.special_effects.clear()
	for e_v: Variant in d.get("special_effects", []):
		s.special_effects.append(String(e_v))
	s.hit_limit = int(d.get("hit_limit", HITS_TO_DESTROY_UNARMORED))
	return s


## Le voci di scenario possono essere una semplice stringa (solo il nome) o un
## oggetto completo: accettiamo entrambe, cosi' gli scenari importati dai .vsav
## restano validi anche prima che le statistiche siano trascritte.
static func from_variant(v: Variant) -> Ship:
	if typeof(v) == TYPE_DICTIONARY:
		return Ship.from_dict(v)
	return Ship.new(String(v))
