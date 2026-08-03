class_name SoloRunner
extends RefCounted

## Replay deterministico end-to-end di uno scenario in solitario, headless.
##
## Serve alla milestone R0 della revisione: finche' l'unico modo di giocare uno
## scenario era premere tasti nella GUI, una regressione nel ciclo del bot si
## vedeva solo per caso. Questa classe percorre la partita per intero - tiro
## della Tabella Azioni, modificatori automatici, decisione di `SoloAI`,
## Scorrere del Tempo, Iniziativa, Battaglia, Completamenti, fine scenario -
## senza nessun `Node`, e produce una trascrizione ripetibile a parita' di seme.
##
## DUE COSE CHE QUESTA CLASSE NON E'
##
## 1. Non e' una nuova sorgente di regole. Ogni regola resta dove stava:
##    `SoloOpponent` per le tabelle, `SoloAI` per la policy dell'avversario
##    immaginario, `TimeLapse`, `Initiative`, `ActionEngine`, `Results`,
##    `Completion`, `Battle`, `SoloBattle`. Qui c'e' soltanto la SEQUENZA, che
##    prima esisteva solo dentro `ui/main.gd` e quindi non era testabile.
##
## 2. La policy del GIOCATORE simulato non e' una regola GMT. Il fascicolo
##    solitario non dice come deve giocare l'essere umano; per il replay serve
##    comunque una mano deterministica, e quella qui sotto e' dichiaratamente
##    una convenzione dell'harness: Completa se puo', altrimenti attacca se
##    l'azione e' gia' legale, altrimenti avvicina la Traiettoria, altrimenti
##    Passa. Ogni riga che ne deriva e' marcata `GIOCATORE (policy harness)`
##    nella trascrizione, cosi' nessuno la scambia per una regola stampata.
##
## NOTA sulla duplicazione con `ui/main.gd`: la vista implementa la stessa
## sequenza con le sue attese asincrone e i suoi dialoghi. Finche' non sara'
## riscritta sopra questa classe (voce aperta in TODO_REVISIONE.md), una
## modifica alla sequenza va fatta in tutti e due i posti.

## Limite di sicurezza: un ciclo che non converge e' un difetto da mostrare,
## non un processo da lasciare girare. Il replay si ferma e lo dichiara.
const MAX_TURNS := 120

## Stessa idea dentro una Battaglia: le fasi hanno sempre una fine, ma se una
## regressione la togliesse il replay non deve bloccarsi in silenzio.
const MAX_BATTLE_STEPS := 400

## Quante continuazioni prescritte si accettano di fila su una stessa uscita
## della Tabella. Il fascicolo ne stampa al massimo due (Traiettoria + azione).
const MAX_FOLLOW_UPS := 4

var state: GameState = null
var graph: MapGraph = null
var engine: ActionEngine = null
var solo: SoloOpponent = null
var scenario: Scenario = null
var victory: Victory = null
var vp_tracker: VictoryTracker = null
var port_control: Dictionary = {}

var player_side: int = -1
var imaginary_side: int = -1

## Trascrizione riga per riga. E' il prodotto del replay: due esecuzioni con lo
## stesso seme devono darla identica, carattere per carattere.
var transcript: Array[String] = []

var turns: int = 0
var bot_turns: int = 0
var player_turns: int = 0
var battles: int = 0
var completions: int = 0
var stopped_reason: String = ""

## `stopped_reason` valorizzato per una lacuna DICHIARATA del fascicolo, non
## per un difetto del ciclo. Serve a distinguere "il regolamento non prevede
## questa posizione" da "il replay non converge".
var declared_gap: bool = false
var load_error: String = ""

## Se il giocatore simulato tenta di Sottrarre l'Iniziativa quando il bot
## dichiara un Completamento o una Ricerca Navale. Falso di default: rende il
## replay piu' corto e piu' leggibile, e la strada del tentativo e' comunque
## coperta dai test dedicati.
var player_steals_initiative: bool = false


# ------------------------------------------------------------------ avvio --

## Prepara lo scenario esattamente come fa la schermata iniziale, ma senza GUI.
## Ritorna false e riempie `load_error` se lo scenario non e' giocabile.
func load_scenario(scenario_id: String, p_seed: int) -> bool:
	scenario = Scenario.load_by_id(scenario_id)
	if scenario == null or scenario.load_error != "":
		load_error = "scenario '%s' non caricato: %s" % [scenario_id,
			scenario.load_error if scenario != null else "file assente"]
		return false
	graph = MapGraph.load_default()
	engine = ActionEngine.load_default()
	state = GameState.new(graph, p_seed)
	state.apply_dict(scenario.to_state_dict())
	port_control = scenario.port_control()
	state.configure_port_info_triggers(port_control)
	victory = Victory.from_scenario(scenario)
	vp_tracker = VictoryTracker.new(victory, state)
	solo = SoloOpponent.load_for(scenario.id)
	if solo == null:
		load_error = "lo scenario '%s' non ha tabelle solitarie" % scenario_id
		return false
	solo.set_phase(state.solo_phase, state.solo_phase_reason)
	if victory == null or victory.mode != Victory.Mode.DEBRIEFING:
		load_error = "lo scenario '%s' non e' un solitario (nessun Debriefing)" % scenario_id
		return false
	player_side = victory.solo_side
	imaginary_side = 1 - player_side
	if state.task_forces.is_empty() and not scenario.map_info.is_empty():
		load_error = "%s: %s" % [String(scenario.map_info.get("name", "mappa speciale")),
			String(scenario.map_info.get("status", "reticolo non calibrato"))]
		return false
	return true


# ------------------------------------------------------------- ciclo lungo --

func run(max_turns: int = MAX_TURNS) -> Dictionary:
	_line("=== %s ===" % scenario.title)
	_line("Seme %d; giocatore %s, avversario immaginario %s." % [
		state.rng.seed_value, Initiative.side_name(player_side),
		Initiative.side_name(imaginary_side)])
	_line("Setup: %d Task Force, meteo %s, Iniziativa %s, %d marker RV." % [
		state.task_forces.size(), Initiative.weather_label(state.weather),
		Initiative.side_name(state.initiative), state.rendezvous_markers.size()])
	for tf in state.task_forces:
		_line("  %s (%s): %s" % [tf.display_name(),
			Initiative.side_name(tf.side), _tf_position(tf)])

	# Una condizione di fine puo' essere gia' vera prima del primo turno: va
	# verificata subito, non dopo aver fatto agire qualcuno.
	if SoloAI.enforce_scenario_end(state):
		_line("FINE SCENARIO prima del primo turno: %s" % state.solo_end_reason)

	while not state.solo_ended and turns < max_turns:
		turns += 1
		_line("")
		_line("--- Turno %d - Iniziativa %s (conto %d, meteo %s) ---" % [turns,
			Initiative.side_name(state.initiative), state.initiative_count,
			Initiative.weather_label(state.weather)])
		var before_seed := state.rng.log.size()
		if state.initiative == imaginary_side:
			bot_turns += 1
			_bot_turn()
		else:
			player_turns += 1
			_player_turn()
		if SoloAI.enforce_scenario_end(state):
			_line("FINE SCENARIO: %s" % state.solo_end_reason)
		var stall := _declared_stall()
		if stall != "" and not state.solo_ended:
			stopped_reason = stall
			declared_gap = true
			_line("STALLO DICHIARATO: %s" % stall)
			break
		# Un turno che non tira nemmeno un dado e non cambia l'Iniziativa non
		# fa progredire niente: e' un ciclo fermo, e va dichiarato subito
		# invece di consumare tutti i turni disponibili.
		if state.rng.log.size() == before_seed and not state.solo_ended:
			stopped_reason = ("turno %d senza alcun tiro: il ciclo non avanza"
				% turns)
			_line("INTERROTTO: %s" % stopped_reason)
			break
	if not state.solo_ended and stopped_reason == "":
		stopped_reason = "raggiunto il limite di %d turni" % max_turns
		_line("INTERROTTO: %s" % stopped_reason)

	_line("")
	_line("=== Esito ===")
	_line("Turni: %d (bot %d, giocatore %d); Battaglie: %d; Completamenti: %d."
		% [turns, bot_turns, player_turns, battles, completions])
	_line("VP: Kriegsmarine %s, Royal Navy %s." % [
		state.vp_text(TaskForce.Side.KRIEGSMARINE),
		state.vp_text(TaskForce.Side.ROYAL_NAVY)])
	var debrief := victory.outcome(state)
	var row: Dictionary = debrief.get("row", {})
	_line("Debriefing: punteggio %s -> %s" % [
		GameState.vp_str(float(debrief.get("score", 0.0))),
		String(row.get("label", "riga non trovata")) if not row.is_empty()
			else "riga non trovata"])
	return {
		"ended": state.solo_ended,
		"reason": state.solo_end_reason,
		"stopped": stopped_reason,
		"declared_gap": declared_gap,
		"turns": turns,
		"bot_turns": bot_turns,
		"player_turns": player_turns,
		"battles": battles,
		"completions": completions,
		"debriefing": debrief,
		"transcript": transcript,
	}


## Posizione in cui nessuna condizione di fine stampata potra' mai avverarsi.
##
## In BL1 succede davvero: la fine chiede "due o meno marker Rendezvous E
## nessuna Task Force tedesca in gioco" (p.5), ma un marker RV si rimuove solo
## con un Controllo Rifornimento, che a sua volta richiede una Stazione
## tedesca. Senza Task Force e senza Gruppi di Rinforzo, i tre marker restano
## sul tabellone per sempre. Il fascicolo non prevede questo caso: il replay lo
## dichiara invece di girare a vuoto, e la riga resta nel registro come lacuna
## nota, non come un difetto del motore.
func _declared_stall() -> String:
	if not state.forces_of(player_side).is_empty():
		return ""
	if _has_available_reinforcements():
		return ""
	if not scenario.id.begins_with("BL1"):
		return ""
	if state.rendezvous_markers.size() <= 2:
		return ""
	return ("il giocatore non ha piu' Task Force ne' Gruppi di Rinforzo e "
		+ "restano %d marker Rendezvous: la condizione di fine stampata "
		+ "(due o meno marker E nessuna TF tedesca) non puo' piu' avverarsi.") \
		% state.rendezvous_markers.size()


func _has_available_reinforcements() -> bool:
	var prefix := "KM" if player_side == TaskForce.Side.KRIEGSMARINE else "RN"
	var ports := scenario.reinforcement_ports()
	for k_v: Variant in scenario.reinforcements.keys():
		var group := String(k_v)
		if not group.begins_with(prefix) or not ports.has(group):
			continue
		if not (scenario.reinforcements[k_v] as Array).is_empty():
			return true
	return false


# ------------------------------------------- turno dell'avversario immaginario --

## Mirror headless di `ui/main.gd::_solo_roll_action(auto = true)`.
func _bot_turn() -> void:
	solo.set_phase(state.solo_phase, state.solo_phase_reason)
	var tid := solo.action_table_id()
	var t := solo.table(tid)
	if t == null:
		_line("BOT: lo scenario non ha una Tabella delle Azioni; il turno passa.")
		_give_initiative_to(player_side)
		return
	var inferred := SoloAI.automatic_modifiers(t, state, imaginary_side)
	for line_v: Variant in inferred["explanations"]:
		_line("BOT   modificatore automatico: %s" % String(line_v))
	for line_v: Variant in inferred["unresolved"]:
		_line("BOT   dato non modellato, modificatore non applicato: %s"
			% String(line_v))
	var selector := solo.action_row_selector(state, player_side, tid)
	var result := solo.act(state.rng, selector, inferred["active"])
	state.set_modifier_track(imaginary_side, int(result.get("modifier", 0)))
	_line("BOT - %s (%s)" % [t.title,
		solo.action_row_selector_label(state, player_side, tid)])
	for line in SoloTable.describe(result).split("\n"):
		_line("BOT   " + line)
	_apply_bot_result(result)


func _apply_bot_result(result: Dictionary) -> void:
	if String(result.get("code", "")).to_upper() == "I":
		_maybe_go_late("result_i", "la Tabella Azioni ha dato I")
	var decision := SoloAI.execute_code(String(result.get("code", "")), state,
		graph, engine, port_control, imaginary_side)
	_apply_bot_decision(result, decision, 0)


## Mirror headless di `ui/main.gd::_apply_solo_ai_decision`.
##
## `depth` conta le continuazioni prescritte sulla stessa uscita della Tabella:
## il fascicolo ne stampa due al massimo, e una ricorsione che non si ferma e'
## un difetto, non un ciclo di gioco.
func _apply_bot_decision(result: Dictionary, decision: Dictionary,
		depth: int) -> void:
	for line_v: Variant in decision.get("log", []):
		_line("BOT   " + String(line_v))
	var code := String(result.get("code", "?"))
	if bool(decision.get("completion", false)):
		if _inactive_steals("Completamento del bot"):
			_line("BOT   Completamento impedito dal cambio d'Iniziativa.")
			_bot_time_lapse(decision.get("active", null),
				decision.get("target_hex", Vector2i.MAX))
			return
		var active: TaskForce = decision["active"]
		var comp := Completion.resolve(active, decision["completion_port"],
			vp_tracker)
		for line_v2: Variant in comp.get("log", []):
			_line("BOT   " + String(line_v2))
		if bool(comp.get("ok", false)):
			completions += 1
		return
	if String(decision.get("action_key", "")) != "":
		_resolve_bot_action(decision)
		return
	if not bool(decision.get("ok", false)):
		# Nessun effetto applicabile: il bot non puo' restare fermo con
		# l'Iniziativa in mano, se no il ciclo si blocca.
		if not bool(decision.get("pass_initiative", false)):
			_line("BOT   risultato %s senza effetto applicabile: cede l'Iniziativa." % code)
			_give_initiative_to(player_side)
			return
	if bool(decision.get("time_lapse_before_pass", false)):
		_line("BOT   Completamento impossibile: esegue Passare e Scorrere del Tempo.")
		_bot_time_lapse(decision.get("active", null))
	if bool(decision.get("roll_again", false)):
		_line("BOT   la tabella ordina un altro tiro immediato.")
		if not state.solo_ended:
			_bot_turn()
		return
	if String(decision.get("turn_kind", "")) == "trajectory":
		_bot_time_lapse(decision.get("active", null),
			decision.get("target_hex", Vector2i.MAX))
		if _inactive_steals("Traiettoria del bot"):
			return
		var follow: Dictionary = decision.get("follow_up", {})
		if not follow.is_empty() and depth < MAX_FOLLOW_UPS:
			_line("BOT   continua la procedura prescritta senza ritirare la Tabella.")
			var next := SoloAI.continue_follow_up(decision, state, graph, engine,
				port_control, imaginary_side)
			_apply_bot_decision(result, next, depth + 1)
		return
	if bool(decision.get("pass_initiative", false)):
		_give_initiative_to(player_side)


## Mirror headless di `ui/main.gd::_resolve_solo_ai_action`.
func _resolve_bot_action(decision: Dictionary) -> void:
	var key := String(decision.get("action_key", ""))
	var active: TaskForce = decision.get("active", null)
	var target: TaskForce = decision.get("target", null)
	if active == null or target == null:
		_line("BOT   azione incompleta: manca la TF attiva o il bersaglio.")
		_give_initiative_to(player_side)
		return
	var dec := ActionEngine.Declaration.new()
	dec.action_key = key
	dec.active = active
	dec.target = target
	dec.launch_hex = decision.get("launch_hex", Vector2i.MAX)
	dec.target_hex = decision.get("target_hex", Vector2i.MAX)
	var res := engine.resolve(dec, state)
	var label := String(engine.action(key).get("label", key))
	if not bool(res["ok"]):
		_line("BOT   %s rifiutata: %s" % [label, String(res["error"])])
		_give_initiative_to(player_side)
		return
	_line("BOT   %s -> %s" % [label, engine.describe(res)])
	if _canceled_by_interruption(res):
		_line("BOT   azione annullata da Interruzione.")
		_apply_interruption_cancel(res, dec)
		return
	var pending := Results.Battle.NONE
	var initiative_changes := false
	for code_v: Variant in res["results"] as Array:
		var applied := Results.apply(String(code_v), active, target,
			dec.target_hex, state)
		_line("BOT     %s" % String(applied["text"]))
		if bool(applied.get("initiative_changes", false)):
			initiative_changes = true
		if applied["battle"] != Results.Battle.NONE:
			pending = applied["battle"]
	_report_eliminated("BOT - %s" % label)
	if key == "AIR_STRIKE":
		_maybe_go_late("air_strike", "il bot ha eseguito un Attacco Aereo")
	elif key == "STEALTH_ATTACK":
		_maybe_go_late("stealth_attack", "il bot ha eseguito un Attacco Furtivo")
	if pending != Results.Battle.NONE and not _prepare_battle(active, target):
		pending = Results.Battle.NONE
	if pending != Results.Battle.NONE:
		_maybe_go_late("battle", "un risultato del bot ha aperto una Battaglia")
		_run_battle(pending, active, target, dec.target_hex)
		return
	if bool(engine.action(key).get("causes_time_lapse", false)):
		_bot_time_lapse(active, dec.target_hex,
			dec.launch_hex if key == "AIR_STRIKE" else Vector2i.MAX)
	# RB p.53: certi risultati fanno CAMBIARE l'Iniziativa; non si Cerca, passa
	# e basta. Confonderli con una ricerca dell'Iniziativa e' un errore
	# silenzioso: il conteggio si comporta in modo diverso.
	if initiative_changes:
		_give_initiative_to(1 - active.side)
		return
	if key == "NAVAL_SEARCH":
		_inactive_steals("Ricerca Navale del bot")
	else:
		_seek_initiative("BOT")


# --------------------------------------------------- turno del giocatore --

## POLICY DELL'HARNESS, non una regola del fascicolo: vedi l'intestazione.
func _player_turn() -> void:
	# Il Controllo Rifornimento di BL1 non e' una scelta: e' obbligatorio non
	# appena il tedesco ha l'Iniziativa e una sua Stazione occupa un RV
	# (AC Solo scenarios 2022 p.6). Va quindi prima dell'azione.
	_bl1_fueling_checks()
	var forces := state.forces_of(player_side)
	if forces.is_empty():
		# Restare senza Task Force non e' la fine dello scenario: i Gruppi di
		# Rinforzo sono ancora nella loro Casella Porto e si chiamano con
		# Riorganizzare (RB p.37). Se non ce ne sono piu', la partita e'
		# davvero ferma, e va detto invece di consumare i turni rimasti.
		if _player_reinforce():
			return
		_line("GIOCATORE (policy harness): nessuna Task Force in gioco e "
			+ "nessun Gruppo di Rinforzo disponibile; Passa.")
		_give_initiative_to(imaginary_side)
		return
	# L'ordine e' quello dell'obiettivo stampato di BL1 e BL2: un Convoglio
	# arriva in porto, un cacciatore va a caccia di Convogli, e si rientra
	# soltanto quando non resta niente da fare. Un giocatore che Completa alla
	# prima occasione toglie dalla mappa proprio le navi che devono agire, e il
	# replay non arriverebbe mai a meta' partita.
	if _player_completion(true):
		return
	if _player_attack():
		return
	# Il rientro va tentato PRIMA della Traiettoria, non dopo: una TF che puo'
	# sempre allungare di un segmento non arriva mai all'ultima riga, e resta a
	# fare avanti e indietro fra due porti fino al limite dei turni. E' successo
	# davvero con il seme 42.
	var going_home := not _enemy_convoy_in_play() \
		or bool(state.solo_counters.get("bl1_fuel_limits", false))
	if going_home and _player_completion(false):
		return
	if _player_trajectory():
		return
	if _player_completion(false):
		return
	_line("GIOCATORE (policy harness): Passare.")
	_player_time_lapse(_player_main_force())
	_seek_initiative("GIOCATORE")


## BL1 p.6: "you must roll a die and apply the result on the Fueling Table".
## Il ciclo si ripete finche' ci sono candidati, perche' un risultato puo'
## spostare l'RV su un altro esagono con un'altra Stazione tedesca.
func _bl1_fueling_checks() -> void:
	var table := solo.table("fueling")
	if table == null:
		return
	var candidates := SoloAI.bl1_fueling_candidates(state)
	var guard := 0
	while not candidates.is_empty() and guard < 10:
		guard += 1
		var tf: TaskForce = candidates[0]
		var h := tf.trajectory.station_hex
		var result := table.roll_and_read(state.rng, state.weather, [])
		state.set_modifier_track(TaskForce.Side.KRIEGSMARINE,
			int(result.get("modifier", 0)))
		_line("RIFORNIMENTO obbligatorio: %s e' una Stazione sul marker RV in %s."
			% [tf.display_name(), str(h)])
		for line in SoloTable.describe(result).split("\n"):
			_line("   " + line)
		var applied := SoloAI.apply_table_result("fueling", result, state, graph,
			engine, port_control, player_side, tf)
		for line_v: Variant in applied.get("log", []):
			_line("   " + String(line_v))
		if not bool(applied.get("ok", false)):
			break
		if String(applied.get("initiative", "")) == "vie":
			_seek_initiative("RIFORNIMENTO")
		candidates = SoloAI.bl1_fueling_candidates(state)


## Chiama il primo Gruppo di Rinforzo del giocatore che abbia ancora navi e un
## porto trascritto. Un gruppo senza porto NON viene fatto entrare a caso: il
## dato manca ed e' un buco dichiarato, non una posizione da indovinare.
func _player_reinforce() -> bool:
	var prefix := "KM" if player_side == TaskForce.Side.KRIEGSMARINE else "RN"
	var ports := scenario.reinforcement_ports()
	for k_v: Variant in scenario.reinforcements.keys():
		var group := String(k_v)
		if not group.begins_with(prefix):
			continue
		var ships: Array = scenario.reinforcements[k_v]
		if ships.is_empty():
			continue
		if not ports.has(group):
			_line("GIOCATORE (policy harness): il Gruppo %s non ha un porto "
				% group + "trascritto; non viene fatto entrare.")
			continue
		var port := graph.port_hex(String(ports[group]))
		if port == Vector2i.MAX:
			continue
		var r := Reorganize.attempt_reinforcement(state, player_side, port,
			ships, group)
		if not bool(r["ok"]):
			_line("GIOCATORE (policy harness): Rinforzi %s rifiutati: %s"
				% [group, String(r["error"])])
			continue
		_line("GIOCATORE (policy harness): tentativo di Rinforzo %s." % group)
		for line_v: Variant in r["log"]:
			_line("GIOCATORE   " + String(line_v))
		if bool(r["success"]):
			var leaders := scenario.reinforcement_leaders()
			var new_tf: TaskForce = r.get("tf", null)
			if leaders.has(group) and new_tf != null:
				new_tf.leader = String(leaders[group])
			scenario.reinforcements[k_v] = []
			_seek_initiative("GIOCATORE")
		elif bool(r["initiative_passes"]):
			_player_time_lapse(_player_main_force())
			var passed := Initiative.pass_to_inactive(state)
			for line_v2: Variant in passed["log"]:
				_line("GIOCATORE   " + String(line_v2))
		return true
	return false


## `convoys_only` distingue le due occasioni in cui il giocatore simulato
## Completa: la prima e' il mestiere di un Convoglio, la seconda e' il rientro
## quando non c'e' piu' niente da fare.
func _player_completion(convoys_only: bool) -> bool:
	for tf in state.forces_of(player_side):
		if not _player_may_declare(tf, "COMPLETION"):
			continue
		if convoys_only and not _carries_convoy(tf):
			continue
		var why := Completion.refusal(tf, graph, port_control)
		if why != "":
			# Il motivo va scritto: una TF ferma in porto che non Completa mai
			# e' esattamente il caso che ha fatto girare a vuoto il replay, e
			# senza questa riga non si capiva perche'.
			if not convoys_only and not graph.ports_in(_anchor(tf)).is_empty():
				_line("GIOCATORE (policy harness): %s e' in un esagono di porto "
					% tf.display_name() + "ma non puo' Completare: %s." % why)
			continue
		var options := Completion.port_options(tf, graph, port_control)
		if options.is_empty():
			continue
		_line("GIOCATORE (policy harness): Completamento di %s a %s."
			% [tf.display_name(), String(options[0]["name"])])
		if _inactive_steals("Completamento del giocatore"):
			_line("GIOCATORE   Completamento impedito dal cambio d'Iniziativa.")
			return true
		var comp := Completion.resolve(tf, options[0], vp_tracker)
		for line_v: Variant in comp.get("log", []):
			_line("GIOCATORE   " + String(line_v))
		if bool(comp.get("ok", false)):
			completions += 1
		return true
	return false


## L'obiettivo stampato di BL1 e' "Score Hits on British Convoys. Under no
## circumstances, however, are you to lose a German vessel" (p.5); quello di BL2
## e' "Score Hits on German Convoys ... Sink German raiders" (p.9). In tutti e
## due i casi il bersaglio giusto e' il Convoglio: attaccare la corazzata
## nemica perche' capita nello stesso esagono e' esattamente la mossa che il
## fascicolo scoraggia, e nel primo replay costava la partita al turno uno.
func _player_attack() -> bool:
	for convoys_first in [true, false]:
		for tf in state.forces_of(player_side):
			if _carries_convoy(tf):
				continue      # una TF che scorta non caccia (RB p.11)
			for key in ["ENGAGE", "NAVAL_SEARCH"]:
				if not _player_may_declare(tf, key):
					continue
				for enemy in state.forces_of(imaginary_side):
					if convoys_first != _carries_convoy(enemy):
						continue
					var dec := ActionEngine.Declaration.new()
					dec.action_key = key
					dec.active = tf
					dec.target = enemy
					dec.target_hex = _shared_hex(tf, enemy)
					if dec.target_hex == Vector2i.MAX:
						continue
					if engine.legality_error(dec, state) != "":
						continue
					if not convoys_first and not _worth_attacking(tf, enemy):
						continue
					_line("GIOCATORE (policy harness): %s con %s contro %s."
						% [String(engine.action(key).get("label", key)),
							tf.display_name(), enemy.display_name()])
					_resolve_player_action(dec)
					return true
	return false


## Una TF senza Convoglio attacca un'altra TF senza Convoglio solo se non ci
## rimette: nessuna nave nemica di classe superiore e nessuna nave propria gia'
## danneggiata. Non e' una regola, e' la prudenza che l'obiettivo chiede.
func _worth_attacking(mine: TaskForce, enemy: TaskForce) -> bool:
	var heavy := ["BB", "BC"]
	for s in mine.afloat_ships():
		if s.damaged:
			return false
	for s in enemy.afloat_ships():
		if heavy.has(s.type_code):
			for own in mine.afloat_ships():
				if heavy.has(own.type_code):
					return true
			return false
	return true


func _enemy_convoy_in_play() -> bool:
	for tf in state.forces_of(imaginary_side):
		if _carries_convoy(tf):
			return true
	return false


func _carries_convoy(tf: TaskForce) -> bool:
	for s in tf.afloat_ships():
		if s.kind == Ship.Kind.CONVOY:
			return true
	return false


func _resolve_player_action(dec: ActionEngine.Declaration) -> void:
	var key := dec.action_key
	var res := engine.resolve(dec, state)
	var label := String(engine.action(key).get("label", key))
	if not bool(res["ok"]):
		_line("GIOCATORE   %s rifiutata: %s" % [label, String(res["error"])])
		_give_initiative_to(imaginary_side)
		return
	_line("GIOCATORE   %s -> %s" % [label, engine.describe(res)])
	if _canceled_by_interruption(res):
		_line("GIOCATORE   azione annullata da Interruzione.")
		_apply_interruption_cancel(res, dec)
		return
	var pending := Results.Battle.NONE
	var initiative_changes := false
	for code_v: Variant in res["results"] as Array:
		var applied := Results.apply(String(code_v), dec.active, dec.target,
			dec.target_hex, state)
		_line("GIOCATORE     %s" % String(applied["text"]))
		if bool(applied.get("initiative_changes", false)):
			initiative_changes = true
		if applied["battle"] != Results.Battle.NONE:
			pending = applied["battle"]
	_report_eliminated("GIOCATORE - %s" % label)
	if key == "AIR_STRIKE":
		_maybe_go_late("air_strike", "il giocatore ha eseguito un Attacco Aereo")
	elif key == "STEALTH_ATTACK":
		_maybe_go_late("stealth_attack", "il giocatore ha eseguito un Attacco Furtivo")
	if pending != Results.Battle.NONE and not _prepare_battle(dec.active, dec.target):
		pending = Results.Battle.NONE
	if pending != Results.Battle.NONE:
		_maybe_go_late("battle", "un risultato del giocatore ha aperto una Battaglia")
		_bl2_neutral_incident(key, dec.active, dec.target_hex)
		_run_battle(pending, dec.active, dec.target, dec.target_hex)
		return
	_bl2_neutral_incident(key, dec.active, dec.target_hex)
	if bool(engine.action(key).get("causes_time_lapse", false)):
		_player_time_lapse(dec.active, dec.target_hex)
	if initiative_changes:
		_give_initiative_to(1 - dec.active.side)
		return
	_seek_initiative("GIOCATORE")


## Allunga la Traiettoria verso l'avversario piu' vicino e poi Scorre il Tempo.
## E' l'azione Traiettoria: la rotta la calcola `SoloAI.best_route`, la stessa
## usata dal bot, per non avere due pianificatori diversi.
func _player_trajectory() -> bool:
	var tf := _player_main_force()
	if tf == null or not _player_may_declare(tf, "TRAJECTORY"):
		return false
	var goal := _player_goal(tf)
	if goal == Vector2i.MAX:
		_line("GIOCATORE (policy harness): %s non ha un obiettivo raggiungibile."
			% tf.display_name())
		return false
	var plan := SoloAI.best_route(state, graph, tf, goal)
	if plan.is_empty():
		_line("GIOCATORE (policy harness): nessuna rotta legale da %s verso %s."
			% [str(_anchor(tf)), str(goal)])
		return false
	var end := int(plan["end"])
	var was_station := tf.trajectory.is_station()
	var added := 0
	for h_v: Variant in plan["steps"] as Array:
		if tf.length() >= Trajectory.MAX_SEGMENTS:
			break
		var h: Vector2i = h_v
		var info := state.triggers_info(h, tf.side)
		if not tf.trajectory.extend(h, end, graph, state.port_hexes(), info,
				tf.side):
			break
		added += 1
		if was_station:
			end = 1
			was_station = false
	if added == 0:
		_line("GIOCATORE (policy harness): %s non puo' estendere la Traiettoria "
			% tf.display_name() + "verso %s (%d segmenti attuali)."
			% [str(goal), tf.length()])
		return false
	_line("GIOCATORE (policy harness): Traiettoria di %s, %d segmenti verso %s."
		% [tf.display_name(), added, str(goal)])
	_player_time_lapse(tf, goal)
	_seek_initiative("GIOCATORE")
	return true


## Il giocatore simulato rispetta i vincoli di scenario che il core conosce:
## oggi i Limiti di Carburante di BL1 e le restrizioni per TF (Guasti
## Meccanici). Non e' una scelta tattica, e' una regola stampata.
func _player_may_declare(tf: TaskForce, key: String) -> bool:
	var allowed: Array = tf.solo_flags.get("bl1_actions_only", [])
	if not allowed.is_empty() and not allowed.has(key):
		return false
	if bool(state.solo_counters.get("bl1_fuel_limits", 0)) \
			and not ["COMPLETION", "PASS", "TRAJECTORY"].has(key):
		return false
	return true


func _player_main_force() -> TaskForce:
	var best: TaskForce = null
	for tf in state.forces_of(player_side):
		if best == null or tf.id < best.id:
			best = tf
	return best


# --------------------------------------------------------- pezzi comuni --

func _canceled_by_interruption(res: Dictionary) -> bool:
	var ir: Dictionary = res.get("interruption", {})
	return not ir.is_empty() and bool(ir.get("triggered", false)) \
		and int(ir.get("result", Interruption.Result.ALERT)) \
			!= Interruption.Result.ALERT


## Le tre uscite dell'Interruzione che annullano l'azione (RB p.22). Sfuggire
## chiede una scelta all'Inattivo: nel replay non la si finge, la si dichiara.
func _apply_interruption_cancel(res: Dictionary,
		dec: ActionEngine.Declaration) -> void:
	var ir: Dictionary = res.get("interruption", {})
	_line("      %s" % String(ir.get("effect", "Azione annullata.")))
	match int(ir.get("result", Interruption.Result.ALERT)):
		Interruption.Result.SLIP_AWAY:
			_line("      Sfuggire: l'effetto scelto dall'Inattivo non e' "
				+ "automatizzato nel replay; si Cerca l'Iniziativa.")
			_seek_initiative("Interruzione")
		Interruption.Result.VIE_FOR_INITIATIVE:
			_seek_initiative("Interruzione")
		Interruption.Result.INITIATIVE_CHANGE:
			_give_initiative_to(1 - dec.active.side)


func _seek_initiative(who: String) -> bool:
	var r := Initiative.seek(state)
	for line_v: Variant in r["log"]:
		_line("%s   %s" % [who, String(line_v)])
	return bool(r.get("changed", false))


## L'Inattivo tenta di Sottrarre. Se e' l'avversario immaginario lo fa sempre
## (e' la regola solitaria applicata da `ui/main.gd`); se e' il giocatore
## simulato, decide `player_steals_initiative`.
func _inactive_steals(reason: String) -> bool:
	var inactive := 1 - state.initiative
	if inactive == player_side and not player_steals_initiative:
		_line("   %s: il giocatore simulato rinuncia a Sottrarre." % reason)
		return false
	var r := Initiative.steal(state)
	for line_v: Variant in r["log"]:
		_line("   %s" % String(line_v))
	return bool(r.get("changed", false))


func _give_initiative_to(side: int) -> void:
	if state.initiative == side:
		return
	state.initiative = side
	state.initiative_count = 0
	var w := Initiative.weather_check(state)
	_line("   L'Iniziativa passa a %s; il conteggio torna a zero."
		% Initiative.side_name(side))
	_line("   %s" % String(w["log"]))


## Scorrere del Tempo del bot: stessa scelta deterministica di `ui/main.gd`,
## cioe' il capo piu' lontano dall'obiettivo dichiarato dalla procedura.
func _bot_time_lapse(tf: TaskForce, goal: Vector2i = Vector2i.MAX,
		protected_hex: Vector2i = Vector2i.MAX) -> void:
	_time_lapse(tf, goal, protected_hex, "BOT")


func _player_time_lapse(tf: TaskForce, goal: Vector2i = Vector2i.MAX) -> void:
	_time_lapse(tf, goal, Vector2i.MAX, "GIOCATORE")


func _time_lapse(tf: TaskForce, goal: Vector2i, protected_hex: Vector2i,
		who: String) -> void:
	if tf == null or tf.trajectory.is_station():
		return
	var amount := TimeLapse.required_removal(tf.speed, state.weather, state.rng)
	var opts := TimeLapse.removal_options(tf.trajectory, tf.speed, amount,
		protected_hex)
	if opts.is_empty():
		_line("%s   Scorrere del Tempo: nessuna rimozione legale." % who)
		return
	var chosen: Dictionary = opts[0]
	var best := -INF
	for option in opts:
		var ends: Array = option["ends"]
		var d0 := Hex.distance(tf.trajectory.end_hex(0), goal) \
			if goal != Vector2i.MAX else 0
		var d1 := Hex.distance(tf.trajectory.end_hex(1), goal) \
			if goal != Vector2i.MAX else 0
		var score := float(int(ends[0]) * d0 + int(ends[1]) * d1)
		if score > best:
			best = score
			chosen = option
	var freed := TimeLapse.apply(tf.trajectory, chosen)
	var station_note := ""
	if tf.trajectory.length() == 0 and not freed.is_empty():
		var pick := freed[0]
		if protected_hex != Vector2i.MAX and freed.has(protected_hex):
			pick = protected_hex
		elif goal != Vector2i.MAX:
			for h in freed:
				if Hex.distance(h, goal) < Hex.distance(pick, goal):
					pick = h
		tf.trajectory.become_station(pick)
		station_note = "; Stazione in %s" % str(pick)
	_line("%s   Scorrere del Tempo: %s rimuove %s%s." % [who,
		tf.display_name(), String(chosen["label"]), station_note])


func _report_eliminated(reason: String) -> void:
	for loss in state.remove_eliminated_forces(reason):
		_line("   TF rimossa dalla mappa: %s (nessuna nave a galla)."
			% String(loss.get("tf_name", "Task Force")))
		if int(loss.get("convoys", 0)) > 0:
			_maybe_go_late("convoy_destroyed", "un Convoglio e' stato distrutto")


func _maybe_go_late(event: String, reason: String) -> bool:
	if state.solo_phase == SoloOpponent.Phase.LATE:
		return false
	if not solo.goes_late_after(event):
		return false
	state.solo_phase = SoloOpponent.Phase.LATE
	state.solo_phase_reason = reason
	solo.set_phase(state.solo_phase, state.solo_phase_reason)
	_line("   Solitario: passa alla tabella Tardi: %s." % reason)
	return true


## BL2 p.11: Ingaggiare o Attacco Aereo britannico dentro le Acque Neutrali
## tirano l'Incidente Internazionale dopo la risoluzione.
func _bl2_neutral_incident(key: String, active: TaskForce,
		target_hex: Vector2i) -> void:
	if scenario.id != "BL2 Contain and Destroy" or active == null \
			or active.side != TaskForce.Side.ROYAL_NAVY \
			or not ["ENGAGE", "AIR_STRIKE"].has(key):
		return
	if not SoloAI.bl2_is_neutral_water(scenario.rules(), target_hex):
		return
	if not solo.has("incident"):
		_line("   BL2: Incidente Internazionale richiesto, tabella non disponibile.")
		return
	var roll := (solo.table("incident") as SoloTable).roll_and_read(state.rng, 0)
	_line("   BL2 - Incidente Internazionale nelle Acque Neutrali")
	for line in SoloTable.describe(roll).split("\n"):
		_line("     " + line)
	var applied := SoloAI.apply_table_result("incident", roll, state, graph,
		engine, port_control, player_side)
	for line_v: Variant in applied.get("log", []):
		_line("     " + String(line_v))


# ------------------------------------------------------------- Battaglia --

## Identificazione automatica prima della Mappa di Battaglia (regola solitaria
## generale). False = la Battaglia non si apre, e va detto perche'.
func _prepare_battle(active: TaskForce, target: TaskForce) -> bool:
	for tf_v: Variant in [active, target]:
		var tf: TaskForce = tf_v
		var identified := SoloAI.identify_for_battle(solo, state, graph, engine,
			port_control, tf)
		if not bool(identified.get("needed", false)):
			continue
		_line("   Identificazione automatica di %s prima della Battaglia."
			% tf.display_name())
		var roll: Dictionary = identified.get("roll", {})
		if not roll.is_empty():
			for line in SoloTable.describe(roll).split("\n"):
				_line("     " + line)
		for line_v: Variant in identified.get("log", []):
			if String(line_v) != "":
				_line("     " + String(line_v))
		if not bool(identified.get("ok", false)):
			_line("   Battaglia non aperta: identificazione non applicabile.")
			return false
	return true


## La Battaglia headless. Entrambe le parti usano `SoloBattle`: in solitario il
## bot decide da solo, e il giocatore simulato usa la stessa dottrina invece di
## una tattica inventata qui.
func _run_battle(kind_result: int, active: TaskForce, target: TaskForce,
		hex: Vector2i) -> void:
	if active.afloat_ships().is_empty() or target.afloat_ships().is_empty():
		_line("   Battaglia non aperta: una delle due TF non ha navi.")
		return
	var kind := BattleState.Kind.BATTLE
	if kind_result == Results.Battle.SURPRISE:
		kind = BattleState.Kind.SURPRISE
	elif kind_result == Results.Battle.LIMITED:
		kind = BattleState.Kind.LIMITED
	var bs := BattleState.new(kind, state.weather)
	bs.advanced = state.advanced_battle
	bs.active_tf = active
	bs.target_tf = target
	bs.hex = hex
	var b := Battle.new(bs, state.rng, vp_tracker)
	b.start()
	battles += 1
	_line("   %s aperta in %s." % [BattleState.KIND_LABELS[kind], str(hex)])
	var steps := 0
	while not bs.ended and steps < MAX_BATTLE_STEPS:
		steps += 1
		_battle_step(b, bs)
	if steps >= MAX_BATTLE_STEPS:
		stopped_reason = "la Battaglia non e' terminata entro %d fasi" % MAX_BATTLE_STEPS
		_line("   INTERROTTO: %s" % stopped_reason)
	var out := b.finish()
	for line in bs.log:
		_line("     " + line)
	for t_v: Variant in (out["sunk"] as Array):
		_line("     affondata: %s" % String(t_v))
	_line("   Battaglia conclusa: %s" % bs.end_reason)
	_report_eliminated("Battaglia")
	_seek_initiative("Battaglia")


func _battle_step(b: Battle, bs: BattleState) -> void:
	match bs.phase:
		BattleState.Phase.ATTITUDE:
			if not b.pending_snafu.is_empty():
				var candidates: Array = b.pending_snafu.get("candidates", [])
				# La scelta e' del giocatore Bersaglio: nel replay si prende la
				# prima nave, deterministicamente, e lo si scrive.
				b.resolve_snafu_choice(candidates[0] if not candidates.is_empty()
					else null)
			var choices := SoloBattle.attitude_choices(bs, imaginary_side)
			for ship_v: Variant in SoloBattle.attitude_choices(bs, player_side).keys():
				choices[ship_v] = SoloBattle.attitude_choices(bs, player_side)[ship_v]
			b.attitude_phase(choices)
			if not bs.ended:
				bs.phase = BattleState.Phase.GUNNERY
		BattleState.Phase.GUNNERY:
			var g := SoloBattle.targeting(bs, imaginary_side)
			g.merge(SoloBattle.targeting(bs, player_side))
			b.gunnery_phase(g)
			if not bs.ended:
				bs.phase = BattleState.Phase.TORPEDO
		BattleState.Phase.TORPEDO:
			var t := SoloBattle.targeting(bs, imaginary_side, true)
			t.merge(SoloBattle.targeting(bs, player_side, true))
			b.torpedo_phase(t)
			if not bs.ended:
				bs.phase = BattleState.Phase.MANEUVER
		BattleState.Phase.MANEUVER:
			var m := SoloBattle.maneuver_moves(bs, imaginary_side)
			m.merge(SoloBattle.maneuver_moves(bs, player_side))
			b.maneuver_phase(m)
			if not bs.ended:
				bs.phase = bs.next_phase()
		BattleState.Phase.LINGERING:
			b.lingering_phase([])
			if not bs.ended:
				bs.phase = BattleState.Phase.BREAK_AWAY
		BattleState.Phase.BREAK_AWAY:
			var active_runs := bs.active_tf != null \
				and SoloBattle.wants_break_away(bs, bs.active_tf.side)
			var target_runs := bs.target_tf != null \
				and SoloBattle.wants_break_away(bs, bs.target_tf.side)
			b.break_away_phase(active_runs, target_runs)
			if not bs.ended:
				b.end_round()
		_:
			bs.end_battle("fase non gestita dal replay: %d" % bs.phase)


# ------------------------------------------------------------- strumenti --

func _shared_hex(a: TaskForce, b: TaskForce) -> Vector2i:
	if a == null or b == null:
		return Vector2i.MAX
	var hs := a.trajectory.hexes()
	if a.trajectory.is_station():
		hs.append(a.trajectory.station_hex)
	for h in hs:
		if b.trajectory.occupies(h):
			return h
	return Vector2i.MAX


## Dove punta la Traiettoria del giocatore simulato, in ordine di priorita':
##
##   1. il porto di destinazione, se la TF scorta un Convoglio;
##   2. un marker Rendezvous ancora attivo e ancora utilizzabile da questa TF
##      (in BL1 sono il carburante, e il Controllo Rifornimento e' l'unico modo
##      di toglierli dal tabellone);
##   3. il Convoglio nemico piu' vicino, che e' l'obiettivo stampato;
##   4. il porto amico piu' vicino: finiti i Convogli da cacciare, si rientra.
##
## Il punto 4 non e' un ripiego estetico: senza, una TF senza bersagli resta
## parcheggiata a Passare per sempre, e in BL1 la condizione di fine ("nessuna
## TF tedesca in gioco") non si avvera mai.
func _player_goal(tf: TaskForce) -> Vector2i:
	var from := _anchor(tf)
	# Il "Nuovo Obiettivo" del risultato a. del Rifornimento chiude tutti gli
	# altri porti a questa TF (BL1 p.6): puntare al porto amico piu' vicino la
	# faceva navigare avanti e indietro fra Kiel e Wilhelmshaven senza poter
	# mai Completare, ed e' il difetto che il seme 1 ha fatto emergere.
	var granted := String(tf.solo_flags.get("bl1_completion_port", ""))
	if granted != "":
		var granted_hex := graph.port_hex(granted)
		if granted_hex != Vector2i.MAX and granted_hex != from:
			return granted_hex
	if _carries_convoy(tf):
		var port := _convoy_destination_hex(tf)
		if port != Vector2i.MAX:
			return port
	# Con i Limiti di Carburante in vigore restano solo Completamento, Passare
	# e Traiettoria (BL1 p.8): l'unica rotta che ha ancora senso e' quella di
	# casa.
	if bool(state.solo_counters.get("bl1_fuel_limits", false)):
		return _nearest_friendly_port_hex(from)
	var rv := _nearest_rendezvous(tf, from)
	if rv != Vector2i.MAX:
		return rv
	var bestd := 9999
	var best := Vector2i.MAX
	for enemy in state.forces_of(imaginary_side):
		if not _carries_convoy(enemy):
			continue
		var h := _anchor(enemy)
		var d := Hex.distance(from, h)
		if d < bestd and h != from:
			bestd = d
			best = h
	if best != Vector2i.MAX:
		return best
	return _nearest_friendly_port_hex(from)


func _convoy_destination_hex(tf: TaskForce) -> Vector2i:
	for port_v: Variant in tf.solo_flags.get("completion_ports", []):
		var h := graph.port_hex(String(port_v))
		if h != Vector2i.MAX:
			return h
	return Vector2i.MAX


## Un marker gia' consumato da questa TF (`bl1_no_more_fueling`) o l'esagono in
## cui la TF si trova gia' non sono obiettivi: puntarci significa chiedere una
## rotta di lunghezza zero e restare fermi.
func _nearest_rendezvous(tf: TaskForce, from: Vector2i) -> Vector2i:
	if bool(tf.solo_flags.get("bl1_no_more_fueling", false)):
		return Vector2i.MAX
	var best := Vector2i.MAX
	var bestd := 9999
	for rv in state.rendezvous_markers:
		if not bool(rv.get("active", true)):
			continue
		var h := Vector2i(int(rv.get("q", 0)), int(rv.get("r", 0)))
		if h == from or not graph.is_playable(h):
			continue
		var d := Hex.distance(from, h)
		if d < bestd:
			bestd = d
			best = h
	return best


func _nearest_friendly_port_hex(from: Vector2i) -> Vector2i:
	var best := Vector2i.MAX
	var bestd := 9999
	for pname_v: Variant in graph.ports.keys():
		var p: Dictionary = graph.ports[pname_v]
		var control := Completion.control_of(p, port_control)
		if control != "BOTH" and control != VictoryTracker.side_name(player_side):
			continue
		var h := graph.port_hex(String(pname_v))
		if h == Vector2i.MAX or h == from:
			continue
		var d := Hex.distance(from, h)
		if d < bestd:
			bestd = d
			best = h
	return best


func _anchor(tf: TaskForce) -> Vector2i:
	return tf.trajectory.station_hex if tf.trajectory.is_station() \
		else tf.trajectory.end_hex(0)


func _tf_position(tf: TaskForce) -> String:
	if tf.completed:
		return "Completata a %s" % tf.completed_port
	if tf.trajectory.is_station():
		return "Stazione in %s" % str(tf.trajectory.station_hex)
	return "Traiettoria di %d segmenti" % tf.length()


func _line(text: String) -> void:
	transcript.append(text)
