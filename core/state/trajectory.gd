class_name Trajectory
extends RefCounted

## Una Task Force e' rappresentata da una Stazione OPPURE da una Traiettoria,
## mai da entrambe (RB p.14). Questa classe modella entrambi gli stati:
##
##   segments vuoto  -> la TF e' una STAZIONE, posta in station_hex
##   segments pieno  -> la TF e' una TRAIETTORIA
##
## Regole di forma implementate (RB p.15-16):
##   - massimo 15 segmenti, minimo 1 (sotto = Stazione)
##   - un solo segmento per esagono (per questa TF; altre TF possono condividerlo)
##   - i segmenti non possono stare nelle Caselle Porto (una Stazione si')
##   - forma lineare: una sola linea con esattamente due capi
##   - niente buchi, niente biforcazioni
##   - i segmenti si aggiungono e si rimuovono SOLO dai capi

const MAX_SEGMENTS := 15

## Ogni segmento: { "hex": Vector2i, "info": bool, "contact": bool }
var segments: Array[Dictionary] = []

## Valido solo quando segments e' vuoto.
var station_hex: Vector2i = Vector2i.ZERO

## Un segnalino Contatto puo' stare anche su una Stazione (RB p.23).
var station_contact: bool = false

## La Stazione puo' stare in una Casella Porto; in tal caso il nome del box.
var station_port: String = ""


# ------------------------------------------------------------------- stato --

func is_station() -> bool:
	return segments.is_empty()


func is_trajectory() -> bool:
	return not segments.is_empty()


## Numero di segmenti. Una Stazione ne ha zero (usato dal Totale Traiettoria).
func length() -> int:
	return segments.size()


func hexes() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for s in segments:
		out.append(s["hex"] as Vector2i)
	return out


func occupies(h: Vector2i) -> bool:
	if is_station():
		return station_hex == h
	for s in segments:
		if (s["hex"] as Vector2i) == h:
			return true
	return false


## L'esagono a un capo. end 0 = testa (indice 0), end 1 = coda (ultimo).
func end_hex(end: int) -> Vector2i:
	if is_station():
		return station_hex
	return segments[0]["hex"] if end == 0 else segments[-1]["hex"]


func info_count() -> int:
	var n := 0
	for s in segments:
		if s["info"]:
			n += 1
	return n


func has_info() -> bool:
	return info_count() > 0


func contact_count() -> int:
	var n := 0
	for s in segments:
		if s["contact"]:
			n += 1
	if is_station() and station_contact:
		n += 1
	return n


# ------------------------------------------------------- estensione (RB 16) --

## Puo' un segmento essere aggiunto in `h` al capo `end`?
## `end` 0 = davanti, 1 = dietro. Per una Stazione entrambi valgono uguale.
func can_extend(h: Vector2i, end: int, graph: MapGraph, port_hexes: Dictionary = {}) -> bool:
	return extend_error(h, end, graph, port_hexes) == ""


## Come can_extend ma restituisce il motivo del rifiuto (stringa vuota = ok).
## Avere il motivo per esteso serve alla UI: si mostra al giocatore perche' una
## mossa non e' legale invece di limitarsi a ignorare il click.
func extend_error(h: Vector2i, end: int, graph: MapGraph,
		port_hexes: Dictionary = {}) -> String:
	if segments.size() >= MAX_SEGMENTS:
		return "una Traiettoria non puo' superare i %d segmenti" % MAX_SEGMENTS
	if not graph.is_playable(h):
		return "esagono fuori dall'area di gioco"
	if port_hexes.has(h):
		return "un segmento non puo' stare in una Casella Porto"
	if occupies(h):
		return "questa Task Force ha gia' un segmento in quell'esagono"
	var from := end_hex(end)
	if not graph.is_adjacent(from, h):
		if Hex.are_adjacent(from, h):
			return "passaggio negato (lati 'not adjacent')"
		return "l'esagono non e' adiacente al capo della Traiettoria"
	return ""


## Aggiunge un segmento al capo indicato. Ritorna false se illegale.
## `info` va messo a true dal chiamante quando l'esagono innesca Informazioni
## (porto nemico, base aerea, Stazione TF nemica, forza Furtiva) - RB p.21.
func extend(h: Vector2i, end: int, graph: MapGraph, port_hexes: Dictionary = {},
		info: bool = false) -> bool:
	if extend_error(h, end, graph, port_hexes) != "":
		return false
	var seg := {"hex": h, "info": info, "contact": false}
	if is_station():
		# la Stazione diventa Traiettoria: il primo segmento parte dalla Stazione
		segments.append(seg)
		station_contact = false
		station_port = ""
	elif end == 0:
		segments.insert(0, seg)
	else:
		segments.append(seg)
	return true


# --------------------------------------------------------- rimozione (RB 16) --

## Rimuove un segmento dal capo indicato. Ritorna l'esagono liberato,
## o Vector2i.MAX se non c'era nulla da rimuovere.
func remove_end(end: int) -> Vector2i:
	if segments.is_empty():
		return Vector2i.MAX
	var seg: Dictionary = segments.pop_front() if end == 0 else segments.pop_back()
	return seg["hex"] as Vector2i


## True se il segmento al capo `end` ha un segnalino Informazioni.
func end_has_info(end: int) -> bool:
	if segments.is_empty():
		return false
	return segments[0]["info"] if end == 0 else segments[-1]["info"]


## Trasforma in Stazione. Secondo RB p.14/p.19 la Stazione puo' essere posta in
## QUALSIASI esagono che ha appena rimosso un segmento; il chiamante sceglie.
## I segnalini Informazioni spariscono (una Stazione non puo' averne) - RB p.21.
## Un eventuale segnalino Contatto nell'esagono scelto passa alla Stazione.
func become_station(h: Vector2i, keep_contact: bool = false) -> void:
	segments.clear()
	station_hex = h
	station_contact = keep_contact
	station_port = ""


# ----------------------------------------------------------- segnalini info --

func set_info(index: int, value: bool) -> bool:
	if index < 0 or index >= segments.size():
		return false
	segments[index]["info"] = value
	return true


func index_of_hex(h: Vector2i) -> int:
	for i in segments.size():
		if (segments[i]["hex"] as Vector2i) == h:
			return i
	return -1


## Assegna Contatto al segmento (o alla Stazione) nell'esagono. RB p.23:
## uno solo per segmento/Stazione.
func set_contact_at(h: Vector2i, value: bool) -> bool:
	if is_station():
		if station_hex != h:
			return false
		station_contact = value
		return true
	var i := index_of_hex(h)
	if i < 0:
		return false
	segments[i]["contact"] = value
	return true


# -------------------------------------------------------------- validazione --

## Verifica invarianti di forma. Ritorna la lista dei problemi (vuota = valida).
## Usata dai test e dall'editor; il gioco normale non dovrebbe mai violarle.
func validate(graph: MapGraph) -> Array[String]:
	var errs: Array[String] = []
	if segments.size() > MAX_SEGMENTS:
		errs.append("troppi segmenti: %d" % segments.size())
	var seen := {}
	for s in segments:
		var h: Vector2i = s["hex"]
		if seen.has(h):
			errs.append("segmento duplicato in %s (biforcazione o buco)" % str(h))
		seen[h] = true
		if not graph.is_playable(h):
			errs.append("segmento fuori area in %s" % str(h))
	for i in range(segments.size() - 1):
		var a: Vector2i = segments[i]["hex"]
		var b: Vector2i = segments[i + 1]["hex"]
		if not graph.is_adjacent(a, b):
			errs.append("catena interrotta fra %s e %s" % [str(a), str(b)])
	var infos := 0
	for s in segments:
		if s["info"]:
			infos += 1
	if is_station() and infos > 0:
		errs.append("una Stazione non puo' avere segnalini Informazioni")
	return errs


# ---------------------------------------------------------- serializzazione --

func to_dict() -> Dictionary:
	var segs: Array = []
	for s in segments:
		var h: Vector2i = s["hex"]
		segs.append({"q": h.x, "r": h.y, "info": s["info"], "contact": s["contact"]})
	return {
		"segments": segs,
		"station_q": station_hex.x,
		"station_r": station_hex.y,
		"station_contact": station_contact,
		"station_port": station_port,
	}


static func from_dict(d: Dictionary) -> Trajectory:
	var t := Trajectory.new()
	for s_v: Variant in d.get("segments", []):
		var s: Dictionary = s_v
		t.segments.append({
			"hex": Vector2i(int(s["q"]), int(s["r"])),
			"info": bool(s.get("info", false)),
			"contact": bool(s.get("contact", false)),
		})
	t.station_hex = Vector2i(int(d.get("station_q", 0)), int(d.get("station_r", 0)))
	t.station_contact = bool(d.get("station_contact", false))
	t.station_port = String(d.get("station_port", ""))
	return t


func duplicate_traj() -> Trajectory:
	return Trajectory.from_dict(to_dict())
