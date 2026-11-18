class_name PortBox
extends RefCounted

## Caselle Porto (RB p.8).
##
## Una Stazione in un esagono di porto AMICO puo' trasferirsi nella Casella
## Porto, e tornare nell'esagono: lo fa il giocatore Attivo, senza Azione e
## senza costo. Nella Casella la Task Force e' "sicura":
##
##   - non puo' essere attaccata da Attacco Aereo, Ingaggiare o Attacco
##     Furtivo;
##   - non puo' essere designata per Coordinamento o Supporto Aereo;
##   - non puo' essere la TF Attiva di Attacco Aereo, Ingaggiare o Ricerca
##     Navale.
##
## E non causa Informazioni a chi passa nell'esagono: quello lo faceva gia'
## `GameState.triggers_info`. Il resto NON c'era: `station_port` era un campo
## che si scriveva e quasi nessuno leggeva, quindi una Home Fleet ferma nella
## Casella di Scapa Flow si poteva Ingaggiare.
##
## Un segmento di Traiettoria non sta mai in una Casella Porto (RB p.15): la
## Stazione esce dalla Casella quando diventa Traiettoria, e lo fa
## `Trajectory.extend`.

const SAFE_FROM := ["AIR_STRIKE", "ENGAGE", "STEALTH_ATTACK"]
const NOT_ACTIVE_FOR := ["AIR_STRIKE", "ENGAGE", "NAVAL_SEARCH"]


static func is_in_box(tf: TaskForce) -> bool:
	return tf != null and tf.trajectory.is_station() \
		and tf.trajectory.station_port != ""


## In quale Casella Porto puo' entrare questa Stazione, o "" se in nessuna.
##
## LACUNA DICHIARATA sulle mappe inserto: li' i porti fuori mappa (Murmansk,
## Stretto di Danimarca) "non sono collegati a Caselle Porto" (RB p.9), e il
## fascicolo solitario toglie dal gioco le Caselle dei porti norvegesi negli
## scenari N (p.16). Su un inserto si ammettono quindi solo i porti stampati
## come tali e non norvegesi.
static func enterable_port(tf: TaskForce, graph: MapGraph,
		port_control: Dictionary) -> String:
	if tf == null or tf.completed or not tf.trajectory.is_station() \
			or is_in_box(tf):
		return ""
	var h := tf.trajectory.station_hex
	for pname_v: Variant in graph.ports_in(h):
		var pname := String(pname_v)
		var p: Dictionary = graph.ports.get(pname, {})
		if p.is_empty():
			continue
		if Completion.control_of(p, port_control) != VictoryTracker.side_name(tf.side):
			continue
		if graph.is_inset():
			if String(p.get("nation", "")) == "NO" \
					or not graph.off_map_box_hexes(pname).is_empty():
				continue
		return pname
	return ""


static func enter(tf: TaskForce, port_name: String) -> bool:
	if tf == null or port_name == "" or not tf.trajectory.is_station():
		return false
	tf.trajectory.station_port = port_name
	return true


static func leave(tf: TaskForce) -> bool:
	if not is_in_box(tf):
		return false
	tf.trajectory.station_port = ""
	return true


## Perche' questa dichiarazione viola la sicurezza della Casella Porto.
## Stringa vuota = non la viola.
static func declaration_error(dec: ActionEngine.Declaration) -> String:
	if SAFE_FROM.has(dec.action_key) and is_in_box(dec.target):
		return ("%s e' nella Casella Porto di %s: li' non puo' essere attaccata "
			+ "(RB p.8)") % [dec.target.display_name(),
				dec.target.trajectory.station_port]
	if NOT_ACTIVE_FOR.has(dec.action_key) and is_in_box(dec.active):
		return ("%s e' nella Casella Porto di %s: deve prima uscirne per "
			+ "eseguire questa azione (RB p.8)") % [dec.active.display_name(),
				dec.active.trajectory.station_port]
	for tf in [dec.active_coordinating, dec.active_air_support,
			dec.target_coordinating, dec.target_air_support]:
		if is_in_box(tf):
			return ("%s e' in una Casella Porto e non puo' essere designata per "
				+ "Coordinamento o Supporto Aereo (RB p.8)") % tf.display_name()
	return ""
