class_name Sfx
extends Node

## Gli effetti sonori della Battaglia.
##
## I suoni sono generati da `tools/make_sounds.py`, non campionati: niente
## file di terzi, niente licenze, e si rigenerano cambiando due numeri.
##
## Un pool di lettori invece di uno solo, perche' in una bordata partono sei
## cannonate ravvicinate e con un lettore unico la seconda taglierebbe la
## prima. Ogni colpo esce con un'altezza leggermente diversa: sei cannonate
## identiche suonano come un difetto, non come una battaglia.

const DIR := "res://assets/audio/"
const VOICES := 8

const GUN := "gun"
const SPLASH := "splash"
const HIT := "hit"
const TORPEDO := "torpedo"
const SINK := "sink"
const FIRE := "fire"
const KLAXON := "klaxon"

## Volume di ogni suono, in decibel. Le cannonate sono tante e vanno tenute
## indietro; l'affondamento e' uno solo e deve pesare.
const GAIN := {
	GUN: -9.0, SPLASH: -13.0, HIT: -5.0, TORPEDO: -10.0,
	SINK: 0.0, FIRE: -17.0, KLAXON: -8.0,
}

## Quanto puo' variare l'altezza, in semitoni-ish (moltiplicatore).
const PITCH_SPREAD := {GUN: 0.14, SPLASH: 0.18, HIT: 0.10, TORPEDO: 0.08}

static var muted := false

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _fire_player: AudioStreamPlayer = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Headless non ha un'uscita audio: caricare i suoni li' sarebbe lavoro
	# buttato, e i test di fumo girano headless.
	if DisplayServer.get_name() == "headless":
		muted = true
		return
	_rng.randomize()
	for n in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_voices.append(p)
	_fire_player = AudioStreamPlayer.new()
	add_child(_fire_player)


func _stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := DIR + name + ".wav"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


## Suona un effetto. `delay` in secondi: serve a far arrivare lo schizzo
## quando il proiettile ci arriva, non quando parte.
func play(name: String, delay: float = 0.0) -> void:
	if muted:
		return
	if delay > 0.0:
		var tm := get_tree().create_timer(delay)
		tm.timeout.connect(func() -> void: play(name))
		return
	var s := _stream(name)
	if s == null:
		return
	var p := _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = s
	p.volume_db = float(GAIN.get(name, -6.0))
	var spread := float(PITCH_SPREAD.get(name, 0.0))
	p.pitch_scale = 1.0 + _rng.randf_range(-spread, spread)
	p.play()


## Il crepitio dell'incendio: uno solo, in ciclo, con il volume che cresce col
## numero di navi che bruciano. Un lettore per nave sarebbe rumore su rumore.
##
## Il ciclo e' impostato in assets/audio/fire.wav.import, non qui: il file e'
## importato compresso in QOA, e mettere loop_end contando i byte del PCM
## darebbe un punto di ripetizione sbagliato.
func set_fires(count: int) -> void:
	if muted or _fire_player == null:
		return
	if count <= 0:
		if _fire_player.playing:
			_fire_player.stop()
		return
	var s := _stream(FIRE)
	if s == null:
		return
	_fire_player.volume_db = float(GAIN[FIRE]) + minf(float(count - 1) * 2.5, 5.0)
	if not _fire_player.playing:
		_fire_player.stream = s
		_fire_player.play()


func stop_all() -> void:
	for p in _voices:
		p.stop()
	if _fire_player != null:
		_fire_player.stop()
