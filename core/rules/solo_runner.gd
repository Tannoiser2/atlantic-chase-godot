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

## I quindici scenari solitari e il seme con cui sono FISSATI.
##
## Stanno qui e non nei due strumenti che li usano - `tools/replay_solo.gd` e
## `tools/bless_replays.gd` - perche' un elenco in due copie e' un elenco che
## prima o poi ne contiene quattordici da una parte e quindici dall'altra.
const ALL_SOLO := [
	"BL1 Raiders of the North Atlantic", "BL2 Contain and Destroy",
	"BL3 Raiders of the North Sea", "N1 Operazione Wilfred",
	"N2 Operazione Weser (nord)", "N3 Operazione Weser (sud)",
	"N4 Operazione Weser (nord & sud)", "N5 Meglio Tardi che Mai",
	"N6 Il Dilemma delle Operazioni", "B1 Operazione Berlino",
	"B2 La Battaglia dell'Atlantico", "B3 Operazione Reno",
	"B4 Decisione sui Mari", "A1 Convogli PQ", "A2 L'Ultima Battaglia",
]
const BLESSED_SEED := 20260803


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
	# Cinque scenari solitari si giocano su una mappa inserto, non sulla Mappa
	# Operazionale. La superficie va scelta prima di schierare: gli esagoni
	# esistono su tutte e due, quindi sbagliarla non da' errore, da' una partita
	# giocata sulle coordinate sbagliate.
	var inset := scenario.inset_key()
	graph = MapGraph.load_default() if inset == "" else MapGraph.load_inset(inset)
	if graph.load_error != "":
		load_error = "mappa non caricata per '%s': %s" % [scenario_id, graph.load_error]
		return false
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
			String(scenario.map_info.get("status", "schieramento non trascritto"))]
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
			_begin_player_turn()
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
	_bl1_murmansk_before_debriefing()
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
	# Il giocatore non ha ne' Task Force ne' Gruppi di Rinforzo: non puo' piu'
	# fare niente che avvicini una condizione di fine. Se la fine non e' gia'
	# scattata, non scattera' mai, e continuare a tirare la Tabella per il bot
	# non e' una partita: e' un ciclo che consuma turni.
	if state.solo_end_conditions.is_empty():
		return ("il giocatore non ha piu' Task Force ne' Gruppi di Rinforzo, e "
			+ "lo scenario non ha condizioni di fine trascritte.")
	if turns <= 1:
		# Non ne ha mai avute: e' lo schieramento a mancare, non la partita ad
		# essere finita male. A2 compra le proprie forze coi VP prima della
		# prima azione (p.63) e quel passaggio non e' modellato.
		return ("il giocatore non ha Task Force fin dall'inizio e non ha Gruppi "
			+ "di Rinforzo utilizzabili: lo schieramento di questo scenario non "
			+ "e' modellato, quindi non c'e' partita da giocare.")
	if scenario.id.begins_with("BL1"):
		return ("il giocatore non ha piu' Task Force ne' Gruppi di Rinforzo e "
			+ "restano %d marker Rendezvous: la condizione di fine stampata "
			+ "(due o meno marker E nessuna TF tedesca) non puo' piu' avverarsi.") \
			% state.active_rendezvous_count()
	return ("il giocatore non ha piu' Task Force ne' Gruppi di Rinforzo: "
		+ "nessuna condizione di fine stampata puo' piu' avverarsi.")


## Tira la rotta di un Gruppo di Rinforzo che non ha un porto fisso. La tabella
## e' nel dato (`reinforcement_routes`), qui c'e' solo il dado: la regola dice
## quali porti, non quando tirare.
func _rolled_reinforcement_route(group: String) -> Dictionary:
	var routes: Array = scenario.reinforcement_routes().get(group, [])
	if routes.is_empty():
		return {}
	var roll := state.rng.d6("Rotta del Gruppo di Rinforzo %s" % group)
	for entry_v: Variant in routes:
		var entry: Dictionary = entry_v
		if roll <= int(entry.get("max", 6)):
			return entry
	return routes[routes.size() - 1]


func _has_available_reinforcements() -> bool:
	var prefix := "KM" if player_side == TaskForce.Side.KRIEGSMARINE else "RN"
	var ports := scenario.reinforcement_ports()
	var routes := scenario.reinforcement_routes()
	for k_v: Variant in scenario.reinforcements.keys():
		var group := String(k_v)
		# Un Gruppo e' utilizzabile se ha un porto fisso OPPURE una rotta da
		# tirare: senza nessuno dei due il motore si rifiuta di farlo entrare,
		# perche' non sa dove metterlo.
		if not group.begins_with(prefix):
			continue
		if not ports.has(group) and not routes.has(group):
			continue
		if not (scenario.reinforcements[k_v] as Array).is_empty():
			return true
	return false


# ------------------------------------------- turno dell'avversario immaginario --

## Mirror headless di `ui/main.gd::_solo_roll_action(auto = true)`.
##
## Resta uno dei due punti ancora rispecchiati: qui si tira la Tabella e si
## scrivono i modificatori. Le REGOLE stanno in `SoloSequence` e in `SoloAI`;
## quello che diverge fra i due e' solo come si chiedono i modificatori - qui
## `ask_modifiers`, nella vista un dialogo.
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
	var chosen_mods := ask_modifiers(t, inferred)
	var result := solo.act(state.rng, selector, chosen_mods)
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


## Cammina i passi che `SoloSequence.steps_for` prescrive.
##
## L'ORDINE non e' piu' qui: era scritto due volte, una per ciclo, e le due
## copie erano gia' divergute sul tetto alle continuazioni. Qui resta solo come
## si ESEGUE un passo senza GUI - il che, per due passi su nove, vuol dire non
## fare niente.
func _apply_bot_decision(result: Dictionary, decision: Dictionary,
		depth: int) -> void:
	for step_v: Variant in SoloSequence.steps_for(decision, depth):
		var step: Dictionary = step_v
		match int(step["step"]):
			SoloSequence.Step.LOG:
				for line_v: Variant in step.get("lines", []):
					_line("BOT   " + String(line_v))
			SoloSequence.Step.STEAL_CHECK:
				if not _inactive_steals(String(step.get("label", ""))):
					continue
				var refused := String(step.get("refused", ""))
				if refused != "":
					_line("BOT   " + refused)
				for alt_v: Variant in step.get("on_steal", []):
					_run_bot_step(alt_v as Dictionary, result, decision)
				return
			_:
				if _run_bot_step(step, result, decision):
					return


## Un passo solo. Ritorna true se dopo di lui non si prosegue.
func _run_bot_step(step: Dictionary, result: Dictionary,
		decision: Dictionary) -> bool:
	match int(step["step"]):
		SoloSequence.Step.TIME_LAPSE:
			var note := String(step.get("note", ""))
			if note != "":
				_line("BOT   " + note)
			_bot_time_lapse(step.get("active", null),
				step.get("goal", Vector2i.MAX))
		SoloSequence.Step.COMPLETION:
			var comp := Completion.resolve(step["active"], step["port"],
				vp_tracker)
			for line_v: Variant in comp.get("log", []):
				_line("BOT   " + String(line_v))
			if bool(comp.get("ok", false)):
				completions += 1
			return true
		SoloSequence.Step.ACTION:
			_resolve_bot_action(decision)
			return true
		SoloSequence.Step.ROLL_AGAIN:
			_line("BOT   la tabella ordina un altro tiro immediato.")
			if not state.solo_ended:
				_bot_turn()
			return true
		SoloSequence.Step.FOLLOW_UP:
			_line("BOT   continua la procedura prescritta senza ritirare la Tabella.")
			var next := SoloAI.continue_follow_up(decision, state, graph, engine,
				port_control, imaginary_side)
			_apply_bot_decision(result, next, int(step.get("depth", 1)))
			return true
		SoloSequence.Step.YIELD_INITIATIVE:
			var why := String(step.get("reason", ""))
			if why == "senza effetto applicabile":
				_line("BOT   risultato %s senza effetto applicabile: cede l'Iniziativa."
					% String(result.get("code", "?")))
			_give_initiative_to(player_side)
			return true
		SoloSequence.Step.KEEP_INITIATIVE:
			# Senza GUI non c'e' nessuna coda da riempire: il ciclo del runner
			# torna da solo al giro successivo.
			return true
	return false


## Mirror headless di `ui/main.gd::_resolve_solo_ai_action`: l'ultimo rimasto.
## Qui l'azione si risolve e basta; li' apre la Mappa di Battaglia.
func _resolve_bot_action(decision: Dictionary) -> void:
	var key := String(decision.get("action_key", ""))
	var dec := SoloSequence.declaration_for(decision)
	if dec == null:
		_line("BOT   azione incompleta: manca la TF attiva o il bersaglio.")
		_give_initiative_to(player_side)
		return
	var active := dec.active
	var target := dec.target
	if not dec.active_stealth.is_empty():
		_line("BOT   l'azione la esegue la forza Furtiva %s in %s: Totale Traiettoria zero (RB p.41)."
			% [Stealth.kind_name(int(dec.active_stealth.get("kind", -1))),
				str(Vector2i(int(dec.active_stealth.get("q", 0)),
					int(dec.active_stealth.get("r", 0))))])
	if not dec.active_air_base.is_empty():
		_line("BOT   l'Attacco Aereo parte dalla base aerea in %s: Totale "
			% str(AirBase.hex_of(dec.active_air_base))
			+ "Traiettoria zero, e non c'e' nessuna Traiettoria da accorciare (RB p.27).")
	if dec.active_coordinating != null:
		_line("BOT   %s coordina l'azione." % dec.active_coordinating.display_name())
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
	# "After the attack ... the Submarine marker is removed from play"
	# (N3 p.26). Dopo l'applicazione dei risultati, non prima: mentre si
	# risolvono, l'attaccante dev'essere ancora nel suo esagono.
	_remove_stealth_after_attack(decision, dec)
	var late_event := SoloSequence.late_event_for_action(key)
	if late_event != "":
		_maybe_go_late(late_event, "il bot ha eseguito %s" % label)
	if pending != Results.Battle.NONE and not _prepare_battle(active, target):
		pending = Results.Battle.NONE
	if pending != Results.Battle.NONE:
		_maybe_go_late("battle", "un risultato del bot ha aperto una Battaglia")
		_run_battle(pending, active, target, dec.target_hex)
		return
	if bool(engine.action(key).get("causes_time_lapse", false)):
		# RB p.41: dopo un Attacco Furtivo fanno Scorrere del Tempo le Traiettorie
		# delle TF DESIGNATE, e una forza Furtiva non e' una TF. Con lei sola
		# designata non c'e' niente da accorciare, ed e' quello che succede qui
		# perche' `active` e' nullo.
		_bot_time_lapse(active,
			decision.get("time_lapse_goal", dec.target_hex),
			dec.launch_hex if key == "AIR_STRIKE" else Vector2i.MAX,
			bool(decision.get("time_lapse_prefer_near", false)))
	match SoloSequence.after_action(key, initiative_changes):
		SoloSequence.AfterAction.CHANGE:
			_give_initiative_to(1 - dec.acting_side())
		SoloSequence.AfterAction.OFFER_STEAL:
			_inactive_steals("Ricerca Navale del bot")
		_:
			_seek_initiative("BOT")


# --------------------------------------------------- turno del giocatore --

## POLICY DELL'HARNESS, non una regola del fascicolo: vedi l'intestazione.
func _player_turn() -> void:
	# I Controlli Rifornimento tirano dadi, e un turno rigiocato dopo una
	# domanda non deve ritirarli: si fanno una volta per turno, e la memoria
	# la azzera chi COMINCIA un turno nuovo, non chi lo rigioca.
	if not _turn_rolls.has("fueling"):
		_turn_rolls["fueling"] = true
		_bl1_fueling_checks()
	# Il Controllo Rifornimento di BL1 non e' una scelta: e' obbligatorio non
	# appena il tedesco ha l'Iniziativa e una sua Stazione occupa un RV
	# (AC Solo scenarios 2022 p.6). Va quindi prima dell'azione.
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
	# L'ordine della policy e' un ELENCO, non una catena di if. E' il primo
	# passo verso l'unificazione con la GUI: in una macchina a passi ogni voce
	# di questo elenco diventa un caso, e chi guida il ciclo - il replay con la
	# sua policy, l'interfaccia con le sue domande - sceglie come rispondere.
	# Finche' resta cablato qui, la GUI e' costretta a riscriverlo.
	#
	# Le ragioni dell'ordine stanno accanto a ogni voce, e non sono di comodo:
	# vengono dagli obiettivi stampati degli scenari.
	for step_v: Variant in _player_step_order():
		var step := String(step_v)
		if _run_player_step(step):
			return
		if _aborted:
			return
	_line("GIOCATORE (policy harness): Passare.")
	_player_time_lapse(_player_main_force())
	_seek_initiative("GIOCATORE")


## BL1 p.8: la tabella Murmansk si tira PRIMA del Debriefing, e sposta i VP.
## Va quindi qui, fra la fine dello scenario e il punteggio, non nel ciclo.
func _bl1_murmansk_before_debriefing() -> void:
	if not SoloAI.bl1_murmansk_pending(state):
		return
	var applied := SoloAI.bl1_murmansk_check(state, solo.table("murmansk"))
	_line("Murmansk? Una TF tedesca ha Completato a Murmansk: si tira prima del Debriefing.")
	var roll: Dictionary = applied.get("roll", {})
	if not roll.is_empty():
		for line in SoloTable.describe(roll).split("\n"):
			_line("   " + line)
	for line_v: Variant in applied.get("log", []):
		_line("   " + String(line_v))


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


## Servono altri Convogli per arrivare alla fine stampata?
##
## Si guarda la soglia piu' alta fra le condizioni di fine dello scenario e la
## si confronta con quelli gia' Completati piu' quelli ancora a galla. Se non
## bastano, l'unico posto da cui possono arrivare e' un Gruppo di Rinforzo.
func _needs_more_convoys() -> bool:
	var needed := 0
	for rule_v: Variant in state.solo_end_conditions.get("any", []):
		for cond_v: Variant in (rule_v as Dictionary).get("all", []):
			var cond: Dictionary = cond_v
			var kind := String(cond.get("kind", ""))
			if kind == "convoys_completed_total" or kind == "convoys_completed_by":
				needed = maxi(needed, int(cond.get("value", 0)))
	if needed == 0:
		return false
	var available := state.convoys_completed
	for tf in state.forces_of(player_side):
		if _carries_convoy(tf):
			available += 1
	return available < needed


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
		var port_name := String(ports.get(group, ""))
		var destination := ""
		if port_name == "":
			# Un Gruppo puo' non avere un porto FISSO e averlo invece tirato:
			# succede solo col Gruppo A di A1 (p.59), che determina col dado
			# sia il porto di partenza sia quello di destinazione.
			var route := _rolled_reinforcement_route(group)
			port_name = String(route.get("from", ""))
			destination = String(route.get("to", ""))
		if port_name == "":
			_line("GIOCATORE (policy harness): il Gruppo %s non ha un porto "
				% group + "trascritto; non viene fatto entrare.")
			continue
		var port := graph.port_hex(port_name)
		if port == Vector2i.MAX:
			_line("GIOCATORE (policy harness): il porto %s del Gruppo %s non e' "
				% [port_name, group] + "nel grafo calibrato.")
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
			# Una rotta tirata porta anche la destinazione: senza, il Convoglio
			# entrerebbe senza sapere dove deve andare, e il Completamento non
			# potrebbe mai riuscire.
			if destination != "" and new_tf != null:
				new_tf.solo_flags["completion_ports"] = [destination]
				_line("GIOCATORE   rotta tirata: da %s a %s."
					% [port_name, destination])
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
## Passo 2 dell'unificazione: le DOMANDE che il ciclo pone diventano esplicite.
##
## Finora il ciclo rispondeva da solo alle scelte del giocatore prendendo la
## prima opzione - `options[0]` - e la GUI, che quelle stesse scelte le deve
## CHIEDERE, non poteva riusare il ciclo. Ogni scelta passa adesso di qui.
##
## Chi chiama passa anche l'indice che PREFERIREBBE, perche' certe scelte hanno
## un criterio che vive dove stanno i numeri: allo Scorrere del Tempo si toglie
## dal capo piu' lontano dall'obiettivo, e quel conto lo sa fare solo chi ha la
## Traiettoria sotto mano. Il criterio resta li'; qui sta la DECISIONE di
## accettarlo. `SoloRunner` la accetta sempre - e' la policy harness - mentre
## una GUI ignora il preferito e chiede all'essere umano, senza che il resto
## del ciclo cambi di una riga.
##
## Ritorna l'INDICE scelto. Non puo' rifiutare: rifiutare e' una decisione della
## sequenza, non della scelta, e sta nei passi della policy.
## Chi risponde alle domande, se qualcuno e' stato messo. Riceve
## (domanda, opzioni, preferito) e ritorna l'indice. Vuoto = risponde la policy
## harness accettando il preferito.
##
## E' la forma che avra' `answer()` nella macchina a passi: gia' adesso permette
## a un test di forzare una strada diversa e vedere la partita cambiare, che e'
## l'unico modo di sapere che la cucitura non e' decorativa.
var answerer: Callable = Callable()

# --- macchina a passi (passo 4 dell'unificazione con la GUI) -----------------
#
# Il meccanismo, ed e' semplice a patto di dire cosa lo rende sicuro: una
# domanda senza risposta INTERROMPE il turno, e `answer()` lo rigioca da capo
# con le risposte accumulate. Rigiocare va bene solo se prima di ogni domanda
# non e' successo niente di irreversibile - e c'era un'eccezione, il dado dello
# Scorrere del Tempo, che adesso viene tirato una volta sola e ricordato
# (`_turn_rolls`).
var _pending: Dictionary = {}          ## domanda in attesa, o vuoto
var _answers: Array[int] = []          ## risposte gia' date per QUESTO turno
var _answer_index: int = 0
var _turn_rolls: Dictionary = {}       ## tiri gia' fatti in questo turno
var _aborted: bool = false
var _stepping: bool = false            ## vero solo dentro step()/answer()
## Lunghezza della trascrizione all'inizio del turno. Rigiocare un turno
## riemette le righe gia' scritte, e il registro e' l'unico effetto che
## sopravvive alla ripresa: si riporta indietro a ogni giro. Se ne e' accorto
## il test, che confrontava un turno guidato a passi con lo stesso turno giocato
## tutto insieme e ne trovava nove righe contro sette.
var _turn_transcript_len: int = 0
## Fotografia dello stato all'inizio del turno.
##
## Rigiocare un turno non basta riportare indietro il registro: i passi della
## policy MODIFICANO lo stato prima di arrivare a una domanda - il passo
## Traiettoria allunga la rotta e solo dopo lo Scorrere del Tempo chiede quali
## segmenti togliere. Al secondo giro il mondo era diverso e la partita
## imboccava un'altra strada: nel test, un Completamento a Methil al posto di
## una Traiettoria.
##
## La fotografia usa `to_dict`/`apply_dict`, cioe' la stessa strada del
## salvataggio, che il progetto verifica da sempre - RNG compreso, che e'
## serializzato come stringa apposta. Se il ripristino non fosse fedele, non lo
## sarebbe nemmeno caricare una partita.
var _turn_snapshot: Dictionary = {}


func ask_choice(question: String, options: Array[String],
		preferred: int = 0) -> int:
	if options.is_empty():
		return -1
	var fallback := clampi(preferred, 0, options.size() - 1)
	# Risposta gia' data in un giro precedente di questo stesso turno: si
	# riconsuma nell'ordine, cosi' rigiocare il turno da' la stessa partita.
	if _answer_index < _answers.size():
		var replayed := _answers[_answer_index]
		_answer_index += 1
		return clampi(replayed, 0, options.size() - 1)
	if answerer.is_valid():
		var given: Variant = answerer.call(question, options, fallback)
		if typeof(given) == TYPE_INT:
			# Una risposta fuori elenco non fa saltare la partita: si riporta
			# dentro e si tira avanti. Un guidatore che sbaglia indice e' un
			# difetto suo, non un motivo per fermare il ciclo a meta'.
			return clampi(int(given), 0, options.size() - 1)
		return fallback
	if not _stepping:
		return fallback
	# Nessuno puo' rispondere adesso: si sospende il turno e si consegna la
	# domanda a chi guida.
	_pending = {"question": question, "options": options.duplicate(),
		"preferred": fallback}
	_aborted = true
	return -1


# ------------------------------------------------- macchina a passi (API) --

## Comincia un turno del giocatore pulito: niente risposte accumulate, niente
## tiri ricordati. Chi RIGIOCA un turno dopo una domanda non deve chiamarlo.
func _begin_player_turn() -> void:
	_answers.clear()
	_answer_index = 0
	_turn_rolls.clear()
	_pending = {}
	_aborted = false
	_turn_transcript_len = transcript.size()
	_turn_snapshot = state.to_dict()


## Gioca un turno del giocatore fermandosi alla prima domanda senza risposta.
##
## Ritorna { "kind": "question", "question", "options", "preferred" } se serve
## una scelta, oppure { "kind": "done" } se il turno e' finito.
##
## E' la forma che la GUI puo' guidare: fra `step()` e `answer()` ci sta il suo
## `await Choice.ask`, e il ciclo resta sincrono - che e' il motivo per cui
## l'ereditarieta' con una `ask_choice` coroutine non poteva funzionare.
func step() -> Dictionary:
	_begin_player_turn()
	return _run_player_turn_once()


## Risponde alla domanda in sospeso e riprende. Il turno viene RIGIOCATO da capo
## con tutte le risposte date finora: e' sicuro perche' prima di ogni domanda
## non succede niente di irreversibile - i tiri di dado del turno sono
## ricordati, e i passi della policy che precedono sono solo controlli.
func answer(index: int) -> Dictionary:
	if _pending.is_empty():
		return {"kind": "done"}
	_answers.append(index)
	_answer_index = 0
	_pending = {}
	_aborted = false
	# Si riparte dalla fotografia: le risposte gia' date rifanno lo stesso
	# cammino, e quella nuova prosegue da dove ci si era fermati.
	return _run_player_turn_once(true)


func _run_player_turn_once(restore: bool = false) -> Dictionary:
	if restore and not _turn_snapshot.is_empty():
		state.apply_dict(_turn_snapshot)
	transcript.resize(_turn_transcript_len)
	_stepping = true
	_player_turn()
	_stepping = false
	if not _pending.is_empty():
		var q := _pending.duplicate(true)
		q["kind"] = "question"
		return q
	return {"kind": "done"}


## Il giocatore Inattivo vuole tentare di Sottrarre l'Iniziativa?
##
## E' l'ultima delle domande che il turno del bot pone all'avversario umano, e
## nella GUI e' un bottone: "l'avversario immaginario tenta di Sottrarre" contro
## "lasci correre". Qui risponde `player_steals_initiative`, che e' la policy
## harness - il giocatore simulato di solito rinuncia, perche' un tentativo
## fallito fa salire il conteggio e regala il turno dopo.
var steal_answerer: Callable = Callable()


func ask_steal(reason: String) -> bool:
	if not steal_answerer.is_valid():
		return player_steals_initiative
	var given: Variant = steal_answerer.call(reason, player_steals_initiative)
	return bool(given) if typeof(given) == TYPE_BOOL else player_steals_initiative


## I modificatori della Tabella Azioni da attivare per questo tiro.
##
## E' una domanda a SCELTA MULTIPLA, non singola, e per questo non passa da
## `ask_choice`: il fascicolo stampa condizioni indipendenti - "se il Meteo e'
## Cattivo", "se una TF britannica e' nell'esagono" - e valgono tutte insieme.
## Costringerla in una scelta singola avrebbe voluto dire inventare un elenco di
## combinazioni che il fascicolo non stampa.
##
## `SoloRunner` risponde con quelli DEDOTTI dallo stato, che e' l'unico modo di
## giocare senza un umano; la GUI apre le caselle da spuntare e lascia decidere.
## Chi risponde riceve anche le spiegazioni e i casi non risolti, perche' sono
## quello che rende la spunta una decisione informata e non un indovinello.
var modifier_answerer: Callable = Callable()


func ask_modifiers(table: SoloTable, inferred: Dictionary) -> Array:
	var active: Array = inferred.get("active", [])
	if not modifier_answerer.is_valid():
		return active
	var given: Variant = modifier_answerer.call(table, active,
		inferred.get("explanations", []), inferred.get("unresolved", []))
	return given if typeof(given) == TYPE_ARRAY else active


## L'ordine in cui il giocatore simulato prova le sue azioni.
##
## NON e' una regola GMT: e' la policy della harness, ed e' per questo che ogni
## riga che ne esce e' marcata "GIOCATORE (policy harness)" nella trascrizione.
## Le ragioni pero' vengono dal fascicolo, e sono queste:
##
##   norway      lo sbarco in Norvegia e' l'OBIETTIVO di N1 (posare le Mine) e
##               di N2/N3 (consegnare truppe), non un ripiego. Chi Completa in
##               porto per primo si porta via le navi che devono sbarcare.
##   convoy      un Convoglio che arriva in porto e' l'obiettivo stampato di
##               BL1 e BL2.
##   reinforce   B2, B4 e A1 chiedono piu' Convogli Completati di quanti ne
##               schierino: il terzo sta in un Gruppo di Rinforzo e va chiamato,
##               o la condizione di fine non potra' mai avverarsi.
##   attack      un cacciatore va a caccia di Convogli.
##   go_home     il rientro va tentato PRIMA della Traiettoria: una TF che puo'
##               sempre allungare di un segmento non arriva mai all'ultima riga
##               e resta a fare avanti e indietro fra due porti fino al limite
##               dei turni. E' successo davvero, col seme 42.
##   trajectory  altrimenti si naviga.
##   complete    e solo in ultimo si rientra comunque.
func _player_step_order() -> Array[String]:
	return ["norway", "convoy", "reinforce", "attack", "go_home",
		"trajectory", "complete"]


## Esegue un passo della policy. Ritorna vero se il passo ha consumato l'azione.
func _run_player_step(step: String) -> bool:
	match step:
		"norway":
			return _player_norway_completion()
		"convoy":
			return _player_completion(true)
		"reinforce":
			return _needs_more_convoys() and _player_reinforce()
		"attack":
			return _player_attack()
		"go_home":
			var going_home := not _enemy_convoy_in_play() \
				or bool(state.solo_counters.get("bl1_fuel_limits", false))
			return going_home and _player_completion(false)
		"trajectory":
			return _player_trajectory()
		"complete":
			return _player_completion(false)
	push_error("passo di policy sconosciuto: %s" % step)
	return false


## Completamento in Norvegia (fascicolo p.16), con quello che ne consegue: la
## posa delle Mine se l'esagono e' un bersaglio dichiarato (N1 p.17) e il tiro
## della Reazione Norvegese, che tocca al giocatore e non all'avversario
## immaginario.
##
## La differenza che conta rispetto a un Completamento in porto: la Task Force
## NON esce di scena, fa Scorrere del Tempo e resta in gioco. E' per questo che
## una sola TF puo' posare tre Mine in tre esagoni diversi.
func _player_norway_completion() -> bool:
	# Vale solo per gli scenari 'N'. Il fascicolo apre il capitolo con "'N'
	# SCENARIOS: NORWAY ... Each of these scenarios allows for Completion
	# actions in Norway" (p.16): e' una regola di QUEL gruppo, non del gioco.
	# Senza questo vincolo A1 e N5 - che hanno Narvik e Trondheim sulla loro
	# mappa come porti qualsiasi - sbarcavano in Norvegia a ogni turno e il
	# replay non finiva piu': la Task Force non viene rimossa, quindi si poteva
	# ripetere all'infinito. Se ne sono accorti i due replay, non io.
	if not scenario.id.begins_with("N"):
		return false
	var targets: Array = scenario.mines_targets()
	for tf in state.forces_of(player_side):
		if not _player_may_declare(tf, "COMPLETION"):
			continue
		if not Norway.carries_landing_force(tf):
			continue
		var h := _anchor(tf)
		if not Norway.can_complete(graph, tf, h):
			continue
		# Sbarcare due volte nello stesso esagono con la stessa Task Force non
		# aggiunge niente, e siccome la TF non viene rimossa si ripeterebbe per
		# sempre. Il fascicolo non lo vieta perche' non ne ha bisogno: un
		# giocatore non lo farebbe. La policy harness si', quindi glielo si dice.
		var done_here: Array = tf.solo_flags.get("norway_done", [])
		if done_here.has(str(h)):
			continue
		# E se in questo esagono le Mine ci sono gia', non c'e' niente da posare.
		if not targets.is_empty() and not Stealth.can_lay_mines(state, targets, tf, h):
			continue
		_line("GIOCATORE (policy harness): Completamento in Norvegia di %s in %s."
			% [tf.display_name(), str(h)])
		if _inactive_steals("Completamento in Norvegia"):
			_line("GIOCATORE   Impedito dal cambio d'Iniziativa.")
			return true
		var done := Norway.complete(state, graph, tf, h, false)
		for line_v: Variant in done.get("log", []):
			_line("GIOCATORE   " + String(line_v))
		if not bool(done.get("ok", false)):
			return true
		completions += 1
		var seen: Array = tf.solo_flags.get("norway_done", [])
		seen.append(str(h))
		tf.solo_flags["norway_done"] = seen
		if not targets.is_empty():
			var mines := Stealth.lay_mines(state, targets, tf, h)
			for line_v: Variant in mines.get("log", []):
				_line("GIOCATORE   " + String(line_v))
		# "roll a die and check the result on the Norwegian Reaction Table":
		# tocca al giocatore, mai all'avversario immaginario.
		if bool(done.get("check_reaction", false)):
			var reaction := Norway.roll_reaction(state, graph, state.rng,
				scenario.id, tf, h)
			if bool(reaction.get("ok", false)):
				for line_v: Variant in reaction.get("log", []):
					_line("GIOCATORE   " + String(line_v))
				var applied := Norway.apply_reaction(state, reaction, tf,
					graph, scenario.id, h)
				for line_v: Variant in applied.get("log", []):
					_line("GIOCATORE   " + String(line_v))
				if int(applied.get("initiative_to", -1)) >= 0:
					state.initiative = int(applied["initiative_to"])
					_line("GIOCATORE   L'Iniziativa passa a %s."
						% Initiative.side_name(state.initiative))
			else:
				_line("GIOCATORE   Reazione Norvegese non tirata: %s"
					% String(reaction.get("reason", "")))
		# "do not remove the TF or its ships. Instead, perform Time Lapse."
		if bool(done.get("time_lapse", false)):
			_player_time_lapse(tf)
		return true
	return false


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
		var labels: Array[String] = []
		for o_v: Variant in options:
			labels.append(String((o_v as Dictionary)["name"]))
		var pick := ask_choice("porto di Completamento per %s" % tf.display_name(),
			labels)
		if pick < 0:
			return true
		_line("GIOCATORE (policy harness): Completamento di %s a %s."
			% [tf.display_name(), labels[pick]])
		if _inactive_steals("Completamento del giocatore"):
			_line("GIOCATORE   Completamento impedito dal cambio d'Iniziativa.")
			return true
		var comp := Completion.resolve(tf, options[pick], vp_tracker)
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
	# I candidati si RACCOLGONO tutti, in ordine di preferenza, e poi si sceglie
	# dalla cucitura. Prima si usciva al primo legale: comodo per il replay,
	# inutile per la GUI, che quei candidati li deve mostrare tutti perche' la
	# scelta e' del giocatore.
	#
	# L'ordine e' la preferenza: prima i Convogli. L'obiettivo stampato di BL1 e
	# BL2 e' colpire i Convogli, e attaccare la corazzata nemica perche' capita
	# nello stesso esagono e' la mossa che il fascicolo scoraggia - nel primo
	# replay costava la partita al turno uno.
	var moves: Array[Dictionary] = []
	var labels: Array[String] = []
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
					moves.append({"dec": dec, "key": key, "tf": tf, "enemy": enemy})
					labels.append("%s con %s contro %s"
						% [String(engine.action(key).get("label", key)),
							tf.display_name(), enemy.display_name()])
	if moves.is_empty():
		return false
	var pick := ask_choice("attacco del giocatore", labels)
	if pick < 0:
		return true
	var move: Dictionary = moves[pick]
	_line("GIOCATORE (policy harness): %s." % labels[pick])
	_resolve_player_action(move["dec"])
	return true


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
			_give_initiative_to(1 - dec.acting_side())


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
	if inactive == player_side and not ask_steal(reason):
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
		protected_hex: Vector2i = Vector2i.MAX,
		prefer_near: bool = false) -> void:
	_time_lapse(tf, goal, protected_hex, "BOT", prefer_near)


func _player_time_lapse(tf: TaskForce, goal: Vector2i = Vector2i.MAX) -> void:
	_time_lapse(tf, goal, Vector2i.MAX, "GIOCATORE")


func _time_lapse(tf: TaskForce, goal: Vector2i, protected_hex: Vector2i,
		who: String, prefer_near: bool = false) -> void:
	if tf == null or tf.trajectory.is_station():
		return
	# Il dado va tirato UNA volta per turno anche se il turno viene rigiocato
	# dopo una domanda: senza questa memoria, ogni ripresa ne consumerebbe un
	# altro e la stessa partita darebbe risultati diversi.
	var roll_key := "time_lapse:%d" % tf.id
	var amount: int = int(_turn_rolls[roll_key]) if _turn_rolls.has(roll_key) \
		else TimeLapse.required_removal(tf.speed, state.weather, state.rng)
	_turn_rolls[roll_key] = amount
	var opts := TimeLapse.removal_options(tf.trajectory, tf.speed, amount,
		protected_hex)
	if opts.is_empty():
		_line("%s   Scorrere del Tempo: nessuna rimozione legale." % who)
		return
	# Il criterio e' quello stampato dalla procedura - di solito "rimuovi i
	# segmenti piu' LONTANI da X", ogni tanto "piu' VICINI a X" - e sta in
	# `SoloSequence` perche' e' una regola, non un modo di mostrarla.
	var preferred := SoloSequence.time_lapse_preference(opts, tf.trajectory,
		goal, prefer_near)
	var labels: Array[String] = []
	for option_v: Variant in opts:
		var ends: Array = (option_v as Dictionary)["ends"]
		labels.append("%d dalla testa, %d dalla coda" % [int(ends[0]), int(ends[1])])
	var picked := ask_choice("segmenti da togliere a %s" % tf.display_name(),
		labels, preferred)
	if picked < 0:
		return
	var chosen: Dictionary = opts[picked]
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
## Una procedura puo' prescrivere che la forza Furtiva lasci il gioco dopo aver
## attaccato: N3 p.26 lo fa per il Sommergibile britannico, che potra' tornare
## con un altro 'SA' o 'SR'. La condizione sta nella decisione, non qui: e' la
## procedura stampata a stabilirla, non una regola generale delle forze Furtive.
func _remove_stealth_after_attack(decision: Dictionary,
		dec: ActionEngine.Declaration) -> void:
	if not bool(decision.get("stealth_removed_after", false)):
		return
	if dec.active_stealth.is_empty():
		return
	var h := Vector2i(int(dec.active_stealth.get("q", 0)),
		int(dec.active_stealth.get("r", 0)))
	if Stealth.remove_at(state, h, dec.acting_side()):
		_line("BOT   la forza Furtiva %s lascia il gioco dopo l'attacco, come "
			% Stealth.kind_name(int(dec.active_stealth.get("kind", -1)))
			+ "prescrive la procedura.")


func _prepare_battle(active: TaskForce, target: TaskForce) -> bool:
	for tf_v: Variant in [active, target]:
		var tf: TaskForce = tf_v
		# Con un attaccante Furtivo l'Attiva non esiste: non c'e' niente da
		# identificare da quella parte.
		if tf == null:
			continue
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
		# Una Task Force che non e' ne' Stazione ne' Traiettoria - tutti i
		# segmenti rimossi senza diventare Stazione - da' ancora (0,0), che non
		# e' un esagono della mappa. Puntarci significa chiedere per sempre una
		# rotta che non esiste: il replay lo ha mostrato come una partita di 120
		# turni in cui il giocatore Passava a ogni turno "verso (0, 0)".
		if not graph.has_hex(h):
			continue
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
