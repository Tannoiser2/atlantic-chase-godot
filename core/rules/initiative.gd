class_name Initiative
extends RefCounted

## Iniziativa e Condizioni Meteo (RB p.25, p.54).
##
## Ogni volta che l'Iniziativa cambia mano, il nuovo giocatore Attivo verifica
## il Meteo prima della propria azione: con Meteo Buono cambia a 6, con Meteo
## Avverso cambia a 5-6.


static func side_name(side: int) -> String:
	return "Kriegsmarine" if side == TaskForce.Side.KRIEGSMARINE else "Royal Navy"


static func weather_label(weather: int) -> String:
	return "cattivo" if weather == TimeLapse.Weather.BAD else "buono"


static func weather_check(state: GameState) -> Dictionary:
	var before := state.weather
	var roll := state.rng.d6("Verifica Meteo")
	var changes := (before == TimeLapse.Weather.GOOD and roll == 6) \
		or (before == TimeLapse.Weather.BAD and roll >= 5)
	if changes:
		state.weather = TimeLapse.Weather.BAD if before == TimeLapse.Weather.GOOD \
			else TimeLapse.Weather.GOOD
	return {"roll": roll, "before": before, "after": state.weather,
		"changed": changes, "log": "Verifica Meteo: 1d6 = %d, %s -> %s%s." % [
			roll, weather_label(before), weather_label(state.weather),
			" (cambia)" if changes else ""]}


static func pass_to_inactive(state: GameState) -> Dictionary:
	state.initiative = 1 - state.initiative
	state.initiative_count = 0
	var w := weather_check(state)
	return {"changed": true, "winner": state.initiative, "weather": w,
		"log": ["L'Iniziativa passa a %s; il conteggio torna a zero."
			% side_name(state.initiative), String(w["log"])] as Array[String]}


## Cercare l'Iniziativa: l'Attivo tira 1d6; l'Inattivo tira 1d6 e somma il
## Conto dell'Iniziativa ed eventualmente Manovre Evasive. Parita' = Attivo.
static func seek(state: GameState, inactive_evasive: bool = false) -> Dictionary:
	var active := state.initiative
	var inactive := 1 - active
	var a := state.rng.d6("Cercare l'Iniziativa - Attivo")
	var i := state.rng.d6("Cercare l'Iniziativa - Inattivo")
	var mod := state.initiative_count + (1 if inactive_evasive else 0)
	var itotal := i + mod
	var changed := itotal > a
	var lines: Array[String] = [
		"Cercare l'Iniziativa: %s 1d6=%d; %s 1d6=%d%+d -> %d." % [
			side_name(active), a, side_name(inactive), i, mod, itotal]]
	if changed:
		state.initiative = inactive
		state.initiative_count = 0
		lines.append("L'Iniziativa passa a %s; il conteggio torna a zero."
			% side_name(inactive))
		var w := weather_check(state)
		lines.append(String(w["log"]))
		return {"changed": true, "winner": inactive, "active_roll": a,
			"inactive_roll": i, "modifier": mod, "weather": w, "log": lines}
	state.initiative_count += 1
	lines.append("%s mantiene l'Iniziativa; il conteggio sale a %d."
		% [side_name(active), state.initiative_count])
	return {"changed": false, "winner": active, "active_roll": a,
		"inactive_roll": i, "modifier": mod, "weather": {}, "log": lines}


## Sottrarre l'Iniziativa: l'Inattivo tira 2d6 + Conto + eventuali Manovre
## Evasive; con 9+ prende l'Iniziativa, altrimenti il Conto sale di 1.
static func steal(state: GameState, inactive_evasive: bool = false) -> Dictionary:
	var inactive := 1 - state.initiative
	var roll := state.rng.d6x2("Sottrarre l'Iniziativa")
	var mod := state.initiative_count + (1 if inactive_evasive else 0)
	var total := roll + mod
	var lines: Array[String] = [
		"Sottrarre l'Iniziativa: %s 2d6=%d%+d -> %d (serve 9)." % [
			side_name(inactive), roll, mod, total]]
	if total >= 9:
		state.initiative = inactive
		state.initiative_count = 0
		lines.append("Riesce: l'Iniziativa passa a %s; il conteggio torna a zero."
			% side_name(inactive))
		var w := weather_check(state)
		lines.append(String(w["log"]))
		return {"changed": true, "success": true, "winner": inactive,
			"roll": roll, "modifier": mod, "total": total, "weather": w,
			"log": lines}
	state.initiative_count += 1
	lines.append("Fallisce: %s mantiene l'Iniziativa; il conteggio sale a %d."
		% [side_name(state.initiative), state.initiative_count])
	return {"changed": false, "success": false, "winner": state.initiative,
		"roll": roll, "modifier": mod, "total": total, "weather": {},
		"log": lines}


## L'Inattivo rinuncia al tiro e prende Manovre Evasive: il Conto non aumenta.
static func decline_steal_for_evasive(state: GameState, tf: TaskForce) -> Dictionary:
	if tf != null:
		tf.evasive = true
	return {"changed": false, "success": false, "winner": state.initiative,
		"log": ["Sottrarre l'Iniziativa: l'Inattivo rinuncia; il conteggio resta a %d."
			% state.initiative_count,
			"Manovre Evasive assegnate a %s." % tf.display_name()
				if tf != null else "Nessuna TF disponibile per Manovre Evasive."] as Array[String]}
