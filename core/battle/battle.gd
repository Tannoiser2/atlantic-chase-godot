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

## La Verifica Snafu di questa Battaglia, se si gioca in avanzato. Vuota con
## le regole base.
var snafu: Dictionary = {}

## Scelta ancora da compiere durante il piazzamento Snafu. Le scelte sono
## lasciate alla UI; il motore ne valida e applica l'esito.
var pending_snafu: Dictionary = {}


func _init(p_state: BattleState, p_rng: DiceRNG,
		p_tracker: VictoryTracker = null) -> void:
	state = p_state
	rng = p_rng
	tracker = p_tracker


func start() -> void:
	if state.predeployed:
		surprise_first_strike = false
		state.note("Schieramento dello scenario mantenuto nelle zone indicate.")
	else:
		surprise_first_strike = state.deploy()
	state.round_number = 1
	state.phase = state.first_phase()
	state.note("Inizio Battaglia. Ultimo Round: %d (meteo %s)." % [
		state.last_round,
		"cattivo" if state.weather == TimeLapse.Weather.BAD else "buono"])
	if not state.advanced:
		return
	if state.skip_snafu:
		state.note("Istruzione dello scenario: la Verifica Snafu viene saltata.")
		if state.starting_confusion_side >= 0:
			state.confusion_side = state.starting_confusion_side
			state.note("  Il segnalino Confusione parte alla %s." % (
				"Kriegsmarine" if state.confusion_side == TaskForce.Side.KRIEGSMARINE
				else "Royal Navy"))
		return
	# La Verifica Snafu si tira UNA VOLTA, prima del Round Uno, e decide con
	# che disgrazia comincia la Battaglia.
	snafu = Snafu.check(rng, state.weather)
	state.note("Verifica Snafu: 2d6 = %d -> %s" % [int(snafu["sum"]),
		String(snafu["label"])])
	state.note("  " + String(snafu["explain"]))
	if bool(snafu["extra_round"]):
		state.last_round += 1
		state.note("  Ultimo Round spostato a %d." % state.last_round)
	if int(snafu["result"]) == Snafu.Result.CONFUSION:
		_assign_confusion()
	elif int(snafu["result"]) == Snafu.Result.MECHANICAL \
			or int(snafu["result"]) == Snafu.Result.BOILER:
		if state.active_ships().size() <= 1:
			state.note("  Una sola nave Attiva: il risultato diventa Confusione.")
			_assign_confusion()
		else:
			pending_snafu = {"kind": "delayed_entry",
				"chooser_side": state.target_tf.side,
				"candidates": state.active_ships(),
				"round": 2 if int(snafu["result"]) == Snafu.Result.MECHANICAL else 1}
			state.note("  Il giocatore Bersaglio deve scegliere una nave Attiva "
				+ "che entrera' piu' tardi.")
	elif int(snafu["result"]) == Snafu.Result.NO_RADAR:
		var chooser_active := Snafu.beneficiary_is_active(rng)
		var chooser_tf := state.active_tf if chooser_active else state.target_tf
		var enemy_tf := state.target_tf if chooser_active else state.active_tf
		pending_snafu = {"kind": "no_radar",
			"chooser_side": chooser_tf.side,
			"candidates": state.ships_of(enemy_tf)}
		state.note("  %s deve scegliere una nave nemica per Niente Radar."
			% chooser_tf.display_name())


func _assign_confusion() -> void:
	var to_active := Snafu.beneficiary_is_active(rng)
	var tf := state.active_tf if to_active else state.target_tf
	state.confusion_side = tf.side if tf != null else -1
	state.note("  Il segnalino Confusione va a %s."
		% ("Kriegsmarine" if state.confusion_side
			== TaskForce.Side.KRIEGSMARINE else "Royal Navy"))


func resolve_snafu_choice(ship: Ship) -> Dictionary:
	if pending_snafu.is_empty():
		return {"ok": false, "error": "nessuna scelta Snafu in attesa"}
	if ship == null or not (pending_snafu.get("candidates", []) as Array).has(ship):
		return {"ok": false, "error": "questa nave non e' una scelta valida"}
	var kind := String(pending_snafu.get("kind", ""))
	if kind == "no_radar":
		if not ship.special_effects.has(Lingering.NO_RADAR_KEY):
			ship.special_effects.append(Lingering.NO_RADAR_KEY)
		state.note("Snafu - Niente Radar assegnato a %s." % ship.name)
	elif kind == "delayed_entry":
		var entry_round := int(pending_snafu.get("round", 1))
		state.delayed_entry[ship] = {
			"round": entry_round,
			"phase": BattleState.Phase.LINGERING,
			"zone": BattleState.Zone.FAR,
			"attitude": Attitude.Kind.CLOSING,
		}
		state.note("Snafu - %s entrera' negli Effetti Duraturi del Round %d."
			% [ship.name, entry_round])
	else:
		return {"ok": false, "error": "scelta Snafu non riconosciuta"}
	pending_snafu.clear()
	return {"ok": true, "error": ""}


func setup_attitudes_for(ship: Ship) -> Array[int]:
	if not Attitude.can_change(ship):
		return [ship.attitude] as Array[int]
	if state.round_number > 1:
		return [Attitude.Kind.ACQUIRING, Attitude.Kind.CLOSING,
			Attitude.Kind.RUNNING] as Array[int]
	if state.fixed_setup_attitudes.has(ship):
		return [int(state.fixed_setup_attitudes[ship])] as Array[int]
	var is_active := state.active_ships().has(ship)
	var result := int(snafu.get("result", -1))
	if is_active and result == Snafu.Result.OPEN_ARC:
		return [Attitude.Kind.ACQUIRING, Attitude.Kind.CLOSING,
			Attitude.Kind.RUNNING] as Array[int]
	if not is_active and result == Snafu.Result.UNEXPECTED_BEARING:
		return [Attitude.Kind.ACQUIRING, Attitude.Kind.CLOSING,
			Attitude.Kind.RUNNING] as Array[int]
	return Attitude.setup_options(is_active)


# -------------------------------------------------------- 1. Attitudine --

## Fase dell'Attitudine (Regole Avanzate p.3): i giocatori riassegnano
## un'attitudine a ogni nave, in segreto, e le rivelano insieme.
##
## `choices` associa nave -> Attitude.Kind. Le navi non elencate tengono
## quella che avevano: e' legale, il fascicolo dice "puo' essere la stessa
## attitudine di prima".
## LA SCELTA DELLA PLANCIA (Regole Avanzate). Una nave che ha preso la Plancia
## deve scegliere, ogni Round, fra due mali: non sparare, oppure restare Ferma.
##
## La scelta e' del PROPRIETARIO e va fatta subito, prima del Fuoco: per questo
## la si raccoglie nella fase dell'Attitudine, che nel Round avanzato viene
## prima. Finora nessuno la chiedeva, e la Plancia non faceva niente.
##
## `choice` e' "no_fire" oppure "stopped". Ritorna il motivo del rifiuto, o ""
## se la scelta e' stata registrata.
func set_bridge_choice(ship: Ship, choice: String) -> String:
	if ship == null or ship.sunk:
		return "nave assente"
	if not SpecialEffects.bridge_choice_needed(ship):
		return "%s non ha la Plancia: non deve scegliere niente" % ship.name
	if choice != "no_fire" and choice != "stopped":
		return "la Plancia si sceglie fra 'no_fire' e 'stopped'"
	state.bridge_choice[ship] = choice
	ship.round_stopped = choice == "stopped"
	state.note("%s (Plancia): %s." % [ship.name,
		"rinuncia al Fuoco" if choice == "no_fire" else "resta Ferma"])
	return ""


## Le navi che devono ancora scegliere per la Plancia in questo Round.
## Vuoto = si puo' procedere col Fuoco.
func bridge_choices_pending() -> Array[Ship]:
	var out: Array[Ship] = []
	if not state.advanced:
		return out
	for s in state.all_ships():
		if s.sunk or not SpecialEffects.bridge_choice_needed(s):
			continue
		if not state.bridge_choice.has(s):
			out.append(s)
	return out


func attitude_phase(choices: Dictionary = {}) -> void:
	state.phase = BattleState.Phase.ATTITUDE
	for s_v: Variant in choices.keys():
		var s: Ship = s_v
		if s.sunk:
			continue
		var want := int(choices[s_v])
		if not setup_attitudes_for(s).has(want):
			state.note("%s: attitudine %s non consentita nel piazzamento."
				% [s.name, Attitude.label(want)])
			continue
		s.attitude = want
	# le Comunicazioni fanno male proprio adesso, a ogni Round
	for s in state.all_ships():
		if s.sunk:
			continue
		for line in SpecialEffects.attitude_step(s):
			state.note(line)
	state.check_end()


# ------------------------------------------------------ 2. Fuoco di Cannoni --

## `targeting` associa nave attaccante -> nave bersaglio.
## RB p.57: gli effetti si applicano dopo che TUTTE le navi hanno attaccato.
## Eccezione: nel Round Uno dopo una SORPRESA con TF Attiva piu' veloce, le
## navi Attive sparano per prime e i loro Colpi si applicano subito.
func gunnery_phase(targeting: Dictionary) -> Array[Dictionary]:
	state.phase = BattleState.Phase.GUNNERY
	var results: Array[Dictionary] = []

	# La Plancia: chi ha scelto di rinunciare al Fuoco non entra in nessuna
	# ondata. Chi ha scelto di restare Fermo spara, ed e' bersaglio con +3.
	for s_v: Variant in state.bridge_choice.keys():
		if String(state.bridge_choice[s_v]) == "no_fire":
			state.note("%s non spara: la Plancia." % (s_v as Ship).name)

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
			clear_damage_control()
			return results
		var later := _resolve_wave(second_wave, targeting)
		results.append_array(later)
		_apply_hits(later)
	else:
		results = _resolve_wave(second_wave, targeting)
		_apply_hits(results)

	clear_damage_control()
	state.check_end()
	return results


func _resolve_wave(firers: Array[Ship], targeting: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for firer in firers:
		if firer.sunk or not targeting.has(firer):
			continue
		if blocked_by_damage_control(firer):
			state.note("%s non spara: Controllo Danni dichiarato nel Round precedente."
				% firer.name)
			continue
		if String(state.bridge_choice.get(firer, "")) == "no_fire":
			continue
		var target: Ship = targeting[firer]
		if target == null or target.sunk:
			continue
		var st := Maneuver.is_obscured(state, target)
		var sf := Maneuver.is_obscured(state, firer)
		var extra: Array[Dictionary] = []
		if state.advanced:
			var no_radar := Lingering.no_radar_modifier(firer,
				Gunnery.range_between(firer.battle_zone, target.battle_zone))
			if no_radar != 0:
				extra.append({"label": "Niente Radar", "value": no_radar})
			if not snafu.is_empty() \
					and int(snafu.get("result", -1)) == Snafu.Result.POOR_VISIBILITY:
				var vis := Snafu.visibility_modifier(true,
					Gunnery.range_between(firer.battle_zone, target.battle_zone))
				if vis != 0:
					extra.append({"label": "Scarsa Visibilita'", "value": vis})
		var a := Gunnery.attack(firer, target, rng, st, sf, state.advanced, 1,
			extra)
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
		var obscured := Maneuver.is_obscured(state, firer)
		var poor_visibility := 0
		if state.advanced and not snafu.is_empty() \
				and int(snafu.get("result", -1)) == Snafu.Result.POOR_VISIBILITY \
				and firer.battle_zone == BattleState.Zone.NEAR \
				and target.battle_zone == BattleState.Zone.NEAR:
			poor_visibility = -1
		var a := AdvancedTorpedo.attack(firer, target, rng, obscured,
			poor_visibility) if state.advanced \
			else Torpedo.attack(firer, target, rng, obscured)
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
		var zone := int(m.get("zone", -1))
		var smoke := bool(m.get("smoke", ship.smoke))
		var refusal := Attitude.maneuver_refusal(ship, zone, smoke) \
			if state.advanced else ""
		var txt := "" if refusal != "" else Maneuver.apply(ship, zone, smoke)
		if txt == "":
			state.note(refusal if refusal != "" \
				else "mossa illegale ignorata per %s" % ship.name)
		else:
			state.note(txt)


# ------------------------------------------------- 5. Effetti Duraturi --

## Fase degli Effetti Duraturi (Regole Avanzate p.11). Si salta del tutto se
## nessuna nave ha un effetto speciale.
##
## `damage_control` elenca le navi che dichiarano il Controllo Danni: tirano
## tre dadi e tengono i due piu' alti, ma non spareranno nel Round successivo.
## `resolver` e' opzionale e serve ai test: se e' nullo, il risultato si legge
## sulla tabella.
func lingering_phase(damage_control: Array = []) -> Array[Dictionary]:
	state.phase = BattleState.Phase.LINGERING
	var out: Array[Dictionary] = []
	_enter_delayed(BattleState.Phase.LINGERING)
	for s in state.all_ships():
		if s.sunk:
			continue
		var dc: bool = damage_control.has(s)
		if dc:
			s.set_meta("damage_control_round", state.round_number + 1)
		# ogni effetto si verifica DA SOLO, con un tiro suo: due effetti
		# fanno due tiri, non uno
		for effect in Lingering.lingering_checks(s):
			var roll := Lingering.roll(rng, dc, effect)
			var res := Lingering.lingering_result(effect, int(roll["sum"]))
			state.note("Effetti Duraturi - %s, %s: 2d6 = %d -> %s"
				% [s.name, effect, int(roll["sum"]), res])
			state.note("  " + Lingering.apply(s, effect, res))
			roll["result"] = res
			out.append(roll)
			if s.sunk:
				break
	state.check_end()
	return out


## Una nave che ha dichiarato il Controllo Danni non spara nel Round dopo.
func blocked_by_damage_control(ship: Ship) -> bool:
	return int(ship.get_meta("damage_control_round", -1)) == state.round_number


func clear_damage_control() -> void:
	for s in state.all_ships():
		if int(s.get_meta("damage_control_round", -1)) <= state.round_number:
			s.remove_meta("damage_control_round")


# ------------------------------------------------------------------ 6. Fuga --

## `declare_active` / `declare_target`: chi annuncia di voler uscire.
func break_away_phase(declare_active: bool, declare_target: bool) -> Dictionary:
	state.phase = BattleState.Phase.BREAK_AWAY
	_enter_delayed(BattleState.Phase.BREAK_AWAY)
	if state.round_number < state.minimum_break_away_round:
		state.note("Istruzione dello scenario: la Fuga non e' consentita prima "
			+ "del Round %d." % state.minimum_break_away_round)
		return {"mutual": false, "attempted": false, "blocked": true}
	if declare_active and declare_target:
		BreakAway.mutual(state)
		return {"mutual": true, "success": true}
	if not declare_active and not declare_target:
		return {"mutual": false, "attempted": false}
	var tf: TaskForce = state.active_tf if declare_active else state.target_tf
	var eligible := false
	for ship in state.ships_of(tf):
		var min_round := int(ship.get_meta("break_away_min_round", 1))
		var required_zone := int(ship.get_meta("break_away_required_zone", -1))
		if state.round_number >= min_round \
				and (required_zone < 0 or ship.battle_zone == required_zone):
			eligible = true
			break
	if not eligible:
		state.note("Fuga non consentita: nessuna nave soddisfa le istruzioni "
			+ "speciali dello scenario.")
		return {"mutual": false, "attempted": false, "blocked": true}
	var fog := state.advanced and not snafu.is_empty() \
		and int(snafu.get("result", -1)) == Snafu.Result.FOG
	var a := BreakAway.attempt(state, tf, rng, fog)
	state.note(BreakAway.describe(a))
	if a["success"]:
		BreakAway.apply_success(state, tf)
	a["mutual"] = false
	a["attempted"] = true
	return a


func _enter_delayed(phase: int) -> void:
	for s_v: Variant in state.delayed_entry.keys().duplicate():
		var delayed: Ship = s_v
		var entry_v: Variant = state.delayed_entry[s_v]
		var entry: Dictionary = entry_v if typeof(entry_v) == TYPE_DICTIONARY \
			else {"round": int(entry_v), "phase": BattleState.Phase.LINGERING,
				"zone": BattleState.Zone.FAR, "attitude": Attitude.Kind.CLOSING}
		if int(entry.get("round", 1)) != state.round_number \
				or int(entry.get("phase", BattleState.Phase.LINGERING)) != phase:
			continue
		state.delayed_entry.erase(s_v)
		delayed.battle_zone = int(entry.get("zone", BattleState.Zone.FAR))
		delayed.attitude = int(entry.get("attitude", Attitude.Kind.CLOSING))
		state.note("%s entra in zona %s, attitudine %s." % [delayed.name,
			BattleState.ZONE_LABELS[delayed.battle_zone],
			Attitude.label(delayed.attitude)])


## Chiude il Round e passa al successivo, oppure termina la Battaglia
## (RB p.62: fine dell'Ultimo Round, o un giocatore senza navi).
func end_round() -> bool:
	if state.check_end():
		return true
	if state.round_number >= state.last_round:
		# BATTAGLIA ESTESA (Regole Avanzate p.13): se alla fine dell'Ultimo
		# Round nessuna nave e' in Corsa, se ne gioca un altro. E' la regola
		# piu' bella del fascicolo: la Battaglia finisce quando qualcuno vuole
		# andarsene, e finche' tutti hanno voglia di combattere si combatte.
		if state.advanced and not state.extended and Snafu.nobody_running(state):
			state.extended = true
			state.last_round += 1
			state.note("Nessuna nave e' in Corsa: si gioca un Round in piu'.")
		else:
			state.end_battle("raggiunto l'Ultimo Round (%d)" % state.last_round)
			return true
	# La scelta della Plancia vale un Round solo, e la nave che era Ferma per
	# quella scelta torna alla sua velocita': se restasse, la Plancia
	# diventerebbe un affondamento lento e silenzioso.
	for s_v: Variant in state.bridge_choice.keys():
		(s_v as Ship).round_stopped = false
	state.bridge_choice.clear()
	state.round_number += 1
	state.phase = state.first_phase()
	state.note("--- Round %d ---" % state.round_number)
	return false


# ------------------------------------------------------------------ uscita --

## RB p.49/62: al termine entrambe le TF ricevono un segnalino Contatto (se non
## l'hanno gia') e diventano Stazioni nell'esagono di Battaglia; poi si Cerca
## l'Iniziativa. Le navi superstiti tornano alla loro Casella Task Force.
func finish() -> Dictionary:
	var out := {"sunk": [] as Array[String], "survivors": [] as Array[String]}
	# La Verifica del Disingaggio viene PRIMA di tutto il resto: decide chi
	# torna a casa e chi si autoaffonda a un passo dall'uscita, e una nave che
	# non ce la fa non deve comparire fra i superstiti.
	if state.advanced:
		_disengagement()
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
		# RB p.62: la Battaglia rimuove le Manovre Evasive da entrambe le TF.
		tf.evasive = false
		if not tf.is_eliminated():
			tf.trajectory.become_station(state.hex, true)
			tf.trajectory.station_contact = true
	state.note("Uscita: entrambe le Task Force diventano Stazioni in %s con un "
		% str(state.hex) + "segnalino Contatto. I giocatori Cercano l'Iniziativa.")
	return out


## Verifica del Disingaggio (Regole Avanzate p.14): all'uscita ogni nave con
## effetti speciali tira per sapere se ce la fa.
##
## E' l'ultimo momento in cui una Battaglia puo' ancora uccidere: un incendio
## che ferma la nave da' autoaffondamento su tutte e quattro le colonne, quindi
## una nave che esce in fiamme non torna a casa, punto.
##
## `german_vulnerable` e' la regola opzionale: il tedesco tira tre dadi e tiene
## i due piu' bassi. Vale solo negli scenari operativi e nella Campagna, e non
## se la Battaglia e' avvenuta vicino a casa - quindi la decisione sta fuori di
## qui, e chi chiama la passa.
func _disengagement(german_vulnerable: bool = false) -> void:
	for tf in [state.active_tf, state.target_tf]:
		if tf == null:
			continue
		var vulnerable: bool = german_vulnerable \
			and tf.side == TaskForce.Side.KRIEGSMARINE
		for s in tf.ships:
			if s.sunk:
				continue
			for effect in Lingering.disengagement_checks(s):
				var roll := Lingering.disengagement_roll(rng, vulnerable)
				var res := Lingering.disengagement_result(effect,
					int(roll["sum"]))
				state.note("Disingaggio - %s, %s: 2d6 = %d -> %s"
					% [s.name, effect, int(roll["sum"]), res])
				state.note("  " + Lingering.apply_disengagement(s, effect, res))
				if s.sunk:
					break


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
			var obscured := Maneuver.is_obscured(state, f)
			var can_attack := AdvancedTorpedo.can_attack(f, obscured) \
				if state.advanced else Torpedo.can_attack(f, obscured)
			if not can_attack:
				continue
			for e in side[1] as Array[Ship]:
				var valid := AdvancedTorpedo.is_valid_target(e) \
					if state.advanced else Torpedo.is_valid_target(e)
				if valid:
					out[f] = e
					break
	return out
