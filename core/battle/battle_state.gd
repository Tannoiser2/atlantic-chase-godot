class_name BattleState
extends RefCounted

## Stato di una Battaglia (RB pp.55-62).
##
## La Mappa di Battaglia non e' una griglia: ogni lato ha tre zone in linea,
##
##     LONTANA -- VICINA -- RAVVICINATA  |  RAVVICINATA -- VICINA -- LONTANA
##       lato A                                                lato B
##
## e ogni nave sta in una delle tre zone del PROPRIO lato. Il raggio fra due
## navi dipende soltanto dalla coppia non ordinata delle loro zone, quindi non
## serve nessuna geometria: basta una tabella a sei righe.

enum Zone { FAR, NEAR, CLOSE }
enum Kind { BATTLE, SURPRISE, LIMITED }
## Le Regole Avanzate aggiungono due fasi: l'Attitudine PRIMA del Fuoco, e gli
## Effetti Duraturi fra la Manovra e la Fuga. Vanno in fondo all'enum e non al
## loro posto logico, per non rinumerare le fasi base: una partita salvata con
## "phase": 2 deve restare in Manovra.
enum Phase { GUNNERY, TORPEDO, MANEUVER, BREAK_AWAY, ENDED, ATTITUDE,
	LINGERING }

const ZONE_LABELS := ["Lontana", "Vicina", "Ravvicinata"]
const KIND_LABELS := ["Battaglia", "Sorpresa", "Battaglia Limitata"]
const PHASE_LABELS := ["Fuoco di Cannoni", "Siluri", "Manovra", "Fuga",
	"conclusa", "Attitudine", "Effetti Duraturi"]

## L'ordine vero delle fasi in un Round, che NON e' l'ordine dell'enum.
const ORDER_BASIC := [Phase.GUNNERY, Phase.TORPEDO, Phase.MANEUVER,
	Phase.BREAK_AWAY]
const ORDER_ADVANCED := [Phase.ATTITUDE, Phase.GUNNERY, Phase.TORPEDO,
	Phase.MANEUVER, Phase.LINGERING, Phase.BREAK_AWAY]


## La fase che segue questa, o ENDED se il Round e' finito.
func next_phase() -> int:
	var order: Array = ORDER_ADVANCED if advanced else ORDER_BASIC
	var i := order.find(phase)
	if i < 0 or i + 1 >= order.size():
		return Phase.ENDED
	return int(order[i + 1])


func first_phase() -> int:
	return Phase.ATTITUDE if advanced else Phase.GUNNERY

## Si gioca con le Regole Avanzate di Battaglia?
##
## Spento (predefinito) tutto funziona come nel regolamento base: attitudini
## ignorate, tabella del Fuoco di sempre, nessun effetto speciale. Le avanzate
## sono un fascicolo a parte e si accendono di comune accordo fra i giocatori.
var advanced: bool = false

## I mini-scenari arrivano dal fascicolo gia' disposti nelle zone corrette.
## Una Battaglia nata sulla mappa operazionale, invece, deve ancora eseguire
## il piazzamento normale di `deploy()`.
var predeployed: bool = false

## Attitudini espressamente imposte dal mini-scenario al piazzamento. Le navi
## marcate ANY non entrano qui e restano una scelta del giocatore.
var fixed_setup_attitudes: Dictionary = {}

## Eccezioni dichiarate dal fascicolo dei mini-scenari. Restano dati dello
## scenario: il motore applica la regola senza riconoscere nomi come "MS3".
var skip_snafu: bool = false
## La scelta della PLANCIA per il Round corrente: nave -> "no_fire" | "stopped".
##
## Regole Avanzate: una nave che ha preso la Plancia deve scegliere, OGNI
## Round, fra non sparare e restare Ferma. Non e' un effetto che si applica da
## solo: e' una decisione del proprietario, e finora nessuno gliela chiedeva -
## il che voleva dire che la Plancia non faceva niente.
var bridge_choice: Dictionary = {}

var starting_confusion_side: int = -1
var minimum_break_away_round: int = 1

## La Battaglia e' gia' stata estesa per "nessuna nave in Corsa"? Si allunga
## una volta sola per quella condizione, se no due flotte decise a restare
## combatterebbero all'infinito.
var extended: bool = false

## Il segnalino Confusione (Verifica Snafu): chi ce l'ha, e se lo ha gia' speso.
## -1 = nessuno ce l'ha. Vale una volta sola in tutta la Battaglia, ed e'
## l'unico elemento del gioco che permette di toccare le navi altrui.
var confusion_side: int = -1
var confusion_used: bool = false

var kind: int = Kind.BATTLE
var weather: int = TimeLapse.Weather.GOOD

## Le due Task Force che combattono. `active` e' quella del giocatore Attivo.
var active_tf: TaskForce = null
var target_tf: TaskForce = null

## Esagono in cui avviene la Battaglia: al termine entrambe le TF vi diventano
## Stazioni con un segnalino Contatto (RB p.49).
var hex: Vector2i = Vector2i.ZERO

var round_number: int = 1
var last_round: int = 3
var phase: int = Phase.GUNNERY
var ended: bool = false
var end_reason: String = ""

## Navi uscite dalla Battaglia (Fuga riuscita o Fuga parziale con Evasive).
var withdrawn: Array[Ship] = []

## Navi tenute fuori dalla Mappa di Battaglia. Il valore e' un dizionario con
## round, fase, zona e attitudine d'ingresso; si usa sia per Snafu sia per gli
## ingressi prescritti da un mini-scenario.
var delayed_entry: Dictionary = {}

var log: Array[String] = []


func _init(p_kind: int = Kind.BATTLE, p_weather: int = TimeLapse.Weather.GOOD) -> void:
	kind = p_kind
	weather = p_weather
	last_round = _last_round_for(p_kind, p_weather)


static func _last_round_for(k: int, w: int) -> int:
	# RB p.62: tre round con meteo Buono, due con Avverso.
	# Una Battaglia Limitata (da SCHERMAGLIA) dura un solo round.
	if k == Kind.LIMITED:
		return 1
	return 2 if w == TimeLapse.Weather.BAD else 3


func note(s: String) -> void:
	log.append(s)


# ------------------------------------------------------------ schieramento --

## Schiera le due Task Force secondo il risultato che ha causato la Battaglia
## (RB p.55). Ritorna true se il giocatore Attivo ha il vantaggio della Sorpresa.
func deploy() -> bool:
	var surprise_advantage := false
	for s in _afloat(active_tf):
		s.battle_zone = Zone.FAR
		s.smoke = false
	for s in _afloat(target_tf):
		s.battle_zone = Zone.FAR
		s.smoke = false

	if kind == Kind.SURPRISE and active_is_faster():
		# Il giocatore Attivo piazza le navi avversarie in Vicina e/o Lontana a
		# sua scelta. Qui si sceglie Vicina, che e' la scelta piu' aggressiva e
		# quella che il giocatore fara' quasi sempre; in M5 completo la scelta
		# passera' al giocatore.
		for s in _afloat(target_tf):
			s.battle_zone = Zone.NEAR
		surprise_advantage = true
		note("Sorpresa: la TF Attiva e' piu' veloce. Le navi avversarie sono "
			+ "piazzate dall'Attivo in zona Vicina, niente Fumo iniziale, e "
			+ "l'Attivo spara per primo nel Round Uno.")
	else:
		note("%s: tutte le navi nelle rispettive zone Lontane." % KIND_LABELS[kind])
	return surprise_advantage


func active_is_faster() -> bool:
	if active_tf == null or target_tf == null:
		return false
	return active_tf.speed > target_tf.speed


# ------------------------------------------------------------------ query --

static func _afloat(tf: TaskForce) -> Array[Ship]:
	var out: Array[Ship] = []
	if tf == null:
		return out
	for s in tf.ships:
		if not s.sunk:
			out.append(s)
	return out


## Navi ancora sulla Mappa di Battaglia (a galla e non uscite).
func ships_of(tf: TaskForce) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in _afloat(tf):
		if not withdrawn.has(s) and not delayed_entry.has(s):
			out.append(s)
	return out


func active_ships() -> Array[Ship]:
	return ships_of(active_tf)


func target_ships() -> Array[Ship]:
	return ships_of(target_tf)


func all_ships() -> Array[Ship]:
	var out := active_ships()
	out.append_array(target_ships())
	return out


func enemy_of(s: Ship) -> TaskForce:
	return target_tf if active_ships().has(s) else active_tf


func own_tf_of(s: Ship) -> TaskForce:
	return active_tf if active_ships().has(s) else target_tf


func ships_in_zone(tf: TaskForce, z: int) -> Array[Ship]:
	var out: Array[Ship] = []
	for s in ships_of(tf):
		if s.battle_zone == z:
			out.append(s)
	return out


## RB p.62: la Battaglia finisce anche quando un giocatore resta senza navi.
func check_end() -> bool:
	if ended:
		return true
	if active_ships().is_empty() and not _has_delayed(active_tf):
		_end("il giocatore Attivo non ha piu' navi sulla Mappa di Battaglia")
		return true
	if target_ships().is_empty() and not _has_delayed(target_tf):
		_end("il giocatore Bersaglio non ha piu' navi sulla Mappa di Battaglia")
		return true
	return false


func _has_delayed(tf: TaskForce) -> bool:
	if tf == null:
		return false
	for s_v: Variant in delayed_entry.keys():
		var s: Ship = s_v
		if tf.ships.has(s) and not s.sunk:
			return true
	return false


func _end(reason: String) -> void:
	ended = true
	end_reason = reason
	phase = Phase.ENDED
	note("Battaglia conclusa: %s." % reason)


func end_battle(reason: String) -> void:
	_end(reason)


func summary() -> String:
	var a := active_ships().size()
	var b := target_ships().size()
	return "Round %d/%d, fase %s - %s: %d navi, %s: %d navi" % [
		round_number, last_round, PHASE_LABELS[phase],
		active_tf.display_name() if active_tf else "?", a,
		target_tf.display_name() if target_tf else "?", b]
