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
	var scapa := graph.port_hex("Scapa Flow")
	true_(scapa != Vector2i.MAX, "Scapa Flow e' sulla mappa")
	var control := {"Scapa Flow": uk}
	true_(Stealth.placement_error(st, graph, control, ge, scapa).contains("nemico"),
		"un porto nemico e' vietato")
	eq(Stealth.placement_error(st, graph, control, uk, scapa), "",
		"lo stesso porto, per chi lo controlla, va bene")
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
