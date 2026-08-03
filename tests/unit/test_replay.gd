extends TestCase

## Replay end-to-end degli scenari in solitario (milestone R0).
##
## Non verifica una tabella per volta: fa giocare BL1 e BL2 dall'inizio alla
## fine con `SoloRunner` e controlla le proprieta' che devono valere SEMPRE,
## qualunque cosa escano i dadi. Sono proprio quelle che una regressione nel
## ciclo del bot rompe per prima e che nessun test unitario vede:
##
##   - a parita' di seme la partita e' identica, riga per riga;
##   - la partita termina per una condizione STAMPATA, non per esaurimento
##     turni;
##   - dopo la fine dello scenario nessuno agisce piu';
##   - i Completamenti avvengono in porti che quella parte puo' davvero usare;
##   - salvare e ricaricare a meta' partita da' lo stesso stato e lo stesso RNG.
##
## I semi sono fissi. Cambiarli significa cambiare la partita di riferimento, e
## va fatto di proposito: un seme scelto perche' "cosi' passa" nasconde
## esattamente il difetto che questa suite deve trovare.

const BL1 := "BL1 Raiders of the North Atlantic"
const BL2 := "BL2 Contain and Destroy"

## Semi verificati a mano: entrambi arrivano a una condizione di fine stampata.
const BL1_SEED := 20260803
const BL2_SEED := 20260803

## Semi ulteriori per la proprieta' "termina o dichiara una lacuna". Ne bastano
## pochi: la suite deve restare veloce.
const SWEEP_SEEDS := [2, 3, 7, 42]


func name() -> String:
	return "Replay solitario BL1/BL2"


func run() -> void:
	test_bl1_replay_reaches_printed_end()
	test_bl2_replay_reaches_printed_end()
	test_replays_are_deterministic()
	test_nothing_acts_after_scenario_end()
	test_completions_use_legal_ports()
	test_sweep_terminates_or_declares_a_gap()
	test_save_and_reload_preserve_the_replay()
	test_bl1_action_row_counts_british_convoys()
	test_bl2_action_row_counts_player_completions()
	test_bl1_scenario_end_needs_both_conditions()
	test_active_rendezvous_count_ignores_removed_markers()
	test_bl1_bad_weather_air_result_needs_a_cruiser()
	test_bl1_fuel_limits_thresholds()
	test_south_america_is_closed_without_a_fueling_grant()


func _run(scenario_id: String, seed_value: int) -> Dictionary:
	var runner := SoloRunner.new()
	_begin("replay %s" % scenario_id)
	if not runner.load_scenario(scenario_id, seed_value):
		check(false, "scenario non caricato: %s" % runner.load_error)
		return {}
	return runner.run()


# ------------------------------------------------------- partite complete --

func test_bl1_replay_reaches_printed_end() -> void:
	_begin("BL1 arriva a una fine stampata")
	var out := _run(BL1, BL1_SEED)
	true_(bool(out.get("ended", false)),
		"il replay BL1 deve chiudersi con una condizione di fine dello scenario")
	eq(String(out.get("stopped", "x")), "",
		"il replay BL1 non deve fermarsi per limite di turni")
	true_(String(out.get("reason", "")).contains("Rendezvous"),
		"la fine di BL1 e' quella stampata a p.5, sui marker Rendezvous")
	true_(int(out.get("bot_turns", 0)) > 0,
		"l'avversario immaginario deve aver giocato almeno un turno")
	true_(int(out.get("player_turns", 0)) > 0,
		"il giocatore simulato deve aver giocato almeno un turno")


func test_bl2_replay_reaches_printed_end() -> void:
	_begin("BL2 arriva a una fine stampata")
	var out := _run(BL2, BL2_SEED)
	true_(bool(out.get("ended", false)),
		"il replay BL2 deve chiudersi con una condizione di fine dello scenario")
	eq(String(out.get("stopped", "x")), "",
		"il replay BL2 non deve fermarsi per limite di turni")
	var reason := String(out.get("reason", ""))
	true_(reason.contains("Convogli") or reason.contains("navi"),
		"la fine di BL2 e' due Convogli Completati oppure quattro navi affondate")


## E' la proprieta' che rende utile tutto il resto: senza determinismo una
## regressione si vede oggi e sparisce domani.
func test_replays_are_deterministic() -> void:
	_begin("stesso seme, stessa partita")
	for pair_v: Variant in [[BL1, BL1_SEED], [BL2, BL2_SEED]]:
		var pair: Array = pair_v
		var a := _run(String(pair[0]), int(pair[1]))
		var b := _run(String(pair[0]), int(pair[1]))
		var ta: Array = a.get("transcript", [])
		var tb: Array = b.get("transcript", [])
		eq(ta.size(), tb.size(),
			"%s: le due trascrizioni devono avere lo stesso numero di righe"
				% String(pair[0]))
		var first_difference := -1
		for i in mini(ta.size(), tb.size()):
			if String(ta[i]) != String(tb[i]):
				first_difference = i
				break
		eq(first_difference, -1,
			"%s: le due trascrizioni devono coincidere riga per riga"
				% String(pair[0]))


## Il difetto corretto in `bf65a2b` era proprio questo: una procedura accodata
## continuava dopo la fine dello scenario. Qui si verifica sulla trascrizione.
func test_nothing_acts_after_scenario_end() -> void:
	_begin("dopo la fine nessuno agisce")
	for pair_v: Variant in [[BL1, BL1_SEED], [BL2, BL2_SEED]]:
		var pair: Array = pair_v
		var out := _run(String(pair[0]), int(pair[1]))
		var lines: Array = out.get("transcript", [])
		var end_at := -1
		for i in lines.size():
			if String(lines[i]).begins_with("FINE SCENARIO"):
				end_at = i
				break
		true_(end_at >= 0, "%s: la trascrizione deve contenere la fine scenario"
			% String(pair[0]))
		var after := 0
		for i in range(end_at + 1, lines.size()):
			var line := String(lines[i])
			if line.begins_with("--- Turno ") or line.begins_with("BOT - ") \
					or line.begins_with("GIOCATORE (policy harness)"):
				after += 1
		eq(after, 0, "%s: nessun turno o azione dopo la fine dello scenario"
			% String(pair[0]))


## Un Completamento in un porto che quella parte non controlla e' esattamente
## il tipo di errore che passa inosservato: la partita continua, i punti sono
## sbagliati, e nessuno se ne accorge fino al Debriefing.
func test_completions_use_legal_ports() -> void:
	_begin("i Completamenti usano porti leciti")
	var runner := SoloRunner.new()
	true_(runner.load_scenario(BL1, BL1_SEED), "BL1 caricato")
	var out := runner.run()
	var checked := 0
	for tf in runner.state.task_forces:
		if not tf.completed or tf.completed_port == "":
			continue
		var port: Dictionary = runner.graph.ports.get(tf.completed_port, {})
		if port.is_empty():
			continue
		checked += 1
		var control := Completion.control_of(port, runner.port_control)
		var granted := String(tf.solo_flags.get("bl1_completion_port", ""))
		var allowed := control == "BOTH" \
			or control == VictoryTracker.side_name(tf.side) \
			or granted == tf.completed_port
		true_(allowed, "%s ha Completato a %s, controllato da '%s'"
			% [tf.display_name(), tf.completed_port, control])
	true_(checked > 0 or int(out.get("completions", 0)) == 0,
		"se ci sono stati Completamenti, almeno uno va verificato")


func test_sweep_terminates_or_declares_a_gap() -> void:
	_begin("ogni seme finisce o dichiara la lacuna")
	for seed_v: Variant in SWEEP_SEEDS:
		for scenario_id in [BL1, BL2]:
			var out := _run(scenario_id, int(seed_v))
			var ended := bool(out.get("ended", false))
			var gap := bool(out.get("declared_gap", false))
			true_(ended or gap, ("%s con seme %d deve chiudersi per una "
				+ "condizione stampata oppure dichiarare la lacuna, mai "
				+ "esaurire i turni") % [scenario_id, int(seed_v)])


## Il salvataggio deve contenere anche lo stato solitario. Un campo dimenticato
## non si vede finche' qualcuno non ricarica a meta' scenario.
func test_save_and_reload_preserve_the_replay() -> void:
	_begin("salvataggio e ricarica a meta' replay")
	var runner := SoloRunner.new()
	true_(runner.load_scenario(BL2, BL2_SEED), "BL2 caricato")
	runner.run(4)
	var saved := runner.state.to_dict()
	var restored := GameState.new(runner.graph, 0)
	restored.apply_dict(saved)
	eq(restored.initiative, runner.state.initiative, "Iniziativa conservata")
	eq(restored.initiative_count, runner.state.initiative_count,
		"Conto dell'Iniziativa conservato")
	eq(restored.weather, runner.state.weather, "meteo conservato")
	eq(restored.solo_phase, runner.state.solo_phase, "fase Presto/Tardi conservata")
	eq(restored.solo_ended, runner.state.solo_ended, "fine scenario conservata")
	eq(restored.convoys_completed, runner.state.convoys_completed,
		"Convogli Completati conservati")
	eq(restored.task_forces.size(), runner.state.task_forces.size(),
		"numero di Task Force conservato")
	eq(restored.active_rendezvous_count(), runner.state.active_rendezvous_count(),
		"marker Rendezvous ancora attivi conservati")
	# Il seme non basta: conta lo STATO del generatore, che JSON degrada se
	# salvato come numero invece che come stringa.
	var a := restored.rng.d6("controllo")
	var b := runner.state.rng.d6("controllo")
	eq(a, b, "il generatore ricaricato deve produrre lo stesso tiro")


# ------------------------------------------------- regole verificate a mano --

## AC Solo scenarios 2022 p.7: la riga si sceglie contando "successful British
## Convoy Completion actions and/or destroyed Convoys". In BL1 il britannico e'
## l'avversario IMMAGINARIO, non il giocatore.
func test_bl1_action_row_counts_british_convoys() -> void:
	_begin("BL1: la riga conta i Convogli britannici")
	var solo := SoloOpponent.load_for(BL1)
	check(solo != null, "tabelle BL1 caricate")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.scenario_name = BL1
	var german := TaskForce.Side.KRIEGSMARINE
	eq(solo.action_row_selector(st, german), 0, "all'inizio la riga e' zero")
	# Un Completamento TEDESCO non deve muovere la riga.
	st.count_convoy_completed(TaskForce.Side.KRIEGSMARINE)
	eq(solo.action_row_selector(st, german), 0,
		"un Completamento tedesco non conta per la Tabella Azioni Britanniche")
	st.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	eq(solo.action_row_selector(st, german), 1,
		"un Convoglio britannico Completato porta la riga a uno")
	# Anche i Convogli britannici DISTRUTTI contano, ed e' la meta' della
	# regola che mancava del tutto.
	st.casualties.append({"side": TaskForce.Side.ROYAL_NAVY, "convoys": 1,
		"ships": ["Convoy x2"]})
	eq(solo.action_row_selector(st, german), 2,
		"un Convoglio britannico distrutto porta la riga a due")


func test_bl2_action_row_counts_player_completions() -> void:
	_begin("BL2: la riga conta i Completamenti del giocatore britannico")
	var solo := SoloOpponent.load_for(BL2)
	check(solo != null, "tabelle BL2 caricate")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.scenario_name = BL2
	var british := TaskForce.Side.ROYAL_NAVY
	eq(solo.action_row_selector(st, british, "actions_early"), 0,
		"all'inizio la riga e' zero")
	st.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	eq(solo.action_row_selector(st, british, "actions_early"), 1,
		"il Completamento britannico e' quello che conta in BL2")
	# La tabella Tardi non usa un conteggio: usa il meteo.
	st.weather = TimeLapse.Weather.BAD
	eq(solo.action_row_selector(st, british, "actions_late"), TimeLapse.Weather.BAD,
		"la tabella Tardi si legge sulla riga del meteo")


## p.5: "two or fewer Rendezvous markers remaining AND the Germans have no Task
## Forces in play". Le due condizioni valgono insieme.
func test_bl1_scenario_end_needs_both_conditions() -> void:
	_begin("BL1: la fine chiede tutte e due le condizioni")
	var graph := MapGraph.load_default()
	var st := GameState.new(graph, 1)
	st.scenario_name = BL1
	st.rendezvous_markers = [
		{"q": 10, "r": 3, "active": true},
		{"q": 9, "r": -2, "active": true},
		{"q": 11, "r": -5, "active": true},
	] as Array[Dictionary]
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.trajectory.become_station(Vector2i(10, 3))
	tf.ships.append(Ship.new("Lutzow"))
	st.add_task_force(tf)
	false_(SoloAI.enforce_scenario_end(st),
		"con tre marker e una TF tedesca lo scenario non finisce")
	st.remove_rendezvous_at(Vector2i(10, 3))
	false_(SoloAI.enforce_scenario_end(st),
		"due marker ma una TF tedesca ancora in gioco: non finisce")
	st.remove_task_force(tf)
	true_(SoloAI.enforce_scenario_end(st),
		"due marker e nessuna TF tedesca: lo scenario finisce")
	true_(st.solo_end_reason.contains("Rendezvous"),
		"il motivo deve citare i marker Rendezvous")


## `remove_rendezvous_at` marca il marker come inattivo invece di cancellarlo,
## per conservarne la posizione nel salvataggio: contare l'Array darebbe sempre
## il numero iniziale.
func test_active_rendezvous_count_ignores_removed_markers() -> void:
	_begin("i marker rimossi non si contano piu'")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.rendezvous_markers = [
		{"q": 10, "r": 3, "active": true},
		{"q": 9, "r": -2, "active": true},
	] as Array[Dictionary]
	eq(st.active_rendezvous_count(), 2, "due marker attivi")
	true_(st.remove_rendezvous_at(Vector2i(10, 3)), "il marker viene rimosso")
	eq(st.active_rendezvous_count(), 1, "resta un solo marker attivo")
	eq(st.rendezvous_markers.size(), 2,
		"la voce resta nell'elenco, cosi' il salvataggio ricorda dov'era")


## p.7: con Meteo Cattivo la 'A' diventa una 'X' solo se una TF britannica ha
## un CA; senza CA in gioco diventa una 'B', cioe' il Blocco.
func test_bl1_bad_weather_air_result_needs_a_cruiser() -> void:
	_begin("BL1: 'A' con Meteo Cattivo")
	var graph := MapGraph.load_default()
	var engine := ActionEngine.load_default()
	var st := GameState.new(graph, 7)
	st.scenario_name = BL1
	st.weather = TimeLapse.Weather.BAD
	var german := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	german.trajectory.become_station(Vector2i(15, -2))
	german.ships.append(ShipRoster.shared().make("Lutzow"))
	st.add_task_force(german)
	# Senza nessun CA britannico in gioco: deve nascere il Blocco.
	var no_ca := SoloAI.execute_code("A", st, graph, engine, {},
		TaskForce.Side.ROYAL_NAVY)
	var made_blockade := false
	for tf in st.forces_of(TaskForce.Side.ROYAL_NAVY):
		if tf.display_name() == "Blocco britannico":
			made_blockade = true
	true_(made_blockade,
		"senza CA britannici la 'A' con Meteo Cattivo diventa una 'B'")
	true_(bool(no_ca.get("roll_again", false)),
		"il Blocco ordina un altro tiro sulla Tabella Azioni")
	# Ora c'e' un CA in gioco: torna a essere una 'X'.
	var st2 := GameState.new(graph, 7)
	st2.scenario_name = BL1
	st2.weather = TimeLapse.Weather.BAD
	var german2 := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	german2.trajectory.become_station(Vector2i(15, -2))
	german2.ships.append(ShipRoster.shared().make("Lutzow"))
	st2.add_task_force(german2)
	var british := TaskForce.new(2, TaskForce.Side.ROYAL_NAVY)
	british.trajectory.become_station(Vector2i(15, -3))
	british.ships.append(ShipRoster.shared().make("Norfolk"))
	st2.add_task_force(british)
	var with_ca := SoloAI.execute_code("A", st2, graph, engine, {},
		TaskForce.Side.ROYAL_NAVY)
	var chosen: TaskForce = with_ca.get("active", null)
	check(chosen != null, "la procedura deve scegliere una TF")
	if chosen != null:
		eq(chosen.display_name(), british.display_name(),
			"la TF scelta e' quella che ha il CA")


## p.8: i risultati F e X invocano i Limiti di Carburante a tre e a due
## Convogli britannici Completati.
func test_bl1_fuel_limits_thresholds() -> void:
	_begin("BL1: Limiti di Carburante")
	var graph := MapGraph.load_default()
	var engine := ActionEngine.load_default()
	var st := GameState.new(graph, 11)
	st.scenario_name = BL1
	var german := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	german.trajectory.become_station(Vector2i(15, -2))
	german.ships.append(ShipRoster.shared().make("Lutzow"))
	st.add_task_force(german)
	SoloAI.execute_code("X", st, graph, engine, {}, TaskForce.Side.ROYAL_NAVY)
	false_(bool(st.solo_counters.get("bl1_fuel_limits", false)),
		"senza Completamenti britannici i Limiti non scattano")
	st.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	st.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	SoloAI.execute_code("X", st, graph, engine, {}, TaskForce.Side.ROYAL_NAVY)
	true_(bool(st.solo_counters.get("bl1_fuel_limits", false)),
		"con due Convogli britannici Completati la 'X' invoca i Limiti")
	# La soglia della 'F' e' tre, e vale su uno stato pulito.
	var st2 := GameState.new(graph, 11)
	st2.scenario_name = BL1
	var german2 := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	german2.trajectory.become_station(Vector2i(15, -2))
	german2.ships.append(ShipRoster.shared().make("Lutzow"))
	st2.add_task_force(german2)
	for i in 2:
		st2.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	SoloAI.execute_code("F", st2, graph, engine, {}, TaskForce.Side.ROYAL_NAVY)
	false_(bool(st2.solo_counters.get("bl1_fuel_limits", false)),
		"la 'F' chiede tre Convogli, non due")
	st2.count_convoy_completed(TaskForce.Side.ROYAL_NAVY)
	SoloAI.execute_code("F", st2, graph, engine, {}, TaskForce.Side.ROYAL_NAVY)
	true_(bool(st2.solo_counters.get("bl1_fuel_limits", false)),
		"con tre Convogli britannici Completati la 'F' invoca i Limiti")


## p.5: "Unless allowed by a Fueling Check ... the only ports that German TFs
## may attempt Completion are Kiel, Wilhelmshaven, and Murmansk."
func test_south_america_is_closed_without_a_fueling_grant() -> void:
	_begin("South America e' chiuso senza il Rifornimento")
	var graph := MapGraph.load_default()
	var scenario := Scenario.load_by_id(BL1)
	var control := scenario.port_control()
	var sa := graph.port_hex("South America")
	check(sa != Vector2i.MAX, "South America e' calibrato sulla mappa")
	var tf := TaskForce.new(1, TaskForce.Side.KRIEGSMARINE)
	tf.trajectory.become_station(sa)
	tf.ships.append(ShipRoster.shared().make("Lutzow"))
	eq(Completion.port_options(tf, graph, control).size(), 0,
		"senza il Nuovo Obiettivo del Rifornimento il porto resta chiuso")
	tf.solo_flags["bl1_completion_port"] = "South America"
	var granted := Completion.port_options(tf, graph, control)
	eq(granted.size(), 1,
		"il risultato a. della Tabella del Rifornimento apre South America")
	if granted.size() == 1:
		eq(String(granted[0]["name"]), "South America",
			"ed e' proprio South America")
	# Kiel resta lecito comunque: e' uno dei tre porti stampati.
	var kiel := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	kiel.trajectory.become_station(graph.port_hex("Kiel"))
	kiel.ships.append(ShipRoster.shared().make("Lutzow"))
	eq(Completion.port_options(kiel, graph, control).size(), 1,
		"Kiel resta un porto di Completamento tedesco")
