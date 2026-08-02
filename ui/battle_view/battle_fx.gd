class_name BattleFX
extends Control

## Gli effetti visivi della Battaglia: vampe, traccianti, schizzi, esplosioni,
## incendi, siluri, affondamenti.
##
## E' un Control figlio della vista della Battaglia, e questo basta a metterlo
## sopra tutto: i figli di un Control disegnano dopo il suo _draw(). E' la
## stessa regola che teneva NASCOSTO il badge dei Colpi quando le pedine erano
## nodi - qui, per una volta, gioca a favore.
##
## PRINCIPIO: gli effetti non fermano il gioco e non mangiano i tasti. Chi
## preme SPAZIO mentre una bordata e' ancora in volo la salta e va avanti,
## invece di trovarsi un tasto che non risponde. Un'animazione che blocca e'
## una animazione che al terzo Round si odia.
##
## Ogni effetto e' un Dictionary con `t0`, `dur` e `kind`. Nessun nodo, nessun
## Tween: una lista e un orologio, ripulita quando gli effetti scadono.

## Ritardo fra una cannonata e la successiva dentro la stessa bordata. Le navi
## non sparano tutte insieme: sfalsarle le rende sei navi invece di un rumore.
const SHOT_STAGGER := 0.22

const MUZZLE_DUR := 0.16
const TRACER_DUR := 0.30
const IMPACT_DUR := 0.60
const TORPEDO_DUR := 1.10
const SINK_DUR := 1.80

var _fx: Array[Dictionary] = []
var _fires: Array[Vector2] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()

var sfx: Sfx = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 7


func _process(delta: float) -> void:
	_time += delta
	var i := _fx.size() - 1
	while i >= 0:
		var e := _fx[i]
		if _time >= float(e["t0"]) + float(e["dur"]):
			_fx.remove_at(i)
		i -= 1
	if not _fx.is_empty() or not _fires.is_empty():
		queue_redraw()


## C'e' ancora qualcosa in volo?
func busy() -> bool:
	return not _fx.is_empty()


## Butta via tutto quello che sta suonando a schermo. Serve a chi preme SPAZIO
## due volte: la seconda vuol dire "ho capito, vai".
func skip() -> void:
	_fx.clear()
	queue_redraw()


func _add(kind: String, at: float, dur: float, d: Dictionary) -> void:
	d["kind"] = kind
	d["t0"] = _time + at
	d["dur"] = dur + at
	# jitter fisso alla creazione: se lo si tirasse a ogni fotogramma
	# l'effetto tremerebbe invece di restare fermo
	d["j"] = [_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()]
	_fx.append(d)


## Quanto e' avanzato questo effetto, da 0 a 1. Negativo se non e' ancora ora.
func _phase_of(e: Dictionary) -> float:
	var d := float(e["dur"])
	return 0.0 if d <= 0.0 else (_time - float(e["t0"])) / d


# ------------------------------------------------------------ eventi --

## Una bordata. `shots` e' una lista di
## { from: Vector2, to: Vector2, hit: bool, special: bool, label: String }.
##
## I colpi partono sfalsati; il suono dello schizzo o dell'esplosione arriva
## quando il proiettile ARRIVA, non quando parte - un ritardo di trecento
## millesimi, che e' poco ma e' esattamente quello che fa sembrare vero il
## resto.
func salvo(shots: Array) -> void:
	# Quante volte questo bersaglio e' gia' stato colpito in questa bordata: due
	# navi che sparano alla stessa scrivono l'esito nello stesso punto, e senza
	# impilarli le due scritte diventano una riga illeggibile.
	var stack: Dictionary = {}
	for i in shots.size():
		var s: Dictionary = shots[i]
		var at := float(i) * SHOT_STAGGER
		var from: Vector2 = s["from"]
		var to: Vector2 = s["to"]
		_add("muzzle", at, MUZZLE_DUR, {"pos": from, "dir": (to - from).normalized()})
		_add("tracer", at + 0.04, TRACER_DUR, {"from": from, "to": to})
		var hit: bool = bool(s.get("hit", false))
		var special: bool = bool(s.get("special", false))
		var impact := at + 0.04 + TRACER_DUR
		if hit or special:
			_add("blast", impact, IMPACT_DUR, {"pos": to, "big": special})
		else:
			_add("splash", impact, IMPACT_DUR, {"pos": to})
		var key := Vector2i(to.round())
		var n: int = int(stack.get(key, 0))
		stack[key] = n + 1
		_add("label", impact + 0.05, 0.9,
			{"pos": to, "text": String(s.get("label", "")), "stack": n})
		if sfx != null:
			sfx.play(Sfx.GUN, at)
			sfx.play(Sfx.HIT if (hit or special) else Sfx.SPLASH, impact)


## Un lancio di siluri: piu' lento e piu' silenzioso di una cannonata, e per
## questo piu' minaccioso.
func torpedoes(shots: Array) -> void:
	for i in shots.size():
		var s: Dictionary = shots[i]
		var at := float(i) * 0.30
		_add("torpedo", at, TORPEDO_DUR, {"from": s["from"], "to": s["to"]})
		var impact := at + TORPEDO_DUR
		if bool(s.get("hit", false)):
			_add("blast", impact, IMPACT_DUR + 0.2, {"pos": s["to"], "big": true})
			if sfx != null:
				sfx.play(Sfx.HIT, impact)
		if sfx != null:
			sfx.play(Sfx.TORPEDO, at)


## Una nave affonda. Si disegna dov'era: quando il motore la toglie dalla sua
## zona, la pedina sparisce, e una nave che scompare senza affondare e' il modo
## piu' rapido di non far capire cosa e' successo.
func sinking(rect: Rect2, at: float = 0.0) -> void:
	_add("sinking", at, SINK_DUR, {"rect": rect})
	if sfx != null:
		sfx.play(Sfx.SINK, at)


## Le navi che bruciano, in coordinate schermo. Ridisegnate a ogni fotogramma
## finche' l'incendio resta: e' l'unico effetto che non scade da solo.
func set_fires(points: Array[Vector2]) -> void:
	_fires = points
	if sfx != null:
		sfx.set_fires(points.size())
	queue_redraw()


func klaxon() -> void:
	if sfx != null:
		sfx.play(Sfx.KLAXON)


# ------------------------------------------------------------ disegno --

func _draw() -> void:
	for e in _fx:
		var p := _phase_of(e)
		if p < 0.0 or p > 1.0:
			continue
		match String(e["kind"]):
			"muzzle": _draw_muzzle(e, p)
			"tracer": _draw_tracer(e, p)
			"splash": _draw_splash(e, p)
			"blast": _draw_blast(e, p)
			"torpedo": _draw_torpedo(e, p)
			"sinking": _draw_sinking(e, p)
			"label": _draw_label(e, p)
	for f in _fires:
		_draw_fire(f)


## La vampa: un lampo bianco-giallo e un cono di fumo nella direzione del tiro.
func _draw_muzzle(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var dir: Vector2 = e["dir"]
	var k := 1.0 - p
	var r := 9.0 + 16.0 * (1.0 - k)
	draw_circle(pos, r, Color(1.0, 0.92, 0.55, 0.85 * k))
	draw_circle(pos, r * 0.45, Color(1, 1, 1, 0.95 * k))
	var tip := pos + dir * (26.0 + 30.0 * (1.0 - k))
	var perp := dir.orthogonal() * (7.0 + 9.0 * (1.0 - k))
	draw_colored_polygon(PackedVector2Array([pos + perp, pos - perp, tip]),
		Color(1.0, 0.78, 0.30, 0.55 * k))


## Il tracciante: non una linea da qui a li', ma un segmento CORTO che viaggia.
## Una linea intera fa vedere la geometria; un segmento fa vedere un proiettile.
func _draw_tracer(e: Dictionary, p: float) -> void:
	var a: Vector2 = e["from"]
	var b: Vector2 = e["to"]
	var head := a.lerp(b, p)
	var tail := a.lerp(b, maxf(p - 0.22, 0.0))
	draw_line(tail, head, Color(1.0, 0.85, 0.45, 0.85), 3.0, true)
	draw_circle(head, 3.5, Color(1, 1, 0.85, 0.95))


## Lo schizzo: colonne d'acqua che salgono e ricadono. Tre, non una: un colpo
## mancato in mare non fa un buco, fa una fila di pennacchi.
func _draw_splash(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var j: Array = e["j"]
	var rise := sin(minf(p, 1.0) * PI * 0.85)
	var alpha := (1.0 - p) * 0.9
	for i in 3:
		var dx := (float(j[i]) - 0.5) * 52.0 + float(i - 1) * 16.0
		var h := (34.0 + float(j[i]) * 26.0) * rise
		var w := 5.0 + float(j[i]) * 4.0
		var base := pos + Vector2(dx, 10.0)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-w, 0), base + Vector2(w, 0),
			base + Vector2(w * 0.45, -h), base + Vector2(-w * 0.45, -h)]),
			Color(0.92, 0.96, 1.0, alpha))
		draw_circle(base + Vector2(0, -h), w * 0.9,
			Color(1, 1, 1, alpha * 0.9))


## L'esplosione: nucleo bianco, anello arancione che si allarga, schegge.
func _draw_blast(e: Dictionary, p: float) -> void:
	var pos: Vector2 = e["pos"]
	var big: bool = bool(e.get("big", false))
	var j: Array = e["j"]
	var scale := 1.55 if big else 1.0
	var r := (14.0 + 46.0 * p) * scale
	var a := 1.0 - p
	draw_arc(pos, r, 0, TAU, 32, Color(1.0, 0.55, 0.12, a * 0.9), 5.0 * scale, true)
	draw_circle(pos, r * 0.55, Color(1.0, 0.72, 0.22, a * 0.75))
	draw_circle(pos, r * 0.26, Color(1, 1, 0.92, a))
	# schegge: partono dal centro e rallentano
	for i in 7:
		var ang := TAU * (float(i) / 7.0 + float(j[i % 4]) * 0.14)
		var d := r * (0.9 + 0.7 * float(j[(i + 1) % 4]))
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(pos + dir * d * 0.55, pos + dir * d,
			Color(0.25, 0.20, 0.18, a * 0.8), 2.5, true)
	if big:
		# fumo nero che sale, per distinguere un Risultato Grave da un Colpo
		draw_circle(pos + Vector2(0, -r * 0.8), r * 0.7 * (0.4 + p),
			Color(0.12, 0.11, 0.10, a * 0.5))


func _draw_torpedo(e: Dictionary, p: float) -> void:
	var a: Vector2 = e["from"]
	var b: Vector2 = e["to"]
	var head := a.lerp(b, p)
	var dir := (b - a).normalized()
	var perp := dir.orthogonal()
	# la scia: tratteggio che resta dietro, sempre piu' sbiadito
	var steps := 26
	for i in steps:
		var f := float(i) / float(steps) * p
		var q := a.lerp(b, f)
		var fade := f / maxf(p, 0.001)
		draw_circle(q, 2.6 + 2.0 * fade, Color(1, 1, 1, 0.32 * fade))
	draw_line(head - perp * 4.0, head + perp * 4.0, Color(0.9, 0.95, 1.0, 0.9),
		3.0, true)
	draw_circle(head, 4.0, Color(1, 1, 1, 0.95))


## L'affondamento: la pedina si inclina e scivola sotto, l'acqua si richiude.
func _draw_sinking(e: Dictionary, p: float) -> void:
	var r: Rect2 = e["rect"]
	var c := r.get_center()
	var tilt := p * 0.55
	var drop := p * r.size.y * 1.5
	var a := 1.0 - p * 0.9
	# lo scafo come sagoma, inclinato e in discesa
	var half := r.size * 0.5
	var pts := PackedVector2Array()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var v := Vector2(corner.x * half.x, corner.y * half.y).rotated(tilt)
		pts.append(c + v + Vector2(0, drop))
	draw_colored_polygon(pts, Color(0.16, 0.15, 0.14, a * 0.85))
	# schiuma sulla superficie, che si allarga
	var foam := r.size.x * (0.35 + 0.55 * p)
	draw_arc(c, foam, 0, TAU, 28, Color(1, 1, 1, (1.0 - p) * 0.7), 3.0, true)
	if p < 0.5:
		draw_circle(c, foam * 0.5, Color(0.9, 0.95, 1.0, (0.5 - p) * 0.8))


## L'incendio: due lingue di fiamma che tremolano. Il tremolio viene da un seno
## sul tempo, non da un numero a caso per fotogramma: il fuoco ondeggia, non
## sfarfalla.
func _draw_fire(pos: Vector2) -> void:
	var base := 1.0 + 0.25 * sin(_time * 11.0 + pos.x * 0.05)
	for i in 2:
		var off := Vector2(float(i) * 9.0 - 4.5, 0)
		var wob := sin(_time * (8.0 + float(i) * 3.0) + pos.y * 0.07) * 3.5
		var h := (16.0 + float(i) * 5.0) * base
		var p0 := pos + off
		draw_colored_polygon(PackedVector2Array([
			p0 + Vector2(-6, 0), p0 + Vector2(6, 0),
			p0 + Vector2(wob, -h)]), Color(1.0, 0.45, 0.08, 0.85))
		draw_colored_polygon(PackedVector2Array([
			p0 + Vector2(-3, 0), p0 + Vector2(3, 0),
			p0 + Vector2(wob * 0.6, -h * 0.6)]), Color(1.0, 0.88, 0.35, 0.9))
	draw_circle(pos + Vector2(0, -26.0 * base), 9.0,
		Color(0.15, 0.14, 0.13, 0.35))


## L'esito scritto sopra il punto d'impatto: sale e sbiadisce. E' il ponte fra
## quello che si vede e quello che dice il registro.
func _draw_label(e: Dictionary, p: float) -> void:
	var txt := String(e["text"])
	if txt == "":
		return
	var font := ThemeDB.fallback_font
	var size := 17
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var lift := 34.0 + 26.0 * p + float(int(e.get("stack", 0))) * 23.0
	var pos: Vector2 = (e["pos"] as Vector2) + Vector2(-w * 0.5, -lift)
	var a := 1.0 - p * p
	draw_string(font, pos + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		size, Color(0, 0, 0, a * 0.8))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		Color(1, 0.95, 0.75, a))
