extends TestCase

## Verifica la geometria del reticolo e il grafo della mappa.
##
## I valori attesi non sono inventati: vengono da tools/refine_lattice.py e
## dalla validazione contro le 238 pedine Traiettoria/Stazione dei 22 scenari
## ufficiali del modulo VASSAL.

var graph: MapGraph


func name() -> String:
	return "Hex + MapGraph"


func run() -> void:
	graph = MapGraph.load_default()
	test_graph_loads()
	test_axial_math()
	test_pixel_roundtrip()
	test_adjacency_symmetry()
	test_geometry_constants()
	test_blocked_edges()
	test_real_not_adjacent_arrows()
	test_kiel_canal()
	test_ports()


func test_graph_loads() -> void:
	_begin("caricamento grafo")
	true_(graph.load_error == "", "nessun errore di caricamento: " + graph.load_error)
	true_(graph.hex_count() > 100, "il grafo ha un numero plausibile di esagoni")
	eq(graph.map_size, Vector2i(4203, 2763), "dimensione della mappa")


func test_axial_math() -> void:
	_begin("aritmetica assiale")
	var o := Vector2i(0, 0)
	eq(Hex.neighbors(o).size(), 6, "ogni esagono ha 6 vicini geometrici")
	for d in 6:
		var n := Hex.neighbor(o, d)
		eq(Hex.direction_between(o, n), d, "direzione ritrovata")
		true_(Hex.are_adjacent(o, n), "il vicino e' adiacente")
		eq(Hex.distance(o, n), 1, "distanza 1 dal vicino")
	eq(Hex.distance(Vector2i(0, 0), Vector2i(3, 0)), 3, "distanza lungo un asse")
	eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -1)), 2, "distanza diagonale")
	false_(Hex.are_adjacent(Vector2i(0, 0), Vector2i(2, 0)), "non adiacenti a distanza 2")
	eq(Hex.within(o, 1).size(), 7, "raggio 1 = 7 esagoni")
	eq(Hex.within(o, 2).size(), 19, "raggio 2 = 19 esagoni")


func test_pixel_roundtrip() -> void:
	_begin("conversione esagono <-> pixel")
	var tested := 0
	for h_v: Variant in graph.all_hexes():
		var h: Vector2i = h_v
		var p := graph.hex_to_pixel(h)
		var back := graph.pixel_to_hex(p)
		eq(back, h, "andata e ritorno dal centro di %s" % str(h))
		# anche un punto spostato di mezzo apotema deve restare nello stesso esagono
		var jitter := p + Vector2(graph.inradius * 0.5, 0.0)
		var bj := graph.pixel_to_hex(jitter)
		true_(bj == h or Hex.are_adjacent(h, bj),
			"punto interno mappato coerentemente per %s" % str(h))
		tested += 1
		if tested >= 60:
			break
	true_(tested > 0, "almeno un esagono testato")


func test_adjacency_symmetry() -> void:
	_begin("simmetria dell'adiacenza")
	var asym := 0
	var isolated := 0
	for h_v: Variant in graph.all_hexes():
		var h: Vector2i = h_v
		var nbrs := graph.adjacent_hexes(h)
		if nbrs.is_empty():
			isolated += 1
		for n in nbrs:
			if not graph.adjacent_hexes(n).has(h):
				asym += 1
	eq(asym, 0, "nessuna adiacenza asimmetrica")
	eq(isolated, 0, "nessun esagono isolato")


func test_geometry_constants() -> void:
	_begin("costanti geometriche")
	# valori misurati: passo 213.50, rotazione 44.28 gradi
	almost(graph.spacing, 213.5, 1.0, "passo centro-centro")
	almost(graph.theta_deg, 44.28, 0.5, "rotazione del reticolo")
	almost(graph.inradius, graph.spacing / 2.0, 0.01, "apotema = meta' del passo")
	almost(graph.circumradius, graph.spacing / sqrt(3.0), 0.01,
		"circumraggio = passo / radice(3)")
	# i vettori di base devono avere la stessa lunghezza e 60 gradi fra loro
	almost(graph.e1.length(), graph.e2.length(), 0.5, "basi di uguale lunghezza")
	var ang := rad_to_deg(absf(graph.e1.angle_to(graph.e2)))
	almost(ang, 60.0, 0.5, "60 gradi fra i vettori di base")
	# i 6 vertici devono stare tutti a distanza = circumraggio dal centro
	var h: Vector2i = graph.all_hexes()[0]
	var c := graph.center_of(h)
	for v in graph.hex_corners(h):
		almost(c.distance_to(v), graph.circumradius, 0.01, "vertice sul circumcerchio")


func test_blocked_edges() -> void:
	_begin("lati negati (frecce 'not adjacent')")
	var hs := graph.all_hexes()
	var a: Vector2i = hs[0]
	var nbrs := graph.adjacent_hexes(a)
	if nbrs.is_empty():
		return
	var b: Vector2i = nbrs[0]
	true_(graph.is_adjacent(a, b), "adiacenti prima del blocco")
	graph.block_edge(a, b, true)
	false_(graph.is_adjacent(a, b), "non adiacenti dopo il blocco")
	false_(graph.is_adjacent(b, a), "il blocco e' simmetrico")
	false_(graph.adjacent_hexes(a).has(b), "il lato bloccato sparisce dai vicini")
	graph.block_edge(a, b, false)
	true_(graph.is_adjacent(a, b), "adiacenti di nuovo dopo lo sblocco")


## Le 9 frecce "not adjacent" trascritte dalla mappa (core/data/map_annotations.json).
## Il grafo e' rigenerabile; queste annotazioni no, perche' sono state lette a
## occhio. Questo test impedisce che una rigenerazione le perda in silenzio.
func test_real_not_adjacent_arrows() -> void:
	_begin("frecce 'not adjacent' stampate sulla mappa")
	var expected := [
		[Vector2i(15, -5), Vector2i(15, -4), "Scozia"],
		[Vector2i(15, -4), Vector2i(16, -5), "Firth of Forth"],
		[Vector2i(15, -4), Vector2i(16, -4), "Inghilterra nord"],
		[Vector2i(15, -3), Vector2i(16, -4), "Inghilterra centrale"],
		[Vector2i(14, -3), Vector2i(15, -4), "Canale del Nord"],
		[Vector2i(14, -3), Vector2i(15, -3), "Irlanda sud"],
		[Vector2i(16, -3), Vector2i(16, -2), "Bretagna"],
		[Vector2i(13, -7), Vector2i(13, -6), "Islanda nord"],
		[Vector2i(13, -6), Vector2i(14, -7), "Islanda est"],
	]
	eq(graph.blocked_edge_count(), expected.size(), "numero di lati negati")
	for e: Array in expected:
		var a: Vector2i = e[0]
		var b: Vector2i = e[1]
		var where: String = e[2]
		true_(graph.has_hex(a), "%s: esiste %s" % [where, str(a)])
		true_(graph.has_hex(b), "%s: esiste %s" % [where, str(b)])
		true_(Hex.are_adjacent(a, b), "%s: geometricamente adiacenti" % where)
		false_(graph.is_adjacent(a, b), "%s: passaggio negato" % where)
		false_(graph.adjacent_hexes(a).has(b), "%s: assente dai vicini" % where)

	# la conseguenza che conta: non si attraversa la Gran Bretagna
	var traj := Trajectory.new()
	traj.station_hex = Vector2i(15, -4)
	eq(traj.extend_error(Vector2i(16, -4), 1, graph),
		"passaggio negato dalla mappa ('not adjacent')",
		"una Traiettoria non puo' attraversare l'Inghilterra")


func test_kiel_canal() -> void:
	_begin("Canale di Kiel: riservato alla Kriegsmarine")
	var a := Vector2i(17, -5)
	var b := Vector2i(18, -6)
	true_(graph.has_hex(a) and graph.has_hex(b), "entrambi gli esagoni esistono")
	true_(graph.is_adjacent(a, b), "il lato non e' negato in assoluto")
	true_(graph.is_edge_restricted(a, b), "il lato e' riservato")
	true_(graph.is_adjacent_for(TaskForce.Side.KRIEGSMARINE, a, b),
		"la Kriegsmarine puo' passare")
	false_(graph.is_adjacent_for(TaskForce.Side.ROYAL_NAVY, a, b),
		"la Royal Navy no ('KW Kanal German only')")
	true_(graph.restriction_label(a, b).contains("Kiel"), "l'etichetta lo spiega")

	# e la regola arriva fino alla costruzione della Traiettoria
	var t := Trajectory.new()
	t.station_hex = a
	eq(t.extend_error(b, 1, graph, {}, TaskForce.Side.KRIEGSMARINE), "",
		"una TF tedesca puo' entrare nel canale")
	true_(t.extend_error(b, 1, graph, {}, TaskForce.Side.ROYAL_NAVY)
		.contains("riservato"), "una TF britannica no")
	eq(t.extend_error(b, 1, graph, {}), "",
		"senza indicare la nazione il vincolo non si applica (usato dall'editor)")


## Porti trascritti finora. RB p.13: un porto stampato appartiene a un esagono
## ed e' collegato a una Casella Porto.
func test_ports() -> void:
	_begin("porti collegati agli esagoni")
	var expected := {
		"Scapa Flow": Vector2i(15, -5),
		"Methil": Vector2i(15, -5),
		"Clyde": Vector2i(15, -4),
		"Liverpool": Vector2i(15, -4),
		"Portsmouth": Vector2i(16, -3),
		"Wilhelmshaven": Vector2i(17, -5),
		"Trondheim": Vector2i(17, -8),
		"Brest": Vector2i(15, -2),
		"St. Nazaire": Vector2i(16, -2),
		"Bordeaux": Vector2i(16, -2),
		"Kiel": Vector2i(18, -6),
		"Bergen": Vector2i(17, -6),
		"Hvalfjordur": Vector2i(13, -6),
		"Murmansk": Vector2i(20, -12),
		"Archangel": Vector2i(22, -13),
	}
	for name_v: Variant in expected.keys():
		var name := String(name_v)
		var h: Vector2i = expected[name]
		eq(graph.port_hex(name), h, "%s sta in %s" % [name, str(h)])
		true_(graph.has_hex(h), "%s: l'esagono e' giocabile" % name)

	# piu' porti possono condividere un esagono: Clyde e Liverpool hanno
	# perfino la stessa Casella nel modulo VASSAL
	var shared := graph.ports_in(Vector2i(15, -4))
	true_(shared.has("Clyde") and shared.has("Liverpool"),
		"Clyde e Liverpool condividono l'esagono 15,-4")
	var biscay := graph.ports_in(Vector2i(16, -2))
	true_(biscay.has("St. Nazaire") and biscay.has("Bordeaux"),
		"St. Nazaire e Bordeaux condividono l'esagono 16,-2")

	# 16,-2 e' interamente terraferma: e' giocabile SOLO perche' contiene un
	# porto (RB p.13). Senza questa eccezione i due porti sarebbero irraggiungibili.
	true_(graph.has_hex(Vector2i(16, -2)), "l'esagono dei porti di Biscaglia esiste")
	true_(graph.land_fraction(Vector2i(16, -2)) > 0.5, "ed e' quasi tutto terraferma")
	true_(graph.is_adjacent(Vector2i(15, -2), Vector2i(16, -2)),
		"vi si arriva dal mare al largo di Brest")
	false_(graph.is_adjacent(Vector2i(16, -3), Vector2i(16, -2)),
		"ma non dalla Manica: la freccia della Bretagna obbliga a girare al largo")
	eq(graph.port_hex("Porto Inesistente"), Vector2i.MAX, "porto sconosciuto")

	# RB p.15: un segmento non puo' stare in una Casella Porto (una Stazione si')
	var t := Trajectory.new()
	t.station_hex = Vector2i(15, -5)
	var nb := graph.adjacent_hexes(Vector2i(15, -5))
	if nb.is_empty():
		return
	var ports := {nb[0]: "Scapa Flow Box"}
	true_(t.extend_error(nb[0], 1, graph, ports).contains("Porto"),
		"il segmento e' rifiutato nella Casella Porto")
	eq(t.extend_error(nb[0], 1, graph, {}), "",
		"lo stesso esagono e' legale fuori dalla Casella")
