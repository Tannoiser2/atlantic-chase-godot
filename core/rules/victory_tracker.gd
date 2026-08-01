class_name VictoryTracker
extends RefCounted

## Traduce quello che succede in partita negli eventi che la tabella dei Punti
## Vittoria sa valutare.
##
## Sta in mezzo apposta. La Battaglia sa applicare i Colpi ma non deve sapere
## quanto valgono, e la tabella sa quanto valgono ma non deve sapere come si e'
## arrivati li'. In mezzo serve qualcuno che guardi la nave PRIMA e DOPO e dica
## che cosa e' successo: tre Colpi su un incrociatore integro possono essere
## tre Colpi e basta, oppure tre Colpi e un danno, oppure tre Colpi, un danno e
## un affondamento, e sono tre punteggi diversi.
##
## Il tracciatore e' opzionale: senza tabella VP (i mini-scenari non le hanno
## ancora) resta muto e la partita funziona lo stesso.

var victory: Victory = null
var state: GameState = null


func _init(p_victory: Victory = null, p_state: GameState = null) -> void:
	victory = p_victory
	state = p_state


func active() -> bool:
	return victory != null and state != null and victory.has_table


static func side_name(side: int) -> String:
	return "KRIEGSMARINE" if side == TaskForce.Side.KRIEGSMARINE else "ROYAL_NAVY"


## Fotografia di una nave prima di prendere i Colpi. Va chiamata PRIMA di
## `Ship.apply_hits`, se no non c'e' piu' niente da confrontare.
static func snapshot(ship: Ship) -> Dictionary:
	return {"damaged": ship.damaged, "sunk": ship.sunk}


## Colpi andati a segno su una nave. `before` e' la fotografia di prima.
## `owner_side` e' di chi e' la nave: alcune tabelle ragionano per controllo e
## non per bandiera (vedi Victory).
func hits_on(ship: Ship, hits: int, owner_side: int,
		before: Dictionary) -> Array[String]:
	if not active() or hits <= 0:
		return []
	var lines: Array[String] = []
	var ctx := {"owner": side_name(owner_side)}

	# un Convoglio non e' una nave: ha una riga sua, pagata a Colpo
	if ship.kind == Ship.Kind.CONVOY:
		for i in hits:
			lines.append_array(victory.apply_event(state,
				Victory.Event.HIT_ON_CONVOY, null, ship.name, ctx))
		return lines

	for i in hits:
		lines.append_array(victory.apply_event(state,
			Victory.Event.SHIP_HIT, ship, "", ctx))
	# i passaggi di stato valgono una volta ciascuno, non una per Colpo
	if ship.damaged and not bool(before.get("damaged", false)):
		lines.append_array(victory.apply_event(state,
			Victory.Event.SHIP_DAMAGED, ship, "", ctx))
	if ship.sunk and not bool(before.get("sunk", false)):
		lines.append_array(victory.apply_event(state,
			Victory.Event.SHIP_SUNK, ship, "", ctx))
	return lines


## Una nave che ha eseguito con successo il Completamento in un porto.
## `destination` e' quello che la tabella nomina: a volte il porto ("Kiel",
## "Bergen"), a volte il paese ("France", "Norway", "Germany"). Chi chiama passa
## la chiave giusta per lo scenario in corso.
func ship_completed(ship: Ship, destination: String,
		owner_side: int) -> Array[String]:
	if not active():
		return []
	return victory.apply_event(state, Victory.Event.SHIP_COMPLETED, ship, "",
		{"destination": destination, "owner": side_name(owner_side)})


## Un Convoglio che ha eseguito il Completamento.
func convoy_completed(destination: String, dispersed: bool,
		owner_side: int) -> Array[String]:
	if not active():
		return []
	return victory.apply_event(state, Victory.Event.CONVOY_COMPLETED, null,
		"Convoglio", {"destination": destination, "dispersed": dispersed,
			"owner": side_name(owner_side)})
