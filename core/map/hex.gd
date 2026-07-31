class_name Hex
extends RefCounted

## Coordinate esagonali assiali (q, r) e conversioni verso i pixel della mappa.
##
## Il reticolo di Atlantic Chase e' ruotato di ~44.28 gradi rispetto agli assi
## dell'immagine (GMT ha inclinato la griglia per adattarla alla geografia
## dell'Atlantico), quindi le formule standard "pointy-top"/"flat-top" non si
## applicano: usiamo direttamente i due vettori di base misurati sulla mappa.
##
## Parametri misurati da tools/refine_lattice.py e validati contro le 238 pedine
## Traiettoria/Stazione dei 22 scenari ufficiali (100% nell'esagono corretto).

## Le 6 direzioni assiali, nell'ordine usato anche da map_graph.json.
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

## Nomi leggibili, utili nei log e nei messaggi di errore.
const DIR_NAMES: Array[String] = ["E", "NE", "NO", "O", "SO", "SE"]


static func neighbor(h: Vector2i, dir: int) -> Vector2i:
	return h + DIRS[dir]


static func neighbors(h: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		out.append(h + d)
	return out


## Direzione da `a` a `b` se sono adiacenti, altrimenti -1.
static func direction_between(a: Vector2i, b: Vector2i) -> int:
	var d := b - a
	for i in DIRS.size():
		if DIRS[i] == d:
			return i
	return -1


static func are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return direction_between(a, b) >= 0


## Distanza esagonale (numero minimo di passi).
static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2.0)


## Converte coordinate assiali frazionarie nell'esagono piu' vicino.
## Necessario per la conversione pixel -> esagono.
static func round_axial(qf: float, rf: float) -> Vector2i:
	# passa in coordinate cubiche, arrotonda, corregge la componente col
	# maggiore errore di arrotondamento
	var sf := -qf - rf
	var q := roundi(qf)
	var r := roundi(rf)
	var s := roundi(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(q, r)


## Tutti gli esagoni entro `radius` passi da `center` (incluso).
static func within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		var lo := maxi(-radius, -dq - radius)
		var hi := mini(radius, -dq + radius)
		for dr in range(lo, hi + 1):
			out.append(center + Vector2i(dq, dr))
	return out
