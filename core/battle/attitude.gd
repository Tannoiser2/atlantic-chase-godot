class_name Attitude
extends RefCounted

## Attitudine delle navi (Regole Avanzate di Battaglia, pp.3-4).
##
## Nelle regole avanzate ogni nave sulla Mappa di Battaglia opera in una di tre
## attitudini, indicate girando la pedina: la freccia rossa punta verso il
## nemico (Avvicinamento), lontano dal nemico (Corsa), o parallela a lui
## (Acquisizione).
##
## Non e' un dettaglio di colore: e' la scelta tattica centrale delle regole
## avanzate, e ogni attitudine e' un baratto.
##
##   ACQUISIZIONE  spara meglio (colonna sua sulla Tabella del Fuoco) oppure
##                 puo' DIVIDERE il fuoco su due bersagli - ma non silura, non
##                 manovra, non fugge. E' la nave che sta facendo una cosa
##                 sola: puntare.
##   AVVICINAMENTO spara normale, silura, avanza verso il nemico, e gli rende
##                 piu' difficile fuggire. Ma non puo' fuggire lei.
##   CORSA         spara normale, non silura, arretra, puo' fare Fumo, ed e'
##                 l'unica che puo' tentare la Fuga. Chi la attacca con i
##                 siluri ha -2.
##
## Il regolamento base non ha attitudini: e' come se tutte le navi fossero in
## Avvicinamento. Per questo il modello base resta valido quando le regole
## avanzate sono spente.

enum Kind { ACQUIRING, CLOSING, RUNNING }

const LABELS := ["Acquisizione", "Avvicinamento", "Corsa"]

## Come la scrive il fascicolo scenari sulle pedine, in inglese.
const FROM_MARKER := {
	"ACQUIRING": Kind.ACQUIRING,
	"CLOSING": Kind.CLOSING,
	"RUNNING": Kind.RUNNING,
}


static func label(kind: int) -> String:
	return LABELS[clampi(kind, 0, LABELS.size() - 1)]


static func from_marker(s: String) -> int:
	return int(FROM_MARKER.get(s.to_upper(), Kind.CLOSING))


# ---------------------------------------------------------------- piazzamento --

## Le attitudini legali per una nave al piazzamento.
##
## Le navi del giocatore Attivo DEVONO cominciare in Avvicinamento: e' l'unica
## non-scelta della regola, ed e' coerente - chi ha dichiarato l'Ingaggio si sta
## avvicinando per definizione. L'Inattivo sceglie fra Avvicinamento e Corsa,
## anche mescolando: alcune sue navi possono avvicinarsi mentre altre fuggono.
## Nessuno puo' cominciare in Acquisizione.
static func setup_options(is_active_side: bool) -> Array[int]:
	if is_active_side:
		return [Kind.CLOSING] as Array[int]
	return [Kind.CLOSING, Kind.RUNNING] as Array[int]


## L'attitudine delle navi del giocatore Inattivo la sceglie l'ATTIVO?
## Normalmente no, la sceglie l'Inattivo stesso. Ma dopo una SORPRESA si': il
## bersaglio e' stato colto alla sprovvista e non decide come reagire.
static func active_chooses_for_target(battle_kind: int) -> bool:
	return battle_kind == BattleState.Kind.SURPRISE


## Piazzamento di partenza: Attive in Avvicinamento, Bersaglio come indicato.
static func apply_setup(state: BattleState,
		target_attitudes: Dictionary = {}) -> void:
	for s in state.active_ships():
		s.attitude = Kind.CLOSING
	for s in state.target_ships():
		var want := int(target_attitudes.get(s, Kind.CLOSING))
		s.attitude = want if setup_options(false).has(want) else Kind.CLOSING


# ------------------------------------------------------- cosa puo' fare, e cosa no --

## Colonna della Tabella del Fuoco di Cannoni.
## "acquiring" solo se la nave e' integra: una nave Danneggiata o con un
## effetto speciale perde il beneficio (ma puo' ancora dividere il fuoco).
static func gunnery_column(ship: Ship) -> String:
	if ship.attitude == Kind.ACQUIRING and not ship.damaged \
			and not ship.has_special_effect():
		return "acquiring"
	return "closing"


## Puo' dividere il fuoco su due bersagli?
## Solo in Acquisizione, solo con valore dei cannoni 1 o piu', e i due bersagli
## devono stare allo stesso raggio. Dividendo si rinuncia alla colonna
## Acquisizione: sono due benefici alternativi, non cumulabili.
static func can_split_fire(ship: Ship, band: String) -> bool:
	if ship.attitude != Kind.ACQUIRING:
		return false
	var v: Variant = ship.gun_value(band)
	return v != null and float(v) >= 1.0


## Puo' attaccare con i siluri? Solo in Avvicinamento (RB Avanzate p.4).
static func can_torpedo(ship: Ship) -> bool:
	return ship.attitude == Kind.CLOSING


## Modificatore all'attacco con siluri CONTRO questa nave.
## Una nave in Corsa e' piu' difficile da silurare: sta scappando.
static func torpedo_target_modifier(target: Ship) -> int:
	return -2 if target.attitude == Kind.RUNNING else 0


## Puo' muoversi durante la Manovra?
static func can_maneuver(ship: Ship) -> bool:
	return ship.attitude != Kind.ACQUIRING


## In che direzione si muove: verso il nemico (+1) o via (-1). 0 = ferma.
## La nave si muove nella direzione della sua freccia, e non puo' scegliere:
## l'attitudine e' gia' la scelta.
static func maneuver_direction(ship: Ship) -> int:
	match ship.attitude:
		Kind.CLOSING:
			return 1
		Kind.RUNNING:
			return -1
	return 0


## Puo' produrre Fumo? Solo in Corsa - e comunque mai un Convoglio (RB p.11).
static func can_make_smoke(ship: Ship) -> bool:
	return ship.attitude == Kind.RUNNING and Maneuver.can_make_smoke(ship)


## Puo' Inseguire (nuova opzione della Manovra)? Solo in Avvicinamento, e solo
## dalla zona Vicina o Ravvicinata.
static func can_pursue(ship: Ship) -> bool:
	return ship.attitude == Kind.CLOSING and (
		ship.battle_zone == BattleState.Zone.NEAR
		or ship.battle_zone == BattleState.Zone.CLOSE)


## Puo' tentare la Fuga? Solo in Corsa.
## E' la regola che da' senso a tutte le altre: per andarsene bisogna aver
## deciso di andarsene, e averlo deciso PRIMA, nella fase dell'Attitudine.
static func can_break_away(ship: Ship) -> bool:
	return ship.attitude == Kind.RUNNING


## Modificatore al tentativo di Fuga di `side`, dovuto alle navi nemiche.
##
## -1 se un nemico e' in zona Vicina, e un altro -1 se quel nemico e' anche in
## Avvicinamento. Il secondo -1 vale solo se la nave che si avvicina sta in
## Vicina o Ravvicinata: una nave che si avvicina da Lontano non trattiene
## nessuno.
static func break_away_modifier(state: BattleState, escaping_active: bool) -> int:
	var enemies := state.target_ships() if escaping_active \
		else state.active_ships()
	var near := false
	var closing_near := false
	for e in enemies:
		if e.sunk:
			continue
		if e.battle_zone == BattleState.Zone.NEAR \
				or e.battle_zone == BattleState.Zone.CLOSE:
			near = true
			if e.attitude == Kind.CLOSING:
				closing_near = true
	var m := 0
	if near:
		m -= 1
	if closing_near:
		m -= 1
	return m


## Riassunto leggibile di cosa comporta questa attitudine, per l'interfaccia.
static func describe(kind: int) -> String:
	match kind:
		Kind.ACQUIRING:
			return ("spara meglio o divide il fuoco su due bersagli; "
				+ "niente siluri, niente manovra, niente fuga")
		Kind.RUNNING:
			return ("arretra, puo' fare Fumo ed e' l'unica che puo' tentare "
				+ "la Fuga; non silura, e chi la silura ha -2")
	return ("avanza verso il nemico, silura, e rende piu' difficile la Fuga "
		+ "avversaria; non puo' fuggire")
