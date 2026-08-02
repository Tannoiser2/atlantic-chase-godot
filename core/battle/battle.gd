class_name Battle
extends RefCounted

## Orchestratore della Battaglia: mette in fila le quattro fasi di un Round
## (RB p.56) e gestisce l'inizio e la fine.
##
##   1. Fuoco di Cannoni   le navi attaccano simultaneamente
##   2. Siluri             dalla zona Ravvicinata, contro Ravvicinata o Vicina
##   3. Manovra            una zona, dalla nave piu' lenta, alternando i giocatori
##   4. Fuga               si puo' tentare di uscire dalla Battaglia
##
## Le decisioni (chi spara a chi, chi manovra dove, chi tenta la Fuga) NON sono
## prese qui: il chiamante le passa. Cosi' la stessa classe serve alla UI, ai
## test con tiri imposti, e in futuro al bot del solitario, senza doppioni.
## I metodi `auto_*` forniscono una scelta ragionevole per quando serve solo
## far girare la battaglia.

var state: BattleState
var rng: DiceRNG
var surprise_first_strike: bool = false

## Chi tiene il conto dei Punti Vittoria. Opzionale: senza, la Battaglia
## funziona esattamente come prima e nessuno segna punti. Serve perche' i
## Colpi si contano qui e da nessun'altra parte.
var tracker: VictoryTracker = null


func _init(p_state: BattleState, p_rng: DiceRNG,
		p_tracker: VictoryTracker = null) -> void:
	state = p_state
	rng = p_rng
	tracker = p_tracker


func start() -> void:
	surprise_first_strike = state.deploy()
	state.round_number = 1
	state.phase = BattleState.Phase.GUNNERY
	state.note("Inizio Battaglia. Ultimo Round: %d (meteo %s)." % [
		state.last_round,
		"cattivo" if state.weather == TimeLapse.Weather.BAD else "buono"])


# ------------------------------------------------------ 1. Fuoco di Cannoni --

## `targeting` associa nave attaccante -> nave bersaglio.
## RB p.57: gli effetti si applicano dopo che TUTTE le navi hanno attaccato.
## Eccezione: nel Round Uno dopo una SORPRESA con TF Attiva piu' veloce, le
## navi Attive sparano per prime e i loro Colpi si applicano subito.
func gunnery_phase(targeting: Dictionary) -> Array[Dictionary]:
	state.phase = BattleState.Phase.GUNNERY
	var results: Array[Dictionary] = []

	var first_wave: Array[Ship] = []
	var second_wave: Array[Ship] = []
	if surprise_first_strike and state.round_number == 1:
		first_wave = state.active_ships()
		second_wave = state.target_ships()
		state.note("Round Uno con Sorpresa: le navi Attive sparano per prime.")
	else:
		second_wave = state.all_ships()

	if not first_wave.is_empty():
		results.append_array(_resolve_wave(first_wave, targeting))
		_apply_hits(results)
		state.check_end()
		if state.ended:
			return results
		var later := _resolve_wave(second_wave, targeting)
		results.append_array(later)
		_apply_hits(later)
	else:
		results = _resolve_wave(second_wave, targeting)
		_apply_hits(results)

	state.check_end()
	return results


func _resolve_wave(firers: Array[Ship], targeting: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for firer in firers:
		if firer.sunk or not targeting.has(firer):
			continue
		var target: Ship = targeting[firer]
		if target == null or target.sunk:
			continue
		var st := Maneuver.is_obscured(state, target)
		var sf := Maneuver.is_obscured(state, firer)
		var a := Gunnery.attack(firer, target, rng, st, sf, state.advanced)
		state.note(Gunnery.describe(a))
		out.append(a)
	return out


func _apply_hits(results: Array[Dictionary]) -> void:
	for a in results:
		if not a["ok"]:
			continue
		var target: Ship = a["target"]
		if target == null or target.sunk:
			continue
		# Un Risultato Grave fa ZERO Colpi: e' un effetto, non un danno. Il
		# controllo sui Colpi va quindi fatto DOPO gli effetti speciali, se no
		# tutta la parte piu' interessante delle regole avanzate verrebbe
		# saltata da un `continue` scritto per le regole base.
		_apply_special(a)
		if int(a.get("hits", 0)) <= 0 or target.sunk:
			continue
		# Fotografia e proprietario si prendono PRIMA di applicare i Colpi.
		# La fotografia perche' dopo, danneggiata e affondata sono gia'
		# cambiate e non si distingue piu' un Colpo da un affondamento. Il
		# proprietario perche' una nave affondata non figura piu' fra le navi
		# a galla della sua Task Force: chiedendolo dopo, own_tf_of ricadrebbe
		# sull'altra Task Force e i punti andrebbero al giocatore sbagliato.
		var before := VictoryTracker.snapshot(target)
		var owner_tf := state.own_tf_of(target)
		# un Convoglio disperso incassa un solo Colpo per attacco (RB p.11):
		# e' il motivo per cui vale la pena disperderlo
		var raw := int(a.get("hits", 0))
		var hits := Convoy.hits_taken(target, raw)
		if hits < raw:
			state.note("    %s e' disperso: dei %d Colpi ne incassa %d."
				% [target.name, raw, hits])
		state.note("    " + target.apply_hits(hits))
		if tracker != null and owner_tf != null:
			for line in tracker.hits_on(target, hits, owner_tf.side, before):
				state.note("    " + line)


## Gli Effetti Speciali delle Regole Avanzate.
##
## Sta qui e non dentro Gunnery/Torpedo per la stessa ragione per cui i Colpi
## si applicano qui: la regola vuole che tutto si applichi DOPO che tutte le
## navi hanno attaccato, e questo e' il punto unico in cui succede.
func _apply_special(a: Dictionary) -> void:
	if not state.advanced or not bool(a.get("special", false)):
		return
	var target: Ship = a["target"]
	var effect := String(a.get("effect", ""))
	if effect == "":
		# I risultati del FUOCO non dicono ancora l'effetto: rimandano alle
		# tabelle dei Risultati Speciali, dove due tiri in piu' dicono DOVE e'
		# entrato il colpo e poi che cosa ha rotto. La colonna dipende dal
		# raggio, ed e' li' che sta il senso: da lontano un Catastrofico e'
		# spesso solo un avvistamento sbagliato, da vicino entra sotto la
		# linea di galleggiamento.
		var gv := 0
		var firer: Ship = a.get("firer", null)
		if firer != null:
			var v: Variant = firer.gun_value(String(a.get("band", "far")))
			gv = int(round(float(v))) if v != null else 0
		var res := ResultTables.resolve(
			int(a.get("result", 0)) == AdvancedGunnery.Result.CATASTROPHIC,
			int(a.get("range", 0)), gv, rng)
		state.note("    %s -> %s (dadi %s)" % [String(a.get("label", "")),
			String(res["note"]), str(res["rolls"])])
		if bool(res["hit"]):
			state.note("    " + target.apply_hits(1))
		effect = String(res["effect"])
		if effect == "":
			return
		if effect == "Affondata":
			target.sunk = true
			state.note("    %s: colpita nella sovrastruttura. AFFONDATA."
				% target.name)
			return
	var r := SpecialEffects.apply(target, effect)
	state.note("    " + String(r["log"]))


# ---------------------------------------------------------------- 2. Siluri --

## `attacks` associa nave attaccante -> nave bersaglio, solo per le navi con
## siluri in zona Ravvicinata.
func torpedo_phase(attacks: Dictionary) -> Array[Dictionary]:
	state.phase = BattleState.Phase.TORPEDO
	var out: Array[Dictionary] = []
	for firer_v: Variant in attacks.keys():
		var firer: Ship = firer_v
		var target: Ship = attacks[firer_v]
		if firer.sunk or target == null or target.sunk:
			continue
		var a := AdvancedTorpedo.attack(firer, target, rng) if state.advanced \
			else Torpedo.attack(firer, target, rng)
		state.note(AdvancedTorpedo.describe(a) if state.advanced
			else Torpedo.describe(a))
		out.append(a)
	_apply_hits(out)
	state.check_end()
	return out


# --------------------------------------------------------------- 3. Manovra --

## `moves` associa nave -> { "zone": int (-1 = ferma), "smoke": bool }.
## Le navi non elencate restano dove sono e mantengono lo stato del Fumo.
func maneuver_phase(moves: Dictionary) -> void:
	state.phase = BattleState.Phase.MANEUVER
	for ship in Maneuver.move_order(state):
		if not moves.has(ship):
			continue
		var m: Dictionary = moves[ship]
		var txt := Maneuver.apply(ship, int(m.get("zone", -1)),
			bool(m.get("smoke", ship.smoke)))
		if txt == "":
			state.note("mossa illegale ignorata per %s" % ship.name)
		else:
			state.note(txt)


# ------------------------------------------------------------------ 4. Fuga --

## `declare_active` / `declare_target`: chi annuncia di voler uscire.
func break_away_phase(declare_active: bool, declare_target: bool) -> Dictionary:
	state.phase = BattleState.Phase.BREAK_AWAY
	if declare_active and declare_target:
		BreakAway.mutual(state)
		return {"mutual": true, "success": true}
	if not declare_active and not declare_target:
		return {"mutual": false, "attempted": false}
	var tf: TaskForce = state.active_tf if declare_active else state.target_tf
	var a := BreakAway.attempt(state, tf, rng)
	state.note(BreakAway.describe(a))
	if a["success"]:
		BreakAway.apply_success(state, tf)
	a["mutual"] = false
	a["attempted"] = true
	return a


## Chiude il Round e passa al successivo, oppure termina la Battaglia
## (RB p.62: fine dell'Ultimo Round, o un giocatore senza navi).
func end_round() -> bool:
	if state.check_end():
		return true
	if state.round_number >= state.last_round:
		state.end_battle("raggiunto l'Ultimo Round (%d)" % state.last_round)
		return true
	state.round_number += 1
	state.phase = BattleState.Phase.GUNNERY
	state.note("--- Round %d ---" % state.round_number)
	return false


# ------------------------------------------------------------------ uscita --

## RB p.49/62: al termine entrambe le TF ricevono un segnalino Contatto (se non
## l'hanno gia') e diventano Stazioni nell'esagono di Battaglia; poi si Cerca
## l'Iniziativa. Le navi superstiti tornano alla loro Casella Task Force.
func finish() -> Dictionary:
	var out := {"sunk": [] as Array[String], "survivors": [] as Array[String]}
	for tf in [state.active_tf, state.target_tf]:
		if tf == null:
			continue
		for s in tf.ships:
			if s.sunk:
				(out["sunk"] as Array[String]).append(s.display())
			else:
				(out["survivors"] as Array[String]).append(s.display())
			s.smoke = false
		tf.recompute_speed()
		if not tf.is_eliminated():
			tf.trajectory.become_station(state.hex, true)
			tf.trajectory.station_contact = true
	state.note("Uscita: entrambe le Task Force diventano Stazioni in %s con un "
		% str(state.hex) + "segnalino Contatto. I giocatori Cercano l'Iniziativa.")
	return out


# ----------------------------------------------------- scelte automatiche --

## Bersaglio piu' ovvio per ogni nave: quella nemica piu' vicina che si puo'
## battere, preferendo le gia' danneggiate. Serve alla UI e ai test; non
## pretende di essere una tattica.
func auto_targeting() -> Dictionary:
	var out := {}
	for side in [[state.active_ships(), state.target_ships()],
			[state.target_ships(), state.active_ships()]]:
		var firers: Array[Ship] = side[0]
		var enemies: Array[Ship] = side[1]
		for f in firers:
			var best: Ship = null
			var best_key := 99
			for e in enemies:
				var r := Gunnery.range_between(f.battle_zone, e.battle_zone)
				if not f.can_fire(Gunnery.band_for(r)):
					continue
				var key := r * 2 + (0 if e.damaged else 1)
				if key < best_key:
					best_key = key
					best = e
			if best != null:
				out[f] = best
	return out


func auto_torpedoes() -> Dictionary:
	var out := {}
	for side in [[state.active_ships(), state.target_ships()],
			[state.target_ships(), state.active_ships()]]:
		for f in side[0] as Array[Ship]:
			if not Torpedo.can_attack(f):
				continue
			for e in side[1] as Array[Ship]:
				if Torpedo.is_valid_target(e):
					out[f] = e
					break
	return out
