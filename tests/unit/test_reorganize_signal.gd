extends TestCase

## Riorganizzazione (RB p.37) e Segnalazione (RB p.39), le ultime due azioni.

var graph: MapGraph


func name() -> String:
	return "Riorganizzazione + Segnalazione"


func run() -> void:
	graph = MapGraph.load_default()
	test_split()
	test_split_refusals()
	test_merge()
	test_reinforcement()
	test_signal_targets()
	test_signal_resolve()


func _state() -> GameState:
	return GameState.new(graph, 77)


func _tf(state: GameState, side: int, ships: Array[String],
		h: Vector2i) -> TaskForce:
	var tf := TaskForce.new(0, side)
	tf.color = "GE" if side == TaskForce.Side.KRIEGSMARINE else "Brown"
	tf.slot = Reorganize.in_play(state, side).size()
	tf.name = "TF%d" % (state.task_forces.size() + 1)
	tf.trajectory = Trajectory.new()
	tf.trajectory.become_station(h)
	for n in ships:
		var s := ShipRoster.shared().make(n)
		tf.ships.append(s if s != null else Ship.new(n))
	tf.recompute_speed()
	return state.add_task_force(tf)


# ------------------------------------------------------------------ dividere --

func test_split() -> void:
	_begin("dividere una Task Force")
	var st := _state()
	var h := Vector2i(15, -5)
	var tf := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck", "Preugen", "Hipper"] as Array[String], h)
	tf.trajectory.station_contact = true
	tf.evasive = true

	var moving: Array[Ship] = [tf.ships[1], tf.ships[2]]
	var r := Reorganize.split(st, tf, moving, true, false)
	true_(r["ok"], "la divisione riesce")
	var nt: TaskForce = r["new_tf"]
	eq(tf.ships.size(), 1, "una nave resta")
	eq(nt.ships.size(), 2, "due passano alla nuova")
	eq(nt.trajectory.station_hex, h, "nello stesso esagono")
	eq(nt.side, tf.side, "e dalla stessa parte")

	# i segnalini si SPOSTANO, non si moltiplicano: la divisione non ne crea
	false_(tf.trajectory.station_contact, "il Contatto lascia la vecchia")
	true_(nt.trajectory.station_contact, "e passa alla nuova")
	true_(tf.evasive, "le Manovre Evasive restano dov'erano")
	false_(nt.evasive, "e non si duplicano")

	eq(st.forces_of(TaskForce.Side.KRIEGSMARINE).size(), 2, "ora sono due")


func test_split_refusals() -> void:
	_begin("quando non si puo' dividere")
	var st := _state()
	var h := Vector2i(15, -5)

	# una nave sola non si divide
	var solo := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck"] as Array[String], h)
	true_(Reorganize.split_refusal(st, solo).contains("due navi"),
		"serve piu' di una nave")

	# una Traiettoria non si divide: solo le Stazioni
	var moving := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Scharnhorst", "Gneisenau"] as Array[String], h)
	moving.trajectory.extend(Vector2i(16, -5), 1, graph)
	true_(Reorganize.split_refusal(st, moving).contains("Stazione"),
		"solo una Stazione puo' dividersi")

	# con tutte le caselle occupate la divisione e' proibita
	var st2 := _state()
	for i in Reorganize.max_task_forces(TaskForce.Side.KRIEGSMARINE):
		_tf(st2, TaskForce.Side.KRIEGSMARINE,
			["Bismarck", "Tirpitz"] as Array[String], h)
	eq(Reorganize.free_slots(st2, TaskForce.Side.KRIEGSMARINE), 0,
		"cinque Task Force tedesche, nessuna casella libera")
	true_(Reorganize.split_refusal(st2, st2.task_forces[0]).contains("gia' in gioco"),
		"e la divisione e' proibita")
	# quelle britanniche sono dieci, e sono un conto separato
	eq(Reorganize.max_task_forces(TaskForce.Side.ROYAL_NAVY), 10,
		"dieci caselle britanniche")


# --------------------------------------------------------------------- unire --

func test_merge() -> void:
	_begin("unire due Task Force")
	var st := _state()
	var h := Vector2i(15, -5)
	var a := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Bismarck"] as Array[String], h)
	var b := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Preugen", "Hipper"] as Array[String], h)
	b.trajectory.station_contact = true
	b.evasive = true

	eq(Reorganize.merge_refusal(a, b), "", "si possono unire")
	var r := Reorganize.merge(a, b)
	true_(r["ok"], "l'unione riesce")
	eq(a.ships.size(), 3, "tutte le navi in una sola Task Force")
	eq(b.ships.size(), 0, "l'altra resta vuota")
	true_(a.trajectory.station_contact, "il Contatto passa a quella che resta")
	true_(a.evasive, "e cosi' le Manovre Evasive")
	false_(b.evasive, "che non restano anche sull'altra")

	# la pedina svuotata torna disponibile
	eq(Reorganize.in_play(st, TaskForce.Side.KRIEGSMARINE).size(), 1,
		"in gioco ne resta una")
	true_(Reorganize.free_slots(st, TaskForce.Side.KRIEGSMARINE) >= 4,
		"e le caselle libere sono tornate")

	# esagoni diversi: non si uniscono
	var c := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Tirpitz"] as Array[String], Vector2i(16, -5))
	true_(Reorganize.merge_refusal(a, c).contains("stesso esagono"),
		"servono nello stesso esagono")
	# parti diverse: nemmeno
	var d := _tf(st, TaskForce.Side.ROYAL_NAVY, ["Hood"] as Array[String], h)
	true_(Reorganize.merge_refusal(a, d).contains("parti diverse"),
		"e dalla stessa parte")
	# una Traiettoria non si unisce
	c.trajectory.become_station(h)
	c.trajectory.extend(Vector2i(16, -5), 1, graph)
	true_(Reorganize.merge_refusal(a, c).contains("Stazioni"),
		"solo Stazioni, non Traiettorie")


# ----------------------------------------------------------------- rinforzi --

func test_reinforcement() -> void:
	_begin("tentativo di Rinforzo")
	var kiel := graph.port_hex("Kiel")
	var group: Array = ["Koln", "Konigsberg"]

	# 2d6 >= 7 riesce. Con i tiri imposti si controlla il confine esatto.
	var st := _state()
	_tf(st, TaskForce.Side.KRIEGSMARINE, ["Bismarck"] as Array[String], kiel)
	st.rng.push_forced([3, 4])          # somma 7: il minimo che riesce
	var r := Reorganize.attempt_reinforcement(st, TaskForce.Side.KRIEGSMARINE,
		kiel, group, "A")
	true_(r["ok"], "il tentativo si esegue")
	eq(int(r["roll"]), 7, "2d6 = 7")
	true_(r["success"], "e 7 basta")
	false_(r["initiative_passes"], "l'Iniziativa resta")
	eq((r["tf"] as TaskForce).ships.size(), 3,
		"le navi entrano nella Stazione gia' in porto")

	# 6 fallisce, e il fallimento costa l'Iniziativa
	var st2 := _state()
	_tf(st2, TaskForce.Side.KRIEGSMARINE, ["Bismarck"] as Array[String], kiel)
	st2.rng.push_forced([3, 3])
	var r2 := Reorganize.attempt_reinforcement(st2, TaskForce.Side.KRIEGSMARINE,
		kiel, group, "A")
	eq(int(r2["roll"]), 6, "2d6 = 6")
	false_(r2["success"], "e 6 non basta")
	true_(r2["initiative_passes"], "l'Iniziativa passa all'avversario")
	eq(st2.task_forces[0].ships.size(), 1, "nessuna nave entra in gioco")

	# senza Stazione in porto si crea una Task Force nuova
	var st3 := _state()
	st3.rng.push_forced([5, 5])
	var r3 := Reorganize.attempt_reinforcement(st3, TaskForce.Side.KRIEGSMARINE,
		kiel, group, "A")
	true_(r3["success"], "riuscito")
	var nt: TaskForce = r3["tf"]
	eq(nt.trajectory.station_hex, kiel, "la nuova Task Force nasce in porto")
	eq(nt.ships.size(), 2, "con le navi del Gruppo")

	# senza Stazione in porto E senza caselle libere, e' proibito
	var st4 := _state()
	for i in Reorganize.max_task_forces(TaskForce.Side.KRIEGSMARINE):
		_tf(st4, TaskForce.Side.KRIEGSMARINE, ["Tirpitz"] as Array[String],
			Vector2i(10, 0))
	var r4 := Reorganize.attempt_reinforcement(st4,
		TaskForce.Side.KRIEGSMARINE, kiel, group, "A")
	false_(r4["ok"], "il tentativo e' proibito")
	true_(String(r4["error"]).contains("proibito"), "e lo dice")
	eq(int(r4["roll"]), 0, "senza nemmeno tirare i dadi")


# ---------------------------------------------------------------- segnalare --

## Task Force con una Traiettoria che passa per `seg`.
## Attenzione: la Stazione di partenza NON resta come segmento - una volta che
## ci sono segmenti, la Traiettoria e' fatta solo di quelli.
func _traj_tf(st: GameState, side: int, seg: Array[Vector2i]) -> TaskForce:
	var tf := _tf(st, side, ["Bismarck", "Preugen"] as Array[String],
		Vector2i(15, -5))
	for h in seg:
		tf.trajectory.extend(h, 1, graph)
	return tf


func test_signal_targets() -> void:
	_begin("chi si puo' segnalare")
	var st := _state()
	# catena davvero adiacente sulla mappa: fra 15,-5 e 15,-4 c'e' una delle
	# frecce "not adjacent", quindi quel lato non si puo' percorrere
	var path: Array[Vector2i] = [Vector2i(16, -5), Vector2i(17, -5),
		Vector2i(18, -6)]
	var km := _traj_tf(st, TaskForce.Side.KRIEGSMARINE, path)
	eq(km.trajectory.length(), 3, "la Traiettoria ha tre segmenti")

	# senza segnalini Informazioni non c'e' niente da segnalare
	true_(SignalAction.refusal(km).contains("Informazioni"),
		"senza segnalini la Segnalazione e' rifiutata")
	eq(SignalAction.target_hexes(km).size(), 0, "e nessun esagono bersaglio")

	km.trajectory.set_info(1, true)
	eq(SignalAction.refusal(km), "", "con un segnalino si puo'")
	var hs := SignalAction.target_hexes(km)
	eq(hs.size(), 1, "un solo esagono bersaglio")
	eq(hs[0], path[1], "quello del segnalino")

	# una Stazione non si segnala: e' gia' localizzata
	var station := _tf(st, TaskForce.Side.KRIEGSMARINE,
		["Tirpitz"] as Array[String], Vector2i(18, -6))
	true_(SignalAction.refusal(station).contains("gia' una Stazione"),
		"una Stazione non si segnala")

	# i candidati sono solo gli avversari con almeno un segnalino
	var cands := SignalAction.candidates(st, TaskForce.Side.ROYAL_NAVY)
	eq(cands.size(), 1, "un solo bersaglio legale")
	eq(cands[0], km, "ed e' la Traiettoria con il segnalino")
	eq(SignalAction.candidates(st, TaskForce.Side.KRIEGSMARINE).size(), 0,
		"il tedesco non puo' segnalare se stesso")


func test_signal_resolve() -> void:
	_begin("risolvere la Segnalazione")
	var st := _state()
	# catena davvero adiacente sulla mappa: fra 15,-5 e 15,-4 c'e' una delle
	# frecce "not adjacent", quindi quel lato non si puo' percorrere
	var path: Array[Vector2i] = [Vector2i(16, -5), Vector2i(17, -5),
		Vector2i(18, -6)]
	var km := _traj_tf(st, TaskForce.Side.KRIEGSMARINE, path)
	km.trajectory.set_info(0, true)
	km.trajectory.set_info(2, true)
	km.trajectory.set_contact_at(path[2], true)

	# un esagono senza segnalino non e' un bersaglio legale
	var bad := SignalAction.resolve(km, path[1])
	false_(bad["ok"], "in un esagono senza segnalino non si segnala")

	var r := SignalAction.resolve(km, path[2])
	true_(r["ok"], "la Segnalazione riesce")
	true_(km.trajectory.is_station(), "la Traiettoria diventa una Stazione")
	eq(km.trajectory.station_hex, path[2], "nell'esagono scelto")
	eq(int(r["removed_segments"]), 3, "i tre segmenti sono rimossi")
	true_(r["contact"], "il Contatto del segmento bersaglio si trasferisce")
	true_(km.trajectory.station_contact, "e la Stazione ce l'ha")
	eq(km.trajectory.info_count(), 0,
		"gli altri segnalini Informazioni spariscono con i segmenti")

	# il Contatto su un ALTRO segmento invece si perde: sapere dove una flotta
	# e' passata non e' sapere dove si trova
	var st2 := _state()
	var km2 := _traj_tf(st2, TaskForce.Side.KRIEGSMARINE, path)
	km2.trajectory.set_info(2, true)
	km2.trajectory.set_contact_at(path[0], true)
	var r2 := SignalAction.resolve(km2, path[2])
	true_(r2["ok"], "riesce lo stesso")
	false_(r2["contact"], "ma il Contatto altrove si perde")
	false_(km2.trajectory.station_contact, "e la Stazione non ce l'ha")
