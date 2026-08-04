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

## A2 e' l'unico scenario le cui fini stampate stanno DENTRO i risultati della
## Tabella di Azione Britannica, non nelle condizioni di p.63.
const A2 := "A2 L'Ultima Battaglia"
const A2_SEED := 20260803

## Semi ulteriori per la proprieta' "termina o dichiara una lacuna". Ne bastano
## pochi: la suite deve restare veloce.
const SWEEP_SEEDS := [2, 3, 7, 42]


func name() -> String:
	return "Replay solitario BL1/BL2/A2"


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
	test_sequence_rules_are_shared_by_both_cycles()
	test_declaration_drops_a_coordinating_tf_out_of_position()
	test_gensoul_removes_one_intel_from_a_designated_force()
	test_every_playable_solo_scenario_has_printed_end_conditions()
	test_inset_map_scenarios_refuse_the_operations_map()
	test_unknown_end_condition_never_ends_the_scenario()
	test_a2_does_not_end_before_the_germans_ever_sailed()
	test_a2_reaches_a_printed_end_of_the_british_action_table()
	test_a2_end_result_consumes_rendezvous_then_uboat_markers()
	test_a2_interception_ends_on_each_printed_clause()
	test_a2_selection_table_matches_the_printed_die()
	test_start_counters_survive_setup_and_reload()
	test_player_policy_order_is_explicit()
	test_choices_go_through_an_explicit_question()
	test_a_different_answerer_changes_the_game()


## Il conto delle verifiche di ogni suite e' fisso (`EXPECTED` in
## `tests/run_tests.gd`): un'asserzione dentro un `if` farebbe variare il
## totale e trasformerebbe un test interrotto in un OK falso. Qui e in tutta la
## suite ogni `check` viene quindi eseguito sempre, anche quando il caso
## interessante non si e' verificato.
func _run(scenario_id: String, seed_value: int) -> Dictionary:
	var runner := SoloRunner.new()
	_begin("replay %s" % scenario_id)
	var loaded := runner.load_scenario(scenario_id, seed_value)
	true_(loaded, "scenario caricato: %s" % runner.load_error)
	if not loaded:
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
		for i in range(maxi(end_at, 0) + 1, lines.size()):
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
	# Il numero di Completamenti dipende dai dadi, quindi il numero di
	# verifiche NON puo' dipendere da loro: il runner pretende un conto fisso
	# per suite, e una verifica che a volte non gira e' una verifica persa in
	# silenzio. Si riassume tutto in una riga sola, con l'elenco dei colpevoli.
	var checked := 0
	var illegal: Array[String] = []
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
		if not allowed:
			illegal.append("%s a %s (controllo '%s')"
				% [tf.display_name(), tf.completed_port, control])
	eq(illegal.size(), 0, "Completamenti in porti non consentiti: %s"
		% ", ".join(illegal))
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
	st.solo_end_conditions = Scenario.load_by_id(BL1).end_conditions()
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
	eq(chosen.display_name() if chosen != null else "", british.display_name(),
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
	eq(String(granted[0]["name"]) if granted.size() == 1 else "",
		"South America", "ed e' proprio South America")
	# Kiel resta lecito comunque: e' uno dei tre porti stampati.
	var kiel := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	kiel.trajectory.become_station(graph.port_hex("Kiel"))
	kiel.ships.append(ShipRoster.shared().make("Lutzow"))
	eq(Completion.port_options(kiel, graph, control).size(), 1,
		"Kiel resta un porto di Completamento tedesco")


## Le regole di sequenza vivono in `SoloSequence` proprio perche' il ciclo
## esiste in due esemplari - il core sincrono e la vista asincrona - e le due
## copie erano gia' divergute: `initiative_changes` era applicato solo in una,
## e la regola della TF Coordinatrice era scritta due volte.
func test_sequence_rules_are_shared_by_both_cycles() -> void:
	_begin("le regole di sequenza stanno in un posto solo")
	eq(SoloSequence.branch_of({"completion": true}), SoloSequence.Branch.COMPLETION,
		"un Completamento e' il ramo Completamento")
	eq(SoloSequence.branch_of({"action_key": "ENGAGE"}), SoloSequence.Branch.ACTION,
		"una chiave d'azione e' il ramo Azione")
	eq(SoloSequence.branch_of({"ok": true, "turn_kind": "trajectory"}),
		SoloSequence.Branch.EFFECT, "un effetto applicato e' il ramo Effetto")
	eq(SoloSequence.branch_of({}), SoloSequence.Branch.NOTHING,
		"una decisione vuota non e' nessuno dei tre")
	# Il ramo Completamento ha la precedenza su tutti: una decisione che ha sia
	# `completion` sia `action_key` tenta il Completamento.
	eq(SoloSequence.branch_of({"completion": true, "action_key": "ENGAGE"}),
		SoloSequence.Branch.COMPLETION,
		"il Completamento ha la precedenza sull'azione")

	# La regola che impedisce al ciclo di fermarsi.
	true_(SoloSequence.must_yield_initiative({}),
		"una decisione senza effetto deve cedere l'Iniziativa")
	false_(SoloSequence.must_yield_initiative({"pass_initiative": true}),
		"se la cede gia' da sola, non serve forzarla")
	false_(SoloSequence.must_yield_initiative({"ok": true}),
		"una decisione che applica un effetto tiene l'Iniziativa")

	# RB p.53: cambiare l'Iniziativa e Cercarla sono due cose diverse.
	eq(SoloSequence.after_action("ENGAGE", true), SoloSequence.AfterAction.CHANGE,
		"un risultato che fa cambiare l'Iniziativa la fa passare")
	eq(SoloSequence.after_action("NAVAL_SEARCH", false),
		SoloSequence.AfterAction.OFFER_STEAL,
		"dopo una Ricerca Navale l'Inattivo puo' Sottrarre")
	eq(SoloSequence.after_action("ENGAGE", false), SoloSequence.AfterAction.SEEK,
		"in tutti gli altri casi si Cerca l'Iniziativa")
	eq(SoloSequence.after_action("NAVAL_SEARCH", true),
		SoloSequence.AfterAction.CHANGE,
		"il cambio d'Iniziativa vince anche sulla Ricerca Navale")

	eq(SoloSequence.late_event_for_action("AIR_STRIKE"), "air_strike",
		"l'Attacco Aereo puo' far passare alla tabella Tardi")
	eq(SoloSequence.late_event_for_action("STEALTH_ATTACK"), "stealth_attack",
		"e anche l'Attacco Furtivo")
	eq(SoloSequence.late_event_for_action("ENGAGE"), "",
		"Ingaggiare da solo no")


## RB p.47: la Coordinatrice deve occupare l'esagono Bersaglio. Una fuori
## posto va lasciata cadere, non passata comunque: renderebbe illegale tutta
## l'azione, e il giocatore vedrebbe solo "azione rifiutata".
func test_declaration_drops_a_coordinating_tf_out_of_position() -> void:
	_begin("la Coordinatrice fuori posto viene lasciata cadere")
	var graph := MapGraph.load_default()
	var here := Vector2i(15, -2)
	var elsewhere := Vector2i(12, 0)
	var active := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	active.trajectory.become_station(here)
	var target := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	target.trajectory.become_station(here)
	var near := TaskForce.new(3, TaskForce.Side.ROYAL_NAVY)
	near.trajectory.become_station(here)
	var far := TaskForce.new(4, TaskForce.Side.ROYAL_NAVY)
	far.trajectory.become_station(elsewhere)

	eq(SoloSequence.declaration_for({"action_key": "ENGAGE"}), null,
		"senza TF Attiva e Bersaglio non c'e' dichiarazione")
	var without := SoloSequence.declaration_for({"action_key": "ENGAGE",
		"active": active, "target": target, "target_hex": here})
	eq(without.active_coordinating, null,
		"senza Coordinatrice indicata non se ne inventa una")
	var good := SoloSequence.declaration_for({"action_key": "ENGAGE",
		"active": active, "target": target, "target_hex": here,
		"coordinating": near})
	eq(good.active_coordinating, near,
		"una Coordinatrice sull'esagono Bersaglio viene designata")
	var bad := SoloSequence.declaration_for({"action_key": "ENGAGE",
		"active": active, "target": target, "target_hex": here,
		"coordinating": far})
	eq(bad.active_coordinating, null,
		"una Coordinatrice lontana dall'esagono Bersaglio viene lasciata cadere")
	# E la dichiarazione resta legale: e' il punto di tutta la regola.
	var engine := ActionEngine.load_default()
	var st := GameState.new(graph, 1)
	st.add_task_force(active)
	st.add_task_force(target)
	st.add_task_force(far)
	eq(engine.legality_error(bad, st), "",
		"lasciando cadere la Coordinatrice l'azione resta dichiarabile")


## Gensoul, RB p.10 (letta a 300 dpi): "Quando la sua Task Force e' designata
## quale Task Force Attiva, si puo' rimuovere un segnalino Informazioni da
## qualsiasi TF britannica o francese. Quella TF deve essere designata
## nell'Azione corrente."
func test_gensoul_removes_one_intel_from_a_designated_force() -> void:
	_begin("Gensoul toglie un segnalino Informazioni")
	var graph := MapGraph.load_default()
	var st := GameState.new(graph, 4)
	var active := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	active.leader = "Gensoul"
	active.trajectory.become_station(Vector2i(15, -3))
	_extend_with_info(active, graph, st)
	st.add_task_force(active)
	var enemy := TaskForce.new(2, TaskForce.Side.KRIEGSMARINE)
	enemy.trajectory.become_station(active.trajectory.end_hex(1))
	st.add_task_force(enemy)

	var dec := ActionEngine.Declaration.new()
	dec.action_key = "NAVAL_SEARCH"
	dec.active = active
	dec.target = enemy
	true_(LeaderRules.gensoul_available(st, dec),
		"con la sua TF Attiva e un segnalino da togliere, il beneficio c'e'")
	eq(LeaderRules.gensoul_targets(dec).size(), 1,
		"la TF designata con Informazioni e' l'unico bersaglio")

	var before := active.info_count()
	true_(before > 0, "la TF Attiva ha almeno un segnalino Informazioni")
	var applied := LeaderRules.gensoul_remove_info(st, active)
	true_(bool(applied["ok"]), "il segnalino viene rimosso")
	eq(active.info_count(), before - 1, "ne va via esattamente uno")
	eq(LeaderRules.uses_left(st, "Gensoul"), 0,
		"il beneficio vale una volta per scenario")
	false_(LeaderRules.gensoul_available(st, dec),
		"e dopo l'uso non viene piu' offerto")
	var again := LeaderRules.gensoul_remove_info(st, active)
	false_(bool(again["ok"]), "un secondo uso viene rifiutato")

	# Una TF NON designata nell'Azione non e' un bersaglio, per quanto abbia
	# Informazioni: e' la meta' della regola che si dimentica.
	var st2 := GameState.new(graph, 4)
	var lead := TaskForce.new(1, TaskForce.Side.ROYAL_NAVY)
	lead.leader = "Gensoul"
	lead.trajectory.become_station(Vector2i(15, -3))
	st2.add_task_force(lead)
	var other := TaskForce.new(3, TaskForce.Side.ROYAL_NAVY)
	other.trajectory.become_station(Vector2i(13, -2))
	_extend_with_info(other, graph, st2)
	st2.add_task_force(other)
	var dec2 := ActionEngine.Declaration.new()
	dec2.action_key = "ENGAGE"
	dec2.active = lead
	dec2.target = TaskForce.new(4, TaskForce.Side.KRIEGSMARINE)
	eq(LeaderRules.gensoul_targets(dec2).size(), 0,
		"una TF non designata nell'Azione corrente non e' un bersaglio")
	false_(LeaderRules.gensoul_available(st2, dec2),
		"e senza bersagli il beneficio non viene offerto")
	# Designandola come Coordinatrice diventa un bersaglio lecito.
	dec2.active_coordinating = other
	eq(LeaderRules.gensoul_targets(dec2).size(), 1,
		"designata Coordinatrice, la stessa TF diventa un bersaglio")


## Allunga la Traiettoria di un segmento e gli mette un segnalino Informazioni.
func _extend_with_info(tf: TaskForce, graph: MapGraph, st: GameState) -> void:
	var from := tf.trajectory.station_hex
	for h in graph.adjacent_hexes(from):
		if tf.trajectory.extend(h, 1, graph, st.port_hexes(), true, tf.side):
			return


const OPERATIONS_MAP_SOLO := [
	"BL1 Raiders of the North Atlantic", "BL2 Contain and Destroy",
	"N4 Operazione Weser (nord & sud)", "N6 Il Dilemma delle Operazioni",
	"B1 Operazione Berlino", "B2 La Battaglia dell'Atlantico",
	"B3 Operazione Reno", "B4 Decisione sui Mari",
	"A1 Convogli PQ", "A2 L'Ultima Battaglia",
]

## Cinque scenari solitari si giocano su una MAPPA INSERTO. Il reticolo dei due
## inserti e' misurato, il grafo verificato contro le illustrazioni del
## fascicolo e il motore li carica; quello che manca, per quattro di loro, e' lo
## SCHIERAMENTO iniziale.
const INSET_MAP_SOLO := [
	"BL3 Raiders of the North Sea", "N1 Operazione Wilfred",
	"N2 Operazione Weser (nord)", "N3 Operazione Weser (sud)",
	"N5 Meglio Tardi che Mai",
]

## Gli scenari inserto che hanno gia' lo schieramento trascritto dalla loro
## illustrazione, e che il replay gioca per intero sulla mappa inserto.
const INSET_MAP_PLAYABLE := ["BL3 Raiders of the North Sea", "N1 Operazione Wilfred",
	"N2 Operazione Weser (nord)", "N3 Operazione Weser (sud)",
	"N5 Meglio Tardi che Mai"]


## Senza condizioni di fine trascritte uno scenario non finisce mai, e nel
## replay questo si vedeva come "120 turni": un difetto travestito da partita
## lunga. Ogni scenario giocabile deve averle, e con la fonte accanto.
func test_every_playable_solo_scenario_has_printed_end_conditions() -> void:
	_begin("condizioni di fine trascritte e citate")
	var missing: Array[String] = []
	var unsourced: Array[String] = []
	for id in OPERATIONS_MAP_SOLO:
		var sc := Scenario.load_by_id(id)
		var ec := sc.end_conditions()
		var rules: Array = ec.get("any", [])
		if rules.is_empty():
			missing.append(id)
			continue
		if not String(ec.get("_source", "")).contains("AC_Solo_scenarios_2022") \
				or String(ec.get("_text", "")) == "":
			unsourced.append(id)
	eq(missing.size(), 0, "scenari senza condizioni di fine: %s" % ", ".join(missing))
	eq(unsourced.size(), 0, "condizioni senza fonte o testo stampato: %s"
		% ", ".join(unsourced))


func test_inset_map_scenarios_refuse_the_operations_map() -> void:
	_begin("gli scenari su mappa inserto lo dichiarano")
	var undeclared: Array[String] = []
	var wrong_map: Array[String] = []
	var no_setup_but_playable: Array[String] = []
	for id in INSET_MAP_SOLO:
		var sc := Scenario.load_by_id(id)
		if sc.map_info.is_empty() or sc.inset_key() == "":
			undeclared.append(id)
			continue
		# Le TF di uno scenario inserto devono stare in esagoni DELL'INSERTO.
		# Prima quattro di questi le piazzavano su porti della mappa grande
		# usati come sostituti, cioe' su posizioni inventate: il controllo
		# adesso non e' piu' "nessuna TF", e' "nessuna TF fuori dalla sua mappa".
		var inset := MapGraph.load_inset(sc.inset_key())
		if inset.load_error != "":
			undeclared.append(id)
			continue
		for tf_v: Variant in sc.task_forces:
			var traj: Dictionary = (tf_v as Dictionary).get("trajectory", {})
			var hs: Array[Vector2i] = []
			for seg_v: Variant in traj.get("segments", []):
				var seg: Dictionary = seg_v
				hs.append(Vector2i(int(seg["q"]), int(seg["r"])))
			if traj.get("segments", []).is_empty():
				hs.append(Vector2i(int(traj.get("station_q", 0)),
					int(traj.get("station_r", 0))))
			for h in hs:
				if not inset.has_hex(h):
					wrong_map.append("%s %s" % [id, str(h)])
		if sc.task_forces.is_empty() and INSET_MAP_PLAYABLE.has(id):
			no_setup_but_playable.append(id)
	eq(undeclared.size(), 0, "non dichiarano il loro inserto: %s"
		% ", ".join(undeclared))
	eq(wrong_map.size(), 0, "piazzano TF fuori dalla loro mappa: %s"
		% ", ".join(wrong_map))
	eq(no_setup_but_playable.size(), 0, "dichiarati giocabili ma senza schieramento: %s"
		% ", ".join(no_setup_but_playable))

	# BL3 ha lo schieramento: il replay lo gioca, sulla SUA mappa.
	var ok_runner := SoloRunner.new()
	true_(ok_runner.load_scenario("BL3 Raiders of the North Sea", 20260803),
		"BL3 si carica: %s" % ok_runner.load_error)
	true_(ok_runner.graph != null and ok_runner.graph.is_inset(),
		"e gioca su una mappa inserto")
	eq(ok_runner.graph.inset_key, "map_north_sea", "quella giusta")
	var out := ok_runner.run()
	true_(bool(out.get("ended", false)),
		"e arriva a una fine stampata: %s" % String(out.get("stopped", "")))

	# Gli altri quattro no, e il motivo non deve essere generico.
	var refused := 0
	var says_setup := 0
	for id in INSET_MAP_SOLO:
		if INSET_MAP_PLAYABLE.has(id):
			continue
		var runner := SoloRunner.new()
		if not runner.load_scenario(id, 1):
			refused += 1
			if runner.load_error.to_lower().contains("schieramento"):
				says_setup += 1
	eq(refused, INSET_MAP_SOLO.size() - INSET_MAP_PLAYABLE.size(),
		"gli scenari senza schieramento vengono rifiutati, non giocati male")
	eq(says_setup, refused, "e il motivo dichiarato e' lo schieramento, non la mappa")


## L'interprete conosce poche forme, quelle che il fascicolo usa davvero. Una
## forma che non conosce deve rendere la regola NON soddisfatta: uno scenario
## che non finisce e' un difetto visibile, uno che finisce quando non deve e'
## una partita sbagliata in silenzio.
func test_unknown_end_condition_never_ends_the_scenario() -> void:
	_begin("una condizione sconosciuta non chiude lo scenario")
	var st := GameState.new(MapGraph.load_default(), 1)
	st.scenario_name = "prova"
	st.solo_end_conditions = {"any": [{"reason": "mai",
		"all": [{"kind": "condizione_inventata", "value": 1}]}]}
	false_(SoloAI.enforce_scenario_end(st),
		"una condizione non riconosciuta non fa finire la partita")
	false_(st.solo_ended, "e lo stato resta aperto")
	# Una regola senza condizioni non vale come "sempre vera".
	st.solo_end_conditions = {"any": [{"reason": "vuota", "all": []}]}
	false_(SoloAI.enforce_scenario_end(st), "una regola vuota non e' soddisfatta")


## A2 p.63: "no Task Forces in play (they are sunk or Completed)". La parentesi
## distingue "non ne ha piu'" da "non ne ha ancora", e in A2 conta davvero: lo
## schieramento tedesco si compra coi VP prima della prima azione, passaggio
## non modellato, quindi la partita comincia senza Task Force tedesche.
func test_a2_does_not_end_before_the_germans_ever_sailed() -> void:
	_begin("A2 non finisce prima di aver cominciato")
	var graph := MapGraph.load_default()
	var st := GameState.new(graph, 1)
	st.scenario_name = "A2 L'Ultima Battaglia"
	st.solo_end_conditions = Scenario.load_by_id("A2 L'Ultima Battaglia").end_conditions()
	false_(SoloAI.enforce_scenario_end(st),
		"senza TF tedesche mai entrate in gioco lo scenario non finisce")
	# Una nave persa: adesso la clausola stampata e' soddisfatta.
	st.casualties.append({"side": TaskForce.Side.KRIEGSMARINE,
		"ships": ["Tirpitz"], "convoys": 0})
	true_(SoloAI.enforce_scenario_end(st),
		"perse le navi, la condizione stampata scatta")
	true_(st.solo_end_reason.contains("Task Force"),
		"e il motivo cita le Task Force")


## A2 pp.67-68. Fino a ieri A2 poteva chiudersi solo per la condizione di p.63
## ("il tedesco non ha piu' Task Force in gioco"): le due fini stampate DENTRO
## la Tabella di Azione Britannica non esistevano nel codice.
func test_a2_reaches_a_printed_end_of_the_british_action_table() -> void:
	_begin("A2 arriva a una fine stampata")
	var runner := SoloRunner.new()
	true_(runner.load_scenario(A2, A2_SEED), "A2 si carica: %s" % runner.load_error)
	var out := runner.run()
	true_(bool(out["ended"]), "la partita finisce")
	eq(String(out["stopped"]), "", "e non per un blocco del ciclo")
	true_(int(out["turns"]) < SoloRunner.MAX_TURNS,
		"entro il limite di turni (%d)" % int(out["turns"]))
	true_(String(out["reason"]).contains("p.67"),
		"per una condizione della Tabella di Azione Britannica: %s" % String(out["reason"]))


## Il risultato 'E' consuma marker: Rendezvous col Meteo Cattivo, U-Boat col
## Meteo Buono. Finiti quelli, lo scenario chiude. E' l'unico consumatore dei
## due marker, quindi se il conteggio non scende la fine non arriva mai.
func test_a2_end_result_consumes_rendezvous_then_uboat_markers() -> void:
	_begin("il risultato E di A2 consuma i marker")
	var graph := MapGraph.load_default()
	var uk := TaskForce.Side.ROYAL_NAVY
	# Meteo Buono: si consumano gli U-Boat, due come da p.65.
	var st := _a2_state(graph)
	st.weather = TimeLapse.Weather.GOOD
	eq(int(st.solo_counters.get("a2_uboat_markers", -1)), 2,
		"A2 parte con due marker U-Boat (p.65)")
	var engine := ActionEngine.load_default()
	st.rng.push_forced([2])
	SoloAI.execute_code("E", st, graph, engine, {}, uk)
	eq(int(st.solo_counters.get("a2_uboat_markers", -1)), 1, "il primo E ne toglie uno")
	false_(st.solo_ended, "e non chiude ancora la partita")
	st.solo_counters["a2_uboat_markers"] = 0
	SoloAI.execute_code("E", st, graph, engine, {}, uk)
	true_(st.solo_ended, "senza marker U-Boat lo scenario finisce")
	true_(st.solo_end_reason.contains("U-Boat"), "e il motivo lo dice: %s" % st.solo_end_reason)
	# Meteo Cattivo: si consumano i Rendezvous. A2 ne schiera zero (p.63 li
	# dichiara opzionali), quindi la prima 'E' col Meteo Cattivo chiude subito.
	var st2 := _a2_state(graph)
	st2.weather = TimeLapse.Weather.BAD
	eq(st2.active_rendezvous_count(), 0, "A2 non schiera marker Rendezvous")
	SoloAI.execute_code("E", st2, graph, ActionEngine.load_default(), {}, uk)
	true_(st2.solo_ended, "col Meteo Cattivo e senza Rendezvous lo scenario finisce")
	true_(st2.solo_end_reason.contains("Rendezvous"),
		"e il motivo cita i Rendezvous: %s" % st2.solo_end_reason)


## "End? If a German BB is sunk, or three German ships are sunk, or four
## Convoys have successfully Completed, the scenario ends." Tre clausole in OR:
## ognuna va verificata da sola, altrimenti una che non scatta resta invisibile.
func test_a2_interception_ends_on_each_printed_clause() -> void:
	_begin("le tre clausole di fine del risultato X di A2")
	var graph := MapGraph.load_default()
	var uk := TaskForce.Side.ROYAL_NAVY
	var ge := TaskForce.Side.KRIEGSMARINE

	var bb := _a2_state(graph)
	bb.casualties.append({"side": ge, "ships": ["Tirpitz"], "convoys": 0})
	SoloAI.execute_code("X", bb, graph, ActionEngine.load_default(), {}, uk)
	true_(bb.solo_ended, "una BB tedesca affondata chiude lo scenario")
	true_(bb.solo_end_reason.contains("corazzata"), "e il motivo la cita")

	var three := _a2_state(graph)
	three.casualties.append({"side": ge,
		"ships": ["Scharnhorst", "Hipper", "Preugen"], "convoys": 0})
	SoloAI.execute_code("X", three, graph, ActionEngine.load_default(), {}, uk)
	true_(three.solo_ended, "tre navi tedesche affondate chiudono lo scenario")
	true_(three.solo_end_reason.contains("Tre navi"), "e il motivo le conta")

	var convoys := _a2_state(graph)
	convoys.convoys_completed = 4
	SoloAI.execute_code("X", convoys, graph, ActionEngine.load_default(), {}, uk)
	true_(convoys.solo_ended, "quattro Convogli Completati chiudono lo scenario")
	true_(convoys.solo_end_reason.contains("Quattro"), "e il motivo li conta")

	# Sotto soglia nessuna delle tre scatta: la 'X' resta un'azione normale.
	var open_game := _a2_state(graph)
	open_game.convoys_completed = 3
	open_game.casualties.append({"side": ge, "ships": ["Hipper", "Preugen"], "convoys": 0})
	SoloAI.execute_code("X", open_game, graph, ActionEngine.load_default(), {}, uk)
	false_(open_game.solo_ended, "sotto soglia la partita continua")


## Tabella di Scelta della X (p.68, nessun modificatore): 1-2 n., 3 a., 4 a.*,
## 5 b.*, 6 c. Le stelle non sono decorative: segnano i risultati che chiedono
## anche una TF Coordinatrice.
func test_a2_selection_table_matches_the_printed_die() -> void:
	_begin("la Tabella di Scelta della X di A2")
	eq(SoloAI._a2_selection_row(1), "n", "1 = n.")
	eq(SoloAI._a2_selection_row(2), "n", "2 = n.")
	eq(SoloAI._a2_selection_row(3), "a", "3 = a.")
	eq(SoloAI._a2_selection_row(4), "a*", "4 = a. con la stella")
	eq(SoloAI._a2_selection_row(5), "b*", "5 = b. con la stella")
	eq(SoloAI._a2_selection_row(6), "c", "6 = c.")


## I contatori di partenza sono dato dello scenario, non stato inventato dal
## bot: devono arrivare nello stato allo schieramento e sopravvivere a un
## salvataggio, altrimenti la fine stampata di A2 si perde ricaricando.
func test_start_counters_survive_setup_and_reload() -> void:
	_begin("i contatori di partenza arrivano nello stato e si salvano")
	var sc := Scenario.load_by_id(A2)
	eq(int(sc.solo_start_counters().get("a2_uboat_markers", -1)), 2,
		"lo scenario dichiara due marker U-Boat")
	var graph := MapGraph.load_default()
	var st := GameState.new(graph, 1)
	st.apply_dict(sc.to_state_dict())
	eq(int(st.solo_counters.get("a2_uboat_markers", -1)), 2,
		"e lo schieramento li mette nello stato")
	st.solo_counters["a2_uboat_markers"] = 1
	var reloaded := GameState.new(graph, 1)
	reloaded.apply_dict(st.to_dict())
	eq(int(reloaded.solo_counters.get("a2_uboat_markers", -1)), 1,
		"il salvataggio conserva il conteggio consumato")
	# Uno scenario che non li dichiara non se li inventa.
	eq(Scenario.load_by_id(BL1).solo_start_counters().size(), 0,
		"BL1 non dichiara contatori di partenza")


## Stato di A2 schierato dal dato, senza passare da SoloRunner: serve ai test
## che forzano una singola casella della Tabella di Azione Britannica.
func _a2_state(graph: MapGraph) -> GameState:
	var sc := Scenario.load_by_id(A2)
	var st := GameState.new(graph, 1)
	st.apply_dict(sc.to_state_dict())
	st.scenario_name = A2
	return st


## Primo passo dell'unificazione GUI/SoloRunner: l'ordine della policy del
## giocatore simulato e' un ELENCO leggibile, non una catena di if cablata.
##
## Serve perche' in una macchina a passi ogni voce diventa un caso, e chi guida
## il ciclo - il replay con la sua policy, l'interfaccia con le sue domande -
## sceglie come rispondere. Finche' l'ordine resta cablato, la GUI e' costretta
## a riscriverlo, ed e' esattamente la duplicazione da chiudere.
func test_player_policy_order_is_explicit() -> void:
	_begin("l'ordine della policy del giocatore e' esplicito")
	var runner := SoloRunner.new()
	true_(runner.load_scenario(BL1, BL1_SEED), "scenario caricato: %s" % runner.load_error)
	var order: Array[String] = runner._player_step_order()
	true_(order.size() >= 5, "l'elenco ha i suoi passi (%d)" % order.size())
	# Le due voci il cui ORDINE viene da un difetto pagato: lo sbarco in
	# Norvegia prima di ogni Completamento in porto, e il rientro prima della
	# Traiettoria - senza, una TF allunga di un segmento all'infinito.
	eq(order[0], "norway", "lo sbarco in Norvegia viene per primo")
	true_(order.find("go_home") < order.find("trajectory"),
		"il rientro viene prima della Traiettoria")
	true_(order.find("trajectory") < order.find("complete"),
		"e il Completamento di ripiego per ultimo")
	# Ogni voce dev'essere gestita: un passo senza caso e' un buco silenzioso.
	var unknown: Array[String] = []
	for step in order:
		if not ["norway", "convoy", "reinforce", "attack", "go_home",
				"trajectory", "complete"].has(step):
			unknown.append(step)
	eq(unknown.size(), 0, "nessun passo senza gestore: %s" % ", ".join(unknown))
	# Nessun doppione: due volte lo stesso passo vuol dire un ordine sbagliato.
	var seen: Array[String] = []
	var dupes: Array[String] = []
	for step in order:
		if seen.has(step):
			dupes.append(step)
		seen.append(step)
	eq(dupes.size(), 0, "nessun passo ripetuto: %s" % ", ".join(dupes))


## Passo 2 dell'unificazione: le scelte del giocatore passano da una DOMANDA
## esplicita invece di essere risolte prendendo `options[0]` dentro al ciclo.
##
## E' la cucitura che permette a un guidatore diverso - la GUI, che quelle
## scelte le deve chiedere - di riusare il ciclo invece di riscriverlo.
func test_choices_go_through_an_explicit_question() -> void:
	_begin("le scelte del giocatore passano da una domanda")
	var runner := SoloRunner.new()
	true_(runner.load_scenario(BL1, BL1_SEED), "scenario caricato: %s" % runner.load_error)
	# Il contratto: risponde con un indice valido, e la policy harness sceglie
	# la prima opzione, che e' quella che l'elenco gia' ordina per preferenza.
	var three: Array[String] = ["Kiel", "Brest", "Narvik"]
	eq(runner.ask_choice("prova", three), 0, "la policy harness prende la prima")
	true_(runner.ask_choice("prova", three) < three.size(),
		"e l'indice e' dentro l'elenco")
	# Senza opzioni non si inventa una scelta.
	eq(runner.ask_choice("prova", [] as Array[String]), -1,
		"un elenco vuoto non da' una scelta")
	# La domanda non decide da sola: la stessa risposta per elenchi diversi
	# significa che il ciclo non sta nascondendo una preferenza sua.
	eq(runner.ask_choice("altra", ["Scapa Flow"] as Array[String]), 0,
		"con una sola opzione la risposta e' quella")
	# Chi chiama puo' passare l'indice che PREFERIREBBE: certe scelte hanno un
	# criterio che vive dove stanno i numeri - allo Scorrere del Tempo si toglie
	# dal capo piu' lontano dall'obiettivo. La policy harness lo accetta sempre.
	eq(runner.ask_choice("prova", three, 2), 2, "il preferito viene accettato")
	eq(runner.ask_choice("prova", three, 9), 2,
		"e un preferito fuori elenco viene riportato dentro, non fa saltare tutto")
	eq(runner.ask_choice("prova", three, -3), 0, "anche da sotto")


## La cucitura non e' decorativa: chi risponde si puo' sostituire, e la partita
## cambia. Senza questa prova, `ask_choice` potrebbe essere un giro a vuoto e i
## test precedenti non se ne accorgerebbero.
##
## E' anche la forma che avra' `answer()` quando il ciclo diventera' una
## macchina a passi: la GUI rispondera' cosi', dopo aver chiesto all'umano.
func test_a_different_answerer_changes_the_game() -> void:
	_begin("sostituire chi risponde cambia la partita")
	var asked: Array[String] = []
	var base := SoloRunner.new()
	true_(base.load_scenario(BL2, BL2_SEED), "scenario caricato: %s" % base.load_error)
	base.answerer = func(q: String, _o: Array, p: int) -> int:
		asked.append(q)
		return p
	var plain := base.run()
	true_(asked.size() > 0, "il ciclo ha davvero posto delle domande (%d)" % asked.size())
	true_(bool(plain["ended"]), "e la partita e' finita")

	# Stessa partita, stesso seme, ma chi risponde prende l'ULTIMA opzione
	# invece della preferita. Se la cucitura conta, la trascrizione cambia.
	var other := SoloRunner.new()
	true_(other.load_scenario(BL2, BL2_SEED), "secondo scenario caricato")
	other.answerer = func(_q: String, o: Array, _p: int) -> int:
		return o.size() - 1
	var flipped := other.run()
	var a: Array = plain["transcript"]
	var b: Array = flipped["transcript"]
	var same := a.size() == b.size()
	if same:
		for i in a.size():
			if String(a[i]) != String(b[i]):
				same = false
				break
	false_(same, "la trascrizione e' diversa: le risposte contano davvero")

	# E il ciclo regge una risposta sbagliata invece di rompersi: un indice
	# fuori elenco viene riportato dentro.
	var rude := SoloRunner.new()
	true_(rude.load_scenario(BL2, BL2_SEED), "terzo scenario caricato")
	rude.answerer = func(_q: String, _o: Array, _p: int) -> int:
		return 9999
	var survived := rude.run()
	true_(bool(survived["ended"]) or String(survived["stopped"]) != "",
		"con risposte fuori elenco il ciclo arriva comunque a una fine")
