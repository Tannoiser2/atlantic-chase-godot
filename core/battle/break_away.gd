class_name BreakAway
extends RefCounted

## Fuga / Rompere il Contatto (RB p.61).
##
## Nella fase di Fuga ciascun giocatore puo' annunciare di voler uscire.
##   - se lo dichiarano ENTRAMBI, la Battaglia finisce subito, senza tiro;
##   - se lo dichiara uno solo, tira 2d6 e con 9 o piu' tutte le sue navi
##     escono e la Battaglia termina.
##
## Modificatori (letti dalla tabella sulla mappa):
##   -1  una o piu' navi avversarie in zona Vicina o Ravvicinata
##       (resta -1 anche se sono piu' di una)
##   -1  una nave avversaria e' piu' veloce
##   +2  tutte le proprie navi sono in zona Lontana e in nessun'altra
##
## Fallito il tentativo si puo' spendere un segnalino Manovre Evasive: una nave
## in zona Lontana esce comunque, le altre restano e la Battaglia continua.

const Z := BattleState.Zone
const TARGET := 9


static func modifiers(state: BattleState, tf: TaskForce) -> Dictionary:
	var own := state.ships_of(tf)
	var enemy_tf: TaskForce = state.target_tf if tf == state.active_tf else state.active_tf
	var enemy := state.ships_of(enemy_tf)

	var out: Array[Dictionary] = []

	var enemy_close := false
	for s in enemy:
		if s.battle_zone == Z.NEAR or s.battle_zone == Z.CLOSE:
			enemy_close = true
			break
	if enemy_close:
		out.append({"label": "navi avversarie in zona Vicina o Ravvicinata", "value": -1})

	var fastest_own := -1
	for s in own:
		fastest_own = maxi(fastest_own, s.current_speed())
	var enemy_faster := false
	for s in enemy:
		if s.current_speed() > fastest_own:
			enemy_faster = true
			break
	if enemy_faster:
		out.append({"label": "una nave avversaria e' piu' veloce", "value": -1})

	var all_far := not own.is_empty()
	for s in own:
		if s.battle_zone != Z.FAR:
			all_far = false
			break
	if all_far:
		out.append({"label": "tutte le proprie navi in zona Lontana", "value": 2})

	var total := 0
	for m in out:
		total += int(m["value"])
	return {"list": out, "total": total}


## Tentativo di Fuga di un solo giocatore.
static func attempt(state: BattleState, tf: TaskForce, rng: DiceRNG) -> Dictionary:
	var mods := modifiers(state, tf)
	var raw := rng.d6x2("Fuga di %s" % tf.display_name())
	var total: int = raw + int(mods["total"])
	var ok := total >= TARGET
	return {
		"tf": tf, "raw": raw, "modifiers": mods["list"],
		"modifier_total": mods["total"], "sum": total,
		"target": TARGET, "success": ok,
	}


## Entrambi i giocatori dichiarano: la Battaglia finisce subito, senza tiro.
static func mutual(state: BattleState) -> void:
	state.end_battle("entrambi i giocatori hanno dichiarato di uscire")


## Applica una Fuga riuscita: tutte le navi del giocatore escono.
static func apply_success(state: BattleState, tf: TaskForce) -> void:
	for s in state.ships_of(tf):
		state.withdrawn.append(s)
	state.end_battle("%s ha rotto il contatto" % tf.display_name())


## Fuga parziale con Manovre Evasive: dopo un tentativo fallito, si spende il
## segnalino e UNA nave in zona Lontana esce; le altre restano.
static func spend_evasive(state: BattleState, tf: TaskForce) -> Dictionary:
	if not tf.evasive:
		return {"ok": false, "reason": "%s non ha un segnalino Manovre Evasive"
			% tf.display_name()}
	var far := state.ships_in_zone(tf, Z.FAR)
	if far.is_empty():
		return {"ok": false, "reason": "nessuna nave di %s in zona Lontana"
			% tf.display_name()}
	var ship: Ship = far[0]
	tf.evasive = false
	state.withdrawn.append(ship)
	state.note("Manovre Evasive spese: %s esce dalla Battaglia, le altre restano."
		% ship.name)
	state.check_end()
	return {"ok": true, "ship": ship}


static func describe(a: Dictionary) -> String:
	var parts: Array[String] = []
	for m in a["modifiers"] as Array:
		parts.append("%s %+d" % [m["label"], int(m["value"])])
	var mtxt := (" [" + ", ".join(parts) + "]") if not parts.is_empty() else ""
	return "Fuga di %s: 2d6 = %d%s -> %d (serve %d) = %s" % [
		(a["tf"] as TaskForce).display_name(), a["raw"], mtxt, a["sum"],
		a["target"], "riuscita" if a["success"] else "fallita"]
