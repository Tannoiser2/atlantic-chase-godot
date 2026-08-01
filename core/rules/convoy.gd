class_name Convoy
extends RefCounted

## Le quattro regole speciali dei Convogli (RB p.11).
##
## Un Convoglio non e' una nave: e' molte navi in una pedina sola, e il gioco lo
## tratta diversamente in quattro modi.
##
##   1. CARICO PREZIOSO   non puo' essere Danneggiato, e in gran parte degli
##                        scenari nemmeno distrutto: ogni Colpo si converte in
##                        Punti Vittoria per chi attacca.
##   2. NIENTE FUMO       non puo' produrre Fumo, ma ne beneficia.
##   3. DISPERSIONE       se lo scenario la consente, il proprietario puo'
##                        disperderlo quando ha l'Iniziativa. E' una scelta
##                        senza ritorno.
##   4. AZIONI LIMITATE   una Task Force con un Convoglio non puo' dichiarare
##                        Attacco Aereo, Ingaggiare o Ricerca Navale.
##
## La terza e' la piu' interessante, perche' e' l'unica decisione vera: un
## convoglio disperso arriva a destinazione valendo un punto in meno, ma in
## Battaglia incassa UN SOLO Colpo per attacco invece di tutti. Si sceglie fra
## perdere punti e perdere navi.

## Azioni che una Task Force con un Convoglio non puo' dichiarare (RB p.11).
## Puo' pero' essere Coordinante in queste stesse azioni, e se ha una portaerei
## integra puo' dare Supporto Aereo. E ovviamente puo' esserne il bersaglio.
const FORBIDDEN_ACTIONS := ["AIR_STRIKE", "ENGAGE", "NAVAL_SEARCH"]


static func is_convoy(ship: Ship) -> bool:
	return ship != null and ship.kind == Ship.Kind.CONVOY


static func has_convoy(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s in tf.ships:
		if is_convoy(s) and not s.sunk:
			return true
	return false


static func convoys_in(tf: TaskForce) -> Array[Ship]:
	var out: Array[Ship] = []
	if tf == null:
		return out
	for s in tf.ships:
		if is_convoy(s) and not s.sunk:
			out.append(s)
	return out


## Perche' questa Task Force non puo' dichiarare questa azione.
## Stringa vuota = puo'.
static func action_refusal(tf: TaskForce, action_key: String) -> String:
	if not FORBIDDEN_ACTIONS.has(action_key):
		return ""
	if not has_convoy(tf):
		return ""
	return ("una Task Force con un Convoglio non puo' dichiarare questa "
		+ "azione (RB p.11). Puo' pero' essere Coordinante, e con una "
		+ "portaerei integra puo' dare Supporto Aereo")


# ------------------------------------------------------------------ dispersione --

## Perche' questo Convoglio non puo' disperdersi. Stringa vuota = puo'.
##
## `allowed` viene dalle istruzioni dello scenario: la dispersione non e' un
## diritto, e' un permesso. In Op2 i convogli "non possono essere distrutti ma
## possono disperdersi"; in Op6 il testo dice il contrario.
static func disperse_refusal(ship: Ship, allowed: bool) -> String:
	if not is_convoy(ship):
		return "solo un Convoglio puo' disperdersi"
	if ship.sunk:
		return "questo Convoglio non e' piu' in gioco"
	if ship.dispersed:
		return "e' gia' disperso, e non puo' tornare indietro"
	# i convogli tedeschi hanno una petroliera sul retro, non il lato
	# "disperso": fisicamente non hanno dove girarsi
	if ship.nation == "GE":
		return "i Convogli tedeschi non possono essere dispersi (RB p.6)"
	if not allowed:
		return "le istruzioni di questo scenario non consentono la dispersione"
	return ""


## Disperde il Convoglio. Ritorna { ok, error, log }.
static func disperse(ship: Ship, allowed: bool) -> Dictionary:
	var why := disperse_refusal(ship, allowed)
	if why != "":
		return {"ok": false, "error": why, "log": [] as Array[String]}
	ship.dispersed = true
	return {"ok": true, "error": "", "log": [
		"%s si disperde. Da ora incassa un solo Colpo per attacco, " % ship.name
		+ "ma varra' un punto in meno se arriva a destinazione. "
		+ "La scelta non si puo' disfare."] as Array[String]}


## Quanti Colpi incassa davvero questo bersaglio da UN attacco.
##
## RB p.11: durante ogni Round di Battaglia un Convoglio disperso puo' subire
## un solo Colpo per attacco. Se due navi lo attaccano e ciascuna ne ottiene
## due, incassa due Colpi in totale invece di quattro - uno per attacco, non
## uno per Round. Il limite vale anche per l'Attacco Aereo e per il Furtivo.
static func hits_taken(ship: Ship, hits: int) -> int:
	if is_convoy(ship) and ship.dispersed:
		return mini(hits, 1)
	return hits
