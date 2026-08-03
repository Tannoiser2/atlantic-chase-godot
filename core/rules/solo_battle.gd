class_name SoloBattle
extends RefCounted

## Dottrina dell'avversario immaginario sulla Mappa di Battaglia.
##
## Il fascicolo solitario (AC_Solo_scenarios_2022, p.3) non dà un bot: dà
## tendenze. Quindi qui non si cerca una tattica perfetta; si applicano solo le
## priorità stampate: bersaglia Convogli, poi la nave più letale; la Royal Navy
## chiude la distanza, la Kriegsmarine la tiene salvo bersagli deboli; la Fuga
## scatta quando il fascicolo dice che l'avversario immaginario la tenterebbe.


static func targeting(state: BattleState, imaginary_side: int,
		torpedoes: bool = false) -> Dictionary:
	var out := {}
	var firers := _ships_of_side(state, imaginary_side)
	var enemies := _ships_of_side(state, 1 - imaginary_side)
	var used_targets: Array[Ship] = []
	for f in firers:
		var candidates := _legal_targets(state, f, enemies, torpedoes)
		if candidates.is_empty():
			continue
		var target := _best_target(f, candidates, used_targets, torpedoes)
		if target == null:
			target = _best_target(f, candidates, [], torpedoes)
		if target != null:
			out[f] = target
			used_targets.append(target)
	return out


static func maneuver_moves(state: BattleState, imaginary_side: int) -> Dictionary:
	var out := {}
	var enemies := _ships_of_side(state, 1 - imaginary_side)
	for s in _ships_of_side(state, imaginary_side):
		out[s] = maneuver_for_ship(state, s, imaginary_side, enemies)
	return out


static func maneuver_for_ship(state: BattleState, ship: Ship,
		imaginary_side: int, enemies: Array[Ship] = []) -> Dictionary:
	if enemies.is_empty():
		enemies = _ships_of_side(state, 1 - imaginary_side)
	return {"zone": _maneuver_destination(ship, imaginary_side, enemies,
		state.advanced), "smoke": ship.smoke}


## L'avversario immaginario sceglie da solo le proprie Attitudini. Non sono
## movimenti obbligatori: sono la sua decisione tattica, poi il motore applica
## gli stessi limiti di piazzamento e di scenario del giocatore umano.
static func attitude_choices(state: BattleState, imaginary_side: int) -> Dictionary:
	var out := {}
	var enemies := _ships_of_side(state, 1 - imaginary_side)
	for ship in _ships_of_side(state, imaginary_side):
		if not Attitude.can_change(ship):
			continue
		var choice := Attitude.Kind.CLOSING
		if ship.kind == Ship.Kind.CONVOY or ship.damaged:
			choice = Attitude.Kind.RUNNING
		elif ship.has_torpedo and ship.torpedo_attacks_used \
				< ship.torpedo_attack_limit:
			choice = Attitude.Kind.CLOSING
		elif imaginary_side == TaskForce.Side.ROYAL_NAVY:
			choice = Attitude.Kind.CLOSING if ship.battle_zone == BattleState.Zone.FAR \
				else Attitude.Kind.ACQUIRING
		elif _has_capital(enemies):
			choice = Attitude.Kind.RUNNING
		else:
			choice = Attitude.Kind.ACQUIRING
		out[ship] = choice
	return out


## Se puo', il bot usa Inseguimento contro una nave che sta gia' Correndo:
## rinuncia al proprio movimento e la trascina una zona piu' vicina. E' la
## risposta tattica prevista dal regolamento a un futuro tentativo di Fuga.
static func pursuit_target(state: BattleState, pursuer: Ship,
		imaginary_side: int) -> Ship:
	if not state.advanced or not Attitude.can_pursue(pursuer):
		return null
	for enemy in _ships_of_side(state, 1 - imaginary_side):
		if enemy.attitude == Attitude.Kind.RUNNING \
				and Attitude.pursuit_refusal(pursuer, enemy) == "":
			return enemy
	return null


static func wants_break_away(state: BattleState, imaginary_side: int) -> bool:
	var mine := _ships_of_side(state, imaginary_side)
	var enemies := _ships_of_side(state, 1 - imaginary_side)
	if imaginary_side == TaskForce.Side.ROYAL_NAVY:
		if _has_kind(mine, Ship.Kind.CONVOY) or _has_damaged(mine):
			return true
		return not _has_capital(mine) and _has_capital(enemies)
	# German: Convoglio, DD truppe/rifornimenti o nave danneggiata; oppure
	# una BB/BC britannica integra sul campo.
	if _has_kind(mine, Ship.Kind.CONVOY) or _has_kind(mine, Ship.Kind.DD_SQUADRON) \
			or _has_damaged(mine):
		return true
	for e in enemies:
		if not e.damaged and (e.type_code == "BB" or e.type_code == "BC"):
			return true
	return false


static func _ships_of_side(state: BattleState, side: int) -> Array[Ship]:
	if state.active_tf != null and state.active_tf.side == side:
		return state.active_ships()
	if state.target_tf != null and state.target_tf.side == side:
		return state.target_ships()
	return [] as Array[Ship]


static func _legal_targets(state: BattleState, firer: Ship, enemies: Array[Ship],
		torpedoes: bool) -> Array[Ship]:
	var out: Array[Ship] = []
	for e in enemies:
		if e.sunk:
			continue
		if torpedoes:
			var obscured := Maneuver.is_obscured(state, firer)
			var can_attack := AdvancedTorpedo.can_attack(firer, obscured) \
				if state.advanced else Torpedo.can_attack(firer, obscured)
			var valid := AdvancedTorpedo.is_valid_target(e) \
				if state.advanced else Torpedo.is_valid_target(e)
			if can_attack and valid:
				out.append(e)
		else:
			var r := Gunnery.range_between(firer.battle_zone, e.battle_zone)
			if firer.can_fire(Gunnery.band_for(r)):
				out.append(e)
	return out


static func _best_target(firer: Ship, candidates: Array[Ship],
		already_targeted: Array[Ship], torpedoes: bool) -> Ship:
	var best: Ship = null
	var best_key := -9999
	for e in candidates:
		if already_targeted.has(e):
			continue
		var key := 0
		if e.kind == Ship.Kind.CONVOY:
			key += 1000
		if e.damaged:
			key += 20
		if torpedoes:
			key += 10 - e.current_speed()
		else:
			var r := Gunnery.range_between(e.battle_zone, firer.battle_zone)
			var v: Variant = e.gun_value(Gunnery.band_for(r))
			key += int(round(float(v))) if v != null else 0
		if key > best_key:
			best_key = key
			best = e
	return best


static func _maneuver_destination(ship: Ship, imaginary_side: int,
		enemies: Array[Ship], advanced: bool = false) -> int:
	if advanced:
		if ship.current_speed() == TimeLapse.Speed.STOPPED:
			return -1
		if ship.attitude == Attitude.Kind.ACQUIRING:
			return -1
		if ship.attitude == Attitude.Kind.CLOSING:
			return _closer(ship)
		if ship.attitude == Attitude.Kind.RUNNING:
			return _away(ship)
	if imaginary_side == TaskForce.Side.ROYAL_NAVY:
		if ship.kind == Ship.Kind.CONVOY or ship.damaged:
			return _away(ship)
		if ship.has_torpedo and ship.battle_zone != BattleState.Zone.CLOSE:
			return _closer(ship)
		return _closer(ship)

	# Kriegsmarine: resta/va lontano, salvo bersagli deboli.
	if _enemy_torpedo_in_close(enemies):
		return _away(ship)
	if _only_weak_targets(enemies):
		return _closer(ship)
	return _away(ship)


static func _closer(ship: Ship) -> int:
	if ship.battle_zone == BattleState.Zone.CLOSE:
		return -1
	return ship.battle_zone + 1


static func _away(ship: Ship) -> int:
	if ship.battle_zone == BattleState.Zone.FAR:
		return -1
	return ship.battle_zone - 1


static func _enemy_torpedo_in_close(enemies: Array[Ship]) -> bool:
	for e in enemies:
		if e.has_torpedo and e.battle_zone == BattleState.Zone.CLOSE and not e.sunk:
			return true
	return false


static func _only_weak_targets(enemies: Array[Ship]) -> bool:
	for e in enemies:
		if e.sunk:
			continue
		if e.kind == Ship.Kind.CONVOY or e.kind == Ship.Kind.DD_SQUADRON \
				or e.damaged or e.type_code == "CL":
			continue
		return false
	return true


static func _has_kind(ships: Array[Ship], kind: int) -> bool:
	for s in ships:
		if s.kind == kind and not s.sunk:
			return true
	return false


static func _has_damaged(ships: Array[Ship]) -> bool:
	for s in ships:
		if s.damaged and not s.sunk:
			return true
	return false


static func _has_capital(ships: Array[Ship]) -> bool:
	for s in ships:
		if not s.sunk and (s.type_code == "BB" or s.type_code == "BC"):
			return true
	return false
