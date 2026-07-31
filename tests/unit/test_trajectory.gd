extends TestCase

## Regole di Traiettoria (RB p.14-16) e Segnalini Informazioni (RB p.21).

var graph: MapGraph
var origin: Vector2i


func name() -> String:
	return "Traiettoria"


func run() -> void:
	graph = MapGraph.load_default()
	origin = _find_open_hex()
	test_station_vs_trajectory()
	test_max_length()
	test_one_segment_per_hex()
	test_extends_from_both_ends()
	test_adjacency_required()
	test_port_boxes_forbidden()
	test_removal_from_ends()
	test_becomes_station()
	test_info_markers()
	test_contact_markers()
	test_validation()
	test_serialization()


## Un esagono con tutti e 6 i vicini giocabili, per non avere sorprese ai bordi.
func _find_open_hex() -> Vector2i:
	for h_v: Variant in graph.all_hexes():
		var h: Vector2i = h_v
		if graph.adjacent_hexes(h).size() == 6:
			var ok := true
			for n in graph.adjacent_hexes(h):
				if graph.adjacent_hexes(n).size() < 4:
					ok = false
			if ok:
				return h
	return graph.all_hexes()[0]


## Costruisce una traiettoria di `n` segmenti seguendo esagoni adiacenti.
func _chain(n: int) -> Trajectory:
	var t := Trajectory.new()
	t.station_hex = origin
	var cur := origin
	var visited := {origin: true}
	for i in n:
		var nxt := Vector2i.MAX
		for cand in graph.adjacent_hexes(cur):
			if not visited.has(cand) and not t.occupies(cand):
				nxt = cand
				break
		if nxt == Vector2i.MAX:
			break
		t.extend(nxt, 1, graph)
		visited[nxt] = true
		cur = nxt
	return t


func test_station_vs_trajectory() -> void:
	_begin("Stazione o Traiettoria, non entrambi")
	var t := Trajectory.new()
	t.station_hex = origin
	true_(t.is_station(), "senza segmenti e' una Stazione")
	false_(t.is_trajectory(), "senza segmenti non e' una Traiettoria")
	eq(t.length(), 0, "una Stazione ha lunghezza zero")
	true_(t.occupies(origin), "la Stazione occupa il suo esagono")

	var nb := graph.adjacent_hexes(origin)[0]
	true_(t.extend(nb, 1, graph), "estensione dalla Stazione")
	true_(t.is_trajectory(), "con un segmento e' una Traiettoria")
	false_(t.is_station(), "con un segmento non e' una Stazione")
	eq(t.length(), 1, "un segmento")


func test_max_length() -> void:
	_begin("massimo 15 segmenti")
	var t := _chain(15)
	eq(t.length(), 15, "arrivata a 15 segmenti")
	# un ulteriore segmento adiacente deve essere rifiutato per lunghezza
	var tail: Vector2i = t.end_hex(1)
	for cand in graph.adjacent_hexes(tail):
		if not t.occupies(cand):
			var err := t.extend_error(cand, 1, graph)
			true_(err.contains("15"), "il rifiuto cita il limite di 15: " + err)
			false_(t.extend(cand, 1, graph), "il sedicesimo segmento e' rifiutato")
			break
	eq(t.length(), 15, "resta a 15")


func test_one_segment_per_hex() -> void:
	_begin("un solo segmento per esagono")
	var t := _chain(3)
	var already: Vector2i = t.segments[1]["hex"]
	var err := t.extend_error(already, 1, graph)
	ne(err, "", "riporta un errore")
	true_(err.contains("gia'"), "il motivo e' il segmento gia' presente: " + err)


func test_extends_from_both_ends() -> void:
	_begin("i segmenti si aggiungono a uno o entrambi i capi")
	var t := _chain(3)
	var head: Vector2i = t.end_hex(0)
	var tail: Vector2i = t.end_hex(1)
	ne(head, tail, "capi distinti")

	var added_head := false
	for cand in graph.adjacent_hexes(head):
		if not t.occupies(cand) and t.extend(cand, 0, graph):
			added_head = true
			eq(t.end_hex(0), cand, "il nuovo capo e' quello aggiunto")
			break
	true_(added_head, "aggiunto un segmento in testa")
	eq(t.length(), 4, "lunghezza 4")

	var added_tail := false
	for cand in graph.adjacent_hexes(tail):
		if not t.occupies(cand) and t.extend(cand, 1, graph):
			added_tail = true
			break
	true_(added_tail, "aggiunto un segmento in coda")
	eq(t.length(), 5, "lunghezza 5")


func test_adjacency_required() -> void:
	_begin("niente buchi: il nuovo segmento deve essere adiacente al capo")
	var t := _chain(2)
	var far := t.end_hex(1) + Vector2i(3, 3)
	var err := t.extend_error(far, 1, graph)
	ne(err, "", "un esagono lontano e' rifiutato")


func test_port_boxes_forbidden() -> void:
	_begin("i segmenti non possono stare nelle Caselle Porto")
	var t := _chain(1)
	var tail := t.end_hex(1)
	var target := Vector2i.MAX
	for cand in graph.adjacent_hexes(tail):
		if not t.occupies(cand):
			target = cand
			break
	if target == Vector2i.MAX:
		return
	var ports := {target: "Scapa Flow Box"}
	var err := t.extend_error(target, 1, graph, ports)
	true_(err.contains("Porto"), "rifiutato perche' Casella Porto: " + err)
	false_(t.extend(target, 1, graph, ports), "estensione rifiutata")
	# senza il vincolo porto, lo stesso esagono e' legale
	true_(t.extend(target, 1, graph, {}), "legale fuori dalle Caselle Porto")


func test_removal_from_ends() -> void:
	_begin("i segmenti si rimuovono dai capi")
	var t := _chain(4)
	var head := t.end_hex(0)
	var tail := t.end_hex(1)
	var freed := t.remove_end(0)
	eq(freed, head, "rimosso il segmento di testa")
	eq(t.length(), 3, "lunghezza 3")
	freed = t.remove_end(1)
	eq(freed, tail, "rimosso il segmento di coda")
	eq(t.length(), 2, "lunghezza 2")


func test_becomes_station() -> void:
	_begin("a zero segmenti diventa Stazione")
	var t := _chain(2)
	var h0 := t.end_hex(0)
	t.remove_end(0)
	t.remove_end(0)
	eq(t.length(), 0, "nessun segmento")
	t.become_station(h0)
	true_(t.is_station(), "e' una Stazione")
	eq(t.station_hex, h0, "posta in uno degli esagoni liberati")


func test_info_markers() -> void:
	_begin("segnalini Informazioni")
	var t := _chain(3)
	eq(t.info_count(), 0, "nessun segnalino all'inizio")
	t.set_info(1, true)
	eq(t.info_count(), 1, "un segnalino")
	false_(t.set_info(99, true), "indice fuori intervallo rifiutato")

	# il segnalino sparisce insieme al suo segmento
	var t2 := _chain(3)
	t2.set_info(0, true)
	eq(t2.info_count(), 1, "un segnalino in testa")
	t2.remove_end(0)
	eq(t2.info_count(), 0, "rimosso col segmento")

	# una Stazione non puo' avere segnalini Informazioni
	var t3 := _chain(2)
	t3.set_info(0, true)
	t3.remove_end(0)
	t3.remove_end(0)
	t3.become_station(origin)
	eq(t3.info_count(), 0, "la Stazione non ha segnalini Informazioni")


func test_contact_markers() -> void:
	_begin("segnalini Contatto")
	var t := _chain(3)
	var h: Vector2i = t.segments[1]["hex"]
	true_(t.set_contact_at(h, true), "assegnato al segmento nell'esagono")
	eq(t.contact_count(), 1, "un Contatto")
	false_(t.set_contact_at(Vector2i(999, 999), true), "esagono non occupato: rifiutato")

	# RB p.23: il Contatto sopravvive alla conversione in Stazione
	var t2 := Trajectory.new()
	t2.station_hex = origin
	t2.station_contact = true
	eq(t2.contact_count(), 1, "Contatto sulla Stazione")


func test_validation() -> void:
	_begin("validazione della forma")
	var t := _chain(4)
	eq(t.validate(graph).size(), 0, "una catena costruita legalmente e' valida")

	# catena spezzata costruita a mano
	var bad := Trajectory.new()
	bad.segments.append({"hex": origin, "info": false, "contact": false})
	bad.segments.append({"hex": origin + Vector2i(4, 4), "info": false, "contact": false})
	true_(bad.validate(graph).size() > 0, "una catena interrotta viene segnalata")

	# duplicato
	var dup := Trajectory.new()
	dup.segments.append({"hex": origin, "info": false, "contact": false})
	dup.segments.append({"hex": origin, "info": false, "contact": false})
	true_(dup.validate(graph).size() > 0, "un segmento duplicato viene segnalato")


func test_serialization() -> void:
	_begin("serializzazione")
	var t := _chain(5)
	t.set_info(2, true)
	t.set_contact_at(t.segments[0]["hex"], true)
	var round_trip := Trajectory.from_dict(t.to_dict())
	eq(round_trip.length(), t.length(), "stessa lunghezza")
	eq(round_trip.info_count(), t.info_count(), "stessi segnalini Informazioni")
	eq(round_trip.contact_count(), t.contact_count(), "stessi segnalini Contatto")
	eq(round_trip.end_hex(0), t.end_hex(0), "stessa testa")
	eq(round_trip.end_hex(1), t.end_hex(1), "stessa coda")
