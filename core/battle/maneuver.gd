class_name Maneuver
extends RefCounted

## Fase di Manovra (RB p.60).
##
## Ogni nave puo' muovere di UNA zona, e le navi non danneggiate possono anche
## creare Fumo. L'ordine e' quello che rende la fase interessante: muovono
## prima le navi piu' lente, e i giocatori si alternano. A parita' di velocita'
## muove prima il giocatore Inattivo (la regola precisa che non e' un vantaggio
## agire per primi).

const Z := BattleState.Zone


## Zone raggiungibili da `z` (la Mappa di Battaglia e' una linea di tre zone).
static func adjacent_zones(z: int) -> Array[int]:
	match z:
		Z.FAR: return [Z.NEAR]
		Z.NEAR: return [Z.FAR, Z.CLOSE]
		_: return [Z.NEAR]


static func can_move_to(ship: Ship, z: int) -> bool:
	return adjacent_zones(ship.battle_zone).has(z)


## RB p.60: "Eccetto per i Convogli e le navi Danneggiate, ciascuna nave puo'
## creare Fumo". Una nave con segnalini Colpo puo' farlo finche' non e'
## Danneggiata.
static func can_make_smoke(ship: Ship) -> bool:
	return ship.kind == Ship.Kind.WARSHIP and not ship.damaged and not ship.sunk


## Ordine di manovra: velocita' crescente, alternando i giocatori, con
## l'Inattivo (cioe' la TF Bersaglio) che apre ogni parita'.
static func move_order(state: BattleState) -> Array[Ship]:
	var by_speed := {}
	for s in state.all_ships():
		var sp := s.current_speed()
		if not by_speed.has(sp):
			by_speed[sp] = {"target": [] as Array[Ship], "active": [] as Array[Ship]}
		var side := "active" if state.active_ships().has(s) else "target"
		(by_speed[sp][side] as Array[Ship]).append(s)

	var speeds := by_speed.keys()
	speeds.sort()
	var out: Array[Ship] = []
	for sp_v: Variant in speeds:
		var groups: Dictionary = by_speed[sp_v]
		var t: Array[Ship] = groups["target"]
		var a: Array[Ship] = groups["active"]
		var i := 0
		# il giocatore Inattivo (Bersaglio) apre
		while i < t.size() or i < a.size():
			if i < t.size():
				out.append(t[i])
			if i < a.size():
				out.append(a[i])
			i += 1
	return out


## Applica una mossa. `to_zone` -1 significa "resta dov'e'".
## Ritorna la descrizione, o stringa vuota se la mossa e' illegale.
static func apply(ship: Ship, to_zone: int, make_smoke: bool) -> String:
	var parts: Array[String] = []
	if to_zone >= 0 and to_zone != ship.battle_zone:
		if not can_move_to(ship, to_zone):
			return ""
		parts.append("da %s a %s" % [BattleState.ZONE_LABELS[ship.battle_zone],
			BattleState.ZONE_LABELS[to_zone]])
		ship.battle_zone = to_zone
	if make_smoke != ship.smoke:
		if make_smoke and not can_make_smoke(ship):
			return ""
		ship.smoke = make_smoke
		parts.append("crea Fumo" if make_smoke else "cessa il Fumo")
	if parts.is_empty():
		return "%s resta in zona %s" % [ship.name, BattleState.ZONE_LABELS[ship.battle_zone]]
	return "%s %s" % [ship.name, ", ".join(parts)]


## Il Fumo oscura la nave che lo crea e fino a due altre navi nella stessa zona
## (RB p.60). Qui si considera oscurata ogni nave dello stesso lato e zona,
## fino al limite di due oltre a chi lo crea: e' la scelta piu' favorevole al
## difensore, che e' quella che il giocatore fara' sempre.
static func obscured_ships(state: BattleState, tf: TaskForce) -> Array[Ship]:
	var out: Array[Ship] = []
	for smoker in state.ships_of(tf):
		if not smoker.smoke:
			continue
		if not out.has(smoker):
			out.append(smoker)
		var extra := 0
		for other in state.ships_in_zone(tf, smoker.battle_zone):
			if extra >= 2:
				break
			if other == smoker or out.has(other):
				continue
			out.append(other)
			extra += 1
	return out


## True se `ship` e' oscurata dal Fumo.
static func is_obscured(state: BattleState, ship: Ship) -> bool:
	return obscured_ships(state, state.own_tf_of(ship)).has(ship)
