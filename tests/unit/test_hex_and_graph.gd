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
