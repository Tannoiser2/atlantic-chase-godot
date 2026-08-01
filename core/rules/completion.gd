class_name Completion
extends RefCounted

## Azione Completamento (RB p.29): portare le proprie navi in porto.
##
## La Task Force Attiva viene rimossa dal gioco e le sue navi entrano in porto.
## In uno scenario la rimozione e' definitiva; in una Operazione di campagna le
## navi possono tornare piu' avanti.
##
## Condizioni, dal regolamento:
##   - una sola Task Force puo' essere designata Attiva;
##   - puo' essere una Stazione o una Traiettoria, ma la Traiettoria non puo'
##     avere piu' di 6 segmenti;
##   - almeno un segmento deve stare in un esagono di porto amico, e non
##     importa quale segmento;
##   - una TF con anche un solo segnalino Informazioni non puo' Completare;
##   - il giocatore Inattivo tenta di Sottrarre l'Iniziativa: se ci riesce, il
##     Completamento FALLISCE.
##
## Il Completamento e' il punto in cui quasi tutte le tabelle dei Punti Vittoria
## pagano, quindi qui si passa dal VictoryTracker: quanto vale un Completamento
## dipende dal porto, e in due tabelle su nove anche dallo stato della nave.

const MAX_SEGMENTS := 6

## Chi controlla un porto quando lo scenario non dice altro. Le istruzioni di
## scenario ribaltano spesso questa tabella - dalla quarta Operazione in poi
## "tutti i porti francesi e norvegesi sono controllati dai tedeschi" - quindi
## e' solo un valore di partenza, non una regola.
const DEFAULT_CONTROL := {
	"GE": "KRIEGSMARINE",
	"UK": "ROYAL_NAVY",
	"US": "ROYAL_NAVY",
	"USSR": "ROYAL_NAVY",
	"FR": "ROYAL_NAVY",
	"NO": "ROYAL_NAVY",
	"NEUTRAL": "NONE",
}

## Nazione del porto -> nome del paese come lo scrivono le tabelle VP.
const COUNTRY_NAMES := {
	"FR": "France",
	"NO": "Norway",
	"GE": "Germany",
	"UK": "Britain",
	"US": "United States",
	"USSR": "USSR",
}


## Chi puo' Completare in questo porto: "KRIEGSMARINE", "ROYAL_NAVY", "BOTH"
## oppure "NONE". Il nome del porto ha la precedenza sulla sua nazione, perche'
## gli scenari chiudono singoli porti ("Murmansk e' chiuso", "in South America
## il Completamento non e' permesso") senza toccare gli altri dello stesso
## paese.
static func control_of(port: Dictionary, port_control: Dictionary) -> String:
	var pname := String(port.get("name", ""))
	if port_control.has(pname):
		return String(port_control[pname])
	var nation := String(port.get("nation", ""))
	if port_control.has(nation):
		return String(port_control[nation])
	return String(DEFAULT_CONTROL.get(nation, "NONE"))


static func _side_can(control: String, side: int) -> bool:
	if control == "BOTH":
		return true
	if control == "NONE":
		return false
	return control == VictoryTracker.side_name(side)


## Gli esagoni occupati dalla TF: la Stazione, oppure tutti i segmenti della
## Traiettoria. Il regolamento dice "non importa quale segmento".
static func occupied_hexes(tf: TaskForce) -> Array[Vector2i]:
	var t := tf.trajectory
	if t.is_station():
		return [t.station_hex] as Array[Vector2i]
	var out: Array[Vector2i] = []
	for h in t.hexes():
		if not out.has(h):
			out.append(h)
	return out


## I porti in cui questa TF potrebbe Completare adesso.
## Ritorna [{ "name", "nation", "country", "hex" }], vuoto se nessuno.
static func port_options(tf: TaskForce, graph: MapGraph,
		port_control: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Array[String] = []
	for h in occupied_hexes(tf):
		for pname_v: Variant in graph.ports_in(h):
			var pname := String(pname_v)
			if seen.has(pname):
				continue
			var p: Dictionary = graph.ports.get(pname, {})
			if p.is_empty() or not _side_can(control_of(p, port_control), tf.side):
				continue
			seen.append(pname)
			var nation := String(p.get("nation", ""))
			out.append({
				"name": pname,
				"nation": nation,
				"country": String(COUNTRY_NAMES.get(nation, nation)),
				"hex": h,
			})
	return out


## Perche' questa TF non puo' dichiarare il Completamento. Stringa vuota = puo'.
static func refusal(tf: TaskForce, graph: MapGraph,
		port_control: Dictionary = {}) -> String:
	if tf == null:
		return "nessuna Task Force designata"
	if tf.ships.is_empty():
		return "la Task Force non ha navi"
	if not tf.can_complete():
		return "una TF con segnalino Informazioni non puo' effettuare il Completamento"
	var t := tf.trajectory
	if not t.is_station() and t.segments.size() > MAX_SEGMENTS:
		return ("la Traiettoria ha %d segmenti: il Completamento ne ammette al "
			+ "massimo %d") % [t.segments.size(), MAX_SEGMENTS]
	if port_options(tf, graph, port_control).is_empty():
		return "nessun segmento in un esagono di porto amico"
	return ""


## Il Completamento riesce e la Task Force lascia il gioco.
##
## `port` e' uno degli elementi di port_options. `tracker` puo' essere null: uno
## scenario senza tabella VP completa lo stesso, semplicemente non segna punti.
##
## Ritorna { ok, error, ships, port, log }.
static func resolve(tf: TaskForce, port: Dictionary,
		tracker: VictoryTracker = null) -> Dictionary:
	var out := {"ok": false, "error": "", "ships": [], "port": port,
		"log": [] as Array[String]}
	if tf == null or port.is_empty():
		out["error"] = "Completamento senza Task Force o senza porto"
		return out

	var lines: Array[String] = []
	var pname := String(port.get("name", ""))
	var country := String(port.get("country", ""))
	lines.append("Completamento riuscito a %s: %s lascia il gioco."
		% [pname, tf.name])

	# I punti si assegnano PRIMA di svuotare la Task Force: dopo, le navi non
	# ci sono piu' e non c'e' piu' niente da valutare.
	if tracker != null and tracker.active():
		for s_v: Variant in tf.ships:
			var s: Ship = s_v
			if s.kind == Ship.Kind.CONVOY:
				lines.append_array(tracker.convoy_completed(pname,
					s.dispersed, tf.side))
				# la tabella puo' nominare il paese invece del porto
				if country != pname:
					lines.append_array(tracker.convoy_completed(country,
						s.dispersed, tf.side))
			else:
				lines.append_array(tracker.ship_completed(s, pname, tf.side))
				if country != pname:
					lines.append_array(tracker.ship_completed(s, country,
						tf.side))

	var names: Array[String] = []
	for s_v2: Variant in tf.ships:
		names.append((s_v2 as Ship).name)
	out["ships"] = names

	# rimozione: le navi vanno in porto, Stazione e segmenti tornano nella
	# casella del Display Task Force. In uno scenario e' definitiva; in una
	# Operazione di campagna le navi possono tornare piu' avanti, ed e' per
	# questo che il porto viene ricordato invece di essere dimenticato.
	tf.ships.clear()
	tf.trajectory = Trajectory.new()
	tf.trajectory.become_station(port.get("hex", Vector2i.ZERO))
	tf.completed = true
	tf.completed_port = pname

	out["ok"] = true
	out["log"] = lines
	return out
