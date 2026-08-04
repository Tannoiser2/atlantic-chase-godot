extends TestCase

## Le forze Furtive: Mine, Sottomarini, U-Boat. RB p.41.
##
## La regola interessante non e' l'attacco, e' la RESTRIZIONE all'attacco: una
## Traiettoria e' immune finche' il segmento bersaglio non ha un Contatto o
## delle Informazioni. E' quella che da' un senso al segnalino Contatto, ed e'
## quella che questi test difendono.

var graph: MapGraph


func name() -> String:
	return "Forze Furtive"


func run() -> void:
	graph = MapGraph.load_default()
	test_kinds()
	test_placement_restrictions()
	test_recon_moves_and_informs()
	test_attack_restriction()
	test_enemy_force_triggers_info()
	test_save_and_reload()
	test_scenario_places_stealth_forces()
	test_n1_mines_procedure()
	test_stealth_force_performs_the_attack()
	test_decision_carries_stealth_and_modifier()
	test_time_lapse_preference_reads_both_directions()
	test_air_base_can_launch_an_air_strike()
	test_air_base_best_strike_picks_the_shortest_trajectory()


func _state() -> GameState:
	var st := GameState.new(graph, 1)
	return st


func _tf(st: GameState, side: int, hexes: Array) -> TaskForce:
	var tf := TaskForce.new(st.task_forces.size() + 1, side)
	tf.ships.append(ShipRoster.shared().make("Sheffield"))
	if hexes.size() == 1:
		tf.trajectory.become_station(hexes[0])
	else:
		for h_v: Variant in hexes:
			tf.trajectory.segments.append({"hex": h_v, "info": false, "contact": false})
	st.add_task_force(tf)
	return tf


func test_kinds() -> void:
	_begin("i tre tipi di forza Furtiva")
	eq(Stealth.kind_from_name("mine"), Stealth.Kind.MINES, "Mine")
	eq(Stealth.kind_from_name("Submarine"), Stealth.Kind.SUBMARINE, "Sottomarino")
	eq(Stealth.kind_from_name("U-Boat"), Stealth.Kind.UBOAT, "U-Boat")
	eq(Stealth.kind_name(Stealth.Kind.MINES), "Mine", "il nome torna indietro")
	# "Ricognizione: Attivare una forza di Sottomarini o U-Boat": le Mine non
	# sono nell'elenco, e una volta posate restano dove sono.
	false_(Stealth.can_recon(Stealth.Kind.MINES), "le Mine non fanno Ricognizione")
	true_(Stealth.can_recon(Stealth.Kind.SUBMARINE), "i Sottomarini si'")
	true_(Stealth.can_recon(Stealth.Kind.UBOAT), "gli U-Boat si'")


func test_placement_restrictions() -> void:
	_begin("dove si puo' piazzare una forza Furtiva")
	var st := _state()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	var open_sea := Vector2i(9, 3)
	eq(Stealth.placement_error(st, graph, {}, ge, open_sea), "",
		"il mare aperto va bene")
	false_(Stealth.can_place_at(st, graph, {}, ge, Vector2i(-99, -99)),
		"un esagono fuori mappa no")
	# Porto nemico: vietato. Lo stesso porto, se e' proprio, e' permesso.
	#
	# `port_control` contiene NOMI di parte, non interi: e' la forma che usa il
	# Completamento, ed e' quella che arriva dagli scenari. Questo test passava
	# un intero, e passava lo stesso perche' il codice faceva `int(valore)` -
	# che su una stringa non protesta, torna 0, cioe' KRIEGSMARINE. Con la forma
	# giusta il difetto e' venuto fuori: ogni porto "BOTH" o "NONE" risultava
	# tedesco.
	# NON Scapa Flow: li' c'e' una base aerea britannica stampata, e RB p.41
	# vieta il piazzamento in un esagono con una Base Aerea nemica - il che e'
	# proprio quello che il blocco piu' sotto verifica.
	var scapa := graph.port_hex("Murmansk")
	true_(scapa != Vector2i.MAX, "Murmansk e' sulla mappa")
	var control := {"Murmansk": "ROYAL_NAVY"}
	true_(Stealth.placement_error(st, graph, control, ge, scapa).contains("nemico"),
		"un porto nemico e' vietato")
	eq(Stealth.placement_error(st, graph, control, uk, scapa), "",
		"lo stesso porto, per chi lo controlla, va bene")
	# Un porto aperto a tutti e due non e' nemico di nessuno: N3 stampa Bergen
	# cosi', ed e' l'esagono che la sua Tabella indica di preferire.
	var shared := {"Murmansk": "BOTH"}
	eq(Stealth.placement_error(st, graph, shared, ge, scapa), "",
		"un porto 'BOTH' e' aperto anche all'altra parte")
	eq(Stealth.placement_error(st, graph, shared, uk, scapa), "",
		"a tutte e due, appunto")
	# "NONE" e' un porto chiuso: nessuno lo controlla, quindi e' nemico per
	# entrambi.
	var closed := {"Murmansk": "NONE"}
	true_(Stealth.placement_error(st, graph, closed, uk, scapa).contains("nemico"),
		"un porto che non controlla nessuno resta vietato")
	# E la regola che questo test non poteva provare finche' le basi aeree della
	# Mappa Operazionale non erano trascritte: mai in un esagono con una Base
	# Aerea NEMICA. Scapa Flow ne ha una britannica stampata.
	var uk_base := graph.port_hex("Scapa Flow")
	true_(Stealth.placement_error(st, graph, {}, ge, uk_base).contains("base aerea"),
		"una forza Furtiva tedesca non si piazza sulla base aerea di Scapa Flow")
	eq(Stealth.placement_error(st, graph, {}, uk, uk_base), "",
		"ma il britannico, che quella base ce l'ha, si'")
	# RB p.41 lo dice apposta: si PUO' stare in un esagono con una TF nemica che
	# contiene un CV. E' il caso che uno si aspetterebbe vietato.
	var cv := _tf(st, uk, [open_sea])
	cv.ships.append(ShipRoster.shared().make("Ark Royal"))
	eq(Stealth.placement_error(st, graph, {}, ge, open_sea), "",
		"una TF nemica con un CV non impedisce il piazzamento")


func test_recon_moves_and_informs() -> void:
	_begin("la Ricognizione sposta e genera Informazioni")
	var st := _state()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	var target_hex := Vector2i(9, 3)
	var victim := _tf(st, uk, [Vector2i(8, 3), target_hex, Vector2i(10, 3)])
	var far := _tf(st, uk, [Vector2i(4, 5), Vector2i(5, 5)])
	var force := Stealth.place(st, ge, Stealth.Kind.UBOAT, Vector2i(12, 0))
	eq(victim.trajectory.info_count(), 0, "prima non ci sono Informazioni")

	var out := Stealth.recon(st, graph, {}, force, target_hex)
	true_(bool(out["ok"]), "la Ricognizione riesce: %s" % String(out["reason"]))
	eq(Vector2i(int(force["q"]), int(force["r"])), target_hex,
		"la forza si e' spostata dove le pare: e' un piazzamento, non un movimento")
	eq(victim.trajectory.info_count(), 1,
		"la TF nemica nell'esagono prende le Informazioni")
	true_(victim.trajectory.segments[1]["info"],
		"e le prende il segmento GIUSTO, quello nell'esagono")
	eq(far.trajectory.info_count(), 0, "una TF altrove non prende niente")

	# Le Mine non fanno Ricognizione, e il rifiuto lo dice.
	var mine := Stealth.place(st, ge, Stealth.Kind.MINES, Vector2i(9, 4))
	var refused := Stealth.recon(st, graph, {}, mine, Vector2i(9, 5))
	false_(bool(refused["ok"]), "le Mine non si muovono")
	true_(String(refused["reason"]).contains("Mine"), "e il motivo lo dice")
	eq(Vector2i(int(mine["q"]), int(mine["r"])), Vector2i(9, 4),
		"e infatti la Mina non si e' mossa")


func test_attack_restriction() -> void:
	_begin("una Traiettoria e' immune senza Contatto o Informazioni")
	var st := _state()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	var h := Vector2i(9, 3)
	var moving := _tf(st, uk, [Vector2i(8, 3), h, Vector2i(10, 3)])
	var force := Stealth.place(st, ge, Stealth.Kind.UBOAT, h)

	# Il cuore della regola: senza segnalini, il segmento non si puo' colpire.
	false_(Stealth.can_attack(st, force, moving),
		"senza Contatto ne' Informazioni il segmento e' immune")
	true_(Stealth.attack_error(st, force, moving).contains("Contatto"),
		"e il motivo cita il Contatto: %s" % Stealth.attack_error(st, force, moving))
	eq(Stealth.targets_for(st, force).size(), 0, "quindi non ci sono bersagli")

	moving.trajectory.set_contact_at(h, true)
	true_(Stealth.can_attack(st, force, moving), "col Contatto si puo' colpire")
	moving.trajectory.set_contact_at(h, false)
	moving.trajectory.set_info(1, true)
	true_(Stealth.can_attack(st, force, moving), "e anche con le Informazioni")

	# Una Stazione invece e' sempre attaccabile: non le serve nessun segnalino.
	var st2 := _state()
	var parked := _tf(st2, uk, [h])
	var force2 := Stealth.place(st2, ge, Stealth.Kind.MINES, h)
	true_(parked.trajectory.is_station(), "la seconda TF e' una Stazione")
	true_(Stealth.can_attack(st2, force2, parked),
		"una Stazione si puo' colpire senza segnalini")
	eq(Stealth.targets_for(st2, force2).size(), 1, "ed e' un bersaglio")

	# Fuori esagono, e amico, non si attaccano.
	var elsewhere := _tf(st2, uk, [Vector2i(4, 5)])
	false_(Stealth.can_attack(st2, force2, elsewhere),
		"una TF in un altro esagono non si attacca")
	var friend := _tf(st2, ge, [h])
	false_(Stealth.can_attack(st2, force2, friend),
		"e nemmeno una della propria parte")


## RB p.21 elenca quattro cause che assegnano Informazioni a un segmento, e la
## quarta e' "forza Furtiva". Il commento in GameState la prometteva da sempre;
## senza le pedine non poteva essere vera.
func test_enemy_force_triggers_info() -> void:
	_begin("una forza Furtiva nemica innesca le Informazioni")
	var st := _state()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	var h := Vector2i(9, 3)
	false_(st.triggers_info(h, uk), "prima l'esagono e' innocuo")
	Stealth.place(st, ge, Stealth.Kind.MINES, h)
	true_(st.triggers_info(h, uk), "la Mina tedesca lo rende pericoloso al britannico")
	false_(st.triggers_info(h, ge), "ma non a chi l'ha posata")
	true_(Stealth.enemy_force_at(st, h, uk), "e la si trova cercandola")
	false_(Stealth.enemy_force_at(st, h, ge), "solo se e' nemica")


func test_save_and_reload() -> void:
	_begin("le forze Furtive stanno nel salvataggio")
	var st := _state()
	var ge := TaskForce.Side.KRIEGSMARINE
	Stealth.place(st, ge, Stealth.Kind.MINES, Vector2i(9, 3), "Vestfjorden")
	Stealth.place(st, TaskForce.Side.ROYAL_NAVY, Stealth.Kind.SUBMARINE, Vector2i(4, 5))
	var back := GameState.new(graph, 1)
	back.apply_dict(st.to_dict())
	eq(back.stealth_forces.size(), 2, "tornano tutte e due")
	eq(Stealth.forces_of(back, ge).size(), 1, "una per parte")
	eq(Stealth.forces_at(back, Vector2i(9, 3)).size(), 1, "e nel loro esagono")
	eq(String((Stealth.forces_at(back, Vector2i(9, 3))[0]).get("note", "")),
		"Vestfjorden", "con la nota che le e' stata data")
	true_(Stealth.remove_at(back, Vector2i(9, 3), ge), "si possono togliere")
	eq(back.stealth_forces.size(), 1, "e l'elenco si accorcia")


## Le forze Furtive schierate arrivano dallo scenario, come ogni altra pedina.
func test_scenario_places_stealth_forces() -> void:
	_begin("lo schieramento porta le forze Furtive")
	var sc := Scenario.load_by_id("BL3 Raiders of the North Sea")
	eq(sc.stealth_forces.size(), 1, "BL3 schiera una forza Furtiva")
	var inset := MapGraph.load_inset(sc.inset_key())
	var st := GameState.new(inset, 1)
	st.apply_dict(sc.to_state_dict())
	eq(st.stealth_forces.size(), 1, "e arriva nello stato")
	var f: Dictionary = st.stealth_forces[0]
	eq(Vector2i(int(f["q"]), int(f["r"])), Vector2i(5, 1),
		"il Sommergibile britannico e' in (5,1), come sull'illustrazione di p.12")
	eq(int(f["side"]), TaskForce.Side.ROYAL_NAVY, "ed e' britannico")
	true_(inset.has_hex(Vector2i(5, 1)), "in un esagono che esiste sull'inserto")
	# E deve innescare Informazioni al tedesco, che e' il punto di averlo.
	true_(st.triggers_info(Vector2i(5, 1), TaskForce.Side.KRIEGSMARINE),
		"e rende quell'esagono pericoloso al tedesco")
	# Uno scenario che non ne ha non se le inventa.
	eq(Scenario.load_by_id("BL1 Raiders of the North Atlantic").stealth_forces.size(), 0,
		"BL1 non schiera forze Furtive")


## La procedura Mine di N1 (p.17): tre esagoni bersaglio, solo una TF con un
## Convoglio, un marker per esagono, e la Reazione Norvegese sul solo Narvik.
func test_n1_mines_procedure() -> void:
	_begin("la posa delle Mine di N1")
	var sc := Scenario.load_by_id("N1 Operazione Wilfred")
	var targets := sc.mines_targets()
	eq(targets.size(), 3, "N1 dichiara tre bersagli per le Mine")
	var inset := MapGraph.load_inset(sc.inset_key())
	var st := GameState.new(inset, 1)
	st.apply_dict(sc.to_state_dict())
	eq(Stealth.mines_left(st, targets), 3, "all'inizio sono tutte da posare")

	var uk := TaskForce.Side.ROYAL_NAVY
	var narvik := Vector2i(5, -2)
	var convoy := TaskForce.new(90, uk)
	convoy.ships.append(ShipRoster.shared().make("Convoy x2"))
	convoy.trajectory.become_station(narvik)
	st.add_task_force(convoy)
	var warship := TaskForce.new(91, uk)
	warship.ships.append(ShipRoster.shared().make("Sheffield"))
	warship.trajectory.become_station(narvik)
	st.add_task_force(warship)

	# "To place a Mines marker, a TF WITH A CONVOY must successfully perform a
	# Completion action in the target hex."
	false_(Stealth.can_lay_mines(st, targets, warship, narvik),
		"una TF senza Convoglio non posa Mine")
	true_(Stealth.mines_error(st, targets, warship, narvik).contains("CONVOGLIO"),
		"e il motivo lo dice")
	false_(Stealth.can_lay_mines(st, targets, convoy, Vector2i(3, 1)),
		"e nemmeno in un esagono che non e' bersaglio")

	var out := Stealth.lay_mines(st, targets, convoy, narvik)
	true_(bool(out["ok"]), "col Convoglio nell'esagono giusto si posa: %s" % String(out["reason"]))
	true_(bool(out["time_lapse"]),
		"e si fa Scorrere del Tempo, perche' la TF NON viene rimossa (p.16)")
	# "if the Mines was placed in the Narvik (Vestfjorden) hex, check Norwegian
	# Reaction": solo li'.
	true_(bool(out["check_norwegian_reaction"]),
		"a Narvik va controllata la Reazione Norvegese")
	eq(Stealth.mines_left(st, targets), 2, "ne restano due")
	# La Mina posata e' una forza Furtiva a tutti gli effetti.
	true_(st.triggers_info(narvik, TaskForce.Side.KRIEGSMARINE),
		"e da quel momento l'esagono innesca Informazioni al nemico")

	# "one in the Narvik/Vestfjorden hex, one in the Bud hex, one in the
	# Andalsnes hex": una sola per esagono.
	var again := Stealth.lay_mines(st, targets, convoy, narvik)
	false_(bool(again["ok"]), "non se ne posa una seconda nello stesso esagono")
	true_(String(again["reason"]).contains("gia'"), "e il motivo lo dice")

	# Bud e Andalsnes non fanno scattare la Reazione.
	convoy.trajectory.become_station(Vector2i(5, 2))
	var bud := Stealth.lay_mines(st, targets, convoy, Vector2i(5, 2))
	true_(bool(bud["ok"]), "a Bud si posa")
	false_(bool(bud["check_norwegian_reaction"]),
		"ma a Bud la Reazione Norvegese non si controlla")
	eq(Stealth.mines_left(st, targets), 1, "ne resta una, ad Andalsnes")


## L'ATTACCO FURTIVO ESEGUITO DALLA FORZA FURTIVA (RB p.41).
##
## Il difetto che questi test chiudono era visibile nel registro di una partita
## BL2: "Attacco Furtivo -> Totale Traiettoria 2". Una forza Furtiva ha
## Traiettoria ZERO, quindi quel 2 diceva che l'azione la stava eseguendo una
## Task Force - cioe' che la forza Furtiva non c'entrava niente.
func test_stealth_force_performs_the_attack() -> void:
	_begin("l'Attacco Furtivo lo esegue la forza Furtiva, non una Task Force")
	var st := _state()
	var engine := ActionEngine.load_default()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	var h := Vector2i(9, 3)
	var target := _tf(st, uk, [Vector2i(8, 3), h, Vector2i(10, 3)])
	target.trajectory.set_contact_at(h, true)
	var force := Stealth.place(st, ge, Stealth.Kind.UBOAT, h)

	var dec := ActionEngine.Declaration.new()
	dec.action_key = "STEALTH_ATTACK"
	dec.active_stealth = force
	dec.target = target
	dec.target_hex = h
	eq(engine.legality_error(dec, st), "",
		"senza TF Attiva l'azione e' legale, perche' l'attaccante e' la forza")
	eq(dec.acting_side(), ge, "e la parte si legge dalla forza Furtiva")

	var res := engine.resolve(dec, st)
	true_(bool(res["ok"]), "l'azione si risolve")
	eq(int(res["trajectory_total"]), 3,
		"Totale Traiettoria: zero dall'attaccante Furtivo piu' i tre segmenti "
		+ "del bersaglio")

	# La restrizione al bersaglio resta quella di `Stealth`: e' li' che vive.
	target.trajectory.set_contact_at(h, false)
	true_(engine.legality_error(dec, st).contains("Contatto"),
		"tolto il Contatto l'azione torna illegale, col motivo stampato")

	# Una dichiarazione non puo' avere tutte e due gli attaccanti.
	target.trajectory.set_contact_at(h, true)
	dec.active = _tf(st, ge, [h])
	true_(engine.legality_error(dec, st).contains("non entrambe"),
		"forza Furtiva e TF Attiva insieme sono un errore dichiarato")


## Il modificatore che una procedura stampata impone all'azione deve arrivare
## fino al tiro: N3 p.26 da' +3 all'Attacco Furtivo del Sommergibile, e senza
## questa cucitura il +3 restava scritto nella procedura e basta.
func test_decision_carries_stealth_and_modifier() -> void:
	_begin("la decisione porta la forza Furtiva e il modificatore fino al motore")
	var st := _state()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	var h := Vector2i(9, 3)
	var target := _tf(st, uk, [h])
	var force := Stealth.place(st, ge, Stealth.Kind.UBOAT, h)

	var decision := {
		"action_key": "STEALTH_ATTACK",
		"active": null,
		"active_stealth": force,
		"target": target,
		"target_hex": h,
		"modifier": 3,
	}
	var dec := SoloSequence.declaration_for(decision)
	true_(dec != null, "la dichiarazione si costruisce senza TF Attiva")
	eq(dec.modifier, 3, "e porta il +3 stampato")
	eq(dec.active_stealth.get("kind", -1), Stealth.Kind.UBOAT,
		"e porta la forza Furtiva scelta")

	# Senza attaccante di nessun tipo, invece, non si costruisce: e' il
	# controllo che impedisce di dichiarare un'azione senza chi la esegue.
	var orphan := {"action_key": "STEALTH_ATTACK", "target": target,
		"target_hex": h}
	true_(SoloSequence.declaration_for(orphan) == null,
		"senza ne' TF ne' forza Furtiva non c'e' dichiarazione")


## Lo Scorrere del Tempo prescritto dalle procedure: quasi sempre "i segmenti
## piu' LONTANI da X", ogni tanto "i piu' VICINI a X" (N3 p.26, risultato X).
## Il conto stava scritto due volte, e conosceva solo il primo caso.
func test_time_lapse_preference_reads_both_directions() -> void:
	_begin("la preferenza dello Scorrere del Tempo legge le due direzioni")
	var st := _state()
	var uk := TaskForce.Side.ROYAL_NAVY
	# Una Traiettoria diritta: (5,0) e' il capo 0, (8,0) il capo 1.
	var tf := _tf(st, uk, [Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
		Vector2i(8, 0)])
	var goal := Vector2i(5, 0)
	var opts: Array = [
		{"ends": [1, 0], "label": "dalla testa"},
		{"ends": [0, 1], "label": "dalla coda"},
	]
	# La testa e' l'obiettivo stesso: "piu' LONTANI da" toglie dalla coda.
	eq(SoloSequence.time_lapse_preference(opts, tf.trajectory, goal, false), 1,
		"'piu' lontani da' toglie dal capo lontano dall'obiettivo")
	eq(SoloSequence.time_lapse_preference(opts, tf.trajectory, goal, true), 0,
		"'piu' vicini a' toglie dal capo vicino, che e' la frase al contrario")
	eq(SoloSequence.time_lapse_preference(opts, tf.trajectory, Vector2i.MAX), 0,
		"senza obiettivo si tiene la prima opzione, senza inventare un criterio")
	eq(SoloSequence.time_lapse_preference([], tf.trajectory, goal), -1,
		"e senza opzioni non c'e' niente da preferire")


## L'ATTACCO AEREO LANCIATO DA UNA BASE AEREA (RB p.27).
##
## "Una Task Force con una CV non danneggiata, O UNA BASE AEREA, possono essere
## designate come TF Attiva." Fino a ieri il motore conosceva solo la prima
## meta', e quattro procedure solitarie dichiaravano la lacuna e passavano.
func test_air_base_can_launch_an_air_strike() -> void:
	_begin("un Attacco Aereo puo' partire da una base aerea")
	var st := _state()
	var engine := ActionEngine.load_default()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	st.weather = TimeLapse.Weather.GOOD
	var base_hex := Vector2i(9, 3)
	var target := _tf(st, uk, [Vector2i(9, 3), Vector2i(10, 3)])
	var base := AirBase.place(st, ge, base_hex, "base di prova")

	var dec := ActionEngine.Declaration.new()
	dec.action_key = "AIR_STRIKE"
	dec.active_air_base = base
	dec.target = target
	dec.launch_hex = base_hex
	dec.target_hex = base_hex
	eq(engine.legality_error(dec, st), "",
		"senza TF Attiva l'azione e' legale, perche' la fonte e' la base aerea")
	eq(dec.acting_side(), ge, "e la parte si legge dalla base")
	var res := engine.resolve(dec, st)
	true_(bool(res["ok"]), "l'azione si risolve")
	eq(int(res["trajectory_total"]), 2,
		"Totale Traiettoria: zero dalla base piu' i due segmenti del bersaglio")

	# "L'Attacco Aereo origina dall'esagono della base aerea."
	dec.launch_hex = Vector2i(4, 5)
	true_(engine.legality_error(dec, st).contains("esagono della base aerea"),
		"il Punto di Lancio non puo' essere altrove")
	dec.launch_hex = base_hex

	# "Il bersaglio non puo' essere a piu' di due esagoni dal Punto di Lancio."
	var far := _tf(st, uk, [Vector2i(4, 5)])
	dec.target = far
	dec.target_hex = Vector2i(4, 5)
	true_(engine.legality_error(dec, st).contains("due esagoni"),
		"oltre il raggio di due esagoni l'azione e' rifiutata")

	# "Good weather only" vale come per una CV.
	dec.target = target
	dec.target_hex = base_hex
	st.weather = TimeLapse.Weather.BAD
	true_(engine.legality_error(dec, st).contains("Meteo"),
		"col Meteo Cattivo non si vola, base aerea o CV che sia")

	# Base aerea e TF Attiva insieme sono un errore dichiarato.
	st.weather = TimeLapse.Weather.GOOD
	dec.active = _tf(st, ge, [base_hex])
	true_(engine.legality_error(dec, st).contains("non entrambe"),
		"la fonte e' una sola: base aerea OPPURE Task Force")


## `AirBase.best_strike` enumera i candidati e lascia la legalita' al motore.
func test_air_base_best_strike_picks_the_shortest_trajectory() -> void:
	_begin("fra piu' bersagli a portata si sceglie la Traiettoria piu' corta")
	var st := _state()
	var graph2 := MapGraph.load_default()
	var engine := ActionEngine.load_default()
	var ge := TaskForce.Side.KRIEGSMARINE
	var uk := TaskForce.Side.ROYAL_NAVY
	st.weather = TimeLapse.Weather.GOOD
	var base_hex := Vector2i(9, 3)
	AirBase.place(st, ge, base_hex, "base di prova")
	var long_tf := _tf(st, uk, [Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3)])
	var short_tf := _tf(st, uk, [Vector2i(9, 3)])

	var strike := AirBase.best_strike(st, graph2, engine, ge)
	false_(strike.is_empty(), "un Attacco Aereo legale c'e'")
	eq(strike["target"], short_tf, "e prende la Traiettoria piu' corta")
	ne(strike["target"], long_tf, "non quella piu' lunga")

	# Col Meteo Cattivo non ce n'e' nessuno: la ricerca lo dice tacendo.
	st.weather = TimeLapse.Weather.BAD
	true_(AirBase.best_strike(st, graph2, engine, ge).is_empty(),
		"col Meteo Cattivo non c'e' nessun Attacco Aereo legale")
