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
	test_manual_unplayable_hexes()
	test_kiel_canal()
	test_ports()
	test_inset_graphs_load()
	test_inset_geometry_is_exact()
	test_inset_not_adjacent_arrows_block_trajectory()
	test_inset_extras_are_data()
	test_loading_an_inset_does_not_touch_the_main_map()


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


func test_manual_unplayable_hexes() -> void:
	_begin("esagoni esclusi dopo la verifica della mappa")
	var excluded := [
		Vector2i(3, 5), Vector2i(4, -1), Vector2i(4, 0), Vector2i(4, 3),
		Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8), Vector2i(5, -2),
		Vector2i(5, -1), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 3),
		Vector2i(5, 7), Vector2i(5, 8), Vector2i(6, -2), Vector2i(6, -1),
		Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(8, -3),
		Vector2i(9, -4), Vector2i(10, -6), Vector2i(10, -5), Vector2i(11, -7),
		Vector2i(11, -6), Vector2i(12, -7),
	]
	for h: Vector2i in excluded:
		false_(graph.is_playable(h), "%s non e' giocabile" % str(h))
	true_(graph.is_playable(Vector2i(11, -5)),
		"11,-5 resta giocabile perche' contiene un RV nello schieramento BL1")


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
		"Narvik": Vector2i(17, -9),
		"St. John's": Vector2i(6, 3),
		"Halifax": Vector2i(5, 4),
		"Gibilterra": Vector2i(14, 2),
		"New York": Vector2i(4, 5),
		"Africa": Vector2i(11, 5),
		"South America": Vector2i(6, 7),
	}
	eq(graph.port_count(), 22, "tutti i porti della mappa sono collegati")
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

	# Le STRISCE porto rendono porto ogni esagono che toccano ("Port Strip -
	# each hex is a port" nella legenda), quindi occupano piu' di un esagono.
	true_(graph.is_port_strip("Africa"), "Africa e' una striscia")
	true_(graph.is_port_strip("Kiel"), "Kiel e' una striscia")
	false_(graph.is_port_strip("Clyde"), "Clyde e' un pallino")
	eq(graph.port_hexes_of("Africa").size(), 2, "la striscia Africa copre due esagoni")
	true_(graph.ports_in(Vector2i(12, 4)).has("Africa"),
		"anche il secondo esagono della striscia e' porto")
	eq(graph.port_hexes_of("South America").size(), 2, "South America copre due esagoni")
	true_(graph.ports_in(Vector2i(7, 7)).has("South America"), "idem per South America")

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


## Le due mappe inserto passano dalla stessa classe della Mappa Operazionale:
## il reticolo e' lo stesso - passo misurato 213.9 px contro 213.5 - e cambiano
## solo origine, esagoni e dati che l'inserto stampa in piu'.
func test_inset_graphs_load() -> void:
	_begin("caricamento delle mappe inserto")
	var keys := MapGraph.inset_keys()
	eq(keys.size(), 2, "ci sono due mappe inserto")
	true_(keys.has("map_north_sea"), "c'e' il Mare del Nord")
	true_(keys.has("map_norwegian_sea"), "c'e' il Mare di Norvegia")
	var ns := MapGraph.load_inset("map_north_sea")
	eq(ns.load_error, "", "il Mare del Nord si carica")
	true_(ns.is_inset(), "e si dichiara inserto")
	eq(ns.hex_count(), 34, "34 esagoni sul Mare del Nord")
	# Cinque pallini stampati - i cerchi VUOTI sono Punti di Interesse, non
	# porti - piu' le caselle fuori mappa che il fascicolo usa come porti. Qui
	# e' Portsmouth: Kiel e Scapa Flow hanno gia' il loro pallino.
	eq(ns.port_count(), 6,
		"5 porti stampati piu' Portsmouth, che e' una casella fuori mappa")
	eq(ns.port_hex("Scapa Flow"), Vector2i(1, 0), "Scapa Flow e' in 1,0")
	ne(ns.port_hex("Portsmouth"), Vector2i.MAX,
		"una casella fuori mappa che sulla mappa grande e' un porto lo e' anche qui")
	var nw := MapGraph.load_inset("map_norwegian_sea")
	eq(nw.load_error, "", "il Mare di Norvegia si carica")
	eq(nw.hex_count(), 33, "33 esagoni sul Mare di Norvegia")
	eq(nw.port_hex("Narvik"), Vector2i(5, -2), "Narvik e' in 5,-2")
	# Senza questa traduzione il tedesco di N1 non poteva Completare da nessuna
	# parte: la sua Tabella dei Porti (p.18) elenca Murmansk e Kiel, e sul Mare
	# di Norvegia sono bande stampate ai bordi, non pallini.
	ne(nw.port_hex("Kiel"), Vector2i.MAX, "Kiel e' un porto anche qui")
	ne(nw.port_hex("Murmansk"), Vector2i.MAX, "e Murmansk pure")
	eq(nw.port_hex("Denmark Strait"), Vector2i.MAX,
		"il Denmark Strait invece NON e' un porto: non lo e' su nessuna mappa, "
		+ "e chi lo nomina deve dichiarare che cosa ne fa")
	var bad := MapGraph.load_inset("map_del_mare_inventato")
	true_(bad.load_error != "", "un inserto che non esiste da' un errore, non un grafo vuoto")


## Due trappole prese scrivendo il caricatore, e nessuna delle due si vedeva
## nei numeri: il dato dell'inserto salva `theta_deg` come angolo dei VERTICI
## mentre `hex_corners()` lo vuole come direzione di BASE (30 gradi di
## differenza), e le sue (q,r) sono ribasate sull'angolo della cornice, quindi
## senza l'origine ribasata `hex_to_pixel` sbaglia di una cella e mezzo.
## I centri restavano giusti in tutti e due i casi, perche' vengono dal JSON.
func test_inset_geometry_is_exact() -> void:
	_begin("geometria delle mappe inserto")
	for key_v: Variant in MapGraph.inset_keys():
		var g := MapGraph.load_inset(String(key_v))
		var worst_center := 0.0
		var worst_corner := 0.0
		var worst_mid := 0.0
		var worst_align := 0.0
		for h_v: Variant in g.all_hexes():
			var h: Vector2i = h_v
			worst_center = maxf(worst_center, g.center_of(h).distance_to(g.hex_to_pixel(h)))
			var c := g.center_of(h)
			var corners := g.hex_corners(h)
			for p in corners:
				worst_corner = maxf(worst_corner, absf(c.distance_to(p) - g.circumradius))
			for i in 6:
				var mid := (corners[i] + corners[(i + 1) % 6]) * 0.5
				worst_mid = maxf(worst_mid, absf(c.distance_to(mid) - g.inradius))
			for n in g.adjacent_hexes(h):
				var dir := (g.center_of(n) - c).normalized()
				for p2 in corners:
					worst_align = maxf(worst_align, absf(dir.dot((p2 - c).normalized())))
		true_(worst_center < 1.0,
			"hex_to_pixel ritrova i centri salvati (errore %.2f px)" % worst_center)
		true_(worst_corner < 1.0,
			"i vertici stanno sul circumraggio (errore %.2f px)" % worst_corner)
		true_(worst_mid < 1.0,
			"i punti medi dei lati stanno sull'inraggio (errore %.2f px)" % worst_mid)
		# Un vertice punta a meta' strada fra due vicini: cos(30) = 0.866. Se
		# theta fosse sbagliato di 30 gradi verrebbe 1.0, cioe' un vertice
		# puntato dritto su un vicino.
		true_(worst_align < 0.9,
			"i vertici puntano fra i vicini, non verso di essi (%.3f)" % worst_align)


## RB p.4 e FAQ p.44: la freccia "non adiacente" nega la Traiettoria fra i due
## esagoni che collega. Sono i `blocked_edges` della mappa grande con un altro
## nome, e il caricatore li deve trattare uguale.
func test_inset_not_adjacent_arrows_block_trajectory() -> void:
	_begin("le frecce non adiacente degli inserti negano l'adiacenza")
	var ns := MapGraph.load_inset("map_north_sea")
	eq(ns.blocked_edge_count(), 6, "sei frecce sul Mare del Nord")
	true_(Hex.are_adjacent(Vector2i(1, 1), Vector2i(1, 2)),
		"1,1 e 1,2 sono vicini geometrici")
	false_(ns.is_adjacent(Vector2i(1, 1), Vector2i(1, 2)),
		"ma la freccia in Scozia nega l'adiacenza")
	false_(ns.adjacent_hexes(Vector2i(1, 1)).has(Vector2i(1, 2)),
		"e il vicino sparisce anche dall'elenco")
	true_(ns.is_adjacent(Vector2i(2, 0), Vector2i(3, 0)),
		"un lato senza freccia resta adiacente")
	var nw := MapGraph.load_inset("map_norwegian_sea")
	eq(nw.blocked_edge_count(), 3, "tre frecce sul Mare di Norvegia")
	false_(nw.is_adjacent(Vector2i(6, 1), Vector2i(6, 0)),
		"la freccia a Trondheim nega l'adiacenza")


## Basi aeree, Punti di Interesse e caselle fuori mappa sono DATO esposto, non
## regole implementate: il motore non gioca ancora gli Attacchi Aerei da base
## aerea, e i Punti di Interesse per regola non fanno nulla (p.16).
func test_inset_extras_are_data() -> void:
	_begin("i dati in piu' delle mappe inserto")
	var ns := MapGraph.load_inset("map_north_sea")
	eq(ns.air_bases_of("UK").size(), 5, "cinque basi aeree britanniche")
	eq(ns.air_bases_of("GE").size(), 2, "due basi aeree tedesche")
	eq(ns.air_bases_of().size(), 7, "sette in tutto")
	eq(int(ns.air_base_at(Vector2i(2, 0)).get("range_hexes", 0)), 2,
		"e il raggio stampato e' due esagoni (RB p.27)")
	true_(ns.air_base_at(Vector2i(3, 1)).is_empty(),
		"dove non c'e' base aerea non si inventa niente")
	eq(ns.off_map_box_hexes("Portsmouth"), [Vector2i(3, 4)] as Array[Vector2i],
		"la Casella di Portsmouth tocca 3,4")
	true_(ns.off_map_box_names().has("Norwegian Sea"), "c'e' il passaggio al Mare di Norvegia")

	var nw := MapGraph.load_inset("map_norwegian_sea")
	eq(nw.air_bases_of().size(), 0,
		"il Mare di Norvegia non stampa basi aeree, e zero e' il numero giusto")
	# "nearest Denmark Strait port hex" (p.18) e' al plurale, e infatti sono due.
	eq(nw.off_map_box_hexes("Denmark Strait").size(), 2,
		"lo Stretto di Danimarca designa due esagoni")
	eq(nw.points_of_interest_in(Vector2i(6, 1)), ["Andalsnes"] as Array[String],
		"Andalsnes e' un Punto di Interesse, non un porto")
	true_(nw.port_hex("Andalsnes") == Vector2i.MAX,
		"e infatti non risulta fra i porti")
	true_(nw.off_map_boxes_at(Vector2i(2, 5)).has("Scapa Flow"),
		"2,5 tocca la Casella di Scapa Flow, dove in N1 Completano i Convogli")


## Caricare un inserto non deve cambiare la Mappa Operazionale: sono due
## istanze separate, e la mappa grande e' quella che gioca oggi.
func test_loading_an_inset_does_not_touch_the_main_map() -> void:
	_begin("le due mappe convivono")
	var before := graph.hex_count()
	var ns := MapGraph.load_inset("map_north_sea")
	var main := MapGraph.load_default()
	eq(main.hex_count(), before, "la mappa grande ha sempre i suoi esagoni")
	false_(main.is_inset(), "e non si dichiara inserto")
	eq(main.air_bases_of().size(), 0,
		"la mappa grande non porta basi aeree: non sono trascritte per lei")
	true_(main.hex_count() != ns.hex_count(), "le due mappe restano distinte")
	true_(main.port_count() > ns.port_count(), "e hanno porti diversi")
