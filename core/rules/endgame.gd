class_name Endgame
extends RefCounted

## Il finale di partita degli scenari: quando la caccia finisce e comincia il
## ritorno a casa.
##
## Quasi tutte le Operazioni chiudono con la stessa clausola, scritta a parole
## nel fascicolo:
##
##   "Quando tre Convogli hanno Completato, il tedesco puo' solamente
##    effettuare azioni di Attacco Aereo, Completamento, Passare e Traiettoria.
##    Comunque, se una TF tedesca puo' effettuare il Completamento, lo deve
##    fare."
##
## Da quel momento lo scenario cambia natura. Non e' una regola di contorno: e'
## quella che impedisce al tedesco di restare in mare a caccia dopo che
## l'obiettivo britannico e' stato raggiunto, e quella che lo obbliga a
## rientrare invece di aspettare in un porto senza entrarci.
##
## Le due clausole sono distinte e vanno tenute distinte: la prima VIETA delle
## azioni, la seconda ne IMPONE una. Un motore che confonde "non puoi" con
## "devi" sbaglia in tutti e due i sensi.

## Numero di Convogli arrivati oltre il quale scattano le restrizioni.
const DEFAULT_CONVOY_LIMIT := 3

## Le sole azioni che restano al giocatore limitato.
const ALLOWED_WHEN_RESTRICTED := ["AIR_STRIKE", "COMPLETION", "PASS",
	"TRAJECTORY"]


## Le restrizioni di fine partita sono attive?
static func restricted(state: GameState, rules: Dictionary) -> bool:
	if not bool(rules.get("completion_mandatory", false)):
		return false
	var limit := int(rules.get("convoy_limit", DEFAULT_CONVOY_LIMIT))
	return state.convoys_completed >= limit


## Il lato che subisce le restrizioni. Nelle Operazioni e' sempre il tedesco:
## sono i suoi Convogli affondati e le sue navi lontane da casa.
static func restricted_side(rules: Dictionary) -> int:
	return TaskForce.Side.ROYAL_NAVY \
		if String(rules.get("restricted_side", "KRIEGSMARINE")) == "ROYAL_NAVY" \
		else TaskForce.Side.KRIEGSMARINE


## Perche' questa azione non e' piu' dichiarabile. Stringa vuota = lo e'.
static func action_refusal(state: GameState, rules: Dictionary, side: int,
		action_key: String) -> String:
	if not restricted(state, rules):
		return ""
	if side != restricted_side(rules):
		return ""
	if ALLOWED_WHEN_RESTRICTED.has(action_key):
		return ""
	var limit := int(rules.get("convoy_limit", DEFAULT_CONVOY_LIMIT))
	return ("%d Convogli hanno gia' Completato: da qui in avanti restano solo "
		% limit + "Attacco Aereo, Completamento, Passare e Traiettoria")


## Le Task Force che ORA sono obbligate a Completare.
##
## La clausola dice "se puo', deve": non basta che le restrizioni siano
## attive, serve che il Completamento sia davvero eseguibile. Una Task Force in
## mezzo all'oceano non e' obbligata a niente.
static func must_complete(state: GameState, rules: Dictionary, graph: MapGraph,
		port_control: Dictionary = {}) -> Array[TaskForce]:
	var out: Array[TaskForce] = []
	if not restricted(state, rules):
		return out
	var side := restricted_side(rules)
	for tf in state.forces_of(side):
		if tf.ships.is_empty():
			continue
		if Completion.refusal(tf, graph, port_control) == "":
			out.append(tf)
	return out


## Riga da mostrare al giocatore quando le restrizioni sono attive.
static func notice(state: GameState, rules: Dictionary, graph: MapGraph,
		port_control: Dictionary = {}) -> String:
	if not restricted(state, rules):
		return ""
	var side := restricted_side(rules)
	var who := "Kriegsmarine" if side == TaskForce.Side.KRIEGSMARINE \
		else "Royal Navy"
	var parts: Array[String] = ["%d Convogli hanno Completato: %s puo' solo "
		% [state.convoys_completed, who]
		+ "Attacco Aereo, Completamento, Passare e Traiettoria."]
	var forced := must_complete(state, rules, graph, port_control)
	if not forced.is_empty():
		var names: Array[String] = []
		for tf in forced:
			names.append(tf.display_name())
		parts.append("E DEVE Completare con: %s." % ", ".join(names))
	return " ".join(parts)
