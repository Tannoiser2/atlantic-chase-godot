class_name Reorganize
extends RefCounted

## Azione Riorganizzazione (RB p.37): dividere, unire, chiamare rinforzi.
##
## E' l'azione piu' "amministrativa" del gioco e insieme una delle piu'
## importanti: e' l'unico modo di cambiare la composizione delle Task Force in
## corsa, e l'unico modo di far entrare in gioco i rinforzi.
##
## Con una sola dichiarazione si possono fare PIU' cose - piu' divisioni, piu'
## unioni, piu' tentativi di Rinforzo - quindi qui non c'e' una `resolve()` che
## fa tutto: ci sono le tre operazioni separate, e chi chiama le mette in fila
## quante volte vuole finche' il tentativo di Rinforzo non fallisce.
##
## Il tentativo di Rinforzo e' l'unica delle tre che puo' andare male, e quando
## va male costa caro: una Task Force effettua lo Scorrere del Tempo e
## l'Iniziativa passa subito all'avversario.

## Quante Task Force ha ciascuna parte sul Display: cinque caselle tedesche
## (KM TF, KM TF-1..4) e dieci britanniche (Brown, Red, Tan). Sono i limiti
## fisici del gioco da tavolo, e valgono anche qui: "se tutte le Task Force
## sono gia' in gioco, Dividersi e' proibito".
const MAX_TASK_FORCES := {
	TaskForce.Side.KRIEGSMARINE: 5,
	TaskForce.Side.ROYAL_NAVY: 10,
}

## 2d6, 7 o piu': il tentativo di Rinforzo riesce.
const REINFORCE_TARGET := 7


static func max_task_forces(side: int) -> int:
	return int(MAX_TASK_FORCES.get(side, 5))


## Le Task Force di questa parte davvero in gioco. Una senza navi non occupa
## una casella: e' una pedina che aspetta nella scatola.
static func in_play(state: GameState, side: int) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	for tf in state.forces_of(side):
		if not tf.ships.is_empty():
			out.append(tf)
	return out


static func free_slots(state: GameState, side: int) -> int:
	return maxi(0, max_task_forces(side) - in_play(state, side).size())


# ------------------------------------------------------------------ dividere --

## Perche' questa Task Force non puo' dividersi. Stringa vuota = puo'.
static func split_refusal(state: GameState, tf: TaskForce) -> String:
	if tf == null:
		return "nessuna Task Force designata"
	if not tf.trajectory.is_station():
		return "solo una Stazione Task Force puo' dividersi, non una Traiettoria"
	if tf.ships.size() < 2:
		return "servono almeno due navi per dividere"
	if free_slots(state, tf.side) <= 0:
		return "tutte le Task Force sono gia' in gioco"
	return ""


## Divide `tf` spostando `moving` in una Task Force nuova, nello stesso esagono.
##
## `contact_to_new` e `evasive_to_new` decidono dove vanno i segnalini: la
## divisione NON ne genera di nuovi, quindi il giocatore deve scegliere a quale
## delle due Task Force restano.
##
## Ritorna { ok, error, new_tf, log }.
static func split(state: GameState, tf: TaskForce, moving: Array[Ship],
		contact_to_new: bool = false,
		evasive_to_new: bool = false) -> Dictionary:
	var out := {"ok": false, "error": "", "new_tf": null,
		"log": [] as Array[String]}
	var why := split_refusal(state, tf)
	if why != "":
		out["error"] = why
		return out
	if moving.is_empty() or moving.size() >= tf.ships.size():
		out["error"] = "la divisione deve lasciare almeno una nave in ciascuna Task Force"
		return out
	for s_v: Variant in moving:
		if not tf.ships.has(s_v):
			out["error"] = "una delle navi indicate non e' in questa Task Force"
			return out

	var nt := TaskForce.new(0, tf.side)
	nt.color = tf.color
	nt.slot = _next_free_slot(state, tf.side)
	nt.name = "%s %s-%d" % ["KM" if tf.side == TaskForce.Side.KRIEGSMARINE
		else "RN", tf.color, nt.slot]
	nt.trajectory = Trajectory.new()
	nt.trajectory.become_station(tf.trajectory.station_hex)

	var names: Array[String] = []
	for s_v2: Variant in moving:
		var s: Ship = s_v2
		tf.ships.erase(s)
		nt.ships.append(s)
		names.append(s.name)
	tf.recompute_speed()
	nt.recompute_speed()

	# i segnalini si spostano, non si moltiplicano
	if contact_to_new and tf.trajectory.station_contact:
		tf.trajectory.station_contact = false
		nt.trajectory.station_contact = true
	if evasive_to_new and tf.evasive:
		tf.evasive = false
		nt.evasive = true

	state.add_task_force(nt)
	out["ok"] = true
	out["new_tf"] = nt
	out["log"] = ["%s si divide: %s passano a %s."
		% [tf.display_name(), ", ".join(names), nt.display_name()]] as Array[String]
	return out


static func _next_free_slot(state: GameState, side: int) -> int:
	var used: Array[int] = []
	for tf in state.forces_of(side):
		used.append(tf.slot)
	var i := 0
	while used.has(i):
		i += 1
	return i


# --------------------------------------------------------------------- unire --

## Perche' queste due Task Force non possono unirsi. Stringa vuota = possono.
static func merge_refusal(a: TaskForce, b: TaskForce) -> String:
	if a == null or b == null or a == b:
		return "servono due Task Force distinte"
	if a.side != b.side:
		return "non si possono unire Task Force di parti diverse"
	if not a.trajectory.is_station() or not b.trajectory.is_station():
		return "si uniscono solo due Stazioni, non le Traiettorie"
	if a.trajectory.station_hex != b.trajectory.station_hex:
		return "le due Stazioni devono stare nello stesso esagono"
	return ""


## Unisce `other` dentro `keep`. `other` resta in gioco come pedina vuota,
## pronta a essere riusata da una Divisione o da un Rinforzo riuscito.
static func merge(keep: TaskForce, other: TaskForce) -> Dictionary:
	var out := {"ok": false, "error": "", "log": [] as Array[String]}
	var why := merge_refusal(keep, other)
	if why != "":
		out["error"] = why
		return out
	var moved := other.ships.size()
	for s_v: Variant in other.ships:
		keep.ships.append(s_v as Ship)
	other.ships.clear()
	# Contatto: se ce l'ha una delle due, ce l'ha quella che resta; se ce
	# l'hanno entrambe se ne tiene uno solo. Idem per le Manovre Evasive: una
	# Task Force non puo' averne piu' di uno.
	if other.trajectory.station_contact:
		keep.trajectory.station_contact = true
	if other.evasive:
		keep.evasive = true
	other.evasive = false
	other.trajectory = Trajectory.new()
	keep.recompute_speed()
	out["ok"] = true
	out["log"] = ["%s assorbe %s (%d navi)."
		% [keep.display_name(), other.display_name(), moved]] as Array[String]
	return out


# ----------------------------------------------------------------- rinforzi --

## Perche' non si puo' tentare questo Rinforzo. Stringa vuota = si puo'.
##
## Serve una Stazione Task Force nel porto del Gruppo, oppure una Task Force
## libera da mettere in campo. Senza nessuna delle due, il tentativo e'
## proibito: le navi non avrebbero dove materializzarsi.
static func reinforce_refusal(state: GameState, side: int, port_hex: Vector2i,
		ships: Array) -> String:
	if ships.is_empty():
		return "il Gruppo di Rinforzi e' vuoto"
	if _station_in_port(state, side, port_hex) != null:
		return ""
	if free_slots(state, side) <= 0:
		return ("nessuna Stazione Task Force nel porto e nessuna Task Force "
			+ "libera: il tentativo di Rinforzo e' proibito")
	return ""


static func _station_in_port(state: GameState, side: int,
		port_hex: Vector2i) -> TaskForce:
	for tf in in_play(state, side):
		if tf.trajectory.is_station() and tf.trajectory.station_hex == port_hex:
			return tf
	return null


## Tentativo di Rinforzo: 2d6, 7 o piu' e le navi entrano in gioco.
##
## Il fallimento non e' gratis (RB p.37): una Task Force effettua lo Scorrere
## del Tempo e l'Iniziativa passa subito. Qui si segnala con `failed` e
## `initiative_passes`; chi chiama esegue lo Scorrere del Tempo, perche' quale
## Traiettoria accorciare e' una scelta del giocatore.
##
## Ritorna { ok, error, roll, success, tf, initiative_passes, log }.
static func attempt_reinforcement(state: GameState, side: int,
		port_hex: Vector2i, ships: Array, group_name: String = "") -> Dictionary:
	var out := {"ok": false, "error": "", "roll": 0, "success": false,
		"tf": null, "initiative_passes": false, "log": [] as Array[String]}
	var why := reinforce_refusal(state, side, port_hex, ships)
	if why != "":
		out["error"] = why
		return out

	var roll := state.rng.d6x2("tentativo di Rinforzo %s" % group_name)
	out["ok"] = true
	out["roll"] = roll
	var lines: Array[String] = []
	if roll < REINFORCE_TARGET:
		out["initiative_passes"] = true
		lines.append("Rinforzi %s: 2d6 = %d, meno di %d. Tentativo fallito: "
			% [group_name, roll, REINFORCE_TARGET]
			+ "una Task Force effettua lo Scorrere del Tempo e l'Iniziativa passa.")
		out["log"] = lines
		return out

	var tf := _station_in_port(state, side, port_hex)
	var created := false
	if tf == null:
		tf = TaskForce.new(0, side)
		tf.color = "GE" if side == TaskForce.Side.KRIEGSMARINE else "Brown"
		tf.slot = _next_free_slot(state, side)
		tf.name = "%s Rinforzi %s" % ["KM" if side == TaskForce.Side.KRIEGSMARINE
			else "RN", group_name]
		tf.trajectory = Trajectory.new()
		tf.trajectory.become_station(port_hex)
		state.add_task_force(tf)
		created = true

	var names: Array[String] = []
	for n_v: Variant in ships:
		var nm := String(n_v)
		var sh := ShipRoster.shared().make(nm)
		tf.ships.append(sh if sh != null else Ship.new(nm))
		names.append(nm)
	tf.recompute_speed()

	out["success"] = true
	out["tf"] = tf
	lines.append("Rinforzi %s: 2d6 = %d, riuscito. %s entrano in gioco%s."
		% [group_name, roll, ", ".join(names),
			" in una nuova Task Force" if created else
			" con %s" % tf.display_name()])
	out["log"] = lines
	return out
